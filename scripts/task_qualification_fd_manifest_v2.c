#define _GNU_SOURCE
#include "task_qualification_fd_manifest_v2.h"

#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const pf_tq_isolation_fd_manifest_v2 pf_tq_fd_manifest_v2[] = {
    {"adapter", "steady", "authority-policy", 0},
    {"adapter", "steady", "authority-store", 0},
    {"adapter", "steady", "candidate-archive", 0},
    {"adapter", "steady", "provenance-bundle", 0},
    {"adapter", "steady", "trusted-clock", 0},

    {"service", "post-exec", "adapter-build-policy", 0},
    {"service", "post-exec", "adapter-closure", 0},
    {"service", "post-exec", "authority-policy", 0},
    {"service", "post-exec", "durable-root", 0},
    {"service", "post-exec", "handoff", 0},
    {"service", "post-exec", "isolation-policy", 0},
    {"service", "post-exec", "proc-root", 0},
    {"service", "post-exec", "seed-role-0", 0},
    {"service", "post-exec", "seed-role-1", 0},
    {"service", "post-exec", "seed-role-2", 0},
    {"service", "post-exec", "seed-service", 0},
    {"service", "post-exec", "service-endpoint", 0},
    {"service", "post-exec", "transition", 0},

    {"service", "pre-exec", "adapter-build-policy", 0},
    {"service", "pre-exec", "adapter-closure", 0},
    {"service", "pre-exec", "authority-policy", 0},
    {"service", "pre-exec", "durable-root", 0},
    {"service", "pre-exec", "handoff", 0},
    {"service", "pre-exec", "isolation-policy", 0},
    {"service", "pre-exec", "proc-root", 0},
    {"service", "pre-exec", "seed-role-0", 0},
    {"service", "pre-exec", "seed-role-1", 0},
    {"service", "pre-exec", "seed-role-2", 0},
    {"service", "pre-exec", "seed-service", 0},
    {"service", "pre-exec", "service-endpoint", 0},
    {"service", "pre-exec", "service-executable", 1},
    {"service", "pre-exec", "transition", 0},

    {"service", "steady", "adapter-build-policy", 0},
    {"service", "steady", "adapter-closure", 0},
    {"service", "steady", "authority-policy", 0},
    {"service", "steady", "durable-root", 0},
    {"service", "steady", "handoff", 0},
    {"service", "steady", "isolation-policy", 0},
    {"service", "steady", "proc-root", 0},
    {"service", "steady", "seed-role-0", 0},
    {"service", "steady", "seed-role-1", 0},
    {"service", "steady", "seed-role-2", 0},
    {"service", "steady", "seed-service", 0},
    {"service", "steady", "service-endpoint", 0},
};

_Static_assert(
    sizeof(pf_tq_fd_manifest_v2) / sizeof(pf_tq_fd_manifest_v2[0]) ==
        PF_TQ_FD_MANIFEST_V2_COUNT,
    "production FD manifest count mismatch"
);

