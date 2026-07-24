#define _GNU_SOURCE
/* Test-owned eligible-kernel driver for the production transition component. */
#include "task_qualification_kernel_transition_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/capability.h>
#include <limits.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

#define ADAPTER_UID ((uid_t)1001)
#define SERVICE_UID ((uid_t)1002)
#define ADAPTER_GID ((gid_t)1003)
#define SERVICE_GID ((gid_t)1004)

static void die(const char *where) {
    int saved = errno;
    fprintf(stderr, "PF-KERNEL-DRIVER:%s:errno=%d\n", where, saved);
    fflush(stderr);
    _exit(111);
}

static void fail(const char *where) {
    errno = 0;
    die(where);
}

static int open_proc_root(int close_on_exec) {
    int flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW;
    int fd;
    if (close_on_exec) flags |= O_CLOEXEC;
    fd = open("/proc", flags);
    if (fd != 3) {
        fprintf(stderr, "PF-KERNEL-DRIVER:open-proc-root-fixed-fd:got=%d\n", fd);
        _exit(111);
    }
    return fd;
}

static void emit_checkpoint(
    int proc_root_fd,
    const char *label,
    pf_tq_kernel_crosscheck_v2 crosscheck
) {
    pf_tq_kernel_snapshot_v2 state;
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    if (pf_tq_kernel_snapshot_read_v2(proc_root_fd, crosscheck,
            &state, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:snapshot:%s\n", error);
        _exit(112);
    }
    printf("PF-KERNEL-CHECKPOINT label=%s bnd=%016llx prm=%016llx "
           "eff=%016llx inh=%016llx amb=%016llx uid=%u gid=%u groups=%d nnp=%d\n",
        label, (unsigned long long)state.bounding,
        (unsigned long long)state.permitted,
        (unsigned long long)state.effective,
        (unsigned long long)state.inheritable,
        (unsigned long long)state.ambient,
        (unsigned)state.uid[1], (unsigned)state.gid[1],
        state.supplementary_group_count, state.no_new_privs);
    fflush(stdout);
}

static void expect_rejected(int result, const char *error, const char *where) {
    if (result == 0 || error == NULL || error[0] == '\0') fail(where);
    _exit(0);
}

static void local_capset(uint64_t inheritable, uint64_t permitted, uint64_t effective) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));
    data[0].inheritable = (uint32_t)inheritable;
    data[1].inheritable = (uint32_t)(inheritable >> 32U);
    data[0].permitted = (uint32_t)permitted;
    data[1].permitted = (uint32_t)(permitted >> 32U);
    data[0].effective = (uint32_t)effective;
    data[1].effective = (uint32_t)(effective >> 32U);
    if (syscall(SYS_capset, &header, data) != 0) die("local-capset");
}

