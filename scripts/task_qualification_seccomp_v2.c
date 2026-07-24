#define _GNU_SOURCE
#include "task_qualification_seccomp_v2.h"
#include "task_qualification_pf_jcs_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#if !defined(__x86_64__)
#error "ADR-0021 seccomp v2 currently pins AUDIT_ARCH_X86_64"
#endif

#define PF_TQ_SECCOMP_MAX_RULES 256U
#define PF_TQ_SECCOMP_MAX_ARGS 6U
#define PF_TQ_SECCOMP_MAX_INSNS 4096U
#define PF_TQ_SECCOMP_HEX_BYTES 16U

struct pf_tq_seccomp_syscall_name {
    const char *name;
    int number;
};

#define PF_TQ_SYSCALL(name) {#name, SYS_##name}
static const struct pf_tq_seccomp_syscall_name pf_tq_syscalls[] = {
    PF_TQ_SYSCALL(read), PF_TQ_SYSCALL(write), PF_TQ_SYSCALL(close),
    PF_TQ_SYSCALL(fstat), PF_TQ_SYSCALL(newfstatat), PF_TQ_SYSCALL(lseek),
    PF_TQ_SYSCALL(mmap), PF_TQ_SYSCALL(mprotect), PF_TQ_SYSCALL(munmap),
    PF_TQ_SYSCALL(brk), PF_TQ_SYSCALL(rt_sigaction),
    PF_TQ_SYSCALL(rt_sigprocmask), PF_TQ_SYSCALL(rt_sigreturn),
    PF_TQ_SYSCALL(pread64), PF_TQ_SYSCALL(pwrite64), PF_TQ_SYSCALL(readv),
    PF_TQ_SYSCALL(writev), PF_TQ_SYSCALL(sched_yield), PF_TQ_SYSCALL(madvise),
    PF_TQ_SYSCALL(getpid), PF_TQ_SYSCALL(getppid), PF_TQ_SYSCALL(socketpair),
    PF_TQ_SYSCALL(sendto), PF_TQ_SYSCALL(recvfrom), PF_TQ_SYSCALL(recvmsg),
    PF_TQ_SYSCALL(shutdown), PF_TQ_SYSCALL(setsockopt),
    PF_TQ_SYSCALL(getsockopt), PF_TQ_SYSCALL(exit), PF_TQ_SYSCALL(exit_group),
    PF_TQ_SYSCALL(wait4), PF_TQ_SYSCALL(kill), PF_TQ_SYSCALL(fcntl),
    PF_TQ_SYSCALL(flock), PF_TQ_SYSCALL(fsync), PF_TQ_SYSCALL(fdatasync),
    PF_TQ_SYSCALL(ftruncate), PF_TQ_SYSCALL(getdents64),
    PF_TQ_SYSCALL(readlinkat), PF_TQ_SYSCALL(unlinkat),
    PF_TQ_SYSCALL(renameat), PF_TQ_SYSCALL(renameat2),
    PF_TQ_SYSCALL(gettimeofday), PF_TQ_SYSCALL(getrusage),
    PF_TQ_SYSCALL(prctl), PF_TQ_SYSCALL(arch_prctl), PF_TQ_SYSCALL(gettid),
    PF_TQ_SYSCALL(getuid), PF_TQ_SYSCALL(getgid), PF_TQ_SYSCALL(geteuid),
    PF_TQ_SYSCALL(getegid), PF_TQ_SYSCALL(getgroups), PF_TQ_SYSCALL(getresuid),
    PF_TQ_SYSCALL(getresgid), PF_TQ_SYSCALL(capget), PF_TQ_SYSCALL(capset),
    PF_TQ_SYSCALL(sigaltstack), PF_TQ_SYSCALL(statfs), PF_TQ_SYSCALL(fstatfs),
    PF_TQ_SYSCALL(clock_gettime), PF_TQ_SYSCALL(clock_nanosleep),
    PF_TQ_SYSCALL(openat), PF_TQ_SYSCALL(ppoll), PF_TQ_SYSCALL(epoll_wait),
    PF_TQ_SYSCALL(epoll_ctl), PF_TQ_SYSCALL(epoll_create1),
    PF_TQ_SYSCALL(accept4), PF_TQ_SYSCALL(getrandom),
    PF_TQ_SYSCALL(memfd_create), PF_TQ_SYSCALL(execveat),
    PF_TQ_SYSCALL(seccomp), PF_TQ_SYSCALL(statx), PF_TQ_SYSCALL(pidfd_open),
    PF_TQ_SYSCALL(close_range),
    PF_TQ_SYSCALL(fork), PF_TQ_SYSCALL(vfork), PF_TQ_SYSCALL(clone),
    PF_TQ_SYSCALL(clone3), PF_TQ_SYSCALL(dup), PF_TQ_SYSCALL(dup2),
    PF_TQ_SYSCALL(dup3), PF_TQ_SYSCALL(pidfd_getfd), PF_TQ_SYSCALL(sendmsg),
    PF_TQ_SYSCALL(sendmmsg), PF_TQ_SYSCALL(execve), PF_TQ_SYSCALL(ptrace),
    PF_TQ_SYSCALL(process_vm_readv), PF_TQ_SYSCALL(process_vm_writev),
    PF_TQ_SYSCALL(mount), PF_TQ_SYSCALL(umount2), PF_TQ_SYSCALL(pivot_root),
    PF_TQ_SYSCALL(chroot), PF_TQ_SYSCALL(setns), PF_TQ_SYSCALL(unshare),
    PF_TQ_SYSCALL(open), PF_TQ_SYSCALL(openat2), PF_TQ_SYSCALL(creat),
    PF_TQ_SYSCALL(setuid), PF_TQ_SYSCALL(setgid), PF_TQ_SYSCALL(setreuid),
    PF_TQ_SYSCALL(setregid), PF_TQ_SYSCALL(setresuid),
    PF_TQ_SYSCALL(setresgid), PF_TQ_SYSCALL(setfsuid),
    PF_TQ_SYSCALL(setfsgid), PF_TQ_SYSCALL(setgroups),
};
#undef PF_TQ_SYSCALL

