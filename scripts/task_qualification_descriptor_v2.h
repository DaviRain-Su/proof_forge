#ifndef PROOF_FORGE_TASK_QUALIFICATION_DESCRIPTOR_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_DESCRIPTOR_V2_H

#include "task_qualification_wire_v2.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_DESCRIPTOR_V2_MAX_BYTES 4194304U
#define PF_TQ_DESCRIPTOR_V2_ERROR_BYTES 256U
#define PF_TQ_DESCRIPTOR_V2_SCHEMA \
    "proof-forge.task-qualification-authority-store-service.v2"
#define PF_TQ_DESCRIPTOR_V2_ID_BYTES 128U

typedef struct pf_tq_descriptor_identity_v2 {
    uint64_t device;
    uint64_t inode;
} pf_tq_descriptor_identity_v2;

typedef struct pf_tq_descriptor_expectation_v2 {
    const char *run_id;
    int require_ref;
    pf_tq_wire_content_ref_v2 claimed_ref;
} pf_tq_descriptor_expectation_v2;

typedef struct pf_tq_descriptor_v2 {
    unsigned char *canonical_bytes;
    size_t canonical_size;
    unsigned char digest[32];
    char id[PF_TQ_DESCRIPTOR_V2_ID_BYTES];
    unsigned char service_public_key[32];
    pf_tq_wire_verifier_identity_v2 verifier;
    pf_tq_wire_verifier_identity_v2 supervisor;
    pf_tq_wire_content_ref_v2 isolation_policy;
    char signing_key_ids[3][PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    uint32_t adapter_uid;
    uint32_t adapter_gid;
    uint32_t service_uid;
    uint32_t service_gid;
    pf_tq_descriptor_identity_v2 user_namespace;
    pf_tq_descriptor_identity_v2 seed_root;
} pf_tq_descriptor_v2;

int pf_tq_descriptor_parse_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_descriptor_expectation_v2 *expected,
    pf_tq_descriptor_v2 *result,
    char *error,
    size_t error_size
);

void pf_tq_descriptor_free_v2(pf_tq_descriptor_v2 *descriptor);

#ifdef __cplusplus
}
#endif

#endif
