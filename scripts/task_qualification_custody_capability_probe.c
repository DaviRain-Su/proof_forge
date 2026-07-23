#define _GNU_SOURCE
/*
 * Test-owned Linux kernel probe for TST-DOC-001/task-qualification-v1.
 *
 * This is not production custody code, does not read signing seeds, and cannot
 * produce a protected acceptance.  It proves that the corrected ADR-0021
 * capability checkpoints are reachable through an ordinary static execveat,
 * and that the superseded ptrace-only checkpoint is not reachable.
 */
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <linux/capability.h>
#include <sched.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
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
#define CAP_BIT(cap) (UINT64_C(1) << (cap))
#define TRANSITION_MASK (CAP_BIT(CAP_SETPCAP) | CAP_BIT(CAP_SYS_PTRACE))
#define PTRACE_MASK CAP_BIT(CAP_SYS_PTRACE)

struct snapshot {
    uint64_t inh;
    uint64_t prm;
    uint64_t eff;
    uint64_t bnd;
    uint64_t amb;
    unsigned uid[4];
    unsigned gid[4];
    int groups;
    int no_new_privs;
};

static void die(const char *what) {
    int saved = errno;
    fprintf(stderr, "PF-CAP-PROBE:%s:errno=%d\n", what, saved);
    fflush(stderr);
    _exit(111);
}

static void fail(const char *what) {
    errno = 0;
    die(what);
}

static int cap_last_cap(void) {
    FILE *stream = fopen("/proc/sys/kernel/cap_last_cap", "re");
    if (stream == NULL) die("open-cap-last-cap");
    int last = -1;
    if (fscanf(stream, "%d", &last) != 1 || last < 0 || last >= 64) {
        fclose(stream);
        fail("parse-cap-last-cap");
    }
    if (fclose(stream) != 0) die("close-cap-last-cap");
    return last;
}

static uint64_t kernel_bounding_mask(void) {
    uint64_t mask = 0;
    int last = cap_last_cap();
    for (int cap = 0; cap <= last; ++cap) {
        int value = prctl(PR_CAPBSET_READ, cap, 0, 0, 0);
        if (value < 0) die("PR_CAPBSET_READ");
        if (value == 1) mask |= CAP_BIT(cap);
    }
    return mask;
}

static uint64_t kernel_ambient_mask(void) {
    uint64_t mask = 0;
    int last = cap_last_cap();
    for (int cap = 0; cap <= last; ++cap) {
        int value = prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, cap, 0, 0);
        if (value < 0) die("PR_CAP_AMBIENT_IS_SET");
        if (value == 1) mask |= CAP_BIT(cap);
    }
    return mask;
}

static void kernel_capget(uint64_t *inh, uint64_t *prm, uint64_t *eff) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));
    if (syscall(SYS_capget, &header, data) != 0) die("capget");
    *eff = (uint64_t)data[0].effective | ((uint64_t)data[1].effective << 32);
    *prm = (uint64_t)data[0].permitted | ((uint64_t)data[1].permitted << 32);
    *inh = (uint64_t)data[0].inheritable | ((uint64_t)data[1].inheritable << 32);
}

static struct snapshot read_snapshot(void) {
    struct snapshot result;
    memset(&result, 0, sizeof(result));
    result.groups = getgroups(0, NULL);
    if (result.groups < 0) die("getgroups");

