#ifndef PROOF_FORGE_TASK_QUALIFICATION_DURABLE_STATE_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_DURABLE_STATE_V2_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_DURABLE_KEY_HEX_BYTES 64
#define PF_TQ_DURABLE_DIGEST_WIRE_BYTES 71
#define PF_TQ_DURABLE_ID_BYTES 128
#define PF_TQ_DURABLE_OPERATION_BYTES 32
#define PF_TQ_DURABLE_TIMESTAMP_BYTES 21
#define PF_TQ_DURABLE_REASON_BYTES 96
#define PF_TQ_DURABLE_ERROR_BYTES 256

typedef enum pf_tq_durable_state_v2 {
    PF_TQ_DURABLE_ABSENT = 0,
    PF_TQ_DURABLE_ACTIVE = 1,
    PF_TQ_DURABLE_SIGNING = 2,
    PF_TQ_DURABLE_ACCEPTED = 3,
    PF_TQ_DURABLE_REJECTED = 4
} pf_tq_durable_state_v2;

typedef struct pf_tq_durable_tuple_v2 {
    char task_id[PF_TQ_DURABLE_ID_BYTES];
    char operation[PF_TQ_DURABLE_OPERATION_BYTES];
    char run_id[PF_TQ_DURABLE_ID_BYTES];
    char nonce[PF_TQ_DURABLE_ID_BYTES];
} pf_tq_durable_tuple_v2;

typedef struct pf_tq_durable_snapshot_v2 {
    pf_tq_durable_state_v2 state;
    unsigned sequence;
    int accepted_response_undelivered;
    char key_hex[PF_TQ_DURABLE_KEY_HEX_BYTES + 1];
    char event_digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
    char acceptance_digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
    char response_digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
    char terminal_timestamp[PF_TQ_DURABLE_TIMESTAMP_BYTES];
    char reason[PF_TQ_DURABLE_REASON_BYTES];
} pf_tq_durable_snapshot_v2;

/*
 * Every function borrows root_fd; it never closes or duplicates it. The root
 * must remain a stable, single-link directory owned by expected_uid/gid with
 * mode exactly 0700. All state mutation uses a per-root flock, O_EXCL 0600
 * temporary files, file fsync, renameat2(RENAME_NOREPLACE), and directory
 * fsync. There is deliberately no rename or fsync fallback.
 */
int pf_tq_durable_validate_root_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    char *error,
    size_t error_size
);

int pf_tq_durable_tuple_init_v2(
    pf_tq_durable_tuple_v2 *tuple,
    const char *task_id,
    const char *operation,
    const char *run_id,
    const char *nonce,
    char *error,
    size_t error_size
);

int pf_tq_durable_inspect_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

int pf_tq_durable_recover_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const char *terminal_timestamp,
    unsigned *recovered_count,
    char *error,
    size_t error_size
);

int pf_tq_durable_reserve_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

int pf_tq_durable_begin_signing_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

int pf_tq_durable_accept_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    const char *acceptance_digest,
    const char *response_digest,
    const char *terminal_timestamp,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

int pf_tq_durable_reject_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    const char *reason,
    const char *terminal_timestamp,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

int pf_tq_durable_mark_undelivered_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
);

const char *pf_tq_durable_state_name_v2(pf_tq_durable_state_v2 state);

#ifdef __cplusplus
}
#endif

#endif
