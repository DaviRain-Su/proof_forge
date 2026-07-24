#define _GNU_SOURCE
/* Test-owned driver for service pre-exec raw payload FD consumption. */
#include "task_qualification_pre_exec_payloads_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define PF_TQ_TEST_AUTHORITY_POLICY_FD 100
#define PF_TQ_TEST_AUTHORITY_STORE_FD 101
#define PF_TQ_TEST_CANDIDATE_ARCHIVE_FD 102
#define PF_TQ_TEST_PROVENANCE_BUNDLE_FD 103
#define PF_TQ_TEST_TRUSTED_CLOCK_FD 104
#define PF_TQ_TEST_DURABLE_ROOT_FD 110
#define PF_TQ_TEST_HANDOFF_FD 111
#define PF_TQ_TEST_ISOLATION_POLICY_FD 112
#define PF_TQ_TEST_PROC_ROOT_FD 113
#define PF_TQ_TEST_SEED_ROLE_0_FD 114
#define PF_TQ_TEST_SEED_ROLE_1_FD 115
#define PF_TQ_TEST_SEED_ROLE_2_FD 116
#define PF_TQ_TEST_SEED_SERVICE_FD 117
#define PF_TQ_TEST_SERVICE_ENDPOINT_FD 118
#define PF_TQ_TEST_TRANSITION_FD 119

static unsigned char pf_tq_test_canonical[] = {'{', '}'};

static void pf_tq_test_fail(const char *where) {
    (void)fprintf(stderr, "PF-PRE-EXEC-PAYLOADS-DRIVER:%s:errno=%d\n",
        where, errno);
    exit(111);
}

