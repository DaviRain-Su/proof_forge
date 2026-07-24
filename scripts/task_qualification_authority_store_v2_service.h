#ifndef PROOF_FORGE_TASK_QUALIFICATION_AUTHORITY_STORE_V2_SERVICE_H
#define PROOF_FORGE_TASK_QUALIFICATION_AUTHORITY_STORE_V2_SERVICE_H

#include "task_qualification_durable_state_v2.h"

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_STORE_V2_MAX_FRAME_BYTES 4194304U
#define PF_TQ_STORE_V2_MAX_PACKET_BYTES (4U + PF_TQ_STORE_V2_MAX_FRAME_BYTES)
#define PF_TQ_STORE_V2_MAX_ACCEPTANCE_BYTES 2000000U
#define PF_TQ_STORE_V2_MAX_OBJECTS 4096U
#define PF_TQ_STORE_V2_ID_BYTES 128U
#define PF_TQ_STORE_V2_ERROR_BYTES 256U

typedef struct pf_tq_store_v2_bytes {
    const unsigned char *bytes;
    size_t size;
} pf_tq_store_v2_bytes;

typedef struct pf_tq_store_v2_object {
    const char *kind;
    const char *schema;
    const char *id;
    const char *version;
    const char *digest_domain;
    int embedded_identity;
    pf_tq_store_v2_bytes content;
} pf_tq_store_v2_object;

typedef struct pf_tq_store_v2_signer {
    const char *key_id;
    const char *principal_id;
    unsigned role_mask;
    unsigned char seed[32];
    unsigned char public_key[32];
} pf_tq_store_v2_signer;

#define PF_TQ_STORE_V2_ROLE_ARCHITECTURE (1U << 0)
#define PF_TQ_STORE_V2_ROLE_QUALITY      (1U << 1)
#define PF_TQ_STORE_V2_ROLE_SECURITY     (1U << 2)
#define PF_TQ_STORE_V2_REQUIRED_ROLE_MASK \
    (PF_TQ_STORE_V2_ROLE_ARCHITECTURE | PF_TQ_STORE_V2_ROLE_QUALITY | \
     PF_TQ_STORE_V2_ROLE_SECURITY)

/*
 * Mandatory supervisor-owned direct observers. peer_check revalidates the
 * pinned proc/FD/executable/session facts for the authenticated pid at every
 * checkpoint. current_head re-reads and validates the current policy/head and
 * the unchanged signer-to-principal mapping. terminal_lockdown performs and
 * revalidates the all-zero terminal capability transition. Returning success
 * without those kernel-backed checks is outside this engine's contract.
 */
typedef int (*pf_tq_store_v2_peer_check_fn)(
    void *opaque,
    pid_t peer_pid,
    unsigned checkpoint,
    char *error,
    size_t error_size
);

typedef int (*pf_tq_store_v2_current_head_fn)(
    void *opaque,
    uint64_t *head_sequence,
    unsigned char head_digest[32],
    char *error,
    size_t error_size
);

typedef int (*pf_tq_store_v2_terminal_lockdown_fn)(
    void *opaque,
    char *error,
    size_t error_size
);

typedef struct pf_tq_store_v2_context {
    const char *task_id;
    const char *operation;
    const char *run_id;
    const char *nonce;
    pf_tq_store_v2_bytes service_ref;
    unsigned char handoff_digest[32];
    unsigned char gate_set_digest[32];
    uint64_t head_sequence;
    unsigned char head_digest[32];
    const char *trusted_instant;

    pf_tq_store_v2_bytes adapter;
    pf_tq_store_v2_bytes production_profile_pin_ref;
    pf_tq_store_v2_bytes snapshot_parser;
    pf_tq_store_v2_bytes pre_close_candidate;
    pf_tq_store_v2_bytes closeout_candidate;
    const char *production_profile_digest;

    const pf_tq_store_v2_object *objects;
    size_t object_count;
    unsigned char service_seed[32];
    unsigned char service_public_key[32];
    pf_tq_store_v2_signer role_signers[3];

    int durable_root_fd;
    uid_t durable_uid;
    gid_t durable_gid;
    pf_tq_durable_tuple_v2 durable_tuple;

    uid_t adapter_uid;
    gid_t adapter_gid;
    int require_kernel_credentials;
    int require_pidfd;
    pf_tq_store_v2_peer_check_fn peer_check;
    void *peer_check_opaque;
    pf_tq_store_v2_current_head_fn current_head;
    void *current_head_opaque;
    pf_tq_store_v2_terminal_lockdown_fn terminal_lockdown;
    void *terminal_lockdown_opaque;
} pf_tq_store_v2_context;

/* Checkpoint values passed to peer_check. */
#define PF_TQ_STORE_V2_PEER_HELLO 1U
#define PF_TQ_STORE_V2_PEER_LOOKUP 2U
#define PF_TQ_STORE_V2_PEER_TERMINAL_PREFLIGHT 3U
#define PF_TQ_STORE_V2_PEER_TERMINAL_FINAL 4U

/*
 * Run one exact v2 session on an already-connected AF_UNIX/SOCK_SEQPACKET
 * endpoint. The supervisor must have durably reserved the tuple as active
 * before service startup. Any pre-acceptance error moves active|signing to
 * rejected. A successful terminal response is sent only after the durable
 * accepted event has been fsynced; send failure appends the non-state
 * accepted-response-undelivered audit event.
 */
int pf_tq_store_v2_run(
    int socket_fd,
    pf_tq_store_v2_context *context,
    unsigned char **accepted_bytes,
    size_t *accepted_size,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
