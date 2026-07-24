#define _GNU_SOURCE
#include "task_qualification_handoff_v2.h"

#include <limits.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PF_TQ_HANDOFF_VERSION_V2 "1.0.0"
#define PF_TQ_HANDOFF_ID_PREFIX_V2 \
    "task-qualification-protected-handoff-"
#define PF_TQ_HANDOFF_STATEMENT_DOMAIN_V2 \
    "pf.taskqual.protected-handoff-statement.v1"
#define PF_TQ_HANDOFF_SIGNATURE_DOMAIN_V2 \
    "pf.taskqual.protected-handoff-signature.v1"
#define PF_TQ_HANDOFF_FULL_DOMAIN_V2 \
    "pf.taskqual.protected-handoff.v1"
#define PF_TQ_HANDOFF_CANDIDATE_DOMAIN_V2 \
    "pf.taskqual.candidate.v1"
#define PF_TQ_HANDOFF_POLICY_SCHEMA_V2 \
    "proof-forge.bootstrap-authority-policy.v1"
#define PF_TQ_HANDOFF_PIN_SCHEMA_V2 \
    "proof-forge.task-qualification-production-profile-pin.v1"
#define PF_TQ_HANDOFF_RAW_SCHEMA_V2 \
    "proof-forge.task-qualification-artifact-payload.v1"
#define PF_TQ_HANDOFF_DESCRIPTOR_VERSION_V2 "2.0.0"
#define PF_TQ_HANDOFF_DESCRIPTOR_ID_PREFIX_V2 \
    "task-qualification-store-service-"
#define PF_TQ_HANDOFF_SAFE_INTEGER_MAX_V2 UINT64_C(9007199254740991)

static int pf_tq_handoff_error(
    char *error,
    size_t error_size,
    const char *format,
    ...
) {
    if (error != NULL && error_size > 0U) {
        va_list arguments;
        va_start(arguments, format);
        (void)vsnprintf(error, error_size, format, arguments);
        va_end(arguments);
        error[error_size - 1U] = '\0';
    }
    return -1;
}

static void pf_tq_handoff_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_handoff_free_v2(pf_tq_handoff_v2 *handoff) {
    if (handoff == NULL) return;
    free(handoff->canonical_bytes);
    free(handoff->verified_signers);
    memset(handoff, 0, sizeof(*handoff));
}

static int pf_tq_handoff_digest(
    const char *domain,
    const unsigned char *bytes,
    size_t size,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    static const unsigned char zero = 0U;
    EVP_MD_CTX *context = NULL;
    unsigned int output_size = 0U;
    if (domain == NULL || bytes == NULL || output == NULL) {
        return pf_tq_handoff_error(error, error_size,
            "handoff digest arguments rejected");
    }
    context = EVP_MD_CTX_new();
    if (context == NULL || EVP_DigestInit_ex(context, EVP_sha256(), NULL) != 1 ||
            EVP_DigestUpdate(context, domain, strlen(domain)) != 1 ||
            EVP_DigestUpdate(context, &zero, 1U) != 1 ||
            EVP_DigestUpdate(context, bytes, size) != 1 ||
            EVP_DigestFinal_ex(context, output, &output_size) != 1 ||
            output_size != 32U) {
        EVP_MD_CTX_free(context);
        return pf_tq_handoff_error(error, error_size,
            "handoff SHA-256 failed");
    }
    EVP_MD_CTX_free(context);
    return 0;
}

static int pf_tq_handoff_verify_ed25519(
    const unsigned char public_key[32],
    const unsigned char signature[64],
    const unsigned char *message,
    size_t message_size
) {
    EVP_PKEY *key = NULL;
    EVP_MD_CTX *context = NULL;
    int verified = 0;
    key = EVP_PKEY_new_raw_public_key(
        EVP_PKEY_ED25519, NULL, public_key, 32U);
    context = EVP_MD_CTX_new();
    if (key != NULL && context != NULL &&
            EVP_DigestVerifyInit(context, NULL, NULL, NULL, key) == 1 &&
            EVP_DigestVerify(context, signature, 64U,
                message, message_size) == 1) {
        verified = 1;
    }
    EVP_MD_CTX_free(context);
    EVP_PKEY_free(key);
    return verified;
}

static const pf_tq_jcs_node_v2 *pf_tq_handoff_field(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field
) {
    return pf_tq_jcs_object_get_v2(document, object, field);
}

static int pf_tq_handoff_copy_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    if (pf_tq_jcs_copy_string_v2(document,
            pf_tq_handoff_field(document, object, field), output,
            output_size, error, error_size) != 0) {
        return pf_tq_handoff_error(error, error_size,
            "handoff string field rejected: %s", field);
    }
    return 0;
}

static int pf_tq_handoff_string_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    const char *expected,
    char *error,
    size_t error_size
) {
    if (!pf_tq_jcs_string_equal_v2(document,
            pf_tq_handoff_field(document, object, field), expected)) {
        return pf_tq_handoff_error(error, error_size,
            "handoff %s mismatch", field);
    }
    return 0;
}

static int pf_tq_handoff_git_object(const char *value) {
    size_t index;
    if (value == NULL || strlen(value) != 40U) return 0;
    for (index = 0U; index < 40U; ++index) {
        if (!((value[index] >= '0' && value[index] <= '9') ||
                (value[index] >= 'a' && value[index] <= 'f'))) return 0;
    }
    return 1;
}

