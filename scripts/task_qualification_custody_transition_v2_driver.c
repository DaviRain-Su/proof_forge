#define _GNU_SOURCE
/* Test-owned driver for the sealed supervisor->service custody transition. */
#include "task_qualification_custody_transition_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/memfd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static const unsigned char executable_ref[] =
    "{\"digest\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\","
    "\"id\":\"transition-test-executable\","
    "\"schema\":\"proof-forge.task-qualification-artifact-payload.v1\","
    "\"version\":\"1.0.0\"}";

static const char *const seed_slots[4] = {
    "service", "role-0", "role-1", "role-2"
};

static const char *const seed_keys[4] = {
    "service", "key-architecture", "key-quality", "key-security"
};

static void die(const char *where) {
    int saved = errno;
    fprintf(stderr, "PF-TRANSITION-DRIVER:%s:errno=%d\n", where, saved);
    fflush(stderr);
    _exit(111);
}

static void fail(const char *where) {
    errno = 0;
    die(where);
}

static void close_all(void) {
    if (syscall(SYS_close_range, 3U, UINT_MAX, 0U) != 0) die("close-range");
}

static void create_seed_paths(char paths[4][64]) {
    size_t index;
    for (index = 0U; index < 4U; ++index) {
        int fd;
        unsigned char content[32];
        (void)snprintf(paths[index], 64U, "transition-seed-%ld-%zu",
            (long)getpid(), index);
        memset(content, (int)(index + 1U), sizeof(content));
        fd = open(paths[index], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0400);
        if (fd != 7) die("create-seed-path");
        if (fchmod(fd, 0400) != 0 || write(fd, content, sizeof(content)) !=
                (ssize_t)sizeof(content) || fsync(fd) != 0 || close(fd) != 0) {
            die("write-seed-path");
        }
    }
}

static void open_seed_fds(char paths[4][64]) {
    size_t index;
    for (index = 0U; index < 4U; ++index) {
        int fd = open(paths[index], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        if (fd != 7 + (int)index || fcntl(fd, F_SETFD, 0) != 0) {
            die("open-seed-fixed-fd");
        }
    }
}

static void cleanup_seed_paths(char paths[4][64]) {
    size_t index;
    for (index = 0U; index < 4U; ++index) {
        (void)close(7 + (int)index);
        if (unlink(paths[index]) != 0) die("unlink-seed-path");
    }
}

static void setup_data(
    const char *self_path,
    pf_tq_custody_transition_data_v2 *data,
    char paths[4][64]
) {
    int endpoints[2];
    int proc_root_fd;
    int executable_fd;
    size_t index;
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES];
    close_all();
    proc_root_fd = open("/proc", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (proc_root_fd != 3) die("open-proc-root");
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, endpoints) != 0 ||
            endpoints[0] != 4 || endpoints[1] != 5 ||
            fcntl(endpoints[0], F_SETFD, 0) != 0 ||
            fcntl(endpoints[1], F_SETFD, 0) != 0) {
        die("socketpair-fixed-fds");
    }
    executable_fd = open(self_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (executable_fd != 6) die("open-executable-fixed-fd");
    create_seed_paths(paths);
    open_seed_fds(paths);
    memset(data, 0, sizeof(*data));
    if (pf_tq_transition_self_identity_v2(proc_root_fd,
            &data->supervisor_pid, &data->start_time_ticks,
            &data->user_namespace, &data->pid_namespace,
            error, sizeof(error)) != 0 ||
            pf_tq_transition_capture_fd_v2(4, &data->adapter_endpoint,
                error, sizeof(error)) != 0 ||
            pf_tq_transition_capture_fd_v2(5, &data->service_endpoint,
                error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-TRANSITION-DRIVER:setup:%s\n", error);
        _exit(112);
    }
    data->adapter_pid = getppid();
    if (data->adapter_pid <= 0 || data->adapter_pid == data->supervisor_pid) {
        fail("adapter-pid-fixture");
    }
    data->service_executable_fd = 6;
    data->service_executable_ref.bytes = executable_ref;
    data->service_executable_ref.size = sizeof(executable_ref) - 1U;
    for (index = 0U; index < 32U; ++index) {
        data->service_executable_payload_sha256[index] = (unsigned char)index;
    }
    for (index = 0U; index < 4U; ++index) {
        struct stat status;
        if (fstat(7 + (int)index, &status) != 0) die("fstat-seed");
        data->seeds[index].slot = seed_slots[index];
        data->seeds[index].key_id = seed_keys[index];
        data->seeds[index].fd = 7 + (int)index;
        data->seeds[index].device = (uint64_t)status.st_dev;
        data->seeds[index].inode = (uint64_t)status.st_ino;
    }
}

static size_t build_fd_roles(
    pf_tq_transition_fd_role_v2 roles[16],
    int include_executable,
    int include_transition
) {
    size_t count = 0U;
    int fd;
    for (fd = 0; fd <= 5; ++fd) {
        roles[count].fd = fd;
        roles[count].fd_flags = fd == 3 ? FD_CLOEXEC : 0;
        ++count;
    }
    if (include_executable) {
        roles[count].fd = 6;
        roles[count].fd_flags = FD_CLOEXEC;
        ++count;
    }
    for (fd = 7; fd <= 10; ++fd) {
        roles[count].fd = fd;
        roles[count].fd_flags = 0;
        ++count;
    }
    if (include_transition) {
        roles[count].fd = 11;
        roles[count].fd_flags = 0;
        ++count;
    }
    return count;
}

static int validate_fd_roles(int include_executable, int include_transition) {
    pf_tq_transition_fd_role_v2 roles[16];
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES];
    size_t count = build_fd_roles(roles, include_executable, include_transition);
    int result = pf_tq_transition_validate_fd_roles_v2(
        3, roles, count, error, sizeof(error));
    if (result != 0) {
        fprintf(stderr, "PF-TRANSITION-DRIVER:fd-roles:%s\n", error);
    }
    return result;
}

