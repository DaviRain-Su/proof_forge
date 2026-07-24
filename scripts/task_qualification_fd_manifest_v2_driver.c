#define _GNU_SOURCE
/* Test-owned driver for the ADR-0021 production FD lifecycle owner. */
#include "task_qualification_fd_manifest_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PF_TQ_TEST_ADAPTER_AUTHORITY_POLICY_FD 10
#define PF_TQ_TEST_ADAPTER_AUTHORITY_STORE_FD 11
#define PF_TQ_TEST_ADAPTER_CANDIDATE_ARCHIVE_FD 12
#define PF_TQ_TEST_ADAPTER_PROVENANCE_BUNDLE_FD 13
#define PF_TQ_TEST_ADAPTER_TRUSTED_CLOCK_FD 14
#define PF_TQ_TEST_SERVICE_ADAPTER_BUILD_POLICY_FD 20
#define PF_TQ_TEST_SERVICE_ADAPTER_CLOSURE_FD 21
#define PF_TQ_TEST_SERVICE_DURABLE_ROOT_FD 22
#define PF_TQ_TEST_SERVICE_HANDOFF_FD 23
#define PF_TQ_TEST_SERVICE_ISOLATION_POLICY_FD 24
#define PF_TQ_TEST_SERVICE_PROC_ROOT_FD 25
#define PF_TQ_TEST_SERVICE_SEED_ROLE_0_FD 26
#define PF_TQ_TEST_SERVICE_SEED_ROLE_1_FD 27
#define PF_TQ_TEST_SERVICE_SEED_ROLE_2_FD 28
#define PF_TQ_TEST_SERVICE_SEED_SERVICE_FD 29
#define PF_TQ_TEST_SERVICE_ENDPOINT_FD 30
#define PF_TQ_TEST_SERVICE_EXECUTABLE_FD 31
#define PF_TQ_TEST_SERVICE_TRANSITION_FD 32

static void pf_tq_test_fail(const char *message) {
    (void)fprintf(stderr, "PF-FD-MANIFEST-DRIVER:%s:errno=%d\n", message, errno);
    exit(111);
}

static int pf_tq_test_service_fd(const char *role) {
    if (strcmp(role, "adapter-build-policy") == 0) {
        return PF_TQ_TEST_SERVICE_ADAPTER_BUILD_POLICY_FD;
    }
    if (strcmp(role, "adapter-closure") == 0) {
        return PF_TQ_TEST_SERVICE_ADAPTER_CLOSURE_FD;
    }
    if (strcmp(role, "authority-policy") == 0) {
        return PF_TQ_TEST_ADAPTER_AUTHORITY_POLICY_FD;
    }
    if (strcmp(role, "durable-root") == 0) {
        return PF_TQ_TEST_SERVICE_DURABLE_ROOT_FD;
    }
    if (strcmp(role, "handoff") == 0) {
        return PF_TQ_TEST_SERVICE_HANDOFF_FD;
    }
    if (strcmp(role, "isolation-policy") == 0) {
        return PF_TQ_TEST_SERVICE_ISOLATION_POLICY_FD;
    }
    if (strcmp(role, "proc-root") == 0) {
        return PF_TQ_TEST_SERVICE_PROC_ROOT_FD;
    }
    if (strcmp(role, "seed-role-0") == 0) {
        return PF_TQ_TEST_SERVICE_SEED_ROLE_0_FD;
    }
    if (strcmp(role, "seed-role-1") == 0) {
        return PF_TQ_TEST_SERVICE_SEED_ROLE_1_FD;
    }
    if (strcmp(role, "seed-role-2") == 0) {
        return PF_TQ_TEST_SERVICE_SEED_ROLE_2_FD;
    }
    if (strcmp(role, "seed-service") == 0) {
        return PF_TQ_TEST_SERVICE_SEED_SERVICE_FD;
    }
    if (strcmp(role, "service-endpoint") == 0) {
        return PF_TQ_TEST_SERVICE_ENDPOINT_FD;
    }
    if (strcmp(role, "service-executable") == 0) {
        return PF_TQ_TEST_SERVICE_EXECUTABLE_FD;
    }
    if (strcmp(role, "transition") == 0) {
        return PF_TQ_TEST_SERVICE_TRANSITION_FD;
    }
    return -1;
}

