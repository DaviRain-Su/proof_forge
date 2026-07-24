#ifndef PROOF_FORGE_TASK_QUALIFICATION_SEED_CUSTODY_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_SEED_CUSTODY_V2_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_SEED_CUSTODY_V2_COUNT 4U
#define PF_TQ_SEED_CUSTODY_V2_ERROR_BYTES 256U

typedef struct pf_tq_seed_expectation_v2 {
    const char *slot;
    const char *key_id;
    int fd;
    unsigned char public_key[32];
} pf_tq_seed_expectation_v2;

typedef struct pf_tq_seed_custody_config_v2 {
    int seed_root_fd;
    dev_t seed_root_device;
    ino_t seed_root_inode;
    uid_t service_uid;
    gid_t service_gid;
    pf_tq_seed_expectation_v2 seeds[PF_TQ_SEED_CUSTODY_V2_COUNT];
} pf_tq_seed_custody_config_v2;

typedef struct pf_tq_custodied_seed_v2 {
    int fd;
    dev_t device;
    ino_t inode;
    unsigned char seed[32];
    unsigned char public_key[32];
} pf_tq_custodied_seed_v2;

typedef struct pf_tq_seed_custody_v2 {
    int initialized;
    pf_tq_custodied_seed_v2 seeds[PF_TQ_SEED_CUSTODY_V2_COUNT];
} pf_tq_seed_custody_v2;

/*
 * Consume one already-opened seedRootFd and open the four literal seed files
 * exactly once, in service/role-0/role-1/role-2 order. The root FD must have
 * been opened O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC and is closed on every
 * return path. Each seed open must directly return its policy-fixed FD; this
 * function never dup(2)s or moves a descriptor.
 *
 * On success the four seed FDs remain open with FD_CLOEXEC cleared for the
 * static supervisor->service exec transition. The caller owns the result and
 * must call pf_tq_seed_custody_close_v2 before any non-exit return. On failure
 * all opened seed FDs are closed and all copied seed material is cleansed.
 */
int pf_tq_seed_custody_open_v2(
    const pf_tq_seed_custody_config_v2 *config,
    pf_tq_seed_custody_v2 *custody,
    char *error,
    size_t error_size
);

void pf_tq_seed_custody_close_v2(pf_tq_seed_custody_v2 *custody);

#ifdef __cplusplus
}
#endif

#endif
