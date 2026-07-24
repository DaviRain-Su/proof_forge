#include "task_qualification_wire_v2.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int pf_tq_wire_error(
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

static int pf_tq_wire_ascii_alnum(unsigned char value) {
    return (value >= 'A' && value <= 'Z') ||
        (value >= 'a' && value <= 'z') ||
        (value >= '0' && value <= '9');
}

int pf_tq_wire_safe_id_v2(const char *value) {
    size_t size = value == NULL ? 0U : strlen(value);
    size_t index;
    if (size == 0U || size >= PF_TQ_WIRE_V2_SAFE_ID_BYTES ||
            !pf_tq_wire_ascii_alnum((unsigned char)value[0]) ||
            !pf_tq_wire_ascii_alnum((unsigned char)value[size - 1U])) return 0;
    for (index = 1U; index + 1U < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!(pf_tq_wire_ascii_alnum(character) || character == '.' ||
                character == '_' || character == ':' || character == '+' ||
                character == '-')) return 0;
    }
    return 1;
}

int pf_tq_wire_profile_id_v2(const char *value) {
    size_t size = value == NULL ? 0U : strlen(value);
    size_t index;
    int previous_separator = 0;
    if (size == 0U || size >= PF_TQ_WIRE_V2_CONTENT_ID_BYTES ||
            value[0] < 'a' || value[0] > 'z') return 0;
    for (index = 1U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (character == '-' || character == '.') {
            if (previous_separator || index + 1U == size) return 0;
            previous_separator = 1;
        } else if ((character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9')) {
            previous_separator = 0;
        } else {
            return 0;
        }
    }
    return 1;
}

static int pf_tq_wire_document_id(const char *value) {
    size_t size = value == NULL ? 0U : strlen(value);
    size_t index;
    int previous_separator = 0;
    if (size == 0U || size >= PF_TQ_WIRE_V2_CONTENT_ID_BYTES ||
            value[0] < 'A' || value[0] > 'Z') return 0;
    for (index = 1U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (character == '-') {
            if (previous_separator || index + 1U == size) return 0;
            previous_separator = 1;
        } else if ((character >= 'A' && character <= 'Z') ||
                (character >= '0' && character <= '9')) {
            previous_separator = 0;
        } else {
            return 0;
        }
    }
    return 1;
}

static int pf_tq_wire_schema(const char *value) {
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
                continue;
            }
            if (character == '-' && index + 1U < size &&
                    ((value[index + 1U] >= 'a' && value[index + 1U] <= 'z') ||
                     (value[index + 1U] >= '0' && value[index + 1U] <= '9'))) {
                ++index;
                continue;
            }
            return 0;
        }
        if (index < size) {
            ++dots;
            ++index;
            if (index == size) return 0;
        }
    }
    return dots > 0U;
}

static int pf_tq_wire_numeric_identifier(
    const char *start,
    size_t size,
    int forbid_leading_zero
) {
    uint64_t value = 0U;
    size_t index;
    if (size == 0U || (forbid_leading_zero && size > 1U && start[0] == '0')) {
        return 0;
    }
    for (index = 0U; index < size; ++index) {
        unsigned digit;
        if (start[index] < '0' || start[index] > '9') return 0;
        digit = (unsigned)(start[index] - '0');
        if (value > (UINT64_MAX - digit) / 10U) return 0;
        value = value * 10U + digit;
    }
    return 1;
}

static int pf_tq_wire_semver_identifier(
    const char *start,
    size_t size,
    int prerelease
) {
    size_t index;
    int numeric = 1;
    if (size == 0U) return 0;
    for (index = 0U; index < size; ++index) {
        unsigned char character = (unsigned char)start[index];
        if (!pf_tq_wire_ascii_alnum(character) && character != '-') return 0;
        if (character < '0' || character > '9') numeric = 0;
    }
    return !(prerelease && numeric && size > 1U && start[0] == '0');
}

int pf_tq_wire_semver_v2(const char *value) {
    size_t size = value == NULL ? 0U : strlen(value);
    size_t offset = 0U;
    unsigned core;
    if (size == 0U || size >= PF_TQ_WIRE_V2_VERSION_BYTES) return 0;
    for (core = 0U; core < 3U; ++core) {
        size_t start = offset;
        while (offset < size && value[offset] >= '0' && value[offset] <= '9') {
            ++offset;
        }
        if (!pf_tq_wire_numeric_identifier(value + start, offset - start, 1)) return 0;
        if (core < 2U) {
            if (offset >= size || value[offset] != '.') return 0;
            ++offset;
        }
    }
    if (offset < size && value[offset] == '-') {
        ++offset;
        for (;;) {
            size_t start = offset;
            while (offset < size && value[offset] != '.' && value[offset] != '+') {
                ++offset;
            }
            if (!pf_tq_wire_semver_identifier(value + start, offset - start, 1)) return 0;
            if (offset >= size || value[offset] == '+') break;
            ++offset;
        }
    }
    if (offset < size && value[offset] == '+') {
        ++offset;
        for (;;) {
            size_t start = offset;
            while (offset < size && value[offset] != '.') ++offset;
            if (!pf_tq_wire_semver_identifier(value + start, offset - start, 0)) return 0;
            if (offset >= size) break;
            ++offset;
        }
    }
    return offset == size;
}