static int pf_tq_handoff_task_id(const char *value) {
    size_t size = value == NULL ? 0U : strlen(value);
    size_t index = 5U;
    int group_has_character = 0;
    if (size <= 5U || size >= PF_TQ_HANDOFF_V2_TASK_ID_BYTES ||
            memcmp(value, "TASK-", 5U) != 0) return 0;
    while (index < size) {
        unsigned char character = (unsigned char)value[index];
        if ((character >= 'A' && character <= 'Z') ||
                (character >= '0' && character <= '9')) {
            group_has_character = 1;
        } else if (character == '-' && group_has_character && index + 1U < size) {
            group_has_character = 0;
        } else {
            return 0;
        }
        ++index;
    }
    return group_has_character;
}

static int pf_tq_handoff_operation(const char *value) {
    return value != NULL && (
        strcmp(value, "task-qualification") == 0 ||
        strcmp(value, "task-completion") == 0 ||
        strcmp(value, "d0-10-bootstrap-approval") == 0 ||
        strcmp(value, "d0-10-bootstrap-receipt") == 0);
}

static int pf_tq_handoff_leap_year(unsigned year) {
    return year % 4U == 0U && (year % 100U != 0U || year % 400U == 0U);
}

static int pf_tq_handoff_two_digits(const char *value, size_t offset) {
    if (value[offset] < '0' || value[offset] > '9' ||
            value[offset + 1U] < '0' || value[offset + 1U] > '9') return -1;
    return (value[offset] - '0') * 10 + (value[offset + 1U] - '0');
}

static int pf_tq_handoff_rfc3339(const char *value) {
    static const unsigned days[] = {
        0U, 31U, 28U, 31U, 30U, 31U, 30U,
        31U, 31U, 30U, 31U, 30U, 31U
    };
    unsigned year = 0U;
    int month;
    int day;
    int hour;
    int minute;
    int second;
    unsigned maximum_day;
    size_t index;
    if (value == NULL || strlen(value) != 20U || value[4] != '-' ||
            value[7] != '-' || value[10] != 'T' || value[13] != ':' ||
            value[16] != ':' || value[19] != 'Z') return 0;
    for (index = 0U; index < 4U; ++index) {
        if (value[index] < '0' || value[index] > '9') return 0;
        year = year * 10U + (unsigned)(value[index] - '0');
    }
    month = pf_tq_handoff_two_digits(value, 5U);
    day = pf_tq_handoff_two_digits(value, 8U);
    hour = pf_tq_handoff_two_digits(value, 11U);
    minute = pf_tq_handoff_two_digits(value, 14U);
    second = pf_tq_handoff_two_digits(value, 17U);
    if (year == 0U || month < 1 || month > 12 || day < 1 ||
            hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
            second < 0 || second > 59) return 0;
    maximum_day = days[(size_t)month];
    if (month == 2 && pf_tq_handoff_leap_year(year)) ++maximum_day;
    return (unsigned)day <= maximum_day;
}

static int pf_tq_handoff_fixed_string(
    const char *value,
    size_t capacity
) {
    return value != NULL && memchr(value, '\0', capacity) != NULL;
}

static int pf_tq_handoff_schema(const char *value) {
    size_t size = value == NULL ? 0U : strlen(value);
    size_t index = 0U;
    unsigned dots = 0U;
    if (size == 0U || size >= PF_TQ_WIRE_V2_SCHEMA_BYTES) return 0;
    while (index < size) {
        if (value[index] < 'a' || value[index] > 'z') return 0;
        ++index;
        while (index < size && value[index] != '.') {
            unsigned char character = (unsigned char)value[index];
            if ((character >= 'a' && character <= 'z') ||
                    (character >= '0' && character <= '9')) {
                ++index;
            } else if (character == '-' && index + 1U < size &&
                    ((value[index + 1U] >= 'a' && value[index + 1U] <= 'z') ||
                     (value[index + 1U] >= '0' && value[index + 1U] <= '9'))) {
                ++index;
            } else {
                return 0;
            }
        }
        if (index < size) {
            ++dots;
            ++index;
            if (index == size) return 0;
        }
    }
    return dots > 0U;
}

static int pf_tq_handoff_ref_shape(
    const pf_tq_wire_content_ref_v2 *reference
) {
    return reference != NULL &&
        pf_tq_handoff_fixed_string(reference->schema,
            sizeof(reference->schema)) &&
        pf_tq_handoff_fixed_string(reference->id, sizeof(reference->id)) &&
        pf_tq_handoff_fixed_string(reference->version,
            sizeof(reference->version)) &&
        pf_tq_handoff_schema(reference->schema) &&
        pf_tq_wire_profile_id_v2(reference->id) &&
        pf_tq_wire_semver_v2(reference->version);
}

static int pf_tq_handoff_identity_shape(
    const pf_tq_wire_verifier_identity_v2 *identity
) {
    return identity != NULL &&
        pf_tq_handoff_fixed_string(identity->id, sizeof(identity->id)) &&
        pf_tq_wire_safe_id_v2(identity->id) &&
        pf_tq_handoff_ref_shape(&identity->executable) &&
        pf_tq_handoff_ref_shape(&identity->closure) &&
        pf_tq_handoff_ref_shape(&identity->build_policy);
}

