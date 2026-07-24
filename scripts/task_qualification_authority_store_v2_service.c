#define _GNU_SOURCE
#include "task_qualification_authority_store_v2_service.h"
#include "task_qualification_pf_jcs_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <poll.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

#define PF_TQ_STORE_PROTOCOL "pf.taskqual.authority-store.rpc.v2"
#define PF_TQ_STORE_NAMESPACE "task-qualification-production-v1"
#define PF_TQ_STORE_VERSION "2.0.0"

#define PF_TQ_CLIENT_HELLO_SCHEMA \
    "proof-forge.task-qualification-store-client-hello.v2"
#define PF_TQ_SERVER_HELLO_SCHEMA \
    "proof-forge.task-qualification-store-server-hello.v2"
#define PF_TQ_LOOKUP_REQUEST_SCHEMA \
    "proof-forge.task-qualification-store-lookup-request.v2"
#define PF_TQ_LOOKUP_RESPONSE_SCHEMA \
    "proof-forge.task-qualification-store-lookup-response.v2"
#define PF_TQ_TERMINAL_REQUEST_SCHEMA \
    "proof-forge.task-qualification-store-acceptance-sign-request.v2"
#define PF_TQ_TERMINAL_RESPONSE_SCHEMA \
    "proof-forge.task-qualification-store-acceptance-sign-response.v2"
#define PF_TQ_ACCEPTANCE_SCHEMA \
    "proof-forge.protected-task-qualification-acceptance.v1"

#define PF_TQ_SERVER_HELLO_SIGNATURE_DOMAIN \
    "pf.taskqual.store-server-hello-signature.v2"
#define PF_TQ_LOOKUP_RESPONSE_SIGNATURE_DOMAIN \
    "pf.taskqual.store-lookup-response-signature.v2"
#define PF_TQ_TERMINAL_RESPONSE_SIGNATURE_DOMAIN \
    "pf.taskqual.store-acceptance-sign-response-signature.v2"
#define PF_TQ_TERMINAL_RESPONSE_FULL_DOMAIN \
    "pf.taskqual.store-acceptance-sign-response.v2"
#define PF_TQ_ACCEPTANCE_STATEMENT_DOMAIN \
    "pf.taskqual.protected-acceptance-statement.v1"
#define PF_TQ_ACCEPTANCE_SIGNATURE_DOMAIN \
    "pf.taskqual.protected-acceptance-signature.v1"
#define PF_TQ_ACCEPTANCE_FULL_DOMAIN \
    "pf.taskqual.protected-acceptance.v1"

#define PF_TQ_MINIMUM_EFFECTIVE_SOCKET_BUFFER 8388608
#define PF_TQ_DIGEST_WIRE_BYTES 71U
#define PF_TQ_SIGNATURE_HEX_BYTES 128U
#define PF_TQ_SCALAR_BYTES 512U

struct pf_tq_scalar {
    unsigned char bytes[PF_TQ_SCALAR_BYTES];
    size_t size;
};

struct pf_tq_peer_state {
    pid_t pid;
    uid_t uid;
    gid_t gid;
    int pidfd;
    int initialized;
};

struct pf_tq_object_projection {
    unsigned char *ref;
    size_t ref_size;
    char digest_wire[PF_TQ_DIGEST_WIRE_BYTES + 1U];
};

static int pf_tq_store_error(
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

static void pf_tq_store_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static bool pf_tq_ascii_nonempty(const char *value, size_t maximum) {
    size_t index;
    size_t size = value == NULL ? 0U : strlen(value);
    if (size == 0U || size > maximum) return false;
    for (index = 0U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (character < 0x20U || character > 0x7eU) return false;
    }
    return true;
}

static bool pf_tq_is_lower_hex(const char *value, size_t size) {
    size_t index;
    if (value == NULL || strlen(value) != size) return false;
    for (index = 0U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!((character >= '0' && character <= '9') ||
                (character >= 'a' && character <= 'f'))) return false;
    }
    return true;
}

static bool pf_tq_is_digest_wire(const char *value) {
    return value != NULL && strncmp(value, "sha256:", 7U) == 0 &&
        pf_tq_is_lower_hex(value + 7U, 64U);
}

static bool pf_tq_is_operation(const char *value) {
    static const char *const operations[] = {
        "task-qualification", "task-completion",
        "d0-10-bootstrap-approval", "d0-10-bootstrap-receipt"
    };
    size_t index;
    if (value == NULL) return false;
    for (index = 0U; index < sizeof(operations) / sizeof(operations[0]); ++index) {
        if (strcmp(value, operations[index]) == 0) return true;
    }
    return false;
}

static void pf_tq_hex(
    const unsigned char *bytes,
    size_t size,
    char *output
) {
    static const char alphabet[] = "0123456789abcdef";
    size_t index;
    for (index = 0U; index < size; ++index) {
        output[2U * index] = alphabet[bytes[index] >> 4U];
        output[2U * index + 1U] = alphabet[bytes[index] & 15U];
    }
    output[2U * size] = '\0';
}

static int pf_tq_sha256(
    const unsigned char *first,
    size_t first_size,
    const unsigned char *second,
    size_t second_size,
    const unsigned char *third,
    size_t third_size,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    EVP_MD_CTX *digest = EVP_MD_CTX_new();
    unsigned int output_size = 0U;
    if (digest == NULL || EVP_DigestInit_ex(digest, EVP_sha256(), NULL) != 1 ||
            (first_size > 0U && EVP_DigestUpdate(digest, first, first_size) != 1) ||
            (second_size > 0U && EVP_DigestUpdate(digest, second, second_size) != 1) ||
            (third_size > 0U && EVP_DigestUpdate(digest, third, third_size) != 1) ||
            EVP_DigestFinal_ex(digest, output, &output_size) != 1 ||
            output_size != 32U) {
        EVP_MD_CTX_free(digest);
        return pf_tq_store_error(error, error_size, "SHA-256 operation failed");
    }
    EVP_MD_CTX_free(digest);
    return 0;
}

static int pf_tq_domain_digest(
    const char *domain,
    const unsigned char *bytes,
    size_t size,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    static const unsigned char zero = 0U;
    return pf_tq_sha256((const unsigned char *)domain, strlen(domain),
        &zero, 1U, bytes, size, output, error, error_size);
}

static void pf_tq_digest_wire(
    const unsigned char digest[32],
    char output[PF_TQ_DIGEST_WIRE_BYTES + 1U]
) {
    memcpy(output, "sha256:", 7U);
    pf_tq_hex(digest, 32U, output + 7U);
}

static int pf_tq_ed25519_public(
    const unsigned char seed[32],
    unsigned char public_key[32],
    char *error,
    size_t error_size
) {
    EVP_PKEY *key = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_ED25519, NULL, seed, 32U);
    size_t size = 32U;
    if (key == NULL || EVP_PKEY_get_raw_public_key(key, public_key, &size) != 1 ||
            size != 32U) {
        EVP_PKEY_free(key);
        return pf_tq_store_error(error, error_size,
            "Ed25519 public-key derivation failed");
    }
    EVP_PKEY_free(key);
    return 0;
}

static int pf_tq_ed25519_sign(
    const unsigned char seed[32],
    const unsigned char *message,
    size_t message_size,
    unsigned char signature[64],
    char *error,
    size_t error_size
) {
    EVP_PKEY *key = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_ED25519, NULL, seed, 32U);
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    size_t signature_size = 64U;
    if (key == NULL || context == NULL ||
            EVP_DigestSignInit(context, NULL, NULL, NULL, key) != 1 ||
            EVP_DigestSign(context, signature, &signature_size,
                message, message_size) != 1 || signature_size != 64U) {
        EVP_MD_CTX_free(context);
        EVP_PKEY_free(key);
        OPENSSL_cleanse(signature, 64U);
        return pf_tq_store_error(error, error_size, "Ed25519 signing failed");
    }
    EVP_MD_CTX_free(context);
    EVP_PKEY_free(key);
    return 0;
}

static int pf_tq_scalar_string(
    struct pf_tq_scalar *scalar,
    const char *value,
    char *error,
    size_t error_size
) {
    return pf_tq_jcs_encode_string_v2(value, scalar->bytes,
        sizeof(scalar->bytes), &scalar->size, error, error_size);
}

static int pf_tq_scalar_uint(
    struct pf_tq_scalar *scalar,
    uint64_t value,
    char *error,
    size_t error_size
) {
    return pf_tq_jcs_encode_uint_v2(value, scalar->bytes,
        sizeof(scalar->bytes), &scalar->size, error, error_size);
}

static int pf_tq_field_compare(const void *left, const void *right) {
    const pf_tq_jcs_field_v2 *a = left;
    const pf_tq_jcs_field_v2 *b = right;
    return strcmp(a->key, b->key);
}

static int pf_tq_raw_compare(
    const unsigned char *left,
    size_t left_size,
    const unsigned char *right,
    size_t right_size
) {
    size_t shared = left_size < right_size ? left_size : right_size;
    int comparison = memcmp(left, right, shared);
    if (comparison != 0) return comparison;
    if (left_size < right_size) return -1;
    if (left_size > right_size) return 1;
    return 0;
}

static int pf_tq_encode_fields_alloc(
    const pf_tq_jcs_field_v2 *fields,
    size_t field_count,
    unsigned char **output,
    size_t *output_size,
    size_t maximum,
    char *error,
    size_t error_size
) {
    pf_tq_jcs_field_v2 *sorted;
    unsigned char *buffer;
    size_t written = 0U;
    if (fields == NULL || field_count == 0U || output == NULL ||
            output_size == NULL || maximum == 0U) {
        return pf_tq_store_error(error, error_size,
            "object field encoder arguments rejected");
    }
    sorted = malloc(field_count * sizeof(*sorted));
    buffer = malloc(maximum);
    if (sorted == NULL || buffer == NULL) {
        free(sorted);
        free(buffer);
        return pf_tq_store_error(error, error_size,
            "object field encoder allocation failed");
    }
    memcpy(sorted, fields, field_count * sizeof(*sorted));
    qsort(sorted, field_count, sizeof(*sorted), pf_tq_field_compare);
    if (pf_tq_jcs_encode_object_v2(sorted, field_count, buffer, maximum,
            &written, error, error_size) != 0) {
        free(sorted);
        free(buffer);
        return -1;
    }
    free(sorted);
    *output = buffer;
    *output_size = written;
    return 0;
}

