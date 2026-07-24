#define _GNU_SOURCE
#include "task_qualification_isolation_policy_v2.h"
#include "task_qualification_pf_jcs_v2.h"
#include "task_qualification_unicode_v2.h"

#include <limits.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PF_TQ_ISOLATION_SCHEMA_V2 \
    "proof-forge.task-qualification-store-isolation-policy.v2"
#define PF_TQ_ISOLATION_NAMESPACE_V2 "task-qualification-production-v1"
#define PF_TQ_ISOLATION_VERSION_V2 "2.0.0"
#define PF_TQ_ISOLATION_ID_PREFIX_V2 "task-qualification-store-isolation-"
#define PF_TQ_ISOLATION_DIGEST_DOMAIN_V2 \
    "pf.taskqual.store-isolation-policy.v2"
#define PF_TQ_ISOLATION_MAX_ENTRIES_V2 65536U
#define PF_TQ_ISOLATION_LINUX_ID_MAX_V2 UINT32_C(2147483647)
#define PF_TQ_ISOLATION_OVERFLOW_ID_V2 UINT32_C(65534)

static int pf_tq_isolation_error(
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

static void pf_tq_isolation_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_isolation_policy_free_v2(pf_tq_isolation_policy_v2 *policy) {
    size_t index;
    if (policy == NULL) return;
    for (index = 0U; index < policy->service_mount_count; ++index) {
        free(policy->service_mounts[index].target);
    }
    for (index = 0U; index < policy->adapter_mount_count; ++index) {
        free(policy->adapter_mounts[index].target);
    }
    free(policy->service_mounts);
    free(policy->adapter_mounts);
    free(policy->fd_roles);
    free(policy->canonical_bytes);
    memset(policy, 0, sizeof(*policy));
}

static int pf_tq_isolation_operation(const char *value) {
    static const char *const operations[] = {
        "task-qualification", "task-completion",
        "d0-10-bootstrap-approval", "d0-10-bootstrap-receipt"
    };
    size_t index;
    if (value == NULL) return 0;
    for (index = 0U; index < sizeof(operations) / sizeof(operations[0]); ++index) {
        if (strcmp(value, operations[index]) == 0) return 1;
    }
    return 0;
}

static int pf_tq_isolation_ascii_id(const char *value, size_t maximum) {
    size_t index;
    size_t size = value == NULL ? 0U : strlen(value);
    if (size == 0U || size > maximum) return 0;
    for (index = 0U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!((character >= 'A' && character <= 'Z') ||
                (character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9') || character == '-' ||
                character == '.' || character == '_')) return 0;
    }
    return 1;
}

static int pf_tq_isolation_role_id(const char *value) {
    size_t index;
    size_t size = value == NULL ? 0U : strlen(value);
    if (size == 0U || size >= PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES ||
            value[0] < 'a' || value[0] > 'z') return 0;
    for (index = 1U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!((character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9') ||
                character == '-')) return 0;
    }
    return 1;
}

static int pf_tq_isolation_linux_id(uint64_t value) {
    return value >= 1U && value <= PF_TQ_ISOLATION_LINUX_ID_MAX_V2 &&
        value != PF_TQ_ISOLATION_OVERFLOW_ID_V2;
}

static int pf_tq_isolation_identity_equal(
    pf_tq_isolation_identity_v2 left,
    pf_tq_isolation_identity_v2 right
) {
    return left.device == right.device && left.inode == right.inode;
}

static int pf_tq_isolation_key_compare(
    const char *left_process,
    const char *left_stage,
    const char *left_role,
    const char *right_process,
    const char *right_stage,
    const char *right_role
) {
    int comparison = strcmp(left_process, right_process);
    if (comparison != 0) return comparison;
    comparison = strcmp(left_stage, right_stage);
    return comparison != 0 ? comparison : strcmp(left_role, right_role);
}

static int pf_tq_isolation_expectation_validate(
    const pf_tq_isolation_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    size_t index;
    if (expected == NULL ||
            !pf_tq_isolation_ascii_id(expected->task_id,
                PF_TQ_ISOLATION_POLICY_V2_ID_BYTES - 1U) ||
            !pf_tq_isolation_operation(expected->operation) ||
            !pf_tq_isolation_ascii_id(expected->run_id,
                PF_TQ_ISOLATION_POLICY_V2_ID_BYTES - 1U) ||
            !pf_tq_isolation_ascii_id(expected->nonce,
                PF_TQ_ISOLATION_POLICY_V2_ID_BYTES - 1U) ||
            !pf_tq_isolation_linux_id(expected->adapter_uid) ||
            !pf_tq_isolation_linux_id(expected->adapter_gid) ||
            !pf_tq_isolation_linux_id(expected->service_uid) ||
            !pf_tq_isolation_linux_id(expected->service_gid) ||
            expected->adapter_uid == expected->service_uid ||
            expected->adapter_gid == expected->service_gid ||
            expected->fd_manifest == NULL || expected->fd_manifest_count == 0U ||
            expected->fd_manifest_count > PF_TQ_ISOLATION_MAX_ENTRIES_V2 ||
            expected->proc_root_role_index >= expected->fd_manifest_count ||
            expected->durable_root_role_index >= expected->fd_manifest_count ||
            expected->service_executable_role_index >= expected->fd_manifest_count ||
            expected->proc_root_role_index == expected->durable_root_role_index ||
            expected->proc_root_role_index == expected->service_executable_role_index ||
            expected->durable_root_role_index == expected->service_executable_role_index ||
            (expected->require_digest != 0 && expected->require_digest != 1)) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy expectation shape rejected");
    }
    for (index = 0U; index < expected->fd_manifest_count; ++index) {
        const pf_tq_isolation_fd_manifest_v2 *entry = &expected->fd_manifest[index];
        if (!pf_tq_isolation_role_id(entry->process) ||
                !pf_tq_isolation_role_id(entry->stage) ||
                !pf_tq_isolation_role_id(entry->role) ||
                (entry->close_on_exec != 0 && entry->close_on_exec != 1) ||
                (index > 0U && pf_tq_isolation_key_compare(
                    expected->fd_manifest[index - 1U].process,
                    expected->fd_manifest[index - 1U].stage,
                    expected->fd_manifest[index - 1U].role,
                    entry->process, entry->stage, entry->role) >= 0)) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy FD manifest rejected at %zu", index);
        }
    }
    if (expected->fd_manifest[expected->service_executable_role_index].
            close_on_exec != 1) {
        return pf_tq_isolation_error(error, error_size,
            "service executable manifest role must be close-on-exec");
    }
    return 0;
}