static int pf_tq_test_hex_digit(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static int pf_tq_test_hex(const char *text, unsigned char output[32]) {
    size_t index;
    if (text == NULL || strlen(text) != 64U) return -1;
    for (index = 0U; index < 32U; ++index) {
        int high = pf_tq_test_hex_digit((unsigned char)text[2U * index]);
        int low = pf_tq_test_hex_digit((unsigned char)text[2U * index + 1U]);
        if (high < 0 || low < 0) return -1;
        output[index] = (unsigned char)((unsigned)high * 16U + (unsigned)low);
    }
    return 0;
}

static void pf_tq_test_ref(
    pf_tq_wire_content_ref_v2 *reference,
    const char *identifier,
    const char *version,
    const unsigned char digest[32]
) {
    int schema_size;
    int id_size;
    int version_size;
    memset(reference, 0, sizeof(*reference));
    schema_size = snprintf(reference->schema, sizeof(reference->schema), "%s",
        PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA);
    id_size = snprintf(reference->id, sizeof(reference->id), "%s", identifier);
    version_size = snprintf(reference->version, sizeof(reference->version), "%s",
        version);
    if (schema_size <= 0 || (size_t)schema_size >= sizeof(reference->schema) ||
            id_size <= 0 || (size_t)id_size >= sizeof(reference->id) ||
            version_size <= 0 ||
            (size_t)version_size >= sizeof(reference->version)) {
        pf_tq_test_fail("content-ref-render");
    }
    memcpy(reference->digest, digest, 32U);
}

static void pf_tq_test_fixed_ref(
    pf_tq_wire_content_ref_v2 *reference,
    const char *schema,
    const char *identifier,
    const char *version,
    unsigned char seed
) {
    int schema_size;
    int id_size;
    int version_size;
    memset(reference, 0, sizeof(*reference));
    schema_size = snprintf(reference->schema, sizeof(reference->schema), "%s",
        schema);
    id_size = snprintf(reference->id, sizeof(reference->id), "%s", identifier);
    version_size = snprintf(reference->version, sizeof(reference->version), "%s",
        version);
    if (schema_size <= 0 || (size_t)schema_size >= sizeof(reference->schema) ||
            id_size <= 0 || (size_t)id_size >= sizeof(reference->id) ||
            version_size <= 0 ||
            (size_t)version_size >= sizeof(reference->version)) {
        pf_tq_test_fail("fixed-ref-render");
    }
    memset(reference->digest, seed, sizeof(reference->digest));
}

static pf_tq_handoff_channels_v2 pf_tq_test_channels(void) {
    pf_tq_handoff_channels_v2 channels;
    channels.authority_policy_fd = PF_TQ_TEST_AUTHORITY_POLICY_FD;
    channels.authority_store_fd = PF_TQ_TEST_AUTHORITY_STORE_FD;
    channels.candidate_archive_fd = PF_TQ_TEST_CANDIDATE_ARCHIVE_FD;
    channels.provenance_bundle_fd = PF_TQ_TEST_PROVENANCE_BUNDLE_FD;
    channels.trusted_clock_fd = PF_TQ_TEST_TRUSTED_CLOCK_FD;
    return channels;
}

static int pf_tq_test_adapter_fd(const char *role) {
    if (strcmp(role, "authority-policy") == 0) {
        return PF_TQ_TEST_AUTHORITY_POLICY_FD;
    }
    if (strcmp(role, "authority-store") == 0) {
        return PF_TQ_TEST_AUTHORITY_STORE_FD;
    }
    if (strcmp(role, "candidate-archive") == 0) {
        return PF_TQ_TEST_CANDIDATE_ARCHIVE_FD;
    }
    if (strcmp(role, "provenance-bundle") == 0) {
        return PF_TQ_TEST_PROVENANCE_BUNDLE_FD;
    }
    if (strcmp(role, "trusted-clock") == 0) {
        return PF_TQ_TEST_TRUSTED_CLOCK_FD;
    }
    return -1;
}

static int pf_tq_test_service_fd(
    const char *role,
    int build_policy_fd,
    int closure_fd,
    int executable_fd
) {
    if (strcmp(role, "adapter-build-policy") == 0) return build_policy_fd;
    if (strcmp(role, "adapter-closure") == 0) return closure_fd;
    if (strcmp(role, "authority-policy") == 0) {
        return PF_TQ_TEST_AUTHORITY_POLICY_FD;
    }
    if (strcmp(role, "durable-root") == 0) return PF_TQ_TEST_DURABLE_ROOT_FD;
    if (strcmp(role, "handoff") == 0) return PF_TQ_TEST_HANDOFF_FD;
    if (strcmp(role, "isolation-policy") == 0) {
        return PF_TQ_TEST_ISOLATION_POLICY_FD;
    }
    if (strcmp(role, "proc-root") == 0) return PF_TQ_TEST_PROC_ROOT_FD;
    if (strcmp(role, "seed-role-0") == 0) return PF_TQ_TEST_SEED_ROLE_0_FD;
    if (strcmp(role, "seed-role-1") == 0) return PF_TQ_TEST_SEED_ROLE_1_FD;
    if (strcmp(role, "seed-role-2") == 0) return PF_TQ_TEST_SEED_ROLE_2_FD;
    if (strcmp(role, "seed-service") == 0) return PF_TQ_TEST_SEED_SERVICE_FD;
    if (strcmp(role, "service-endpoint") == 0) {
        return PF_TQ_TEST_SERVICE_ENDPOINT_FD;
    }
    if (strcmp(role, "service-executable") == 0) return executable_fd;
    if (strcmp(role, "transition") == 0) return PF_TQ_TEST_TRANSITION_FD;
    return -1;
}

static void pf_tq_test_policy(
    pf_tq_isolation_policy_v2 *policy,
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT],
    int build_policy_fd,
    int closure_fd,
    int executable_fd
) {
    pf_tq_isolation_expectation_v2 expectation;
    char error[PF_TQ_PRE_EXEC_PAYLOADS_V2_ERROR_BYTES];
    size_t index;
    memset(policy, 0, sizeof(*policy));
    memset(roles, 0, PF_TQ_FD_MANIFEST_V2_COUNT * sizeof(*roles));
    memset(&expectation, 0, sizeof(expectation));
    if (pf_tq_fd_manifest_bind_expectation_v2(
            &expectation, error, sizeof(error)) != 0 || error[0] != '\0') {
        pf_tq_test_fail("manifest-bind");
    }
    for (index = 0U; index < expectation.fd_manifest_count; ++index) {
        const pf_tq_isolation_fd_manifest_v2 *manifest =
            &expectation.fd_manifest[index];
        int fd = strcmp(manifest->process, "adapter") == 0
            ? pf_tq_test_adapter_fd(manifest->role)
            : pf_tq_test_service_fd(manifest->role, build_policy_fd,
                closure_fd, executable_fd);
        if (fd <= 2 || snprintf(roles[index].process,
                sizeof(roles[index].process), "%s", manifest->process) <= 0 ||
                snprintf(roles[index].stage,
                    sizeof(roles[index].stage), "%s", manifest->stage) <= 0 ||
                snprintf(roles[index].role,
                    sizeof(roles[index].role), "%s", manifest->role) <= 0) {
            pf_tq_test_fail("manifest-row");
        }
        roles[index].fd = fd;
        roles[index].close_on_exec = manifest->close_on_exec;
    }
    policy->canonical_bytes = pf_tq_test_canonical;
    policy->canonical_size = sizeof(pf_tq_test_canonical);
    memset(policy->digest, 0x55, sizeof(policy->digest));
    (void)snprintf(policy->task_id, sizeof(policy->task_id), "TASK-D1-01");
    (void)snprintf(policy->operation, sizeof(policy->operation),
        "task-qualification");
    (void)snprintf(policy->run_id, sizeof(policy->run_id), "run-v2");
    (void)snprintf(policy->nonce, sizeof(policy->nonce), "nonce-v2");
    policy->adapter_uid = 1001U;
    policy->adapter_gid = 1003U;
    policy->service_uid = 1002U;
    policy->service_gid = 1004U;
    policy->user_namespace.device = 10U;
    policy->user_namespace.inode = 11U;
    policy->seed_root.device = 20U;
    policy->seed_root.inode = 23U;
    policy->fd_roles = roles;
    policy->fd_role_count = expectation.fd_manifest_count;
    policy->service_executable_fd = executable_fd;
}

