#ifndef PROOF_FORGE_TASK_QUALIFICATION_SOCKET_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_SOCKET_V2_H

#include "task_qualification_fd_manifest_v2.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_SOCKET_V2_ERROR_BYTES 256U
#define PF_TQ_SOCKET_V2_REQUESTED_BUFFER_BYTES 4194304
#define PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES 8388608

typedef enum pf_tq_socket_endpoint_role_v2 {
    PF_TQ_SOCKET_ADAPTER_V2 = 1,
    PF_TQ_SOCKET_SERVICE_V2 = 2
} pf_tq_socket_endpoint_role_v2;

typedef struct pf_tq_socket_pair_v2 {
    int adapter_fd;
    int service_fd;
    pf_tq_transition_fd_identity_v2 adapter_created;
    pf_tq_transition_fd_identity_v2 service_created;
    int adapter_send_buffer;
    int adapter_receive_buffer;
    int service_send_buffer;
    int service_receive_buffer;
} pf_tq_socket_pair_v2;

/*
 * Create exactly one socketpair(AF_UNIX, SOCK_SEQPACKET|SOCK_CLOEXEC, 0).
 * The two calls must directly return the policy's adapter authority-store and
 * service-endpoint FDs; no dup, retry, bind/connect/accept or fallback exists.
 * Both directions are configured to the fixed requested buffer size and must
 * report at least the fixed Linux effective minimum.
 */
int pf_tq_socket_pair_create_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    pf_tq_socket_pair_v2 *result,
    char *error,
    size_t error_size
);

/* Close exactly the opposite endpoint after fork; retain CLOEXEC on this role. */
int pf_tq_socket_pair_select_v2(
    const pf_tq_socket_pair_v2 *pair,
    pf_tq_socket_endpoint_role_v2 role,
    char *error,
    size_t error_size
);

/*
 * After the opposite endpoint is closed and immediately before the role's
 * exec, clear FD_CLOEXEC exactly once on the retained endpoint and return its
 * independently recaptured identity.
 */
int pf_tq_socket_endpoint_prepare_exec_v2(
    const pf_tq_socket_pair_v2 *pair,
    pf_tq_socket_endpoint_role_v2 role,
    pf_tq_transition_fd_identity_v2 *identity,
    char *error,
    size_t error_size
);

/* Validate one unnamed endpoint's exact identity, socket properties and state. */
int pf_tq_socket_endpoint_validate_v2(
    int fd,
    const pf_tq_transition_fd_identity_v2 *expected,
    int pass_credentials,
    char *error,
    size_t error_size
);

/* Service-start one-time transition from SO_PASSCRED=0 to exact value 1. */
int pf_tq_socket_service_enable_credentials_v2(
    int fd,
    const pf_tq_transition_fd_identity_v2 *expected,
    char *error,
    size_t error_size
);

/*
 * Join direct post-exec observations to the two identities captured from the
 * unique creation call.  Both observed endpoints must have fd_flags=0 and may
 * then be copied into the sealed custody transition record.
 */
int pf_tq_socket_lineage_validate_v2(
    const pf_tq_socket_pair_v2 *pair,
    const pf_tq_transition_fd_identity_v2 *adapter_observed,
    const pf_tq_transition_fd_identity_v2 *service_observed,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