static int pf_tq_build_signed_object(
    const pf_tq_jcs_field_v2 *unsigned_fields,
    size_t unsigned_count,
    const char *signature_domain,
    const unsigned char seed[32],
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    unsigned char *unsigned_bytes = NULL;
    size_t unsigned_size = 0U;
    unsigned char *message = NULL;
    size_t message_size;
    unsigned char signature[64];
    char signature_hex[PF_TQ_SIGNATURE_HEX_BYTES + 1U];
    struct pf_tq_scalar signature_value;
    pf_tq_jcs_field_v2 *signed_fields = NULL;
    int result = -1;
    if (pf_tq_encode_fields_alloc(unsigned_fields, unsigned_count,
            &unsigned_bytes, &unsigned_size, PF_TQ_STORE_V2_MAX_FRAME_BYTES,
            error, error_size) != 0) goto cleanup;
    message_size = strlen(signature_domain) + 1U + unsigned_size;
    message = malloc(message_size);
    signed_fields = malloc((unsigned_count + 1U) * sizeof(*signed_fields));
    if (message == NULL || signed_fields == NULL) {
        (void)pf_tq_store_error(error, error_size,
            "signed frame allocation failed");
        goto cleanup;
    }
    memcpy(message, signature_domain, strlen(signature_domain));
    message[strlen(signature_domain)] = 0U;
    memcpy(message + strlen(signature_domain) + 1U,
        unsigned_bytes, unsigned_size);
    if (pf_tq_ed25519_sign(seed, message, message_size, signature,
            error, error_size) != 0) goto cleanup;
    pf_tq_hex(signature, sizeof(signature), signature_hex);
    if (pf_tq_scalar_string(&signature_value, signature_hex,
            error, error_size) != 0) goto cleanup;
    memcpy(signed_fields, unsigned_fields,
        unsigned_count * sizeof(*signed_fields));
    signed_fields[unsigned_count].key = "signature";
    signed_fields[unsigned_count].value = signature_value.bytes;
    signed_fields[unsigned_count].value_size = signature_value.size;
    if (pf_tq_encode_fields_alloc(signed_fields, unsigned_count + 1U,
            output, output_size, PF_TQ_STORE_V2_MAX_FRAME_BYTES,
            error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    OPENSSL_cleanse(signature, sizeof(signature));
    free(signed_fields);
    free(message);
    free(unsigned_bytes);
    return result;
}

static int pf_tq_build_placeholder_signed_object(
    const pf_tq_jcs_field_v2 *unsigned_fields,
    size_t unsigned_count,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    static const char zero_signature[PF_TQ_SIGNATURE_HEX_BYTES + 1U] =
        "0000000000000000000000000000000000000000000000000000000000000000"
        "0000000000000000000000000000000000000000000000000000000000000000";
    struct pf_tq_scalar signature_value;
    pf_tq_jcs_field_v2 *fields = malloc(
        (unsigned_count + 1U) * sizeof(*fields));
    int result;
    if (fields == NULL || pf_tq_scalar_string(&signature_value, zero_signature,
            error, error_size) != 0) {
        free(fields);
        return pf_tq_store_error(error, error_size,
            "placeholder signature construction failed");
    }
    memcpy(fields, unsigned_fields, unsigned_count * sizeof(*fields));
    fields[unsigned_count].key = "signature";
    fields[unsigned_count].value = signature_value.bytes;
    fields[unsigned_count].value_size = signature_value.size;
    result = pf_tq_encode_fields_alloc(fields, unsigned_count + 1U,
        output, output_size, PF_TQ_STORE_V2_MAX_FRAME_BYTES,
        error, error_size);
    free(fields);
    return result;
}

static int pf_tq_node_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    const char *expected,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_jcs_object_get_v2(document, object, field);
    if (!pf_tq_jcs_string_equal_v2(document, node, expected)) {
        return pf_tq_store_error(error, error_size,
            "frame field %s does not match", field);
    }
    return 0;
}

static int pf_tq_node_uint(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    uint64_t expected,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_jcs_object_get_v2(document, object, field);
    if (node == NULL || node->type != PF_TQ_JCS_UINT || node->uint_value != expected) {
        return pf_tq_store_error(error, error_size,
            "frame field %s integer does not match", field);
    }
    return 0;
}

static int pf_tq_node_raw(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    pf_tq_store_v2_bytes expected,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_jcs_object_get_v2(document, object, field);
    if (!pf_tq_jcs_raw_equal_v2(document, node, expected.bytes, expected.size)) {
        return pf_tq_store_error(error, error_size,
            "frame field %s raw value does not match", field);
    }
    return 0;
}

static int pf_tq_node_digest(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    const unsigned char expected[32],
    char *error,
    size_t error_size
) {
    char wire[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    pf_tq_digest_wire(expected, wire);
    return pf_tq_node_string(document, object, field, wire, error, error_size);
}

static int pf_tq_validate_echo(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *root,
    const pf_tq_store_v2_context *context,
    int include_handoff_digest,
    char *error,
    size_t error_size
) {
    if (pf_tq_node_string(document, root, "taskId", context->task_id,
            error, error_size) != 0 ||
            pf_tq_node_string(document, root, "operation", context->operation,
                error, error_size) != 0 ||
            pf_tq_node_string(document, root, "runId", context->run_id,
                error, error_size) != 0 ||
            pf_tq_node_string(document, root, "nonce", context->nonce,
                error, error_size) != 0 ||
            pf_tq_node_raw(document, root, "service", context->service_ref,
                error, error_size) != 0 ||
            pf_tq_node_uint(document, root, "headSequence", context->head_sequence,
                error, error_size) != 0 ||
            pf_tq_node_digest(document, root, "headDigest", context->head_digest,
                error, error_size) != 0) return -1;
    if (include_handoff_digest && pf_tq_node_digest(document, root,
            "handoffDigest", context->handoff_digest, error, error_size) != 0) {
        return -1;
    }
    return 0;
}

static int pf_tq_pidfd_alive(
    const struct pf_tq_peer_state *peer,
    char *error,
    size_t error_size
) {
    struct pollfd descriptor;
    int result;
    if (peer->pidfd < 0) return 0;
    descriptor.fd = peer->pidfd;
    descriptor.events = POLLIN | POLLHUP | POLLERR;
    descriptor.revents = 0;
    result = poll(&descriptor, 1U, 0);
    if (result < 0) {
        return pf_tq_store_error(error, error_size,
            "pidfd liveness poll failed: %s", strerror(errno));
    }
    if (result != 0 || descriptor.revents != 0) {
        return pf_tq_store_error(error, error_size, "adapter pidfd is not alive");
    }
    return 0;
}

static int pf_tq_peer_observe(
    pf_tq_store_v2_context *context,
    struct pf_tq_peer_state *peer,
    const struct ucred *credentials,
    unsigned checkpoint,
    char *error,
    size_t error_size
) {
    if (credentials->pid <= 0 || credentials->pid == getpid() ||
            credentials->uid != context->adapter_uid ||
            credentials->gid != context->adapter_gid) {
        return pf_tq_store_error(error, error_size,
            "SCM_CREDENTIALS peer identity rejected pid=%ld/self=%ld uid=%lu/%lu gid=%lu/%lu",
            (long)credentials->pid, (long)getpid(),
            (unsigned long)credentials->uid, (unsigned long)context->adapter_uid,
            (unsigned long)credentials->gid, (unsigned long)context->adapter_gid);
    }
    if (!peer->initialized) {
        peer->pid = credentials->pid;
        peer->uid = credentials->uid;
        peer->gid = credentials->gid;
        peer->pidfd = -1;
        if (context->require_pidfd) {
            peer->pidfd = (int)syscall(SYS_pidfd_open, credentials->pid, 0U);
            if (peer->pidfd < 0) {
                return pf_tq_store_error(error, error_size,
                    "pidfd_open failed: %s", strerror(errno));
            }
        }
        peer->initialized = 1;
    } else if (peer->pid != credentials->pid || peer->uid != credentials->uid ||
            peer->gid != credentials->gid) {
        return pf_tq_store_error(error, error_size,
            "SCM_CREDENTIALS changed within session");
    }
    if (pf_tq_pidfd_alive(peer, error, error_size) != 0) return -1;
    if (context->peer_check != NULL && context->peer_check(
            context->peer_check_opaque, peer->pid, checkpoint,
            error, error_size) != 0) return -1;
    return pf_tq_pidfd_alive(peer, error, error_size);
}

static int pf_tq_peer_checkpoint(
    pf_tq_store_v2_context *context,
    struct pf_tq_peer_state *peer,
    unsigned checkpoint,
    char *error,
    size_t error_size
) {
    if (!peer->initialized || pf_tq_pidfd_alive(peer, error, error_size) != 0) {
        return pf_tq_store_error(error, error_size,
            "terminal peer checkpoint lacks an alive authenticated peer");
    }
    if (context->peer_check != NULL && context->peer_check(
            context->peer_check_opaque, peer->pid, checkpoint,
            error, error_size) != 0) return -1;
    return pf_tq_pidfd_alive(peer, error, error_size);
}

static int pf_tq_receive_frame(
    int socket_fd,
    pf_tq_store_v2_context *context,
    struct pf_tq_peer_state *peer,
    unsigned checkpoint,
    unsigned char **payload,
    size_t *payload_size,
    char *error,
    size_t error_size
) {
    unsigned char *packet = malloc(PF_TQ_STORE_V2_MAX_PACKET_BYTES);
    unsigned char control[CMSG_SPACE(sizeof(struct ucred))];
    struct iovec iov;
    struct msghdr message;
    struct cmsghdr *header;
    struct ucred credentials;
    unsigned credential_count = 0U;
    ssize_t amount;
    uint32_t declared;
    if (packet == NULL) {
        return pf_tq_store_error(error, error_size,
            "frame receive allocation failed");
    }
    memset(&message, 0, sizeof(message));
    memset(control, 0, sizeof(control));
    iov.iov_base = packet;
    iov.iov_len = PF_TQ_STORE_V2_MAX_PACKET_BYTES;
    message.msg_iov = &iov;
    message.msg_iovlen = 1U;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);
    amount = recvmsg(socket_fd, &message, 0);
    if (amount <= 0) {
        free(packet);
        return pf_tq_store_error(error, error_size,
            "seqpacket receive failed/EOF: %s",
            amount < 0 ? strerror(errno) : "EOF");
    }
    if ((message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0 || amount < 5) {
        free(packet);
        return pf_tq_store_error(error, error_size,
            "seqpacket truncation/header rejected");
    }
    for (header = CMSG_FIRSTHDR(&message); header != NULL;
            header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level != SOL_SOCKET ||
                header->cmsg_type != SCM_CREDENTIALS ||
                header->cmsg_len != CMSG_LEN(sizeof(struct ucred))) {
            free(packet);
            return pf_tq_store_error(error, error_size,
                "unexpected seqpacket ancillary data");
        }
        if (++credential_count != 1U) {
            free(packet);
            return pf_tq_store_error(error, error_size,
                "multiple SCM_CREDENTIALS records rejected");
        }
        memcpy(&credentials, CMSG_DATA(header), sizeof(credentials));
    }
    if (context->require_kernel_credentials && credential_count != 1U) {
        free(packet);
        return pf_tq_store_error(error, error_size,
            "missing SCM_CREDENTIALS record");
    }
    if (credential_count == 1U && pf_tq_peer_observe(
            context, peer, &credentials, checkpoint, error, error_size) != 0) {
        free(packet);
        return -1;
    }
    declared = ((uint32_t)packet[0] << 24U) | ((uint32_t)packet[1] << 16U) |
        ((uint32_t)packet[2] << 8U) | (uint32_t)packet[3];
    if (declared == 0U || declared > PF_TQ_STORE_V2_MAX_FRAME_BYTES ||
            (size_t)amount != 4U + (size_t)declared) {
        free(packet);
        return pf_tq_store_error(error, error_size,
            "seqpacket u32 length mismatch/out of bounds");
    }
    memmove(packet, packet + 4U, declared);
    *payload = packet;
    *payload_size = declared;
    return 0;
}

static int pf_tq_send_frame(
    int socket_fd,
    const unsigned char *payload,
    size_t payload_size,
    char *error,
    size_t error_size
) {
    unsigned char *packet;
    ssize_t amount;
    if (payload == NULL || payload_size == 0U ||
            payload_size > PF_TQ_STORE_V2_MAX_FRAME_BYTES) {
        return pf_tq_store_error(error, error_size,
            "outbound frame payload size rejected");
    }
    packet = malloc(payload_size + 4U);
    if (packet == NULL) {
        return pf_tq_store_error(error, error_size,
            "outbound frame allocation failed");
    }
    packet[0] = (unsigned char)(payload_size >> 24U);
    packet[1] = (unsigned char)(payload_size >> 16U);
    packet[2] = (unsigned char)(payload_size >> 8U);
    packet[3] = (unsigned char)payload_size;
    memcpy(packet + 4U, payload, payload_size);
    amount = send(socket_fd, packet, payload_size + 4U, MSG_NOSIGNAL);
    free(packet);
    if (amount < 0 || (size_t)amount != payload_size + 4U) {
        return pf_tq_store_error(error, error_size,
            "seqpacket send failed/partial: %s",
            amount < 0 ? strerror(errno) : "partial");
    }
    return 0;
}

static int pf_tq_no_extra_packet(
    int socket_fd,
    char *error,
    size_t error_size
) {
    unsigned char byte;
    ssize_t amount = recv(socket_fd, &byte, 1U, MSG_PEEK | MSG_DONTWAIT);
    if (amount > 0) {
        return pf_tq_store_error(error, error_size,
            "extra terminal packet queued before signing");
    }
    if (amount == 0) {
        return pf_tq_store_error(error, error_size,
            "adapter disconnected before terminal signing");
    }
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
        return pf_tq_store_error(error, error_size,
            "terminal extra-packet check failed: %s", strerror(errno));
    }
    return 0;
}

