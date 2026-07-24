#define _GNU_SOURCE
/* Test-owned driver for the ADR-0021 unique seqpacket socket lineage owner. */
#include "task_qualification_socket_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#define PF_TQ_TEST_ADAPTER_FD 4
#define PF_TQ_TEST_SERVICE_FD 5
#define PF_TQ_TEST_AUTHORITY_POLICY_FD 10
#define PF_TQ_TEST_CANDIDATE_ARCHIVE_FD 11
#define PF_TQ_TEST_PROVENANCE_BUNDLE_FD 12
#define PF_TQ_TEST_TRUSTED_CLOCK_FD 13

struct pf_tq_test_linux_dirent64 {
    uint64_t d_ino;
    int64_t d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[];
};

static void pf_tq_test_die(const char *where) {
    int saved = errno;
    (void)fprintf(stderr, "PF-SOCKET-DRIVER:%s:errno=%d\n", where, saved);
    _exit(111);
}

static void pf_tq_test_close_all(void) {
    if (syscall(SYS_close_range, 3U, UINT_MAX, 0U) != 0) {
        pf_tq_test_die("close-range");
    }
}

static void pf_tq_test_require_closed(int fd, const char *where) {
    errno = 0;
    if (fcntl(fd, F_GETFD) != -1 || errno != EBADF) pf_tq_test_die(where);
}

static int pf_tq_test_adapter_role_fd(const char *role) {
    if (strcmp(role, "authority-policy") == 0) {
        return PF_TQ_TEST_AUTHORITY_POLICY_FD;
    }
    if (strcmp(role, "authority-store") == 0) return PF_TQ_TEST_ADAPTER_FD;
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

static int pf_tq_test_service_role_fd(const char *role) {
    if (strcmp(role, "adapter-build-policy") == 0) return 20;
    if (strcmp(role, "adapter-closure") == 0) return 21;
    if (strcmp(role, "authority-policy") == 0) {
        return PF_TQ_TEST_AUTHORITY_POLICY_FD;
    }
    if (strcmp(role, "durable-root") == 0) return 22;
    if (strcmp(role, "handoff") == 0) return 23;
    if (strcmp(role, "isolation-policy") == 0) return 24;
    if (strcmp(role, "proc-root") == 0) return 25;
    if (strcmp(role, "seed-role-0") == 0) return 26;
    if (strcmp(role, "seed-role-1") == 0) return 27;
    if (strcmp(role, "seed-role-2") == 0) return 28;
    if (strcmp(role, "seed-service") == 0) return 29;
    if (strcmp(role, "service-endpoint") == 0) return PF_TQ_TEST_SERVICE_FD;
    if (strcmp(role, "service-executable") == 0) return 30;
    if (strcmp(role, "transition") == 0) return 31;
    return -1;
}

static pf_tq_handoff_channels_v2 pf_tq_test_channels(void) {
    pf_tq_handoff_channels_v2 channels;
    channels.authority_policy_fd = PF_TQ_TEST_AUTHORITY_POLICY_FD;
    channels.authority_store_fd = PF_TQ_TEST_ADAPTER_FD;
    channels.candidate_archive_fd = PF_TQ_TEST_CANDIDATE_ARCHIVE_FD;
    channels.provenance_bundle_fd = PF_TQ_TEST_PROVENANCE_BUNDLE_FD;
    channels.trusted_clock_fd = PF_TQ_TEST_TRUSTED_CLOCK_FD;
    return channels;
}

static void pf_tq_test_policy(
    pf_tq_isolation_policy_v2 *policy,
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT]
) {
    pf_tq_isolation_expectation_v2 expected;
    char error[PF_TQ_SOCKET_V2_ERROR_BYTES];
    size_t index;
    memset(policy, 0, sizeof(*policy));
    memset(roles, 0, PF_TQ_FD_MANIFEST_V2_COUNT * sizeof(*roles));
    memset(&expected, 0, sizeof(expected));
    if (pf_tq_fd_manifest_bind_expectation_v2(
            &expected, error, sizeof(error)) != 0 || error[0] != '\0') {
        pf_tq_test_die("manifest-bind");
    }
    for (index = 0U; index < expected.fd_manifest_count; ++index) {
        const pf_tq_isolation_fd_manifest_v2 *manifest =
            &expected.fd_manifest[index];
        int fd = strcmp(manifest->process, "adapter") == 0
            ? pf_tq_test_adapter_role_fd(manifest->role)
            : pf_tq_test_service_role_fd(manifest->role);
        int process_size;
        int stage_size;
        int role_size;
        if (fd < 0) pf_tq_test_die("manifest-role");
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
            pf_tq_test_die("manifest-copy");
        }
        roles[index].fd = fd;
        roles[index].close_on_exec = manifest->close_on_exec;
    }
    policy->fd_roles = roles;
    policy->fd_role_count = PF_TQ_FD_MANIFEST_V2_COUNT;
    policy->service_executable_fd = 30;
}