static int pf_tq_handoff_raw_identity(
    const pf_tq_wire_verifier_identity_v2 *identity
) {
    return identity != NULL &&
        strcmp(identity->executable.schema, PF_TQ_HANDOFF_RAW_SCHEMA_V2) == 0 &&
        strcmp(identity->closure.schema, PF_TQ_HANDOFF_RAW_SCHEMA_V2) == 0 &&
        strcmp(identity->build_policy.schema, PF_TQ_HANDOFF_RAW_SCHEMA_V2) == 0;
}

static int pf_tq_handoff_channels_valid(
    const pf_tq_handoff_channels_v2 *channels
) {
    int values[5];
    size_t index;
    size_t other;
    if (channels == NULL) return 0;
    values[0] = channels->authority_policy_fd;
    values[1] = channels->authority_store_fd;
    values[2] = channels->candidate_archive_fd;
    values[3] = channels->provenance_bundle_fd;
    values[4] = channels->trusted_clock_fd;
    for (index = 0U; index < 5U; ++index) {
        if (values[index] < 0) return 0;
        for (other = 0U; other < index; ++other) {
            if (values[index] == values[other]) return 0;
        }
    }
    return 1;
}

static int pf_tq_handoff_channels_equal(
    const pf_tq_handoff_channels_v2 *left,
    const pf_tq_handoff_channels_v2 *right
) {
    return left != NULL && right != NULL &&
        left->authority_policy_fd == right->authority_policy_fd &&
        left->authority_store_fd == right->authority_store_fd &&
        left->candidate_archive_fd == right->candidate_archive_fd &&
        left->provenance_bundle_fd == right->provenance_bundle_fd &&
        left->trusted_clock_fd == right->trusted_clock_fd;
}

static int pf_tq_handoff_expectation_validate(
    const pf_tq_handoff_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    char descriptor_id[PF_TQ_WIRE_V2_CONTENT_ID_BYTES];
    size_t index;
    size_t other;
    int rendered;
    if (expected == NULL ||
            !pf_tq_handoff_fixed_string(expected->task_id,
                PF_TQ_HANDOFF_V2_TASK_ID_BYTES) ||
            !pf_tq_handoff_task_id(expected->task_id) ||
            !pf_tq_handoff_fixed_string(expected->operation,
                PF_TQ_HANDOFF_V2_OPERATION_BYTES) ||
            !pf_tq_handoff_operation(expected->operation) ||
            !pf_tq_handoff_fixed_string(expected->run_id,
                PF_TQ_WIRE_V2_SAFE_ID_BYTES) ||
            !pf_tq_wire_safe_id_v2(expected->run_id) ||
            !pf_tq_handoff_fixed_string(expected->nonce,
                PF_TQ_WIRE_V2_SAFE_ID_BYTES) ||
            !pf_tq_wire_safe_id_v2(expected->nonce) ||
            !pf_tq_handoff_fixed_string(expected->candidate.commit,
                sizeof(expected->candidate.commit)) ||
            !pf_tq_handoff_fixed_string(expected->candidate.tree_object_id,
                sizeof(expected->candidate.tree_object_id)) ||
            !pf_tq_handoff_git_object(expected->candidate.commit) ||
            !pf_tq_handoff_git_object(expected->candidate.tree_object_id) ||
            !pf_tq_handoff_ref_shape(&expected->authority_policy) ||
            !pf_tq_handoff_ref_shape(&expected->production_profile_pin) ||
            !pf_tq_handoff_identity_shape(&expected->adapter) ||
            !pf_tq_handoff_identity_shape(&expected->snapshot_parser) ||
            !pf_tq_handoff_ref_shape(&expected->authority_store_service) ||
            !pf_tq_handoff_identity_shape(&expected->trusted_clock_service) ||
            expected->revocation_head_sequence >
                PF_TQ_HANDOFF_SAFE_INTEGER_MAX_V2 ||
            !pf_tq_handoff_fixed_string(expected->trusted_instant,
                PF_TQ_HANDOFF_V2_INSTANT_BYTES) ||
            !pf_tq_handoff_rfc3339(expected->trusted_instant) ||
            !pf_tq_handoff_channels_valid(&expected->channels) ||
            expected->principals == NULL || expected->principal_count < 3U ||
            expected->principal_count > PF_TQ_HANDOFF_V2_MAX_SIGNATURES) {
        return pf_tq_handoff_error(error, error_size,
            "handoff expectation shape rejected");
    }
    rendered = snprintf(descriptor_id, sizeof(descriptor_id), "%s%s",
        PF_TQ_HANDOFF_DESCRIPTOR_ID_PREFIX_V2, expected->run_id);
    if (rendered <= 0 || (size_t)rendered >= sizeof(descriptor_id) ||
            !pf_tq_wire_profile_id_v2(descriptor_id) ||
            strcmp(expected->authority_policy.schema,
                PF_TQ_HANDOFF_POLICY_SCHEMA_V2) != 0 ||
            strcmp(expected->production_profile_pin.schema,
                PF_TQ_HANDOFF_PIN_SCHEMA_V2) != 0 ||
            strcmp(expected->authority_store_service.schema,
                PF_TQ_DESCRIPTOR_V2_SCHEMA) != 0 ||
            strcmp(expected->authority_store_service.id, descriptor_id) != 0 ||
            strcmp(expected->authority_store_service.version,
                PF_TQ_HANDOFF_DESCRIPTOR_VERSION_V2) != 0 ||
            !pf_tq_handoff_raw_identity(&expected->adapter) ||
            !pf_tq_handoff_raw_identity(&expected->snapshot_parser) ||
            !pf_tq_handoff_raw_identity(&expected->trusted_clock_service)) {
        return pf_tq_handoff_error(error, error_size,
            "handoff expectation owner/run join rejected");
    }
    for (index = 0U; index < expected->principal_count; ++index) {
        const pf_tq_handoff_principal_v2 *principal =
            &expected->principals[index];
        if (!pf_tq_handoff_fixed_string(principal->principal_id,
                    PF_TQ_WIRE_V2_SAFE_ID_BYTES) ||
                !pf_tq_handoff_fixed_string(principal->key_id,
                    PF_TQ_WIRE_V2_SAFE_ID_BYTES) ||
                !pf_tq_wire_safe_id_v2(principal->principal_id) ||
                !pf_tq_wire_safe_id_v2(principal->key_id) ||
                principal->roles == 0U ||
                (principal->roles & ~PF_TQ_HANDOFF_ROLE_MASK_V2) != 0U ||
                (principal->current != 0 && principal->current != 1) ||
                (index > 0U && strcmp(expected->principals[index - 1U].key_id,
                    principal->key_id) >= 0)) {
            return pf_tq_handoff_error(error, error_size,
                "handoff principal registry rejected");
        }
        for (other = 0U; other < index; ++other) {
            if (memcmp(expected->principals[other].public_key,
                    principal->public_key, 32U) == 0) {
                return pf_tq_handoff_error(error, error_size,
                    "handoff principal public keys must be unique");
            }
        }
    }
    return 0;
}

