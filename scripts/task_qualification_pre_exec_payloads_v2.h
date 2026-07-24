#ifndef PROOF_FORGE_TASK_QUALIFICATION_PRE_EXEC_PAYLOADS_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_PRE_EXEC_PAYLOADS_V2_H

#include "task_qualification_artifact_payload_v2.h"
#include "task_qualification_fd_manifest_v2.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_PRE_EXEC_PAYLOADS_V2_ERROR_BYTES 256U

typedef struct pf_tq_pre_exec_payloads_v2 {
    pf_tq_artifact_payload_v2 adapter_build_policy;
    pf_tq_artifact_payload_v2 adapter_closure;
    pf_tq_artifact_payload_v2 service_executable;
} pf_tq_pre_exec_payloads_v2;

/*
 * Consume the three raw payload FDs retained by the service pre-exec stage.
 * Inputs must be already parsed canonical handoff, v2 descriptor, and
 * isolation-policy values.  This function rechecks their tuple/ref/manifest
 * joins, exact descriptor flags, and raw ContentRef owners.  It does not claim
 * static-ELF structure or runtime executable provenance; those remain a
 * separate executable owner.
 */
int pf_tq_pre_exec_payloads_consume_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_v2 *handoff,
    const pf_tq_descriptor_v2 *descriptor,
    pf_tq_pre_exec_payloads_v2 *result,
    char *error,
    size_t error_size
);

void pf_tq_pre_exec_payloads_free_v2(pf_tq_pre_exec_payloads_v2 *payloads);

#ifdef __cplusplus
}
#endif

#endif