    FILE *stream = fopen("/proc/self/status", "re");
    if (stream == NULL) die("open-self-status");
    char *line = NULL;
    size_t capacity = 0;
    unsigned long long value = 0;
    bool seen_inh = false, seen_prm = false, seen_eff = false;
    bool seen_bnd = false, seen_amb = false, seen_uid = false;
    bool seen_gid = false, seen_nnp = false;
    while (getline(&line, &capacity, stream) >= 0) {
        if (sscanf(line, "CapInh:%llx", &value) == 1) {
            result.inh = (uint64_t)value;
            seen_inh = true;
        } else if (sscanf(line, "CapPrm:%llx", &value) == 1) {
            result.prm = (uint64_t)value;
            seen_prm = true;
        } else if (sscanf(line, "CapEff:%llx", &value) == 1) {
            result.eff = (uint64_t)value;
            seen_eff = true;
        } else if (sscanf(line, "CapBnd:%llx", &value) == 1) {
            result.bnd = (uint64_t)value;
            seen_bnd = true;
        } else if (sscanf(line, "CapAmb:%llx", &value) == 1) {
            result.amb = (uint64_t)value;
            seen_amb = true;
        } else if (sscanf(line, "Uid:%u%u%u%u", &result.uid[0], &result.uid[1],
                          &result.uid[2], &result.uid[3]) == 4) {
            seen_uid = true;
        } else if (sscanf(line, "Gid:%u%u%u%u", &result.gid[0], &result.gid[1],
                          &result.gid[2], &result.gid[3]) == 4) {
            seen_gid = true;
        } else if (sscanf(line, "NoNewPrivs:%d", &result.no_new_privs) == 1) {
            seen_nnp = true;
        }
    }
    free(line);
    if (fclose(stream) != 0) die("close-self-status");
    if (!seen_inh || !seen_prm || !seen_eff || !seen_bnd || !seen_amb ||
        !seen_uid || !seen_gid || !seen_nnp) {
        fail("incomplete-self-status");
    }

    uint64_t capget_inh = 0, capget_prm = 0, capget_eff = 0;
    kernel_capget(&capget_inh, &capget_prm, &capget_eff);
    if (result.inh != capget_inh || result.prm != capget_prm ||
        result.eff != capget_eff || result.bnd != kernel_bounding_mask() ||
        result.amb != kernel_ambient_mask()) {
        fail("capability-cross-check");
    }
    return result;
}

static void require_ids(const struct snapshot *state, uid_t uid, gid_t gid) {
    for (size_t index = 0; index < 4; ++index) {
        if (state->uid[index] != (unsigned)uid || state->gid[index] != (unsigned)gid) {
            fail("credential-slot-mismatch");
        }
    }
    if (state->groups != 0) fail("supplementary-groups-not-empty");
}

static void emit_checkpoint(const char *label, uint64_t bnd, uint64_t prm,
                            uint64_t eff, uint64_t inh, uint64_t amb,
                            uid_t uid, gid_t gid, int expected_nnp) {
    struct snapshot state = read_snapshot();
    require_ids(&state, uid, gid);
    if (state.bnd != bnd || state.prm != prm || state.eff != eff ||
        state.inh != inh || state.amb != amb ||
        state.no_new_privs != expected_nnp) {
        fail("checkpoint-mismatch");
    }
    printf("PF-CAP-CHECKPOINT label=%s bnd=%016llx prm=%016llx eff=%016llx "
           "inh=%016llx amb=%016llx uid=%u gid=%u groups=%d nnp=%d\n",
           label,
           (unsigned long long)state.bnd,
           (unsigned long long)state.prm,
           (unsigned long long)state.eff,
           (unsigned long long)state.inh,
           (unsigned long long)state.amb,
           state.uid[1], state.gid[1], state.groups, state.no_new_privs);
    fflush(stdout);
}

static void set_capability_masks(uint64_t prm, uint64_t eff, uint64_t inh) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));
    data[0].permitted = (uint32_t)prm;
    data[1].permitted = (uint32_t)(prm >> 32);
    data[0].effective = (uint32_t)eff;
    data[1].effective = (uint32_t)(eff >> 32);
    data[0].inheritable = (uint32_t)inh;
    data[1].inheritable = (uint32_t)(inh >> 32);
    if (syscall(SYS_capset, &header, data) != 0) die("capset");
}

static void drop_bounding_except(uint64_t keep) {
    int last = cap_last_cap();
    for (int cap = 0; cap <= last; ++cap) {
        if ((keep & CAP_BIT(cap)) != 0) continue;
        if (prctl(PR_CAPBSET_DROP, cap, 0, 0, 0) != 0) die("PR_CAPBSET_DROP");
    }
    if (kernel_bounding_mask() != keep) fail("bounding-mask-after-drop");
}

static void clear_ambient(void) {
    if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
        die("PR_CAP_AMBIENT_CLEAR_ALL");
    }
}

static void set_nnp(void) {
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) die("PR_SET_NO_NEW_PRIVS");
}

static void drop_credentials(uid_t uid, gid_t gid) {
    if (setgroups(0, NULL) != 0) die("setgroups-empty");
    if (setresgid(gid, gid, gid) != 0) die("setresgid");
    if (setresuid(uid, uid, uid) != 0) die("setresuid");
}

