#define _GNU_SOURCE
#include "task_qualification_custody_transition_v2.h"
#include "task_qualification_pf_jcs_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/memfd.h>
#include <linux/magic.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <unistd.h>

#define PF_TQ_TRANSITION_MAX_SAFE UINT64_C(9007199254740991)
#define PF_TQ_TRANSITION_DIGEST_WIRE_BYTES 71U
#define PF_TQ_TRANSITION_SEALS \
    (F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)

struct pf_tq_transition_linux_dirent64 {
    uint64_t d_ino;
    int64_t d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[];
};

struct pf_tq_transition_scalar {
    unsigned char bytes[512];
    size_t size;
};

static const char *const pf_tq_transition_slots[PF_TQ_SEED_CUSTODY_V2_COUNT] = {
    "service", "role-0", "role-1", "role-2"
};

static int pf_tq_transition_error(
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

static void pf_tq_transition_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static bool pf_tq_transition_safe_u64(uint64_t value) {
    return value <= PF_TQ_TRANSITION_MAX_SAFE;
}

static bool pf_tq_transition_ascii_id(const char *value) {
    size_t index;
    size_t size = value == NULL ? 0U : strlen(value);
    if (size == 0U || size > 127U) return false;
    for (index = 0U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!((character >= 'A' && character <= 'Z') ||
                (character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9') ||
                character == '-' || character == '.' || character == '_')) {
            return false;
        }
    }
    return true;
}

static int pf_tq_transition_field_compare(const void *left, const void *right) {
    const pf_tq_jcs_field_v2 *a = left;
    const pf_tq_jcs_field_v2 *b = right;
    return strcmp(a->key, b->key);
}

static int pf_tq_transition_encode_fields(
    const pf_tq_jcs_field_v2 *fields,
    size_t field_count,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    pf_tq_jcs_field_v2 *sorted = NULL;
    unsigned char *bytes = NULL;
    size_t written = 0U;
    if (fields == NULL || field_count == 0U || output == NULL || output_size == NULL) {
        return pf_tq_transition_error(error, error_size,
            "transition object encoder arguments rejected");
    }
    sorted = malloc(field_count * sizeof(*sorted));
    bytes = malloc(PF_TQ_CUSTODY_TRANSITION_V2_MAX_BYTES);
    if (sorted == NULL || bytes == NULL) {
        free(sorted);
        free(bytes);
        return pf_tq_transition_error(error, error_size,
            "transition object encoder allocation failed");
    }
    memcpy(sorted, fields, field_count * sizeof(*sorted));
    qsort(sorted, field_count, sizeof(*sorted), pf_tq_transition_field_compare);
    if (pf_tq_jcs_encode_object_v2(sorted, field_count, bytes,
            PF_TQ_CUSTODY_TRANSITION_V2_MAX_BYTES, &written,
            error, error_size) != 0) {
        free(sorted);
        free(bytes);
        return -1;
    }
    free(sorted);
    *output = bytes;
    *output_size = written;
    return 0;
}

static int pf_tq_transition_scalar_string(
    struct pf_tq_transition_scalar *scalar,
    const char *value,
    char *error,
    size_t error_size
) {
    return pf_tq_jcs_encode_string_v2(value, scalar->bytes,
        sizeof(scalar->bytes), &scalar->size, error, error_size);
}

static int pf_tq_transition_scalar_uint(
    struct pf_tq_transition_scalar *scalar,
    uint64_t value,
    char *error,
    size_t error_size
) {
    return pf_tq_jcs_encode_uint_v2(value, scalar->bytes,
        sizeof(scalar->bytes), &scalar->size, error, error_size);
}

static void pf_tq_transition_hex(
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

static int pf_tq_transition_content_ref_validate(
    pf_tq_transition_bytes_v2 ref,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"digest", "id", "schema", "version"};
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    const pf_tq_jcs_node_v2 *node;
    char text[256];
    int result = -1;
    if (ref.bytes == NULL || ref.size == 0U || ref.size > 4096U ||
            pf_tq_jcs_parse_v2(ref.bytes, ref.size, &document,
                error, error_size) != 0) return -1;
    root = pf_tq_jcs_root_v2(&document);
    if (root == NULL || pf_tq_jcs_object_exact_v2(&document, root, fields, 4U,
            error, error_size) != 0) goto cleanup;
    node = pf_tq_jcs_object_get_v2(&document, root, "digest");
    if (pf_tq_jcs_copy_string_v2(&document, node, text, sizeof(text),
            error, error_size) != 0 || strlen(text) != 71U ||
            strncmp(text, "sha256:", 7U) != 0) goto cleanup;
    for (size_t index = 7U; index < 71U; ++index) {
        if (!((text[index] >= '0' && text[index] <= '9') ||
                (text[index] >= 'a' && text[index] <= 'f'))) goto cleanup;
    }
    for (size_t index = 1U; index < 4U; ++index) {
        node = pf_tq_jcs_object_get_v2(&document, root, fields[index]);
        if (pf_tq_jcs_copy_string_v2(&document, node, text, sizeof(text),
                error, error_size) != 0) goto cleanup;
    }
    result = 0;
cleanup:
    if (result != 0 && error != NULL && error_size > 0U && error[0] == '\0') {
        (void)pf_tq_transition_error(error, error_size,
            "service executable ContentRef rejected");
    }
    pf_tq_jcs_free_v2(&document);
    return result;
}

static int pf_tq_transition_encode_namespace(
    const pf_tq_transition_namespace_v2 *identity,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    struct pf_tq_transition_scalar device;
    struct pf_tq_transition_scalar inode;
    pf_tq_jcs_field_v2 fields[2];
    if (identity == NULL || !pf_tq_transition_safe_u64(identity->device) ||
            !pf_tq_transition_safe_u64(identity->inode) ||
            pf_tq_transition_scalar_uint(&device, identity->device,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&inode, identity->inode,
                error, error_size) != 0) return -1;
    fields[0] = (pf_tq_jcs_field_v2){"device", device.bytes, device.size};
    fields[1] = (pf_tq_jcs_field_v2){"inode", inode.bytes, inode.size};
    return pf_tq_transition_encode_fields(fields, 2U,
        output, output_size, error, error_size);
}

static int pf_tq_transition_encode_fd(
    const pf_tq_transition_fd_identity_v2 *identity,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    struct pf_tq_transition_scalar fd, device, inode, mode, flags;
    pf_tq_jcs_field_v2 fields[5];
    if (identity == NULL || identity->fd < 0 ||
            !pf_tq_transition_safe_u64((uint64_t)identity->fd) ||
            !pf_tq_transition_safe_u64(identity->device) ||
            !pf_tq_transition_safe_u64(identity->inode) ||
            !pf_tq_transition_safe_u64(identity->mode) ||
            (identity->fd_flags != 0 && identity->fd_flags != FD_CLOEXEC) ||
            pf_tq_transition_scalar_uint(&fd, (uint64_t)identity->fd,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&device, identity->device,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&inode, identity->inode,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&mode, identity->mode,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&flags, (uint64_t)identity->fd_flags,
                error, error_size) != 0) return -1;
    fields[0] = (pf_tq_jcs_field_v2){"fd", fd.bytes, fd.size};
    fields[1] = (pf_tq_jcs_field_v2){"device", device.bytes, device.size};
    fields[2] = (pf_tq_jcs_field_v2){"inode", inode.bytes, inode.size};
    fields[3] = (pf_tq_jcs_field_v2){"mode", mode.bytes, mode.size};
    fields[4] = (pf_tq_jcs_field_v2){"fdFlags", flags.bytes, flags.size};
    return pf_tq_transition_encode_fields(fields, 5U,
        output, output_size, error, error_size);
}

static int pf_tq_transition_encode_seed(
    const pf_tq_transition_seed_v2 *seed,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    struct pf_tq_transition_scalar slot, key, fd, device, inode;
    pf_tq_jcs_field_v2 fields[5];
    if (seed == NULL || !pf_tq_transition_ascii_id(seed->slot) ||
            !pf_tq_transition_ascii_id(seed->key_id) || seed->fd < 0 ||
            !pf_tq_transition_safe_u64((uint64_t)seed->fd) ||
            !pf_tq_transition_safe_u64(seed->device) ||
            !pf_tq_transition_safe_u64(seed->inode) ||
            pf_tq_transition_scalar_string(&slot, seed->slot,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_string(&key, seed->key_id,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&fd, (uint64_t)seed->fd,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&device, seed->device,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&inode, seed->inode,
                error, error_size) != 0) return -1;
    fields[0] = (pf_tq_jcs_field_v2){"slot", slot.bytes, slot.size};
    fields[1] = (pf_tq_jcs_field_v2){"keyId", key.bytes, key.size};
    fields[2] = (pf_tq_jcs_field_v2){"fd", fd.bytes, fd.size};
    fields[3] = (pf_tq_jcs_field_v2){"device", device.bytes, device.size};
    fields[4] = (pf_tq_jcs_field_v2){"inode", inode.bytes, inode.size};
    return pf_tq_transition_encode_fields(fields, 5U,
        output, output_size, error, error_size);
}

static int pf_tq_transition_seed_array(
    const pf_tq_transition_seed_v2 seeds[PF_TQ_SEED_CUSTODY_V2_COUNT],
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    unsigned char *objects[PF_TQ_SEED_CUSTODY_V2_COUNT] = {NULL, NULL, NULL, NULL};
    size_t sizes[PF_TQ_SEED_CUSTODY_V2_COUNT] = {0U, 0U, 0U, 0U};
    size_t total = 2U;
    size_t offset = 0U;
    size_t index;
    unsigned char *array = NULL;
    int result = -1;
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        if (pf_tq_transition_encode_seed(&seeds[index], &objects[index],
                &sizes[index], error, error_size) != 0) goto cleanup;
        if (sizes[index] > PF_TQ_CUSTODY_TRANSITION_V2_MAX_BYTES - total -
                (index > 0U ? 1U : 0U)) {
            (void)pf_tq_transition_error(error, error_size,
                "transition seed array size overflow");
            goto cleanup;
        }
        total += sizes[index] + (index > 0U ? 1U : 0U);
    }
    array = malloc(total);
    if (array == NULL) {
        (void)pf_tq_transition_error(error, error_size,
            "transition seed array allocation failed");
        goto cleanup;
    }
    array[offset++] = '[';
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        if (index > 0U) array[offset++] = ',';
        memcpy(array + offset, objects[index], sizes[index]);
        offset += sizes[index];
    }
    array[offset++] = ']';
    if (offset != total) {
        (void)pf_tq_transition_error(error, error_size,
            "transition seed array encoder mismatch");
        goto cleanup;
    }
    *output = array;
    *output_size = total;
    array = NULL;
    result = 0;
cleanup:
    free(array);
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        free(objects[index]);
    }
    return result;
}