struct pf_tq_seccomp_arg {
    unsigned index;
    int masked;
    uint64_t value;
    uint64_t mask;
};

struct pf_tq_seccomp_rule {
    int syscall_number;
    char syscall_name[64];
    size_t argument_count;
    struct pf_tq_seccomp_arg arguments[PF_TQ_SECCOMP_MAX_ARGS];
    size_t arguments_raw_start;
    size_t arguments_raw_end;
};

struct pf_tq_seccomp_policy {
    pf_tq_seccomp_stage_v2 stage;
    size_t rule_count;
    struct pf_tq_seccomp_rule rules[PF_TQ_SECCOMP_MAX_RULES];
};

struct pf_tq_seccomp_program {
    struct sock_filter instructions[PF_TQ_SECCOMP_MAX_INSNS];
    size_t count;
};

static int pf_tq_seccomp_error(
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

static void pf_tq_seccomp_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static int pf_tq_seccomp_copy_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_jcs_object_get_v2(document, object, field);
    return pf_tq_jcs_copy_string_v2(document, node, output,
        output_size, error, error_size);
}

static int pf_tq_seccomp_syscall_table_validate(
    char *error,
    size_t error_size
) {
    size_t left;
    size_t count = sizeof(pf_tq_syscalls) / sizeof(pf_tq_syscalls[0]);
    for (left = 0U; left < count; ++left) {
        size_t right;
        if (pf_tq_syscalls[left].name == NULL ||
                pf_tq_syscalls[left].name[0] == '\0' ||
                pf_tq_syscalls[left].number < 0) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp syscall table contains an invalid entry");
        }
        for (right = left + 1U; right < count; ++right) {
            if (strcmp(pf_tq_syscalls[left].name,
                    pf_tq_syscalls[right].name) == 0 ||
                    pf_tq_syscalls[left].number == pf_tq_syscalls[right].number) {
                return pf_tq_seccomp_error(error, error_size,
                    "seccomp syscall table name/number is not unique");
            }
        }
    }
    return 0;
}

static int pf_tq_seccomp_resolve(const char *name, int *number) {
    size_t index;
    for (index = 0U; index < sizeof(pf_tq_syscalls) / sizeof(pf_tq_syscalls[0]);
            ++index) {
        if (strcmp(name, pf_tq_syscalls[index].name) == 0) {
            *number = pf_tq_syscalls[index].number;
            return 0;
        }
    }
    return -1;
}