static int pf_tq_test_adapter_fd(const char *role) {
    if (strcmp(role, "authority-policy") == 0) {
        return PF_TQ_TEST_ADAPTER_AUTHORITY_POLICY_FD;
    }
    if (strcmp(role, "authority-store") == 0) {
        return PF_TQ_TEST_ADAPTER_AUTHORITY_STORE_FD;
    }
    if (strcmp(role, "candidate-archive") == 0) {
        return PF_TQ_TEST_ADAPTER_CANDIDATE_ARCHIVE_FD;
    }
    if (strcmp(role, "provenance-bundle") == 0) {
        return PF_TQ_TEST_ADAPTER_PROVENANCE_BUNDLE_FD;
    }
    if (strcmp(role, "trusted-clock") == 0) {
        return PF_TQ_TEST_ADAPTER_TRUSTED_CLOCK_FD;
    }
    return -1;
}

static pf_tq_handoff_channels_v2 pf_tq_test_channels(void) {
    pf_tq_handoff_channels_v2 channels;
    channels.authority_policy_fd = PF_TQ_TEST_ADAPTER_AUTHORITY_POLICY_FD;
    channels.authority_store_fd = PF_TQ_TEST_ADAPTER_AUTHORITY_STORE_FD;
    channels.candidate_archive_fd = PF_TQ_TEST_ADAPTER_CANDIDATE_ARCHIVE_FD;
    channels.provenance_bundle_fd = PF_TQ_TEST_ADAPTER_PROVENANCE_BUNDLE_FD;
    channels.trusted_clock_fd = PF_TQ_TEST_ADAPTER_TRUSTED_CLOCK_FD;
    return channels;
}

static void pf_tq_test_policy(
    pf_tq_isolation_policy_v2 *policy,
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT]
) {
    pf_tq_isolation_expectation_v2 expected;
    char error[PF_TQ_FD_MANIFEST_V2_ERROR_BYTES];
    size_t index;
    memset(policy, 0, sizeof(*policy));
    memset(roles, 0,
        PF_TQ_FD_MANIFEST_V2_COUNT * sizeof(*roles));
    memset(&expected, 0, sizeof(expected));
    if (pf_tq_fd_manifest_bind_expectation_v2(
            &expected, error, sizeof(error)) != 0 || error[0] != '\0' ||
            expected.fd_manifest == NULL ||
            expected.fd_manifest_count != PF_TQ_FD_MANIFEST_V2_COUNT ||
            expected.proc_root_role_index !=
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_PROC_ROOT_INDEX ||
            expected.durable_root_role_index !=
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_DURABLE_ROOT_INDEX ||
            expected.service_executable_role_index !=
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_EXECUTABLE_INDEX) {
        pf_tq_test_fail("bind-expectation");
    }
    for (index = 0U; index < expected.fd_manifest_count; ++index) {
        const pf_tq_isolation_fd_manifest_v2 *manifest =
            &expected.fd_manifest[index];
        int fd = strcmp(manifest->process, "adapter") == 0
            ? pf_tq_test_adapter_fd(manifest->role)
            : pf_tq_test_service_fd(manifest->role);
        int rendered_process;
        int rendered_stage;
        int rendered_role;
        if (fd < 0) pf_tq_test_fail("unknown-manifest-role");
        rendered_process = snprintf(roles[index].process,
            sizeof(roles[index].process), "%s", manifest->process);
        rendered_stage = snprintf(roles[index].stage,
            sizeof(roles[index].stage), "%s", manifest->stage);
        rendered_role = snprintf(roles[index].role,
            sizeof(roles[index].role), "%s", manifest->role);
        if (rendered_process <= 0 ||
                (size_t)rendered_process >= sizeof(roles[index].process) ||
                rendered_stage <= 0 ||
                (size_t)rendered_stage >= sizeof(roles[index].stage) ||
                rendered_role <= 0 ||
                (size_t)rendered_role >= sizeof(roles[index].role)) {
            pf_tq_test_fail("manifest-copy");
        }
        roles[index].fd = fd;
        roles[index].close_on_exec = manifest->close_on_exec;
    }
    policy->fd_roles = roles;
    policy->fd_role_count = expected.fd_manifest_count;
    policy->service_executable_fd = PF_TQ_TEST_SERVICE_EXECUTABLE_FD;
}