static int pf_tq_isolation_digest(
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
            EVP_DigestUpdate(context, PF_TQ_ISOLATION_DIGEST_DOMAIN_V2,
                strlen(PF_TQ_ISOLATION_DIGEST_DOMAIN_V2)) != 1 ||
            EVP_DigestUpdate(context, &zero, 1U) != 1 ||
            EVP_DigestUpdate(context, bytes, size) != 1 ||
            EVP_DigestFinal_ex(context, output, &output_size) != 1 ||
            output_size != 32U) {
        EVP_MD_CTX_free(context);
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy SHA-256 failed");
    }
    EVP_MD_CTX_free(context);
    return 0;
}

static const pf_tq_jcs_node_v2 *pf_tq_isolation_field(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *name
) {
    return pf_tq_jcs_object_get_v2(document, object, name);
}

static int pf_tq_isolation_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    if (pf_tq_jcs_copy_string_v2(document,
            pf_tq_isolation_field(document, object, field), output,
            output_size, error, error_size) != 0) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy string field rejected: %s", field);
    }
    return 0;
}

static int pf_tq_isolation_string_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    const char *expected,
    char *error,
    size_t error_size
) {
    if (!pf_tq_jcs_string_equal_v2(document,
            pf_tq_isolation_field(document, object, field), expected)) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy %s mismatch", field);
    }
    return 0;
}

static int pf_tq_isolation_uint(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    uint64_t *value,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_isolation_field(document, object, field);
    if (node == NULL || node->type != PF_TQ_JCS_UINT) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy unsigned field rejected: %s", field);
    }
    *value = node->uint_value;
    return 0;
}

static int pf_tq_isolation_uint_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    uint64_t expected,
    char *error,
    size_t error_size
) {
    uint64_t value = 0U;
    if (pf_tq_isolation_uint(document, object, field, &value,
            error, error_size) != 0) return -1;
    if (value != expected) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy %s must be %llu", field,
            (unsigned long long)expected);
    }
    return 0;
}

static int pf_tq_isolation_bool(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    int *value,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_isolation_field(document, object, field);
    if (node == NULL || node->type != PF_TQ_JCS_BOOL) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy boolean field rejected: %s", field);
    }
    *value = node->bool_value;
    return 0;
}