static int pf_tq_fd_manifest_error(
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

static void pf_tq_fd_manifest_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static int pf_tq_fd_manifest_array_equal(
    const char value[PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES],
    const char *expected
) {
    size_t size = strlen(expected);
    return size < PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES &&
        memcmp(value, expected, size) == 0 && value[size] == '\0';
}

static int pf_tq_fd_manifest_input_equal(
    const char *value,
    const char *expected
) {
    size_t value_size;
    size_t expected_size = strlen(expected);
    if (value == NULL) return 0;
    value_size = strnlen(value, PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES);
    return value_size < PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES &&
        value_size == expected_size && memcmp(value, expected, value_size) == 0;
}

static int pf_tq_fd_manifest_supported_stage(
    const char *process,
    const char *stage,
    size_t *row_count
) {
    if (pf_tq_fd_manifest_input_equal(process, "adapter") &&
            pf_tq_fd_manifest_input_equal(stage, "steady")) {
        if (row_count != NULL) {
            *row_count = PF_TQ_FD_MANIFEST_V2_ADAPTER_STEADY_COUNT;
        }
        return 1;
    }
    if (pf_tq_fd_manifest_input_equal(process, "service") &&
            pf_tq_fd_manifest_input_equal(stage, "post-exec")) {
        if (row_count != NULL) {
            *row_count = PF_TQ_FD_MANIFEST_V2_SERVICE_POST_EXEC_COUNT;
        }
        return 1;
    }
    if (pf_tq_fd_manifest_input_equal(process, "service") &&
            pf_tq_fd_manifest_input_equal(stage, "pre-exec")) {
        if (row_count != NULL) {
            *row_count = PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_COUNT;
        }
        return 1;
    }
    if (pf_tq_fd_manifest_input_equal(process, "service") &&
            pf_tq_fd_manifest_input_equal(stage, "steady")) {
        if (row_count != NULL) {
            *row_count = PF_TQ_FD_MANIFEST_V2_SERVICE_STEADY_COUNT;
        }
        return 1;
    }
    return 0;
}

static int pf_tq_fd_manifest_find(
    const pf_tq_isolation_policy_v2 *policy,
    const char *process,
    const char *stage,
    const char *role,
    size_t *found
) {
    size_t index;
    for (index = 0U; index < policy->fd_role_count; ++index) {
        const pf_tq_isolation_fd_role_v2 *entry = &policy->fd_roles[index];
        if (pf_tq_fd_manifest_array_equal(entry->process, process) &&
                pf_tq_fd_manifest_array_equal(entry->stage, stage) &&
                pf_tq_fd_manifest_array_equal(entry->role, role)) {
            if (found != NULL) *found = index;
            return 0;
        }
    }
    return -1;
}

static int pf_tq_fd_manifest_core_validate(
    const pf_tq_isolation_policy_v2 *policy,
    char *error,
    size_t error_size
) {
    size_t index;
    size_t other;
    size_t adapter_authority_policy;
    size_t adapter_authority_store;
    size_t service_authority_policy;
    size_t service_endpoint;
    size_t service_executable;
    if (policy == NULL || policy->fd_roles == NULL ||
            policy->fd_role_count != PF_TQ_FD_MANIFEST_V2_COUNT) {
        return pf_tq_fd_manifest_error(error, error_size,
            "production FD policy shape rejected");
    }
    for (index = 0U; index < PF_TQ_FD_MANIFEST_V2_COUNT; ++index) {
        const pf_tq_isolation_fd_manifest_v2 *manifest =
            &pf_tq_fd_manifest_v2[index];
        const pf_tq_isolation_fd_role_v2 *entry = &policy->fd_roles[index];
        if (!pf_tq_fd_manifest_array_equal(entry->process,
                manifest->process) ||
                !pf_tq_fd_manifest_array_equal(entry->stage,
                    manifest->stage) ||
                !pf_tq_fd_manifest_array_equal(entry->role,
                    manifest->role) ||
                entry->close_on_exec != manifest->close_on_exec ||
                entry->fd <= 2) {
            return pf_tq_fd_manifest_error(error, error_size,
                "production FD policy row rejected at %zu", index);
        }
        for (other = 0U; other < index; ++other) {
            const pf_tq_isolation_fd_role_v2 *prior =
                &policy->fd_roles[other];
            if (pf_tq_fd_manifest_array_equal(
                    prior->process, manifest->process) &&
                    pf_tq_fd_manifest_array_equal(
                        prior->stage, manifest->stage) &&
                    prior->fd == entry->fd) {
                return pf_tq_fd_manifest_error(error, error_size,
                    "production FD policy reuses an FD within a stage");
            }
        }
    }

    for (index = 5U; index <= 17U; ++index) {
        const pf_tq_isolation_fd_role_v2 *post = &policy->fd_roles[index];
        size_t pre;
        if (pf_tq_fd_manifest_find(policy, "service", "pre-exec",
                post->role, &pre) != 0 ||
                post->fd != policy->fd_roles[pre].fd) {
            return pf_tq_fd_manifest_error(error, error_size,
                "service pre/post-exec FD continuity rejected");
        }
    }
    for (index = 32U; index <= 43U; ++index) {
        const pf_tq_isolation_fd_role_v2 *steady = &policy->fd_roles[index];
        size_t post;
        if (pf_tq_fd_manifest_find(policy, "service", "post-exec",
                steady->role, &post) != 0 ||
                steady->fd != policy->fd_roles[post].fd) {
            return pf_tq_fd_manifest_error(error, error_size,
                "service post-exec/steady FD continuity rejected");
        }
    }

    if (pf_tq_fd_manifest_find(policy, "adapter", "steady",
            "authority-policy", &adapter_authority_policy) != 0 ||
            pf_tq_fd_manifest_find(policy, "adapter", "steady",
                "authority-store", &adapter_authority_store) != 0 ||
            pf_tq_fd_manifest_find(policy, "service", "pre-exec",
                "authority-policy", &service_authority_policy) != 0 ||
            pf_tq_fd_manifest_find(policy, "service", "pre-exec",
                "service-endpoint", &service_endpoint) != 0 ||
            pf_tq_fd_manifest_find(policy, "service", "pre-exec",
                "service-executable", &service_executable) != 0) {
        return pf_tq_fd_manifest_error(error, error_size,
            "production FD policy required role lookup failed");
    }
    if (policy->fd_roles[adapter_authority_policy].fd !=
            policy->fd_roles[service_authority_policy].fd) {
        return pf_tq_fd_manifest_error(error, error_size,
            "authority-policy FD is not retained across the fork boundary");
    }
    if (policy->fd_roles[adapter_authority_store].fd ==
            policy->fd_roles[service_endpoint].fd) {
        return pf_tq_fd_manifest_error(error, error_size,
            "adapter and service socket endpoint FDs alias");
    }
    if (policy->service_executable_fd !=
            policy->fd_roles[service_executable].fd) {
        return pf_tq_fd_manifest_error(error, error_size,
            "service executable scalar/manifest FD mismatch");
    }
    return 0;
}

int pf_tq_fd_manifest_bind_expectation_v2(
    pf_tq_isolation_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    pf_tq_fd_manifest_clear_error(error, error_size);
    if (expected == NULL) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest expectation is null");
    }
    if (expected->fd_manifest == pf_tq_fd_manifest_v2 &&
            expected->fd_manifest_count == PF_TQ_FD_MANIFEST_V2_COUNT &&
            expected->proc_root_role_index ==
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_PROC_ROOT_INDEX &&
            expected->durable_root_role_index ==
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_DURABLE_ROOT_INDEX &&
            expected->service_executable_role_index ==
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_EXECUTABLE_INDEX) {
        return 0;
    }
    if (expected->fd_manifest != NULL || expected->fd_manifest_count != 0U ||
            expected->proc_root_role_index != 0U ||
            expected->durable_root_role_index != 0U ||
            expected->service_executable_role_index != 0U) {
        return pf_tq_fd_manifest_error(error, error_size,
            "caller-supplied FD manifest authority rejected");
    }
    expected->fd_manifest = pf_tq_fd_manifest_v2;
    expected->fd_manifest_count = PF_TQ_FD_MANIFEST_V2_COUNT;
    expected->proc_root_role_index =
        PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_PROC_ROOT_INDEX;
    expected->durable_root_role_index =
        PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_DURABLE_ROOT_INDEX;
    expected->service_executable_role_index =
        PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_EXECUTABLE_INDEX;
    return 0;
}