static int pf_tq_seccomp_hex_value(unsigned char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

static int pf_tq_seccomp_hex64(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    uint64_t *output,
    char *error,
    size_t error_size
) {
    uint64_t result = 0U;
    size_t index;
    if (node == NULL || node->type != PF_TQ_JCS_STRING ||
            node->string_size != PF_TQ_SECCOMP_HEX_BYTES) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp scalar is not 16 lowercase hex digits");
    }
    for (index = 0U; index < PF_TQ_SECCOMP_HEX_BYTES; ++index) {
        int digit = pf_tq_seccomp_hex_value(
            document->bytes[node->string_start + index]);
        if (digit < 0) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp scalar is not lowercase hex");
        }
        result = (result << 4U) | (unsigned)digit;
    }
    *output = result;
    return 0;
}

static int pf_tq_seccomp_parse_argument(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    struct pf_tq_seccomp_arg *argument,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"index", "mask", "operation", "value"};
    const pf_tq_jcs_node_v2 *index_node;
    char operation[32];
    if (node == NULL || node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp argument rule is not an object");
    }
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 4U,
            error, error_size) != 0) return -1;
    index_node = pf_tq_jcs_object_get_v2(document, node, "index");
    if (index_node == NULL || index_node->type != PF_TQ_JCS_UINT ||
            index_node->uint_value > 5U) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp argument index is outside 0..5");
    }
    if (pf_tq_seccomp_copy_string(document, node, "operation", operation,
            sizeof(operation), error, error_size) != 0 ||
            pf_tq_seccomp_hex64(document,
                pf_tq_jcs_object_get_v2(document, node, "value"),
                &argument->value, error, error_size) != 0 ||
            pf_tq_seccomp_hex64(document,
                pf_tq_jcs_object_get_v2(document, node, "mask"),
                &argument->mask, error, error_size) != 0) return -1;
    argument->index = (unsigned)index_node->uint_value;
    if (strcmp(operation, "eq") == 0) {
        if (argument->mask != UINT64_MAX) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp eq argument mask must be ffffffffffffffff");
        }
        argument->masked = 0;
    } else if (strcmp(operation, "masked-eq") == 0) {
        if (argument->mask == 0U ||
                (argument->value & ~argument->mask) != 0U) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp masked-eq mask/value rejected");
        }
        argument->masked = 1;
    } else {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp argument operation must be eq|masked-eq");
    }
    return 0;
}

static int pf_tq_seccomp_parse_rule(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    struct pf_tq_seccomp_rule *rule,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"action", "arguments", "syscall"};
    const pf_tq_jcs_node_v2 *arguments;
    char action[16];
    size_t index;
    memset(rule, 0, sizeof(*rule));
    if (node == NULL || node->type != PF_TQ_JCS_OBJECT ||
            pf_tq_jcs_object_exact_v2(document, node, fields, 3U,
                error, error_size) != 0 ||
            pf_tq_seccomp_copy_string(document, node, "action", action,
                sizeof(action), error, error_size) != 0 ||
            strcmp(action, "allow") != 0 ||
            pf_tq_seccomp_copy_string(document, node, "syscall",
                rule->syscall_name, sizeof(rule->syscall_name),
                error, error_size) != 0 ||
            pf_tq_seccomp_resolve(rule->syscall_name,
                &rule->syscall_number) != 0) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp syscall rule/action/name rejected");
    }
    arguments = pf_tq_jcs_object_get_v2(document, node, "arguments");
    if (arguments == NULL || arguments->type != PF_TQ_JCS_ARRAY ||
            arguments->child_count > PF_TQ_SECCOMP_MAX_ARGS) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp syscall argument array exceeds six");
    }
    rule->argument_count = arguments->child_count;
    rule->arguments_raw_start = arguments->raw_start;
    rule->arguments_raw_end = arguments->raw_end;
    for (index = 0U; index < rule->argument_count; ++index) {
        if (pf_tq_seccomp_parse_argument(document,
                pf_tq_jcs_array_at_v2(document, arguments, index),
                &rule->arguments[index], error, error_size) != 0) return -1;
        if (index > 0U && rule->arguments[index - 1U].index >=
                rule->arguments[index].index) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp arguments must be strictly index-sorted");
        }
    }
    return 0;
}

static int pf_tq_seccomp_raw_compare(
    const unsigned char *left,
    size_t left_size,
    const unsigned char *right,
    size_t right_size
) {
    size_t shared = left_size < right_size ? left_size : right_size;
    int result = memcmp(left, right, shared);
    if (result != 0) return result;
    if (left_size < right_size) return -1;
    if (left_size > right_size) return 1;
    return 0;
}

