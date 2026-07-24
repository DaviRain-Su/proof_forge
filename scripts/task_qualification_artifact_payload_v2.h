#ifndef PROOF_FORGE_TASK_QUALIFICATION_ARTIFACT_PAYLOAD_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_ARTIFACT_PAYLOAD_V2_H

#include "task_qualification_wire_v2.h"

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_ARTIFACT_PAYLOAD_V2_ERROR_BYTES 256U
#define PF_TQ_ARTIFACT_PAYLOAD_V2_MAX_BYTES 67108864U
#define PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA \
    "proof-forge.task-qualification-artifact-payload.v1"
#define PF_TQ_ARTIFACT_PAYLOAD_V2_DOMAIN \
    "pf.taskqual.artifact-payload.v1"

typedef struct pf_tq_artifact_payload_v2 {
    unsigned char *bytes;
    size_t size;
    unsigned char plain_sha256[32];
    uint64_t device;
    uint64_t inode;
    uint64_t mode;
    uid_t uid;
    gid_t gid;
} pf_tq_artifact_payload_v2;

/*
 * Stable-pread one pre-opened immutable regular payload FD, require exact
 * flags/single-link/no-setid/no-file-capability metadata, recompute the raw
 * artifact ContentRef domain and independent plain SHA-256, and retain owned
 * bytes on success.  The current file offset is never read or changed.
 */
int pf_tq_artifact_payload_verify_fd_v2(
    int fd,
    int expected_fd_flags,
    const pf_tq_wire_content_ref_v2 *expected_ref,
    pf_tq_artifact_payload_v2 *result,
    char *error,
    size_t error_size
);

void pf_tq_artifact_payload_free_v2(pf_tq_artifact_payload_v2 *payload);

#ifdef __cplusplus
}
#endif

#endif