static int pf_tq_isolation_bool_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    int expected,
    char *error,
    size_t error_size
) {
    int value = 0;
    if (pf_tq_isolation_bool(document, object, field, &value,
            error, error_size) != 0) return -1;
    if (value != expected) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy %s boolean mismatch", field);
    }
    return 0;
}

static int pf_tq_isolation_identity_parse(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_isolation_identity_v2 *identity,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"device", "inode"};
    if (node == NULL || node->type != PF_TQ_JCS_OBJECT ||
            pf_tq_jcs_object_exact_v2(document, node, fields, 2U,
                error, error_size) != 0 ||
            pf_tq_isolation_uint(document, node, "device", &identity->device,
                error, error_size) != 0 ||
            pf_tq_isolation_uint(document, node, "inode", &identity->inode,
                error, error_size) != 0) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy Linux identity rejected");
    }
    return 0;
}

static int pf_tq_isolation_map_parse(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *array,
    const uint32_t expected_inside[2],
    pf_tq_isolation_id_map_v2 output[2],
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"insideId", "length", "outsideId"};
    size_t index;
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count != 2U) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy ID map must contain exactly two entries");
    }
    for (index = 0U; index < 2U; ++index) {
        const pf_tq_jcs_node_v2 *entry =
            pf_tq_jcs_array_at_v2(document, array, index);
        uint64_t inside = 0U;
        uint64_t outside = 0U;
        if (entry == NULL || entry->type != PF_TQ_JCS_OBJECT ||
                pf_tq_jcs_object_exact_v2(document, entry, fields, 3U,
                    error, error_size) != 0 ||
                pf_tq_isolation_uint(document, entry, "insideId", &inside,
                    error, error_size) != 0 ||
                pf_tq_isolation_uint_exact(document, entry, "length", 1U,
                    error, error_size) != 0 ||
                pf_tq_isolation_uint(document, entry, "outsideId", &outside,
                    error, error_size) != 0 ||
                inside != expected_inside[index] ||
                !pf_tq_isolation_linux_id(outside)) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy ID map entry rejected at %zu", index);
        }
        output[index].inside_id = (uint32_t)inside;
        output[index].outside_id = (uint32_t)outside;
    }
    if (output[0].inside_id >= output[1].inside_id ||
            output[0].outside_id == output[1].outside_id) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy ID map order/uniqueness rejected");
    }
    return 0;
}

static int pf_tq_isolation_path_validate(
    const unsigned char *bytes,
    size_t size,
    char *error,
    size_t error_size
) {
    size_t component_start;
    size_t index;
    if (bytes == NULL || size == 0U || size > PF_TQ_ISOLATION_POLICY_V2_PATH_BYTES ||
            bytes[0] != '/' || (size > 1U && bytes[size - 1U] == '/')) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy mount target shape rejected");
    }
    if (pf_tq_unicode_require_nfc_v2(bytes, size, error, error_size) != 0) {
        return -1;
    }
    if (size == 1U) return 0;
    component_start = 1U;
    for (index = 1U; index <= size; ++index) {
        if (index < size && bytes[index] != '/') {
            if (bytes[index] == 0U) {
                return pf_tq_isolation_error(error, error_size,
                    "isolation-policy mount target contains NUL");
            }
            continue;
        }
        if (index == component_start) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy mount target contains an empty component");
        }
        if (index - component_start > 255U ||
                (index - component_start == 1U && bytes[component_start] == '.') ||
                (index - component_start == 2U && bytes[component_start] == '.' &&
                    bytes[component_start + 1U] == '.')) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy mount target component rejected");
        }
        component_start = index + 1U;
    }
    return 0;
}

static int pf_tq_isolation_bytes_compare(
    const unsigned char *left,
    size_t left_size,
    const unsigned char *right,
    size_t right_size
) {
    size_t shared = left_size < right_size ? left_size : right_size;
    int comparison = memcmp(left, right, shared);
    if (comparison != 0) return comparison;
    if (left_size < right_size) return -1;
    if (left_size > right_size) return 1;
    return 0;
}