static int pf_tq_test_projection(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    const char *process,
    const char *stage,
    const int *expected_fds,
    size_t expected_count,
    int close_on_exec_fd
) {
    pf_tq_transition_fd_role_v2 output[
        PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_COUNT + 3U];
    char error[PF_TQ_FD_MANIFEST_V2_ERROR_BYTES];
    size_t written = 99U;
    size_t index;
    memset(output, 0x5a, sizeof(output));
    if (pf_tq_fd_manifest_project_v2(policy, channels, process, stage,
            output, sizeof(output) / sizeof(output[0]), &written,
            error, sizeof(error)) != 0 || error[0] != '\0' ||
            written != expected_count) return -1;
    for (index = 0U; index < written; ++index) {
        int expected_flags = expected_fds[index] == close_on_exec_fd
            ? FD_CLOEXEC : 0;
        if (output[index].fd != expected_fds[index] ||
                output[index].fd_flags != expected_flags ||
                (index > 0U && output[index - 1U].fd >= output[index].fd)) {
            return -1;
        }
    }
    return 0;
}

static int pf_tq_test_valid(void) {
    static const int adapter[] = {0, 1, 2, 10, 11, 12, 13, 14};
    static const int service_pre[] = {
        0, 1, 2, 10, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
    };
    static const int service_post[] = {
        0, 1, 2, 10, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32
    };
    static const int service_steady[] = {
        0, 1, 2, 10, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30
    };
    pf_tq_isolation_policy_v2 policy;
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT];
    pf_tq_handoff_channels_v2 channels = pf_tq_test_channels();
    char error[PF_TQ_FD_MANIFEST_V2_ERROR_BYTES];
    int fd = -1;
    int close_on_exec = -1;
    pf_tq_test_policy(&policy, roles);
    if (pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error)) != 0 ||
            error[0] != '\0') return 1;
    if (pf_tq_fd_manifest_lookup_v2(&policy, "service", "pre-exec",
            "service-executable", &fd, &close_on_exec,
            error, sizeof(error)) != 0 || error[0] != '\0' ||
            fd != PF_TQ_TEST_SERVICE_EXECUTABLE_FD || close_on_exec != 1) {
        return 2;
    }
    if (pf_tq_test_projection(&policy, &channels, "adapter", "steady",
            adapter, sizeof(adapter) / sizeof(adapter[0]), -1) != 0 ||
            pf_tq_test_projection(&policy, &channels, "service", "pre-exec",
                service_pre, sizeof(service_pre) / sizeof(service_pre[0]),
                PF_TQ_TEST_SERVICE_EXECUTABLE_FD) != 0 ||
            pf_tq_test_projection(&policy, &channels, "service", "post-exec",
                service_post, sizeof(service_post) / sizeof(service_post[0]),
                -1) != 0 ||
            pf_tq_test_projection(&policy, &channels, "service", "steady",
                service_steady,
                sizeof(service_steady) / sizeof(service_steady[0]), -1) != 0) {
        return 3;
    }
    fd = -1;
    close_on_exec = -1;
    error[0] = '\0';
    if (pf_tq_fd_manifest_lookup_v2(&policy, "service", "post-exec",
            "service-executable", &fd, &close_on_exec,
            error, sizeof(error)) == 0 || error[0] == '\0' || fd != -1 ||
            close_on_exec != -1) return 4;
    return 0;
}

