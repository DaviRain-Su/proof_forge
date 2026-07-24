#define _GNU_SOURCE
/* Test-owned eligible-kernel driver for ADR-0021 U/P/A namespace isolation. */
#include "task_qualification_namespace_v2.h"
#include "task_qualification_kernel_transition_v2.h"
#include "task_qualification_peer_observer_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/capability.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define PF_TQ_NS_STACK_BYTES (1024U * 1024U)
#define PF_TQ_NS_PROC_FD 8
#define PF_TQ_NS_EXECUTABLE_FD 9
#define PF_TQ_NS_ADAPTER_UID 1001U
#define PF_TQ_NS_SERVICE_UID 1002U
#define PF_TQ_NS_ADAPTER_GID 1003U
#define PF_TQ_NS_SERVICE_GID 1004U

struct pf_tq_ns_linux_dirent64 {
    uint64_t inode;
    int64_t offset;
    unsigned short record_length;
    unsigned char type;
    char name[];
};

struct pf_tq_ns_child_context {
    const char *mode;
    const char *self_path;
    const char *setup_path;
    const char *sentinel_path;
    unsigned outside[4];
    int ready_write;
    int go_read;
};

static void pf_tq_ns_die(const char *where) {
    int saved = errno;
    (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:%s:errno=%d\n", where, saved);
    _exit(111);
}

static void pf_tq_ns_fail(const char *where) {
    errno = 0;
    pf_tq_ns_die(where);
}

static void pf_tq_ns_expect_rejected(
    int result,
    const char *error,
    const char *where
) {
    if (result == 0 || error == NULL || error[0] == '\0') pf_tq_ns_fail(where);
}

static uint64_t pf_tq_ns_effective_capabilities(void) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));
    if (syscall(SYS_capget, &header, data) != 0) pf_tq_ns_die("capget");
    return (uint64_t)data[0].effective |
        ((uint64_t)data[1].effective << 32U);
}

static int pf_tq_ns_identity_equal(
    const pf_tq_namespace_identity_v2 *left,
    const pf_tq_namespace_identity_v2 *right
) {
    return left->device == right->device && left->inode == right->inode;
}

static int pf_tq_ns_wait_success(pid_t child, const char *where) {
    int status = 0;
    if (waitpid(child, &status, 0) != child) pf_tq_ns_die("waitpid");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:%s:status=%d\n", where, status);
        return -1;
    }
    return 0;
}

static unsigned pf_tq_ns_parse_id(const char *raw) {
    char *end = NULL;
    unsigned long value;
    if (raw == NULL || raw[0] == '\0') pf_tq_ns_fail("empty-outside-id");
    errno = 0;
    value = strtoul(raw, &end, 10);
    if (errno != 0 || end == raw || *end != '\0' || value > UINT32_MAX) {
        pf_tq_ns_fail("invalid-outside-id");
    }
    return (unsigned)value;
}

static int pf_tq_ns_run_helper(const char *path, char *const argv[]) {
    pid_t child = fork();
    int status = 0;
    if (child < 0) pf_tq_ns_die("fork-map-helper");
    if (child == 0) {
        execv(path, argv);
        pf_tq_ns_die("exec-map-helper");
    }
    if (waitpid(child, &status, 0) != child) pf_tq_ns_die("wait-map-helper");
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128;
}

static void pf_tq_ns_install_maps(pid_t child, const unsigned outside[4]) {
    char pid_text[32], uid_a[32], uid_s[32], gid_a[32], gid_s[32];
    char *uid_argv[] = {
        (char *)"/usr/bin/newuidmap", pid_text,
        (char *)"1001", uid_a, (char *)"1",
        (char *)"1002", uid_s, (char *)"1", NULL,
    };
    char *gid_argv[] = {
        (char *)"/usr/bin/newgidmap", pid_text,
        (char *)"1003", gid_a, (char *)"1",
        (char *)"1004", gid_s, (char *)"1", NULL,
    };
    (void)snprintf(pid_text, sizeof(pid_text), "%ld", (long)child);
    (void)snprintf(uid_a, sizeof(uid_a), "%u", outside[0]);
    (void)snprintf(uid_s, sizeof(uid_s), "%u", outside[1]);
    (void)snprintf(gid_a, sizeof(gid_a), "%u", outside[2]);
    (void)snprintf(gid_s, sizeof(gid_s), "%u", outside[3]);
    if (pf_tq_ns_run_helper(uid_argv[0], uid_argv) != 0) {
        pf_tq_ns_fail("newuidmap");
    }
    if (pf_tq_ns_run_helper(gid_argv[0], gid_argv) != 0) {
        pf_tq_ns_fail("newgidmap");
    }
}