static void pf_tq_test_context(
    pf_tq_handoff_v2 *handoff,
    pf_tq_descriptor_v2 *descriptor,
    const unsigned char build_digest[32],
    const unsigned char closure_digest[32],
    const unsigned char executable_digest[32]
) {
    memset(handoff, 0, sizeof(*handoff));
    memset(descriptor, 0, sizeof(*descriptor));
    handoff->canonical_bytes = pf_tq_test_canonical;
    handoff->canonical_size = sizeof(pf_tq_test_canonical);
    (void)snprintf(handoff->task_id, sizeof(handoff->task_id), "TASK-D1-01");
    (void)snprintf(handoff->operation, sizeof(handoff->operation),
        "task-qualification");
    (void)snprintf(handoff->run_id, sizeof(handoff->run_id), "run-v2");
    (void)snprintf(handoff->nonce, sizeof(handoff->nonce), "nonce-v2");
    (void)snprintf(handoff->adapter.id, sizeof(handoff->adapter.id),
        "protected-adapter-v2");
    pf_tq_test_fixed_ref(&handoff->adapter.executable,
        PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA, "adapter-executable-v2",
        "1.0.0", 0x30U);
    pf_tq_test_ref(&handoff->adapter.closure, "adapter-closure-v2",
        "1.0.0", closure_digest);
    pf_tq_test_ref(&handoff->adapter.build_policy, "adapter-build-policy-v2",
        "1.0.0", build_digest);
    handoff->channels = pf_tq_test_channels();

    descriptor->canonical_bytes = pf_tq_test_canonical;
    descriptor->canonical_size = sizeof(pf_tq_test_canonical);
    memset(descriptor->digest, 0x44, sizeof(descriptor->digest));
    (void)snprintf(descriptor->id, sizeof(descriptor->id),
        "task-qualification-store-service-run-v2");
    (void)snprintf(descriptor->verifier.id, sizeof(descriptor->verifier.id),
        "authority-store-v2");
    pf_tq_test_ref(&descriptor->verifier.executable,
        "authority-store-executable-v2", "1.0.0", executable_digest);
    pf_tq_test_fixed_ref(&descriptor->verifier.closure,
        PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA, "authority-store-closure-v2",
        "1.0.0", 0x31U);
    pf_tq_test_fixed_ref(&descriptor->verifier.build_policy,
        PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA, "authority-store-build-policy-v2",
        "1.0.0", 0x32U);
    descriptor->adapter_uid = 1001U;
    descriptor->adapter_gid = 1003U;
    descriptor->service_uid = 1002U;
    descriptor->service_gid = 1004U;
    descriptor->user_namespace.device = 10U;
    descriptor->user_namespace.inode = 11U;
    descriptor->seed_root.device = 20U;
    descriptor->seed_root.inode = 23U;
    pf_tq_test_fixed_ref(&descriptor->isolation_policy,
        "proof-forge.task-qualification-store-isolation-policy.v2",
        "task-qualification-store-isolation-run-v2", "2.0.0", 0x55U);
    pf_tq_test_fixed_ref(&handoff->authority_store_service,
        PF_TQ_DESCRIPTOR_V2_SCHEMA,
        "task-qualification-store-service-run-v2", "2.0.0", 0x44U);
}

