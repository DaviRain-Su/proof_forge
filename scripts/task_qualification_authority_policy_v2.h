#ifndef PROOF_FORGE_TASK_QUALIFICATION_AUTHORITY_POLICY_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_AUTHORITY_POLICY_V2_H

#include "task_qualification_handoff_v2.h"
#include "task_qualification_wire_v2.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_AUTHORITY_POLICY_V2_MAX_BYTES 4194304U
#define PF_TQ_AUTHORITY_POLICY_V2_ERROR_BYTES 256U
#define PF_TQ_AUTHORITY_POLICY_V2_SCHEMA \
    "proof-forge.bootstrap-authority-policy.v1"
#define PF_TQ_AUTHORITY_POLICY_V2_MAX_PRINCIPALS 256U
#define PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES 6U
#define PF_TQ_AUTHORITY_POLICY_V2_ID_BYTES 128U
#define PF_TQ_AUTHORITY_POLICY_V2_TASK_ID_BYTES 32U

typedef struct pf_tq_authority_rule_v2 {
    uint32_t required_roles;
    uint32_t minimum_distinct_signers;
} pf_tq_authority_rule_v2;

typedef struct pf_tq_authority_principal_v2 {
    char principal_id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    char key_id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    unsigned char public_key[32];
    uint32_t roles;
} pf_tq_authority_principal_v2;

typedef struct pf_tq_authority_task_rule_v2 {
    char task_id[PF_TQ_AUTHORITY_POLICY_V2_TASK_ID_BYTES];
    pf_tq_authority_rule_v2 rule;
} pf_tq_authority_task_rule_v2;

typedef struct pf_tq_authority_verifier_v2 {
    char id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    unsigned char executable_digest[32];
    char receipt_key_id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    unsigned char receipt_public_key[32];
} pf_tq_authority_verifier_v2;

typedef struct pf_tq_authority_policy_expectation_v2 {
    pf_tq_wire_content_ref_v2 claimed_ref;
} pf_tq_authority_policy_expectation_v2;

typedef struct pf_tq_authority_policy_v2 {
    unsigned char *canonical_bytes;
    size_t canonical_size;
    unsigned char digest[32];
    char id[PF_TQ_AUTHORITY_POLICY_V2_ID_BYTES];
    char version[PF_TQ_WIRE_V2_VERSION_BYTES];
    pf_tq_authority_principal_v2 *principals;
    size_t principal_count;
    pf_tq_authority_task_rule_v2 task_rules[PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES];
    size_t task_rule_count;
    pf_tq_authority_rule_v2 required_test_set_rule;
    pf_tq_authority_rule_v2 formal_catalog_rule;
    pf_tq_authority_rule_v2 bootstrap_set_rule;
    pf_tq_authority_rule_v2 session_containment_rule;
    pf_tq_authority_rule_v2 freshness_authority_rule;
    pf_tq_authority_rule_v2 private_scan_rule;
    pf_tq_wire_content_ref_v2 private_scan_policy;
    pf_tq_authority_rule_v2 revocation_snapshot_rule;
    pf_tq_wire_content_ref_v2 authority_store_service;
    pf_tq_authority_verifier_v2 verifier;
} pf_tq_authority_policy_v2;

int pf_tq_authority_policy_parse_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_authority_policy_expectation_v2 *expected,
    pf_tq_authority_policy_v2 *result,
    char *error,
    size_t error_size
);

/* The projected principal_id/key_id pointers borrow policy-owned storage and
 * remain valid only until pf_tq_authority_policy_free_v2(policy). */
int pf_tq_authority_policy_handoff_registry_v2(
    const pf_tq_authority_policy_v2 *policy,
    pf_tq_handoff_principal_v2 *principals,
    size_t capacity,
    size_t *written,
    char *error,
    size_t error_size
);

int pf_tq_authority_policy_bind_handoff_v2(
    const pf_tq_authority_policy_v2 *policy,
    pf_tq_handoff_expectation_v2 *handoff,
    pf_tq_handoff_principal_v2 *principal_storage,
    size_t principal_capacity,
    char *error,
    size_t error_size
);

void pf_tq_authority_policy_free_v2(pf_tq_authority_policy_v2 *policy);

#ifdef __cplusplus
}
#endif

#endif