static int pf_tq_wire_copy_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node =
        pf_tq_jcs_object_get_v2(document, object, field);
    if (pf_tq_jcs_copy_string_v2(document, node, output, output_size,
            error, error_size) != 0) {
        return pf_tq_wire_error(error, error_size,
            "wire string field rejected: %s", field);
    }
    return 0;
}

static int pf_tq_wire_hex_value(unsigned char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

int pf_tq_wire_parse_digest_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    unsigned char digest[32],
    char *error,
    size_t error_size
) {
    char wire[72];
    size_t index;
    if (digest == NULL || pf_tq_jcs_copy_string_v2(document, node, wire,
            sizeof(wire), error, error_size) != 0 || strlen(wire) != 71U ||
            memcmp(wire, "sha256:", 7U) != 0) {
        return pf_tq_wire_error(error, error_size,
            "wire digest must be sha256 lowercase hex");
    }
    for (index = 0U; index < 32U; ++index) {
        int high = pf_tq_wire_hex_value((unsigned char)wire[7U + 2U * index]);
        int low = pf_tq_wire_hex_value((unsigned char)wire[8U + 2U * index]);
        if (high < 0 || low < 0) {
            return pf_tq_wire_error(error, error_size,
                "wire digest must be sha256 lowercase hex");
        }
        digest[index] = (unsigned char)((unsigned)high * 16U + (unsigned)low);
    }
    return 0;
}

int pf_tq_wire_parse_content_ref_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_wire_content_ref_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"digest", "id", "schema", "version"};
    if (document == NULL || node == NULL || result == NULL ||
            node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_wire_error(error, error_size,
            "ContentRef must be a closed object");
    }
    memset(result, 0, sizeof(*result));
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 4U,
            error, error_size) != 0 ||
            pf_tq_wire_copy_string(document, node, "schema", result->schema,
                sizeof(result->schema), error, error_size) != 0 ||
            pf_tq_wire_copy_string(document, node, "id", result->id,
                sizeof(result->id), error, error_size) != 0 ||
            pf_tq_wire_copy_string(document, node, "version", result->version,
                sizeof(result->version), error, error_size) != 0 ||
            !pf_tq_wire_schema(result->schema) ||
            (!pf_tq_wire_profile_id_v2(result->id) &&
                !pf_tq_wire_document_id(result->id)) ||
            !pf_tq_wire_semver_v2(result->version) ||
            pf_tq_wire_parse_digest_v2(document,
                pf_tq_jcs_object_get_v2(document, node, "digest"),
                result->digest, error, error_size) != 0) {
        return pf_tq_wire_error(error, error_size,
            "ContentRef schema/id/version/digest rejected");
    }
    return 0;
}

int pf_tq_wire_parse_verifier_identity_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_wire_verifier_identity_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "buildPolicy", "closure", "executable", "id", "sourceDigest"
    };
    if (document == NULL || node == NULL || result == NULL ||
            node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_wire_error(error, error_size,
            "VerifierIdentity must be a closed object");
    }
    memset(result, 0, sizeof(*result));
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 5U,
            error, error_size) != 0 ||
            pf_tq_wire_copy_string(document, node, "id", result->id,
                sizeof(result->id), error, error_size) != 0 ||
            !pf_tq_wire_safe_id_v2(result->id) ||
            pf_tq_wire_parse_content_ref_v2(document,
                pf_tq_jcs_object_get_v2(document, node, "executable"),
                &result->executable, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(document,
                pf_tq_jcs_object_get_v2(document, node, "closure"),
                &result->closure, error, error_size) != 0 ||
            pf_tq_wire_parse_digest_v2(document,
                pf_tq_jcs_object_get_v2(document, node, "sourceDigest"),
                result->source_digest, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(document,
                pf_tq_jcs_object_get_v2(document, node, "buildPolicy"),
                &result->build_policy, error, error_size) != 0) {
        return pf_tq_wire_error(error, error_size,
            "VerifierIdentity fields rejected");
    }
    return 0;
}

int pf_tq_wire_content_ref_equal_v2(
    const pf_tq_wire_content_ref_v2 *left,
    const pf_tq_wire_content_ref_v2 *right
) {
    return left != NULL && right != NULL &&
        strcmp(left->schema, right->schema) == 0 &&
        strcmp(left->id, right->id) == 0 &&
        strcmp(left->version, right->version) == 0 &&
        memcmp(left->digest, right->digest, 32U) == 0;
}

int pf_tq_wire_verifier_identity_equal_v2(
    const pf_tq_wire_verifier_identity_v2 *left,
    const pf_tq_wire_verifier_identity_v2 *right
) {
    return left != NULL && right != NULL && strcmp(left->id, right->id) == 0 &&
        pf_tq_wire_content_ref_equal_v2(&left->executable, &right->executable) &&
        pf_tq_wire_content_ref_equal_v2(&left->closure, &right->closure) &&
        memcmp(left->source_digest, right->source_digest, 32U) == 0 &&
        pf_tq_wire_content_ref_equal_v2(&left->build_policy, &right->build_policy);
}