static int pf_tq_transition_build(
    const pf_tq_custody_transition_data_v2 *data,
    unsigned char **output,
    size_t *output_size,
    char *error,
    size_t error_size
) {
    unsigned char *user_namespace = NULL;
    size_t user_namespace_size = 0U;
    unsigned char *pid_namespace = NULL;
    size_t pid_namespace_size = 0U;
    unsigned char *adapter_endpoint = NULL;
    size_t adapter_endpoint_size = 0U;
    unsigned char *service_endpoint = NULL;
    size_t service_endpoint_size = 0U;
    unsigned char *seeds = NULL;
    size_t seeds_size = 0U;
    char digest_text[PF_TQ_TRANSITION_DIGEST_WIRE_BYTES + 1U];
    struct pf_tq_transition_scalar schema, version, supervisor_pid, start_ticks;
    struct pf_tq_transition_scalar adapter_pid, executable_fd, executable_digest;
    pf_tq_jcs_field_v2 fields[13];
    int result = -1;
    if (pf_tq_transition_encode_namespace(&data->user_namespace,
            &user_namespace, &user_namespace_size, error, error_size) != 0 ||
            pf_tq_transition_encode_namespace(&data->pid_namespace,
                &pid_namespace, &pid_namespace_size, error, error_size) != 0 ||
            pf_tq_transition_encode_fd(&data->adapter_endpoint,
                &adapter_endpoint, &adapter_endpoint_size, error, error_size) != 0 ||
            pf_tq_transition_encode_fd(&data->service_endpoint,
                &service_endpoint, &service_endpoint_size, error, error_size) != 0 ||
            pf_tq_transition_seed_array(data->seeds, &seeds,
                &seeds_size, error, error_size) != 0 ||
            pf_tq_transition_scalar_string(&schema,
                "proof-forge.task-qualification-custody-transition.v2",
                error, error_size) != 0 ||
            pf_tq_transition_scalar_string(&version, "2.0.0",
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&supervisor_pid,
                (uint64_t)data->supervisor_pid, error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&start_ticks, data->start_time_ticks,
                error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&adapter_pid,
                (uint64_t)data->adapter_pid, error, error_size) != 0 ||
            pf_tq_transition_scalar_uint(&executable_fd,
                (uint64_t)data->service_executable_fd, error, error_size) != 0) {
        goto cleanup;
    }
    memcpy(digest_text, "sha256:", 7U);
    pf_tq_transition_hex(data->service_executable_payload_sha256, 32U,
        digest_text + 7U);
    if (pf_tq_transition_scalar_string(&executable_digest, digest_text,
            error, error_size) != 0) goto cleanup;
    fields[0] = (pf_tq_jcs_field_v2){"schema", schema.bytes, schema.size};
    fields[1] = (pf_tq_jcs_field_v2){"version", version.bytes, version.size};
    fields[2] = (pf_tq_jcs_field_v2){"supervisorPid", supervisor_pid.bytes, supervisor_pid.size};
    fields[3] = (pf_tq_jcs_field_v2){"startTimeTicks", start_ticks.bytes, start_ticks.size};
    fields[4] = (pf_tq_jcs_field_v2){"userNamespace", user_namespace, user_namespace_size};
    fields[5] = (pf_tq_jcs_field_v2){"pidNamespace", pid_namespace, pid_namespace_size};
    fields[6] = (pf_tq_jcs_field_v2){"adapterPid", adapter_pid.bytes, adapter_pid.size};
    fields[7] = (pf_tq_jcs_field_v2){"adapterEndpoint", adapter_endpoint, adapter_endpoint_size};
    fields[8] = (pf_tq_jcs_field_v2){"serviceEndpoint", service_endpoint, service_endpoint_size};
    fields[9] = (pf_tq_jcs_field_v2){"serviceExecutableFd", executable_fd.bytes, executable_fd.size};
    fields[10] = (pf_tq_jcs_field_v2){"serviceExecutable", data->service_executable_ref.bytes, data->service_executable_ref.size};
    fields[11] = (pf_tq_jcs_field_v2){"serviceExecutablePayloadSha256", executable_digest.bytes, executable_digest.size};
    fields[12] = (pf_tq_jcs_field_v2){"seeds", seeds, seeds_size};
    if (pf_tq_transition_encode_fields(fields, 13U, output, output_size,
            error, error_size) != 0) goto cleanup;
    result = 0;
cleanup:
    free(seeds);
    free(service_endpoint);
    free(adapter_endpoint);
    free(pid_namespace);
    free(user_namespace);
    return result;
}

