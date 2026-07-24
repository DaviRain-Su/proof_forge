#define _GNU_SOURCE
/* Test-owned driver for the production ADR-0021 seccomp policy loader. */
#include "task_qualification_seccomp_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
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

#define PF_TQ_TEST_PROC_ROOT_FD 90
#define PF_TQ_TEST_DURABLE_ROOT_FD 91
#define PF_TQ_TEST_SERVICE_EXECUTABLE_FD 92
#define PF_TQ_TEST_RUNTIME_FD 3

static void pf_tq_test_fail(const char *message) {
    (void)fprintf(stderr, "PF-SECCOMP-DRIVER:%s:errno=%d\n", message, errno);
    exit(111);
}

static unsigned char *pf_tq_test_read_policy(
    const char *path,
    size_t *size
) {
    struct stat metadata;
    unsigned char *bytes;
    size_t offset = 0U;
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0 || fstat(fd, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
            metadata.st_size <= 0 ||
            (uint64_t)metadata.st_size > PF_TQ_SECCOMP_V2_MAX_POLICY_BYTES) {
        if (fd >= 0) (void)close(fd);
        pf_tq_test_fail("policy-open-or-stat");
    }
    *size = (size_t)metadata.st_size;
    bytes = malloc(*size);
    if (bytes == NULL) {
        (void)close(fd);
        pf_tq_test_fail("policy-allocate");
    }
    while (offset < *size) {
        ssize_t amount = read(fd, bytes + offset, *size - offset);
        if (amount <= 0) {
            free(bytes);
            (void)close(fd);
            pf_tq_test_fail("policy-read");
        }
        offset += (size_t)amount;
    }
    if (close(fd) != 0) {
        free(bytes);
        pf_tq_test_fail("policy-close");
    }
    return bytes;
}

static int pf_tq_test_stage(
    const char *text,
    pf_tq_seccomp_stage_v2 *stage
) {
    if (strcmp(text, "adapter") == 0) {
        *stage = PF_TQ_SECCOMP_ADAPTER_V2;
    } else if (strcmp(text, "custody-pre-exec") == 0) {
        *stage = PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2;
    } else if (strcmp(text, "service-final") == 0) {
        *stage = PF_TQ_SECCOMP_SERVICE_FINAL_V2;
    } else {
        return -1;
    }
    return 0;
}

static pf_tq_seccomp_context_v2 pf_tq_test_context(
    pf_tq_seccomp_stage_v2 stage
) {
    pf_tq_seccomp_context_v2 context;
    context.stage = stage;
    context.proc_root_fd = PF_TQ_TEST_PROC_ROOT_FD;
    context.durable_root_fd = PF_TQ_TEST_DURABLE_ROOT_FD;
    context.service_executable_fd = PF_TQ_TEST_SERVICE_EXECUTABLE_FD;
    return context;
}

static int pf_tq_test_validate(
    const char *mode,
    const char *stage_text,
    const char *path
) {
    pf_tq_seccomp_stage_v2 stage;
    pf_tq_seccomp_context_v2 context;
    unsigned char *bytes;
    size_t size;
    char error[PF_TQ_SECCOMP_V2_ERROR_BYTES];
    int result;
    if (pf_tq_test_stage(stage_text, &stage) != 0) return 2;
    context = pf_tq_test_context(stage);
    bytes = pf_tq_test_read_policy(path, &size);
    result = pf_tq_seccomp_validate_v2(
        bytes, size, &context, error, sizeof(error));
    free(bytes);
    if (strcmp(mode, "--validate") == 0) {
        if (result != 0 || error[0] != '\0') {
            (void)fprintf(stderr, "PF-SECCOMP-DRIVER:unexpected-reject:%s\n", error);
            return 1;
        }
    } else {
        if (result == 0 || error[0] == '\0') {
            (void)fprintf(stderr, "PF-SECCOMP-DRIVER:unexpected-accept\n");
            return 1;
        }
    }
    return 0;
}

