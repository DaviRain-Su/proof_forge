#define _GNU_SOURCE
/* Test-owned driver for the ADR-0021 raw artifact payload C owner. */
#include "task_qualification_artifact_payload_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void pf_tq_test_fail(const char *where) {
    (void)fprintf(stderr, "PF-ARTIFACT-PAYLOAD-DRIVER:%s:errno=%d\n", where, errno);
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
    const char *identifier,
    const char *version,
    const char *ref_digest,
    const char *plain_digest
) {
    pf_tq_wire_content_ref_v2 ref;
    pf_tq_artifact_payload_v2 payload;
    unsigned char expected_plain[32];
    struct stat metadata;
    char error[PF_TQ_ARTIFACT_PAYLOAD_V2_ERROR_BYTES];
    int open_flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC;
    int expected_fd_flags = FD_CLOEXEC;
    int fd;
    int result;
    off_t before;
    off_t after;
    memset(&ref, 0, sizeof(ref));
    memset(&payload, 0, sizeof(payload));
    if (strcmp(mutation, "read-write-fd") == 0) {
        open_flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC;
    }
    if (strcmp(mutation, "no-cloexec-fd") == 0) {
        open_flags = O_RDONLY | O_NOFOLLOW;
    }
    if (strcmp(mutation, "expected-flags-zero") == 0) expected_fd_flags = 0;
    fd = open(path, open_flags);
    if (fd < 0 || fstat(fd, &metadata) != 0) pf_tq_test_fail("open-or-stat");
    if (snprintf(ref.schema, sizeof(ref.schema), "%s",
            strcmp(mutation, "schema") == 0
                ? "proof-forge.task-qualification-fixture-resolved-blob.v1"
                : PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA) <= 0 ||
            snprintf(ref.id, sizeof(ref.id), "%s",
                strcmp(mutation, "id") == 0 ? "Bad/Id" : identifier) <= 0 ||
            snprintf(ref.version, sizeof(ref.version), "%s",
                strcmp(mutation, "version") == 0 ? "01.0.0" : version) <= 0 ||
            pf_tq_test_hex(ref_digest, ref.digest) != 0 ||
            pf_tq_test_hex(plain_digest, expected_plain) != 0) {
        (void)close(fd);
        pf_tq_test_fail("arguments");
    }
    if (strcmp(mutation, "digest") == 0) ref.digest[0] ^= 1U;
    before = lseek(fd, 0, SEEK_CUR);
    result = pf_tq_artifact_payload_verify_fd_v2(
        fd, expected_fd_flags, &ref, &payload, error, sizeof(error));
    after = lseek(fd, 0, SEEK_CUR);
    if (strcmp(expectation, "--accept") == 0) {
        if (result != 0 || error[0] != '\0' || payload.bytes == NULL ||
                payload.size != (size_t)metadata.st_size ||
                memcmp(payload.plain_sha256, expected_plain, 32U) != 0 ||
                payload.device != (uint64_t)metadata.st_dev ||
                payload.inode != (uint64_t)metadata.st_ino ||
                before != 0 || after != before) {
            pf_tq_artifact_payload_free_v2(&payload);
            (void)close(fd);
            return 1;
        }
    } else if (result == 0 || error[0] == '\0' || payload.bytes != NULL ||
            payload.size != 0U || before != 0 || after != before) {
        pf_tq_artifact_payload_free_v2(&payload);
        (void)close(fd);
        return 1;
    }
    pf_tq_artifact_payload_free_v2(&payload);
    if (payload.bytes != NULL || payload.size != 0U || close(fd) != 0) return 1;
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_artifact_payload_v2 payload;
    char error[PF_TQ_ARTIFACT_PAYLOAD_V2_ERROR_BYTES];
    int result;
    memset(&payload, 0x5a, sizeof(payload));
    result = pf_tq_artifact_payload_verify_fd_v2(
        -1, 7, NULL, &payload, error, sizeof(error));
    pf_tq_artifact_payload_free_v2(&payload);
    return result != 0 && error[0] != '\0' &&
        payload.bytes == NULL && payload.size == 0U ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--invalid-input") == 0) {
        return pf_tq_test_invalid();
    }
    if (argc == 8 && (strcmp(argv[1], "--accept") == 0 ||
            strcmp(argv[1], "--reject") == 0)) {
        return pf_tq_test_run(
            argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
    }
    return 2;
}