static int pf_tq_seccomp_stage_parse(
    const char *stage,
    pf_tq_seccomp_stage_v2 *result
) {
    if (strcmp(stage, "adapter") == 0) {
        *result = PF_TQ_SECCOMP_ADAPTER_V2;
    } else if (strcmp(stage, "custody-pre-exec") == 0) {
        *result = PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2;
    } else if (strcmp(stage, "service-final") == 0) {
        *result = PF_TQ_SECCOMP_SERVICE_FINAL_V2;
    } else {
        return -1;
    }
    return 0;
}

static int pf_tq_seccomp_parse(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_seccomp_context_v2 *context,
    struct pf_tq_seccomp_policy *policy,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "auditArch", "defaultAction", "noNewPrivs", "rules", "stage"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *rules;
    const pf_tq_jcs_node_v2 *nnp;
    char audit_arch[32];
    char default_action[32];
    char stage[32];
    size_t index;
    int result = -1;
    memset(policy, 0, sizeof(*policy));
    if (bytes == NULL || size == 0U || size > PF_TQ_SECCOMP_V2_MAX_POLICY_BYTES ||
            context == NULL || context->stage < PF_TQ_SECCOMP_ADAPTER_V2 ||
            context->stage > PF_TQ_SECCOMP_SERVICE_FINAL_V2) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp policy bytes/context rejected");
    }
    if (pf_tq_jcs_parse_v2(bytes, size, &document,
            error, error_size) != 0) return -1;
    root = pf_tq_jcs_root_v2(&document);
    if (root == NULL || root->type != PF_TQ_JCS_OBJECT ||
            pf_tq_jcs_object_exact_v2(&document, root, fields, 5U,
                error, error_size) != 0 ||
            pf_tq_seccomp_copy_string(&document, root, "auditArch", audit_arch,
                sizeof(audit_arch), error, error_size) != 0 ||
            strcmp(audit_arch, "AUDIT_ARCH_X86_64") != 0 ||
            pf_tq_seccomp_copy_string(&document, root, "defaultAction",
                default_action, sizeof(default_action), error, error_size) != 0 ||
            strcmp(default_action, "kill-process") != 0 ||
            pf_tq_seccomp_copy_string(&document, root, "stage", stage,
                sizeof(stage), error, error_size) != 0 ||
            pf_tq_seccomp_stage_parse(stage, &policy->stage) != 0 ||
            policy->stage != context->stage) {
        (void)pf_tq_seccomp_error(error, error_size,
            "seccomp policy header/stage rejected");
        goto cleanup;
    }
    nnp = pf_tq_jcs_object_get_v2(&document, root, "noNewPrivs");
    rules = pf_tq_jcs_object_get_v2(&document, root, "rules");
    if (nnp == NULL || nnp->type != PF_TQ_JCS_BOOL || !nnp->bool_value ||
            rules == NULL || rules->type != PF_TQ_JCS_ARRAY ||
            rules->child_count == 0U || rules->child_count > PF_TQ_SECCOMP_MAX_RULES) {
        (void)pf_tq_seccomp_error(error, error_size,
            "seccomp noNewPrivs/rule count rejected");
        goto cleanup;
    }
    policy->rule_count = rules->child_count;
    for (index = 0U; index < policy->rule_count; ++index) {
        struct pf_tq_seccomp_rule *current = &policy->rules[index];
        if (pf_tq_seccomp_parse_rule(&document,
                pf_tq_jcs_array_at_v2(&document, rules, index), current,
                error, error_size) != 0) goto cleanup;
        if (index > 0U) {
            const struct pf_tq_seccomp_rule *previous = &policy->rules[index - 1U];
            int comparison = previous->syscall_number < current->syscall_number ? -1 :
                previous->syscall_number > current->syscall_number ? 1 :
                pf_tq_seccomp_raw_compare(
                    document.bytes + previous->arguments_raw_start,
                    previous->arguments_raw_end - previous->arguments_raw_start,
                    document.bytes + current->arguments_raw_start,
                    current->arguments_raw_end - current->arguments_raw_start);
            if (comparison >= 0) {
                (void)pf_tq_seccomp_error(error, error_size,
                    "seccomp rules must be syscall-number/arguments sorted unique");
                goto cleanup;
            }
        }
    }
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&document);
    return result;
}

static const struct pf_tq_seccomp_arg *pf_tq_seccomp_arg_find(
    const struct pf_tq_seccomp_rule *rule,
    unsigned index
) {
    size_t cursor;
    for (cursor = 0U; cursor < rule->argument_count; ++cursor) {
        if (rule->arguments[cursor].index == index) return &rule->arguments[cursor];
    }
    return NULL;
}

