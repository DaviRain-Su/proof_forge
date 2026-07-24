#define _GNU_SOURCE
#include "task_qualification_descriptor_v2.h"

#include <limits.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PF_TQ_DESCRIPTOR_VERSION_V2 "2.0.0"
#define PF_TQ_DESCRIPTOR_NAMESPACE_V2 "task-qualification-production-v1"
#define PF_TQ_DESCRIPTOR_PROTOCOL_V2 "pf.taskqual.authority-store.rpc.v2"
#define PF_TQ_DESCRIPTOR_ID_PREFIX_V2 "task-qualification-store-service-"
#define PF_TQ_DESCRIPTOR_DOMAIN_V2 "pf.taskqual.authority-store-service.v2"
#define PF_TQ_DESCRIPTOR_ISOLATION_SCHEMA_V2 \
    "proof-forge.task-qualification-store-isolation-policy.v2"
#define PF_TQ_DESCRIPTOR_ISOLATION_ID_PREFIX_V2 \
    "task-qualification-store-isolation-"
#define PF_TQ_DESCRIPTOR_RAW_SCHEMA_V2 \
    "proof-forge.task-qualification-artifact-payload.v1"
#define PF_TQ_DESCRIPTOR_LINUX_ID_MAX_V2 UINT32_C(2147483647)
#define PF_TQ_DESCRIPTOR_OVERFLOW_ID_V2 UINT32_C(65534)

static int pf_tq_descriptor_error(
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

static void pf_tq_descriptor_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_descriptor_free_v2(pf_tq_descriptor_v2 *descriptor) {
    if (descriptor == NULL) return;
    free(descriptor->canonical_bytes);
    memset(descriptor, 0, sizeof(*descriptor));
}

static int pf_tq_descriptor_linux_id(uint64_t value) {
    return value >= 1U && value <= PF_TQ_DESCRIPTOR_LINUX_ID_MAX_V2 &&
        value != PF_TQ_DESCRIPTOR_OVERFLOW_ID_V2;
}

static int pf_tq_descriptor_expectation_validate(
    const pf_tq_descriptor_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    if (expected == NULL || !pf_tq_wire_safe_id_v2(expected->run_id) ||
            (expected->require_ref != 0 && expected->require_ref != 1)) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor expectation shape rejected");
    }
    if (expected->require_ref &&
            (strcmp(expected->claimed_ref.schema, PF_TQ_DESCRIPTOR_V2_SCHEMA) != 0 ||
             !pf_tq_wire_profile_id_v2(expected->claimed_ref.id) ||
             !pf_tq_wire_semver_v2(expected->claimed_ref.version))) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor claimed ContentRef shape rejected");
    }
    return 0;
}

static int pf_tq_descriptor_digest(
    const unsigned char *bytes,
    size_t size,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    static const unsigned char zero = 0U;
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    unsigned int output_size = 0U;
    if (context == NULL || EVP_DigestInit_ex(context, EVP_sha256(), NULL) != 1 ||
            EVP_DigestUpdate(context, PF_TQ_DESCRIPTOR_DOMAIN_V2,
                strlen(PF_TQ_DESCRIPTOR_DOMAIN_V2)) != 1 ||
            EVP_DigestUpdate(context, &zero, 1U) != 1 ||
            EVP_DigestUpdate(context, bytes, size) != 1 ||
            EVP_DigestFinal_ex(context, output, &output_size) != 1 ||
            output_size != 32U) {
        EVP_MD_CTX_free(context);
        return pf_tq_descriptor_error(error, error_size,
            "descriptor SHA-256 failed");
    }
    EVP_MD_CTX_free(context);
    return 0;
}

static const pf_tq_jcs_node_v2 *pf_tq_descriptor_field(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field
) {
    return pf_tq_jcs_object_get_v2(document, object, field);
}

static int pf_tq_descriptor_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    if (pf_tq_jcs_copy_string_v2(document,
            pf_tq_descriptor_field(document, object, field), output,
            output_size, error, error_size) != 0) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor string field rejected: %s", field);
    }
    return 0;
}