static int pf_tq_test_find_role(
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT],
    const char *process,
    const char *stage,
    const char *role
) {
    size_t index;
    for (index = 0U; index < PF_TQ_FD_MANIFEST_V2_COUNT; ++index) {
        if (strcmp(roles[index].process, process) == 0 &&
                strcmp(roles[index].stage, stage) == 0 &&
                strcmp(roles[index].role, role) == 0) return (int)index;
    }
    return -1;
}

static int pf_tq_test_run(
    const char *expectation,
    const char *mutation,
    const char *build_path,
    const char *closure_path,
    const char *executable_path,
    const unsigned char build_digest[32],
    const unsigned char closure_digest[32],
    const unsigned char executable_digest[32],
    const unsigned char build_plain[32],
    const unsigned char closure_plain[32],
    const unsigned char executable_plain[32]
) {
    pf_tq_isolation_policy_v2 policy;
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT];
    pf_tq_handoff_v2 handoff;
    pf_tq_descriptor_v2 descriptor;
    pf_tq_pre_exec_payloads_v2 payloads;
    char error[PF_TQ_PRE_EXEC_PAYLOADS_V2_ERROR_BYTES];
    int build_flags = O_RDONLY | O_NOFOLLOW;
    int closure_flags = O_RDONLY | O_NOFOLLOW;
    int executable_flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC;
    int build_fd = -1;
    int closure_fd = -1;
    int executable_fd = -1;
    int role_index;
    int result;
    off_t offsets_before[3];
    off_t offsets_after[3];
    struct stat statuses[3];
    memset(&payloads, 0, sizeof(payloads));
    if (strcmp(mutation, "build-readwrite") == 0) {
        build_flags = O_RDWR | O_NOFOLLOW;
    }
    if (strcmp(mutation, "closure-cloexec") == 0) closure_flags |= O_CLOEXEC;
    if (strcmp(mutation, "service-no-cloexec") == 0) {
        executable_flags &= ~O_CLOEXEC;
    }
    build_fd = open(build_path, build_flags);
    closure_fd = open(closure_path, closure_flags);
    executable_fd = open(executable_path, executable_flags);
    if (build_fd <= 2 || closure_fd <= 2 || executable_fd <= 2 ||
            build_fd == closure_fd || build_fd == executable_fd ||
            closure_fd == executable_fd || fstat(build_fd, &statuses[0]) != 0 ||
            fstat(closure_fd, &statuses[1]) != 0 ||
            fstat(executable_fd, &statuses[2]) != 0) {
        pf_tq_test_fail("open-or-stat");
    }
    pf_tq_test_policy(&policy, roles, build_fd, closure_fd, executable_fd);
    pf_tq_test_context(&handoff, &descriptor, build_digest,
        closure_digest, executable_digest);

    if (strcmp(mutation, "build-stale-ref") == 0) {
        handoff.adapter.build_policy.digest[0] ^= 1U;
    } else if (strcmp(mutation, "closure-stale-ref") == 0) {
        handoff.adapter.closure.digest[0] ^= 1U;
    } else if (strcmp(mutation, "service-stale-ref") == 0) {
        descriptor.verifier.executable.digest[0] ^= 1U;
    } else if (strcmp(mutation, "service-schema") == 0) {
        (void)snprintf(descriptor.verifier.executable.schema,
            sizeof(descriptor.verifier.executable.schema),
            "proof-forge.host-observation.v1");
    } else if (strcmp(mutation, "closure-version") == 0) {
        (void)snprintf(handoff.adapter.closure.version,
            sizeof(handoff.adapter.closure.version), "01.0.0");
    } else if (strcmp(mutation, "build-id") == 0) {
        (void)snprintf(handoff.adapter.build_policy.id,
            sizeof(handoff.adapter.build_policy.id), "Bad/Id");
    } else if (strcmp(mutation, "manifest-fd") == 0) {
        role_index = pf_tq_test_find_role(roles, "service", "pre-exec",
            "adapter-closure");
        if (role_index < 0) pf_tq_test_fail("manifest-role-find");
        roles[(size_t)role_index].fd = build_fd;
    } else if (strcmp(mutation, "descriptor-ref") == 0) {
        handoff.authority_store_service.digest[0] ^= 1U;
    } else if (strcmp(mutation, "isolation-ref") == 0) {
        descriptor.isolation_policy.digest[0] ^= 1U;
    } else if (strcmp(mutation, "tuple") == 0) {
        (void)snprintf(policy.nonce, sizeof(policy.nonce), "other-nonce");
    } else if (strcmp(mutation, "descriptor-uid") == 0) {
        ++descriptor.service_uid;
    } else if (strcmp(mutation, "user-namespace") == 0) {
        ++descriptor.user_namespace.inode;
    } else if (strcmp(mutation, "seed-root") == 0) {
        ++descriptor.seed_root.device;
    } else if (strcmp(mutation, "canonical") == 0) {
        handoff.canonical_bytes = NULL;
        handoff.canonical_size = 0U;
    }

    offsets_before[0] = lseek(build_fd, 0, SEEK_CUR);
    offsets_before[1] = lseek(closure_fd, 0, SEEK_CUR);
    offsets_before[2] = lseek(executable_fd, 0, SEEK_CUR);
    result = pf_tq_pre_exec_payloads_consume_v2(
        &policy, &handoff, &descriptor, &payloads, error, sizeof(error));
    offsets_after[0] = lseek(build_fd, 0, SEEK_CUR);
    offsets_after[1] = lseek(closure_fd, 0, SEEK_CUR);
    offsets_after[2] = lseek(executable_fd, 0, SEEK_CUR);
    if (strcmp(expectation, "--accept") == 0) {
        if (result != 0 || error[0] != '\0' ||
                payloads.adapter_build_policy.bytes == NULL ||
                payloads.adapter_closure.bytes == NULL ||
                payloads.service_executable.bytes == NULL ||
                payloads.adapter_build_policy.size !=
                    (size_t)statuses[0].st_size ||
                payloads.adapter_closure.size !=
                    (size_t)statuses[1].st_size ||
                payloads.service_executable.size !=
                    (size_t)statuses[2].st_size ||
                memcmp(payloads.adapter_build_policy.plain_sha256,
                    build_plain, 32U) != 0 ||
                memcmp(payloads.adapter_closure.plain_sha256,
                    closure_plain, 32U) != 0 ||
                memcmp(payloads.service_executable.plain_sha256,
                    executable_plain, 32U) != 0) {
            pf_tq_pre_exec_payloads_free_v2(&payloads);
            return 1;
        }
    } else if (result == 0 || error[0] == '\0' ||
            payloads.adapter_build_policy.bytes != NULL ||
            payloads.adapter_build_policy.size != 0U ||
            payloads.adapter_closure.bytes != NULL ||
            payloads.adapter_closure.size != 0U ||
            payloads.service_executable.bytes != NULL ||
            payloads.service_executable.size != 0U) {
        pf_tq_pre_exec_payloads_free_v2(&payloads);
        return 1;
    }
    for (size_t index = 0U; index < 3U; ++index) {
        if (offsets_before[index] != 0 ||
                offsets_after[index] != offsets_before[index]) {
            pf_tq_pre_exec_payloads_free_v2(&payloads);
            return 1;
        }
    }
    pf_tq_pre_exec_payloads_free_v2(&payloads);
    if (payloads.adapter_build_policy.bytes != NULL ||
            payloads.adapter_closure.bytes != NULL ||
            payloads.service_executable.bytes != NULL ||
            close(executable_fd) != 0 || close(closure_fd) != 0 ||
            close(build_fd) != 0) return 1;
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_pre_exec_payloads_v2 payloads;
    char error[PF_TQ_PRE_EXEC_PAYLOADS_V2_ERROR_BYTES];
    int result;
    memset(&payloads, 0x5a, sizeof(payloads));
    result = pf_tq_pre_exec_payloads_consume_v2(
        NULL, NULL, NULL, &payloads, error, sizeof(error));
    pf_tq_pre_exec_payloads_free_v2(&payloads);
    return result != 0 && error[0] != '\0' &&
        payloads.adapter_build_policy.bytes == NULL &&
        payloads.adapter_closure.bytes == NULL &&
        payloads.service_executable.bytes == NULL ? 0 : 1;
}

int main(int argc, char **argv) {
    unsigned char digests[6][32];
    if (argc == 2 && strcmp(argv[1], "--invalid-input") == 0) {
        return pf_tq_test_invalid();
    }
    if (argc != 12 || (strcmp(argv[1], "--accept") != 0 &&
            strcmp(argv[1], "--reject") != 0)) return 2;
    for (size_t index = 0U; index < 6U; ++index) {
        if (pf_tq_test_hex(argv[6 + index], digests[index]) != 0) return 2;
    }
    return pf_tq_test_run(argv[1], argv[2], argv[3], argv[4], argv[5],
        digests[0], digests[1], digests[2], digests[3], digests[4],
        digests[5]);
}