static size_t pf_tq_ns_proc_count(int proc_root_fd) {
    unsigned char buffer[4096];
    size_t count = 0U;
    int fd = openat(proc_root_fd, ".",
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) pf_tq_ns_die("open-proc-count");
    for (;;) {
        ssize_t amount = syscall(SYS_getdents64, fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (amount < 0) pf_tq_ns_die("getdents-proc-count");
        if (amount == 0) break;
        while (offset < (size_t)amount) {
            const struct pf_tq_ns_linux_dirent64 *entry =
                (const struct pf_tq_ns_linux_dirent64 *)(const void *)(
                    buffer + offset);
            size_t minimum = offsetof(
                struct pf_tq_ns_linux_dirent64, name) + 1U;
            size_t name_capacity;
            size_t name_size;
            size_t index;
            int decimal = 1;
            if (entry->record_length < minimum ||
                    offset + entry->record_length > (size_t)amount) {
                pf_tq_ns_fail("malformed-proc-dirent");
            }
            name_capacity = entry->record_length - offsetof(
                struct pf_tq_ns_linux_dirent64, name);
            name_size = strnlen(entry->name, name_capacity);
            if (name_size == 0U || name_size == name_capacity) {
                pf_tq_ns_fail("malformed-proc-name");
            }
            for (index = 0U; index < name_size; ++index) {
                if (entry->name[index] < '0' || entry->name[index] > '9') {
                    decimal = 0;
                }
            }
            if (decimal) ++count;
            offset += entry->record_length;
        }
    }
    if (close(fd) != 0) pf_tq_ns_die("close-proc-count");
    return count;
}

static void pf_tq_ns_root_checks(const char *sentinel_path) {
    int fd;
    errno = 0;
    fd = open(sentinel_path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd >= 0 || errno != ENOENT) {
        if (fd >= 0) (void)close(fd);
        pf_tq_ns_fail("old-root-visible");
    }
    errno = 0;
    fd = open("/write-probe", O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd >= 0 || errno != EROFS) {
        if (fd >= 0) {
            (void)close(fd);
            (void)unlink("/write-probe");
        }
        pf_tq_ns_fail("isolated-root-writable");
    }
}

static void pf_tq_ns_open_fixed_setup(
    const char *setup_path,
    const char *self_path,
    int channels[2],
    int *setup_fd,
    int *executable_fd
) {
    size_t index;
    if (syscall(SYS_close_range, 3U, UINT_MAX, 0U) != 0) {
        pf_tq_ns_die("close-range-before-namespace");
    }
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, channels) != 0 ||
            channels[0] != 3 || channels[1] != 4) {
        pf_tq_ns_die("namespace-fixed-socketpair");
    }
    for (index = 5U; index < PF_TQ_NS_PROC_FD; ++index) {
        int fd = open("/dev/null", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        if (fd != (int)index) pf_tq_ns_die("namespace-fixed-placeholder");
    }
    *setup_fd = open(setup_path,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (*setup_fd != PF_TQ_NS_PROC_FD) pf_tq_ns_die("namespace-fixed-setup-root");
    *executable_fd = open(self_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (*executable_fd != PF_TQ_NS_EXECUTABLE_FD) {
        pf_tq_ns_die("namespace-fixed-self-executable");
    }
    for (index = 10U; index <= 13U; ++index) {
        int fd = open("/dev/null", O_RDONLY | O_NOFOLLOW);
        if (fd != (int)index) pf_tq_ns_die("namespace-fixed-adapter-channel");
    }
}

static void pf_tq_ns_maps(
    const unsigned outside[4],
    pf_tq_namespace_id_map_entry_v2 uid_map[2],
    pf_tq_namespace_id_map_entry_v2 gid_map[2]
) {
    uid_map[0].inside_id = PF_TQ_NS_ADAPTER_UID;
    uid_map[0].outside_id = outside[0];
    uid_map[1].inside_id = PF_TQ_NS_SERVICE_UID;
    uid_map[1].outside_id = outside[1];
    gid_map[0].inside_id = PF_TQ_NS_ADAPTER_GID;
    gid_map[0].outside_id = outside[2];
    gid_map[1].inside_id = PF_TQ_NS_SERVICE_GID;
    gid_map[1].outside_id = outside[3];
}

static int pf_tq_ns_adapter_positive(
    int channels[2],
    int executable_fd,
    const char *sentinel_path,
    const pf_tq_namespace_set_v2 *service
) {
    pf_tq_namespace_set_v2 adapter;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    char *const arguments[] = {
        (char *)"pf-taskqualification-namespace-v2-adapter",
        (char *)"--adapter-child", (char *)sentinel_path, NULL,
    };
    char *const environment[] = {NULL};
    if (pf_tq_namespace_enter_adapter_v2(PF_TQ_NS_PROC_FD,
            service, &adapter, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:adapter-enter:%s\n", error);
        return 120;
    }
    if (pf_tq_kernel_isolate_adapter_v2(PF_TQ_NS_PROC_FD,
            PF_TQ_NS_ADAPTER_UID, PF_TQ_NS_ADAPTER_GID,
            error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:adapter-isolate:%s\n", error);
        return 121;
    }
    if (close(channels[0]) != 0 || close(PF_TQ_NS_PROC_FD) != 0 ||
            fcntl(channels[1], F_SETFD, 0) != 0 ||
            fcntl(channels[1], F_GETFD) != 0) {
        pf_tq_ns_die("adapter-exec-channel-transition");
    }
    (void)syscall(SYS_execveat, executable_fd, "",
        arguments, environment, AT_EMPTY_PATH);
    pf_tq_ns_die("adapter-execveat");
    return 122;
}

static int pf_tq_ns_adapter_child(const char *sentinel_path) {
    pf_tq_namespace_set_v2 adapter;
    pf_tq_kernel_snapshot_v2 state;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    char marker = 'R';
    size_t count;
    size_t index;
    int proc_root_fd = open(
        "/proc", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (proc_root_fd != 3 || pf_tq_namespace_current_v2(proc_root_fd,
            &adapter, error, sizeof(error)) != 0 ||
            pf_tq_kernel_snapshot_read_v2(proc_root_fd,
                PF_TQ_KERNEL_CROSSCHECK_FULL_V2, &state,
                error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:adapter-child-state:%s\n", error);
        return 123;
    }
    if (state.bounding != 0U || state.permitted != 0U ||
            state.effective != 0U || state.inheritable != 0U ||
            state.ambient != 0U || state.supplementary_group_count != 0 ||
            state.no_new_privs != 1) {
        pf_tq_ns_fail("adapter-child-authority-state");
    }
    for (index = 0U; index < 4U; ++index) {
        if (state.uid[index] != PF_TQ_NS_ADAPTER_UID ||
                state.gid[index] != PF_TQ_NS_ADAPTER_GID) {
            pf_tq_ns_fail("adapter-child-credential-state");
        }
    }
    pf_tq_ns_root_checks(sentinel_path);
    count = pf_tq_ns_proc_count(proc_root_fd);
    if (getpid() != 1 || count != 1U) pf_tq_ns_fail("adapter-proc-scope");
    if (close(proc_root_fd) != 0) pf_tq_ns_die("adapter-close-proc-root");
    (void)printf(
        "PF-NS adapter pid=1 procCount=1 capEff=%016llx user=%llu:%llu pidns=%llu:%llu mnt=%llu:%llu\n",
        (unsigned long long)pf_tq_ns_effective_capabilities(),
        (unsigned long long)adapter.user_namespace.device,
        (unsigned long long)adapter.user_namespace.inode,
        (unsigned long long)adapter.pid_namespace.device,
        (unsigned long long)adapter.pid_namespace.inode,
        (unsigned long long)adapter.mount_namespace.device,
        (unsigned long long)adapter.mount_namespace.inode);
    (void)fflush(stdout);
    if (send(4, &marker, 1U, MSG_NOSIGNAL) != 1) {
        pf_tq_ns_die("adapter-send-ready");
    }
    if (recv(4, &marker, 1U, 0) != 1 || marker != 'G') {
        pf_tq_ns_die("adapter-receive-go");
    }
    return 0;
}

static void pf_tq_ns_adapter_identity_negative(
    int channels[2],
    const pf_tq_namespace_set_v2 *service
) {
    pf_tq_namespace_set_v2 substituted = *service;
    pf_tq_namespace_set_v2 ignored;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    int result;
    (void)channels;
    substituted.mount_namespace.inode ^= 1U;
    result = pf_tq_namespace_enter_adapter_v2(PF_TQ_NS_PROC_FD,
        &substituted, &ignored, error, sizeof(error));
    pf_tq_ns_expect_rejected(result, error,
        "adapter-service-identity-substitution-accepted");
}

static int pf_tq_ns_adapter_role_fd(const char *role) {
    if (strcmp(role, "authority-policy") == 0) return 10;
    if (strcmp(role, "authority-store") == 0) return 4;
    if (strcmp(role, "candidate-archive") == 0) return 11;
    if (strcmp(role, "provenance-bundle") == 0) return 12;
    if (strcmp(role, "trusted-clock") == 0) return 13;
    return -1;
}

static int pf_tq_ns_service_role_fd(const char *role) {
    if (strcmp(role, "adapter-build-policy") == 0) return 20;
    if (strcmp(role, "adapter-closure") == 0) return 21;
    if (strcmp(role, "authority-policy") == 0) return 10;
    if (strcmp(role, "durable-root") == 0) return 22;
    if (strcmp(role, "handoff") == 0) return 23;
    if (strcmp(role, "isolation-policy") == 0) return 24;
    if (strcmp(role, "proc-root") == 0) return PF_TQ_NS_PROC_FD;
    if (strcmp(role, "seed-role-0") == 0) return 25;
    if (strcmp(role, "seed-role-1") == 0) return 26;
    if (strcmp(role, "seed-role-2") == 0) return 27;
    if (strcmp(role, "seed-service") == 0) return 28;
    if (strcmp(role, "service-endpoint") == 0) return 3;
    if (strcmp(role, "service-executable") == 0) return PF_TQ_NS_EXECUTABLE_FD;
    if (strcmp(role, "transition") == 0) return 29;
    return -1;
}

static void pf_tq_ns_copy_identity(
    pf_tq_isolation_identity_v2 *output,
    const pf_tq_namespace_identity_v2 *input
) {
    output->device = input->device;
    output->inode = input->inode;
}

static void pf_tq_ns_peer_policy(
    const pf_tq_namespace_set_v2 *service,
    const pf_tq_namespace_set_v2 *adapter,
    pf_tq_isolation_policy_v2 *policy,
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT],
    pf_tq_handoff_channels_v2 *channels
) {
    pf_tq_isolation_expectation_v2 expected;
    char error[PF_TQ_FD_MANIFEST_V2_ERROR_BYTES];
    size_t index;
    memset(policy, 0, sizeof(*policy));
    memset(roles, 0, PF_TQ_FD_MANIFEST_V2_COUNT * sizeof(*roles));
    memset(&expected, 0, sizeof(expected));
    if (pf_tq_fd_manifest_bind_expectation_v2(
            &expected, error, sizeof(error)) != 0) {
        pf_tq_ns_fail("peer-manifest-bind");
    }
    for (index = 0U; index < expected.fd_manifest_count; ++index) {
        const pf_tq_isolation_fd_manifest_v2 *manifest =
            &expected.fd_manifest[index];
        int fd = strcmp(manifest->process, "adapter") == 0
            ? pf_tq_ns_adapter_role_fd(manifest->role)
            : pf_tq_ns_service_role_fd(manifest->role);
        int process_size;
        int stage_size;
        int role_size;
        if (fd < 0) pf_tq_ns_fail("peer-manifest-role");
        process_size = snprintf(roles[index].process,
            sizeof(roles[index].process), "%s", manifest->process);
        stage_size = snprintf(roles[index].stage,
            sizeof(roles[index].stage), "%s", manifest->stage);
        role_size = snprintf(roles[index].role,
            sizeof(roles[index].role), "%s", manifest->role);
        if (process_size <= 0 || stage_size <= 0 || role_size <= 0 ||
                (size_t)process_size >= sizeof(roles[index].process) ||
                (size_t)stage_size >= sizeof(roles[index].stage) ||
                (size_t)role_size >= sizeof(roles[index].role)) {
            pf_tq_ns_fail("peer-manifest-copy");
        }
        roles[index].fd = fd;
        roles[index].close_on_exec = manifest->close_on_exec;
    }
    policy->fd_roles = roles;
    policy->fd_role_count = PF_TQ_FD_MANIFEST_V2_COUNT;
    policy->service_executable_fd = PF_TQ_NS_EXECUTABLE_FD;
    policy->adapter_uid = PF_TQ_NS_ADAPTER_UID;
    policy->adapter_gid = PF_TQ_NS_ADAPTER_GID;
    policy->service_uid = PF_TQ_NS_SERVICE_UID;
    policy->service_gid = PF_TQ_NS_SERVICE_GID;
    pf_tq_ns_copy_identity(&policy->user_namespace, &service->user_namespace);
    pf_tq_ns_copy_identity(
        &policy->parent_pid_namespace, &service->pid_namespace);
    pf_tq_ns_copy_identity(
        &policy->adapter_pid_namespace, &adapter->pid_namespace);
    pf_tq_ns_copy_identity(
        &policy->service_mount_namespace, &service->mount_namespace);
    pf_tq_ns_copy_identity(
        &policy->adapter_mount_namespace, &adapter->mount_namespace);
    channels->authority_policy_fd = 10;
    channels->authority_store_fd = 4;
    channels->candidate_archive_fd = 11;
    channels->provenance_bundle_fd = 12;
    channels->trusted_clock_fd = 13;
}

static void pf_tq_ns_peer_identities(
    int adapter_endpoint_fd,
    int executable_fd,
    pf_tq_transition_fd_identity_v2 *endpoint,
    pf_tq_peer_executable_identity_v2 *executable
) {
    struct stat endpoint_status;
    struct stat executable_status;
    if (fstat(adapter_endpoint_fd, &endpoint_status) != 0 ||
            fstat(executable_fd, &executable_status) != 0) {
        pf_tq_ns_die("peer-input-fstat");
    }
    endpoint->fd = adapter_endpoint_fd;
    endpoint->device = (uint64_t)endpoint_status.st_dev;
    endpoint->inode = (uint64_t)endpoint_status.st_ino;
    endpoint->mode = (uint64_t)endpoint_status.st_mode;
    endpoint->fd_flags = 0;
    executable->device = (uint64_t)executable_status.st_dev;
    executable->inode = (uint64_t)executable_status.st_ino;
    executable->mode = (uint64_t)executable_status.st_mode;
}

static int pf_tq_ns_service_positive(
    const struct pf_tq_ns_child_context *context,
    int channels[2],
    int executable_fd,
    const pf_tq_namespace_set_v2 *service
) {
    pf_tq_namespace_set_v2 peer;
    pf_tq_isolation_policy_v2 policy;
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT];
    pf_tq_handoff_channels_v2 handoff_channels;
    pf_tq_transition_fd_identity_v2 adapter_endpoint;
    pf_tq_peer_executable_identity_v2 adapter_executable;
    pf_tq_peer_observer_v2 observer;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    char marker;
    size_t count;
    pid_t adapter;
    int pidfd;
    int channel_fd;
    pf_tq_ns_peer_identities(channels[1], executable_fd,
        &adapter_endpoint, &adapter_executable);
    if (pf_tq_namespace_prepare_adapter_pid_v2(
            PF_TQ_NS_PROC_FD, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:prepare-adapter:%s\n", error);
        return 121;
    }
    adapter = fork();
    if (adapter < 0) pf_tq_ns_die("fork-adapter");
    if (adapter == 0) {
        int status = pf_tq_ns_adapter_positive(
            channels, executable_fd, context->sentinel_path, service);
        _exit(status);
    }
    if (adapter != 2) pf_tq_ns_fail("adapter-not-pid-two-in-P");
    if (close(executable_fd) != 0 || close(channels[1]) != 0) {
        pf_tq_ns_die("service-close-adapter-exec-channel");
    }
    for (channel_fd = 10; channel_fd <= 13; ++channel_fd) {
        if (close(channel_fd) != 0) pf_tq_ns_die("service-close-adapter-channel");
    }
    if (recv(channels[0], &marker, 1U, 0) != 1 || marker != 'R') {
        pf_tq_ns_die("service-receive-ready");
    }
    if (pf_tq_namespace_peer_v2(PF_TQ_NS_PROC_FD, adapter,
            &peer, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:peer-observe:%s\n", error);
        return 122;
    }
    if (!pf_tq_ns_identity_equal(&peer.user_namespace,
            &service->user_namespace) ||
            pf_tq_ns_identity_equal(&peer.pid_namespace,
                &service->pid_namespace) ||
            pf_tq_ns_identity_equal(&peer.mount_namespace,
                &service->mount_namespace)) {
        pf_tq_ns_fail("service-peer-topology");
    }
    if (pf_tq_kernel_prepare_custody_v2(PF_TQ_NS_PROC_FD,
            PF_TQ_NS_SERVICE_UID, PF_TQ_NS_SERVICE_GID,
            error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:service-prepare:%s\n", error);
        return 122;
    }
    count = pf_tq_ns_proc_count(PF_TQ_NS_PROC_FD);
    if (getpid() != 1 || count != 2U) pf_tq_ns_fail("service-proc-scope");
    pf_tq_ns_root_checks(context->sentinel_path);
    pf_tq_ns_peer_policy(service, &peer, &policy, roles, &handoff_channels);
    pidfd = (int)syscall(SYS_pidfd_open, adapter, 0U);
    if (pidfd < 0 || fcntl(pidfd, F_GETFD) != FD_CLOEXEC ||
            pf_tq_peer_observer_initialize_v2(PF_TQ_NS_PROC_FD,
                &policy, &handoff_channels, &adapter_endpoint,
                &adapter_executable, &observer,
                error, sizeof(error)) != 0 || error[0] != '\0' ||
            pf_tq_peer_observer_check_v2(&observer, adapter, pidfd, 1U,
                error, sizeof(error)) != 0 || error[0] != '\0' ||
            pf_tq_peer_observer_check_v2(&observer, adapter, pidfd, 2U,
                error, sizeof(error)) != 0 || error[0] != '\0') {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:peer-observer:%s\n", error);
        return 123;
    }
    marker = 'G';
    if (send(channels[0], &marker, 1U, MSG_NOSIGNAL) != 1) {
        pf_tq_ns_die("service-send-go");
    }
    if (pf_tq_ns_wait_success(adapter, "adapter") != 0) return 124;
    if (close(pidfd) != 0) pf_tq_ns_die("service-close-pidfd");
    (void)printf(
        "PF-NS service pid=1 adapterPid=2 procCount=2 capEff=%016llx user=%llu:%llu pidns=%llu:%llu mnt=%llu:%llu\n",
        (unsigned long long)pf_tq_ns_effective_capabilities(),
        (unsigned long long)service->user_namespace.device,
        (unsigned long long)service->user_namespace.inode,
        (unsigned long long)service->pid_namespace.device,
        (unsigned long long)service->pid_namespace.inode,
        (unsigned long long)service->mount_namespace.device,
        (unsigned long long)service->mount_namespace.inode);
    (void)fflush(stdout);
    return 0;
}

static void pf_tq_ns_service_negative(
    const char *mode,
    int channels[2],
    const pf_tq_namespace_set_v2 *service
) {
    pf_tq_namespace_set_v2 ignored;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    int result;
    if (strcmp(mode, "--prepare-adapter-repeat") == 0) {
        if (pf_tq_namespace_prepare_adapter_pid_v2(
                PF_TQ_NS_PROC_FD, error, sizeof(error)) != 0) {
            pf_tq_ns_fail("first-adapter-prepare");
        }
        result = pf_tq_namespace_prepare_adapter_pid_v2(
            PF_TQ_NS_PROC_FD, error, sizeof(error));
        pf_tq_ns_expect_rejected(result, error, "second-adapter-prepare-accepted");
        return;
    }
    if (strcmp(mode, "--peer-invalid-pid") == 0) {
        result = pf_tq_namespace_peer_v2(
            PF_TQ_NS_PROC_FD, -1, &ignored, error, sizeof(error));
        pf_tq_ns_expect_rejected(result, error, "invalid-peer-pid-accepted");
        return;
    }
    if (strcmp(mode, "--adapter-without-a") == 0) {
        pid_t child = fork();
        if (child < 0) pf_tq_ns_die("fork-adapter-without-a");
        if (child == 0) {
            result = pf_tq_namespace_enter_adapter_v2(PF_TQ_NS_PROC_FD,
                service, &ignored, error, sizeof(error));
            pf_tq_ns_expect_rejected(
                result, error, "adapter-without-A-accepted");
            _exit(0);
        }
        if (pf_tq_ns_wait_success(child, "adapter-without-a") != 0) _exit(124);
        return;
    }
    if (strcmp(mode, "--adapter-identity-substitution") == 0) {
        pid_t child;
        if (pf_tq_namespace_prepare_adapter_pid_v2(
                PF_TQ_NS_PROC_FD, error, sizeof(error)) != 0) {
            pf_tq_ns_fail("adapter-substitution-prepare");
        }
        child = fork();
        if (child < 0) pf_tq_ns_die("fork-adapter-substitution");
        if (child == 0) {
            pf_tq_ns_adapter_identity_negative(channels, service);
            _exit(0);
        }
        if (pf_tq_ns_wait_success(child, "adapter-substitution") != 0) _exit(125);
        return;
    }
    pf_tq_ns_fail("unknown-service-negative");
}

static int pf_tq_ns_namespaced_child(void *opaque) {
    struct pf_tq_ns_child_context *context = opaque;
    pf_tq_namespace_id_map_entry_v2 uid_map[2];
    pf_tq_namespace_id_map_entry_v2 gid_map[2];
    pf_tq_namespace_set_v2 service;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    char marker = 'R';
    int channels[2];
    int setup_fd;
    int executable_fd;
    int result;
    if (write(context->ready_write, &marker, 1U) != 1) {
        pf_tq_ns_die("child-write-ready");
    }
    if (read(context->go_read, &marker, 1U) != 1 || marker != 'G') {
        pf_tq_ns_die("child-read-go");
    }
    if (close(context->ready_write) != 0 || close(context->go_read) != 0) {
        pf_tq_ns_die("child-close-map-sync");
    }
    pf_tq_ns_open_fixed_setup(context->setup_path, context->self_path,
        channels, &setup_fd, &executable_fd);
    if (strcmp(context->mode, "--release-no-cloexec") == 0) {
        if (fcntl(setup_fd, F_SETFD, 0) != 0) {
            pf_tq_ns_die("clear-release-cloexec");
        }
        result = pf_tq_namespace_enter_service_v2(
            setup_fd, &service, error, sizeof(error));
        pf_tq_ns_expect_rejected(
            result, error, "non-cloexec-release-accepted");
        return 0;
    }
    if (pf_tq_namespace_enter_service_v2(
            setup_fd, &service, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:service-enter:%s\n", error);
        return 126;
    }
    if (pf_tq_kernel_converge_preseed_v2(
            PF_TQ_NS_PROC_FD, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:preseed:%s\n", error);
        return 127;
    }
    pf_tq_ns_maps(context->outside, uid_map, gid_map);
    if (strcmp(context->mode, "--map-mismatch") == 0) {
        uid_map[0].outside_id += 1U;
        result = pf_tq_namespace_validate_maps_v2(
            PF_TQ_NS_PROC_FD, uid_map, gid_map, error, sizeof(error));
        pf_tq_ns_expect_rejected(result, error, "map-mismatch-accepted");
        return 0;
    }
    if (strcmp(context->mode, "--outside-reuse") == 0) {
        gid_map[1].outside_id = uid_map[0].outside_id;
        result = pf_tq_namespace_validate_maps_v2(
            PF_TQ_NS_PROC_FD, uid_map, gid_map, error, sizeof(error));
        pf_tq_ns_expect_rejected(result, error, "outside-reuse-accepted");
        return 0;
    }
    if (strcmp(context->mode, "--inside-order") == 0) {
        uid_map[0].inside_id = uid_map[1].inside_id;
        result = pf_tq_namespace_validate_maps_v2(
            PF_TQ_NS_PROC_FD, uid_map, gid_map, error, sizeof(error));
        pf_tq_ns_expect_rejected(result, error, "inside-order-accepted");
        return 0;
    }
    if (strcmp(context->mode, "--reserved-id") == 0) {
        uid_map[0].inside_id = 65534U;
        result = pf_tq_namespace_validate_maps_v2(
            PF_TQ_NS_PROC_FD, uid_map, gid_map, error, sizeof(error));
        pf_tq_ns_expect_rejected(result, error, "reserved-id-accepted");
        return 0;
    }
    if (pf_tq_namespace_validate_maps_v2(PF_TQ_NS_PROC_FD,
            uid_map, gid_map, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-NAMESPACE-DRIVER:map-validate:%s\n", error);
        return 127;
    }
    if (strcmp(context->mode, "--positive") == 0) {
        return pf_tq_ns_service_positive(
            context, channels, executable_fd, &service);
    }
    pf_tq_ns_service_negative(context->mode, channels, &service);
    return 0;
}

static int pf_tq_ns_mode_known(const char *mode) {
    static const char *const modes[] = {
        "--positive", "--map-mismatch", "--outside-reuse",
        "--inside-order", "--reserved-id",
        "--prepare-adapter-repeat", "--peer-invalid-pid",
        "--adapter-without-a", "--adapter-identity-substitution",
        "--release-no-cloexec",
    };
    size_t index;
    for (index = 0U; index < sizeof(modes) / sizeof(modes[0]); ++index) {
        if (strcmp(mode, modes[index]) == 0) return 1;
    }
    return 0;
}

static int pf_tq_ns_top_level(
    const char *mode,
    const char *self_path,
    const char *setup_path,
    const char *sentinel_path,
    const unsigned outside[4]
) {
    struct pf_tq_ns_child_context context;
    char *stack;
    int ready[2];
    int go[2];
    pid_t child;
    char marker;
    int result;
    size_t left;
    if (!pf_tq_ns_mode_known(mode)) return 2;
    for (left = 0U; left < 4U; ++left) {
        size_t right;
        for (right = left + 1U; right < 4U; ++right) {
            if (outside[left] == outside[right]) pf_tq_ns_fail("outside-id-reuse");
        }
    }
    if (pipe2(ready, O_CLOEXEC) != 0 || pipe2(go, O_CLOEXEC) != 0) {
        pf_tq_ns_die("mapping-pipes");
    }
    stack = malloc(PF_TQ_NS_STACK_BYTES);
    if (stack == NULL) pf_tq_ns_die("clone-stack");
    memset(&context, 0, sizeof(context));
    context.mode = mode;
    context.self_path = self_path;
    context.setup_path = setup_path;
    context.sentinel_path = sentinel_path;
    memcpy(context.outside, outside, sizeof(context.outside));
    context.ready_write = ready[1];
    context.go_read = go[0];
    child = clone(pf_tq_ns_namespaced_child,
        stack + PF_TQ_NS_STACK_BYTES,
        CLONE_NEWUSER | CLONE_NEWPID | SIGCHLD, &context);
    if (child < 0) pf_tq_ns_die("clone-U-P");
    if (close(ready[1]) != 0 || close(go[0]) != 0) pf_tq_ns_die("parent-close-sync");
    if (read(ready[0], &marker, 1U) != 1 || marker != 'R') {
        pf_tq_ns_die("parent-read-ready");
    }
    pf_tq_ns_install_maps(child, outside);
    marker = 'G';
    if (write(go[1], &marker, 1U) != 1) pf_tq_ns_die("parent-write-go");
    if (close(ready[0]) != 0 || close(go[1]) != 0) pf_tq_ns_die("parent-close-sync-final");
    result = pf_tq_ns_wait_success(child, "U-P-service") == 0 ? 0 : 128;
    free(stack);
    return result;
}

static int pf_tq_ns_not_pid_one(const char *setup_path) {
    pf_tq_namespace_set_v2 ignored;
    char error[PF_TQ_NAMESPACE_V2_ERROR_BYTES];
    int setup_fd = open(setup_path,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int result;
    if (setup_fd < 0) pf_tq_ns_die("not-pid-one-open-setup");
    result = pf_tq_namespace_enter_service_v2(
        setup_fd, &ignored, error, sizeof(error));
    return result != 0 && error[0] != '\0' ? 0 : 1;
}

int main(int argc, char **argv) {
    unsigned outside[4];
    size_t index;
    if (argc == 3 && strcmp(argv[1], "--adapter-child") == 0) {
        return pf_tq_ns_adapter_child(argv[2]);
    }
    if (argc == 3 && strcmp(argv[1], "--not-pid-one") == 0) {
        return pf_tq_ns_not_pid_one(argv[2]);
    }
    if (argc != 8) return 2;
    for (index = 0U; index < 4U; ++index) {
        outside[index] = pf_tq_ns_parse_id(argv[index + 4U]);
    }
    return pf_tq_ns_top_level(
        argv[1], argv[0], argv[2], argv[3], outside);
}