static int pf_tq_transition_read_proc(
    int proc_root_fd,
    const char *path,
    unsigned char *bytes,
    size_t capacity,
    size_t *size,
    char *error,
    size_t error_size
) {
    size_t offset = 0U;
    int fd = openat(proc_root_fd, path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    int result = -1;
    if (fd < 0) {
        return pf_tq_transition_error(error, error_size,
            "transition proc openat failed for %s: %s", path, strerror(errno));
    }
    while (offset < capacity) {
        ssize_t amount = read(fd, bytes + offset, capacity - offset);
        if (amount < 0 && errno == EINTR) continue;
        if (amount < 0) {
            (void)pf_tq_transition_error(error, error_size,
                "transition proc read failed: %s", strerror(errno));
            goto cleanup;
        }
        if (amount == 0) break;
        offset += (size_t)amount;
    }
    if (offset == 0U || offset == capacity) {
        (void)pf_tq_transition_error(error, error_size,
            "transition proc entry empty/overbound");
        goto cleanup;
    }
    *size = offset;
    result = 0;
cleanup:
    if (close(fd) != 0 && result == 0) {
        return pf_tq_transition_error(error, error_size,
            "transition proc close failed: %s", strerror(errno));
    }
    return result;
}

static int pf_tq_transition_namespace_capture(
    int proc_root_fd,
    const char *path,
    pf_tq_transition_namespace_v2 *identity,
    char *error,
    size_t error_size
) {
    struct stat status;
    int fd = openat(proc_root_fd, path, O_RDONLY | O_CLOEXEC);
    int result = -1;
    if (fd < 0 || fstat(fd, &status) != 0) {
        if (fd >= 0) (void)close(fd);
        return pf_tq_transition_error(error, error_size,
            "transition namespace capture failed for %s: %s",
            path, strerror(errno));
    }
    if (!pf_tq_transition_safe_u64((uint64_t)status.st_dev) ||
            !pf_tq_transition_safe_u64((uint64_t)status.st_ino)) {
        (void)pf_tq_transition_error(error, error_size,
            "transition namespace identity exceeds safe integer");
        goto cleanup;
    }
    identity->device = (uint64_t)status.st_dev;
    identity->inode = (uint64_t)status.st_ino;
    result = 0;
cleanup:
    if (close(fd) != 0 && result == 0) {
        return pf_tq_transition_error(error, error_size,
            "transition namespace FD close failed: %s", strerror(errno));
    }
    return result;
}

int pf_tq_transition_capture_fd_v2(
    int fd,
    pf_tq_transition_fd_identity_v2 *identity,
    char *error,
    size_t error_size
) {
    struct stat status;
    int flags;
    pf_tq_transition_clear_error(error, error_size);
    if (identity != NULL) memset(identity, 0, sizeof(*identity));
    if (fd < 0 || identity == NULL || fstat(fd, &status) != 0 ||
            (flags = fcntl(fd, F_GETFD)) < 0) {
        return pf_tq_transition_error(error, error_size,
            "transition FD identity capture failed: %s", strerror(errno));
    }
    if (!pf_tq_transition_safe_u64((uint64_t)fd) ||
            !pf_tq_transition_safe_u64((uint64_t)status.st_dev) ||
            !pf_tq_transition_safe_u64((uint64_t)status.st_ino) ||
            !pf_tq_transition_safe_u64((uint64_t)status.st_mode) ||
            (flags != 0 && flags != FD_CLOEXEC)) {
        return pf_tq_transition_error(error, error_size,
            "transition FD identity values rejected");
    }
    identity->fd = fd;
    identity->device = (uint64_t)status.st_dev;
    identity->inode = (uint64_t)status.st_ino;
    identity->mode = (uint64_t)status.st_mode;
    identity->fd_flags = flags;
    return 0;
}

int pf_tq_transition_validate_fd_roles_v2(
    int proc_root_fd,
    const pf_tq_transition_fd_role_v2 *roles,
    size_t role_count,
    char *error,
    size_t error_size
) {
    unsigned char buffer[4096];
    unsigned char seen[256];
    char path[64];
    int directory_fd = -1;
    int result = -1;
    size_t index;
    pf_tq_transition_clear_error(error, error_size);
    if (proc_root_fd < 0 || roles == NULL || role_count == 0U ||
            role_count > sizeof(seen) || snprintf(path, sizeof(path),
                "%ld/fd", (long)getpid()) <= 0) {
        return pf_tq_transition_error(error, error_size,
            "transition FD-role arguments/path rejected");
    }
    memset(seen, 0, sizeof(seen));
    for (index = 0U; index < role_count; ++index) {
        if (roles[index].fd < 0 ||
                (roles[index].fd_flags != 0 &&
                 roles[index].fd_flags != FD_CLOEXEC) ||
                (index > 0U && roles[index - 1U].fd >= roles[index].fd)) {
            return pf_tq_transition_error(error, error_size,
                "transition FD-role set is not strictly sorted/valid");
        }
    }
    directory_fd = openat(proc_root_fd, path,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory_fd < 0) {
        return pf_tq_transition_error(error, error_size,
            "transition FD-role proc enumeration open failed: %s",
            strerror(errno));
    }
    for (;;) {
        ssize_t amount = syscall(SYS_getdents64,
            directory_fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (amount < 0) {
            (void)pf_tq_transition_error(error, error_size,
                "transition FD-role getdents64 failed: %s", strerror(errno));
            goto cleanup;
        }
        if (amount == 0) break;
        while (offset < (size_t)amount) {
            const struct pf_tq_transition_linux_dirent64 *entry =
                (const struct pf_tq_transition_linux_dirent64 *)(const void *)(
                    buffer + offset);
            size_t minimum = offsetof(
                struct pf_tq_transition_linux_dirent64, d_name) + 1U;
            size_t name_capacity;
            const char *terminator;
            uint64_t number = 0U;
            size_t cursor;
            bool matched = false;
            if (entry->d_reclen < minimum ||
                    entry->d_reclen > (size_t)amount - offset) {
                (void)pf_tq_transition_error(error, error_size,
                    "transition FD-role directory record malformed");
                goto cleanup;
            }
            name_capacity = entry->d_reclen - offsetof(
                struct pf_tq_transition_linux_dirent64, d_name);
            terminator = memchr(entry->d_name, '\0', name_capacity);
            if (terminator == NULL || entry->d_ino == 0U) {
                (void)pf_tq_transition_error(error, error_size,
                    "transition FD-role directory name/inode malformed");
                goto cleanup;
            }
            if (strcmp(entry->d_name, ".") == 0 ||
                    strcmp(entry->d_name, "..") == 0) {
                offset += entry->d_reclen;
                continue;
            }
            if (entry->d_name[0] == '\0' ||
                    (entry->d_name[0] == '0' && entry->d_name[1] != '\0')) {
                (void)pf_tq_transition_error(error, error_size,
                    "transition FD-role name is not canonical decimal");
                goto cleanup;
            }
            for (cursor = 0U; entry->d_name[cursor] != '\0'; ++cursor) {
                unsigned digit;
                if (entry->d_name[cursor] < '0' ||
                        entry->d_name[cursor] > '9') {
                    (void)pf_tq_transition_error(error, error_size,
                        "transition FD-role name is not decimal");
                    goto cleanup;
                }
                digit = (unsigned)(entry->d_name[cursor] - '0');
                if (number > ((uint64_t)INT_MAX - digit) / 10U) {
                    (void)pf_tq_transition_error(error, error_size,
                        "transition FD-role number exceeds int");
                    goto cleanup;
                }
                number = number * 10U + digit;
            }
            if ((int)number == directory_fd) {
                offset += entry->d_reclen;
                continue;
            }
            for (index = 0U; index < role_count; ++index) {
                if (roles[index].fd == (int)number) {
                    if (seen[index] != 0U) {
                        (void)pf_tq_transition_error(error, error_size,
                            "transition FD-role appears more than once");
                        goto cleanup;
                    }
                    seen[index] = 1U;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                (void)pf_tq_transition_error(error, error_size,
                    "transition process contains an unexpected FD");
                goto cleanup;
            }
            offset += entry->d_reclen;
        }
    }
    for (index = 0U; index < role_count; ++index) {
        if (seen[index] != 1U) {
            (void)pf_tq_transition_error(error, error_size,
                "transition process is missing an expected FD");
            goto cleanup;
        }
    }
    result = 0;
cleanup:
    if (close(directory_fd) != 0 && result == 0) {
        return pf_tq_transition_error(error, error_size,
            "transition FD-role directory close failed: %s", strerror(errno));
    }
    if (result == 0) {
        for (index = 0U; index < role_count; ++index) {
            if (fcntl(roles[index].fd, F_GETFD) != roles[index].fd_flags) {
                return pf_tq_transition_error(error, error_size,
                    "transition FD-role closeOnExec flags mismatch");
            }
        }
    }
    return result;
}

int pf_tq_transition_self_identity_v2(
    int proc_root_fd,
    pid_t *pid,
    uint64_t *start_time_ticks,
    pf_tq_transition_namespace_v2 *user_namespace,
    pf_tq_transition_namespace_v2 *pid_namespace,
    char *error,
    size_t error_size
) {
    unsigned char bytes[4096];
    size_t size = 0U;
    size_t close = 0U;
    size_t cursor;
    unsigned field = 3U;
    struct statfs filesystem;
    pf_tq_transition_clear_error(error, error_size);
    if (pid == NULL || start_time_ticks == NULL || user_namespace == NULL ||
            pid_namespace == NULL || proc_root_fd < 0) {
        return pf_tq_transition_error(error, error_size,
            "transition self-identity arguments rejected");
    }
    if (fstatfs(proc_root_fd, &filesystem) != 0 ||
            filesystem.f_type != PROC_SUPER_MAGIC ||
            pf_tq_transition_read_proc(proc_root_fd, "self/stat", bytes,
                sizeof(bytes), &size, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_transition_error(error, error_size,
                "transition procRoot/self identity rejected");
        }
        return -1;
    }
    for (cursor = 0U; cursor < size; ++cursor) {
        if (bytes[cursor] == ')') close = cursor;
    }
    if (close == 0U || close + 2U >= size || bytes[close + 1U] != ' ') {
        return pf_tq_transition_error(error, error_size,
            "transition /proc/self/stat comm delimiter rejected");
    }
    cursor = close + 2U;
    while (field <= 22U) {
        size_t start;
        uint64_t value = 0U;
        while (cursor < size && bytes[cursor] == ' ') ++cursor;
        start = cursor;
        while (cursor < size && bytes[cursor] != ' ' && bytes[cursor] != '\n') {
            ++cursor;
        }
        if (start == cursor) {
            return pf_tq_transition_error(error, error_size,
                "transition /proc/self/stat field is empty");
        }
        if (field == 22U) {
            for (size_t index = start; index < cursor; ++index) {
                unsigned digit;
                if (bytes[index] < '0' || bytes[index] > '9') {
                    return pf_tq_transition_error(error, error_size,
                        "transition start-time field is not decimal");
                }
                digit = (unsigned)(bytes[index] - '0');
                if (value > (PF_TQ_TRANSITION_MAX_SAFE - digit) / 10U) {
                    return pf_tq_transition_error(error, error_size,
                        "transition start-time exceeds safe integer");
                }
                value = value * 10U + digit;
            }
            *start_time_ticks = value;
        }
        ++field;
    }
    *pid = getpid();
    if (*pid <= 0 || !pf_tq_transition_safe_u64((uint64_t)*pid)) {
        return pf_tq_transition_error(error, error_size,
            "transition self PID rejected");
    }
    if (pf_tq_transition_namespace_capture(proc_root_fd, "self/ns/user",
                user_namespace, error, error_size) != 0 ||
            pf_tq_transition_namespace_capture(proc_root_fd, "self/ns/pid",
                pid_namespace, error, error_size) != 0) return -1;
    return 0;
}

static bool pf_tq_transition_namespace_equal(
    const pf_tq_transition_namespace_v2 *left,
    const pf_tq_transition_namespace_v2 *right
) {
    return left->device == right->device && left->inode == right->inode;
}

static bool pf_tq_transition_fd_equal(
    const pf_tq_transition_fd_identity_v2 *left,
    const pf_tq_transition_fd_identity_v2 *right
) {
    return left->fd == right->fd && left->device == right->device &&
        left->inode == right->inode && left->mode == right->mode &&
        left->fd_flags == right->fd_flags;
}

static int pf_tq_transition_data_validate(
    int transition_fd,
    int proc_root_fd,
    const pf_tq_custody_transition_data_v2 *data,
    int creation,
    char *error,
    size_t error_size
) {
    pid_t pid;
    uint64_t start_ticks;
    pf_tq_transition_namespace_v2 user_namespace;
    pf_tq_transition_namespace_v2 pid_namespace;
    pf_tq_transition_fd_identity_v2 service_endpoint;
    size_t index;
    size_t other;
    if (data == NULL || transition_fd <= 2 || proc_root_fd < 0 ||
            transition_fd == proc_root_fd || data->supervisor_pid <= 0 ||
            data->adapter_pid <= 0 || data->adapter_pid == data->supervisor_pid ||
            data->service_executable_fd <= 2 ||
            data->service_executable_fd == transition_fd ||
            data->service_executable_fd == proc_root_fd) {
        return pf_tq_transition_error(error, error_size,
            "transition basic PID/FD configuration rejected");
    }
    if (pf_tq_transition_content_ref_validate(data->service_executable_ref,
            error, error_size) != 0 ||
            pf_tq_transition_self_identity_v2(proc_root_fd, &pid, &start_ticks,
                &user_namespace, &pid_namespace, error, error_size) != 0) return -1;
    if (pid != data->supervisor_pid || start_ticks != data->start_time_ticks ||
            !pf_tq_transition_namespace_equal(
                &user_namespace, &data->user_namespace) ||
            !pf_tq_transition_namespace_equal(
                &pid_namespace, &data->pid_namespace)) {
        return pf_tq_transition_error(error, error_size,
            "transition self PID/start-time/namespace identity mismatch");
    }
    if (data->adapter_endpoint.fd <= 2 || data->service_endpoint.fd <= 2 ||
            data->adapter_endpoint.fd == data->service_endpoint.fd ||
            data->adapter_endpoint.fd == transition_fd ||
            data->service_endpoint.fd == transition_fd ||
            data->adapter_endpoint.fd == proc_root_fd ||
            data->service_endpoint.fd == proc_root_fd ||
            data->adapter_endpoint.fd == data->service_executable_fd ||
            data->service_endpoint.fd == data->service_executable_fd ||
            data->adapter_endpoint.fd_flags != 0 ||
            data->service_endpoint.fd_flags != 0 ||
            (data->adapter_endpoint.mode & S_IFMT) != S_IFSOCK ||
            (data->service_endpoint.mode & S_IFMT) != S_IFSOCK ||
            (data->adapter_endpoint.device == data->service_endpoint.device &&
             data->adapter_endpoint.inode == data->service_endpoint.inode)) {
        return pf_tq_transition_error(error, error_size,
            "transition socket endpoint identities rejected");
    }
    if (pf_tq_transition_capture_fd_v2(data->service_endpoint.fd,
            &service_endpoint, error, error_size) != 0 ||
            !pf_tq_transition_fd_equal(
                &service_endpoint, &data->service_endpoint)) {
        return pf_tq_transition_error(error, error_size,
            "transition service endpoint no longer matches runtime FD");
    }
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        pf_tq_transition_fd_identity_v2 seed_fd;
        const pf_tq_transition_seed_v2 *seed = &data->seeds[index];
        struct stat status;
        int open_flags;
        if (seed->slot == NULL || strcmp(seed->slot,
                pf_tq_transition_slots[index]) != 0 ||
                !pf_tq_transition_ascii_id(seed->key_id) || seed->fd <= 2 ||
                seed->fd == transition_fd || seed->fd == proc_root_fd ||
                seed->fd == data->adapter_endpoint.fd ||
                seed->fd == data->service_endpoint.fd ||
                seed->fd == data->service_executable_fd ||
                pf_tq_transition_capture_fd_v2(seed->fd, &seed_fd,
                    error, error_size) != 0 || seed_fd.fd_flags != 0 ||
                fstat(seed->fd, &status) != 0 || !S_ISREG(status.st_mode) ||
                (status.st_mode & 07777U) != 0400U || status.st_nlink != 1U ||
                (open_flags = fcntl(seed->fd, F_GETFL)) < 0 ||
                (open_flags & O_ACCMODE) != O_RDONLY ||
                seed_fd.device != seed->device || seed_fd.inode != seed->inode) {
            return pf_tq_transition_error(error, error_size,
                "transition inherited seed FD identity rejected at %zu", index);
        }
        if ((index == 0U && strcmp(seed->key_id, "service") != 0) ||
                (index > 0U && strcmp(seed->key_id, "service") == 0) ||
                (index > 1U && strcmp(data->seeds[index - 1U].key_id,
                    seed->key_id) >= 0)) {
            return pf_tq_transition_error(error, error_size,
                "transition seed slot/key order rejected");
        }
        for (other = 0U; other < index; ++other) {
            if (data->seeds[other].fd == seed->fd ||
                    (data->seeds[other].device == seed->device &&
                     data->seeds[other].inode == seed->inode)) {
                return pf_tq_transition_error(error, error_size,
                    "transition seed FD/inode reuse rejected");
            }
        }
    }
    if (creation) {
        struct stat executable;
        int flags = fcntl(data->service_executable_fd, F_GETFD);
        int open_flags = fcntl(data->service_executable_fd, F_GETFL);
        if (fstat(data->service_executable_fd, &executable) != 0 ||
                !S_ISREG(executable.st_mode) || executable.st_nlink != 1U ||
                (executable.st_mode & (S_ISUID | S_ISGID)) != 0 ||
                flags != FD_CLOEXEC || open_flags < 0 ||
                (open_flags & O_ACCMODE) != O_RDONLY) {
            return pf_tq_transition_error(error, error_size,
                "transition service executable FD identity rejected");
        }
    } else {
        errno = 0;
        if (fcntl(data->service_executable_fd, F_GETFD) != -1 || errno != EBADF) {
            return pf_tq_transition_error(error, error_size,
                "serviceExecutableFd was not closed by successful exec");
        }
    }
    return 0;
}

static int pf_tq_transition_memfd_validate(
    int fd,
    struct stat *status,
    char *error,
    size_t error_size
) {
    int flags;
    int seals;
    if (fstat(fd, status) != 0 || !S_ISREG(status->st_mode) ||
            status->st_uid != geteuid() || status->st_gid != getegid() ||
            status->st_nlink != 0U || status->st_size <= 0 ||
            status->st_size > (off_t)PF_TQ_CUSTODY_TRANSITION_V2_MAX_BYTES ||
            (flags = fcntl(fd, F_GETFD)) != 0 ||
            (seals = fcntl(fd, F_GET_SEALS)) != PF_TQ_TRANSITION_SEALS) {
        return pf_tq_transition_error(error, error_size,
            "sealed transition memfd identity/size/flags/seals rejected");
    }
    return 0;
}

int pf_tq_custody_transition_create_v2(
    int transition_fd,
    int proc_root_fd,
    const pf_tq_custody_transition_data_v2 *data,
    char *error,
    size_t error_size
) {
    unsigned char *bytes = NULL;
    size_t size = 0U;
    struct stat status;
    int fd = -1;
    int result = -1;
    pf_tq_transition_clear_error(error, error_size);
    errno = 0;
    if (transition_fd <= 2 || fcntl(transition_fd, F_GETFD) != -1 ||
            errno != EBADF) {
        (void)pf_tq_transition_error(error, error_size,
            "policy-fixed transition FD is not initially unused");
        goto cleanup;
    }
    if (pf_tq_transition_data_validate(transition_fd,
            proc_root_fd, data, 1, error, error_size) != 0 ||
            pf_tq_transition_build(data, &bytes, &size,
                error, error_size) != 0) goto cleanup;
    fd = (int)syscall(SYS_memfd_create,
        "pf-tq-custody-transition", MFD_ALLOW_SEALING);
    if (fd < 0) {
        (void)pf_tq_transition_error(error, error_size,
            "transition memfd_create failed: %s", strerror(errno));
        goto cleanup;
    }
    if (fd != transition_fd) {
        (void)pf_tq_transition_error(error, error_size,
            "transition memfd did not return policy-fixed FD");
        goto cleanup;
    }
    if (pwrite(fd, bytes, size, 0) != (ssize_t)size || fsync(fd) != 0 ||
            fcntl(fd, F_ADD_SEALS, PF_TQ_TRANSITION_SEALS) != 0 ||
            pf_tq_transition_memfd_validate(fd, &status,
                error, error_size) != 0 || status.st_size != (off_t)size) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_transition_error(error, error_size,
                "transition write/fsync/seal failed: %s", strerror(errno));
        }
        goto cleanup;
    }
    result = 0;
cleanup:
    free(bytes);
    if (result != 0 && fd >= 0) (void)close(fd);
    return result;
}

