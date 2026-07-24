#define _GNU_SOURCE
#include "task_qualification_socket_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define PF_TQ_SOCKET_V2_MAX_SAFE UINT64_C(9007199254740991)

static int pf_tq_socket_error(
    char *error,
    size_t error_size,
    const char *format,
    ...
) {
    if (error != NULL && error_size > 0U) {
        va_list arguments;
        va_start(arguments, format);
        (void)vsnprintf(error, error_size, format, arguments);
        va_end(arguments);
        error[error_size - 1U] = '\0';
    }
    return -1;
}

static void pf_tq_socket_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static void pf_tq_socket_pair_initialize(pf_tq_socket_pair_v2 *pair) {
    if (pair == NULL) return;
    memset(pair, 0, sizeof(*pair));
    pair->adapter_fd = -1;
    pair->service_fd = -1;
    pair->adapter_created.fd = -1;
    pair->service_created.fd = -1;
}

static int pf_tq_socket_capture(
    int fd,
    pf_tq_transition_fd_identity_v2 *identity,
    char *error,
    size_t error_size
) {
    struct stat status;
    int flags;
    if (identity != NULL) {
        memset(identity, 0, sizeof(*identity));
        identity->fd = -1;
    }
    if (fd < 0 || identity == NULL || fstat(fd, &status) != 0 ||
            (flags = fcntl(fd, F_GETFD)) < 0) {
        return pf_tq_socket_error(error, error_size,
            "socket endpoint identity capture failed: %s", strerror(errno));
    }
    if ((uint64_t)status.st_dev > PF_TQ_SOCKET_V2_MAX_SAFE ||
            (uint64_t)status.st_ino > PF_TQ_SOCKET_V2_MAX_SAFE ||
            (flags != 0 && flags != FD_CLOEXEC)) {
        return pf_tq_socket_error(error, error_size,
            "socket endpoint identity exceeds the closed wire domain");
    }
    identity->fd = fd;
    identity->device = (uint64_t)status.st_dev;
    identity->inode = (uint64_t)status.st_ino;
    identity->mode = (uint64_t)status.st_mode;
    identity->fd_flags = flags;
    return 0;
}

static int pf_tq_socket_identity_equal(
    const pf_tq_transition_fd_identity_v2 *left,
    const pf_tq_transition_fd_identity_v2 *right
) {
    return left != NULL && right != NULL && left->fd == right->fd &&
        left->device == right->device && left->inode == right->inode &&
        left->mode == right->mode && left->fd_flags == right->fd_flags;
}

static int pf_tq_socket_identity_matches_created(
    const pf_tq_transition_fd_identity_v2 *created,
    const pf_tq_transition_fd_identity_v2 *observed
) {
    return created != NULL && observed != NULL &&
        created->fd == observed->fd && created->device == observed->device &&
        created->inode == observed->inode && created->mode == observed->mode &&
        created->fd_flags == FD_CLOEXEC && observed->fd_flags == 0;
}

static int pf_tq_socket_get_int(
    int fd,
    int option,
    int *value,
    char *error,
    size_t error_size
) {
    socklen_t size = sizeof(*value);
    *value = 0;
    if (getsockopt(fd, SOL_SOCKET, option, value, &size) != 0 ||
            size != sizeof(*value)) {
        return pf_tq_socket_error(error, error_size,
            "socket getsockopt(%d) failed: %s", option, strerror(errno));
    }
    return 0;
}

static int pf_tq_socket_unnamed(
    int fd,
    char *error,
    size_t error_size
) {
    struct sockaddr_un local;
    struct sockaddr_un peer;
    socklen_t local_size = sizeof(local);
    socklen_t peer_size = sizeof(peer);
    memset(&local, 0, sizeof(local));
    memset(&peer, 0, sizeof(peer));
    if (getsockname(fd, (struct sockaddr *)(void *)&local,
            &local_size) != 0 ||
            getpeername(fd, (struct sockaddr *)(void *)&peer,
                &peer_size) != 0 ||
            local.sun_family != AF_UNIX || peer.sun_family != AF_UNIX ||
            local_size != offsetof(struct sockaddr_un, sun_path) ||
            peer_size != offsetof(struct sockaddr_un, sun_path)) {
        return pf_tq_socket_error(error, error_size,
            "socket endpoint is not an unnamed connected AF_UNIX pair");
    }
    return 0;
}

