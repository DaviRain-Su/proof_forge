#define _GNU_SOURCE
#include "task_qualification_authority_policy_fd_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <unistd.h>

static int pf_tq_authority_policy_fd_error(
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

static void pf_tq_authority_policy_fd_clear_error(
    char *error,
    size_t error_size
) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_authority_policy_fd_free_v2(
    pf_tq_authority_policy_fd_v2 *consumed
) {
    if (consumed == NULL) return;
    pf_tq_authority_policy_free_v2(&consumed->policy);
    memset(consumed, 0, sizeof(*consumed));
}

static int pf_tq_authority_policy_fd_stat_equal(
    const struct stat *left,
    const struct stat *right
) {
    return left != NULL && right != NULL &&
        left->st_dev == right->st_dev &&
        left->st_ino == right->st_ino &&
        left->st_mode == right->st_mode &&
        left->st_uid == right->st_uid &&
        left->st_gid == right->st_gid &&
        left->st_nlink == right->st_nlink &&
        left->st_size == right->st_size &&
        left->st_mtim.tv_sec == right->st_mtim.tv_sec &&
        left->st_mtim.tv_nsec == right->st_mtim.tv_nsec &&
        left->st_ctim.tv_sec == right->st_ctim.tv_sec &&
        left->st_ctim.tv_nsec == right->st_ctim.tv_nsec;
}

static int pf_tq_authority_policy_fd_no_capability(
    int fd,
    char *error,
    size_t error_size
) {
    ssize_t amount;
    errno = 0;
    amount = fgetxattr(fd, "security.capability", NULL, 0U);
    if (amount >= 0 || errno != ENODATA) {
        return pf_tq_authority_policy_fd_error(error, error_size,
            "authorityPolicyFd security.capability absence rejected");
    }
    return 0;
}

static int pf_tq_authority_policy_fd_read(
    int fd,
    unsigned char *bytes,
    size_t size,
    char *error,
    size_t error_size
) {
    size_t offset = 0U;
    unsigned char extra = 0U;
    while (offset < size) {
        ssize_t amount = pread(fd, bytes + offset, size - offset, (off_t)offset);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) {
            return pf_tq_authority_policy_fd_error(error, error_size,
                "authorityPolicyFd exact pread failed");
        }
        offset += (size_t)amount;
    }
    for (;;) {
        ssize_t amount = pread(fd, &extra, 1U, (off_t)size);
        if (amount < 0 && errno == EINTR) continue;
        if (amount != 0) {
            return pf_tq_authority_policy_fd_error(error, error_size,
                "authorityPolicyFd trailing-byte probe failed");
        }
        break;
    }
    return 0;
}

int pf_tq_authority_policy_fd_consume_v2(
    int fd,
    const pf_tq_authority_policy_expectation_v2 *expected,
    pf_tq_authority_policy_fd_v2 *result,
    char *error,
    size_t error_size
) {
    pf_tq_authority_policy_fd_v2 consumed;
    struct stat before;
    struct stat after;
    unsigned char *bytes = NULL;
    size_t size;
    int descriptor_flags;
    int status_flags;
    int outcome = -1;
    memset(&consumed, 0, sizeof(consumed));
    memset(&before, 0, sizeof(before));
    memset(&after, 0, sizeof(after));
    pf_tq_authority_policy_fd_clear_error(error, error_size);
    if (result != NULL) memset(result, 0, sizeof(*result));
    if (fd < 0 || expected == NULL || result == NULL) {
        return pf_tq_authority_policy_fd_error(error, error_size,
            "authorityPolicyFd API arguments rejected");
    }
    descriptor_flags = fcntl(fd, F_GETFD);
    status_flags = fcntl(fd, F_GETFL);
    if (descriptor_flags != 0 || status_flags < 0 ||
            (status_flags & O_ACCMODE) != O_RDONLY ||
            (status_flags & (O_APPEND | O_NONBLOCK | O_PATH)) != 0) {
        return pf_tq_authority_policy_fd_error(error, error_size,
            "authorityPolicyFd descriptor flags rejected");
    }
    if (fstat(fd, &before) != 0 || !S_ISREG(before.st_mode) ||
            before.st_nlink != 1 || before.st_size <= 0 ||
            (uint64_t)before.st_size >
                (uint64_t)PF_TQ_AUTHORITY_POLICY_V2_MAX_BYTES ||
            (before.st_mode & (S_ISUID | S_ISGID)) != 0) {
        return pf_tq_authority_policy_fd_error(error, error_size,
            "authorityPolicyFd metadata rejected");
    }
    if (pf_tq_authority_policy_fd_no_capability(fd,
            error, error_size) != 0) return -1;
    size = (size_t)before.st_size;
    bytes = malloc(size);
    if (bytes == NULL) {
        (void)pf_tq_authority_policy_fd_error(error, error_size,
            "authorityPolicyFd allocation failed");
        goto cleanup;
    }
    if (pf_tq_authority_policy_fd_read(fd, bytes, size,
            error, error_size) != 0 ||
            pf_tq_authority_policy_fd_no_capability(fd,
                error, error_size) != 0 ||
            fstat(fd, &after) != 0 ||
            !pf_tq_authority_policy_fd_stat_equal(&before, &after)) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_authority_policy_fd_error(error, error_size,
                "authorityPolicyFd changed during stable read");
        }
        goto cleanup;
    }
    if (pf_tq_authority_policy_parse_v2(bytes, size, expected,
            &consumed.policy, error, error_size) != 0) goto cleanup;
    if (consumed.policy.canonical_bytes == NULL ||
            consumed.policy.canonical_size != size ||
            memcmp(consumed.policy.canonical_bytes, bytes, size) != 0) {
        (void)pf_tq_authority_policy_fd_error(error, error_size,
            "authorityPolicyFd parser did not retain the exact snapshot");
        goto cleanup;
    }
    consumed.device = (uint64_t)before.st_dev;
    consumed.inode = (uint64_t)before.st_ino;
    consumed.mode = (uint64_t)before.st_mode;
    consumed.uid = before.st_uid;
    consumed.gid = before.st_gid;
    *result = consumed;
    memset(&consumed, 0, sizeof(consumed));
    pf_tq_authority_policy_fd_clear_error(error, error_size);
    outcome = 0;
cleanup:
    free(bytes);
    pf_tq_authority_policy_fd_free_v2(&consumed);
    return outcome;
}
