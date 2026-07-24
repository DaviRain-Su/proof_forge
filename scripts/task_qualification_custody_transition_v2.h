#ifndef PROOF_FORGE_TASK_QUALIFICATION_CUSTODY_TRANSITION_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_CUSTODY_TRANSITION_V2_H

#include "task_qualification_seed_custody_v2.h"

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_CUSTODY_TRANSITION_V2_ERROR_BYTES 256U
#define PF_TQ_CUSTODY_TRANSITION_V2_MAX_BYTES 65536U

typedef struct pf_tq_transition_bytes_v2 {
    const unsigned char *bytes;
    size_t size;
} pf_tq_transition_bytes_v2;

typedef struct pf_tq_transition_namespace_v2 {
    uint64_t device;
    uint64_t inode;
} pf_tq_transition_namespace_v2;

typedef struct pf_tq_transition_fd_identity_v2 {
    int fd;
    uint64_t device;
    uint64_t inode;
    uint64_t mode;
    int fd_flags;
} pf_tq_transition_fd_identity_v2;

typedef struct pf_tq_transition_seed_v2 {
    const char *slot;
    const char *key_id;
    int fd;
    uint64_t device;
    uint64_t inode;
} pf_tq_transition_seed_v2;

typedef struct pf_tq_transition_fd_role_v2 {
    int fd;
    int fd_flags;
} pf_tq_transition_fd_role_v2;

typedef struct pf_tq_custody_transition_data_v2 {
    pid_t supervisor_pid;
    uint64_t start_time_ticks;
    pf_tq_transition_namespace_v2 user_namespace;
    pf_tq_transition_namespace_v2 pid_namespace;
    pid_t adapter_pid;
    pf_tq_transition_fd_identity_v2 adapter_endpoint;
    pf_tq_transition_fd_identity_v2 service_endpoint;
    int service_executable_fd;
    pf_tq_transition_bytes_v2 service_executable_ref;
    unsigned char service_executable_payload_sha256[32];
    pf_tq_transition_seed_v2 seeds[PF_TQ_SEED_CUSTODY_V2_COUNT];
} pf_tq_custody_transition_data_v2;

/* Capture one current FD identity, including exact F_GETFD flags. */
int pf_tq_transition_capture_fd_v2(
    int fd,
    pf_tq_transition_fd_identity_v2 *identity,
    char *error,
    size_t error_size
);

/* Capture current PID/start-time and U/P namespace identities via procRootFd. */
int pf_tq_transition_self_identity_v2(
    int proc_root_fd,
    pid_t *pid,
    uint64_t *start_time_ticks,
    pf_tq_transition_namespace_v2 *user_namespace,
    pf_tq_transition_namespace_v2 *pid_namespace,
    char *error,
    size_t error_size
);

/* Enumerate <self-pid>/fd through procRootFd and require the exact sorted set. */
int pf_tq_transition_validate_fd_roles_v2(
    int proc_root_fd,
    const pf_tq_transition_fd_role_v2 *roles,
    size_t role_count,
    char *error,
    size_t error_size
);

/*
 * Create exactly one MFD_ALLOW_SEALING memfd at transition_fd (never dup),
 * write the canonical closed transition, and apply the exact four seals.
 */
int pf_tq_custody_transition_create_v2(
    int transition_fd,
    int proc_root_fd,
    const pf_tq_custody_transition_data_v2 *data,
    char *error,
    size_t error_size
);

/*
 * Exact-decode and compare a sealed inherited transition against independently
 * reconstructed runtime facts, then close transition_fd on every return path.
 */
int pf_tq_custody_transition_consume_v2(
    int transition_fd,
    int proc_root_fd,
    const pf_tq_custody_transition_data_v2 *expected,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