static int pf_tq_transition_wire_validate(
    const unsigned char *bytes,
    size_t size,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "adapterEndpoint", "adapterPid", "pidNamespace", "schema", "seeds",
        "serviceEndpoint", "serviceExecutable", "serviceExecutableFd",
        "serviceExecutablePayloadSha256", "startTimeTicks", "supervisorPid",
        "userNamespace", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root;
    int result = -1;
    if (pf_tq_jcs_parse_v2(bytes, size, &document,
            error, error_size) != 0) return -1;
    root = pf_tq_jcs_root_v2(&document);
    if (root != NULL && pf_tq_jcs_object_exact_v2(&document, root, fields,
            sizeof(fields) / sizeof(fields[0]), error, error_size) == 0 &&
            pf_tq_jcs_string_equal_v2(&document,
                pf_tq_jcs_object_get_v2(&document, root, "schema"),
                "proof-forge.task-qualification-custody-transition.v2") &&
            pf_tq_jcs_string_equal_v2(&document,
                pf_tq_jcs_object_get_v2(&document, root, "version"), "2.0.0")) {
        result = 0;
    }
    if (result != 0 && error != NULL && error_size > 0U && error[0] == '\0') {
        (void)pf_tq_transition_error(error, error_size,
            "transition wire schema/version rejected");
    }
    pf_tq_jcs_free_v2(&document);
    return result;
}