static int pf_tq_parse_root(
    const unsigned char *bytes,
    size_t size,
    pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 **root,
    char *error,
    size_t error_size
) {
    if (pf_tq_jcs_parse_v2(bytes, size, document, error, error_size) != 0) return -1;
    *root = pf_tq_jcs_root_v2(document);
    if (*root == NULL || (*root)->type != PF_TQ_JCS_OBJECT) {
        pf_tq_jcs_free_v2(document);
        return pf_tq_store_error(error, error_size,
            "frame root must be a canonical object");
    }
    return 0;
}

static int pf_tq_validate_content_ref_bytes(
    pf_tq_store_v2_bytes bytes,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"digest", "id", "schema", "version"};
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *digest;
    char digest_text[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    int result = -1;
    if (pf_tq_parse_root(bytes.bytes, bytes.size, &document, &root,
            error, error_size) != 0) return -1;
    if (pf_tq_jcs_object_exact_v2(&document, root, fields,
            sizeof(fields) / sizeof(fields[0]), error, error_size) != 0) goto cleanup;
    digest = pf_tq_jcs_object_get_v2(&document, root, "digest");
    if (pf_tq_jcs_copy_string_v2(&document, digest, digest_text,
            sizeof(digest_text), error, error_size) != 0 ||
            !pf_tq_is_digest_wire(digest_text)) {
        (void)pf_tq_store_error(error, error_size,
            "ContentRef digest wire rejected");
        goto cleanup;
    }
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&document);
    return result;
}