static int pf_tq_test_rejected(const char *name) {
    pf_tq_isolation_policy_v2 policy;
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT];
    pf_tq_handoff_channels_v2 channels = pf_tq_test_channels();
    pf_tq_transition_fd_role_v2 projection[
        PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_COUNT + 3U];
    pf_tq_isolation_expectation_v2 expectation;
    char error[PF_TQ_FD_MANIFEST_V2_ERROR_BYTES];
    size_t written = 77U;
    int fd = 77;
    int close_on_exec = 77;
    int result = 0;
    pf_tq_test_policy(&policy, roles);
    memset(projection, 0x33, sizeof(projection));
    memset(&expectation, 0, sizeof(expectation));
    error[0] = '\0';

    if (strcmp(name, "bind-null") == 0) {
        result = pf_tq_fd_manifest_bind_expectation_v2(
            NULL, error, sizeof(error));
    } else if (strcmp(name, "bind-conflict") == 0) {
        expectation.fd_manifest = (const pf_tq_isolation_fd_manifest_v2 *)roles;
        expectation.fd_manifest_count = 1U;
        result = pf_tq_fd_manifest_bind_expectation_v2(
            &expectation, error, sizeof(error));
    } else if (strcmp(name, "validate-null-policy") == 0) {
        result = pf_tq_fd_manifest_validate_policy_v2(
            NULL, &channels, error, sizeof(error));
    } else if (strcmp(name, "validate-null-channels") == 0) {
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, NULL, error, sizeof(error));
    } else if (strcmp(name, "manifest-count") == 0) {
        --policy.fd_role_count;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "row-process") == 0) {
        (void)snprintf(roles[0].process, sizeof(roles[0].process), "candidate");
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "row-stage") == 0) {
        (void)snprintf(roles[0].stage, sizeof(roles[0].stage), "pre-exec");
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "row-role") == 0) {
        (void)snprintf(roles[0].role, sizeof(roles[0].role), "other");
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "row-close-on-exec") == 0) {
        roles[0].close_on_exec = 1;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "row-stdio-collision") == 0) {
        roles[0].fd = 2;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "row-stage-duplicate") == 0) {
        roles[1].fd = roles[0].fd;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "retained-pre-post-drift") == 0) {
        roles[5].fd = 33;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "retained-post-steady-drift") == 0) {
        roles[32].fd = 33;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "transition-drift") == 0) {
        roles[17].fd = 33;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "service-executable-field") == 0) {
        policy.service_executable_fd = 33;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "authority-policy-cross-process") == 0) {
        roles[7].fd = 33;
        roles[20].fd = 33;
        roles[34].fd = 33;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "adapter-endpoint-alias") == 0) {
        roles[16].fd = PF_TQ_TEST_ADAPTER_AUTHORITY_STORE_FD;
        roles[29].fd = PF_TQ_TEST_ADAPTER_AUTHORITY_STORE_FD;
        roles[43].fd = PF_TQ_TEST_ADAPTER_AUTHORITY_STORE_FD;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "channel-mismatch") == 0) {
        ++channels.candidate_archive_fd;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "channel-stdio") == 0) {
        channels.authority_policy_fd = 0;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "channel-duplicate") == 0) {
        channels.authority_store_fd = channels.authority_policy_fd;
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    } else if (strcmp(name, "project-unknown-stage") == 0) {
        result = pf_tq_fd_manifest_project_v2(
            &policy, &channels, "adapter", "pre-exec", projection,
            sizeof(projection) / sizeof(projection[0]), &written,
            error, sizeof(error));
        if (written != 0U) return 90;
    } else if (strcmp(name, "project-small-capacity") == 0) {
        result = pf_tq_fd_manifest_project_v2(
            &policy, &channels, "service", "pre-exec", projection,
            PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_COUNT + 2U, &written,
            error, sizeof(error));
        if (written != 0U || projection[0].fd != 0x33333333) return 91;
    } else if (strcmp(name, "project-null-output") == 0) {
        result = pf_tq_fd_manifest_project_v2(
            &policy, &channels, "service", "steady", NULL, 99U, &written,
            error, sizeof(error));
        if (written != 0U) return 92;
    } else if (strcmp(name, "lookup-null-role") == 0) {
        result = pf_tq_fd_manifest_lookup_v2(
            &policy, "service", "steady", NULL, &fd, &close_on_exec,
            error, sizeof(error));
        if (fd != -1 || close_on_exec != -1) return 93;
    } else {
        return 94;
    }
    return result != 0 && error[0] != '\0' ? 0 : 95;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "valid") == 0) {
        return pf_tq_test_valid();
    }
    if (argc == 2) return pf_tq_test_rejected(argv[1]);
    return 2;
}