static bool pf_tq_seccomp_arg_eq(
    const struct pf_tq_seccomp_arg *argument,
    uint64_t value
) {
    return argument != NULL && !argument->masked && argument->value == value;
}

static bool pf_tq_seccomp_forbidden(const char *name) {
    static const char *const names[] = {
        "fork", "vfork", "clone", "clone3", "dup", "dup2", "dup3",
        "pidfd_getfd", "sendmsg", "sendmmsg", "execve", "ptrace",
        "process_vm_writev", "mount", "umount2", "pivot_root", "chroot",
        "setns", "unshare", "open", "openat2", "creat", "setuid", "setgid",
        "setreuid", "setregid", "setresuid", "setresgid", "setfsuid",
        "setfsgid", "setgroups"
    };
    size_t index;
    for (index = 0U; index < sizeof(names) / sizeof(names[0]); ++index) {
        if (strcmp(name, names[index]) == 0) return true;
    }
    return false;
}

static bool pf_tq_seccomp_open_flags(uint64_t flags, int durable) {
    static const uint64_t proc_flags[] = {
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW,
        O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW,
    };
    static const uint64_t durable_flags[] = {
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW,
        O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
    };
    const uint64_t *accepted = durable ? durable_flags : proc_flags;
    size_t count = durable ? sizeof(durable_flags) / sizeof(durable_flags[0]) :
        sizeof(proc_flags) / sizeof(proc_flags[0]);
    size_t index;
    for (index = 0U; index < count; ++index) {
        if (flags == accepted[index]) return true;
    }
    return false;
}

