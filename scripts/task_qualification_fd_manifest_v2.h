#ifndef PROOF_FORGE_TASK_QUALIFICATION_FD_MANIFEST_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_FD_MANIFEST_V2_H

#include "task_qualification_custody_transition_v2.h"
#include "task_qualification_handoff_v2.h"
#include "task_qualification_isolation_policy_v2.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_FD_MANIFEST_V2_ERROR_BYTES 256U
#define PF_TQ_FD_MANIFEST_V2_COUNT 44U
#define PF_TQ_FD_MANIFEST_V2_ADAPTER_STEADY_COUNT 5U
#define PF_TQ_FD_MANIFEST_V2_SERVICE_POST_EXEC_COUNT 13U
#define PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_COUNT 14U
#define PF_TQ_FD_MANIFEST_V2_SERVICE_STEADY_COUNT 12U

#define PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_DURABLE_ROOT_INDEX 21U
#define PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_PROC_ROOT_INDEX 24U
#define PF_TQ_FD_MANIFEST_V2_SERVICE_PRE_EXEC_EXECUTABLE_INDEX 30U

/*
 * Bind the one production lifecycle vocabulary to an otherwise-unbound
 * isolation-policy expectation.  Rebinding the same canonical owner is
 * idempotent; caller-supplied or partially populated manifest authority is
 * rejected rather than overwritten.
 */
int pf_tq_fd_manifest_bind_expectation_v2(
    pf_tq_isolation_expectation_v2 *expected,
    char *error,
    size_t error_size
);

/*
 * Require the exact 44 policy rows, adapter handoff FD joins, service
 * pre/post/steady retention rules, and distinct socket endpoints.
 */
int pf_tq_fd_manifest_validate_policy_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    char *error,
    size_t error_size
);

/* Exact typed lookup within the closed production process/stage vocabulary. */
int pf_tq_fd_manifest_lookup_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const char *process,
    const char *stage,
    const char *role,
    int *fd,
    int *close_on_exec,
    char *error,
    size_t error_size
);

/*
 * Project one closed stage to the strictly FD-sorted runtime set consumed by
 * pf_tq_transition_validate_fd_roles_v2.  The projection includes stdio
 * 0/1/2 with fd_flags=0 and does not modify output on rejection.
 */
int pf_tq_fd_manifest_project_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    const char *process,
    const char *stage,
    pf_tq_transition_fd_role_v2 *output,
    size_t capacity,
    size_t *written,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