static int pf_tq_isolation_mounts_parse(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *array,
    int adapter,
    pf_tq_isolation_identity_v2 service_proc_root,
    pf_tq_isolation_identity_v2 durable_root,
    pf_tq_isolation_identity_v2 seed_root,
    pf_tq_isolation_mount_v2 **output,
    size_t *output_count,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "noDev", "noExec", "noSuid", "readOnly", "source", "target"
    };
    pf_tq_isolation_mount_v2 *mounts = NULL;
    size_t count;
    size_t index;
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count > PF_TQ_ISOLATION_MAX_ENTRIES_V2) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy mount array rejected");
    }
    count = array->child_count;
    if (count > 0U) {
        mounts = calloc(count, sizeof(*mounts));
        if (mounts == NULL) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy mount allocation failed");
        }
    }
    for (index = 0U; index < count; ++index) {
        const pf_tq_jcs_node_v2 *entry =
            pf_tq_jcs_array_at_v2(document, array, index);
        const pf_tq_jcs_node_v2 *target;
        if (entry == NULL || entry->type != PF_TQ_JCS_OBJECT) {
            (void)pf_tq_isolation_error(error, error_size,
                "isolation-policy mount entry is not an object");
            goto rejected;
        }
        if (pf_tq_jcs_object_exact_v2(document, entry, fields, 6U,
                error, error_size) != 0) goto rejected;
        target = pf_tq_isolation_field(document, entry, "target");
        if (target == NULL || target->type != PF_TQ_JCS_STRING ||
                target->string_decoded_size == 0U ||
                target->string_decoded_size > PF_TQ_ISOLATION_POLICY_V2_PATH_BYTES) {
            (void)pf_tq_isolation_error(error, error_size,
                "isolation-policy mount target size/type rejected");
            goto rejected;
        }
        mounts[index].target = malloc(target->string_decoded_size + 1U);
        if (mounts[index].target == NULL || pf_tq_jcs_copy_string_v2(
                document, target, mounts[index].target,
                target->string_decoded_size + 1U, error, error_size) != 0) goto rejected;
        mounts[index].target_size = target->string_decoded_size;
        if (pf_tq_isolation_path_validate(
                (const unsigned char *)mounts[index].target,
                mounts[index].target_size, error, error_size) != 0 ||
                pf_tq_isolation_identity_parse(document,
                    pf_tq_isolation_field(document, entry, "source"),
                    &mounts[index].source, error, error_size) != 0 ||
                pf_tq_isolation_bool(document, entry, "readOnly",
                    &mounts[index].read_only, error, error_size) != 0 ||
                pf_tq_isolation_bool(document, entry, "noSuid",
                    &mounts[index].no_suid, error, error_size) != 0 ||
                pf_tq_isolation_bool(document, entry, "noDev",
                    &mounts[index].no_dev, error, error_size) != 0 ||
                pf_tq_isolation_bool(document, entry, "noExec",
                    &mounts[index].no_exec, error, error_size) != 0) goto rejected;
        if (index > 0U && pf_tq_isolation_bytes_compare(
                (const unsigned char *)mounts[index - 1U].target,
                mounts[index - 1U].target_size,
                (const unsigned char *)mounts[index].target,
                mounts[index].target_size) >= 0) {
            (void)pf_tq_isolation_error(error, error_size,
                "isolation-policy mount targets are duplicate/unsorted");
            goto rejected;
        }
        if (adapter && (pf_tq_isolation_identity_equal(
                    mounts[index].source, service_proc_root) ||
                pf_tq_isolation_identity_equal(mounts[index].source, durable_root) ||
                pf_tq_isolation_identity_equal(mounts[index].source, seed_root))) {
            (void)pf_tq_isolation_error(error, error_size,
                "adapter mount references a forbidden service root");
            goto rejected;
        }
    }
    *output = mounts;
    *output_count = count;
    return 0;
rejected:
    for (size_t cleanup = 0U; cleanup < count; ++cleanup) {
        free(mounts[cleanup].target);
    }
    free(mounts);
    return -1;
}