static int pf_tq_handoff_parse_candidate(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_handoff_candidate_v2 *candidate,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "archiveSha256", "commit", "treeObjectId"
    };
    if (node == NULL || candidate == NULL || node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_handoff_error(error, error_size,
            "handoff candidate must be a closed object");
    }
    memset(candidate, 0, sizeof(*candidate));
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 3U,
            error, error_size) != 0 ||
            pf_tq_handoff_copy_string(document, node, "commit",
                candidate->commit, sizeof(candidate->commit),
                error, error_size) != 0 ||
            pf_tq_handoff_copy_string(document, node, "treeObjectId",
                candidate->tree_object_id, sizeof(candidate->tree_object_id),
                error, error_size) != 0 ||
            !pf_tq_handoff_git_object(candidate->commit) ||
            !pf_tq_handoff_git_object(candidate->tree_object_id) ||
            pf_tq_wire_parse_digest_v2(document,
                pf_tq_handoff_field(document, node, "archiveSha256"),
                candidate->archive_sha256, error, error_size) != 0 ||
            node->raw_end <= node->raw_start || node->raw_end > document->size ||
            pf_tq_handoff_digest(PF_TQ_HANDOFF_CANDIDATE_DOMAIN_V2,
                document->bytes + node->raw_start,
                node->raw_end - node->raw_start, candidate->digest,
                error, error_size) != 0) {
        return pf_tq_handoff_error(error, error_size,
            "handoff candidate rejected");
    }
    return 0;
}

static int pf_tq_handoff_parse_channels(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_handoff_channels_v2 *channels,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "authorityPolicyFd", "authorityStoreFd", "candidateArchiveFd",
        "provenanceBundleFd", "trustedClockFd"
    };
    int *outputs[5];
    size_t index;
    if (node == NULL || channels == NULL || node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_handoff_error(error, error_size,
            "handoff channels must be a closed object");
    }
    memset(channels, 0, sizeof(*channels));
    outputs[0] = &channels->authority_policy_fd;
    outputs[1] = &channels->authority_store_fd;
    outputs[2] = &channels->candidate_archive_fd;
    outputs[3] = &channels->provenance_bundle_fd;
    outputs[4] = &channels->trusted_clock_fd;
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 5U,
            error, error_size) != 0) return -1;
    for (index = 0U; index < 5U; ++index) {
        const pf_tq_jcs_node_v2 *value =
            pf_tq_handoff_field(document, node, fields[index]);
        if (value == NULL || value->type != PF_TQ_JCS_UINT ||
                value->uint_value > (uint64_t)INT_MAX) {
            return pf_tq_handoff_error(error, error_size,
                "handoff channel FD rejected: %s", fields[index]);
        }
        *outputs[index] = (int)value->uint_value;
    }
    if (!pf_tq_handoff_channels_valid(channels)) {
        return pf_tq_handoff_error(error, error_size,
            "handoff channel FDs must be pairwise distinct");
    }
    return 0;
}

static int pf_tq_handoff_parse_revocation(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    uint64_t *sequence,
    unsigned char digest[32],
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"headDigest", "headSequence"};
    const pf_tq_jcs_node_v2 *sequence_node;
    if (node == NULL || sequence == NULL || digest == NULL ||
            node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_handoff_error(error, error_size,
            "handoff revocationHead must be a closed object");
    }
    sequence_node = pf_tq_handoff_field(document, node, "headSequence");
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 2U,
            error, error_size) != 0 || sequence_node == NULL ||
            sequence_node->type != PF_TQ_JCS_UINT ||
            sequence_node->uint_value > PF_TQ_HANDOFF_SAFE_INTEGER_MAX_V2 ||
            pf_tq_wire_parse_digest_v2(document,
                pf_tq_handoff_field(document, node, "headDigest"), digest,
                error, error_size) != 0) {
        return pf_tq_handoff_error(error, error_size,
            "handoff revocationHead rejected");
    }
    *sequence = sequence_node->uint_value;
    return 0;
}

