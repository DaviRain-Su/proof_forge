#ifndef PROOF_FORGE_TASK_QUALIFICATION_HANDOFF_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_HANDOFF_V2_H

#include "task_qualification_descriptor_v2.h"
#include "task_qualification_wire_v2.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_HANDOFF_V2_MAX_BYTES 4194304U
#define PF_TQ_HANDOFF_V2_ERROR_BYTES 256U
#define PF_TQ_HANDOFF_V2_SCHEMA \
    "proof-forge.task-qualification-protected-handoff.v1"
#define PF_TQ_HANDOFF_V2_ID_BYTES 257U
#define PF_TQ_HANDOFF_V2_TASK_ID_BYTES 4097U
#define PF_TQ_HANDOFF_V2_OPERATION_BYTES 32U
#define PF_TQ_HANDOFF_V2_GIT_OBJECT_BYTES 41U
#define PF_TQ_HANDOFF_V2_INSTANT_BYTES 21U
#define PF_TQ_HANDOFF_V2_MAX_SIGNATURES 256U

#define PF_TQ_HANDOFF_ROLE_ARCHITECTURE_V2 UINT32_C(1)
#define PF_TQ_HANDOFF_ROLE_QUALITY_V2 UINT32_C(2)
#define PF_TQ_HANDOFF_ROLE_SECURITY_V2 UINT32_C(4)
#define PF_TQ_HANDOFF_ROLE_RELEASE_V2 UINT32_C(8)
#define PF_TQ_HANDOFF_REQUIRED_ROLE_MASK_V2 \
    (PF_TQ_HANDOFF_ROLE_ARCHITECTURE_V2 | \
     PF_TQ_HANDOFF_ROLE_QUALITY_V2 | \
     PF_TQ_HANDOFF_ROLE_SECURITY_V2)
#define PF_TQ_HANDOFF_ROLE_MASK_V2 \
    (PF_TQ_HANDOFF_REQUIRED_ROLE_MASK_V2 | PF_TQ_HANDOFF_ROLE_RELEASE_V2)

typedef struct pf_tq_handoff_candidate_v2 {
    char commit[PF_TQ_HANDOFF_V2_GIT_OBJECT_BYTES];
    char tree_object_id[PF_TQ_HANDOFF_V2_GIT_OBJECT_BYTES];
    unsigned char archive_sha256[32];
    unsigned char digest[32];
} pf_tq_handoff_candidate_v2;

typedef struct pf_tq_handoff_channels_v2 {
    int authority_policy_fd;
    int authority_store_fd;
    int candidate_archive_fd;
    int provenance_bundle_fd;
    int trusted_clock_fd;
} pf_tq_handoff_channels_v2;

typedef struct pf_tq_handoff_principal_v2 {
    const char *principal_id;
    const char *key_id;
    unsigned char public_key[32];
    uint32_t roles;
    int current;
} pf_tq_handoff_principal_v2;

typedef struct pf_tq_handoff_expectation_v2 {
    const char *task_id;
    const char *operation;
    const char *run_id;
    const char *nonce;
    pf_tq_handoff_candidate_v2 candidate;
    pf_tq_wire_content_ref_v2 authority_policy;
    pf_tq_wire_content_ref_v2 production_profile_pin;
    unsigned char gate_set_digest[32];
    pf_tq_wire_verifier_identity_v2 adapter;
    pf_tq_wire_verifier_identity_v2 snapshot_parser;
    pf_tq_wire_content_ref_v2 authority_store_service;
    pf_tq_wire_verifier_identity_v2 trusted_clock_service;
    uint64_t revocation_head_sequence;
    unsigned char revocation_head_digest[32];
    const char *trusted_instant;
    pf_tq_handoff_channels_v2 channels;
    const pf_tq_handoff_principal_v2 *principals;
    size_t principal_count;
} pf_tq_handoff_expectation_v2;

typedef struct pf_tq_handoff_verified_signer_v2 {
    char key_id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    char principal_id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    unsigned char public_key[32];
    unsigned char signature[64];
    uint32_t roles;
} pf_tq_handoff_verified_signer_v2;

typedef struct pf_tq_handoff_v2 {
    unsigned char *canonical_bytes;
    size_t canonical_size;
    unsigned char full_digest[32];
    unsigned char statement_digest[32];
    char id[PF_TQ_HANDOFF_V2_ID_BYTES];
    char task_id[PF_TQ_HANDOFF_V2_TASK_ID_BYTES];
    char operation[PF_TQ_HANDOFF_V2_OPERATION_BYTES];
    char run_id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    char nonce[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    pf_tq_handoff_candidate_v2 candidate;
    pf_tq_wire_content_ref_v2 authority_policy;
    pf_tq_wire_content_ref_v2 production_profile_pin;
    unsigned char gate_set_digest[32];
    pf_tq_wire_verifier_identity_v2 adapter;
    pf_tq_wire_verifier_identity_v2 snapshot_parser;
    pf_tq_wire_content_ref_v2 authority_store_service;
    pf_tq_wire_verifier_identity_v2 trusted_clock_service;
    uint64_t revocation_head_sequence;
    unsigned char revocation_head_digest[32];
    char trusted_instant[PF_TQ_HANDOFF_V2_INSTANT_BYTES];
    pf_tq_handoff_channels_v2 channels;
    pf_tq_handoff_verified_signer_v2 *verified_signers;
    size_t signature_count;
} pf_tq_handoff_v2;

int pf_tq_handoff_parse_verify_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_handoff_expectation_v2 *expected,
    pf_tq_handoff_v2 *result,
    char *error,
    size_t error_size
);

int pf_tq_handoff_join_descriptor_v2(
    const pf_tq_handoff_v2 *handoff,
    const pf_tq_descriptor_v2 *descriptor,
    const pf_tq_handoff_expectation_v2 *expected,
    char *error,
    size_t error_size
);

void pf_tq_handoff_free_v2(pf_tq_handoff_v2 *handoff);

#ifdef __cplusplus
}
#endif

#endif