static int pf_tq_test_invalid_inputs(const char *mode, const char *path) {
    pf_tq_seccomp_context_v2 context = pf_tq_test_context(PF_TQ_SECCOMP_ADAPTER_V2);
    unsigned char *bytes = NULL;
    size_t size = 0U;
    char error[PF_TQ_SECCOMP_V2_ERROR_BYTES];
    int result;
    if (strcmp(mode, "--invalid-context") == 0 ||
            strcmp(mode, "--invalid-fd-context") == 0) {
        bytes = pf_tq_test_read_policy(path, &size);
        if (strcmp(mode, "--invalid-context") == 0) {
            context.stage = (pf_tq_seccomp_stage_v2)99;
        } else {
            context.durable_root_fd = context.proc_root_fd;
        }
        result = pf_tq_seccomp_validate_v2(
            bytes, size, &context, error, sizeof(error));
        free(bytes);
    } else {
        result = pf_tq_seccomp_validate_v2(
            NULL, 0U, &context, error, sizeof(error));
    }
    return result != 0 && error[0] != '\0' ? 0 : 1;
}

static void pf_tq_test_runtime_child(
    const char *mode,
    const unsigned char *bytes,
    size_t size,
    int target_fd
) {
    pf_tq_seccomp_context_v2 context = pf_tq_test_context(PF_TQ_SECCOMP_ADAPTER_V2);
    char error[PF_TQ_SECCOMP_V2_ERROR_BYTES];
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) _exit(120);
    if (pf_tq_seccomp_install_v2(
            bytes, size, &context, error, sizeof(error)) != 0) {
        ssize_t ignored = write(
            STDERR_FILENO, error, strnlen(error, sizeof(error)));
        (void)ignored;
        _exit(121);
    }
    if (strcmp(mode, "--runtime-allowed") == 0) {
        if (syscall(SYS_fcntl, target_fd, F_GETFD, 0) < 0) {
            (void)syscall(SYS_exit_group, 256);
        }
        (void)syscall(SYS_exit_group, 256);
    } else if (strcmp(mode, "--runtime-wrong-argument") == 0) {
        (void)syscall(SYS_fcntl, target_fd, F_GETFL, 0);
    } else if (strcmp(mode, "--runtime-high-bits") == 0) {
        uint64_t widened_fd = ((uint64_t)1U << 32U) | (unsigned)target_fd;
        (void)syscall(SYS_fcntl, widened_fd, F_GETFD, 0);
    } else if (strcmp(mode, "--runtime-mask-reject") == 0) {
        (void)syscall(SYS_exit_group, 1);
    } else {
        (void)syscall(SYS_getpid);
    }
    (void)syscall(SYS_exit_group, 256);
    _exit(122);
}

static int pf_tq_test_runtime(const char *mode, const char *path) {
    unsigned char *bytes;
    size_t size;
    pid_t child;
    int target_fd;
    int status = 0;
    bytes = pf_tq_test_read_policy(path, &size);
    target_fd = open("/dev/null", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (target_fd != PF_TQ_TEST_RUNTIME_FD) {
        free(bytes);
        if (target_fd >= 0) (void)close(target_fd);
        pf_tq_test_fail("runtime-fixed-fd");
    }
    child = fork();
    if (child < 0) {
        free(bytes);
        (void)close(target_fd);
        pf_tq_test_fail("runtime-fork");
    }
    if (child == 0) {
        pf_tq_test_runtime_child(mode, bytes, size, target_fd);
    }
    if (waitpid(child, &status, 0) != child) {
        free(bytes);
        (void)close(target_fd);
        pf_tq_test_fail("runtime-waitpid");
    }
    free(bytes);
    if (close(target_fd) != 0) pf_tq_test_fail("runtime-close");
    if (strcmp(mode, "--runtime-allowed") == 0) {
        return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 1;
    }
    return WIFSIGNALED(status) && WTERMSIG(status) == SIGSYS ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc == 4 && (strcmp(argv[1], "--validate") == 0 ||
            strcmp(argv[1], "--reject") == 0)) {
        return pf_tq_test_validate(argv[1], argv[2], argv[3]);
    }
    if (argc == 3 && (strcmp(argv[1], "--invalid-context") == 0 ||
            strcmp(argv[1], "--invalid-fd-context") == 0 ||
            strncmp(argv[1], "--runtime-", 10U) == 0)) {
        if (strcmp(argv[1], "--invalid-context") == 0 ||
                strcmp(argv[1], "--invalid-fd-context") == 0) {
            return pf_tq_test_invalid_inputs(argv[1], argv[2]);
        }
        return pf_tq_test_runtime(argv[1], argv[2]);
    }
    if (argc == 2 && strcmp(argv[1], "--null-policy") == 0) {
        return pf_tq_test_invalid_inputs(argv[1], NULL);
    }
    return 2;
}