static void adapter_transition(void) {
    drop_bounding_except(0);
    drop_credentials(ADAPTER_UID, ADAPTER_GID);
    clear_ambient();
    set_capability_masks(0, 0, 0);
    set_nnp();
    emit_checkpoint("adapter-final", 0, 0, 0, 0, 0,
                    ADAPTER_UID, ADAPTER_GID, 1);
    _exit(0);
}

static void exec_self(int executable_fd, const char *mode) {
    char *const argv[] = {(char *)"pf-cap-transition-probe", (char *)mode, NULL};
    char *const envp[] = {NULL};
    syscall(SYS_execveat, executable_fd, "", argv, envp, AT_EMPTY_PATH);
    die("execveat");
}

static void service_transition(const char *self_path, bool old_checkpoint) {
    int executable_fd = open(self_path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (executable_fd < 0) die("open-self-executable");

    uint64_t keep = old_checkpoint ? PTRACE_MASK : TRANSITION_MASK;
    drop_bounding_except(keep);
    if (prctl(PR_SET_KEEPCAPS, 1, 0, 0, 0) != 0) die("PR_SET_KEEPCAPS");
    drop_credentials(SERVICE_UID, SERVICE_GID);

    if (old_checkpoint) {
        set_capability_masks(PTRACE_MASK, PTRACE_MASK, 0);
        set_nnp();
        emit_checkpoint("old-pre-exec", PTRACE_MASK, PTRACE_MASK,
                        PTRACE_MASK, 0, 0, SERVICE_UID, SERVICE_GID, 1);
        exec_self(executable_fd, "--old-service-child");
    }

    set_capability_masks(TRANSITION_MASK, TRANSITION_MASK, TRANSITION_MASK);
    if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, CAP_SETPCAP, 0, 0) != 0) {
        die("raise-ambient-setpcap");
    }
    if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, CAP_SYS_PTRACE, 0, 0) != 0) {
        die("raise-ambient-ptrace");
    }
    set_nnp();
    emit_checkpoint("service-pre-exec", TRANSITION_MASK, TRANSITION_MASK,
                    TRANSITION_MASK, TRANSITION_MASK, TRANSITION_MASK,
                    SERVICE_UID, SERVICE_GID, 1);
    exec_self(executable_fd, "--service-child");
}

static int service_child(void) {
    emit_checkpoint("service-post-exec", TRANSITION_MASK, TRANSITION_MASK,
                    TRANSITION_MASK, TRANSITION_MASK, TRANSITION_MASK,
                    SERVICE_UID, SERVICE_GID, 1);
    if (prctl(PR_CAPBSET_DROP, CAP_SYS_PTRACE, 0, 0, 0) != 0) {
        die("drop-bounding-ptrace");
    }
    if (prctl(PR_CAPBSET_DROP, CAP_SETPCAP, 0, 0, 0) != 0) {
        die("drop-bounding-setpcap");
    }
    clear_ambient();
    set_capability_masks(PTRACE_MASK, PTRACE_MASK, 0);
    emit_checkpoint("service-steady", 0, PTRACE_MASK, PTRACE_MASK, 0, 0,
                    SERVICE_UID, SERVICE_GID, 1);
    set_capability_masks(0, 0, 0);
    emit_checkpoint("service-terminal", 0, 0, 0, 0, 0,
                    SERVICE_UID, SERVICE_GID, 1);
    return 0;
}

static int old_service_child(void) {
    emit_checkpoint("old-post-exec", PTRACE_MASK, 0, 0, 0, 0,
                    SERVICE_UID, SERVICE_GID, 1);
    errno = 0;
    if (prctl(PR_CAPBSET_DROP, CAP_SYS_PTRACE, 0, 0, 0) == 0 || errno != EPERM) {
        fail("old-checkpoint-drop-did-not-fail-eperm");
    }
    printf("PF-CAP-OLD-DROP errno=%d\n", errno);
    fflush(stdout);
    return 0;
}

static int wait_success(pid_t child, const char *label) {
    int status = 0;
    if (waitpid(child, &status, 0) != child) die("waitpid");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "PF-CAP-PROBE:%s:child-status=%d\n", label, status);
        return 1;
    }
    return 0;
}