static int pf_tq_handoff_candidate_equal(
    const pf_tq_handoff_candidate_v2 *left,
    const pf_tq_handoff_candidate_v2 *right
) {
    return left != NULL && right != NULL &&
        strcmp(left->commit, right->commit) == 0 &&
        strcmp(left->tree_object_id, right->tree_object_id) == 0 &&
        memcmp(left->archive_sha256, right->archive_sha256, 32U) == 0;
}

static int pf_tq_handoff_projection_matches(
    const pf_tq_handoff_v2 *handoff,
    const pf_tq_handoff_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    if (strcmp(handoff->task_id, expected->task_id) != 0 ||
            strcmp(handoff->operation, expected->operation) != 0 ||
            strcmp(handoff->run_id, expected->run_id) != 0 ||
            strcmp(handoff->nonce, expected->nonce) != 0 ||
            !pf_tq_handoff_candidate_equal(&handoff->candidate,
                &expected->candidate) ||
            !pf_tq_wire_content_ref_equal_v2(&handoff->authority_policy,
                &expected->authority_policy) ||
            !pf_tq_wire_content_ref_equal_v2(&handoff->production_profile_pin,
                &expected->production_profile_pin) ||
            memcmp(handoff->gate_set_digest,
                expected->gate_set_digest, 32U) != 0 ||
            !pf_tq_wire_verifier_identity_equal_v2(&handoff->adapter,
                &expected->adapter) ||
            !pf_tq_wire_verifier_identity_equal_v2(&handoff->snapshot_parser,
                &expected->snapshot_parser) ||
            !pf_tq_wire_content_ref_equal_v2(&handoff->authority_store_service,
                &expected->authority_store_service) ||
            !pf_tq_wire_verifier_identity_equal_v2(
                &handoff->trusted_clock_service,
                &expected->trusted_clock_service) ||
            handoff->revocation_head_sequence !=
                expected->revocation_head_sequence ||
            memcmp(handoff->revocation_head_digest,
                expected->revocation_head_digest, 32U) != 0 ||
            strcmp(handoff->trusted_instant, expected->trusted_instant) != 0 ||
            !pf_tq_handoff_channels_equal(&handoff->channels,
                &expected->channels)) {
        return pf_tq_handoff_error(error, error_size,
            "handoff candidate-external expectation mismatch");
    }
    return 0;
}

static int pf_tq_handoff_unsigned_bytes(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *root,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "adapter", "authorityPolicy", "authorityStoreService", "candidate",
        "channels", "gateSetDigest", "id", "nonce", "operation",
        "productionProfilePin", "revocationHead", "runId", "schema",
        "snapshotParser", "taskId", "trustedClockService", "trustedInstant",
        "version"
    };
    pf_tq_jcs_field_v2 encoded[18];
    size_t index;
    for (index = 0U; index < 18U; ++index) {
        const pf_tq_jcs_node_v2 *node =
            pf_tq_handoff_field(document, root, fields[index]);
        if (node == NULL || node->raw_end <= node->raw_start ||
                node->raw_end > document->size) {
            return pf_tq_handoff_error(error, error_size,
                "handoff unsigned field range rejected");
        }
        encoded[index].key = fields[index];
        encoded[index].value = document->bytes + node->raw_start;
        encoded[index].value_size = node->raw_end - node->raw_start;
    }
    return pf_tq_jcs_encode_object_v2(encoded, 18U, output, output_size,
        written, error, error_size);
}

static const pf_tq_handoff_principal_v2 *pf_tq_handoff_find_principal(
    const pf_tq_handoff_expectation_v2 *expected,
    const char *key_id
) {
    size_t low = 0U;
    size_t high = expected->principal_count;
    while (low < high) {
        size_t middle = low + (high - low) / 2U;
        int comparison = strcmp(expected->principals[middle].key_id, key_id);
        if (comparison < 0) low = middle + 1U;
        else if (comparison > 0) high = middle;
        else return &expected->principals[middle];
    }
    return NULL;
}

