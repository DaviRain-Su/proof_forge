#ifndef PROOF_FORGE_TASK_QUALIFICATION_KERNEL_TRANSITION_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_KERNEL_TRANSITION_V2_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_KERNEL_V2_ERROR_BYTES 256U
#define PF_TQ_KERNEL_V2_CAP_SETGID 6U
#define PF_TQ_KERNEL_V2_CAP_SETUID 7U
#define PF_TQ_KERNEL_V2_CAP_SETPCAP 8U
#define PF_TQ_KERNEL_V2_CAP_SYS_PTRACE 19U
#define PF_TQ_KERNEL_V2_CAP_SYS_ADMIN 21U
#define PF_TQ_KERNEL_V2_CAP_BIT(value) (UINT64_C(1) << (value))
#define PF_TQ_KERNEL_V2_PRESEED_MASK \
    (PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SETGID) | \
     PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SETUID) | \
     PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SETPCAP) | \
     PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SYS_PTRACE) | \
     PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SYS_ADMIN))
#define PF_TQ_KERNEL_V2_CUSTODY_MASK \
    (PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SETPCAP) | \
     PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SYS_PTRACE))
#define PF_TQ_KERNEL_V2_STEADY_MASK \
    PF_TQ_KERNEL_V2_CAP_BIT(PF_TQ_KERNEL_V2_CAP_SYS_PTRACE)

typedef enum pf_tq_kernel_crosscheck_v2 {
    PF_TQ_KERNEL_CROSSCHECK_FULL_V2 = 0,
    PF_TQ_KERNEL_CROSSCHECK_FILTERED_V2 = 1
} pf_tq_kernel_crosscheck_v2;

/*
 * All mutating APIs below are intentionally irreversible. If one returns an
 * error after beginning a transition, the supervisor/service must durably
 * reject the reserved tuple and terminate; retrying in the same process is
 * outside the contract.
 */
typedef struct pf_tq_kernel_snapshot_v2 {
    uint64_t inheritable;
    uint64_t permitted;
    uint64_t effective;
    uint64_t bounding;
    uint64_t ambient;
    uid_t uid[4];
    gid_t gid[4];
    int supplementary_group_count;
    int no_new_privs;
} pf_tq_kernel_snapshot_v2;

/* Read fixed self/status through a pinned procRootFd and cross-check it. */
int pf_tq_kernel_snapshot_read_v2(
    int proc_root_fd,
    pf_tq_kernel_crosscheck_v2 crosscheck,
    pf_tq_kernel_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

/*
 * After namespace/mount setup and before forking the adapter, irreversibly
 * converge setup authority to exact B/P/E=[6,7,8,19,21], I/A=[], NNP=0.
 */
int pf_tq_kernel_converge_preseed_v2(
    int proc_root_fd,
    char *error,
    size_t error_size
);

/* Adapter setup: exact preSeed -> all capability sets empty and NNP=1. */
int pf_tq_kernel_isolate_adapter_v2(
    int proc_root_fd,
    uid_t adapter_uid,
    gid_t adapter_gid,
    char *error,
    size_t error_size
);

/*
 * Supervisor pre-seed transition. The caller must still possess the exact
 * preSeed capability minimum. Success yields B/P/E/I/A=[8,19], exact service
 * IDs, no supplementary groups, and no_new_privs still zero.
 */
int pf_tq_kernel_prepare_custody_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
);

/* Set no_new_privs immediately before the custody seccomp/static exec step. */
int pf_tq_kernel_custody_no_new_privs_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
);

/*
 * First post-exec service transition: require all five sets [8,19], drop
 * bounding 19 then 8, clear ambient, and converge to P/E=[19], B/I/A=[] before
 * any inherited seed FD is read.
 */
int pf_tq_kernel_service_post_exec_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
);

/* Final filtered-stage all-zero capability transition before role signing. */
int pf_tq_kernel_terminal_lockdown_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
