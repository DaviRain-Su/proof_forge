#ifndef PROOF_FORGE_TASK_QUALIFICATION_SECCOMP_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_SECCOMP_V2_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_SECCOMP_V2_ERROR_BYTES 256U
#define PF_TQ_SECCOMP_V2_MAX_POLICY_BYTES 1048576U

typedef enum pf_tq_seccomp_stage_v2 {
    PF_TQ_SECCOMP_ADAPTER_V2 = 0,
    PF_TQ_SECCOMP_CUSTODY_PRE_EXEC_V2 = 1,
    PF_TQ_SECCOMP_SERVICE_FINAL_V2 = 2
} pf_tq_seccomp_stage_v2;

typedef struct pf_tq_seccomp_context_v2 {
    pf_tq_seccomp_stage_v2 stage;
    int service_executable_fd;
    int proc_root_fd;
    int durable_root_fd;
} pf_tq_seccomp_context_v2;

/* Parse the closed canonical policy, resolve syscall names, enforce ADR-0021
 * hard constraints, and compile a bounded deny-default x86_64 cBPF program. */
int pf_tq_seccomp_validate_v2(
    const unsigned char *policy_bytes,
    size_t policy_size,
    const pf_tq_seccomp_context_v2 *context,
    char *error,
    size_t error_size
);

/* Validate as above, require no_new_privs=1, then install with seccomp flags 0. */
int pf_tq_seccomp_install_v2(
    const unsigned char *policy_bytes,
    size_t policy_size,
    const pf_tq_seccomp_context_v2 *context,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