static int pf_tq_handoff_parse_signatures(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *signatures,
    const pf_tq_handoff_expectation_v2 *expected,
    pf_tq_handoff_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"algorithm", "keyId", "signature"};
    size_t index;
    if (signatures == NULL || signatures->type != PF_TQ_JCS_ARRAY ||
            signatures->child_count < 3U ||
            signatures->child_count > expected->principal_count ||
            signatures->child_count > PF_TQ_HANDOFF_V2_MAX_SIGNATURES) {
        return pf_tq_handoff_error(error, error_size,
            "handoff signatures count must be 3..current-principal-count");
    }
    result->verified_signers = calloc(signatures->child_count,
        sizeof(*result->verified_signers));
    if (result->verified_signers == NULL) {
        return pf_tq_handoff_error(error, error_size,
            "handoff signer allocation failed");
    }
    result->signature_count = signatures->child_count;
    for (index = 0U; index < signatures->child_count; ++index) {
        const pf_tq_jcs_node_v2 *signature =
            pf_tq_jcs_array_at_v2(document, signatures, index);
        pf_tq_handoff_verified_signer_v2 *verified =
            &result->verified_signers[index];
        const pf_tq_handoff_principal_v2 *principal;
        size_t written = 0U;
        if (signature == NULL || signature->type != PF_TQ_JCS_OBJECT ||
                pf_tq_jcs_object_exact_v2(document, signature, fields, 3U,
                    error, error_size) != 0 ||
                pf_tq_handoff_copy_string(document, signature, "keyId",
                    verified->key_id, sizeof(verified->key_id),
                    error, error_size) != 0 ||
                !pf_tq_wire_safe_id_v2(verified->key_id) ||
                (index > 0U && strcmp(
                    result->verified_signers[index - 1U].key_id,
                    verified->key_id) >= 0) ||
                pf_tq_handoff_string_exact(document, signature, "algorithm",
                    "ed25519", error, error_size) != 0 ||
                pf_tq_jcs_decode_hex_v2(document,
                    pf_tq_handoff_field(document, signature, "signature"),
                    verified->signature, 64U, 64U, &written,
                    error, error_size) != 0 || written != 64U) {
            return pf_tq_handoff_error(error, error_size,
                "handoff signature syntax/order rejected");
        }
        principal = pf_tq_handoff_find_principal(expected, verified->key_id);
        if (principal == NULL || !principal->current) {
            return pf_tq_handoff_error(error, error_size,
                "handoff signer is unknown or non-current");
        }
        (void)snprintf(verified->principal_id,
            sizeof(verified->principal_id), "%s", principal->principal_id);
        memcpy(verified->public_key, principal->public_key, 32U);
        verified->roles = principal->roles;
    }
    return 0;
}

static int pf_tq_handoff_verify_signatures(
    pf_tq_handoff_v2 *result,
    char *error,
    size_t error_size
) {
    unsigned char message[
        sizeof(PF_TQ_HANDOFF_SIGNATURE_DOMAIN_V2) - 1U + 1U + 32U];
    const size_t domain_size =
        sizeof(PF_TQ_HANDOFF_SIGNATURE_DOMAIN_V2) - 1U;
    uint32_t covered_roles = 0U;
    size_t distinct_principals = 0U;
    size_t index;
    memcpy(message, PF_TQ_HANDOFF_SIGNATURE_DOMAIN_V2, domain_size);
    message[domain_size] = 0U;
    memcpy(message + domain_size + 1U, result->statement_digest, 32U);
    for (index = 0U; index < result->signature_count; ++index) {
        size_t other;
        int principal_seen = 0;
        pf_tq_handoff_verified_signer_v2 *signer =
            &result->verified_signers[index];
        if (!pf_tq_handoff_verify_ed25519(signer->public_key,
                signer->signature, message, sizeof(message))) {
            return pf_tq_handoff_error(error, error_size,
                "handoff Ed25519 signature rejected: %s", signer->key_id);
        }
        covered_roles |= signer->roles;
        for (other = 0U; other < index; ++other) {
            if (strcmp(result->verified_signers[other].principal_id,
                    signer->principal_id) == 0) {
                principal_seen = 1;
                break;
            }
        }
        if (!principal_seen) ++distinct_principals;
    }
    if (distinct_principals < 3U ||
            (covered_roles & PF_TQ_HANDOFF_REQUIRED_ROLE_MASK_V2) !=
                PF_TQ_HANDOFF_REQUIRED_ROLE_MASK_V2) {
        return pf_tq_handoff_error(error, error_size,
            "handoff signatures do not satisfy distinct A+Q+S rule");
    }
    return 0;
}