static int pf_tq_descriptor_string_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    const char *expected,
    char *error,
    size_t error_size
) {
    if (!pf_tq_jcs_string_equal_v2(document,
            pf_tq_descriptor_field(document, object, field), expected)) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor %s mismatch", field);
    }
    return 0;
}

static int pf_tq_descriptor_uint(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    uint64_t *value,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node =
        pf_tq_descriptor_field(document, object, field);
    if (node == NULL || node->type != PF_TQ_JCS_UINT) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor unsigned field rejected: %s", field);
    }
    *value = node->uint_value;
    return 0;
}

static int pf_tq_descriptor_uint_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    uint64_t expected,
    char *error,
    size_t error_size
) {
    uint64_t value = 0U;
    if (pf_tq_descriptor_uint(document, object, field, &value,
            error, error_size) != 0) return -1;
    if (value != expected) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor %s scalar mismatch", field);
    }
    return 0;
}

static int pf_tq_descriptor_identity(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_descriptor_identity_v2 *identity,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"device", "inode"};
    if (node == NULL || identity == NULL || node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor Linux identity must be object");
    }
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 2U,
            error, error_size) != 0 ||
            pf_tq_descriptor_uint(document, node, "device", &identity->device,
                error, error_size) != 0 ||
            pf_tq_descriptor_uint(document, node, "inode", &identity->inode,
                error, error_size) != 0) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor Linux identity rejected");
    }
    return 0;
}

static int pf_tq_descriptor_hex32(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    size_t written = 0U;
    if (pf_tq_jcs_decode_hex_v2(document, node, output, 32U, 32U,
            &written, error, error_size) != 0 || written != 32U) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor servicePublicKey must be 32-byte lowercase hex");
    }
    return 0;
}

static int pf_tq_descriptor_identity_raw_owners(
    const pf_tq_wire_verifier_identity_v2 *identity
) {
    return identity != NULL &&
        strcmp(identity->executable.schema, PF_TQ_DESCRIPTOR_RAW_SCHEMA_V2) == 0 &&
        strcmp(identity->closure.schema, PF_TQ_DESCRIPTOR_RAW_SCHEMA_V2) == 0 &&
        strcmp(identity->build_policy.schema, PF_TQ_DESCRIPTOR_RAW_SCHEMA_V2) == 0;
}

