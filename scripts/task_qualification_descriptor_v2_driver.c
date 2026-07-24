#define _GNU_SOURCE
/* Test-owned driver for the ADR-0021 v2 descriptor C owner. */
#include "task_qualification_descriptor_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void pf_tq_test_fail(const char *message) {
    (void)fprintf(stderr, "PF-DESCRIPTOR-DRIVER:%s:errno=%d\n", message, errno);
    exit(111);
}

static int pf_tq_test_hex(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static int pf_tq_test_digest(const char *text, unsigned char output[32]) {
    size_t index;
    if (text == NULL || strlen(text) != 64U) return -1;
    for (index = 0U; index < 32U; ++index) {
        int high = pf_tq_test_hex((unsigned char)text[2U * index]);
        int low = pf_tq_test_hex((unsigned char)text[2U * index + 1U]);
        if (high < 0 || low < 0) return -1;
        output[index] = (unsigned char)((unsigned)high * 16U + (unsigned)low);
    }
    return 0;
}

static unsigned char *pf_tq_test_read(const char *path, size_t *size) {
    struct stat metadata;
    unsigned char *bytes;
    size_t offset = 0U;
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0 || fstat(fd, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
            metadata.st_size <= 0 ||
            (uint64_t)metadata.st_size > PF_TQ_DESCRIPTOR_V2_MAX_BYTES) {
        if (fd >= 0) (void)close(fd);
        pf_tq_test_fail("descriptor-open-or-stat");
    }
    *size = (size_t)metadata.st_size;
    bytes = malloc(*size);
    if (bytes == NULL) {
        (void)close(fd);
        pf_tq_test_fail("descriptor-allocate");
    }
    while (offset < *size) {
        ssize_t amount = read(fd, bytes + offset, *size - offset);
        if (amount <= 0) {
            free(bytes);
            (void)close(fd);
            pf_tq_test_fail("descriptor-read");
        }
        offset += (size_t)amount;
    }
    if (close(fd) != 0) {
        free(bytes);
        pf_tq_test_fail("descriptor-close");
    }
    return bytes;
}

static pf_tq_descriptor_expectation_v2 pf_tq_test_expectation(
    const char *digest_hex
) {
    pf_tq_descriptor_expectation_v2 expected;
    memset(&expected, 0, sizeof(expected));
    expected.run_id = "run-descriptor-v2";
    expected.require_ref = 1;
    (void)snprintf(expected.claimed_ref.schema,
        sizeof(expected.claimed_ref.schema),
        "%s", PF_TQ_DESCRIPTOR_V2_SCHEMA);
    (void)snprintf(expected.claimed_ref.id, sizeof(expected.claimed_ref.id),
        "task-qualification-store-service-run-descriptor-v2");
    (void)snprintf(expected.claimed_ref.version,
        sizeof(expected.claimed_ref.version), "2.0.0");
    if (pf_tq_test_digest(digest_hex, expected.claimed_ref.digest) != 0) {
        pf_tq_test_fail("digest-argument");
    }
    return expected;
}

static int pf_tq_test_projection(
    const pf_tq_descriptor_v2 *descriptor,
    char *error,
    size_t error_size
) {
    if (descriptor == NULL ||
            strcmp(descriptor->id,
                "task-qualification-store-service-run-descriptor-v2") != 0 ||
            descriptor->adapter_uid != 1001U || descriptor->adapter_gid != 1003U ||
            descriptor->service_uid != 1002U || descriptor->service_gid != 1004U ||
            descriptor->user_namespace.device != 10U ||
            descriptor->user_namespace.inode != 11U ||
            descriptor->seed_root.device != 20U || descriptor->seed_root.inode != 23U ||
            strcmp(descriptor->verifier.id, "authority-store-v2") != 0 ||
            strcmp(descriptor->supervisor.id, "store-supervisor-v2") != 0 ||
            strcmp(descriptor->isolation_policy.id,
                "task-qualification-store-isolation-run-descriptor-v2") != 0 ||
            strcmp(descriptor->signing_key_ids[0], "arch-key") != 0 ||
            strcmp(descriptor->signing_key_ids[1], "quality-key") != 0 ||
            strcmp(descriptor->signing_key_ids[2], "security-key") != 0 ||
            descriptor->canonical_bytes == NULL || descriptor->canonical_size == 0U) {
        (void)snprintf(error, error_size, "typed descriptor projection mismatch");
        return -1;
    }
    return 0;
}

static int pf_tq_test_run(
    const char *mode,
    const char *path,
    const char *digest_hex
) {
    unsigned char *bytes;
    size_t size;
    pf_tq_descriptor_expectation_v2 expected = pf_tq_test_expectation(digest_hex);
    pf_tq_descriptor_v2 descriptor;
    char error[PF_TQ_DESCRIPTOR_V2_ERROR_BYTES];
    int result;
    memset(&descriptor, 0, sizeof(descriptor));
    bytes = pf_tq_test_read(path, &size);
    result = pf_tq_descriptor_parse_v2(
        bytes, size, &expected, &descriptor, error, sizeof(error));
    free(bytes);
    if (strcmp(mode, "--validate") == 0) {
        if (result != 0 || error[0] != '\0' ||
                pf_tq_test_projection(&descriptor, error, sizeof(error)) != 0) {
            (void)fprintf(stderr, "PF-DESCRIPTOR-DRIVER:unexpected-reject:%s\n", error);
            pf_tq_descriptor_free_v2(&descriptor);
            return 1;
        }
    } else if (result == 0 || error[0] == '\0') {
        (void)fprintf(stderr, "PF-DESCRIPTOR-DRIVER:unexpected-accept\n");
        pf_tq_descriptor_free_v2(&descriptor);
        return 1;
    }
    pf_tq_descriptor_free_v2(&descriptor);
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_descriptor_v2 descriptor;
    char error[PF_TQ_DESCRIPTOR_V2_ERROR_BYTES];
    int result;
    memset(&descriptor, 0, sizeof(descriptor));
    result = pf_tq_descriptor_parse_v2(
        NULL, 0U, NULL, &descriptor, error, sizeof(error));
    pf_tq_descriptor_free_v2(&descriptor);
    return result != 0 && error[0] != '\0' ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc == 4 && (strcmp(argv[1], "--validate") == 0 ||
            strcmp(argv[1], "--reject") == 0)) {
        return pf_tq_test_run(argv[1], argv[2], argv[3]);
    }
    if (argc == 2 && strcmp(argv[1], "--invalid-input") == 0) {
        return pf_tq_test_invalid();
    }
    return 2;
}