static int pf_tq_object_projection(
    const pf_tq_store_v2_object *object,
    struct pf_tq_object_projection *projection,
    char *error,
    size_t error_size
) {
    static const char *const identity_fields[] = {
        "buildPolicy", "closure", "executable", "id", "sourceDigest"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *node;
    unsigned char digest[32];
    struct pf_tq_scalar digest_value;
    struct pf_tq_scalar id_value;
    struct pf_tq_scalar schema_value;
    struct pf_tq_scalar version_value;
    pf_tq_jcs_field_v2 fields[4];
    int result = -1;
    memset(projection, 0, sizeof(*projection));
    if (object == NULL || !pf_tq_ascii_nonempty(object->kind, 127U) ||
            !pf_tq_ascii_nonempty(object->schema, 127U) ||
            !pf_tq_ascii_nonempty(object->id, 127U) ||
            !pf_tq_ascii_nonempty(object->version, 127U) ||
            !pf_tq_ascii_nonempty(object->digest_domain, 127U) ||
            object->content.bytes == NULL || object->content.size == 0U ||
            object->content.size > 2000000U) {
        return pf_tq_store_error(error, error_size,
            "authority object descriptor/content rejected");
    }
    if (pf_tq_parse_root(object->content.bytes, object->content.size,
            &document, &root, error, error_size) != 0) return -1;
    node = pf_tq_jcs_object_get_v2(&document, root, "id");
    if (!pf_tq_jcs_string_equal_v2(&document, node, object->id)) {
        (void)pf_tq_store_error(error, error_size,
            "authority object id does not match descriptor");
        goto cleanup;
    }
    if (object->embedded_identity) {
        if (pf_tq_jcs_object_exact_v2(&document, root, identity_fields,
                sizeof(identity_fields) / sizeof(identity_fields[0]),
                error, error_size) != 0) goto cleanup;
    } else {
        node = pf_tq_jcs_object_get_v2(&document, root, "schema");
        if (!pf_tq_jcs_string_equal_v2(&document, node, object->schema)) {
            (void)pf_tq_store_error(error, error_size,
                "authority object schema does not match descriptor");
            goto cleanup;
        }
        node = pf_tq_jcs_object_get_v2(&document, root, "version");
        if (!pf_tq_jcs_string_equal_v2(&document, node, object->version)) {
            (void)pf_tq_store_error(error, error_size,
                "authority object version does not match descriptor");
            goto cleanup;
        }
    }
    if (pf_tq_domain_digest(object->digest_domain, object->content.bytes,
            object->content.size, digest, error, error_size) != 0) goto cleanup;
    pf_tq_digest_wire(digest, projection->digest_wire);
    if (pf_tq_scalar_string(&digest_value, projection->digest_wire,
            error, error_size) != 0 ||
            pf_tq_scalar_string(&id_value, object->id, error, error_size) != 0 ||
            pf_tq_scalar_string(&schema_value, object->schema,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&version_value, object->version,
                error, error_size) != 0) goto cleanup;
    fields[0] = (pf_tq_jcs_field_v2){"digest", digest_value.bytes, digest_value.size};
    fields[1] = (pf_tq_jcs_field_v2){"id", id_value.bytes, id_value.size};
    fields[2] = (pf_tq_jcs_field_v2){"schema", schema_value.bytes, schema_value.size};
    fields[3] = (pf_tq_jcs_field_v2){"version", version_value.bytes, version_value.size};
    if (pf_tq_encode_fields_alloc(fields, 4U, &projection->ref,
            &projection->ref_size, 1024U, error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&document);
    return result;
}

static void pf_tq_free_projection(struct pf_tq_object_projection *projection) {
    if (projection != NULL) {
        free(projection->ref);
        memset(projection, 0, sizeof(*projection));
    }
}

static int pf_tq_context_validate(
    pf_tq_store_v2_context *context,
    char *error,
    size_t error_size
) {
    static const char *const fixed_kinds[] = {
        "authority-policy", "production-profile-pin", "production-profile",
        "adapter", "snapshot-parser", "authority-store-service",
        "trusted-clock-service", "revocation-snapshot"
    };
    unsigned char derived[32];
    unsigned roles = 0U;
    size_t index;
    pf_tq_durable_snapshot_v2 snapshot;
    struct pf_tq_object_projection projection;
    if (context == NULL || !pf_tq_ascii_nonempty(context->task_id, 127U) ||
            !pf_tq_is_operation(context->operation) ||
            !pf_tq_ascii_nonempty(context->run_id, 127U) ||
            !pf_tq_ascii_nonempty(context->nonce, 127U) ||
            !pf_tq_ascii_nonempty(context->trusted_instant, 20U) ||
            !pf_tq_is_digest_wire(context->production_profile_digest) ||
            context->head_sequence > UINT64_C(9007199254740991) ||
            context->object_count < 8U ||
            context->object_count > PF_TQ_STORE_V2_MAX_OBJECTS ||
            context->objects == NULL || context->durable_root_fd < 0 ||
            context->require_kernel_credentials != 1 ||
            context->require_pidfd != 1 || context->peer_check == NULL ||
            context->current_head == NULL || context->terminal_lockdown == NULL) {
        return pf_tq_store_error(error, error_size,
            "authority-store service context shape rejected");
    }
    if (pf_tq_validate_content_ref_bytes(context->service_ref,
            error, error_size) != 0 ||
            pf_tq_validate_content_ref_bytes(context->production_profile_pin_ref,
                error, error_size) != 0) return -1;
    for (index = 0U; index < 8U; ++index) {
        if (strcmp(context->objects[index].kind, fixed_kinds[index]) != 0) {
            return pf_tq_store_error(error, error_size,
                "authority object fixed lookup order mismatch at %zu", index);
        }
    }
    for (index = 8U; index < context->object_count; ++index) {
        if (strcmp(context->objects[index].kind, "revocation-record") != 0 ||
                (index > 8U && strcmp(context->objects[index - 1U].id,
                    context->objects[index].id) >= 0)) {
            return pf_tq_store_error(error, error_size,
                "revocation-record object order/uniqueness rejected");
        }
    }
    if (pf_tq_ed25519_public(context->service_seed, derived,
            error, error_size) != 0 || memcmp(derived,
                context->service_public_key, 32U) != 0) {
        return pf_tq_store_error(error, error_size,
            "service seed/public key mismatch");
    }
    for (index = 0U; index < 3U; ++index) {
        size_t other;
        if (!pf_tq_ascii_nonempty(context->role_signers[index].key_id, 127U) ||
                !pf_tq_ascii_nonempty(
                    context->role_signers[index].principal_id, 127U) ||
                context->role_signers[index].role_mask == 0U ||
                (context->role_signers[index].role_mask &
                    ~PF_TQ_STORE_V2_REQUIRED_ROLE_MASK) != 0U ||
                pf_tq_ed25519_public(context->role_signers[index].seed,
                    derived, error, error_size) != 0 ||
                memcmp(derived, context->role_signers[index].public_key, 32U) != 0 ||
                memcmp(derived, context->service_public_key, 32U) == 0) {
            return pf_tq_store_error(error, error_size,
                "role signer seed/public identity rejected");
        }
        if (index > 0U && strcmp(context->role_signers[index - 1U].key_id,
                context->role_signers[index].key_id) >= 0) {
            return pf_tq_store_error(error, error_size,
                "role signer key IDs must be strictly sorted");
        }
        for (other = 0U; other < index; ++other) {
            if (strcmp(context->role_signers[other].principal_id,
                    context->role_signers[index].principal_id) == 0 ||
                    memcmp(context->role_signers[other].public_key,
                        context->role_signers[index].public_key, 32U) == 0) {
                return pf_tq_store_error(error, error_size,
                    "role signer principal/key reuse rejected");
            }
        }
        roles |= context->role_signers[index].role_mask;
    }
    if ((roles & PF_TQ_STORE_V2_REQUIRED_ROLE_MASK) !=
            PF_TQ_STORE_V2_REQUIRED_ROLE_MASK) {
        return pf_tq_store_error(error, error_size,
            "role signers do not cover architecture/quality/security");
    }
    if (strcmp(context->durable_tuple.task_id, context->task_id) != 0 ||
            strcmp(context->durable_tuple.operation, context->operation) != 0 ||
            strcmp(context->durable_tuple.run_id, context->run_id) != 0 ||
            strcmp(context->durable_tuple.nonce, context->nonce) != 0 ||
            pf_tq_durable_inspect_v2(context->durable_root_fd,
                context->durable_uid, context->durable_gid,
                &context->durable_tuple, &snapshot, error, error_size) != 0 ||
            snapshot.state != PF_TQ_DURABLE_ACTIVE) {
        return pf_tq_store_error(error, error_size,
            "durable tuple must start exact active");
    }
    if (pf_tq_object_projection(&context->objects[1], &projection,
            error, error_size) != 0) return -1;
    if (projection.ref_size != context->production_profile_pin_ref.size ||
            memcmp(projection.ref, context->production_profile_pin_ref.bytes,
                projection.ref_size) != 0) {
        pf_tq_free_projection(&projection);
        return pf_tq_store_error(error, error_size,
            "production profile pin ref does not recompute");
    }
    pf_tq_free_projection(&projection);
    if (pf_tq_object_projection(&context->objects[2], &projection,
            error, error_size) != 0) return -1;
    if (strcmp(projection.digest_wire, context->production_profile_digest) != 0) {
        pf_tq_free_projection(&projection);
        return pf_tq_store_error(error, error_size,
            "production profile digest does not recompute");
    }
    pf_tq_free_projection(&projection);
    if (context->objects[3].content.size != context->adapter.size ||
            memcmp(context->objects[3].content.bytes, context->adapter.bytes,
                context->adapter.size) != 0 ||
            context->objects[4].content.size != context->snapshot_parser.size ||
            memcmp(context->objects[4].content.bytes, context->snapshot_parser.bytes,
                context->snapshot_parser.size) != 0) {
        return pf_tq_store_error(error, error_size,
            "adapter/snapshot-parser lookup bytes mismatch handoff values");
    }
    if (pf_tq_object_projection(&context->objects[5], &projection,
            error, error_size) != 0) return -1;
    if (projection.ref_size != context->service_ref.size || memcmp(
            projection.ref, context->service_ref.bytes, projection.ref_size) != 0) {
        pf_tq_free_projection(&projection);
        return pf_tq_store_error(error, error_size,
            "service descriptor ref does not recompute");
    }
    pf_tq_free_projection(&projection);
    return 0;
}

static int pf_tq_socket_validate(
    int socket_fd,
    pf_tq_store_v2_context *context,
    char *error,
    size_t error_size
) {
    int domain = 0;
    int type = 0;
    int send_buffer = 0;
    int receive_buffer = 0;
    int pass_credentials = 1;
    socklen_t size = sizeof(int);
    if (socket_fd < 0 || getsockopt(socket_fd, SOL_SOCKET, SO_DOMAIN,
            &domain, &size) != 0 || domain != AF_UNIX ||
            getsockopt(socket_fd, SOL_SOCKET, SO_TYPE, &type, &size) != 0 ||
            type != SOCK_SEQPACKET ||
            getsockopt(socket_fd, SOL_SOCKET, SO_SNDBUF,
                &send_buffer, &size) != 0 ||
            getsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF,
                &receive_buffer, &size) != 0 ||
            send_buffer < PF_TQ_MINIMUM_EFFECTIVE_SOCKET_BUFFER ||
            receive_buffer < PF_TQ_MINIMUM_EFFECTIVE_SOCKET_BUFFER) {
        return pf_tq_store_error(error, error_size,
            "authorityStoreFd socket domain/type/buffer rejected");
    }
    if (context->require_kernel_credentials && setsockopt(socket_fd,
            SOL_SOCKET, SO_PASSCRED, &pass_credentials,
            sizeof(pass_credentials)) != 0) {
        return pf_tq_store_error(error, error_size,
            "SO_PASSCRED setup failed: %s", strerror(errno));
    }
    return 0;
}

static int pf_tq_build_echo_scalars(
    const pf_tq_store_v2_context *context,
    struct pf_tq_scalar *task,
    struct pf_tq_scalar *operation,
    struct pf_tq_scalar *run,
    struct pf_tq_scalar *nonce,
    struct pf_tq_scalar *head_sequence,
    struct pf_tq_scalar *head_digest,
    struct pf_tq_scalar *handoff_digest,
    char *error,
    size_t error_size
) {
    char digest[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    if (pf_tq_scalar_string(task, context->task_id, error, error_size) != 0 ||
            pf_tq_scalar_string(operation, context->operation,
                error, error_size) != 0 ||
            pf_tq_scalar_string(run, context->run_id, error, error_size) != 0 ||
            pf_tq_scalar_string(nonce, context->nonce, error, error_size) != 0 ||
            pf_tq_scalar_uint(head_sequence, context->head_sequence,
                error, error_size) != 0) return -1;
    pf_tq_digest_wire(context->head_digest, digest);
    if (pf_tq_scalar_string(head_digest, digest, error, error_size) != 0) return -1;
    pf_tq_digest_wire(context->handoff_digest, digest);
    return pf_tq_scalar_string(handoff_digest, digest, error, error_size);
}

static int pf_tq_send_server_hello(
    int socket_fd,
    const pf_tq_store_v2_context *context,
    char *error,
    size_t error_size
) {
    struct pf_tq_scalar task, operation, run, nonce, head_sequence;
    struct pf_tq_scalar head_digest, handoff_digest, schema, version, status;
    pf_tq_jcs_field_v2 fields[11];
    unsigned char *frame = NULL;
    size_t frame_size = 0U;
    int result = -1;
    if (pf_tq_build_echo_scalars(context, &task, &operation, &run, &nonce,
            &head_sequence, &head_digest, &handoff_digest,
            error, error_size) != 0 ||
            pf_tq_scalar_string(&schema, PF_TQ_SERVER_HELLO_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&version, PF_TQ_STORE_VERSION,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&status, "ready", error, error_size) != 0) return -1;
    fields[0] = (pf_tq_jcs_field_v2){"taskId", task.bytes, task.size};
    fields[1] = (pf_tq_jcs_field_v2){"operation", operation.bytes, operation.size};
    fields[2] = (pf_tq_jcs_field_v2){"runId", run.bytes, run.size};
    fields[3] = (pf_tq_jcs_field_v2){"nonce", nonce.bytes, nonce.size};
    fields[4] = (pf_tq_jcs_field_v2){"service", context->service_ref.bytes, context->service_ref.size};
    fields[5] = (pf_tq_jcs_field_v2){"handoffDigest", handoff_digest.bytes, handoff_digest.size};
    fields[6] = (pf_tq_jcs_field_v2){"headSequence", head_sequence.bytes, head_sequence.size};
    fields[7] = (pf_tq_jcs_field_v2){"headDigest", head_digest.bytes, head_digest.size};
    fields[8] = (pf_tq_jcs_field_v2){"schema", schema.bytes, schema.size};
    fields[9] = (pf_tq_jcs_field_v2){"version", version.bytes, version.size};
    fields[10] = (pf_tq_jcs_field_v2){"status", status.bytes, status.size};
    if (pf_tq_build_signed_object(fields, 11U,
            PF_TQ_SERVER_HELLO_SIGNATURE_DOMAIN, context->service_seed,
            &frame, &frame_size, error, error_size) != 0) goto cleanup;
    result = pf_tq_send_frame(socket_fd, frame, frame_size, error, error_size);
cleanup:
    free(frame);
    return result;
}

static int pf_tq_validate_client_hello(
    const unsigned char *payload,
    size_t payload_size,
    const pf_tq_store_v2_context *context,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "handoffDigest", "headDigest", "headSequence", "nonce", "operation",
        "runId", "schema", "service", "taskId", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    int result = -1;
    if (pf_tq_parse_root(payload, payload_size, &document, &root,
            error, error_size) != 0) return -1;
    if (pf_tq_jcs_object_exact_v2(&document, root, fields,
            sizeof(fields) / sizeof(fields[0]), error, error_size) != 0 ||
            pf_tq_node_string(&document, root, "schema", PF_TQ_CLIENT_HELLO_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_node_string(&document, root, "version", PF_TQ_STORE_VERSION,
                error, error_size) != 0 ||
            pf_tq_validate_echo(&document, root, context, 1,
                error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&document);
    return result;
}

static int pf_tq_validate_lookup_key(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *key,
    const pf_tq_store_v2_context *context,
    const pf_tq_store_v2_object *object,
    size_t request_id,
    char *error,
    size_t error_size
) {
    static const char *const object_fields[] = {
        "gateSetDigest", "kind", "namespace", "objectId", "objectKind",
        "operation", "taskId"
    };
    static const char *const head_fields[] = {
        "gateSetDigest", "headDigest", "headSequence", "kind", "namespace",
        "objectKind", "operation", "taskId"
    };
    const char *const *fields;
    size_t field_count;
    if (key == NULL || key->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_store_error(error, error_size, "lookup key must be object");
    }
    if (request_id == 7U) {
        fields = head_fields;
        field_count = sizeof(head_fields) / sizeof(head_fields[0]);
        if (pf_tq_node_string(document, key, "kind", "revocation-head",
                error, error_size) != 0 ||
                pf_tq_node_uint(document, key, "headSequence",
                    context->head_sequence, error, error_size) != 0 ||
                pf_tq_node_digest(document, key, "headDigest",
                    context->head_digest, error, error_size) != 0) return -1;
    } else {
        fields = object_fields;
        field_count = sizeof(object_fields) / sizeof(object_fields[0]);
        if (pf_tq_node_string(document, key, "kind", "object",
                error, error_size) != 0 ||
                pf_tq_node_string(document, key, "objectId", object->id,
                    error, error_size) != 0) return -1;
    }
    if (pf_tq_jcs_object_exact_v2(document, key, fields, field_count,
            error, error_size) != 0 ||
            pf_tq_node_string(document, key, "namespace", PF_TQ_STORE_NAMESPACE,
                error, error_size) != 0 ||
            pf_tq_node_string(document, key, "taskId", context->task_id,
                error, error_size) != 0 ||
            pf_tq_node_string(document, key, "operation", context->operation,
                error, error_size) != 0 ||
            pf_tq_node_string(document, key, "objectKind", object->kind,
                error, error_size) != 0 ||
            pf_tq_node_digest(document, key, "gateSetDigest",
                context->gate_set_digest, error, error_size) != 0) return -1;
    return 0;
}

static int pf_tq_validate_lookup_request(
    const unsigned char *payload,
    size_t payload_size,
    const pf_tq_store_v2_context *context,
    const pf_tq_store_v2_object *object,
    size_t request_id,
    pf_tq_store_v2_bytes *key_bytes,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "headDigest", "headSequence", "key", "nonce", "operation", "requestId",
        "runId", "schema", "service", "taskId", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *key;
    int result = -1;
    if (pf_tq_parse_root(payload, payload_size, &document, &root,
            error, error_size) != 0) return -1;
    key = pf_tq_jcs_object_get_v2(&document, root, "key");
    if (pf_tq_jcs_object_exact_v2(&document, root, fields,
            sizeof(fields) / sizeof(fields[0]), error, error_size) != 0 ||
            pf_tq_node_string(&document, root, "schema", PF_TQ_LOOKUP_REQUEST_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_node_string(&document, root, "version", PF_TQ_STORE_VERSION,
                error, error_size) != 0 ||
            pf_tq_node_uint(&document, root, "requestId", request_id,
                error, error_size) != 0 ||
            pf_tq_validate_echo(&document, root, context, 0,
                error, error_size) != 0 ||
            pf_tq_validate_lookup_key(&document, key, context, object,
                request_id, error, error_size) != 0) goto cleanup;
    key_bytes->bytes = payload + key->raw_start;
    key_bytes->size = key->raw_end - key->raw_start;
    result = 0;
cleanup:
    if (result != 0) {
        key_bytes->bytes = NULL;
        key_bytes->size = 0U;
    }
    /* key_bytes points into payload, not into document arenas. */
    pf_tq_jcs_free_v2(&document);
    return result;
}

static int pf_tq_hex_json(
    const unsigned char *bytes,
    size_t size,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    char *hex;
    unsigned char *encoded;
    size_t written = 0U;
    if (size > (PF_TQ_STORE_V2_MAX_FRAME_BYTES - 2U) / 2U) {
        return pf_tq_store_error(error, error_size,
            "lookup object bytes exceed response hex bound");
    }
    hex = malloc(2U * size + 1U);
    encoded = malloc(2U * size + 3U);
    if (hex == NULL || encoded == NULL) {
        free(hex);
        free(encoded);
        return pf_tq_store_error(error, error_size,
            "lookup object hex allocation failed");
    }
    pf_tq_hex(bytes, size, hex);
    if (pf_tq_jcs_encode_string_v2(hex, encoded, 2U * size + 3U,
            &written, error, error_size) != 0) {
        free(hex);
        free(encoded);
        return -1;
    }
    free(hex);
    *output = encoded;
    *output_size = written;
    return 0;
}

static int pf_tq_send_lookup_response(
    int socket_fd,
    const pf_tq_store_v2_context *context,
    const pf_tq_store_v2_object *object,
    size_t request_id,
    pf_tq_store_v2_bytes key,
    char *error,
    size_t error_size
) {
    struct pf_tq_object_projection projection;
    unsigned char *object_hex = NULL;
    size_t object_hex_size = 0U;
    struct pf_tq_scalar task, operation, run, nonce, head_sequence;
    struct pf_tq_scalar head_digest, handoff_digest, schema, version, status, rid;
    pf_tq_jcs_field_v2 fields[14];
    unsigned char *frame = NULL;
    size_t frame_size = 0U;
    int result = -1;
    memset(&projection, 0, sizeof(projection));
    if (pf_tq_object_projection(object, &projection, error, error_size) != 0 ||
            pf_tq_hex_json(object->content.bytes, object->content.size,
                &object_hex, &object_hex_size, error, error_size) != 0 ||
            pf_tq_build_echo_scalars(context, &task, &operation, &run, &nonce,
                &head_sequence, &head_digest, &handoff_digest,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&schema, PF_TQ_LOOKUP_RESPONSE_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&version, PF_TQ_STORE_VERSION,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&status, "found", error, error_size) != 0 ||
            pf_tq_scalar_uint(&rid, request_id, error, error_size) != 0) goto cleanup;
    fields[0] = (pf_tq_jcs_field_v2){"requestId", rid.bytes, rid.size};
    fields[1] = (pf_tq_jcs_field_v2){"taskId", task.bytes, task.size};
    fields[2] = (pf_tq_jcs_field_v2){"operation", operation.bytes, operation.size};
    fields[3] = (pf_tq_jcs_field_v2){"runId", run.bytes, run.size};
    fields[4] = (pf_tq_jcs_field_v2){"nonce", nonce.bytes, nonce.size};
    fields[5] = (pf_tq_jcs_field_v2){"service", context->service_ref.bytes, context->service_ref.size};
    fields[6] = (pf_tq_jcs_field_v2){"headSequence", head_sequence.bytes, head_sequence.size};
    fields[7] = (pf_tq_jcs_field_v2){"headDigest", head_digest.bytes, head_digest.size};
    fields[8] = (pf_tq_jcs_field_v2){"key", key.bytes, key.size};
    fields[9] = (pf_tq_jcs_field_v2){"object", projection.ref, projection.ref_size};
    fields[10] = (pf_tq_jcs_field_v2){"objectBytesHex", object_hex, object_hex_size};
    fields[11] = (pf_tq_jcs_field_v2){"schema", schema.bytes, schema.size};
    fields[12] = (pf_tq_jcs_field_v2){"version", version.bytes, version.size};
    fields[13] = (pf_tq_jcs_field_v2){"status", status.bytes, status.size};
    if (pf_tq_build_signed_object(fields, 14U,
            PF_TQ_LOOKUP_RESPONSE_SIGNATURE_DOMAIN, context->service_seed,
            &frame, &frame_size, error, error_size) != 0) goto cleanup;
    result = pf_tq_send_frame(socket_fd, frame, frame_size, error, error_size);
cleanup:
    free(frame);
    free(object_hex);
    pf_tq_free_projection(&projection);
    return result;
}

static bool pf_tq_role_grammar(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node
) {
    size_t index;
    if (node == NULL || node->type != PF_TQ_JCS_STRING ||
            node->string_size == 0U || node->string_size > 512U) return false;
    for (index = 0U; index < node->string_size; ++index) {
        unsigned char character = document->bytes[node->string_start + index];
        if (!((character >= 'A' && character <= 'Z') ||
                (character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9') ||
                character == '-' || character == '.' || character == '_' ||
                character == '/')) return false;
    }
    if (document->bytes[node->string_start] == '/' ||
            document->bytes[node->string_start + node->string_size - 1U] == '/') {
        return false;
    }
    for (index = 1U; index < node->string_size; ++index) {
        if (document->bytes[node->string_start + index - 1U] == '/' &&
                document->bytes[node->string_start + index] == '/') return false;
    }
    return true;
}

static int pf_tq_digest_field_shape(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *root,
    const char *field,
    char *error,
    size_t error_size
) {
    const pf_tq_jcs_node_v2 *node = pf_tq_jcs_object_get_v2(document, root, field);
    char wire[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    if (pf_tq_jcs_copy_string_v2(document, node, wire,
            sizeof(wire), error, error_size) != 0 || !pf_tq_is_digest_wire(wire)) {
        return pf_tq_store_error(error, error_size,
            "unsigned acceptance digest field %s rejected", field);
    }
    return 0;
}

static int pf_tq_validate_unsigned_acceptance(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_store_v2_context *context,
    pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 **root,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "adapter", "authorityClass", "bundleDigest", "closeoutCandidate",
        "governanceCompletionDigest", "id", "ledgerProjectionDigest", "operation",
        "preCloseCandidate", "productionProfileDigest", "productionProfilePin",
        "provenanceBundleDigest", "provenanceRoles", "pureProjectionDigest",
        "schema", "snapshotParser", "subjectDigest", "trustedVerificationInstant",
        "version"
    };
    static const char *const digest_fields[] = {
        "bundleDigest", "productionProfileDigest", "provenanceBundleDigest",
        "pureProjectionDigest", "subjectDigest"
    };
    const pf_tq_jcs_node_v2 *closeout;
    const pf_tq_jcs_node_v2 *ledger;
    const pf_tq_jcs_node_v2 *governance;
    const pf_tq_jcs_node_v2 *roles;
    const pf_tq_jcs_node_v2 *previous = NULL;
    size_t index;
    char expected_id[PF_TQ_STORE_V2_ID_BYTES * 2U];
    const char *suffix = context->task_id;
    char suffix_lower[PF_TQ_STORE_V2_ID_BYTES];
    size_t suffix_size;
    if (size == 0U || size > PF_TQ_STORE_V2_MAX_ACCEPTANCE_BYTES ||
            pf_tq_parse_root(bytes, size, document, root,
                error, error_size) != 0) return -1;
    if (strncmp(suffix, "TASK-", 5U) == 0) suffix += 5U;
    suffix_size = strlen(suffix);
    if (suffix_size == 0U || suffix_size >= sizeof(suffix_lower)) goto invalid_id;
    for (index = 0U; index < suffix_size; ++index) {
        unsigned char character = (unsigned char)suffix[index];
        suffix_lower[index] = (char)(character >= 'A' && character <= 'Z'
            ? character - 'A' + 'a' : character);
    }
    suffix_lower[suffix_size] = '\0';
    if (snprintf(expected_id, sizeof(expected_id),
            "protected-task-qualification-%s-%s",
            context->operation, suffix_lower) >= (int)sizeof(expected_id)) {
invalid_id:
        pf_tq_jcs_free_v2(document);
        return pf_tq_store_error(error, error_size,
            "unsigned acceptance derived id overflow");
    }
    if (pf_tq_jcs_object_exact_v2(document, *root, fields,
            sizeof(fields) / sizeof(fields[0]), error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "schema", PF_TQ_ACCEPTANCE_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "version", "1.0.0",
                error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "authorityClass",
                "production-candidate-bound", error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "operation", context->operation,
                error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "id", expected_id,
                error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "trustedVerificationInstant",
                context->trusted_instant, error, error_size) != 0 ||
            pf_tq_node_string(document, *root, "productionProfileDigest",
                context->production_profile_digest, error, error_size) != 0 ||
            pf_tq_node_raw(document, *root, "adapter", context->adapter,
                error, error_size) != 0 ||
            pf_tq_node_raw(document, *root, "snapshotParser",
                context->snapshot_parser, error, error_size) != 0 ||
            pf_tq_node_raw(document, *root, "productionProfilePin",
                context->production_profile_pin_ref, error, error_size) != 0 ||
            pf_tq_node_raw(document, *root, "preCloseCandidate",
                context->pre_close_candidate, error, error_size) != 0) {
        pf_tq_jcs_free_v2(document);
        return -1;
    }
    for (index = 0U; index < sizeof(digest_fields) / sizeof(digest_fields[0]);
            ++index) {
        if (pf_tq_digest_field_shape(document, *root, digest_fields[index],
                error, error_size) != 0) {
            pf_tq_jcs_free_v2(document);
            return -1;
        }
    }
    closeout = pf_tq_jcs_object_get_v2(document, *root, "closeoutCandidate");
    ledger = pf_tq_jcs_object_get_v2(document, *root, "ledgerProjectionDigest");
    governance = pf_tq_jcs_object_get_v2(
        document, *root, "governanceCompletionDigest");
    if (strcmp(context->operation, "task-completion") == 0 ||
            strcmp(context->operation, "d0-10-bootstrap-receipt") == 0) {
        if (context->closeout_candidate.bytes == NULL ||
                !pf_tq_jcs_raw_equal_v2(document, closeout,
                    context->closeout_candidate.bytes,
                    context->closeout_candidate.size)) {
            pf_tq_jcs_free_v2(document);
            return pf_tq_store_error(error, error_size,
                "receipt acceptance closeoutCandidate mismatch");
        }
    } else if (closeout == NULL || closeout->type != PF_TQ_JCS_NULL) {
        pf_tq_jcs_free_v2(document);
        return pf_tq_store_error(error, error_size,
            "approval acceptance closeoutCandidate must be null");
    }
    if (strcmp(context->operation, "d0-10-bootstrap-receipt") == 0) {
        if (ledger == NULL || ledger->type != PF_TQ_JCS_STRING ||
                governance == NULL || governance->type != PF_TQ_JCS_STRING ||
                pf_tq_digest_field_shape(document, *root,
                    "ledgerProjectionDigest", error, error_size) != 0 ||
                pf_tq_digest_field_shape(document, *root,
                    "governanceCompletionDigest", error, error_size) != 0) {
            pf_tq_jcs_free_v2(document);
            return -1;
        }
    } else if (ledger == NULL || ledger->type != PF_TQ_JCS_NULL ||
            governance == NULL || governance->type != PF_TQ_JCS_NULL) {
        pf_tq_jcs_free_v2(document);
        return pf_tq_store_error(error, error_size,
            "non-D0-receipt external digests must be null");
    }
    roles = pf_tq_jcs_object_get_v2(document, *root, "provenanceRoles");
    if (roles == NULL || roles->type != PF_TQ_JCS_ARRAY || roles->child_count == 0U) {
        pf_tq_jcs_free_v2(document);
        return pf_tq_store_error(error, error_size,
            "provenanceRoles must be a nonempty array");
    }
    for (index = 0U; index < roles->child_count; ++index) {
        const pf_tq_jcs_node_v2 *role = pf_tq_jcs_array_at_v2(document, roles, index);
        if (!pf_tq_role_grammar(document, role)) {
            pf_tq_jcs_free_v2(document);
            return pf_tq_store_error(error, error_size,
                "provenance role grammar rejected");
        }
        if (previous != NULL) {
            int comparison = pf_tq_raw_compare(
                document->bytes + previous->string_start, previous->string_size,
                document->bytes + role->string_start, role->string_size);
            if (comparison >= 0) {
                pf_tq_jcs_free_v2(document);
                return pf_tq_store_error(error, error_size,
                    "provenanceRoles must be strictly ASCII-sorted");
            }
        }
        previous = role;
    }
    return 0;
}

static int pf_tq_validate_terminal_request(
    const unsigned char *payload,
    size_t payload_size,
    const pf_tq_store_v2_context *context,
    size_t request_id,
    unsigned char **unsigned_acceptance,
    size_t *unsigned_acceptance_size,
    unsigned char statement_digest[32],
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "acceptanceStatementDigest", "adapter", "handoffDigest", "headDigest",
        "headSequence", "nonce", "operation", "productionProfilePin",
        "requestId", "runId", "schema", "service", "snapshotParser", "taskId",
        "unsignedAcceptanceBytesHex", "version"
    };
    pf_tq_jcs_document_v2 document;
    pf_tq_jcs_document_v2 acceptance_document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *acceptance_root;
    const pf_tq_jcs_node_v2 *hex;
    size_t decoded = 0U;
    int result = -1;
    memset(&acceptance_document, 0, sizeof(acceptance_document));
    if (pf_tq_parse_root(payload, payload_size, &document, &root,
            error, error_size) != 0) return -1;
    hex = pf_tq_jcs_object_get_v2(&document, root, "unsignedAcceptanceBytesHex");
    if (pf_tq_jcs_object_exact_v2(&document, root, fields,
            sizeof(fields) / sizeof(fields[0]), error, error_size) != 0 ||
            pf_tq_node_string(&document, root, "schema", PF_TQ_TERMINAL_REQUEST_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_node_string(&document, root, "version", PF_TQ_STORE_VERSION,
                error, error_size) != 0 ||
            pf_tq_node_uint(&document, root, "requestId", request_id,
                error, error_size) != 0 ||
            pf_tq_validate_echo(&document, root, context, 1,
                error, error_size) != 0 ||
            pf_tq_node_raw(&document, root, "adapter", context->adapter,
                error, error_size) != 0 ||
            pf_tq_node_raw(&document, root, "productionProfilePin",
                context->production_profile_pin_ref, error, error_size) != 0 ||
            pf_tq_node_raw(&document, root, "snapshotParser",
                context->snapshot_parser, error, error_size) != 0) goto cleanup;
    *unsigned_acceptance = malloc(PF_TQ_STORE_V2_MAX_ACCEPTANCE_BYTES);
    if (*unsigned_acceptance == NULL || pf_tq_jcs_decode_hex_v2(
            &document, hex, *unsigned_acceptance, 1U,
            PF_TQ_STORE_V2_MAX_ACCEPTANCE_BYTES, &decoded,
            error, error_size) != 0) goto cleanup;
    *unsigned_acceptance_size = decoded;
    if (pf_tq_validate_unsigned_acceptance(*unsigned_acceptance, decoded,
            context, &acceptance_document, &acceptance_root,
            error, error_size) != 0 ||
            pf_tq_domain_digest(PF_TQ_ACCEPTANCE_STATEMENT_DOMAIN,
                *unsigned_acceptance, decoded, statement_digest,
                error, error_size) != 0 ||
            pf_tq_node_digest(&document, root, "acceptanceStatementDigest",
                statement_digest, error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&acceptance_document);
    pf_tq_jcs_free_v2(&document);
    if (result != 0) {
        free(*unsigned_acceptance);
        *unsigned_acceptance = NULL;
        *unsigned_acceptance_size = 0U;
    }
    return result;
}

static int pf_tq_build_approval_signature_array(
    pf_tq_store_v2_context *context,
    const unsigned char statement_digest[32],
    int dry_run,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    unsigned char message[sizeof(PF_TQ_ACCEPTANCE_SIGNATURE_DOMAIN) + 32U];
    unsigned char signature[64];
    char signature_hex[PF_TQ_SIGNATURE_HEX_BYTES + 1U];
    unsigned char *objects[3] = {NULL, NULL, NULL};
    size_t object_sizes[3] = {0U, 0U, 0U};
    size_t index;
    size_t total = 2U;
    unsigned char *array = NULL;
    size_t offset = 0U;
    int result = -1;
    memcpy(message, PF_TQ_ACCEPTANCE_SIGNATURE_DOMAIN,
        sizeof(PF_TQ_ACCEPTANCE_SIGNATURE_DOMAIN) - 1U);
    message[sizeof(PF_TQ_ACCEPTANCE_SIGNATURE_DOMAIN) - 1U] = 0U;
    memcpy(message + sizeof(PF_TQ_ACCEPTANCE_SIGNATURE_DOMAIN),
        statement_digest, 32U);
    for (index = 0U; index < 3U; ++index) {
        struct pf_tq_scalar algorithm, key_id, signature_value;
        pf_tq_jcs_field_v2 fields[3];
        if (dry_run) {
            memset(signature_hex, '0', PF_TQ_SIGNATURE_HEX_BYTES);
            signature_hex[PF_TQ_SIGNATURE_HEX_BYTES] = '\0';
        } else {
            if (pf_tq_ed25519_sign(context->role_signers[index].seed,
                    message, sizeof(message), signature,
                    error, error_size) != 0) goto cleanup;
            pf_tq_hex(signature, sizeof(signature), signature_hex);
            OPENSSL_cleanse(signature, sizeof(signature));
        }
        if (pf_tq_scalar_string(&algorithm, "ed25519", error, error_size) != 0 ||
                pf_tq_scalar_string(&key_id, context->role_signers[index].key_id,
                    error, error_size) != 0 ||
                pf_tq_scalar_string(&signature_value, signature_hex,
                    error, error_size) != 0) goto cleanup;
        fields[0] = (pf_tq_jcs_field_v2){"algorithm", algorithm.bytes, algorithm.size};
        fields[1] = (pf_tq_jcs_field_v2){"keyId", key_id.bytes, key_id.size};
        fields[2] = (pf_tq_jcs_field_v2){"signature", signature_value.bytes, signature_value.size};
        if (pf_tq_encode_fields_alloc(fields, 3U, &objects[index],
                &object_sizes[index], 1024U, error, error_size) != 0) goto cleanup;
        total += object_sizes[index] + (index > 0U ? 1U : 0U);
    }
    array = malloc(total);
    if (array == NULL) {
        (void)pf_tq_store_error(error, error_size,
            "approval signature array allocation failed");
        goto cleanup;
    }
    array[offset++] = '[';
    for (index = 0U; index < 3U; ++index) {
        if (index > 0U) array[offset++] = ',';
        memcpy(array + offset, objects[index], object_sizes[index]);
        offset += object_sizes[index];
    }
    array[offset++] = ']';
    if (offset != total) {
        (void)pf_tq_store_error(error, error_size,
            "approval signature array size mismatch");
        goto cleanup;
    }
    *output = array;
    *output_size = total;
    array = NULL;
    result = 0;
cleanup:
    OPENSSL_cleanse(signature, sizeof(signature));
    OPENSSL_cleanse(message, sizeof(message));
    free(array);
    for (index = 0U; index < 3U; ++index) free(objects[index]);
    return result;
}

static int pf_tq_build_signed_acceptance(
    const unsigned char *unsigned_bytes,
    size_t unsigned_size,
    const unsigned char *signature_array,
    size_t signature_array_size,
    unsigned char **signed_bytes,
    size_t *signed_size,
    char *error,
    size_t error_size
) {
    static const char *const signed_fields[] = {
        "adapter", "authorityClass", "bundleDigest", "closeoutCandidate",
        "governanceCompletionDigest", "id", "ledgerProjectionDigest", "operation",
        "preCloseCandidate", "productionProfileDigest", "productionProfilePin",
        "provenanceBundleDigest", "provenanceRoles", "pureProjectionDigest",
        "schema", "signatures", "snapshotParser", "subjectDigest",
        "trustedVerificationInstant", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    pf_tq_jcs_field_v2 fields[20];
    size_t index;
    int result = -1;
    if (pf_tq_parse_root(unsigned_bytes, unsigned_size, &document, &root,
            error, error_size) != 0) return -1;
    for (index = 0U; index < 20U; ++index) {
        const pf_tq_jcs_node_v2 *node;
        fields[index].key = signed_fields[index];
        if (strcmp(signed_fields[index], "signatures") == 0) {
            fields[index].value = signature_array;
            fields[index].value_size = signature_array_size;
            continue;
        }
        node = pf_tq_jcs_object_get_v2(&document, root, signed_fields[index]);
        if (node == NULL) {
            (void)pf_tq_store_error(error, error_size,
                "unsigned acceptance field missing during signed transform");
            goto cleanup;
        }
        fields[index].value = unsigned_bytes + node->raw_start;
        fields[index].value_size = node->raw_end - node->raw_start;
    }
    if (pf_tq_encode_fields_alloc(fields, 20U, signed_bytes, signed_size,
            PF_TQ_STORE_V2_MAX_ACCEPTANCE_BYTES, error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&document);
    return result;
}

static int pf_tq_acceptance_ref(
    const unsigned char *acceptance,
    size_t acceptance_size,
    unsigned char **ref,
    size_t *ref_size,
    char digest_wire[PF_TQ_DIGEST_WIRE_BYTES + 1U],
    char *error,
    size_t error_size
) {
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *id_node;
    const pf_tq_jcs_node_v2 *version_node;
    char id[256];
    char version[32];
    unsigned char digest[32];
    struct pf_tq_scalar digest_value, id_value, schema_value, version_value;
    pf_tq_jcs_field_v2 fields[4];
    int result = -1;
    if (pf_tq_parse_root(acceptance, acceptance_size, &document, &root,
            error, error_size) != 0) return -1;
    id_node = pf_tq_jcs_object_get_v2(&document, root, "id");
    version_node = pf_tq_jcs_object_get_v2(&document, root, "version");
    if (pf_tq_jcs_copy_string_v2(&document, id_node, id, sizeof(id),
            error, error_size) != 0 ||
            pf_tq_jcs_copy_string_v2(&document, version_node, version,
                sizeof(version), error, error_size) != 0 ||
            pf_tq_domain_digest(PF_TQ_ACCEPTANCE_FULL_DOMAIN,
                acceptance, acceptance_size, digest, error, error_size) != 0) goto cleanup;
    pf_tq_digest_wire(digest, digest_wire);
    if (pf_tq_scalar_string(&digest_value, digest_wire, error, error_size) != 0 ||
            pf_tq_scalar_string(&id_value, id, error, error_size) != 0 ||
            pf_tq_scalar_string(&schema_value, PF_TQ_ACCEPTANCE_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&version_value, version,
                error, error_size) != 0) goto cleanup;
    fields[0] = (pf_tq_jcs_field_v2){"digest", digest_value.bytes, digest_value.size};
    fields[1] = (pf_tq_jcs_field_v2){"id", id_value.bytes, id_value.size};
    fields[2] = (pf_tq_jcs_field_v2){"schema", schema_value.bytes, schema_value.size};
    fields[3] = (pf_tq_jcs_field_v2){"version", version_value.bytes, version_value.size};
    if (pf_tq_encode_fields_alloc(fields, 4U, ref, ref_size, 1024U,
            error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    pf_tq_jcs_free_v2(&document);
    return result;
}

static int pf_tq_terminal_response_fields(
    const pf_tq_store_v2_context *context,
    size_t request_id,
    const unsigned char statement_digest[32],
    const unsigned char *acceptance_ref,
    size_t acceptance_ref_size,
    const unsigned char *acceptance,
    size_t acceptance_size,
    pf_tq_jcs_field_v2 fields[15],
    struct pf_tq_scalar scalars[12],
    unsigned char **acceptance_hex,
    size_t *acceptance_hex_size,
    char *error,
    size_t error_size
) {
    char digest[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    if (pf_tq_build_echo_scalars(context,
            &scalars[0], &scalars[1], &scalars[2], &scalars[3],
            &scalars[4], &scalars[5], &scalars[6], error, error_size) != 0 ||
            pf_tq_scalar_string(&scalars[7], PF_TQ_TERMINAL_RESPONSE_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&scalars[8], PF_TQ_STORE_VERSION,
                error, error_size) != 0 ||
            pf_tq_scalar_string(&scalars[9], "signed", error, error_size) != 0 ||
            pf_tq_hex_json(acceptance, acceptance_size,
                acceptance_hex, acceptance_hex_size, error, error_size) != 0) return -1;
    pf_tq_digest_wire(statement_digest, digest);
    if (pf_tq_scalar_string(&scalars[10], digest, error, error_size) != 0 ||
            pf_tq_scalar_uint(&scalars[11], request_id,
                error, error_size) != 0) return -1;
    fields[0] = (pf_tq_jcs_field_v2){"acceptanceStatementDigest", scalars[10].bytes, scalars[10].size};
    fields[1] = (pf_tq_jcs_field_v2){"acceptance", acceptance_ref, acceptance_ref_size};
    fields[2] = (pf_tq_jcs_field_v2){"requestId", scalars[11].bytes, scalars[11].size};
    fields[3] = (pf_tq_jcs_field_v2){"taskId", scalars[0].bytes, scalars[0].size};
    fields[4] = (pf_tq_jcs_field_v2){"operation", scalars[1].bytes, scalars[1].size};
    fields[5] = (pf_tq_jcs_field_v2){"runId", scalars[2].bytes, scalars[2].size};
    fields[6] = (pf_tq_jcs_field_v2){"nonce", scalars[3].bytes, scalars[3].size};
    fields[7] = (pf_tq_jcs_field_v2){"service", context->service_ref.bytes, context->service_ref.size};
    fields[8] = (pf_tq_jcs_field_v2){"handoffDigest", scalars[6].bytes, scalars[6].size};
    fields[9] = (pf_tq_jcs_field_v2){"headSequence", scalars[4].bytes, scalars[4].size};
    fields[10] = (pf_tq_jcs_field_v2){"headDigest", scalars[5].bytes, scalars[5].size};
    fields[11] = (pf_tq_jcs_field_v2){"status", scalars[9].bytes, scalars[9].size};
    fields[12] = (pf_tq_jcs_field_v2){"acceptanceBytesHex", *acceptance_hex, *acceptance_hex_size};
    fields[13] = (pf_tq_jcs_field_v2){"schema", scalars[7].bytes, scalars[7].size};
    fields[14] = (pf_tq_jcs_field_v2){"version", scalars[8].bytes, scalars[8].size};
    return 0;
}

static int pf_tq_terminal_preflight_size(
    pf_tq_store_v2_context *context,
    size_t request_id,
    const unsigned char *unsigned_acceptance,
    size_t unsigned_acceptance_size,
    const unsigned char statement_digest[32],
    char *error,
    size_t error_size
) {
    unsigned char *signature_array = NULL;
    size_t signature_array_size = 0U;
    unsigned char *acceptance = NULL;
    size_t acceptance_size = 0U;
    unsigned char *acceptance_ref = NULL;
    size_t acceptance_ref_size = 0U;
    char acceptance_digest[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    pf_tq_jcs_field_v2 fields[15];
    struct pf_tq_scalar scalars[12];
    unsigned char *acceptance_hex = NULL;
    size_t acceptance_hex_size = 0U;
    unsigned char *response = NULL;
    size_t response_size = 0U;
    int result = -1;
    if (pf_tq_build_approval_signature_array(context, statement_digest, 1,
            &signature_array, &signature_array_size, error, error_size) != 0 ||
            pf_tq_build_signed_acceptance(unsigned_acceptance,
                unsigned_acceptance_size, signature_array, signature_array_size,
                &acceptance, &acceptance_size, error, error_size) != 0 ||
            acceptance_size > PF_TQ_STORE_V2_MAX_ACCEPTANCE_BYTES ||
            pf_tq_acceptance_ref(acceptance, acceptance_size,
                &acceptance_ref, &acceptance_ref_size, acceptance_digest,
                error, error_size) != 0 ||
            pf_tq_terminal_response_fields(context, request_id, statement_digest,
                acceptance_ref, acceptance_ref_size, acceptance, acceptance_size,
                fields, scalars, &acceptance_hex, &acceptance_hex_size,
                error, error_size) != 0 ||
            pf_tq_build_placeholder_signed_object(fields, 15U,
                &response, &response_size, error, error_size) != 0 ||
            response_size >= PF_TQ_STORE_V2_MAX_FRAME_BYTES) goto cleanup;
    result = 0;
cleanup:
    free(response);
    free(acceptance_hex);
    free(acceptance_ref);
    free(acceptance);
    free(signature_array);
    return result;
}

static int pf_tq_current_head_exact(
    pf_tq_store_v2_context *context,
    char *error,
    size_t error_size
) {
    uint64_t sequence = context->head_sequence;
    unsigned char digest[32];
    memcpy(digest, context->head_digest, 32U);
    if (context->current_head != NULL && context->current_head(
            context->current_head_opaque, &sequence, digest,
            error, error_size) != 0) return -1;
    if (sequence != context->head_sequence ||
            memcmp(digest, context->head_digest, 32U) != 0) {
        return pf_tq_store_error(error, error_size,
            "authority policy/revocation head drift rejected");
    }
    return 0;
}

static void pf_tq_reject_durable(
    pf_tq_store_v2_context *context,
    const char *reason
) {
    char ignored[PF_TQ_STORE_V2_ERROR_BYTES];
    pf_tq_durable_snapshot_v2 snapshot;
    pf_tq_durable_snapshot_v2 current;
    if (context == NULL || context->durable_root_fd < 0 ||
            !pf_tq_ascii_nonempty(context->trusted_instant, 20U)) return;
    if (pf_tq_durable_inspect_v2(context->durable_root_fd,
            context->durable_uid, context->durable_gid,
            &context->durable_tuple, &current, ignored, sizeof(ignored)) == 0 &&
            (current.state == PF_TQ_DURABLE_ACTIVE ||
             current.state == PF_TQ_DURABLE_SIGNING)) {
        (void)pf_tq_durable_reject_v2(context->durable_root_fd,
            context->durable_uid, context->durable_gid,
            &context->durable_tuple, reason, context->trusted_instant,
            &snapshot, ignored, sizeof(ignored));
    }
}

static int pf_tq_complete_terminal(
    int socket_fd,
    pf_tq_store_v2_context *context,
    struct pf_tq_peer_state *peer,
    size_t request_id,
    const unsigned char *unsigned_acceptance,
    size_t unsigned_acceptance_size,
    const unsigned char statement_digest[32],
    unsigned char **accepted_bytes,
    size_t *accepted_size,
    char *error,
    size_t error_size
) {
    unsigned char *signature_array = NULL;
    size_t signature_array_size = 0U;
    unsigned char *acceptance = NULL;
    size_t acceptance_size = 0U;
    unsigned char *acceptance_ref = NULL;
    size_t acceptance_ref_size = 0U;
    char acceptance_digest[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    pf_tq_jcs_field_v2 fields[15];
    struct pf_tq_scalar scalars[12];
    unsigned char *acceptance_hex = NULL;
    size_t acceptance_hex_size = 0U;
    unsigned char *response = NULL;
    size_t response_size = 0U;
    unsigned char response_digest_raw[32];
    char response_digest[PF_TQ_DIGEST_WIRE_BYTES + 1U];
    pf_tq_durable_snapshot_v2 snapshot;
    int accepted_committed = 0;
    int result = -1;
    if (pf_tq_terminal_preflight_size(context, request_id,
            unsigned_acceptance, unsigned_acceptance_size, statement_digest,
            error, error_size) != 0 ||
            pf_tq_pidfd_alive(peer, error, error_size) != 0 ||
            pf_tq_no_extra_packet(socket_fd, error, error_size) != 0 ||
            (context->terminal_lockdown != NULL && context->terminal_lockdown(
                context->terminal_lockdown_opaque, error, error_size) != 0) ||
            pf_tq_durable_begin_signing_v2(context->durable_root_fd,
                context->durable_uid, context->durable_gid,
                &context->durable_tuple, &snapshot, error, error_size) != 0 ||
            pf_tq_build_approval_signature_array(context, statement_digest, 0,
                &signature_array, &signature_array_size,
                error, error_size) != 0 ||
            pf_tq_build_signed_acceptance(unsigned_acceptance,
                unsigned_acceptance_size, signature_array, signature_array_size,
                &acceptance, &acceptance_size, error, error_size) != 0 ||
            pf_tq_acceptance_ref(acceptance, acceptance_size,
                &acceptance_ref, &acceptance_ref_size, acceptance_digest,
                error, error_size) != 0 ||
            pf_tq_terminal_response_fields(context, request_id, statement_digest,
                acceptance_ref, acceptance_ref_size, acceptance, acceptance_size,
                fields, scalars, &acceptance_hex, &acceptance_hex_size,
                error, error_size) != 0 ||
            pf_tq_build_signed_object(fields, 15U,
                PF_TQ_TERMINAL_RESPONSE_SIGNATURE_DOMAIN, context->service_seed,
                &response, &response_size, error, error_size) != 0 ||
            pf_tq_peer_checkpoint(context, peer,
                PF_TQ_STORE_V2_PEER_TERMINAL_FINAL, error, error_size) != 0 ||
            pf_tq_current_head_exact(context, error, error_size) != 0 ||
            pf_tq_domain_digest(PF_TQ_TERMINAL_RESPONSE_FULL_DOMAIN,
                response, response_size, response_digest_raw,
                error, error_size) != 0) goto cleanup;
    pf_tq_digest_wire(response_digest_raw, response_digest);
    if (pf_tq_durable_accept_v2(context->durable_root_fd,
            context->durable_uid, context->durable_gid,
            &context->durable_tuple, acceptance_digest, response_digest,
            context->trusted_instant, &snapshot, error, error_size) != 0) goto cleanup;
    accepted_committed = 1;
    if (pf_tq_send_frame(socket_fd, response, response_size,
            error, error_size) != 0) {
        char ignored[PF_TQ_STORE_V2_ERROR_BYTES];
        (void)pf_tq_durable_mark_undelivered_v2(context->durable_root_fd,
            context->durable_uid, context->durable_gid,
            &context->durable_tuple, &snapshot, ignored, sizeof(ignored));
        goto cleanup;
    }
    *accepted_bytes = acceptance;
    *accepted_size = acceptance_size;
    acceptance = NULL;
    result = 0;
cleanup:
    if (result != 0 && !accepted_committed) {
        pf_tq_reject_durable(context, "service-terminal-rejected");
    }
    OPENSSL_cleanse(response_digest_raw, sizeof(response_digest_raw));
    free(response);
    free(acceptance_hex);
    free(acceptance_ref);
    free(acceptance);
    free(signature_array);
    return result;
}

int pf_tq_store_v2_run(
    int socket_fd,
    pf_tq_store_v2_context *context,
    unsigned char **accepted_bytes,
    size_t *accepted_size,
    char *error,
    size_t error_size
) {
    struct pf_tq_peer_state peer;
    unsigned char *payload = NULL;
    size_t payload_size = 0U;
    size_t request_id;
    unsigned char *unsigned_acceptance = NULL;
    size_t unsigned_acceptance_size = 0U;
    unsigned char statement_digest[32];
    int result = -1;
    pf_tq_store_clear_error(error, error_size);
    if (accepted_bytes == NULL || accepted_size == NULL) {
        return pf_tq_store_error(error, error_size,
            "service result outputs are missing");
    }
    *accepted_bytes = NULL;
    *accepted_size = 0U;
    memset(&peer, 0, sizeof(peer));
    peer.pidfd = -1;
    memset(statement_digest, 0, sizeof(statement_digest));
    if (pf_tq_context_validate(context, error, error_size) != 0 ||
            pf_tq_socket_validate(socket_fd, context, error, error_size) != 0 ||
            pf_tq_current_head_exact(context, error, error_size) != 0) goto cleanup;
    if (pf_tq_receive_frame(socket_fd, context, &peer,
            PF_TQ_STORE_V2_PEER_HELLO, &payload, &payload_size,
            error, error_size) != 0 ||
            pf_tq_validate_client_hello(payload, payload_size, context,
                error, error_size) != 0 ||
            pf_tq_send_server_hello(socket_fd, context,
                error, error_size) != 0) goto cleanup;
    free(payload);
    payload = NULL;
    for (request_id = 0U; request_id < context->object_count; ++request_id) {
        pf_tq_store_v2_bytes key;
        if (pf_tq_receive_frame(socket_fd, context, &peer,
                PF_TQ_STORE_V2_PEER_LOOKUP, &payload, &payload_size,
                error, error_size) != 0 ||
                pf_tq_validate_lookup_request(payload, payload_size, context,
                    &context->objects[request_id], request_id, &key,
                    error, error_size) != 0 ||
                pf_tq_send_lookup_response(socket_fd, context,
                    &context->objects[request_id], request_id, key,
                    error, error_size) != 0) goto cleanup;
        free(payload);
        payload = NULL;
    }
    if (pf_tq_receive_frame(socket_fd, context, &peer,
            PF_TQ_STORE_V2_PEER_TERMINAL_PREFLIGHT,
            &payload, &payload_size, error, error_size) != 0 ||
            pf_tq_validate_terminal_request(payload, payload_size, context,
                context->object_count, &unsigned_acceptance,
                &unsigned_acceptance_size, statement_digest,
                error, error_size) != 0 ||
            pf_tq_complete_terminal(socket_fd, context, &peer,
                context->object_count, unsigned_acceptance,
                unsigned_acceptance_size, statement_digest,
                accepted_bytes, accepted_size, error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    if (result != 0) pf_tq_reject_durable(context, "service-protocol-rejected");
    if (peer.pidfd >= 0) close(peer.pidfd);
    free(unsigned_acceptance);
    free(payload);
    OPENSSL_cleanse(statement_digest, sizeof(statement_digest));
    return result;
}
