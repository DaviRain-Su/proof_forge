#define _GNU_SOURCE
/* Test-owned driver for the protected-handoff static C owner. */
#include "task_qualification_handoff_v2.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static void pf_tq_test_fail(const char *message) {
    (void)fprintf(stderr, "PF-HANDOFF-DRIVER:%s:errno=%d\n", message, errno);
    exit(111);
}

static int pf_tq_test_hex_value(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static int pf_tq_test_hex(const char *text, unsigned char *output, size_t size) {
    size_t index;
    if (text == NULL || strlen(text) != 2U * size) return -1;
    for (index = 0U; index < size; ++index) {
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
            (uint64_t)metadata.st_size > PF_TQ_HANDOFF_V2_MAX_BYTES) {
        if (fd >= 0) (void)close(fd);
        pf_tq_test_fail("handoff-open-or-stat");
    }
    *size = (size_t)metadata.st_size;
    bytes = malloc(*size);
    if (bytes == NULL) {
        (void)close(fd);
        pf_tq_test_fail("handoff-allocate");
    }
    while (offset < *size) {
        ssize_t amount = read(fd, bytes + offset, *size - offset);
        if (amount <= 0) {
            free(bytes);
            (void)close(fd);
            pf_tq_test_fail("handoff-read");
        }
        offset += (size_t)amount;
    }
    if (close(fd) != 0) {
        free(bytes);
        pf_tq_test_fail("handoff-close");
    }
    return bytes;
}

static void pf_tq_test_ref(
    pf_tq_wire_content_ref_v2 *reference,
    const char *schema,
    const char *identifier,
    unsigned char seed
) {
    memset(reference, 0, sizeof(*reference));
    (void)snprintf(reference->schema, sizeof(reference->schema), "%s", schema);
    (void)snprintf(reference->id, sizeof(reference->id), "%s", identifier);
    (void)snprintf(reference->version, sizeof(reference->version), "1.0.0");
    memset(reference->digest, seed, sizeof(reference->digest));
}

static void pf_tq_test_identity(
    pf_tq_wire_verifier_identity_v2 *identity,
    const char *identifier,
    unsigned char seed
) {
    memset(identity, 0, sizeof(*identity));
    (void)snprintf(identity->id, sizeof(identity->id), "%s", identifier);
    pf_tq_test_ref(&identity->executable,
        "proof-forge.task-qualification-artifact-payload.v1",
        seed == 1U ? "adapter-executable" :
            (seed == 11U ? "snapshot-parser-executable" : "trusted-clock-executable"),
        seed);
    pf_tq_test_ref(&identity->closure,
        "proof-forge.task-qualification-artifact-payload.v1",
        seed == 1U ? "adapter-closure" :
            (seed == 11U ? "snapshot-parser-closure" : "trusted-clock-closure"),
        (unsigned char)(seed + 1U));
    memset(identity->source_digest, (unsigned char)(seed + 2U),
        sizeof(identity->source_digest));
    pf_tq_test_ref(&identity->build_policy,
        "proof-forge.task-qualification-artifact-payload.v1",
        seed == 1U ? "adapter-build-policy" :
            (seed == 11U ? "snapshot-parser-build-policy" : "trusted-clock-build-policy"),
        (unsigned char)(seed + 3U));
}

static pf_tq_handoff_expectation_v2 pf_tq_test_expectation(
    pf_tq_handoff_principal_v2 principals[4]
) {
    static const char *const principal_ids[4] = {
        "principal-architecture", "principal-quality", "principal-release",
        "principal-security"
    };
    static const char *const key_ids[4] = {
        "key-architecture", "key-quality", "key-release", "key-security"
    };
    static const char *const public_keys[4] = {
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
        "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
        "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
        "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"
    };
    static const uint32_t roles[4] = {
        PF_TQ_HANDOFF_ROLE_ARCHITECTURE_V2,
        PF_TQ_HANDOFF_ROLE_QUALITY_V2,
        PF_TQ_HANDOFF_ROLE_RELEASE_V2,
        PF_TQ_HANDOFF_ROLE_SECURITY_V2
    };
    pf_tq_handoff_expectation_v2 expected;
    size_t index;
    memset(&expected, 0, sizeof(expected));
    expected.task_id = "TASK-D1-01";
    expected.operation = "task-qualification";
    expected.run_id = "run-handoff-v2";
    expected.nonce = "nonce-handoff-v2";
    memset(expected.candidate.commit, '1', 40U);
    expected.candidate.commit[40] = '\0';
    memset(expected.candidate.tree_object_id, '2', 40U);
    expected.candidate.tree_object_id[40] = '\0';
    memset(expected.candidate.archive_sha256, 0x33, 32U);
    pf_tq_test_ref(&expected.authority_policy,
        "proof-forge.bootstrap-authority-policy.v1",
        "bootstrap-authority-root", 0x40U);
    pf_tq_test_ref(&expected.production_profile_pin,
        "proof-forge.task-qualification-production-profile-pin.v1",
        "tq-pin-d1-01-tq-00112233445566778899aabbccddeeff0011223344556677",
        0x41U);
    memset(expected.gate_set_digest, 0x42, sizeof(expected.gate_set_digest));
    pf_tq_test_identity(&expected.adapter, "adapter-v2", 1U);
    pf_tq_test_identity(&expected.snapshot_parser, "snapshot-parser-v2", 11U);
    pf_tq_test_ref(&expected.authority_store_service,
        PF_TQ_DESCRIPTOR_V2_SCHEMA,
        "task-qualification-store-service-run-handoff-v2", 0x43U);
    (void)snprintf(expected.authority_store_service.version,
        sizeof(expected.authority_store_service.version), "2.0.0");
    pf_tq_test_identity(&expected.trusted_clock_service, "trusted-clock-v2", 21U);
    expected.revocation_head_sequence = 42U;
    memset(expected.revocation_head_digest, 0x44,
        sizeof(expected.revocation_head_digest));
    expected.trusted_instant = "2026-07-25T12:34:56Z";
    expected.channels.authority_policy_fd = 3;
    expected.channels.authority_store_fd = 4;
    expected.channels.candidate_archive_fd = 5;
    expected.channels.provenance_bundle_fd = 6;
    expected.channels.trusted_clock_fd = 7;
    for (index = 0U; index < 4U; ++index) {
        memset(&principals[index], 0, sizeof(principals[index]));
        principals[index].principal_id = principal_ids[index];
        principals[index].key_id = key_ids[index];
        if (pf_tq_test_hex(public_keys[index], principals[index].public_key, 32U) != 0) {
            pf_tq_test_fail("principal-public-key");
        }
        principals[index].roles = roles[index];
        principals[index].current = 1;
    }
    expected.principals = principals;
    expected.principal_count = 4U;
    return expected;
}

static void pf_tq_test_descriptor(
    pf_tq_descriptor_v2 *descriptor,
    const pf_tq_handoff_expectation_v2 *expected
) {
    memset(descriptor, 0, sizeof(*descriptor));
    (void)snprintf(descriptor->id, sizeof(descriptor->id), "%s",
        expected->authority_store_service.id);
    memcpy(descriptor->digest, expected->authority_store_service.digest, 32U);
    (void)snprintf(descriptor->signing_key_ids[0],
        sizeof(descriptor->signing_key_ids[0]), "key-architecture");
    (void)snprintf(descriptor->signing_key_ids[1],
        sizeof(descriptor->signing_key_ids[1]), "key-quality");
    (void)snprintf(descriptor->signing_key_ids[2],
        sizeof(descriptor->signing_key_ids[2]), "key-security");
}

static int pf_tq_test_projection(
    const pf_tq_handoff_v2 *handoff,
    const unsigned char expected_full_digest[32],
    const unsigned char expected_statement_digest[32],
    char *error,
    size_t error_size
) {
    unsigned char expected_candidate_digest[32];
    if (pf_tq_test_hex(
            "e50256e65b0cbf61ac7119e26f8f877a0842b661cfbd1843d85a1e85773e24bf",
            expected_candidate_digest, 32U) != 0) {
        (void)snprintf(error, error_size, "candidate digest fixture rejected");
        return -1;
    }
    if (handoff == NULL ||
            strcmp(handoff->id,
                "task-qualification-protected-handoff-run-handoff-v2") != 0 ||
            strcmp(handoff->task_id, "TASK-D1-01") != 0 ||
            strcmp(handoff->operation, "task-qualification") != 0 ||
            strcmp(handoff->run_id, "run-handoff-v2") != 0 ||
            strcmp(handoff->nonce, "nonce-handoff-v2") != 0 ||
            strcmp(handoff->candidate.commit, "1111111111111111111111111111111111111111") != 0 ||
            handoff->revocation_head_sequence != 42U ||
            handoff->channels.authority_store_fd != 4 ||
            handoff->signature_count < 3U || handoff->signature_count > 4U ||
            memcmp(handoff->candidate.digest,
                expected_candidate_digest, 32U) != 0 ||
            strcmp(handoff->adapter.id, "adapter-v2") != 0 ||
            strcmp(handoff->snapshot_parser.id, "snapshot-parser-v2") != 0 ||
            strcmp(handoff->trusted_clock_service.id, "trusted-clock-v2") != 0 ||
            memcmp(handoff->full_digest, expected_full_digest, 32U) != 0 ||
            memcmp(handoff->statement_digest, expected_statement_digest, 32U) != 0 ||
            handoff->canonical_bytes == NULL || handoff->canonical_size == 0U) {
        (void)snprintf(error, error_size, "typed handoff projection mismatch");
        return -1;
    }
    return 0;
}

static int pf_tq_test_mode_prefix(const char *mode, const char *prefix) {
    return mode != NULL && prefix != NULL &&
        strncmp(mode, prefix, strlen(prefix)) == 0;
}

static void pf_tq_test_mutate_expectation(
    const char *mode,
    pf_tq_handoff_expectation_v2 *expected,
    pf_tq_handoff_principal_v2 principals[4]
) {
    if (strcmp(mode, "--expectation-noncurrent") == 0) {
        principals[3].current = 0;
    } else if (strcmp(mode, "--expectation-duplicate-public-key") == 0) {
        memcpy(principals[3].public_key, principals[2].public_key, 32U);
    } else if (strcmp(mode, "--expectation-count-low") == 0) {
        expected->principal_count = 2U;
    } else if (strcmp(mode, "--expectation-owner-v1") == 0) {
        (void)snprintf(expected->authority_store_service.schema,
            sizeof(expected->authority_store_service.schema),
            "proof-forge.task-qualification-authority-store-service.v1");
    }
}

static void pf_tq_test_mutate_descriptor_join(
    const char *mode,
    pf_tq_descriptor_v2 *descriptor,
    pf_tq_handoff_expectation_v2 *expected,
    pf_tq_handoff_principal_v2 principals[4]
) {
    if (strcmp(mode, "--descriptor-ref-digest") == 0) {
        descriptor->digest[0] ^= 1U;
    } else if (strcmp(mode, "--descriptor-id") == 0) {
        (void)snprintf(descriptor->id, sizeof(descriptor->id),
            "task-qualification-store-service-other");
    } else if (strcmp(mode, "--descriptor-key-order") == 0) {
        char temporary[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
        (void)snprintf(temporary, sizeof(temporary), "%s",
            descriptor->signing_key_ids[0]);
        (void)snprintf(descriptor->signing_key_ids[0],
            sizeof(descriptor->signing_key_ids[0]), "%s",
            descriptor->signing_key_ids[1]);
        (void)snprintf(descriptor->signing_key_ids[1],
            sizeof(descriptor->signing_key_ids[1]), "%s", temporary);
    } else if (strcmp(mode, "--descriptor-key-unknown") == 0) {
        (void)snprintf(descriptor->signing_key_ids[2],
            sizeof(descriptor->signing_key_ids[2]), "key-zzz");
    } else if (strcmp(mode, "--descriptor-service-key-reuse") == 0) {
        memcpy(descriptor->service_public_key, principals[0].public_key, 32U);
    } else if (strcmp(mode, "--descriptor-principal-duplicate") == 0) {
        principals[3].principal_id = principals[1].principal_id;
    } else if (strcmp(mode, "--descriptor-role-coverage") == 0) {
        principals[3].roles = PF_TQ_HANDOFF_ROLE_RELEASE_V2;
    }
    expected->principals = principals;
}

static int pf_tq_test_run(
    const char *mode,
    const char *path,
    const char *full_digest_hex,
    const char *statement_digest_hex
) {
    pf_tq_handoff_principal_v2 principals[4];
    pf_tq_handoff_expectation_v2 expected = pf_tq_test_expectation(principals);
    pf_tq_descriptor_v2 descriptor;
    pf_tq_handoff_v2 handoff;
    unsigned char expected_full_digest[32];
    unsigned char expected_statement_digest[32];
    unsigned char *bytes;
    size_t size;
    char error[PF_TQ_HANDOFF_V2_ERROR_BYTES];
    int result;
    int expectation_reject = pf_tq_test_mode_prefix(mode, "--expectation-");
    int descriptor_reject = pf_tq_test_mode_prefix(mode, "--descriptor-");
    memset(&handoff, 0, sizeof(handoff));
    if (pf_tq_test_hex(full_digest_hex, expected_full_digest, 32U) != 0 ||
            pf_tq_test_hex(statement_digest_hex, expected_statement_digest, 32U) != 0) {
        pf_tq_test_fail("digest-argument");
    }
    if (expectation_reject) {
        pf_tq_test_mutate_expectation(mode, &expected, principals);
    } else if (strcmp(mode, "--alternate-signer-validate") == 0) {
        principals[2].roles |= PF_TQ_HANDOFF_ROLE_SECURITY_V2;
    }
    bytes = pf_tq_test_read(path, &size);
    result = pf_tq_handoff_parse_verify_v2(
        bytes, size, &expected, &handoff, error, sizeof(error));
    free(bytes);
    if (strcmp(mode, "--reject") == 0 || expectation_reject) {
        if (result == 0 || error[0] == '\0') {
            (void)fprintf(stderr, "PF-HANDOFF-DRIVER:unexpected-accept\n");
            pf_tq_handoff_free_v2(&handoff);
            return 1;
        }
        pf_tq_handoff_free_v2(&handoff);
        return 0;
    }
    if (result != 0 || error[0] != '\0' ||
            pf_tq_test_projection(&handoff, expected_full_digest,
                expected_statement_digest, error, sizeof(error)) != 0) {
        (void)fprintf(stderr, "PF-HANDOFF-DRIVER:unexpected-reject:%s\n", error);
        pf_tq_handoff_free_v2(&handoff);
        return 1;
    }
    pf_tq_test_descriptor(&descriptor, &expected);
    if (descriptor_reject) {
        pf_tq_test_mutate_descriptor_join(
            mode, &descriptor, &expected, principals);
        result = pf_tq_handoff_join_descriptor_v2(
            &handoff, &descriptor, &expected, error, sizeof(error));
        if (result == 0 || error[0] == '\0') {
            (void)fprintf(stderr, "PF-HANDOFF-DRIVER:descriptor-unexpected-accept\n");
            pf_tq_handoff_free_v2(&handoff);
            return 1;
        }
    } else if (strcmp(mode, "--validate") == 0 ||
            strcmp(mode, "--alternate-signer-validate") == 0) {
        if (pf_tq_handoff_join_descriptor_v2(
                &handoff, &descriptor, &expected,
                error, sizeof(error)) != 0 || error[0] != '\0') {
            (void)fprintf(stderr, "PF-HANDOFF-DRIVER:descriptor-join:%s\n", error);
            pf_tq_handoff_free_v2(&handoff);
            return 1;
        }
    } else {
        pf_tq_handoff_free_v2(&handoff);
        return 2;
    }
    pf_tq_handoff_free_v2(&handoff);
    return 0;
}

static int pf_tq_test_invalid(void) {
    pf_tq_handoff_v2 handoff;
    pf_tq_handoff_principal_v2 principals[4];
    pf_tq_handoff_expectation_v2 expected = pf_tq_test_expectation(principals);
    char error[PF_TQ_HANDOFF_V2_ERROR_BYTES];
    int result;
    memset(&handoff, 0, sizeof(handoff));
    result = pf_tq_handoff_parse_verify_v2(
        NULL, 0U, &expected, &handoff, error, sizeof(error));
    pf_tq_handoff_free_v2(&handoff);
    return result != 0 && error[0] != '\0' ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc == 5 && (strcmp(argv[1], "--validate") == 0 ||
            strcmp(argv[1], "--alternate-signer-validate") == 0 ||
            strcmp(argv[1], "--reject") == 0 ||
            pf_tq_test_mode_prefix(argv[1], "--expectation-") ||
            pf_tq_test_mode_prefix(argv[1], "--descriptor-"))) {
        return pf_tq_test_run(argv[1], argv[2], argv[3], argv[4]);
    }
    if (argc == 2 && strcmp(argv[1], "--invalid-input") == 0) {
        return pf_tq_test_invalid();
    }
    return 2;
}