int pf_tq_fd_manifest_validate_policy_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    char *error,
    size_t error_size
) {
    static const char *const roles[5] = {
        "authority-policy", "authority-store", "candidate-archive",
        "provenance-bundle", "trusted-clock"
    };
    int channel_fds[5];
    size_t index;
    size_t other;
    pf_tq_fd_manifest_clear_error(error, error_size);
    if (channels == NULL) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest handoff channels are null");
    }
    if (pf_tq_fd_manifest_core_validate(
            policy, error, error_size) != 0) return -1;
    channel_fds[0] = channels->authority_policy_fd;
    channel_fds[1] = channels->authority_store_fd;
    channel_fds[2] = channels->candidate_archive_fd;
    channel_fds[3] = channels->provenance_bundle_fd;
    channel_fds[4] = channels->trusted_clock_fd;
    for (index = 0U; index < 5U; ++index) {
        size_t row;
        if (channel_fds[index] <= 2 ||
                pf_tq_fd_manifest_find(policy, "adapter", "steady",
                    roles[index], &row) != 0 ||
                policy->fd_roles[row].fd != channel_fds[index]) {
            return pf_tq_fd_manifest_error(error, error_size,
                "adapter handoff channel join rejected at %zu", index);
        }
        for (other = 0U; other < index; ++other) {
            if (channel_fds[other] == channel_fds[index]) {
                return pf_tq_fd_manifest_error(error, error_size,
                    "adapter handoff channels reuse an FD");
            }
        }
    }
    return 0;
}