static int pf_tq_seccomp_rule_hard_constraints(
    const struct pf_tq_seccomp_rule *rule,
    const pf_tq_seccomp_context_v2 *context,
    unsigned *drop_ptrace,
    unsigned *drop_setpcap,
    unsigned *ambient_clear,
    unsigned *capset,
    unsigned *seccomp_overlay,
    unsigned *execveat,
    char *error,
    size_t error_size
) {
    const struct pf_tq_seccomp_arg *arg0 = pf_tq_seccomp_arg_find(rule, 0U);
    const struct pf_tq_seccomp_arg *arg1 = pf_tq_seccomp_arg_find(rule, 1U);
    const struct pf_tq_seccomp_arg *arg2 = pf_tq_seccomp_arg_find(rule, 2U);
    const struct pf_tq_seccomp_arg *arg3 = pf_tq_seccomp_arg_find(rule, 3U);
    const struct pf_tq_seccomp_arg *arg4 = pf_tq_seccomp_arg_find(rule, 4U);
    if (pf_tq_seccomp_forbidden(rule->syscall_name)) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp policy contains a globally forbidden syscall: %s",
            rule->syscall_name);
    }
    if (strcmp(rule->syscall_name, "execveat") == 0) {
        if (context->stage != PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 ||
                rule->argument_count != 2U ||
                !pf_tq_seccomp_arg_eq(arg0,
                    (uint64_t)context->service_executable_fd) ||
                !pf_tq_seccomp_arg_eq(arg4, AT_EMPTY_PATH)) {
            return pf_tq_seccomp_error(error, error_size,
                "execveat is not exact custody fixed-FD/AT_EMPTY_PATH");
        }
        ++*execveat;
    }
    if (strcmp(rule->syscall_name, "openat") == 0) {
        int durable;
        uint64_t flags;
        if (arg0 == NULL || arg2 == NULL || arg0->masked || arg2->masked ||
                arg0->value == (uint64_t)(int64_t)AT_FDCWD ||
                (arg0->value != (uint64_t)context->proc_root_fd &&
                 arg0->value != (uint64_t)context->durable_root_fd) ||
                pf_tq_seccomp_arg_find(rule, 1U) != NULL) {
            return pf_tq_seccomp_error(error, error_size,
                "openat lacks exact fixed dirfd/flags constraints");
        }
        durable = arg0->value == (uint64_t)context->durable_root_fd;
        flags = arg2->value;
        if (!pf_tq_seccomp_open_flags(flags, durable) ||
                ((flags & O_CREAT) != 0U &&
                 !pf_tq_seccomp_arg_eq(arg3, 0600U))) {
            return pf_tq_seccomp_error(error, error_size,
                "openat flags/mode are outside the ADR fixed set");
        }
    }
    if (strcmp(rule->syscall_name, "fcntl") == 0) {
        static const uint64_t allowed[] = {
            F_GETFD, F_SETFD, F_GETFL, F_GET_SEALS, F_ADD_SEALS
        };
        size_t index;
        bool accepted = false;
        if (arg1 == NULL || arg1->masked) {
            return pf_tq_seccomp_error(error, error_size,
                "fcntl rule must constrain command exactly");
        }
        for (index = 0U; index < sizeof(allowed) / sizeof(allowed[0]); ++index) {
            if (arg1->value == allowed[index]) accepted = true;
        }
        if (!accepted || arg1->value == F_DUPFD || arg1->value == F_DUPFD_CLOEXEC) {
            return pf_tq_seccomp_error(error, error_size,
                "fcntl command is not in the non-dup fixed set");
        }
    }
    if (strcmp(rule->syscall_name, "capset") == 0) {
        if (rule->argument_count != 0U ||
                context->stage == PF_TQ_SECCOMP_ADAPTER_V2) {
            return pf_tq_seccomp_error(error, error_size,
                "capset rule stage/arguments rejected");
        }
        ++*capset;
    }
    if (strcmp(rule->syscall_name, "seccomp") == 0) {
        if (context->stage != PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 ||
                rule->argument_count != 2U ||
                !pf_tq_seccomp_arg_eq(arg0, SECCOMP_SET_MODE_FILTER) ||
                !pf_tq_seccomp_arg_eq(arg1, 0U)) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp overlay rule is not exact custody flags-zero");
        }
        ++*seccomp_overlay;
    }
    if (strcmp(rule->syscall_name, "prctl") == 0) {
        if (arg0 == NULL || arg0->masked) {
            return pf_tq_seccomp_error(error, error_size,
                "prctl rule must constrain option exactly");
        }
        if (context->stage == PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 &&
                pf_tq_seccomp_arg_eq(arg0, PR_CAPBSET_DROP) &&
                rule->argument_count == 5U &&
                pf_tq_seccomp_arg_eq(arg2, 0U) &&
                pf_tq_seccomp_arg_eq(arg3, 0U) &&
                pf_tq_seccomp_arg_eq(arg4, 0U) && arg1 != NULL && !arg1->masked) {
            if (arg1->value == 19U) ++*drop_ptrace;
            else if (arg1->value == 8U) ++*drop_setpcap;
            else return pf_tq_seccomp_error(error, error_size,
                "custody PR_CAPBSET_DROP capability rejected");
        } else if (context->stage == PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 &&
                pf_tq_seccomp_arg_eq(arg0, PR_CAP_AMBIENT) &&
                rule->argument_count == 5U &&
                pf_tq_seccomp_arg_eq(arg1, PR_CAP_AMBIENT_CLEAR_ALL) &&
                pf_tq_seccomp_arg_eq(arg2, 0U) &&
                pf_tq_seccomp_arg_eq(arg3, 0U) &&
                pf_tq_seccomp_arg_eq(arg4, 0U)) {
            ++*ambient_clear;
        } else if (context->stage == PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 &&
                pf_tq_seccomp_arg_eq(arg0, PR_CAPBSET_READ) &&
                rule->argument_count == 5U && arg1 != NULL && !arg1->masked &&
                arg1->value < 64U && pf_tq_seccomp_arg_eq(arg2, 0U) &&
                pf_tq_seccomp_arg_eq(arg3, 0U) &&
                pf_tq_seccomp_arg_eq(arg4, 0U)) {
            /* Exact read-only bounding-set cross-check for one capability. */
        } else if (context->stage == PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 &&
                pf_tq_seccomp_arg_eq(arg0, PR_CAP_AMBIENT) &&
                rule->argument_count == 5U &&
                pf_tq_seccomp_arg_eq(arg1, PR_CAP_AMBIENT_IS_SET) &&
                arg2 != NULL && !arg2->masked && arg2->value < 64U &&
                pf_tq_seccomp_arg_eq(arg3, 0U) &&
                pf_tq_seccomp_arg_eq(arg4, 0U)) {
            /* Exact read-only ambient-set cross-check for one capability. */
        } else if (pf_tq_seccomp_arg_eq(arg0, PR_GET_NO_NEW_PRIVS) &&
                rule->argument_count == 5U &&
                pf_tq_seccomp_arg_eq(arg1, 0U) &&
                pf_tq_seccomp_arg_eq(arg2, 0U) &&
                pf_tq_seccomp_arg_eq(arg3, 0U) &&
                pf_tq_seccomp_arg_eq(arg4, 0U)) {
            /* Read-only NNP cross-check is safe in every filtered stage. */
        } else {
            return pf_tq_seccomp_error(error, error_size,
                "prctl rule is outside the stage-exact scalar set");
        }
    }
    return 0;
}