static void run_mapped_children(bool old_checkpoint, const char *self_path) {
    if (!old_checkpoint) {
        pid_t adapter = fork();
        if (adapter < 0) die("fork-adapter");
        if (adapter == 0) adapter_transition();
        if (wait_success(adapter, "adapter") != 0) _exit(112);
    }

    pid_t service = fork();
    if (service < 0) die("fork-service");
    if (service == 0) service_transition(self_path, old_checkpoint);
    if (wait_success(service, "service") != 0) _exit(113);
    _exit(0);
}

static int run_helper(const char *path, char *const argv[]) {
    pid_t child = fork();
    if (child < 0) die("fork-map-helper");
    if (child == 0) {
        execv(path, argv);
        die("exec-map-helper");
    }
    int status = 0;
    if (waitpid(child, &status, 0) != child) die("wait-map-helper");
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128;
}

static unsigned parse_id(const char *raw) {
    if (raw == NULL || *raw == '\0') fail("empty-outside-id");
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(raw, &end, 10);
    if (errno != 0 || end == raw || *end != '\0' || value > UINT32_MAX) {
        fail("invalid-outside-id");
    }
    return (unsigned)value;
}

static void install_maps(pid_t child, const unsigned outside[4]) {
    char pid_text[32], uid_a[32], uid_s[32], gid_a[32], gid_s[32];
    snprintf(pid_text, sizeof(pid_text), "%ld", (long)child);
    snprintf(uid_a, sizeof(uid_a), "%u", outside[0]);
    snprintf(uid_s, sizeof(uid_s), "%u", outside[1]);
    snprintf(gid_a, sizeof(gid_a), "%u", outside[2]);
    snprintf(gid_s, sizeof(gid_s), "%u", outside[3]);

    char *uid_argv[] = {
        (char *)"/usr/bin/newuidmap", pid_text,
        (char *)"1001", uid_a, (char *)"1",
        (char *)"1002", uid_s, (char *)"1", NULL,
    };
    if (run_helper(uid_argv[0], uid_argv) != 0) die("newuidmap");

    char *gid_argv[] = {
        (char *)"/usr/bin/newgidmap", pid_text,
        (char *)"1003", gid_a, (char *)"1",
        (char *)"1004", gid_s, (char *)"1", NULL,
    };
    if (run_helper(gid_argv[0], gid_argv) != 0) die("newgidmap");
}

static int top_level_probe(bool old_checkpoint, const char *self_path,
                           const unsigned outside[4]) {
    for (size_t left = 0; left < 4; ++left) {
        for (size_t right = left + 1; right < 4; ++right) {
            if (outside[left] == outside[right]) fail("outside-ids-not-distinct");
        }
    }

    int ready[2], go[2];
    if (pipe2(ready, O_CLOEXEC) != 0 || pipe2(go, O_CLOEXEC) != 0) die("pipe2");
    pid_t child = fork();
    if (child < 0) die("fork-userns-child");
    if (child == 0) {
        close(ready[0]);
        close(go[1]);
        if (unshare(CLONE_NEWUSER) != 0) die("unshare-userns");
        char marker = 'R';
        if (write(ready[1], &marker, 1) != 1) die("write-ready");
        if (read(go[0], &marker, 1) != 1 || marker != 'G') die("read-go");
        close(ready[1]);
        close(go[0]);
        run_mapped_children(old_checkpoint, self_path);
    }

    close(ready[1]);
    close(go[0]);
    char marker = 0;
    if (read(ready[0], &marker, 1) != 1 || marker != 'R') die("parent-ready");
    install_maps(child, outside);
    marker = 'G';
    if (write(go[1], &marker, 1) != 1) die("parent-go");
    close(ready[0]);
    close(go[1]);
    return wait_success(child, "userns");
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--service-child") == 0) {
        return service_child();
    }
    if (argc == 2 && strcmp(argv[1], "--old-service-child") == 0) {
        return old_service_child();
    }
    if (argc != 6 ||
        (strcmp(argv[1], "--positive") != 0 && strcmp(argv[1], "--old") != 0)) {
        fprintf(stderr, "usage: probe --positive|--old UID_A UID_S GID_A GID_S\n");
        return 2;
    }
    unsigned outside[4] = {
        parse_id(argv[2]), parse_id(argv[3]), parse_id(argv[4]), parse_id(argv[5]),
    };
    return top_level_probe(strcmp(argv[1], "--old") == 0, argv[0], outside);
}