static int pf_tq_isolation_fd_roles_parse(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *array,
    const pf_tq_isolation_expectation_v2 *expected,
    pf_tq_isolation_policy_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "closeOnExec", "fd", "process", "role", "stage"
    };
    size_t index;
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count != expected->fd_manifest_count) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy FD roles do not equal the lifecycle manifest");
    }
    result->fd_roles = calloc(array->child_count, sizeof(*result->fd_roles));
    if (result->fd_roles == NULL) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy FD role allocation failed");
    }
    result->fd_role_count = array->child_count;
    for (index = 0U; index < result->fd_role_count; ++index) {
        const pf_tq_jcs_node_v2 *entry =
            pf_tq_jcs_array_at_v2(document, array, index);
        const pf_tq_isolation_fd_manifest_v2 *manifest =
            &expected->fd_manifest[index];
        uint64_t fd = 0U;
        size_t other;
        if (entry == NULL || entry->type != PF_TQ_JCS_OBJECT ||
                pf_tq_jcs_object_exact_v2(document, entry, fields, 5U,
                    error, error_size) != 0 ||
                pf_tq_isolation_string(document, entry, "process",
                    result->fd_roles[index].process,
                    sizeof(result->fd_roles[index].process),
                    error, error_size) != 0 ||
                pf_tq_isolation_string(document, entry, "stage",
                    result->fd_roles[index].stage,
                    sizeof(result->fd_roles[index].stage),
                    error, error_size) != 0 ||
                pf_tq_isolation_string(document, entry, "role",
                    result->fd_roles[index].role,
                    sizeof(result->fd_roles[index].role),
                    error, error_size) != 0 ||
                !pf_tq_isolation_role_id(result->fd_roles[index].process) ||
                !pf_tq_isolation_role_id(result->fd_roles[index].stage) ||
                !pf_tq_isolation_role_id(result->fd_roles[index].role) ||
                strcmp(result->fd_roles[index].process, manifest->process) != 0 ||
                strcmp(result->fd_roles[index].stage, manifest->stage) != 0 ||
                strcmp(result->fd_roles[index].role, manifest->role) != 0 ||
                pf_tq_isolation_uint(document, entry, "fd", &fd,
                    error, error_size) != 0 || fd > INT_MAX ||
                pf_tq_isolation_bool(document, entry, "closeOnExec",
                    &result->fd_roles[index].close_on_exec,
                    error, error_size) != 0 ||
                result->fd_roles[index].close_on_exec != manifest->close_on_exec) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy FD role rejected at %zu", index);
        }
        result->fd_roles[index].fd = (int)fd;
        for (other = 0U; other < index; ++other) {
            if (strcmp(result->fd_roles[other].process,
                    result->fd_roles[index].process) == 0 &&
                    strcmp(result->fd_roles[other].stage,
                        result->fd_roles[index].stage) == 0 &&
                    result->fd_roles[other].fd == result->fd_roles[index].fd) {
                return pf_tq_isolation_error(error, error_size,
                    "isolation-policy FD reused within process/stage");
            }
        }
    }
    return 0;
}

static int pf_tq_isolation_capabilities_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *root,
    const char *field,
    const uint64_t *expected,
    size_t expected_count,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *array = pf_tq_isolation_field(document, root, field);
    size_t index;
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count != expected_count) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy capability array mismatch: %s", field);
    }
    for (index = 0U; index < expected_count; ++index) {
        const pf_tq_jcs_node_v2 *node =
            pf_tq_jcs_array_at_v2(document, array, index);
        if (node == NULL || node->type != PF_TQ_JCS_UINT ||
                node->uint_value != expected[index] ||
                (index > 0U && expected[index - 1U] >= expected[index])) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy capability value/order mismatch: %s", field);
        }
    }
    return 0;
}

static int pf_tq_isolation_seccomp_parse(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *root,
    const pf_tq_isolation_expectation_v2 *expected,
    pf_tq_isolation_policy_v2 *result,
    size_t starts[3],
    size_t sizes[3],
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *array =
        pf_tq_isolation_field(document, root, "seccompPolicies");
    size_t index;
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count != 3U) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy must contain exactly three seccomp policies");
    }
    for (index = 0U; index < 3U; ++index) {
        const pf_tq_jcs_node_v2 *node =
            pf_tq_jcs_array_at_v2(document, array, index);
        pf_tq_seccomp_context_v2 context;
        if (node == NULL || node->type != PF_TQ_JCS_OBJECT ||
                node->raw_end <= node->raw_start) {
            return pf_tq_isolation_error(error, error_size,
                "isolation-policy seccomp entry rejected at %zu", index);
        }
        context.stage = (pf_tq_seccomp_stage_v2)index;
        context.proc_root_fd = result->fd_roles[
            expected->proc_root_role_index].fd;
        context.durable_root_fd = result->fd_roles[
            expected->durable_root_role_index].fd;
        context.service_executable_fd = result->fd_roles[
            expected->service_executable_role_index].fd;
        starts[index] = node->raw_start;
        sizes[index] = node->raw_end - node->raw_start;
        if (pf_tq_seccomp_validate_v2(
                document->bytes + starts[index], sizes[index], &context,
                error, error_size) != 0) {
            return -1;
        }
    }
    return 0;
}