static int pf_tq_seccomp_hard_constraints(
    const struct pf_tq_seccomp_policy *policy,
    const pf_tq_seccomp_context_v2 *context,
    char *error,
    size_t error_size
) {
    unsigned drop_ptrace = 0U, drop_setpcap = 0U, ambient_clear = 0U;
    unsigned capset = 0U, seccomp_overlay = 0U, execveat = 0U;
    size_t index;
    if (context->proc_root_fd <= 2 || context->durable_root_fd <= 2 ||
            context->proc_root_fd == context->durable_root_fd ||
            (context->stage == PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 &&
             (context->service_executable_fd <= 2 ||
              context->service_executable_fd == context->proc_root_fd ||
              context->service_executable_fd == context->durable_root_fd))) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp fixed FD context rejected");
    }
    for (index = 0U; index < policy->rule_count; ++index) {
        if (pf_tq_seccomp_rule_hard_constraints(&policy->rules[index], context,
                &drop_ptrace, &drop_setpcap, &ambient_clear, &capset,
                &seccomp_overlay, &execveat, error, error_size) != 0) return -1;
    }
    if (context->stage == PF_TQ_SECCOMP_ADAPTER_V2) {
        if (drop_ptrace || drop_setpcap || ambient_clear || capset ||
                seccomp_overlay || execveat) {
            return pf_tq_seccomp_error(error, error_size,
                "adapter seccomp contains custody/service transition rules");
        }
    } else if (context->stage == PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2) {
        if (drop_ptrace != 1U || drop_setpcap != 1U || ambient_clear != 1U ||
                capset != 1U || seccomp_overlay != 1U || execveat != 1U) {
            return pf_tq_seccomp_error(error, error_size,
                "custody seccomp transition-rule cardinality mismatch");
        }
    } else if (capset != 1U || drop_ptrace || drop_setpcap || ambient_clear ||
            seccomp_overlay || execveat) {
        return pf_tq_seccomp_error(error, error_size,
            "service-final seccomp transition-rule cardinality mismatch");
    }
    return 0;
}

static int pf_tq_seccomp_emit(
    struct pf_tq_seccomp_program *program,
    struct sock_filter instruction,
    char *error,
    size_t error_size
) {
    if (program->count >= PF_TQ_SECCOMP_MAX_INSNS) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp BPF instruction bound exceeded");
    }
    program->instructions[program->count++] = instruction;
    return 0;
}