static int pf_tq_socket_validate_internal(
    int fd,
    const pf_tq_transition_fd_identity_v2 *expected,
    int pass_credentials,
    int *send_buffer_output,
    int *receive_buffer_output,
    char *error,
    size_t error_size
) {
    pf_tq_transition_fd_identity_v2 observed;
    int domain;
    int type;
    int protocol;
    int accept_connections;
    int send_buffer;
    int receive_buffer;
    int credentials;
    int pending_error;
    int status_flags;
    if (fd < 0 || expected == NULL || expected->fd != fd ||
            (expected->fd_flags != 0 && expected->fd_flags != FD_CLOEXEC) ||
            (pass_credentials != 0 && pass_credentials != 1) ||
            pf_tq_socket_capture(fd, &observed, error, error_size) != 0 ||
            !pf_tq_socket_identity_equal(&observed, expected) ||
            (observed.mode & S_IFMT) != S_IFSOCK) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "socket endpoint identity mismatch");
        }
        return -1;
    }
    status_flags = fcntl(fd, F_GETFL);
    if (status_flags < 0 || (status_flags & (O_NONBLOCK | O_ASYNC)) != 0 ||
            pf_tq_socket_get_int(fd, SO_DOMAIN, &domain,
                error, error_size) != 0 || domain != AF_UNIX ||
            pf_tq_socket_get_int(fd, SO_TYPE, &type,
                error, error_size) != 0 || type != SOCK_SEQPACKET ||
            pf_tq_socket_get_int(fd, SO_PROTOCOL, &protocol,
                error, error_size) != 0 || protocol != 0 ||
            pf_tq_socket_get_int(fd, SO_ACCEPTCONN, &accept_connections,
                error, error_size) != 0 || accept_connections != 0 ||
            pf_tq_socket_get_int(fd, SO_SNDBUF, &send_buffer,
                error, error_size) != 0 ||
            send_buffer < PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES ||
            pf_tq_socket_get_int(fd, SO_RCVBUF, &receive_buffer,
                error, error_size) != 0 ||
            receive_buffer < PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES ||
            pf_tq_socket_get_int(fd, SO_PASSCRED, &credentials,
                error, error_size) != 0 || credentials != pass_credentials ||
            pf_tq_socket_get_int(fd, SO_ERROR, &pending_error,
                error, error_size) != 0 || pending_error != 0 ||
            pf_tq_socket_unnamed(fd, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "socket endpoint properties rejected");
        }
        return -1;
    }
    if (send_buffer_output != NULL) *send_buffer_output = send_buffer;
    if (receive_buffer_output != NULL) *receive_buffer_output = receive_buffer;
    return 0;
}

int pf_tq_socket_endpoint_validate_v2(
    int fd,
    const pf_tq_transition_fd_identity_v2 *expected,
    int pass_credentials,
    char *error,
    size_t error_size
) {
    pf_tq_socket_clear_error(error, error_size);
    return pf_tq_socket_validate_internal(fd, expected, pass_credentials,
        NULL, NULL, error, error_size);
}

static int pf_tq_socket_pair_shape(
    const pf_tq_socket_pair_v2 *pair,
    char *error,
    size_t error_size
) {
    if (pair == NULL || pair->adapter_fd <= 2 || pair->service_fd <= 2 ||
            pair->adapter_fd == pair->service_fd ||
            pair->adapter_created.fd != pair->adapter_fd ||
            pair->service_created.fd != pair->service_fd ||
            pair->adapter_created.fd_flags != FD_CLOEXEC ||
            pair->service_created.fd_flags != FD_CLOEXEC ||
            (pair->adapter_created.mode & S_IFMT) != S_IFSOCK ||
            (pair->service_created.mode & S_IFMT) != S_IFSOCK ||
            (pair->adapter_created.device == pair->service_created.device &&
             pair->adapter_created.inode == pair->service_created.inode) ||
            pair->adapter_send_buffer <
                PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES ||
            pair->adapter_receive_buffer <
                PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES ||
            pair->service_send_buffer <
                PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES ||
            pair->service_receive_buffer <
                PF_TQ_SOCKET_V2_MINIMUM_EFFECTIVE_BUFFER_BYTES) {
        return pf_tq_socket_error(error, error_size,
            "socket pair captured shape rejected");
    }
    return 0;
}

static int pf_tq_socket_fd_unused(int fd) {
    int result;
    errno = 0;
    result = fcntl(fd, F_GETFD);
    return result == -1 && errno == EBADF;
}