static void pf_tq_test_reverse_endpoints(
    pf_tq_isolation_policy_v2 *policy,
    pf_tq_handoff_channels_v2 *channels
) {
    size_t index;
    for (index = 0U; index < policy->fd_role_count; ++index) {
        pf_tq_isolation_fd_role_v2 *entry = &policy->fd_roles[index];
        if (strcmp(entry->process, "adapter") == 0 &&
                strcmp(entry->role, "authority-store") == 0) {
            entry->fd = PF_TQ_TEST_SERVICE_FD;
        }
        if (strcmp(entry->process, "service") == 0 &&
                strcmp(entry->role, "service-endpoint") == 0) {
            entry->fd = PF_TQ_TEST_ADAPTER_FD;
        }
    }
    channels->authority_store_fd = PF_TQ_TEST_SERVICE_FD;
}

static int pf_tq_test_capture(
    int fd,
    pf_tq_transition_fd_identity_v2 *identity
) {
    struct stat status;
    int flags;
    if (identity == NULL || fstat(fd, &status) != 0 ||
            (flags = fcntl(fd, F_GETFD)) < 0) return -1;
    identity->fd = fd;
    identity->device = (uint64_t)status.st_dev;
    identity->inode = (uint64_t)status.st_ino;
    identity->mode = (uint64_t)status.st_mode;
    identity->fd_flags = flags;
    return 0;
}

static int pf_tq_test_fd_expected(int fd) {
    static const int expected[] = {0, 1, 2, 4, 10, 11, 12, 13};
    size_t index;
    for (index = 0U; index < sizeof(expected) / sizeof(expected[0]); ++index) {
        if (expected[index] == fd) return (int)index;
    }
    return -1;
}

