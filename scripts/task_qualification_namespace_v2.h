#ifndef PROOF_FORGE_TASK_QUALIFICATION_NAMESPACE_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_NAMESPACE_V2_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_NAMESPACE_V2_ERROR_BYTES 256U

typedef struct pf_tq_namespace_identity_v2 {
    uint64_t device;
    uint64_t inode;
} pf_tq_namespace_identity_v2;

typedef struct pf_tq_namespace_set_v2 {
    pf_tq_namespace_identity_v2 user_namespace;
    pf_tq_namespace_identity_v2 pid_namespace;
    pf_tq_namespace_identity_v2 mount_namespace;
} pf_tq_namespace_set_v2;

typedef struct pf_tq_namespace_id_map_entry_v2 {
    uint32_t inside_id;
    uint32_t outside_id;
} pf_tq_namespace_id_map_entry_v2;

/* Validate the exact two-entry UID/GID maps and an allow setgroups gate through
 * a pinned proc root. Entries must be inside-ID sorted and all four outside
 * subordinate IDs must be distinct. */
int pf_tq_namespace_validate_maps_v2(
    int proc_root_fd,
    const pf_tq_namespace_id_map_entry_v2 uid_map[2],
    const pf_tq_namespace_id_map_entry_v2 gid_map[2],
    char *error,
    size_t error_size
);

/* Capture the current process's user/PID/mount namespace identities through a
 * pinned proc root and require a read-only nosuid/nodev/noexec tmpfs root plus
 * read-only nosuid/nodev/noexec procfs. */
int pf_tq_namespace_current_v2(
    int proc_root_fd,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
);

/* Require the caller to be PID 1 in parent namespace P, enter a fresh mount
 * namespace, create a detached readonly tmpfs empty root, chroot into it, and
 * materialize a detached PID-local readonly procfs. proc_root_release_fd is a
 * setup-only CLOEXEC descriptor that is consumed immediately before fsmount;
 * procfs must directly reuse that exact number, with no descriptor move. */
int pf_tq_namespace_enter_service_v2(
    int proc_root_release_fd,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
);

/* While the service remains PID 1 in P, set a fresh child PID namespace A for
 * the one subsequent adapter fork. A is observed from the unique live child. */
int pf_tq_namespace_prepare_adapter_pid_v2(
    int proc_root_fd,
    char *error,
    size_t error_size
);

/* In the unique adapter child (PID 1 in A), enter a separate mount namespace,
 * consume inherited service procfs, and materialize A's detached procfs at the
 * same fixed descriptor number. */
int pf_tq_namespace_enter_adapter_v2(
    int inherited_proc_root_fd,
    const pf_tq_namespace_set_v2 *service_namespaces,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
);

/* Observe one positive canonical decimal peer PID through the service's pinned
 * proc root without accepting caller-controlled path text. */
int pf_tq_namespace_peer_v2(
    int proc_root_fd,
    pid_t peer_pid,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
