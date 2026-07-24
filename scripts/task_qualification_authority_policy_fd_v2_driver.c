#define _GNU_SOURCE
/* Test-owned driver for stable authorityPolicyFd exact consumption. */
#include "task_qualification_authority_policy_fd_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void pf_tq_test_fail(const char *where) {
    (void)fprintf(stderr, "PF-AUTHORITY-POLICY-FD-DRIVER:%s:errno=%d\n",
        where, errno);
    exit(111);
}

static int pf_tq_test_hex_digit(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static int pf_tq_test_hex(const char *text, unsigned char output[32]) {
    size_t index;
    if (text == NULL || strlen(text) != 64U) return -1;
    for (index = 0U; index < 32U; ++index) {
        int high = pf_tq_test_hex_digit((unsigned char)text[2U * index]);
        int low = pf_tq_test_hex_digit((unsigned char)text[2U * index + 1U]);
        if (high < 0 || low < 0) return -1;
        output[index] = (unsigned char)((unsigned)high * 16U + (unsigned)low);
    }
    return 0;
}

static int pf_tq_test_run(
    const char *expectation,
    const char *mutation,
    const char *path,
    const char *digest_hex
) {
    pf_tq_authority_policy_expectation_v2 expected;
    pf_tq_authority_policy_fd_v2 consumed;
    unsigned char expected_digest[32];
    struct stat metadata;
    char error[PF_TQ_AUTHORITY_POLICY_FD_V2_ERROR_BYTES];
    int open_flags = O_RDONLY | O_NOFOLLOW;
    int fd;
    int result;
    off_t before;
    off_t after;
    memset(&expected, 0, sizeof(expected));
    memset(&consumed, 0, sizeof(consumed));
    if (pf_tq_test_hex(digest_hex, expected_digest) != 0) {
        pf_tq_test_fail("digest-argument");
    }
    if (strcmp(mutation, "read-write-fd") == 0) {
        open_flags = O_RDWR | O_NOFOLLOW;
    }
    if (strcmp(mutation, "cloexec-fd") == 0) open_flags |= O_CLOEXEC;
    if (strcmp(mutation, "nonblock-fd") == 0) open_flags |= O_NONBLOCK;
    fd = open(path, open_flags);
    if (fd <= 2 || fstat(fd, &metadata) != 0) pf_tq_test_fail("open-or-stat");
    (void)snprintf(expected.claimed_ref.schema,
        sizeof(expected.claimed_ref.schema), "%s",
        PF_TQ_AUTHORITY_POLICY_V2_SCHEMA);
    (void)snprintf(expected.claimed_ref.id,
        sizeof(expected.claimed_ref.id), "bootstrap-authority-root");
    (void)snprintf(expected.claimed_ref.version,
        sizeof(expected.claimed_ref.version), "1.0.0");
    memcpy(expected.claimed_ref.digest, expected_digest, 32U);
    if (strcmp(mutation, "schema") == 0) {
        (void)snprintf(expected.claimed_ref.schema,
            sizeof(expected.claimed_ref.schema),
            "proof-forge.bootstrap-authority-policy.v2");
    } else if (strcmp(mutation, "id") == 0) {
        (void)snprintf(expected.claimed_ref.id,
            sizeof(expected.claimed_ref.id), "bootstrap-authority-other");
    } else if (strcmp(mutation, "version") == 0) {
        (void)snprintf(expected.claimed_ref.version,
            sizeof(expected.claimed_ref.version), "01.0.0");
    }
    before = lseek(fd, 0, SEEK_CUR);
    result = pf_tq_authority_policy_fd_consume_v2(
        fd, &expected, &consumed, error, sizeof(error));
    after = lseek(fd, 0, SEEK_CUR);
    if (strcmp(expectation, "--accept") == 0) {
        if (result != 0 || error[0] != '\0' ||
                consumed.policy.canonical_bytes == NULL ||
                consumed.policy.canonical_size != (size_t)metadata.st_size ||
                memcmp(consumed.policy.digest, expected_digest, 32U) != 0 ||
                strcmp(consumed.policy.id, "bootstrap-authority-root") != 0 ||
                strcmp(consumed.policy.version, "1.0.0") != 0 ||
                consumed.policy.principal_count != 4U ||
                consumed.device != (uint64_t)metadata.st_dev ||
                consumed.inode != (uint64_t)metadata.st_ino ||
                consumed.mode != (uint64_t)metadata.st_mode ||
                consumed.uid != metadata.st_uid || consumed.gid != metadata.st_gid ||
                before != 0 || after != before) {
            pf_tq_authority_policy_fd_free_v2(&consumed);
            (void)close(fd);
            return 1;
        }
    } else if (result == 0 || error[0] == '\0' ||
            consumed.policy.canonical_bytes != NULL ||
            consumed.policy.canonical_size != 0U || consumed.device != 0U ||
            consumed.inode != 0U || before != 0 || after != before) {
        pf_tq_authority_policy_fd_free_v2(&consumed);
        (void)close(fd);
        return 1;
    }
    pf_tq_authority_policy_fd_free_v2(&consumed);
    if (consumed.policy.canonical_bytes != NULL ||
            consumed.policy.canonical_size != 0U || consumed.device != 0U ||
            consumed.inode != 0U || close(fd) != 0) return 1;
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_authority_policy_fd_v2 consumed;
    char error[PF_TQ_AUTHORITY_POLICY_FD_V2_ERROR_BYTES];
    int result;
    memset(&consumed, 0x5a, sizeof(consumed));
    result = pf_tq_authority_policy_fd_consume_v2(
        -1, NULL, &consumed, error, sizeof(error));
    pf_tq_authority_policy_fd_free_v2(&consumed);
    return result != 0 && error[0] != '\0' &&
        consumed.policy.canonical_bytes == NULL && consumed.device == 0U &&
        consumed.inode == 0U ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--invalid-input") == 0) {
        return pf_tq_test_invalid();
    }
    if (argc == 5 && (strcmp(argv[1], "--accept") == 0 ||
            strcmp(argv[1], "--reject") == 0)) {
        return pf_tq_test_run(argv[1], argv[2], argv[3], argv[4]);
    }
    return 2;
}