int pf_tq_descriptor_parse_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_descriptor_expectation_v2 *expected,
    pf_tq_descriptor_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "adapterGid", "adapterUid", "custodyKind", "id", "isolationPolicy",
        "maximumFrameBytes", "maximumTerminalAcceptances", "namespace",
        "peerInspectionProfile", "protocol", "schema", "seedRoot",
        "serviceGid", "servicePublicKey", "serviceUid", "signingKeyIds",
        "supervisor", "userNamespace", "verifier", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *signing_keys;
    pf_tq_wire_content_ref_v2 actual_ref;
    char expected_id[PF_TQ_DESCRIPTOR_V2_ID_BYTES];
    char expected_isolation_id[PF_TQ_DESCRIPTOR_V2_ID_BYTES];
    uint64_t scalar = 0U;
    int rendered;
    int document_initialized = 0;
    int status = -1;
    pf_tq_descriptor_clear_error(error, error_size);
    if (bytes == NULL || size == 0U || size > PF_TQ_DESCRIPTOR_V2_MAX_BYTES ||
            result == NULL) {
        return pf_tq_descriptor_error(error, error_size,
            "descriptor input/result rejected");
    }
    memset(result, 0, sizeof(*result));
    memset(&actual_ref, 0, sizeof(actual_ref));
    if (pf_tq_descriptor_expectation_validate(expected,
            error, error_size) != 0) return -1;
    if (pf_tq_jcs_parse_v2(bytes, size, &document,
            error, error_size) != 0) return -1;
    document_initialized = 1;
    root = pf_tq_jcs_root_v2(&document);
    if (root == NULL || root->type != PF_TQ_JCS_OBJECT) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor root must be a closed object");
        goto cleanup;
    }
    if (pf_tq_jcs_object_exact_v2(&document, root, fields, 20U,
            error, error_size) != 0 ||
            pf_tq_descriptor_digest(bytes, size, result->digest,
                error, error_size) != 0 ||
            pf_tq_descriptor_string_exact(&document, root, "schema",
                PF_TQ_DESCRIPTOR_V2_SCHEMA, error, error_size) != 0 ||
            pf_tq_descriptor_string_exact(&document, root, "version",
                PF_TQ_DESCRIPTOR_VERSION_V2, error, error_size) != 0 ||
            pf_tq_descriptor_string_exact(&document, root, "namespace",
                PF_TQ_DESCRIPTOR_NAMESPACE_V2, error, error_size) != 0 ||
            pf_tq_descriptor_string_exact(&document, root, "protocol",
                PF_TQ_DESCRIPTOR_PROTOCOL_V2, error, error_size) != 0) goto cleanup;
    rendered = snprintf(expected_id, sizeof(expected_id), "%s%s",
        PF_TQ_DESCRIPTOR_ID_PREFIX_V2, expected->run_id);
    if (rendered <= 0 || (size_t)rendered >= sizeof(expected_id) ||
            pf_tq_descriptor_string(&document, root, "id", result->id,
                sizeof(result->id), error, error_size) != 0 ||
            !pf_tq_wire_profile_id_v2(result->id) ||
            strcmp(result->id, expected_id) != 0) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor id/runId join rejected");
        goto cleanup;
    }
    (void)snprintf(actual_ref.schema, sizeof(actual_ref.schema),
        "%s", PF_TQ_DESCRIPTOR_V2_SCHEMA);
    (void)snprintf(actual_ref.id, sizeof(actual_ref.id), "%s", result->id);
    (void)snprintf(actual_ref.version, sizeof(actual_ref.version),
        "%s", PF_TQ_DESCRIPTOR_VERSION_V2);
    memcpy(actual_ref.digest, result->digest, 32U);
    if (expected->require_ref && !pf_tq_wire_content_ref_equal_v2(
            &actual_ref, &expected->claimed_ref)) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor bytes do not equal claimed ContentRef");
        goto cleanup;
    }
    if (pf_tq_descriptor_hex32(&document,
            pf_tq_descriptor_field(&document, root, "servicePublicKey"),
            result->service_public_key, error, error_size) != 0 ||
            pf_tq_wire_parse_verifier_identity_v2(&document,
                pf_tq_descriptor_field(&document, root, "verifier"),
                &result->verifier, error, error_size) != 0 ||
            pf_tq_wire_parse_verifier_identity_v2(&document,
                pf_tq_descriptor_field(&document, root, "supervisor"),
                &result->supervisor, error, error_size) != 0 ||
            !pf_tq_descriptor_identity_raw_owners(&result->verifier) ||
            !pf_tq_descriptor_identity_raw_owners(&result->supervisor) ||
            pf_tq_wire_parse_content_ref_v2(&document,
                pf_tq_descriptor_field(&document, root, "isolationPolicy"),
                &result->isolation_policy, error, error_size) != 0) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor verifier/supervisor/isolation owner rejected");
        goto cleanup;
    }
    rendered = snprintf(expected_isolation_id, sizeof(expected_isolation_id), "%s%s",
        PF_TQ_DESCRIPTOR_ISOLATION_ID_PREFIX_V2, expected->run_id);
    if (rendered <= 0 || (size_t)rendered >= sizeof(expected_isolation_id) ||
            !pf_tq_wire_profile_id_v2(expected_isolation_id) ||
            strcmp(result->isolation_policy.schema,
                PF_TQ_DESCRIPTOR_ISOLATION_SCHEMA_V2) != 0 ||
            strcmp(result->isolation_policy.id, expected_isolation_id) != 0 ||
            strcmp(result->isolation_policy.version,
                PF_TQ_DESCRIPTOR_VERSION_V2) != 0) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor isolationPolicy ref/runId join rejected");
        goto cleanup;
    }
    signing_keys = pf_tq_descriptor_field(&document, root, "signingKeyIds");
    if (signing_keys == NULL || signing_keys->type != PF_TQ_JCS_ARRAY ||
            signing_keys->child_count != 3U) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor signingKeyIds must contain exactly three keys");
        goto cleanup;
    }
    for (size_t index = 0U; index < 3U; ++index) {
        if (pf_tq_jcs_copy_string_v2(&document,
                pf_tq_jcs_array_at_v2(&document, signing_keys, index),
                result->signing_key_ids[index],
                sizeof(result->signing_key_ids[index]),
                error, error_size) != 0 ||
                !pf_tq_wire_safe_id_v2(result->signing_key_ids[index]) ||
                (index > 0U && strcmp(result->signing_key_ids[index - 1U],
                    result->signing_key_ids[index]) >= 0)) {
            (void)pf_tq_descriptor_error(error, error_size,
                "descriptor signingKeyIds order/grammar rejected");
            goto cleanup;
        }
    }
    if (pf_tq_descriptor_string_exact(&document, root, "custodyKind",
            "one-time-seed-fd-v1", error, error_size) != 0 ||
            pf_tq_descriptor_string_exact(&document, root,
                "peerInspectionProfile", "linux-pidfd-proc-cross-uid-v1",
                error, error_size) != 0 ||
            pf_tq_descriptor_uint_exact(&document, root, "maximumFrameBytes",
                4194304U, error, error_size) != 0 ||
            pf_tq_descriptor_uint_exact(&document, root,
                "maximumTerminalAcceptances", 1U,
                error, error_size) != 0 ||
            pf_tq_descriptor_identity(&document,
                pf_tq_descriptor_field(&document, root, "userNamespace"),
                &result->user_namespace, error, error_size) != 0 ||
            pf_tq_descriptor_identity(&document,
                pf_tq_descriptor_field(&document, root, "seedRoot"),
                &result->seed_root, error, error_size) != 0) goto cleanup;
    if (pf_tq_descriptor_uint(&document, root, "adapterUid", &scalar,
            error, error_size) != 0 || !pf_tq_descriptor_linux_id(scalar)) goto id_rejected;
    result->adapter_uid = (uint32_t)scalar;
    if (pf_tq_descriptor_uint(&document, root, "adapterGid", &scalar,
            error, error_size) != 0 || !pf_tq_descriptor_linux_id(scalar)) goto id_rejected;
    result->adapter_gid = (uint32_t)scalar;
    if (pf_tq_descriptor_uint(&document, root, "serviceUid", &scalar,
            error, error_size) != 0 || !pf_tq_descriptor_linux_id(scalar)) goto id_rejected;
    result->service_uid = (uint32_t)scalar;
    if (pf_tq_descriptor_uint(&document, root, "serviceGid", &scalar,
            error, error_size) != 0 || !pf_tq_descriptor_linux_id(scalar)) goto id_rejected;
    result->service_gid = (uint32_t)scalar;
    if (result->adapter_uid == result->service_uid ||
            result->adapter_gid == result->service_gid) goto id_rejected;

    result->canonical_bytes = malloc(size);
    if (result->canonical_bytes == NULL) {
        (void)pf_tq_descriptor_error(error, error_size,
            "descriptor canonical-byte allocation failed");
        goto cleanup;
    }
    memcpy(result->canonical_bytes, bytes, size);
    result->canonical_size = size;
    status = 0;
    goto cleanup;

id_rejected:
    (void)pf_tq_descriptor_error(error, error_size,
        "descriptor UID/GID rejected");
cleanup:
    if (document_initialized) pf_tq_jcs_free_v2(&document);
    if (status != 0) pf_tq_descriptor_free_v2(result);
    return status;
}