static int pf_tq_seccomp_compile(
    const struct pf_tq_seccomp_policy *policy,
    struct pf_tq_seccomp_program *program,
    char *error,
    size_t error_size
) {
    size_t rule_index;
    memset(program, 0, sizeof(*program));
    if (pf_tq_seccomp_emit(program,
            (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS,
                offsetof(struct seccomp_data, arch)), error, error_size) != 0 ||
            pf_tq_seccomp_emit(program,
                (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K,
                    AUDIT_ARCH_X86_64, 1, 0), error, error_size) != 0 ||
            pf_tq_seccomp_emit(program,
                (struct sock_filter)BPF_STMT(BPF_RET | BPF_K,
                    SECCOMP_RET_KILL_PROCESS), error, error_size) != 0) return -1;
    for (rule_index = 0U; rule_index < policy->rule_count; ++rule_index) {
        const struct pf_tq_seccomp_rule *rule = &policy->rules[rule_index];
        size_t syscall_jump;
        size_t comparisons[PF_TQ_SECCOMP_MAX_ARGS * 2U];
        size_t comparison_count = 0U;
        size_t arg_index;
        size_t block_end;
        if (pf_tq_seccomp_emit(program,
                (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS,
                    offsetof(struct seccomp_data, nr)), error, error_size) != 0) return -1;
        syscall_jump = program->count;
        if (pf_tq_seccomp_emit(program,
                (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K,
                    (uint32_t)rule->syscall_number, 0, 0),
                error, error_size) != 0) return -1;
        for (arg_index = 0U; arg_index < rule->argument_count; ++arg_index) {
            const struct pf_tq_seccomp_arg *argument = &rule->arguments[arg_index];
            uint32_t masks[2] = {(uint32_t)argument->mask,
                (uint32_t)(argument->mask >> 32U)};
            uint32_t values[2] = {(uint32_t)argument->value,
                (uint32_t)(argument->value >> 32U)};
            unsigned word;
            for (word = 0U; word < 2U; ++word) {
                uint32_t offset = (uint32_t)offsetof(struct seccomp_data,
                    args[argument->index]) + 4U * word;
                if (pf_tq_seccomp_emit(program,
                        (struct sock_filter)BPF_STMT(BPF_LD | BPF_W | BPF_ABS,
                            offset), error, error_size) != 0) return -1;
                if (argument->masked && pf_tq_seccomp_emit(program,
                        (struct sock_filter)BPF_STMT(BPF_ALU | BPF_AND | BPF_K,
                            masks[word]), error, error_size) != 0) return -1;
                comparisons[comparison_count++] = program->count;
                if (pf_tq_seccomp_emit(program,
                        (struct sock_filter)BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K,
                            values[word], 0, 0), error, error_size) != 0) return -1;
            }
        }
        if (pf_tq_seccomp_emit(program,
                (struct sock_filter)BPF_STMT(BPF_RET | BPF_K,
                    SECCOMP_RET_ALLOW), error, error_size) != 0) return -1;
        block_end = program->count;
        if (block_end - (syscall_jump + 1U) > UINT8_MAX) {
            return pf_tq_seccomp_error(error, error_size,
                "seccomp syscall BPF branch exceeds uint8");
        }
        program->instructions[syscall_jump].jf =
            (uint8_t)(block_end - (syscall_jump + 1U));
        for (arg_index = 0U; arg_index < comparison_count; ++arg_index) {
            size_t comparison = comparisons[arg_index];
            if (block_end - (comparison + 1U) > UINT8_MAX) {
                return pf_tq_seccomp_error(error, error_size,
                    "seccomp argument BPF branch exceeds uint8");
            }
            program->instructions[comparison].jf =
                (uint8_t)(block_end - (comparison + 1U));
        }
    }
    return pf_tq_seccomp_emit(program,
        (struct sock_filter)BPF_STMT(BPF_RET | BPF_K,
            SECCOMP_RET_KILL_PROCESS), error, error_size);
}

static int pf_tq_seccomp_prepare(
    const unsigned char *policy_bytes,
    size_t policy_size,
    const pf_tq_seccomp_context_v2 *context,
    struct pf_tq_seccomp_program *program,
    char *error,
    size_t error_size
) {
    struct pf_tq_seccomp_policy policy;
    if (pf_tq_seccomp_syscall_table_validate(error, error_size) != 0 ||
            pf_tq_seccomp_parse(policy_bytes, policy_size, context,
                &policy, error, error_size) != 0 ||
            pf_tq_seccomp_hard_constraints(&policy, context,
                error, error_size) != 0 ||
            pf_tq_seccomp_compile(&policy, program,
                error, error_size) != 0) return -1;
    return 0;
}

int pf_tq_seccomp_validate_v2(
    const unsigned char *policy_bytes,
    size_t policy_size,
    const pf_tq_seccomp_context_v2 *context,
    char *error,
    size_t error_size
) {
    struct pf_tq_seccomp_program program;
    pf_tq_seccomp_clear_error(error, error_size);
    return pf_tq_seccomp_prepare(policy_bytes, policy_size,
        context, &program, error, error_size);
}

int pf_tq_seccomp_install_v2(
    const unsigned char *policy_bytes,
    size_t policy_size,
    const pf_tq_seccomp_context_v2 *context,
    char *error,
    size_t error_size
) {
    struct pf_tq_seccomp_program program;
    struct sock_fprog descriptor;
    int no_new_privs;
    pf_tq_seccomp_clear_error(error, error_size);
    if (pf_tq_seccomp_prepare(policy_bytes, policy_size,
            context, &program, error, error_size) != 0) return -1;
    no_new_privs = prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0);
    if (no_new_privs != 1) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp install requires exact no_new_privs=1");
    }
    descriptor.len = (unsigned short)program.count;
    descriptor.filter = program.instructions;
    if (syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0U, &descriptor) != 0) {
        return pf_tq_seccomp_error(error, error_size,
            "seccomp filter install failed: %s", strerror(errno));
    }
    return 0;
}
