#define _GNU_SOURCE
/* Test-owned driver for the BootstrapAuthorityPolicyV1 static C owner. */
#include "task_qualification_authority_policy_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void pf_tq_test_fail(const char *message) {
    (void)fprintf(stderr, "PF-AUTHORITY-POLICY-DRIVER:%s:errno=%d\n", message, errno);
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
            (uint64_t)metadata.st_size > PF_TQ_AUTHORITY_POLICY_V2_MAX_BYTES) {
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

static int pf_tq_test_projection(
    const pf_tq_authority_policy_v2 *policy,
    const unsigned char expected_digest[32],
    const char *expected_version,
    char *error,
    size_t error_size
) {
    static const char *const principal_ids[4] = {
        "principal-architecture", "principal-quality",
        "principal-release", "principal-security"
    };
    static const char *const key_ids[4] = {
        "key-architecture", "key-quality", "key-release", "key-security"
    };
    static const uint32_t roles[4] = {
        PF_TQ_HANDOFF_ROLE_ARCHITECTURE_V2,
        PF_TQ_HANDOFF_ROLE_QUALITY_V2,
        PF_TQ_HANDOFF_ROLE_RELEASE_V2,
        PF_TQ_HANDOFF_ROLE_SECURITY_V2
    };
    pf_tq_handoff_principal_v2 views[PF_TQ_AUTHORITY_POLICY_V2_MAX_PRINCIPALS];
    size_t view_count = 0U;
    size_t index;
    if (policy == NULL ||
            strcmp(policy->id, "bootstrap-authority-root") != 0 ||
            strcmp(policy->version, expected_version) != 0 ||
            memcmp(policy->digest, expected_digest, 32U) != 0 ||
            policy->principal_count != 4U || policy->task_rule_count != 6U ||
            strcmp(policy->task_rules[0].task_id, "TASK-D0-01") != 0 ||
            strcmp(policy->task_rules[5].task_id, "TASK-D0-06") != 0 ||
            strcmp(policy->private_scan_policy.schema,
                "proof-forge.private-scan-policy.v1") != 0 ||
            strcmp(policy->authority_store_service.schema,
                "proof-forge.authority-store-service.v1") != 0 ||
            strcmp(policy->verifier.id, "bootstrap-task-verifier") != 0 ||
            policy->canonical_bytes == NULL || policy->canonical_size == 0U) {
        (void)snprintf(error, error_size, "typed policy projection mismatch");
        return -1;
    }
    for (index = 0U; index < 4U; ++index) {
        if (strcmp(policy->principals[index].principal_id,
                    principal_ids[index]) != 0 ||
                strcmp(policy->principals[index].key_id, key_ids[index]) != 0 ||
                policy->principals[index].roles != roles[index]) {
            (void)snprintf(error, error_size,
                "typed principal projection mismatch");
            return -1;
        }
    }
    if (pf_tq_authority_policy_handoff_registry_v2(
            policy, views, PF_TQ_AUTHORITY_POLICY_V2_MAX_PRINCIPALS,
            &view_count, error, error_size) != 0 || view_count != 4U) {
        return -1;
    }
    for (index = 0U; index < view_count; ++index) {
        if (strcmp(views[index].principal_id,
                    policy->principals[index].principal_id) != 0 ||
                strcmp(views[index].key_id,
                    policy->principals[index].key_id) != 0 ||
                memcmp(views[index].public_key,
                    policy->principals[index].public_key, 32U) != 0 ||
                views[index].roles != policy->principals[index].roles ||
                views[index].current != 1) {
            (void)snprintf(error, error_size,
                "handoff registry projection mismatch");
            return -1;
        }
    }
    return 0;
}

static int pf_tq_test_run(
    const char *mode,
    const char *path,
    const char *digest_hex,
    const char *expected_version
) {
    pf_tq_authority_policy_expectation_v2 expected;
    pf_tq_authority_policy_v2 policy;
    unsigned char expected_digest[32];
    unsigned char *bytes;
    size_t size;
    char error[PF_TQ_AUTHORITY_POLICY_V2_ERROR_BYTES];
    int result;
    memset(&expected, 0, sizeof(expected));
    memset(&policy, 0, sizeof(policy));
    if (pf_tq_test_digest(digest_hex, expected_digest) != 0) {
        pf_tq_test_fail("digest-argument");
    }
    expected.require_ref = 1;
    (void)snprintf(expected.claimed_ref.schema,
        sizeof(expected.claimed_ref.schema),
        "%s", PF_TQ_AUTHORITY_POLICY_V2_SCHEMA);
    (void)snprintf(expected.claimed_ref.id,
        sizeof(expected.claimed_ref.id), "bootstrap-authority-root");
    (void)snprintf(expected.claimed_ref.version,
        sizeof(expected.claimed_ref.version), "%s", expected_version);
    memcpy(expected.claimed_ref.digest, expected_digest, 32U);
    if (strcmp(mode, "--claimed-ref-reject") == 0) {
        expected.claimed_ref.digest[0] ^= 1U;
    }
    bytes = pf_tq_test_read(path, &size);
    result = pf_tq_authority_policy_parse_v2(
        bytes, size, &expected, &policy, error, sizeof(error));
    free(bytes);
    if (strcmp(mode, "--validate") == 0) {
        if (result != 0 || error[0] != '\0' ||
                pf_tq_test_projection(&policy, expected_digest,
                    expected_version, error, sizeof(error)) != 0) {
            (void)fprintf(stderr,
                "PF-AUTHORITY-POLICY-DRIVER:unexpected-reject:%s\n", error);
            pf_tq_authority_policy_free_v2(&policy);
            return 1;
        }
    } else if (result == 0 || error[0] == '\0') {
        (void)fprintf(stderr,
            "PF-AUTHORITY-POLICY-DRIVER:unexpected-accept\n");
        pf_tq_authority_policy_free_v2(&policy);
        return 1;
    }
    pf_tq_authority_policy_free_v2(&policy);
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_authority_policy_v2 policy;
    char error[PF_TQ_AUTHORITY_POLICY_V2_ERROR_BYTES];
    int result;
    memset(&policy, 0, sizeof(policy));
    result = pf_tq_authority_policy_parse_v2(
        NULL, 0U, NULL, &policy, error, sizeof(error));
    pf_tq_authority_policy_free_v2(&policy);
    return result != 0 && error[0] != '\0' ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc == 5 && (strcmp(argv[1], "--validate") == 0 ||
            strcmp(argv[1], "--reject") == 0 ||
            strcmp(argv[1], "--claimed-ref-reject") == 0)) {
        return pf_tq_test_run(argv[1], argv[2], argv[3], argv[4]);
    }
    if (argc == 2 && strcmp(argv[1], "--invalid-input") == 0) {
        return pf_tq_test_invalid();
    }
    return 2;
}
