#define _GNU_SOURCE
#include "task_qualification_artifact_payload_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <unistd.h>

static int pf_tq_artifact_payload_error(
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

static void pf_tq_artifact_payload_clear_error(
    char *error,
    size_t error_size
) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_artifact_payload_free_v2(pf_tq_artifact_payload_v2 *payload) {
    if (payload == NULL) return;
    free(payload->bytes);
    memset(payload, 0, sizeof(*payload));
}

static int pf_tq_artifact_payload_fixed_string(
    const char *value,
    size_t capacity
) {
    return value != NULL && memchr(value, '\0', capacity) != NULL;
}

static int pf_tq_artifact_payload_ref_shape(
    const pf_tq_wire_content_ref_v2 *reference,
    char *error,
    size_t error_size
) {
    if (reference == NULL ||
            !pf_tq_artifact_payload_fixed_string(
                reference->schema, sizeof(reference->schema)) ||
            !pf_tq_artifact_payload_fixed_string(
                reference->id, sizeof(reference->id)) ||
            !pf_tq_artifact_payload_fixed_string(
                reference->version, sizeof(reference->version)) ||
            strcmp(reference->schema,
                PF_TQ_ARTIFACT_PAYLOAD_V2_SCHEMA) != 0 ||
            !pf_tq_wire_profile_id_v2(reference->id) ||
            !pf_tq_wire_semver_v2(reference->version)) {
        return pf_tq_artifact_payload_error(error, error_size,
            "artifact payload ContentRef shape rejected");
    }
    return 0;
}

static int pf_tq_artifact_payload_stat_equal(
    const struct stat *left,
    const struct stat *right
) {
    return left != NULL && right != NULL &&
        left->st_dev == right->st_dev &&
        left->st_ino == right->st_ino &&
        left->st_mode == right->st_mode &&
        left->st_uid == right->st_uid &&
        left->st_gid == right->st_gid &&
        left->st_nlink == right->st_nlink &&
        left->st_size == right->st_size &&
        left->st_mtim.tv_sec == right->st_mtim.tv_sec &&
        left->st_mtim.tv_nsec == right->st_mtim.tv_nsec &&
        left->st_ctim.tv_sec == right->st_ctim.tv_sec &&
        left->st_ctim.tv_nsec == right->st_ctim.tv_nsec;
}

static int pf_tq_artifact_payload_no_capability(
    int fd,
    char *error,
    size_t error_size
) {
    ssize_t amount;
    errno = 0;
    amount = fgetxattr(fd, "security.capability", NULL, 0U);
    if (amount >= 0 || errno != ENODATA) {
        return pf_tq_artifact_payload_error(error, error_size,
            "artifact payload security.capability absence rejected");
    }
    return 0;
}

static int pf_tq_artifact_payload_read_exact(
    int fd,
    unsigned char *bytes,
    size_t size,
    char *error,
    size_t error_size
) {
    size_t offset = 0U;
    unsigned char extra = 0U;
    while (offset < size) {
        ssize_t amount = pread(fd, bytes + offset, size - offset, (off_t)offset);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) {
            return pf_tq_artifact_payload_error(error, error_size,
                "artifact payload exact pread failed");
        }
        offset += (size_t)amount;
    }
    for (;;) {
        ssize_t amount = pread(fd, &extra, 1U, (off_t)size);
        if (amount < 0 && errno == EINTR) continue;
        if (amount != 0) {
            return pf_tq_artifact_payload_error(error, error_size,
                "artifact payload trailing-byte probe failed");
        }
        break;
    }
    return 0;
}

static int pf_tq_artifact_payload_digests(
    const pf_tq_wire_content_ref_v2 *reference,
    const unsigned char *bytes,
    size_t size,
    unsigned char plain_digest[32],
    unsigned char content_digest[32],
    char *error,
    size_t error_size
) {
    static const unsigned char zero = 0U;
    EVP_MD_CTX *plain = NULL;
    EVP_MD_CTX *content = NULL;
    unsigned int plain_size = 0U;
    unsigned int content_size = 0U;
    int result = -1;
    plain = EVP_MD_CTX_new();
    content = EVP_MD_CTX_new();
    if (plain == NULL || content == NULL ||
            EVP_DigestInit_ex(plain, EVP_sha256(), NULL) != 1 ||
            EVP_DigestUpdate(plain, bytes, size) != 1 ||
            EVP_DigestFinal_ex(plain, plain_digest, &plain_size) != 1 ||
            plain_size != 32U ||
            EVP_DigestInit_ex(content, EVP_sha256(), NULL) != 1 ||
            EVP_DigestUpdate(content, PF_TQ_ARTIFACT_PAYLOAD_V2_DOMAIN,
                strlen(PF_TQ_ARTIFACT_PAYLOAD_V2_DOMAIN)) != 1 ||
            EVP_DigestUpdate(content, &zero, 1U) != 1 ||
            EVP_DigestUpdate(content, reference->id,
                strlen(reference->id)) != 1 ||
            EVP_DigestUpdate(content, &zero, 1U) != 1 ||
            EVP_DigestUpdate(content, reference->version,
                strlen(reference->version)) != 1 ||
            EVP_DigestUpdate(content, &zero, 1U) != 1 ||
            EVP_DigestUpdate(content, bytes, size) != 1 ||
            EVP_DigestFinal_ex(content, content_digest, &content_size) != 1 ||
            content_size != 32U) {
        (void)pf_tq_artifact_payload_error(error, error_size,
            "artifact payload SHA-256 failed");
        goto cleanup;
    }
    result = 0;
cleanup:
    EVP_MD_CTX_free(content);
    EVP_MD_CTX_free(plain);
    return result;
}