int pf_tq_handoff_parse_verify_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_handoff_expectation_v2 *expected,
    pf_tq_handoff_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "adapter", "authorityPolicy", "authorityStoreService", "candidate",
        "channels", "gateSetDigest", "id", "nonce", "operation",
        "productionProfilePin", "revocationHead", "runId", "schema",
        "signatures", "snapshotParser", "taskId", "trustedClockService",
        "trustedInstant", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root = NULL;
    unsigned char *unsigned_bytes = NULL;
    size_t unsigned_size = 0U;
    char expected_id[PF_TQ_HANDOFF_V2_ID_BYTES];
    char expected_descriptor_id[PF_TQ_WIRE_V2_CONTENT_ID_BYTES];
    int rendered;
    int document_initialized = 0;
    int status = -1;
    pf_tq_handoff_clear_error(error, error_size);
    if (bytes == NULL || size == 0U || size > PF_TQ_HANDOFF_V2_MAX_BYTES ||
            expected == NULL || result == NULL) {
        return pf_tq_handoff_error(error, error_size,
            "handoff input/expectation/result rejected");
    }
    memset(result, 0, sizeof(*result));
    if (pf_tq_handoff_expectation_validate(expected,
            error, error_size) != 0) return -1;
    if (pf_tq_jcs_parse_v2(bytes, size, &document,
            error, error_size) != 0) return -1;
    document_initialized = 1;
    root = pf_tq_jcs_root_v2(&document);
    if (root == NULL || root->type != PF_TQ_JCS_OBJECT) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff root must be a closed object");
        goto cleanup;
    }
    if (pf_tq_jcs_object_exact_v2(&document, root, fields, 19U,
            error, error_size) != 0 ||
            pf_tq_handoff_digest(PF_TQ_HANDOFF_FULL_DOMAIN_V2,
                bytes, size, result->full_digest,
                error, error_size) != 0 ||
            pf_tq_handoff_string_exact(&document, root, "schema",
                PF_TQ_HANDOFF_V2_SCHEMA, error, error_size) != 0 ||
            pf_tq_handoff_string_exact(&document, root, "version",
                PF_TQ_HANDOFF_VERSION_V2, error, error_size) != 0 ||
            pf_tq_handoff_copy_string(&document, root, "id", result->id,
                sizeof(result->id), error, error_size) != 0 ||
            pf_tq_handoff_copy_string(&document, root, "taskId", result->task_id,
                sizeof(result->task_id), error, error_size) != 0 ||
            pf_tq_handoff_copy_string(&document, root, "operation",
                result->operation, sizeof(result->operation),
                error, error_size) != 0 ||
            pf_tq_handoff_copy_string(&document, root, "runId", result->run_id,
                sizeof(result->run_id), error, error_size) != 0 ||
            pf_tq_handoff_copy_string(&document, root, "nonce", result->nonce,
                sizeof(result->nonce), error, error_size) != 0 ||
            !pf_tq_handoff_task_id(result->task_id) ||
            !pf_tq_handoff_operation(result->operation) ||
            !pf_tq_wire_safe_id_v2(result->run_id) ||
            !pf_tq_wire_safe_id_v2(result->nonce)) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff root scalar grammar rejected");
        goto cleanup;
    }
    rendered = snprintf(expected_id, sizeof(expected_id), "%s%s",
        PF_TQ_HANDOFF_ID_PREFIX_V2, result->run_id);
    if (rendered <= 0 || (size_t)rendered >= sizeof(expected_id) ||
            !pf_tq_wire_safe_id_v2(expected_id) ||
            strcmp(result->id, expected_id) != 0) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff id/runId join rejected");
        goto cleanup;
    }
    if (pf_tq_handoff_parse_candidate(&document,
            pf_tq_handoff_field(&document, root, "candidate"),
            &result->candidate, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(&document,
                pf_tq_handoff_field(&document, root, "authorityPolicy"),
                &result->authority_policy, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(&document,
                pf_tq_handoff_field(&document, root, "productionProfilePin"),
                &result->production_profile_pin, error, error_size) != 0 ||
            pf_tq_wire_parse_digest_v2(&document,
                pf_tq_handoff_field(&document, root, "gateSetDigest"),
                result->gate_set_digest, error, error_size) != 0 ||
            pf_tq_wire_parse_verifier_identity_v2(&document,
                pf_tq_handoff_field(&document, root, "adapter"),
                &result->adapter, error, error_size) != 0 ||
            pf_tq_wire_parse_verifier_identity_v2(&document,
                pf_tq_handoff_field(&document, root, "snapshotParser"),
                &result->snapshot_parser, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(&document,
                pf_tq_handoff_field(&document, root, "authorityStoreService"),
                &result->authority_store_service, error, error_size) != 0 ||
            pf_tq_wire_parse_verifier_identity_v2(&document,
                pf_tq_handoff_field(&document, root, "trustedClockService"),
                &result->trusted_clock_service, error, error_size) != 0 ||
            pf_tq_handoff_parse_revocation(&document,
                pf_tq_handoff_field(&document, root, "revocationHead"),
                &result->revocation_head_sequence,
                result->revocation_head_digest, error, error_size) != 0 ||
            pf_tq_handoff_copy_string(&document, root, "trustedInstant",
                result->trusted_instant, sizeof(result->trusted_instant),
                error, error_size) != 0 ||
            !pf_tq_handoff_rfc3339(result->trusted_instant) ||
            pf_tq_handoff_parse_channels(&document,
                pf_tq_handoff_field(&document, root, "channels"),
                &result->channels, error, error_size) != 0) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff typed fields rejected");
        goto cleanup;
    }
    rendered = snprintf(expected_descriptor_id, sizeof(expected_descriptor_id),
        "%s%s", PF_TQ_HANDOFF_DESCRIPTOR_ID_PREFIX_V2, result->run_id);
    if (rendered <= 0 || (size_t)rendered >= sizeof(expected_descriptor_id) ||
            strcmp(result->authority_policy.schema,
                PF_TQ_HANDOFF_POLICY_SCHEMA_V2) != 0 ||
            strcmp(result->production_profile_pin.schema,
                PF_TQ_HANDOFF_PIN_SCHEMA_V2) != 0 ||
            strcmp(result->authority_store_service.schema,
                PF_TQ_DESCRIPTOR_V2_SCHEMA) != 0 ||
            strcmp(result->authority_store_service.version,
                PF_TQ_HANDOFF_DESCRIPTOR_VERSION_V2) != 0 ||
            strcmp(result->authority_store_service.id,
                expected_descriptor_id) != 0 ||
            !pf_tq_handoff_raw_identity(&result->adapter) ||
            !pf_tq_handoff_raw_identity(&result->snapshot_parser) ||
            !pf_tq_handoff_raw_identity(&result->trusted_clock_service)) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff closed owner dispatch rejected");
        goto cleanup;
    }
    if (pf_tq_handoff_projection_matches(result, expected,
            error, error_size) != 0) goto cleanup;
    unsigned_bytes = malloc(size);
    if (unsigned_bytes == NULL) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff unsigned-byte allocation failed");
        goto cleanup;
    }
    if (pf_tq_handoff_unsigned_bytes(&document, root, unsigned_bytes, size,
            &unsigned_size, error, error_size) != 0 ||
            pf_tq_handoff_digest(PF_TQ_HANDOFF_STATEMENT_DOMAIN_V2,
                unsigned_bytes, unsigned_size, result->statement_digest,
                error, error_size) != 0 ||
            pf_tq_handoff_parse_signatures(&document,
                pf_tq_handoff_field(&document, root, "signatures"), expected,
                result, error, error_size) != 0 ||
            pf_tq_handoff_verify_signatures(result,
                error, error_size) != 0) goto cleanup;
    result->canonical_bytes = malloc(size);
    if (result->canonical_bytes == NULL) {
        (void)pf_tq_handoff_error(error, error_size,
            "handoff canonical-byte allocation failed");
        goto cleanup;
    }
    memcpy(result->canonical_bytes, bytes, size);
    result->canonical_size = size;
    status = 0;

