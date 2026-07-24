#define _GNU_SOURCE
/* Test-owned driver for the production ADR-0021 isolation-policy owner. */
#include "task_qualification_fd_manifest_v2.h"
#include "task_qualification_isolation_policy_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void pf_tq_test_fail(const char *message) {
    (void)fprintf(stderr, "PF-ISOLATION-POLICY-DRIVER:%s:errno=%d\n", message, errno);
    exit(111);
}

static int pf_tq_test_hex_value(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static int pf_tq_test_digest(const char *text, unsigned char output[32]) {
    size_t index;
    if (text == NULL || strlen(text) != 64U) return -1;
    for (index = 0U; index < 32U; ++index) {
        int high = pf_tq_test_hex_value((unsigned char)text[2U * index]);
        int low = pf_tq_test_hex_value((unsigned char)text[2U * index + 1U]);
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
            (uint64_t)metadata.st_size > PF_TQ_ISOLATION_POLICY_V2_MAX_BYTES) {
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

static pf_tq_isolation_expectation_v2 pf_tq_test_expectation(
    const char *digest_hex
) {
    pf_tq_isolation_expectation_v2 expected;
    memset(&expected, 0, sizeof(expected));
    expected.task_id = "TASK-D1-01";
    expected.operation = "task-qualification";
    expected.run_id = "run-policy-v2";
    expected.nonce = "nonce-policy-v2";
    expected.user_namespace.device = 10U;
    expected.user_namespace.inode = 11U;
    expected.seed_root.device = 20U;
    expected.seed_root.inode = 23U;
    expected.adapter_uid = 1001U;
    expected.adapter_gid = 1003U;
    expected.service_uid = 1002U;
    expected.service_gid = 1004U;
    if (pf_tq_fd_manifest_bind_expectation_v2(
            &expected, NULL, 0U) != 0) {
        pf_tq_test_fail("fd-manifest-bind");
    }
    expected.require_digest = 1;
    if (pf_tq_test_digest(digest_hex, expected.digest) != 0) {
        pf_tq_test_fail("digest-argument");
    }
    return expected;
}

static pf_tq_handoff_channels_v2 pf_tq_test_channels(void) {
    pf_tq_handoff_channels_v2 channels;
    channels.authority_policy_fd = 30;
    channels.authority_store_fd = 31;
    channels.candidate_archive_fd = 32;
    channels.provenance_bundle_fd = 33;
    channels.trusted_clock_fd = 34;
    return channels;
}

static int pf_tq_test_result(
    const pf_tq_isolation_policy_v2 *policy,
    char *error,
    size_t error_size
) {
    if (policy == NULL || strcmp(policy->task_id, "TASK-D1-01") != 0 ||
            strcmp(policy->operation, "task-qualification") != 0 ||
            strcmp(policy->run_id, "run-policy-v2") != 0 ||
            strcmp(policy->nonce, "nonce-policy-v2") != 0 ||
            policy->uid_map[0].inside_id != 1001U ||
            policy->uid_map[1].inside_id != 1002U ||
            policy->gid_map[0].inside_id != 1003U ||
            policy->gid_map[1].inside_id != 1004U ||
            policy->service_mount_count != 1U ||
            policy->adapter_mount_count != 1U ||
            policy->fd_role_count != PF_TQ_FD_MANIFEST_V2_COUNT ||
            policy->fd_roles[0].fd != 30 || policy->fd_roles[1].fd != 31 ||
            policy->fd_roles[
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_DURABLE_ROOT_INDEX].fd != 41 ||
            policy->fd_roles[
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_PROC_ROOT_INDEX].fd != 40 ||
            policy->fd_roles[
                PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_EXECUTABLE_INDEX].fd != 42 ||
            policy->seccomp_policies[PF_TQ_SECCOMP_ADAPTER_V2].bytes == NULL ||
            policy->seccomp_policies[PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2].bytes == NULL ||
            policy->seccomp_policies[PF_TQ_SECCOMP_SERVICE_FINAL_V2].bytes == NULL) {
        (void)snprintf(error, error_size, "typed policy projection mismatch");
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
    pf_tq_isolation_expectation_v2 expected = pf_tq_test_expectation(digest_hex);
    pf_tq_isolation_policy_v2 policy;
    char error[PF_TQ_ISOLATION_POLICY_V2_ERROR_BYTES];
    int result;
    memset(&policy, 0, sizeof(policy));
    bytes = pf_tq_test_read(path, &size);
    result = pf_tq_isolation_policy_parse_v2(
        bytes, size, &expected, &policy, error, sizeof(error));
    free(bytes);
    if (result == 0) {
        pf_tq_handoff_channels_v2 channels = pf_tq_test_channels();
        result = pf_tq_fd_manifest_validate_policy_v2(
            &policy, &channels, error, sizeof(error));
    }
    if (strcmp(mode, "--validate") == 0) {
        if (result != 0 || error[0] != '\0' ||
                pf_tq_test_result(&policy, error, sizeof(error)) != 0) {
            (void)fprintf(stderr,
                "PF-ISOLATION-POLICY-DRIVER:unexpected-reject:%s\n", error);
            pf_tq_isolation_policy_free_v2(&policy);
            return 1;
        }
    } else if (result == 0 || error[0] == '\0') {
        (void)fprintf(stderr, "PF-ISOLATION-POLICY-DRIVER:unexpected-accept\n");
        pf_tq_isolation_policy_free_v2(&policy);
        return 1;
    }
    pf_tq_isolation_policy_free_v2(&policy);
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_isolation_policy_v2 policy;
    char error[PF_TQ_ISOLATION_POLICY_V2_ERROR_BYTES];
    int result;
    memset(&policy, 0, sizeof(policy));
    result = pf_tq_isolation_policy_parse_v2(
        NULL, 0U, NULL, &policy, error, sizeof(error));
    pf_tq_isolation_policy_free_v2(&policy);
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