static int pf_tq_test_adapter_fd_set(void) {
    unsigned char buffer[4096];
    unsigned char seen[8] = {0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U};
    int directory_fd = open(
        "/proc/self/fd", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    size_t index;
    if (directory_fd < 0) return -1;
    for (;;) {
        ssize_t amount = syscall(SYS_getdents64,
            directory_fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (amount < 0) {
            (void)close(directory_fd);
            return -1;
        }
        if (amount == 0) break;
        while (offset < (size_t)amount) {
            const struct pf_tq_test_linux_dirent64 *entry =
                (const struct pf_tq_test_linux_dirent64 *)(const void *)(
                    buffer + offset);
            size_t minimum = offsetof(
                struct pf_tq_test_linux_dirent64, d_name) + 1U;
            char *end = NULL;
            long number;
            int expected_index;
            if (entry->d_reclen < minimum ||
                    entry->d_reclen > (size_t)amount - offset ||
                    memchr(entry->d_name, '\0', entry->d_reclen -
                        offsetof(struct pf_tq_test_linux_dirent64, d_name)) == NULL) {
                (void)close(directory_fd);
                return -1;
            }
            if (strcmp(entry->d_name, ".") == 0 ||
                    strcmp(entry->d_name, "..") == 0) {
                offset += entry->d_reclen;
                continue;
            }
            errno = 0;
            number = strtol(entry->d_name, &end, 10);
            if (errno != 0 || end == entry->d_name || *end != '\0' ||
                    number < 0 || number > INT_MAX) {
                (void)close(directory_fd);
                return -1;
            }
            if ((int)number != directory_fd) {
                expected_index = pf_tq_test_fd_expected((int)number);
                if (expected_index < 0 || seen[expected_index] != 0U) {
                    (void)close(directory_fd);
                    return -1;
                }
                seen[expected_index] = 1U;
            }
            offset += entry->d_reclen;
        }
    }
    if (close(directory_fd) != 0) return -1;
    for (index = 0U; index < sizeof(seen); ++index) {
        if (seen[index] != 1U) return -1;
    }
    return 0;
}

static int pf_tq_test_adapter_exec(void) {
    pf_tq_transition_fd_identity_v2 identity;
    char error[PF_TQ_SOCKET_V2_ERROR_BYTES];
    unsigned char ready = 0x51U;
    unsigned char ack = 0U;
    if (pf_tq_test_adapter_fd_set() != 0 ||
            pf_tq_test_capture(PF_TQ_TEST_ADAPTER_FD, &identity) != 0 ||
            pf_tq_socket_endpoint_validate_v2(
                PF_TQ_TEST_ADAPTER_FD, &identity, 0,
                error, sizeof(error)) != 0 || error[0] != '\0' ||
            send(PF_TQ_TEST_ADAPTER_FD, &ready, 1U, MSG_NOSIGNAL) != 1 ||
            recv(PF_TQ_TEST_ADAPTER_FD, &ack, 1U, 0) != 1 || ack != 0xa1U) {
        return 120;
    }
    return 0;
}

static int pf_tq_test_read_fd_flags(
    int proc_root_fd,
    pid_t pid,
    int fd,
    int *close_on_exec
) {
    char path[96];
    char bytes[4096];
    char *line;
    char *end;
    unsigned long long flags;
    ssize_t amount;
    int opened;
    int rendered = snprintf(path, sizeof(path), "%ld/fdinfo/%d", (long)pid, fd);
    if (rendered <= 0 || (size_t)rendered >= sizeof(path)) return -1;
    opened = openat(proc_root_fd, path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (opened < 0) return -1;
    amount = read(opened, bytes, sizeof(bytes) - 1U);
    if (amount <= 0 || close(opened) != 0) return -1;
    bytes[amount] = '\0';
    line = strstr(bytes, "flags:\t");
    if (line == NULL) return -1;
    line += strlen("flags:\t");
    errno = 0;
    flags = strtoull(line, &end, 8);
    if (errno != 0 || end == line || (*end != '\n' && *end != '\0')) return -1;
    *close_on_exec = (flags & (unsigned long long)O_CLOEXEC) != 0U;
    return 0;
}

static int pf_tq_test_observe_adapter(
    int proc_root_fd,
    pid_t pid,
    pf_tq_transition_fd_identity_v2 *identity
) {
    char path[96];
    struct stat status;
    int close_on_exec = -1;
    int rendered = snprintf(path, sizeof(path), "%ld/fd/%d",
        (long)pid, PF_TQ_TEST_ADAPTER_FD);
    if (rendered <= 0 || (size_t)rendered >= sizeof(path) ||
            fstatat(proc_root_fd, path, &status, 0) != 0 ||
            pf_tq_test_read_fd_flags(proc_root_fd, pid,
                PF_TQ_TEST_ADAPTER_FD, &close_on_exec) != 0 || close_on_exec != 0) {
        return -1;
    }
    identity->fd = PF_TQ_TEST_ADAPTER_FD;
    identity->device = (uint64_t)status.st_dev;
    identity->inode = (uint64_t)status.st_ino;
    identity->mode = (uint64_t)status.st_mode;
    identity->fd_flags = 0;
    return 0;
}

static int pf_tq_test_observe_adapter_set(
    int proc_root_fd,
    pid_t pid,
    const pf_tq_transition_fd_role_v2 *expected,
    size_t expected_count
) {
    unsigned char seen[8] = {0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U};
    unsigned char buffer[4096];
    char path[64];
    int directory_fd;
    size_t index;
    int rendered = snprintf(path, sizeof(path), "%ld/fd", (long)pid);
    if (expected == NULL || expected_count != sizeof(seen) ||
            rendered <= 0 || (size_t)rendered >= sizeof(path)) return -1;
    directory_fd = openat(proc_root_fd, path,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory_fd < 0) return -1;
    for (;;) {
        ssize_t amount = syscall(SYS_getdents64,
            directory_fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (amount < 0) {
            (void)close(directory_fd);
            return -1;
        }
        if (amount == 0) break;
        while (offset < (size_t)amount) {
            const struct pf_tq_test_linux_dirent64 *entry =
                (const struct pf_tq_test_linux_dirent64 *)(const void *)(
                    buffer + offset);
            size_t minimum = offsetof(
                struct pf_tq_test_linux_dirent64, d_name) + 1U;
            char *end = NULL;
            long number;
            if (entry->d_reclen < minimum ||
                    entry->d_reclen > (size_t)amount - offset ||
                    memchr(entry->d_name, '\0', entry->d_reclen -
                        offsetof(struct pf_tq_test_linux_dirent64, d_name)) == NULL) {
                (void)close(directory_fd);
                return -1;
            }
            if (strcmp(entry->d_name, ".") == 0 ||
                    strcmp(entry->d_name, "..") == 0) {
                offset += entry->d_reclen;
                continue;
            }
            errno = 0;
            number = strtol(entry->d_name, &end, 10);
            if (errno != 0 || end == entry->d_name || *end != '\0') {
                (void)close(directory_fd);
                return -1;
            }
            for (index = 0U; index < expected_count; ++index) {
                if (number == expected[index].fd) break;
            }
            if (index == expected_count || seen[index] != 0U) {
                (void)close(directory_fd);
                return -1;
            }
            {
                int close_on_exec = -1;
                if (pf_tq_test_read_fd_flags(proc_root_fd, pid,
                        (int)number, &close_on_exec) != 0 ||
                        close_on_exec !=
                            (expected[index].fd_flags == FD_CLOEXEC)) {
                    (void)close(directory_fd);
                    return -1;
                }
            }
            seen[index] = 1U;
            offset += entry->d_reclen;
        }
    }
    if (close(directory_fd) != 0) return -1;
    for (index = 0U; index < sizeof(seen); ++index) {
        if (seen[index] != 1U) return -1;
    }
    return 0;
}

static int pf_tq_test_receive_ready(
    int fd,
    pid_t expected_pid
) {
    unsigned char byte = 0U;
    unsigned char control[CMSG_SPACE(sizeof(struct ucred))];
    struct iovec iov;
    struct msghdr message;
    struct cmsghdr *header;
    unsigned credentials = 0U;
    iov.iov_base = &byte;
    iov.iov_len = 1U;
    memset(&message, 0, sizeof(message));
    memset(control, 0, sizeof(control));
    message.msg_iov = &iov;
    message.msg_iovlen = 1U;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);
    if (recvmsg(fd, &message, 0) != 1 || byte != 0x51U ||
            (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0) return -1;
    for (header = CMSG_FIRSTHDR(&message); header != NULL;
            header = CMSG_NXTHDR(&message, header)) {
        struct ucred observed;
        if (header->cmsg_level != SOL_SOCKET ||
                header->cmsg_type != SCM_CREDENTIALS ||
                header->cmsg_len != CMSG_LEN(sizeof(observed)) ||
                ++credentials != 1U) return -1;
        memcpy(&observed, CMSG_DATA(header), sizeof(observed));
        if (observed.pid != expected_pid || observed.uid != getuid() ||
                observed.gid != getgid()) return -1;
    }
    return credentials == 1U ? 0 : -1;
}

static int pf_tq_test_positive(const char *self_path) {
    pf_tq_isolation_policy_v2 policy;
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT];
    pf_tq_handoff_channels_v2 channels = pf_tq_test_channels();
    pf_tq_socket_pair_v2 pair;
    pf_tq_transition_fd_identity_v2 service_identity;
    pf_tq_transition_fd_identity_v2 adapter_observed;
    pf_tq_transition_fd_role_v2 adapter_roles[
        PF_TQ_FD_MANIFEST_V2_ADAPTER_STEADY_COUNT + 3U];
    size_t adapter_role_count = 0U;
    char error[PF_TQ_SOCKET_V2_ERROR_BYTES];
    int proc_root_fd;
    int executable_fd;
    int filler_fd;
    int channel_fd;
    int status = 0;
    pid_t child;
    unsigned char ack = 0xa1U;
    pf_tq_test_close_all();
    proc_root_fd = open("/proc", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (proc_root_fd != 3) pf_tq_test_die("positive-proc-root");
    pf_tq_test_policy(&policy, roles);
    if (pf_tq_fd_manifest_project_v2(&policy, &channels,
            "adapter", "steady", adapter_roles,
            sizeof(adapter_roles) / sizeof(adapter_roles[0]),
            &adapter_role_count, error, sizeof(error)) != 0 ||
            error[0] != '\0' ||
            adapter_role_count != sizeof(adapter_roles) / sizeof(adapter_roles[0]) ||
            pf_tq_socket_pair_create_v2(
                &policy, &channels, &pair, error, sizeof(error)) != 0 ||
            error[0] != '\0' || pair.adapter_fd != PF_TQ_TEST_ADAPTER_FD ||
            pair.service_fd != PF_TQ_TEST_SERVICE_FD) {
        pf_tq_test_die("positive-create");
    }
    executable_fd = open(self_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (executable_fd != 6) pf_tq_test_die("positive-executable");
    for (filler_fd = 7; filler_fd <= 9; ++filler_fd) {
        if (open("/dev/null", O_RDONLY | O_CLOEXEC) != filler_fd) {
            pf_tq_test_die("positive-filler");
        }
    }
    for (channel_fd = 10; channel_fd <= 13; ++channel_fd) {
        if (open("/dev/null", O_RDONLY) != channel_fd) {
            pf_tq_test_die("positive-channel-fd");
        }
    }
    child = fork();
    if (child < 0) pf_tq_test_die("positive-fork");
    if (child == 0) {
        char *const arguments[] = {(char *)self_path, "--adapter-exec", NULL};
        char *const environment[] = {NULL};
        pf_tq_transition_fd_identity_v2 adapter_identity;
        if (pf_tq_socket_pair_select_v2(&pair, PF_TQ_SOCKET_ADAPTER_V2,
                error, sizeof(error)) != 0 ||
                pf_tq_socket_endpoint_prepare_exec_v2(
                    &pair, PF_TQ_SOCKET_ADAPTER_V2, &adapter_identity,
                    error, sizeof(error)) != 0 || error[0] != '\0' ||
                raise(SIGSTOP) != 0) {
            _exit(121);
        }
        (void)syscall(SYS_execveat, executable_fd, "",
            arguments, environment, AT_EMPTY_PATH);
        _exit(122);
    }
    if (waitpid(child, &status, WUNTRACED) != child ||
            !WIFSTOPPED(status) || WSTOPSIG(status) != SIGSTOP ||
            pf_tq_socket_pair_select_v2(&pair, PF_TQ_SOCKET_SERVICE_V2,
                error, sizeof(error)) != 0 ||
            pf_tq_socket_endpoint_prepare_exec_v2(
                &pair, PF_TQ_SOCKET_SERVICE_V2, &service_identity,
                error, sizeof(error)) != 0 || error[0] != '\0' ||
            pf_tq_socket_service_enable_credentials_v2(
                PF_TQ_TEST_SERVICE_FD, &service_identity,
                error, sizeof(error)) != 0 || error[0] != '\0') {
        pf_tq_test_die("positive-parent-prepare");
    }
    if (close(executable_fd) != 0) {
        pf_tq_test_die("positive-parent-executable-close");
    }
    for (filler_fd = 7; filler_fd <= 9; ++filler_fd) {
        if (close(filler_fd) != 0) pf_tq_test_die("positive-parent-filler-close");
    }
    for (channel_fd = 10; channel_fd <= 13; ++channel_fd) {
        if (close(channel_fd) != 0) pf_tq_test_die("positive-parent-channel-close");
    }
    if (kill(child, SIGCONT) != 0) pf_tq_test_die("positive-child-continue");
    if (pf_tq_test_receive_ready(PF_TQ_TEST_SERVICE_FD, child) != 0 ||
            pf_tq_test_observe_adapter_set(proc_root_fd, child,
                adapter_roles, adapter_role_count) != 0 ||
            pf_tq_test_observe_adapter(
                proc_root_fd, child, &adapter_observed) != 0 ||
            pf_tq_socket_lineage_validate_v2(&pair,
                &adapter_observed, &service_identity,
                error, sizeof(error)) != 0 || error[0] != '\0' ||
            pf_tq_socket_endpoint_validate_v2(PF_TQ_TEST_SERVICE_FD,
                &service_identity, 1, error, sizeof(error)) != 0 ||
            error[0] != '\0' ||
            send(PF_TQ_TEST_SERVICE_FD, &ack, 1U, MSG_NOSIGNAL) != 1 ||
            waitpid(child, &status, 0) != child || !WIFEXITED(status) ||
            WEXITSTATUS(status) != 0) {
        pf_tq_test_die("positive-lineage");
    }
    if (close(PF_TQ_TEST_SERVICE_FD) != 0 || close(proc_root_fd) != 0) {
        pf_tq_test_die("positive-cleanup");
    }
    return 0;
}

static int pf_tq_test_rejected_result(int result, const char *error) {
    return result != 0 && error != NULL && error[0] != '\0' ? 0 : 123;
}

static int pf_tq_test_negative(const char *mode) {
    pf_tq_isolation_policy_v2 policy;
    pf_tq_isolation_fd_role_v2 roles[PF_TQ_FD_MANIFEST_V2_COUNT];
    pf_tq_handoff_channels_v2 channels = pf_tq_test_channels();
    pf_tq_socket_pair_v2 pair;
    pf_tq_transition_fd_identity_v2 identity;
    pf_tq_transition_fd_identity_v2 adapter;
    pf_tq_transition_fd_identity_v2 service;
    char error[PF_TQ_SOCKET_V2_ERROR_BYTES];
    int result;
    pf_tq_test_close_all();
    pf_tq_test_policy(&policy, roles);
    memset(&pair, 0, sizeof(pair));
    error[0] = '\0';

    if (strcmp(mode, "invalid-api") == 0) {
        result = pf_tq_socket_pair_create_v2(
            NULL, NULL, NULL, error, sizeof(error));
        return pf_tq_test_rejected_result(result, error);
    }
    if (strcmp(mode, "allocation-order") == 0) {
        result = pf_tq_socket_pair_create_v2(
            &policy, &channels, &pair, error, sizeof(error));
        if (result == 0 || error[0] == '\0') return 124;
        pf_tq_test_require_closed(3, "allocation-order-left-fd3");
        pf_tq_test_require_closed(4, "allocation-order-left-fd4");
        return 0;
    }
    if (open("/proc", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) != 3) {
        pf_tq_test_die("negative-proc-root");
    }
    if (strcmp(mode, "occupied-fixed-fd") == 0) {
        if (open("/dev/null", O_RDONLY | O_CLOEXEC) != 4) {
            pf_tq_test_die("occupied-open");
        }
        result = pf_tq_socket_pair_create_v2(
            &policy, &channels, &pair, error, sizeof(error));
        if (pf_tq_test_rejected_result(result, error) != 0 ||
                fcntl(4, F_GETFD) < 0) return 125;
        return 0;
    }
    if (strcmp(mode, "reversed-endpoints") == 0) {
        pf_tq_test_reverse_endpoints(&policy, &channels);
        result = pf_tq_socket_pair_create_v2(
            &policy, &channels, &pair, error, sizeof(error));
        if (pf_tq_test_rejected_result(result, error) != 0) return 126;
        pf_tq_test_require_closed(4, "reversed-left-fd4");
        pf_tq_test_require_closed(5, "reversed-left-fd5");
        return 0;
    }
    if (strcmp(mode, "manifest-channel") == 0) {
        ++channels.candidate_archive_fd;
        result = pf_tq_socket_pair_create_v2(
            &policy, &channels, &pair, error, sizeof(error));
        if (pf_tq_test_rejected_result(result, error) != 0) return 127;
        pf_tq_test_require_closed(4, "manifest-channel-left-fd4");
        pf_tq_test_require_closed(5, "manifest-channel-left-fd5");
        return 0;
    }
    if (pf_tq_socket_pair_create_v2(
            &policy, &channels, &pair, error, sizeof(error)) != 0) {
        return 128;
    }
    if (strcmp(mode, "prepare-before-select") == 0) {
        result = pf_tq_socket_endpoint_prepare_exec_v2(
            &pair, PF_TQ_SOCKET_ADAPTER_V2, &identity,
            error, sizeof(error));
    } else if (strcmp(mode, "select-repeat") == 0) {
        if (pf_tq_socket_pair_select_v2(&pair, PF_TQ_SOCKET_ADAPTER_V2,
                error, sizeof(error)) != 0) return 129;
        error[0] = '\0';
        result = pf_tq_socket_pair_select_v2(
            &pair, PF_TQ_SOCKET_ADAPTER_V2, error, sizeof(error));
    } else if (strcmp(mode, "prepare-repeat") == 0) {
        if (pf_tq_socket_pair_select_v2(&pair, PF_TQ_SOCKET_ADAPTER_V2,
                error, sizeof(error)) != 0 ||
                pf_tq_socket_endpoint_prepare_exec_v2(
                    &pair, PF_TQ_SOCKET_ADAPTER_V2, &identity,
                    error, sizeof(error)) != 0) return 130;
        error[0] = '\0';
        result = pf_tq_socket_endpoint_prepare_exec_v2(
            &pair, PF_TQ_SOCKET_ADAPTER_V2, &identity,
            error, sizeof(error));
    } else if (strcmp(mode, "wrong-role") == 0) {
        result = pf_tq_socket_pair_select_v2(
            &pair, (pf_tq_socket_endpoint_role_v2)0,
            error, sizeof(error));
    } else if (strcmp(mode, "buffer-drift") == 0) {
        int small = 1024;
        if (pf_tq_socket_pair_select_v2(&pair, PF_TQ_SOCKET_SERVICE_V2,
                error, sizeof(error)) != 0 ||
                setsockopt(PF_TQ_TEST_SERVICE_FD, SOL_SOCKET, SO_SNDBUF,
                    &small, sizeof(small)) != 0) return 131;
        error[0] = '\0';
        result = pf_tq_socket_endpoint_prepare_exec_v2(
            &pair, PF_TQ_SOCKET_SERVICE_V2, &identity,
            error, sizeof(error));
    } else if (strcmp(mode, "endpoint-replacement") == 0) {
        if (close(PF_TQ_TEST_SERVICE_FD) != 0 ||
                socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0) !=
                    PF_TQ_TEST_SERVICE_FD) return 132;
        result = pf_tq_socket_pair_select_v2(
            &pair, PF_TQ_SOCKET_SERVICE_V2, error, sizeof(error));
    } else if (strcmp(mode, "service-before-exec") == 0) {
        result = pf_tq_socket_service_enable_credentials_v2(
            PF_TQ_TEST_SERVICE_FD, &pair.service_created,
            error, sizeof(error));
    } else if (strcmp(mode, "service-passcred-already") == 0) {
        int enabled = 1;
        if (pf_tq_socket_pair_select_v2(&pair, PF_TQ_SOCKET_SERVICE_V2,
                error, sizeof(error)) != 0 ||
                pf_tq_socket_endpoint_prepare_exec_v2(
                    &pair, PF_TQ_SOCKET_SERVICE_V2, &identity,
                    error, sizeof(error)) != 0 ||
                setsockopt(PF_TQ_TEST_SERVICE_FD, SOL_SOCKET, SO_PASSCRED,
                    &enabled, sizeof(enabled)) != 0) return 133;
        error[0] = '\0';
        result = pf_tq_socket_service_enable_credentials_v2(
            PF_TQ_TEST_SERVICE_FD, &identity, error, sizeof(error));
    } else if (strcmp(mode, "endpoint-expected-flags") == 0) {
        identity = pair.adapter_created;
        identity.fd_flags = 0;
        result = pf_tq_socket_endpoint_validate_v2(
            PF_TQ_TEST_ADAPTER_FD, &identity, 0, error, sizeof(error));
    } else if (strcmp(mode, "lineage-flags") == 0 ||
            strcmp(mode, "lineage-inode") == 0 ||
            strcmp(mode, "lineage-alias") == 0) {
        adapter = pair.adapter_created;
        service = pair.service_created;
        adapter.fd_flags = 0;
        service.fd_flags = 0;
        if (strcmp(mode, "lineage-flags") == 0) {
            adapter.fd_flags = FD_CLOEXEC;
        } else if (strcmp(mode, "lineage-inode") == 0) {
            ++adapter.inode;
        } else {
            service = adapter;
            service.fd = PF_TQ_TEST_SERVICE_FD;
        }
        result = pf_tq_socket_lineage_validate_v2(
            &pair, &adapter, &service, error, sizeof(error));
    } else {
        return 134;
    }
    return pf_tq_test_rejected_result(result, error);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--adapter-exec") == 0) {
        return pf_tq_test_adapter_exec();
    }
    if (argc == 2 && strcmp(argv[1], "positive-exec-lineage") == 0) {
        return pf_tq_test_positive(argv[0]);
    }
    if (argc == 2) return pf_tq_test_negative(argv[1]);
    return 2;
}
