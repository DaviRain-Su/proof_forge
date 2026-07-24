#define _GNU_SOURCE
#include "task_qualification_pre_exec_payloads_v2.h"

#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define PF_TQ_PRE_EXEC_DESCRIPTOR_VERSION_V2 "2.0.0"
#define PF_TQ_PRE_EXEC_DESCRIPTOR_ID_PREFIX_V2 \
    "task-qualification-store-service-"
#define PF_TQ_PRE_EXEC_ISOLATION_SCHEMA_V2 \
    "proof-forge.task-qualification-store-isolation-policy.v2"
#define PF_TQ_PRE_EXEC_ISOLATION_VERSION_V2 "2.0.0"
#define PF_TQ_PRE_EXEC_ISOLATION_ID_PREFIX_V2 \
    "task-qualification-store-isolation-"

static int pf_tq_pre_exec_payloads_error(
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

static void pf_tq_pre_exec_payloads_clear_error(
    char *error,
    size_t error_size
) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_pre_exec_payloads_free_v2(pf_tq_pre_exec_payloads_v2 *payloads) {
    if (payloads == NULL) return;
    pf_tq_artifact_payload_free_v2(&payloads->service_executable);
    pf_tq_artifact_payload_free_v2(&payloads->adapter_closure);
    pf_tq_artifact_payload_free_v2(&payloads->adapter_build_policy);
    memset(payloads, 0, sizeof(*payloads));
}

static int pf_tq_pre_exec_fixed_string(
    const char *value,
    size_t capacity
) {
    return value != NULL && memchr(value, '\0', capacity) != NULL;
}

static int pf_tq_pre_exec_content_ref_shape(
    const pf_tq_wire_content_ref_v2 *reference
) {
    return reference != NULL &&
        pf_tq_pre_exec_fixed_string(reference->schema,
            sizeof(reference->schema)) &&
        pf_tq_pre_exec_fixed_string(reference->id, sizeof(reference->id)) &&
        pf_tq_pre_exec_fixed_string(reference->version,
            sizeof(reference->version));
}

static int pf_tq_pre_exec_content_ref_exact(
    const pf_tq_wire_content_ref_v2 *actual,
    const pf_tq_wire_content_ref_v2 *expected
) {
    return pf_tq_pre_exec_content_ref_shape(actual) &&
        pf_tq_pre_exec_content_ref_shape(expected) &&
        strcmp(actual->schema, expected->schema) == 0 &&
        strcmp(actual->id, expected->id) == 0 &&
        strcmp(actual->version, expected->version) == 0 &&
        memcmp(actual->digest, expected->digest, 32U) == 0;
}

static int pf_tq_pre_exec_ref_render(
    pf_tq_wire_content_ref_v2 *reference,
    const char *schema,
    const char *identifier,
    const char *version,
    const unsigned char digest[32],
    char *error,
    size_t error_size
) {
    int schema_size;
    int id_size;
    int version_size;
    memset(reference, 0, sizeof(*reference));
    schema_size = snprintf(reference->schema, sizeof(reference->schema),
        "%s", schema);
    id_size = snprintf(reference->id, sizeof(reference->id),
        "%s", identifier);
    version_size = snprintf(reference->version, sizeof(reference->version),
        "%s", version);
    if (schema_size <= 0 ||
            (size_t)schema_size >= sizeof(reference->schema) ||
            id_size <= 0 || (size_t)id_size >= sizeof(reference->id) ||
            version_size <= 0 ||
            (size_t)version_size >= sizeof(reference->version)) {
        return pf_tq_pre_exec_payloads_error(error, error_size,
            "pre-exec payload ContentRef rendering failed");
    }
    memcpy(reference->digest, digest, 32U);
    return 0;
}

static int pf_tq_pre_exec_carrier_join(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_v2 *handoff,
    const pf_tq_descriptor_v2 *descriptor,
    char *error,
    size_t error_size
) {
    pf_tq_wire_content_ref_v2 descriptor_ref;
    pf_tq_wire_content_ref_v2 isolation_ref;
    char descriptor_id[PF_TQ_DESCRIPTOR_V2_ID_BYTES];
    char isolation_id[PF_TQ_DESCRIPTOR_V2_ID_BYTES];
    int descriptor_id_size;
    int isolation_id_size;
    if (policy == NULL || handoff == NULL || descriptor == NULL ||
            policy->canonical_bytes == NULL || policy->canonical_size == 0U ||
            policy->canonical_size > PF_TQ_ISOLATION_POLICY_V2_MAX_BYTES ||
            handoff->canonical_bytes == NULL || handoff->canonical_size == 0U ||
            handoff->canonical_size > PF_TQ_HANDOFF_V2_MAX_BYTES ||
            descriptor->canonical_bytes == NULL ||
            descriptor->canonical_size == 0U ||
            descriptor->canonical_size > PF_TQ_DESCRIPTOR_V2_MAX_BYTES ||
            !pf_tq_pre_exec_fixed_string(
                policy->task_id, sizeof(policy->task_id)) ||
            !pf_tq_pre_exec_fixed_string(
                policy->operation, sizeof(policy->operation)) ||
            !pf_tq_pre_exec_fixed_string(
                policy->run_id, sizeof(policy->run_id)) ||
            !pf_tq_pre_exec_fixed_string(
                policy->nonce, sizeof(policy->nonce)) ||
            !pf_tq_pre_exec_fixed_string(
                handoff->task_id, sizeof(handoff->task_id)) ||
            !pf_tq_pre_exec_fixed_string(
                handoff->operation, sizeof(handoff->operation)) ||
            !pf_tq_pre_exec_fixed_string(
                handoff->run_id, sizeof(handoff->run_id)) ||
            !pf_tq_pre_exec_fixed_string(
                handoff->nonce, sizeof(handoff->nonce)) ||
            !pf_tq_pre_exec_fixed_string(
                descriptor->id, sizeof(descriptor->id)) ||
            strcmp(policy->task_id, handoff->task_id) != 0 ||
            strcmp(policy->operation, handoff->operation) != 0 ||
            strcmp(policy->run_id, handoff->run_id) != 0 ||
            strcmp(policy->nonce, handoff->nonce) != 0) {
        return pf_tq_pre_exec_payloads_error(error, error_size,
            "pre-exec payload parsed carrier/tuple join rejected");
    }
    descriptor_id_size = snprintf(descriptor_id, sizeof(descriptor_id),
        "%s%s", PF_TQ_PRE_EXEC_DESCRIPTOR_ID_PREFIX_V2, handoff->run_id);
    isolation_id_size = snprintf(isolation_id, sizeof(isolation_id),
        "%s%s", PF_TQ_PRE_EXEC_ISOLATION_ID_PREFIX_V2, handoff->run_id);
    if (descriptor_id_size <= 0 ||
            (size_t)descriptor_id_size >= sizeof(descriptor_id) ||
            isolation_id_size <= 0 ||
            (size_t)isolation_id_size >= sizeof(isolation_id) ||
            strcmp(descriptor->id, descriptor_id) != 0 ||
            pf_tq_pre_exec_ref_render(&descriptor_ref,
                PF_TQ_DESCRIPTOR_V2_SCHEMA, descriptor_id,
                PF_TQ_PRE_EXEC_DESCRIPTOR_VERSION_V2, descriptor->digest,
                error, error_size) != 0 ||
            !pf_tq_pre_exec_content_ref_exact(
                &handoff->authority_store_service, &descriptor_ref) ||
            pf_tq_pre_exec_ref_render(&isolation_ref,
                PF_TQ_PRE_EXEC_ISOLATION_SCHEMA_V2, isolation_id,
                PF_TQ_PRE_EXEC_ISOLATION_VERSION_V2, policy->digest,
                error, error_size) != 0 ||
            !pf_tq_pre_exec_content_ref_exact(
                &descriptor->isolation_policy, &isolation_ref)) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_pre_exec_payloads_error(error, error_size,
                "pre-exec payload descriptor/isolation ref join rejected");
        }
        return -1;
    }
    if (policy->adapter_uid != descriptor->adapter_uid ||
            policy->adapter_gid != descriptor->adapter_gid ||
            policy->service_uid != descriptor->service_uid ||
            policy->service_gid != descriptor->service_gid ||
            policy->user_namespace.device !=
                descriptor->user_namespace.device ||
            policy->user_namespace.inode !=
                descriptor->user_namespace.inode ||
            policy->seed_root.device != descriptor->seed_root.device ||
            policy->seed_root.inode != descriptor->seed_root.inode) {
        return pf_tq_pre_exec_payloads_error(error, error_size,
            "pre-exec payload descriptor/isolation identity join rejected");
    }
    if (pf_tq_fd_manifest_validate_policy_v2(
            policy, &handoff->channels, error, error_size) != 0) return -1;
    return 0;
}

