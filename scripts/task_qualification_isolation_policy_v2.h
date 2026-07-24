#ifndef PROOF_FORGE_TASK_QUALIFICATION_ISOLATION_POLICY_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_ISOLATION_POLICY_V2_H

#include "task_qualification_seccomp_v2.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_ISOLATION_POLICY_V2_MAX_BYTES 4194304U
#define PF_TQ_ISOLATION_POLICY_V2_ERROR_BYTES 256U
#define PF_TQ_ISOLATION_POLICY_V2_ID_BYTES 128U
#define PF_TQ_ISOLATION_POLICY_V2_OPERATION_BYTES 32U
#define PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES 128U
#define PF_TQ_ISOLATION_POLICY_V2_PATH_BYTES 4096U

typedef struct pf_tq_isolation_identity_v2 {
    uint64_t device;
    uint64_t inode;
} pf_tq_isolation_identity_v2;

typedef struct pf_tq_isolation_id_map_v2 {
    uint32_t inside_id;
    uint32_t outside_id;
} pf_tq_isolation_id_map_v2;

typedef struct pf_tq_isolation_mount_v2 {
    char *target;
    size_t target_size;
    pf_tq_isolation_identity_v2 source;
    int read_only;
    int no_suid;
    int no_dev;
    int no_exec;
} pf_tq_isolation_mount_v2;

typedef struct pf_tq_isolation_fd_role_v2 {
    char process[PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES];
    char stage[PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES];
    char role[PF_TQ_ISOLATION_POLICY_V2_ROLE_BYTES];
    int fd;
    int close_on_exec;
} pf_tq_isolation_fd_role_v2;

/* The lifecycle owner supplies the closed semantic role vocabulary.  Policy
 * bytes choose the fixed FD numbers, but cannot add/remove/rename roles or
 * alter their transition-time close-on-exec state. */
typedef struct pf_tq_isolation_fd_manifest_v2 {
    const char *process;
    const char *stage;
    const char *role;
    int close_on_exec;
} pf_tq_isolation_fd_manifest_v2;

typedef struct pf_tq_isolation_bytes_v2 {
    const unsigned char *bytes;
    size_t size;
} pf_tq_isolation_bytes_v2;

typedef struct pf_tq_isolation_expectation_v2 {
    const char *task_id;
    const char *operation;
    const char *run_id;
    const char *nonce;
    pf_tq_isolation_identity_v2 user_namespace;
    pf_tq_isolation_identity_v2 seed_root;
    uint32_t adapter_uid;
    uint32_t adapter_gid;
    uint32_t service_uid;
    uint32_t service_gid;
    const pf_tq_isolation_fd_manifest_v2 *fd_manifest;
    size_t fd_manifest_count;
    size_t proc_root_role_index;
    size_t durable_root_role_index;
    size_t service_executable_role_index;
    int require_digest;
    unsigned char digest[32];
} pf_tq_isolation_expectation_v2;

typedef struct pf_tq_isolation_policy_v2 {
    unsigned char *canonical_bytes;
    size_t canonical_size;
    unsigned char digest[32];

    char task_id[PF_TQ_ISOLATION_POLICY_V2_ID_BYTES];
    char operation[PF_TQ_ISOLATION_POLICY_V2_OPERATION_BYTES];
    char run_id[PF_TQ_ISOLATION_POLICY_V2_ID_BYTES];
    char nonce[PF_TQ_ISOLATION_POLICY_V2_ID_BYTES];

    pf_tq_isolation_identity_v2 user_namespace;
    pf_tq_isolation_identity_v2 parent_pid_namespace;
    pf_tq_isolation_identity_v2 adapter_pid_namespace;
    pf_tq_isolation_identity_v2 service_mount_namespace;
    pf_tq_isolation_identity_v2 adapter_mount_namespace;
    pf_tq_isolation_id_map_v2 uid_map[2];
    pf_tq_isolation_id_map_v2 gid_map[2];
    uint32_t adapter_uid;
    uint32_t adapter_gid;
    uint32_t service_uid;
    uint32_t service_gid;
    pf_tq_isolation_identity_v2 service_proc_root;
    pf_tq_isolation_identity_v2 durable_state_root;
    pf_tq_isolation_identity_v2 seed_root;

    pf_tq_isolation_mount_v2 *service_mounts;
    size_t service_mount_count;
    pf_tq_isolation_mount_v2 *adapter_mounts;
    size_t adapter_mount_count;
    pf_tq_isolation_fd_role_v2 *fd_roles;
    size_t fd_role_count;
    int service_executable_fd;
    pf_tq_isolation_bytes_v2 seccomp_policies[3];
} pf_tq_isolation_policy_v2;

/* Exact-decode the full signed isolation-policy payload, join it to the parsed
 * descriptor/handoff expectation and lifecycle FD manifest, recompute its
 * domain digest, and validate all three embedded seccomp tables.  On success
 * result owns its allocations and no pointer references caller input. */
int pf_tq_isolation_policy_parse_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_isolation_expectation_v2 *expected,
    pf_tq_isolation_policy_v2 *result,
    char *error,
    size_t error_size
);

void pf_tq_isolation_policy_free_v2(pf_tq_isolation_policy_v2 *policy);

#ifdef __cplusplus
}
#endif

#endif