static void require_closed(int fd, const char *where) {
    errno = 0;
    if (fcntl(fd, F_GETFD) != -1 || errno != EBADF) fail(where);
}

static int create_transition(
    int transition_fd,
    pf_tq_custody_transition_data_v2 *data,
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES]
) {
    return pf_tq_custody_transition_create_v2(
        transition_fd, 3, data, error, PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES);
}

static int consume_transition(
    int transition_fd,
    pf_tq_custody_transition_data_v2 *data,
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES]
) {
    return pf_tq_custody_transition_consume_v2(
        transition_fd, 3, data, error, PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES);
}

static int finish(char paths[4][64]) {
    (void)close(4);
    (void)close(5);
    (void)close(6);
    cleanup_seed_paths(paths);
    (void)close(3);
    return 0;
}

static int positive(
    pf_tq_custody_transition_data_v2 *data,
    char paths[4][64]
) {
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES];
    static const unsigned char byte = 1U;
    if (validate_fd_roles(1, 0) != 0 ||
            create_transition(11, data, error) != 0 || error[0] != '\0' ||
            validate_fd_roles(1, 1) != 0 ||
            pwrite(11, &byte, 1U, 0) != -1 || errno != EPERM ||
            close(6) != 0 || validate_fd_roles(0, 1) != 0 ||
            consume_transition(11, data, error) != 0 || error[0] != '\0' ||
            validate_fd_roles(0, 0) != 0) {
        fprintf(stderr, "PF-TRANSITION-DRIVER:positive:%s\n", error);
        return 120;
    }
    require_closed(11, "positive-transition-not-consumed");
    return finish(paths);
}