static int pf_tq_pre_exec_consume_role(
    const pf_tq_isolation_policy_v2 *policy,
    const char *role,
    const pf_tq_wire_content_ref_v2 *reference,
    pf_tq_artifact_payload_v2 *payload,
    char *error,
    size_t error_size
) {
    int fd = -1;
    int close_on_exec = -1;
    int expected_flags;
    if (pf_tq_fd_manifest_lookup_v2(policy, "service", "pre-exec", role,
            &fd, &close_on_exec, error, error_size) != 0) return -1;
    if (close_on_exec != 0 && close_on_exec != 1) {
        return pf_tq_pre_exec_payloads_error(error, error_size,
            "pre-exec payload manifest close-on-exec value rejected");
    }
    expected_flags = close_on_exec ? FD_CLOEXEC : 0;
    if (pf_tq_artifact_payload_verify_fd_v2(fd, expected_flags, reference,
            payload, error, error_size) != 0) return -1;
    return 0;
}

static int pf_tq_pre_exec_inode_alias(
    const pf_tq_artifact_payload_v2 *left,
    const pf_tq_artifact_payload_v2 *right
) {
    return left->device == right->device && left->inode == right->inode;
}

int pf_tq_pre_exec_payloads_consume_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_v2 *handoff,
    const pf_tq_descriptor_v2 *descriptor,
    pf_tq_pre_exec_payloads_v2 *result,
    char *error,
    size_t error_size
) {
    pf_tq_pre_exec_payloads_v2 payloads;
    int outcome = -1;
    memset(&payloads, 0, sizeof(payloads));
    pf_tq_pre_exec_payloads_clear_error(error, error_size);
    if (result != NULL) memset(result, 0, sizeof(*result));
    if (result == NULL || policy == NULL || handoff == NULL ||
            descriptor == NULL) {
        return pf_tq_pre_exec_payloads_error(error, error_size,
            "pre-exec payload API arguments rejected");
    }
    if (pf_tq_pre_exec_carrier_join(policy, handoff, descriptor,
            error, error_size) != 0) return -1;
    if (pf_tq_pre_exec_consume_role(policy, "adapter-build-policy",
            &handoff->adapter.build_policy,
            &payloads.adapter_build_policy, error, error_size) != 0 ||
            pf_tq_pre_exec_consume_role(policy, "adapter-closure",
                &handoff->adapter.closure,
                &payloads.adapter_closure, error, error_size) != 0 ||
            pf_tq_pre_exec_consume_role(policy, "service-executable",
                &descriptor->verifier.executable,
                &payloads.service_executable, error, error_size) != 0) {
        goto cleanup;
    }
    if ((payloads.service_executable.mode &
                (S_IXUSR | S_IXGRP | S_IXOTH)) == 0 ||
            pf_tq_pre_exec_inode_alias(&payloads.adapter_build_policy,
                &payloads.adapter_closure) ||
            pf_tq_pre_exec_inode_alias(&payloads.adapter_build_policy,
                &payloads.service_executable) ||
            pf_tq_pre_exec_inode_alias(&payloads.adapter_closure,
                &payloads.service_executable)) {
        (void)pf_tq_pre_exec_payloads_error(error, error_size,
            "pre-exec payload executable mode/inode identity rejected");
        goto cleanup;
    }
    *result = payloads;
    memset(&payloads, 0, sizeof(payloads));
    pf_tq_pre_exec_payloads_clear_error(error, error_size);
    outcome = 0;
cleanup:
    pf_tq_pre_exec_payloads_free_v2(&payloads);
    return outcome;
}