int pf_tq_fd_manifest_lookup_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const char *process,
    const char *stage,
    const char *role,
    int *fd,
    int *close_on_exec,
    char *error,
    size_t error_size
) {
    size_t row;
    pf_tq_fd_manifest_clear_error(error, error_size);
    if (fd != NULL) *fd = -1;
    if (close_on_exec != NULL) *close_on_exec = -1;
    if (fd == NULL || close_on_exec == NULL || role == NULL ||
            !pf_tq_fd_manifest_supported_stage(process, stage, NULL)) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest lookup arguments rejected");
    }
    if (pf_tq_fd_manifest_core_validate(
            policy, error, error_size) != 0) return -1;
    if (strnlen(role, PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES) >=
            PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES ||
            pf_tq_fd_manifest_find(
                policy, process, stage, role, &row) != 0) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest role is absent from the requested stage");
    }
    *fd = policy->fd_roles[row].fd;
    *close_on_exec = policy->fd_roles[row].close_on_exec;
    return 0;
}

static int pf_tq_fd_manifest_fd_compare(const void *left, const void *right) {
    const pf_tq_transition_fd_role_v2 *a = left;
    const pf_tq_transition_fd_role_v2 *b = right;
    if (a->fd < b->fd) return -1;
    if (a->fd > b->fd) return 1;
    return 0;
}

int pf_tq_fd_manifest_project_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    const char *process,
    const char *stage,
    pf_tq_transition_fd_role_v2 *output,
    size_t capacity,
    size_t *written,
    char *error,
    size_t error_size
) {
    size_t row_count = 0U;
    size_t output_count = 3U;
    size_t index;
    pf_tq_transition_fd_role_v2 staged[
        PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_COUNT + 3U];
    pf_tq_fd_manifest_clear_error(error, error_size);
    if (written != NULL) *written = 0U;
    if (written == NULL || output == NULL ||
            !pf_tq_fd_manifest_supported_stage(
                process, stage, &row_count)) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest projection arguments rejected");
    }
    if (capacity < row_count + 3U) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest projection capacity is too small");
    }
    if (pf_tq_fd_manifest_validate_policy_v2(
            policy, channels, error, error_size) != 0) return -1;
    staged[0] = (pf_tq_transition_fd_role_v2){0, 0};
    staged[1] = (pf_tq_transition_fd_role_v2){1, 0};
    staged[2] = (pf_tq_transition_fd_role_v2){2, 0};
    for (index = 0U; index < policy->fd_role_count; ++index) {
        const pf_tq_isolation_fd_role_v2 *entry = &policy->fd_roles[index];
        if (pf_tq_fd_manifest_array_equal(entry->process, process) &&
                pf_tq_fd_manifest_array_equal(entry->stage, stage)) {
            if (output_count >= sizeof(staged) / sizeof(staged[0])) {
                return pf_tq_fd_manifest_error(error, error_size,
                    "FD manifest projection internal bound exceeded");
            }
            staged[output_count].fd = entry->fd;
            staged[output_count].fd_flags = entry->close_on_exec
                ? FD_CLOEXEC : 0;
            ++output_count;
        }
    }
    if (output_count != row_count + 3U) {
        return pf_tq_fd_manifest_error(error, error_size,
            "FD manifest projection row count mismatch");
    }
    qsort(staged, output_count, sizeof(staged[0]),
        pf_tq_fd_manifest_fd_compare);
    for (index = 1U; index < output_count; ++index) {
        if (staged[index - 1U].fd >= staged[index].fd) {
            return pf_tq_fd_manifest_error(error, error_size,
                "FD manifest projection is not strictly unique");
        }
    }
    memcpy(output, staged, output_count * sizeof(staged[0]));
    *written = output_count;
    return 0;
}