int pf_tq_socket_pair_create_v2(
    const pf_tq_isolation_policy_v2 *policy,
    const pf_tq_handoff_channels_v2 *channels,
    pf_tq_socket_pair_v2 *result,
    char *error,
    size_t error_size
) {
    pf_tq_socket_pair_v2 pair;
    int endpoints[2] = {-1, -1};
    int adapter_fd = -1;
    int service_fd = -1;
    int close_on_exec = -1;
    int requested = PF_TQ_SOCKET_V2_REQUESTED_BUFFER_BYTES;
    int accepted = -1;
    pf_tq_socket_clear_error(error, error_size);
    pf_tq_socket_pair_initialize(result);
    pf_tq_socket_pair_initialize(&pair);
    if (policy == NULL || channels == NULL || result == NULL ||
            pf_tq_fd_manifest_validate_policy_v2(
                policy, channels, error, error_size) != 0 ||
            pf_tq_fd_manifest_lookup_v2(policy, "adapter", "steady",
                "authority-store", &adapter_fd, &close_on_exec,
                error, error_size) != 0 || close_on_exec != 0 ||
            pf_tq_fd_manifest_lookup_v2(policy, "service", "pre-exec",
                "service-endpoint", &service_fd, &close_on_exec,
                error, error_size) != 0 || close_on_exec != 0 ||
            adapter_fd <= 2 || service_fd <= 2 || adapter_fd == service_fd) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "socket pair policy/manifest arguments rejected");
        }
        goto cleanup;
    }
    if (!pf_tq_socket_fd_unused(adapter_fd) ||
            !pf_tq_socket_fd_unused(service_fd)) {
        (void)pf_tq_socket_error(error, error_size,
            "policy-fixed socket endpoint FD is already occupied");
        goto cleanup;
    }
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC,
            0, endpoints) != 0) {
        (void)pf_tq_socket_error(error, error_size,
            "unique socketpair creation failed: %s", strerror(errno));
        goto cleanup;
    }
    if (endpoints[0] != adapter_fd || endpoints[1] != service_fd) {
        (void)pf_tq_socket_error(error, error_size,
            "socketpair did not directly return both policy-fixed FDs");
        goto cleanup;
    }
    if (setsockopt(endpoints[0], SOL_SOCKET, SO_SNDBUF,
            &requested, sizeof(requested)) != 0 ||
            setsockopt(endpoints[0], SOL_SOCKET, SO_RCVBUF,
                &requested, sizeof(requested)) != 0 ||
            setsockopt(endpoints[1], SOL_SOCKET, SO_SNDBUF,
                &requested, sizeof(requested)) != 0 ||
            setsockopt(endpoints[1], SOL_SOCKET, SO_RCVBUF,
                &requested, sizeof(requested)) != 0) {
        (void)pf_tq_socket_error(error, error_size,
            "socket buffer setup failed: %s", strerror(errno));
        goto cleanup;
    }
    pair.adapter_fd = adapter_fd;
    pair.service_fd = service_fd;
    if (pf_tq_socket_capture(adapter_fd, &pair.adapter_created,
            error, error_size) != 0 ||
            pf_tq_socket_capture(service_fd, &pair.service_created,
                error, error_size) != 0 ||
            pf_tq_socket_validate_internal(adapter_fd, &pair.adapter_created, 0,
                &pair.adapter_send_buffer, &pair.adapter_receive_buffer,
                error, error_size) != 0 ||
            pf_tq_socket_validate_internal(service_fd, &pair.service_created, 0,
                &pair.service_send_buffer, &pair.service_receive_buffer,
                error, error_size) != 0 ||
            pf_tq_socket_pair_shape(&pair, error, error_size) != 0) {
        goto cleanup;
    }
    *result = pair;
    accepted = 0;
cleanup:
    if (accepted != 0) {
        if (endpoints[0] >= 0) (void)close(endpoints[0]);
        if (endpoints[1] >= 0) (void)close(endpoints[1]);
        pf_tq_socket_pair_initialize(result);
        return -1;
    }
    return 0;
}

static int pf_tq_socket_role_fds(
    const pf_tq_socket_pair_v2 *pair,
    pf_tq_socket_endpoint_role_v2 role,
    int *retained_fd,
    int *opposite_fd,
    const pf_tq_transition_fd_identity_v2 **retained_created,
    const pf_tq_transition_fd_identity_v2 **opposite_created,
    char *error,
    size_t error_size
) {
    if (pf_tq_socket_pair_shape(pair, error, error_size) != 0) return -1;
    if (role == PF_TQ_SOCKET_ADAPTER_V2) {
        *retained_fd = pair->adapter_fd;
        *opposite_fd = pair->service_fd;
        *retained_created = &pair->adapter_created;
        *opposite_created = &pair->service_created;
        return 0;
    }
    if (role == PF_TQ_SOCKET_SERVICE_V2) {
        *retained_fd = pair->service_fd;
        *opposite_fd = pair->adapter_fd;
        *retained_created = &pair->service_created;
        *opposite_created = &pair->adapter_created;
        return 0;
    }
    return pf_tq_socket_error(error, error_size,
        "socket endpoint role rejected");
}

