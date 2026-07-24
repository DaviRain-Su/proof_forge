#ifndef PROOF_FORGE_TASK_QUALIFICATION_AUTHORITY_POLICY_FD_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_AUTHORITY_POLICY_FD_V2_H

#include "task_qualification_authority_policy_v2.h"

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_AUTHORITY_POLICY_FD_V2_ERROR_BYTES 256U

typedef struct pf_tq_authority_policy_fd_v2 {
    pf_tq_authority_policy_v2 policy;
    uint64_t device;
    uint64_t inode;
    uint64_t mode;
    uid_t uid;
    gid_t gid;
} pf_tq_authority_policy_fd_v2;

/*
 * Stable-pread the inherited read-only authorityPolicyFd without changing its
 * offset, then exact-parse it against the caller's independently activated
 * ContentRef expectation.  Success owns the parsed policy projection.
 */
int pf_tq_authority_policy_fd_consume_v2(
    int fd,
    const pf_tq_authority_policy_expectation_v2 *expected,
    pf_tq_authority_policy_fd_v2 *result,
    char *error,
    size_t error_size
);

void pf_tq_authority_policy_fd_free_v2(
    pf_tq_authority_policy_fd_v2 *consumed
);

#ifdef __cplusplus
}
#endif

#endif