int pf_tq_artifact_payload_verify_fd_v2(
    int fd,
    int expected_fd_flags,
    const pf_tq_wire_content_ref_v2 *expected_ref,
    pf_tq_artifact_payload_v2 *result,
    char *error,
    size_t error_size
) {
    pf_tq_artifact_payload_v2 payload;
    struct stat before;
    struct stat after;
    unsigned char content_digest[32];
    int descriptor_flags;
    int status_flags;
    int outcome = -1;
    memset(&payload, 0, sizeof(payload));
    memset(&before, 0, sizeof(before));
    memset(&after, 0, sizeof(after));
    memset(content_digest, 0, sizeof(content_digest));
    pf_tq_artifact_payload_clear_error(error, error_size);
    if (result != NULL) memset(result, 0, sizeof(*result));
    if (result == NULL || fd < 0 ||
            (expected_fd_flags != 0 && expected_fd_flags != FD_CLOEXEC)) {
        return pf_tq_artifact_payload_error(error, error_size,
            "artifact payload API arguments rejected");
    }
    if (pf_tq_artifact_payload_ref_shape(expected_ref,
            error, error_size) != 0) return -1;
    descriptor_flags = fcntl(fd, F_GETFD);
    status_flags = fcntl(fd, F_GETFL);
    if (descriptor_flags < 0 || descriptor_flags != expected_fd_flags ||
            status_flags < 0 ||
            (status_flags & O_ACCMODE) != O_RDONLY ||
            (status_flags & (O_APPEND | O_NONBLOCK | O_PATH)) != 0) {
        return pf_tq_artifact_payload_error(error, error_size,
            "artifact payload descriptor flags rejected");
    }
    if (fstat(fd, &before) != 0 || !S_ISREG(before.st_mode) ||
            before.st_nlink != 1 || before.st_size <= 0 ||
            (uint64_t)before.st_size >
                (uint64_t)PF_TQ_ARTIFACT_PAYLOAD_V2_MAX_BYTES ||
            (before.st_mode & (S_ISUID | S_ISGID)) != 0) {
        return pf_tq_artifact_payload_error(error, error_size,
            "artifact payload metadata rejected");
    }
    if (pf_tq_artifact_payload_no_capability(fd,
            error, error_size) != 0) return -1;
    payload.size = (size_t)before.st_size;
    payload.bytes = malloc(payload.size);
    if (payload.bytes == NULL) {
        (void)pf_tq_artifact_payload_error(error, error_size,
            "artifact payload allocation failed");
        goto cleanup;
    }
    if (pf_tq_artifact_payload_read_exact(fd, payload.bytes, payload.size,
            error, error_size) != 0 ||
            pf_tq_artifact_payload_no_capability(fd,
                error, error_size) != 0 ||
            fstat(fd, &after) != 0 ||
            !pf_tq_artifact_payload_stat_equal(&before, &after)) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_artifact_payload_error(error, error_size,
                "artifact payload changed during stable read");
        }
        goto cleanup;
    }
    if (pf_tq_artifact_payload_digests(expected_ref,
            payload.bytes, payload.size, payload.plain_sha256,
            content_digest, error, error_size) != 0 ||
            CRYPTO_memcmp(content_digest, expected_ref->digest, 32U) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_artifact_payload_error(error, error_size,
                "artifact payload ContentRef digest mismatch");
        }
        goto cleanup;
    }
    payload.device = (uint64_t)before.st_dev;
    payload.inode = (uint64_t)before.st_ino;
    payload.mode = (uint64_t)before.st_mode;
    payload.uid = before.st_uid;
    payload.gid = before.st_gid;
    *result = payload;
    memset(&payload, 0, sizeof(payload));
    pf_tq_artifact_payload_clear_error(error, error_size);
    outcome = 0;
cleanup:
    pf_tq_artifact_payload_free_v2(&payload);
    OPENSSL_cleanse(content_digest, sizeof(content_digest));
    return outcome;
}