int pf_tq_socket_pair_select_v2(
    const pf_tq_socket_pair_v2 *pair,
    pf_tq_socket_endpoint_role_v2 role,
    char *error,
    size_t error_size
) {
    int retained_fd = -1;
    int opposite_fd = -1;
    const pf_tq_transition_fd_identity_v2 *retained_created = NULL;
    const pf_tq_transition_fd_identity_v2 *opposite_created = NULL;
    pf_tq_socket_clear_error(error, error_size);
    if (pf_tq_socket_role_fds(pair, role, &retained_fd, &opposite_fd,
            &retained_created, &opposite_created,
            error, error_size) != 0 ||
            pf_tq_socket_validate_internal(retained_fd, retained_created, 0,
                NULL, NULL, error, error_size) != 0 ||
            pf_tq_socket_validate_internal(opposite_fd, opposite_created, 0,
                NULL, NULL, error, error_size) != 0) return -1;
    if (close(opposite_fd) != 0) {
        return pf_tq_socket_error(error, error_size,
            "opposite socket endpoint close failed: %s", strerror(errno));
    }
    if (!pf_tq_socket_fd_unused(opposite_fd) ||
            pf_tq_socket_validate_internal(retained_fd, retained_created, 0,
                NULL, NULL, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "socket endpoint selection postcondition rejected");
        }
        return -1;
    }
    return 0;
}

int pf_tq_socket_endpoint_prepare_exec_v2(
    const pf_tq_socket_pair_v2 *pair,
    pf_tq_socket_endpoint_role_v2 role,
    pf_tq_transition_fd_identity_v2 *identity,
    char *error,
    size_t error_size
) {
    int retained_fd = -1;
    int opposite_fd = -1;
    const pf_tq_transition_fd_identity_v2 *retained_created = NULL;
    const pf_tq_transition_fd_identity_v2 *opposite_created = NULL;
    pf_tq_transition_fd_identity_v2 expected;
    pf_tq_socket_clear_error(error, error_size);
    if (identity != NULL) {
        memset(identity, 0, sizeof(*identity));
        identity->fd = -1;
    }
    if (identity == NULL || pf_tq_socket_role_fds(pair, role,
            &retained_fd, &opposite_fd, &retained_created, &opposite_created,
            error, error_size) != 0 || !pf_tq_socket_fd_unused(opposite_fd) ||
            pf_tq_socket_validate_internal(retained_fd, retained_created, 0,
                NULL, NULL, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "socket exec preparation ordering rejected");
        }
        return -1;
    }
    expected = *retained_created;
    expected.fd_flags = 0;
    if (fcntl(retained_fd, F_SETFD, 0) != 0 ||
            pf_tq_socket_capture(retained_fd, identity,
                error, error_size) != 0 ||
            !pf_tq_socket_identity_equal(identity, &expected) ||
            pf_tq_socket_validate_internal(retained_fd, identity, 0,
                NULL, NULL, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "retained socket endpoint exec transition rejected");
        }
        return -1;
    }
    return 0;
}

int pf_tq_socket_service_enable_credentials_v2(
    int fd,
    const pf_tq_transition_fd_identity_v2 *expected,
    char *error,
    size_t error_size
) {
    int enabled = 1;
    pf_tq_socket_clear_error(error, error_size);
    if (expected == NULL || expected->fd_flags != 0 ||
            pf_tq_socket_validate_internal(fd, expected, 0,
                NULL, NULL, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "service socket pre-credential state rejected");
        }
        return -1;
    }
    if (setsockopt(fd, SOL_SOCKET, SO_PASSCRED,
            &enabled, sizeof(enabled)) != 0 ||
            pf_tq_socket_validate_internal(fd, expected, 1,
                NULL, NULL, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "service SO_PASSCRED transition failed");
        }
        return -1;
    }
    return 0;
}

int pf_tq_socket_lineage_validate_v2(
    const pf_tq_socket_pair_v2 *pair,
    const pf_tq_transition_fd_identity_v2 *adapter_observed,
    const pf_tq_transition_fd_identity_v2 *service_observed,
    char *error,
    size_t error_size
) {
    pf_tq_socket_clear_error(error, error_size);
    if (pf_tq_socket_pair_shape(pair, error, error_size) != 0 ||
            !pf_tq_socket_identity_matches_created(
                &pair->adapter_created, adapter_observed) ||
            !pf_tq_socket_identity_matches_created(
                &pair->service_created, service_observed) ||
            adapter_observed->fd == service_observed->fd ||
            (adapter_observed->device == service_observed->device &&
             adapter_observed->inode == service_observed->inode)) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_socket_error(error, error_size,
                "post-exec socket endpoint lineage rejected");
        }
        return -1;
    }
    return 0;
}