int pf_tq_isolation_policy_parse_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_isolation_expectation_v2 *expected,
    pf_tq_isolation_policy_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const root_fields[] = {
        "adapterCapabilities", "adapterGid", "adapterMountNamespace",
        "adapterMounts", "adapterPidNamespace", "adapterUid",
        "custodyCapabilities", "durableStateRoot", "execOperation",
        "fdRoles", "finalServiceCapabilities", "gidMap", "id",
        "maximumFrameBytes", "maximumTerminalAcceptances",
        "minimumEffectiveSocketBufferBytes", "namespace", "nonce",
        "operation", "parentPidNamespace", "passCredentials",
        "preSeedCapabilities", "requestedSocketBufferBytes", "runId",
        "schema", "seccompPolicies", "seedRoot", "serviceArgv",
        "serviceEnvironment", "serviceExecutableFd", "serviceGid",
        "serviceMountNamespace", "serviceMounts", "serviceProcRoot",
        "serviceUid", "socketCreation", "socketDomain", "socketSendFlags",
        "socketType", "staticElfRequired", "taskId", "uidMap",
        "userNamespace", "version"
    };
    static const uint64_t preseed[] = {6U, 7U, 8U, 19U, 21U};
    static const uint64_t custody[] = {8U, 19U};
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *array;
    uint32_t uid_inside[2];
    uint32_t gid_inside[2];
    uint32_t outside[4];
    uint64_t scalar;
    char identifier[PF_TQ_ISOLATION_POLICY_V2_ID_BYTES * 2U];
    size_t seccomp_starts[3];
    size_t seccomp_sizes[3];
    int document_initialized = 0;
    int status = -1;
    pf_tq_isolation_clear_error(error, error_size);
    if (bytes == NULL || size == 0U ||
            size > PF_TQ_ISOLATION_POLICY_V2_MAX_BYTES || result == NULL) {
        return pf_tq_isolation_error(error, error_size,
            "isolation-policy input/result rejected");
    }
    memset(result, 0, sizeof(*result));
    if (pf_tq_isolation_expectation_validate(expected,
            error, error_size) != 0) return -1;
    if (pf_tq_jcs_parse_unicode_v2(bytes, size, &document,
            error, error_size) != 0) return -1;
    document_initialized = 1;
    root = pf_tq_jcs_root_v2(&document);
    if (root == NULL || root->type != PF_TQ_JCS_OBJECT) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy root must be a closed object");
        goto cleanup;
    }
    if (pf_tq_jcs_object_exact_v2(&document, root, root_fields,
            sizeof(root_fields) / sizeof(root_fields[0]),
            error, error_size) != 0) goto cleanup;
    if (pf_tq_isolation_digest(bytes, size, result->digest,
            error, error_size) != 0 ||
            (expected->require_digest && memcmp(
                result->digest, expected->digest, 32U) != 0)) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy content digest mismatch");
        goto cleanup;
    }
    if (pf_tq_isolation_string_exact(&document, root, "schema",
            PF_TQ_ISOLATION_SCHEMA_V2, error, error_size) != 0 ||
            pf_tq_isolation_string_exact(&document, root, "version",
                PF_TQ_ISOLATION_VERSION_V2, error, error_size) != 0 ||
            pf_tq_isolation_string_exact(&document, root, "namespace",
                PF_TQ_ISOLATION_NAMESPACE_V2, error, error_size) != 0 ||
            pf_tq_isolation_string(&document, root, "taskId", result->task_id,
                sizeof(result->task_id), error, error_size) != 0 ||
            pf_tq_isolation_string(&document, root, "operation", result->operation,
                sizeof(result->operation), error, error_size) != 0 ||
            pf_tq_isolation_string(&document, root, "runId", result->run_id,
                sizeof(result->run_id), error, error_size) != 0 ||
            pf_tq_isolation_string(&document, root, "nonce", result->nonce,
                sizeof(result->nonce), error, error_size) != 0 ||
            strcmp(result->task_id, expected->task_id) != 0 ||
            strcmp(result->operation, expected->operation) != 0 ||
            strcmp(result->run_id, expected->run_id) != 0 ||
            strcmp(result->nonce, expected->nonce) != 0) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy handoff tuple mismatch");
        goto cleanup;
    }
    if (snprintf(identifier, sizeof(identifier), "%s%s",
            PF_TQ_ISOLATION_ID_PREFIX_V2, result->run_id) <= 0 ||
            pf_tq_isolation_string_exact(&document, root, "id", identifier,
                error, error_size) != 0) goto cleanup;

    if (pf_tq_isolation_identity_parse(&document,
            pf_tq_isolation_field(&document, root, "userNamespace"),
            &result->user_namespace, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "parentPidNamespace"),
                &result->parent_pid_namespace, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "adapterPidNamespace"),
                &result->adapter_pid_namespace, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "serviceMountNamespace"),
                &result->service_mount_namespace, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "adapterMountNamespace"),
                &result->adapter_mount_namespace, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "serviceProcRoot"),
                &result->service_proc_root, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "durableStateRoot"),
                &result->durable_state_root, error, error_size) != 0 ||
            pf_tq_isolation_identity_parse(&document,
                pf_tq_isolation_field(&document, root, "seedRoot"),
                &result->seed_root, error, error_size) != 0) goto cleanup;
    if (!pf_tq_isolation_identity_equal(
                result->user_namespace, expected->user_namespace) ||
            !pf_tq_isolation_identity_equal(result->seed_root, expected->seed_root) ||
            pf_tq_isolation_identity_equal(result->parent_pid_namespace,
                result->adapter_pid_namespace) ||
            pf_tq_isolation_identity_equal(result->service_mount_namespace,
                result->adapter_mount_namespace) ||
            pf_tq_isolation_identity_equal(result->service_proc_root,
                result->durable_state_root) ||
            pf_tq_isolation_identity_equal(result->service_proc_root,
                result->seed_root) ||
            pf_tq_isolation_identity_equal(result->durable_state_root,
                result->seed_root)) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy identity join/distinctness rejected");
        goto cleanup;
    }

    if (pf_tq_isolation_uint(&document, root, "adapterUid", &scalar,
            error, error_size) != 0 || scalar != expected->adapter_uid) goto identity_rejected;
    result->adapter_uid = (uint32_t)scalar;
    if (pf_tq_isolation_uint(&document, root, "adapterGid", &scalar,
            error, error_size) != 0 || scalar != expected->adapter_gid) goto identity_rejected;
    result->adapter_gid = (uint32_t)scalar;
    if (pf_tq_isolation_uint(&document, root, "serviceUid", &scalar,
            error, error_size) != 0 || scalar != expected->service_uid) goto identity_rejected;
    result->service_uid = (uint32_t)scalar;
    if (pf_tq_isolation_uint(&document, root, "serviceGid", &scalar,
            error, error_size) != 0 || scalar != expected->service_gid) goto identity_rejected;
    result->service_gid = (uint32_t)scalar;
    if (!pf_tq_isolation_linux_id(result->adapter_uid) ||
            !pf_tq_isolation_linux_id(result->adapter_gid) ||
            !pf_tq_isolation_linux_id(result->service_uid) ||
            !pf_tq_isolation_linux_id(result->service_gid) ||
            result->adapter_uid == result->service_uid ||
            result->adapter_gid == result->service_gid) goto identity_rejected;
    uid_inside[0] = result->adapter_uid < result->service_uid
        ? result->adapter_uid : result->service_uid;
    uid_inside[1] = result->adapter_uid < result->service_uid
        ? result->service_uid : result->adapter_uid;
    gid_inside[0] = result->adapter_gid < result->service_gid
        ? result->adapter_gid : result->service_gid;
    gid_inside[1] = result->adapter_gid < result->service_gid
        ? result->service_gid : result->adapter_gid;
    if (pf_tq_isolation_map_parse(&document,
            pf_tq_isolation_field(&document, root, "uidMap"), uid_inside,
            result->uid_map, error, error_size) != 0 ||
            pf_tq_isolation_map_parse(&document,
                pf_tq_isolation_field(&document, root, "gidMap"), gid_inside,
                result->gid_map, error, error_size) != 0) goto cleanup;
    outside[0] = result->uid_map[0].outside_id;
    outside[1] = result->uid_map[1].outside_id;
    outside[2] = result->gid_map[0].outside_id;
    outside[3] = result->gid_map[1].outside_id;
    for (size_t left = 0U; left < 4U; ++left) {
        for (size_t right = left + 1U; right < 4U; ++right) {
            if (outside[left] == outside[right]) {
                (void)pf_tq_isolation_error(error, error_size,
                    "isolation-policy outside IDs must be four distinct values");
                goto cleanup;
            }
        }
    }

    if (pf_tq_isolation_mounts_parse(&document,
            pf_tq_isolation_field(&document, root, "serviceMounts"), 0,
            result->service_proc_root, result->durable_state_root,
            result->seed_root, &result->service_mounts,
            &result->service_mount_count, error, error_size) != 0 ||
            pf_tq_isolation_mounts_parse(&document,
                pf_tq_isolation_field(&document, root, "adapterMounts"), 1,
                result->service_proc_root, result->durable_state_root,
                result->seed_root, &result->adapter_mounts,
                &result->adapter_mount_count, error, error_size) != 0 ||
            pf_tq_isolation_fd_roles_parse(&document,
                pf_tq_isolation_field(&document, root, "fdRoles"), expected,
                result, error, error_size) != 0) goto cleanup;

    if (pf_tq_isolation_string_exact(&document, root, "socketDomain", "AF_UNIX",
            error, error_size) != 0 ||
            pf_tq_isolation_string_exact(&document, root, "socketType",
                "SOCK_SEQPACKET", error, error_size) != 0 ||
            pf_tq_isolation_string_exact(&document, root, "socketCreation",
                "socketpair", error, error_size) != 0 ||
            pf_tq_isolation_string_exact(&document, root, "socketSendFlags",
                "MSG_NOSIGNAL", error, error_size) != 0 ||
            pf_tq_isolation_bool_exact(&document, root, "passCredentials", 1,
                error, error_size) != 0 ||
            pf_tq_isolation_uint_exact(&document, root,
                "requestedSocketBufferBytes", 4194304U,
                error, error_size) != 0 ||
            pf_tq_isolation_uint_exact(&document, root,
                "minimumEffectiveSocketBufferBytes", 8388608U,
                error, error_size) != 0 ||
            pf_tq_isolation_uint_exact(&document, root, "maximumFrameBytes",
                4194304U, error, error_size) != 0 ||
            pf_tq_isolation_uint_exact(&document, root,
                "maximumTerminalAcceptances", 1U, error, error_size) != 0 ||
            pf_tq_isolation_string_exact(&document, root, "execOperation",
                "execveat-at-empty-path", error, error_size) != 0 ||
            pf_tq_isolation_bool_exact(&document, root, "staticElfRequired", 1,
                error, error_size) != 0 ||
            pf_tq_isolation_capabilities_exact(&document, root,
                "preSeedCapabilities", preseed,
                sizeof(preseed) / sizeof(preseed[0]), error, error_size) != 0 ||
            pf_tq_isolation_capabilities_exact(&document, root,
                "custodyCapabilities", custody,
                sizeof(custody) / sizeof(custody[0]), error, error_size) != 0 ||
            pf_tq_isolation_capabilities_exact(&document, root,
                "adapterCapabilities", NULL, 0U, error, error_size) != 0 ||
            pf_tq_isolation_capabilities_exact(&document, root,
                "finalServiceCapabilities", NULL, 0U, error, error_size) != 0) {
        goto cleanup;
    }
    if (pf_tq_isolation_uint(&document, root, "serviceExecutableFd", &scalar,
            error, error_size) != 0 || scalar > INT_MAX ||
            (int)scalar != result->fd_roles[
                expected->service_executable_role_index].fd) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy serviceExecutableFd/role mismatch");
        goto cleanup;
    }
    result->service_executable_fd = (int)scalar;
    array = pf_tq_isolation_field(&document, root, "serviceArgv");
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count != 1U ||
            !pf_tq_jcs_string_equal_v2(&document,
                pf_tq_jcs_array_at_v2(&document, array, 0U),
                "proof-forge-taskqualification-store-v2")) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy serviceArgv mismatch");
        goto cleanup;
    }
    array = pf_tq_isolation_field(&document, root, "serviceEnvironment");
    if (array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            array->child_count != 0U) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy serviceEnvironment must be empty");
        goto cleanup;
    }
    if (pf_tq_isolation_seccomp_parse(&document, root, expected, result,
            seccomp_starts, seccomp_sizes, error, error_size) != 0) goto cleanup;

    result->canonical_bytes = malloc(size);
    if (result->canonical_bytes == NULL) {
        (void)pf_tq_isolation_error(error, error_size,
            "isolation-policy canonical-byte allocation failed");
        goto cleanup;
    }
    memcpy(result->canonical_bytes, bytes, size);
    result->canonical_size = size;
    for (size_t index = 0U; index < 3U; ++index) {
        result->seccomp_policies[index].bytes =
            result->canonical_bytes + seccomp_starts[index];
        result->seccomp_policies[index].size = seccomp_sizes[index];
    }
    status = 0;
    goto cleanup;

identity_rejected:
    (void)pf_tq_isolation_error(error, error_size,
        "isolation-policy descriptor UID/GID join rejected");
cleanup:
    if (document_initialized) pf_tq_jcs_free_v2(&document);
    if (status != 0) pf_tq_isolation_policy_free_v2(result);
    return status;
}