cleanup:
    free(unsigned_bytes);
    if (document_initialized) pf_tq_jcs_free_v2(&document);
    if (status != 0) pf_tq_handoff_free_v2(result);
    return status;
}

int pf_tq_handoff_join_descriptor_v2(
    const pf_tq_handoff_v2 *handoff,
    const pf_tq_descriptor_v2 *descriptor,
    const pf_tq_handoff_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    pf_tq_wire_content_ref_v2 descriptor_ref;
    uint32_t covered_roles = 0U;
    char principal_ids[3][PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    size_t index;
    pf_tq_handoff_clear_error(error, error_size);
    if (handoff == NULL || descriptor == NULL || expected == NULL ||
            handoff->canonical_bytes == NULL || handoff->canonical_size == 0U ||
            handoff->verified_signers == NULL || handoff->signature_count < 3U ||
            !pf_tq_handoff_fixed_string(descriptor->id,
                sizeof(descriptor->id)) ||
            pf_tq_handoff_expectation_validate(expected,
                error, error_size) != 0 ||
            pf_tq_handoff_projection_matches(handoff, expected,
                error, error_size) != 0) {
        return pf_tq_handoff_error(error, error_size,
            "handoff/descriptor/current-policy join input rejected");
    }
    memset(&descriptor_ref, 0, sizeof(descriptor_ref));
    (void)snprintf(descriptor_ref.schema, sizeof(descriptor_ref.schema),
        "%s", PF_TQ_DESCRIPTOR_V2_SCHEMA);
    (void)snprintf(descriptor_ref.id, sizeof(descriptor_ref.id),
        "%s", descriptor->id);
    (void)snprintf(descriptor_ref.version, sizeof(descriptor_ref.version),
        "%s", PF_TQ_HANDOFF_DESCRIPTOR_VERSION_V2);
    memcpy(descriptor_ref.digest, descriptor->digest, 32U);
    if (!pf_tq_wire_content_ref_equal_v2(
            &handoff->authority_store_service, &descriptor_ref)) {
        return pf_tq_handoff_error(error, error_size,
            "handoff authorityStoreService does not equal descriptor bytes/ref");
    }
    memset(principal_ids, 0, sizeof(principal_ids));
    for (index = 0U; index < 3U; ++index) {
        const pf_tq_handoff_principal_v2 *matched;
        if (!pf_tq_handoff_fixed_string(descriptor->signing_key_ids[index],
                sizeof(descriptor->signing_key_ids[index])) ||
                !pf_tq_wire_safe_id_v2(descriptor->signing_key_ids[index]) ||
                (index > 0U && strcmp(descriptor->signing_key_ids[index - 1U],
                    descriptor->signing_key_ids[index]) >= 0)) {
            return pf_tq_handoff_error(error, error_size,
                "descriptor signingKeyIds rejected during policy join");
        }
        matched = pf_tq_handoff_find_principal(
            expected, descriptor->signing_key_ids[index]);
        if (matched == NULL || !matched->current) {
            return pf_tq_handoff_error(error, error_size,
                "descriptor signing key is unknown or non-current");
        }
        for (size_t other = 0U; other < index; ++other) {
            if (strcmp(principal_ids[other], matched->principal_id) == 0) {
                return pf_tq_handoff_error(error, error_size,
                    "descriptor signing keys do not map to distinct principals");
            }
        }
        (void)snprintf(principal_ids[index], sizeof(principal_ids[index]),
            "%s", matched->principal_id);
        covered_roles |= matched->roles;
        if (memcmp(descriptor->service_public_key,
                matched->public_key, 32U) == 0) {
            return pf_tq_handoff_error(error, error_size,
                "descriptor service key reuses a role principal key");
        }
    }
    if ((covered_roles & PF_TQ_HANDOFF_REQUIRED_ROLE_MASK_V2) !=
            PF_TQ_HANDOFF_REQUIRED_ROLE_MASK_V2) {
        return pf_tq_handoff_error(error, error_size,
            "descriptor signingKeyIds do not cover A+Q+S");
    }
    return 0;
}
