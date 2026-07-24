#ifndef PROOF_FORGE_TASK_QUALIFICATION_WIRE_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_WIRE_V2_H

#include "task_qualification_pf_jcs_v2.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_WIRE_V2_SCHEMA_BYTES 128U
#define PF_TQ_WIRE_V2_CONTENT_ID_BYTES 128U
#define PF_TQ_WIRE_V2_VERSION_BYTES 256U
#define PF_TQ_WIRE_V2_SAFE_ID_BYTES 257U
#define PF_TQ_WIRE_V2_ERROR_BYTES 256U

typedef struct pf_tq_wire_content_ref_v2 {
    char schema[PF_TQ_WIRE_V2_SCHEMA_BYTES];
    char id[PF_TQ_WIRE_V2_CONTENT_ID_BYTES];
    char version[PF_TQ_WIRE_V2_VERSION_BYTES];
    unsigned char digest[32];
} pf_tq_wire_content_ref_v2;

typedef struct pf_tq_wire_verifier_identity_v2 {
    char id[PF_TQ_WIRE_V2_SAFE_ID_BYTES];
    pf_tq_wire_content_ref_v2 executable;
    pf_tq_wire_content_ref_v2 closure;
    unsigned char source_digest[32];
    pf_tq_wire_content_ref_v2 build_policy;
} pf_tq_wire_verifier_identity_v2;

int pf_tq_wire_parse_digest_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    unsigned char digest[32],
    char *error,
    size_t error_size
);

int pf_tq_wire_parse_content_ref_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_wire_content_ref_v2 *result,
    char *error,
    size_t error_size
);

int pf_tq_wire_parse_verifier_identity_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_wire_verifier_identity_v2 *result,
    char *error,
    size_t error_size
);

int pf_tq_wire_content_ref_equal_v2(
    const pf_tq_wire_content_ref_v2 *left,
    const pf_tq_wire_content_ref_v2 *right
);

int pf_tq_wire_verifier_identity_equal_v2(
    const pf_tq_wire_verifier_identity_v2 *left,
    const pf_tq_wire_verifier_identity_v2 *right
);

int pf_tq_wire_safe_id_v2(const char *value);
int pf_tq_wire_profile_id_v2(const char *value);
int pf_tq_wire_semver_v2(const char *value);

#ifdef __cplusplus
}
#endif

#endif