static int create_negative(
    int mode,
    pf_tq_custody_transition_data_v2 *data,
    char paths[4][64]
) {
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES];
    int transition_fd = mode == 1 ? 12 : 11;
    int occupied = -1;
    int result;
    if (mode == 2) {
        occupied = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (occupied != 11) die("occupy-transition-fd");
    }
    if (mode == 3) data->service_endpoint.inode ^= 1U;
    if (mode == 4) data->user_namespace.inode ^= 1U;
    if (mode == 5) data->start_time_ticks ^= 1U;
    if (mode == 6) data->seeds[2].key_id = "key-a";
    if (mode == 7) data->seeds[2].inode ^= 1U;
    if (mode == 8 && fcntl(8, F_SETFD, FD_CLOEXEC) != 0) die("seed-cloexec");
    if (mode == 9 && fcntl(6, F_SETFD, 0) != 0) die("executable-no-cloexec");
    if (mode == 10) data->adapter_endpoint.fd_flags = FD_CLOEXEC;
    if (mode == 18) data->service_endpoint = data->adapter_endpoint;
    if (mode == 19) data->seeds[2].inode = data->seeds[1].inode;
    if (mode == 20) data->service_executable_ref.size -= 1U;
    if (mode == 21) data->service_executable_fd = 3;
    if (mode == 22) transition_fd = 13;
    result = create_transition(transition_fd, data, error);
    if (result == 0 || error[0] == '\0') return 121;
    if (occupied >= 0) {
        if (close(occupied) != 0) return 122;
    } else {
        require_closed(11, "failed-create-left-transition-fd");
        require_closed(12, "failed-create-left-alternate-fd");
    }
    return finish(paths);
}

static int manual_unsealed(void) {
    static const unsigned char empty[] = "{}";
    int fd = (int)syscall(SYS_memfd_create,
        "pf-tq-custody-transition", MFD_ALLOW_SEALING);
    if (fd != 11 || write(fd, empty, sizeof(empty) - 1U) !=
            (ssize_t)(sizeof(empty) - 1U)) {
        die("manual-unsealed-transition");
    }
    return fd;
}

static int consume_negative(
    int mode,
    pf_tq_custody_transition_data_v2 *data,
    char paths[4][64]
) {
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES];
    int result;
    if (mode == 12 || mode == 13) {
        int fd = manual_unsealed();
        if (mode == 13 && fcntl(fd, F_ADD_SEALS, F_SEAL_GROW) != 0) {
            die("manual-partial-seal");
        }
    } else if (create_transition(11, data, error) != 0) {
        return 123;
    }
    if (mode != 16 && close(6) != 0) die("close-executable-before-consume");
    if (mode == 11) data->start_time_ticks ^= 1U;
    if (mode == 14) data->service_executable_payload_sha256[0] ^= 1U;
    if (mode == 15) data->supervisor_pid += 1;
    if (mode == 17) {
        if (close(5) != 0 || open("/dev/null", O_RDONLY) != 5) {
            die("replace-service-endpoint");
        }
    }
    result = consume_transition(11, data, error);
    if (result == 0 || error[0] == '\0') return 124;
    require_closed(11, "failed-consume-left-transition-fd");
    return finish(paths);
}

static int fd_roles_negative(
    int mode,
    char paths[4][64]
) {
    pf_tq_transition_fd_role_v2 roles[16];
    char error[PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES];
    size_t count = build_fd_roles(roles, 1, 0);
    int extra = -1;
    int result;
    if (mode == 23) {
        extra = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (extra != 11) die("extra-fd-role");
    }
    if (mode == 24) {
        roles[count].fd = 11;
        roles[count].fd_flags = FD_CLOEXEC;
        ++count;
    }
    if (mode == 25) roles[3].fd_flags = 0;
    if (mode == 26) {
        pf_tq_transition_fd_role_v2 temporary = roles[7];
        roles[7] = roles[8];
        roles[8] = temporary;
    }
    result = pf_tq_transition_validate_fd_roles_v2(
        3, roles, count, error, sizeof(error));
    if (result == 0 || error[0] == '\0') return 125;
    if (extra >= 0 && close(extra) != 0) return 126;
    return finish(paths);
}

int main(int argc, char **argv) {
    pf_tq_custody_transition_data_v2 data;
    char paths[4][64];
    int mode;
    if (argc != 2) return 2;
    mode = atoi(argv[1]);
    setup_data(argv[0], &data, paths);
    if (mode == 0) return positive(&data, paths);
    if ((mode >= 1 && mode <= 10) || (mode >= 18 && mode <= 22)) {
        return create_negative(mode, &data, paths);
    }
    if (mode >= 11 && mode <= 17) {
        return consume_negative(mode, &data, paths);
    }
    if (mode >= 23 && mode <= 26) {
        return fd_roles_negative(mode, paths);
    }
    return 2;
}