int pf_tq_custody_transition_consume_v2(
    int transition_fd,
    int proc_root_fd,
    const pf_tq_custody_transition_data_v2 *expected,
    char *error,
    size_t error_size
) {
    unsigned char *actual = NULL;
    unsigned char *expected_bytes = NULL;
    size_t expected_size = 0U;
    struct stat status;
    ssize_t amount;
    int result = -1;
    pf_tq_transition_clear_error(error, error_size);
    if (transition_fd <= 2 || pf_tq_transition_memfd_validate(
            transition_fd, &status, error, error_size) != 0 ||
            pf_tq_transition_data_validate(transition_fd, proc_root_fd,
                expected, 0, error, error_size) != 0 ||
            pf_tq_transition_build(expected, &expected_bytes, &expected_size,
                error, error_size) != 0) goto cleanup;
    actual = malloc((size_t)status.st_size);
    if (actual == NULL) {
        (void)pf_tq_transition_error(error, error_size,
            "transition read allocation failed");
        goto cleanup;
    }
    amount = pread(transition_fd, actual, (size_t)status.st_size, 0);
    if (amount != status.st_size || expected_size != (size_t)status.st_size ||
            pf_tq_transition_wire_validate(actual, (size_t)status.st_size,
                error, error_size) != 0 ||
            memcmp(actual, expected_bytes, expected_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_transition_error(error, error_size,
                "sealed transition bytes do not match reconstructed runtime facts");
        }
        goto cleanup;
    }
    result = 0;
cleanup:
    free(expected_bytes);
    free(actual);
    if (transition_fd >= 0 && close(transition_fd) != 0 && result == 0) {
        return pf_tq_transition_error(error, error_size,
            "transition FD close failed: %s", strerror(errno));
    }
    return result;
}