static int open_self_executable(const char *self_path) {
    int executable_fd = open(self_path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (executable_fd != 4) die("open-self-fixed-fd");
    return executable_fd;
}

static void exec_self(int executable_fd, const char *mode) {
    char *const argv[] = {(char *)"pf-kernel-transition-v2-test", (char *)mode, NULL};
    char *const environment[] = {NULL};
    if (executable_fd != 4) fail("exec-self-fd-drift");
    syscall(SYS_execveat, executable_fd, "", argv, environment, AT_EMPTY_PATH);
    die("execveat-self");
}

static int service_child_positive(void) {
    int proc_root_fd = 3;
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    emit_checkpoint(proc_root_fd, "service-post-exec",
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2);
    if (pf_tq_kernel_service_post_exec_v2(proc_root_fd,
            SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:post-exec:%s\n", error);
        return 113;
    }
    emit_checkpoint(proc_root_fd, "service-steady",
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2);
    if (pf_tq_kernel_terminal_lockdown_v2(proc_root_fd,
            SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:terminal:%s\n", error);
        return 114;
    }
    emit_checkpoint(proc_root_fd, "service-terminal",
        PF_TQ_KERNEL_CROSSCHECK_FILTERED_V2);
    return 0;
}

static int service_child_expected_rejection(const char *mode) {
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    int result;
    if (strcmp(mode, "--post-no-nnp-child") == 0 ||
            strcmp(mode, "--post-old-child") == 0) {
        result = pf_tq_kernel_service_post_exec_v2(
            3, SERVICE_UID, SERVICE_GID, error, sizeof(error));
    } else if (strcmp(mode, "--post-wrong-id-child") == 0) {
        result = pf_tq_kernel_service_post_exec_v2(
            3, SERVICE_UID + 1U, SERVICE_GID, error, sizeof(error));
    } else if (strcmp(mode, "--terminal-repeat-child") == 0) {
        if (pf_tq_kernel_service_post_exec_v2(
                3, SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0 ||
                pf_tq_kernel_terminal_lockdown_v2(
                    3, SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
            return 116;
        }
        result = pf_tq_kernel_terminal_lockdown_v2(
            3, SERVICE_UID, SERVICE_GID, error, sizeof(error));
    } else {
        return 2;
    }
    if (result == 0 || error[0] == '\0') return 115;
    return 0;
}

static void adapter_positive(void) {
    int proc_root_fd = 3;
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    if (pf_tq_kernel_isolate_adapter_v2(proc_root_fd,
            ADAPTER_UID, ADAPTER_GID, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:adapter:%s\n", error);
        _exit(116);
    }
    emit_checkpoint(proc_root_fd, "adapter-final",
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2);
    if (close(proc_root_fd) != 0) die("close-adapter-proc");
    _exit(0);
}

static void service_positive(const char *self_path) {
    int proc_root_fd = 3;
    int executable_fd = open_self_executable(self_path);
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    if (pf_tq_kernel_prepare_custody_v2(proc_root_fd,
            SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0 ||
            pf_tq_kernel_custody_no_new_privs_v2(proc_root_fd,
                SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:service-prepare:%s\n", error);
        _exit(117);
    }
    emit_checkpoint(proc_root_fd, "service-pre-exec",
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2);
    exec_self(executable_fd, "--service-child");
}

static void run_negative(const char *mode, const char *self_path) {
    int needs_exec = strcmp(mode, "--post-no-nnp") == 0 ||
        strcmp(mode, "--post-wrong-id") == 0 || strcmp(mode, "--post-old") == 0 ||
        strcmp(mode, "--terminal-repeat") == 0;
    int proc_root_fd = 3;
    int executable_fd = needs_exec ? open_self_executable(self_path) : -1;
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    int result;
    if (strcmp(mode, "--adapter-wrong-id") == 0) {
        result = pf_tq_kernel_isolate_adapter_v2(
            proc_root_fd, ADAPTER_UID + 10U, ADAPTER_GID,
            error, sizeof(error));
        expect_rejected(result, error, "adapter-wrong-id-accepted");
    }
    if (strcmp(mode, "--prepare-nnp-early") == 0) {
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) die("early-nnp");
        result = pf_tq_kernel_prepare_custody_v2(
            proc_root_fd, SERVICE_UID, SERVICE_GID, error, sizeof(error));
        expect_rejected(result, error, "prepare-early-nnp-accepted");
    }
    if (strcmp(mode, "--prepare-wrong-id") == 0) {
        result = pf_tq_kernel_prepare_custody_v2(
            proc_root_fd, 65534U, SERVICE_GID, error, sizeof(error));
        expect_rejected(result, error, "prepare-overflow-id-accepted");
    }
    if (strcmp(mode, "--terminal-early") == 0) {
        if (pf_tq_kernel_prepare_custody_v2(proc_root_fd,
                SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0 ||
                pf_tq_kernel_custody_no_new_privs_v2(proc_root_fd,
                    SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
            die("terminal-early-prepare");
        }
        result = pf_tq_kernel_terminal_lockdown_v2(
            proc_root_fd, SERVICE_UID, SERVICE_GID, error, sizeof(error));
        expect_rejected(result, error, "terminal-early-accepted");
    }
    if (pf_tq_kernel_prepare_custody_v2(proc_root_fd,
            SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:negative-prepare:%s\n", error);
        _exit(118);
    }
    if (strcmp(mode, "--post-no-nnp") == 0) {
        exec_self(executable_fd, "--post-no-nnp-child");
    }
    if (strcmp(mode, "--post-wrong-id") == 0) {
        if (pf_tq_kernel_custody_no_new_privs_v2(proc_root_fd,
                SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
            die("post-wrong-id-nnp");
        }
        exec_self(executable_fd, "--post-wrong-id-child");
    }
    if (strcmp(mode, "--terminal-repeat") == 0) {
        if (pf_tq_kernel_custody_no_new_privs_v2(proc_root_fd,
                SERVICE_UID, SERVICE_GID, error, sizeof(error)) != 0) {
            die("terminal-repeat-nnp");
        }
        exec_self(executable_fd, "--terminal-repeat-child");
    }
    if (strcmp(mode, "--post-old") == 0) {
        if (prctl(PR_CAPBSET_DROP, PF_TQ_KERNEL_V2_CAP_SETPCAP, 0, 0, 0) != 0 ||
                prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
            die("old-transition-prctl");
        }
        local_capset(0U, PF_TQ_KERNEL_V2_STEADY_MASK,
            PF_TQ_KERNEL_V2_STEADY_MASK);
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) die("old-transition-nnp");
        exec_self(executable_fd, "--post-old-child");
    }
    fail("unknown-negative-mode");
}

static int wait_success(pid_t child, const char *where) {
    int status = 0;
    if (waitpid(child, &status, 0) != child) die("waitpid");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:%s:status=%d\n", where, status);
        return -1;
    }
    return 0;
}

static void run_inside_namespace(const char *mode, const char *self_path) {
    int proc_root_fd = open_proc_root(0);
    char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
    int result;
    if (strcmp(mode, "--preseed-missing") == 0) {
        if (prctl(PR_CAPBSET_DROP, PF_TQ_KERNEL_V2_CAP_SYS_ADMIN, 0, 0, 0) != 0) {
            die("preseed-drop-sys-admin");
        }
        result = pf_tq_kernel_converge_preseed_v2(
            proc_root_fd, error, sizeof(error));
        expect_rejected(result, error, "preseed-missing-accepted");
    }
    if (strcmp(mode, "--preseed-nnp") == 0) {
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) die("preseed-early-nnp");
        result = pf_tq_kernel_converge_preseed_v2(
            proc_root_fd, error, sizeof(error));
        expect_rejected(result, error, "preseed-nnp-accepted");
    }
    if (pf_tq_kernel_converge_preseed_v2(
            proc_root_fd, error, sizeof(error)) != 0) {
        fprintf(stderr, "PF-KERNEL-DRIVER:preseed:%s\n", error);
        _exit(123);
    }
    if (strcmp(mode, "--positive") == 0) {
        pid_t adapter = fork();
        pid_t service;
        if (adapter < 0) die("fork-adapter");
        if (adapter == 0) adapter_positive();
        if (wait_success(adapter, "adapter") != 0) _exit(119);
        service = fork();
        if (service < 0) die("fork-service");
        if (service == 0) service_positive(self_path);
        if (wait_success(service, "service") != 0) _exit(120);
        _exit(0);
    }
    run_negative(mode, self_path);
}

static int run_helper(const char *path, char *const argv[]) {
    pid_t child = fork();
    int status = 0;
    if (child < 0) die("fork-map-helper");
    if (child == 0) {
        execv(path, argv);
        die("exec-map-helper");
    }
    if (waitpid(child, &status, 0) != child) die("wait-map-helper");
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128;
}

static unsigned parse_id(const char *raw) {
    char *end = NULL;
    unsigned long value;
    if (raw == NULL || raw[0] == '\0') fail("empty-outside-id");
    errno = 0;
    value = strtoul(raw, &end, 10);
    if (errno != 0 || end == raw || *end != '\0' || value > UINT32_MAX) {
        fail("invalid-outside-id");
    }
    return (unsigned)value;
}

static void install_maps(pid_t child, const unsigned outside[4]) {
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
    if (run_helper(uid_argv[0], uid_argv) != 0) die("newuidmap");
    if (run_helper(gid_argv[0], gid_argv) != 0) die("newgidmap");
}

static int top_level(
    const char *mode,
    const char *self_path,
    const unsigned outside[4]
) {
    int ready[2], go[2];
    pid_t child;
    char marker = 0;
    size_t left, right;
    for (left = 0U; left < 4U; ++left) {
        for (right = left + 1U; right < 4U; ++right) {
            if (outside[left] == outside[right]) fail("outside-id-reuse");
        }
    }
    if (pipe2(ready, O_CLOEXEC) != 0 || pipe2(go, O_CLOEXEC) != 0) die("pipe2");
    child = fork();
    if (child < 0) die("fork-userns");
    if (child == 0) {
        close(ready[0]);
        close(go[1]);
        if (unshare(CLONE_NEWUSER) != 0) die("unshare-userns");
        marker = 'R';
        if (write(ready[1], &marker, 1U) != 1) die("write-ready");
        if (read(go[0], &marker, 1U) != 1 || marker != 'G') die("read-go");
        close(ready[1]);
        close(go[0]);
        if (syscall(SYS_close_range, 3U, UINT_MAX, 0U) != 0) {
            die("close-range-before-transition");
        }
        run_inside_namespace(mode, self_path);
    }
    close(ready[1]);
    close(go[0]);
    if (read(ready[0], &marker, 1U) != 1 || marker != 'R') die("parent-ready");
    install_maps(child, outside);
    marker = 'G';
    if (write(go[1], &marker, 1U) != 1) die("parent-go");
    close(ready[0]);
    close(go[1]);
    return wait_success(child, "userns") == 0 ? 0 : 121;
}

int main(int argc, char **argv) {
    static const char *const child_modes[] = {
        "--post-no-nnp-child", "--post-wrong-id-child", "--post-old-child",
        "--terminal-repeat-child"
    };
    unsigned outside[4];
    size_t index;
    if (argc == 2 && strcmp(argv[1], "--service-child") == 0) {
        return service_child_positive();
    }
    if (argc == 2) {
        for (index = 0U; index < sizeof(child_modes) / sizeof(child_modes[0]); ++index) {
            if (strcmp(argv[1], child_modes[index]) == 0) {
                return service_child_expected_rejection(argv[1]);
            }
        }
    }
    if (argc == 2 && strcmp(argv[1], "--invalid-proc-root") == 0) {
        pf_tq_kernel_snapshot_v2 snapshot;
        char error[PF_TQ_KERNEL_V2_ERROR_BYTES];
        int root_fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int result;
        if (root_fd < 0) die("open-invalid-proc-root");
        result = pf_tq_kernel_snapshot_read_v2(root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2, &snapshot, error, sizeof(error));
        close(root_fd);
        return result != 0 && error[0] != '\0' ? 0 : 122;
    }
    if (argc != 6) return 2;
    for (index = 0U; index < 4U; ++index) outside[index] = parse_id(argv[index + 2U]);
    return top_level(argv[1], argv[0], outside);
}
