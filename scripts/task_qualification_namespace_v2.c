#define _GNU_SOURCE
#include "task_qualification_namespace_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/magic.h>
#include <linux/mount.h>
#include <limits.h>
#include <sched.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef ST_NODEV
#define ST_NODEV 4
#endif
#ifndef ST_NOEXEC
#define ST_NOEXEC 8
#endif

#define PF_TQ_NAMESPACE_SAFE_INTEGER 9007199254740991ULL
#define PF_TQ_NAMESPACE_MAP_BYTES 512U
#define PF_TQ_NAMESPACE_SETGROUPS_BYTES 32U
#define PF_TQ_NAMESPACE_ROOT_FLAGS \
    ((unsigned long)(ST_RDONLY | ST_NOSUID | ST_NODEV | ST_NOEXEC))

static int pf_tq_namespace_error(
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

static void pf_tq_namespace_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static bool pf_tq_namespace_identity_equal(
    const pf_tq_namespace_identity_v2 *left,
    const pf_tq_namespace_identity_v2 *right
) {
    return left->device == right->device && left->inode == right->inode;
}

static int pf_tq_namespace_identity_fd(
    int fd,
    pf_tq_namespace_identity_v2 *result,
    char *error,
    size_t error_size
) {
    struct stat metadata;
    uint64_t device;
    uint64_t inode;
    if (fstat(fd, &metadata) != 0) {
        return pf_tq_namespace_error(error, error_size,
            "namespace fstat failed: %s", strerror(errno));
    }
    device = (uint64_t)metadata.st_dev;
    inode = (uint64_t)metadata.st_ino;
    if (device == 0U || inode == 0U ||
            device > PF_TQ_NAMESPACE_SAFE_INTEGER ||
            inode > PF_TQ_NAMESPACE_SAFE_INTEGER) {
        return pf_tq_namespace_error(error, error_size,
            "namespace identity is outside PF-JCS safe integers");
    }
    result->device = device;
    result->inode = inode;
    return 0;
}

static int pf_tq_namespace_identity_path(
    int proc_root_fd,
    const char *path,
    pf_tq_namespace_identity_v2 *result,
    char *error,
    size_t error_size
) {
    int fd = openat(proc_root_fd, path, O_RDONLY | O_CLOEXEC);
    int status;
    if (fd < 0) {
        return pf_tq_namespace_error(error, error_size,
            "namespace open %s failed: %s", path, strerror(errno));
    }
    status = pf_tq_namespace_identity_fd(fd, result, error, error_size);
    if (close(fd) != 0 && status == 0) {
        return pf_tq_namespace_error(error, error_size,
            "namespace close %s failed: %s", path, strerror(errno));
    }
    return status;
}

static int pf_tq_namespace_capture_prefix(
    int proc_root_fd,
    const char *prefix,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const names[] = {"user", "pid", "mnt"};
    pf_tq_namespace_identity_v2 *outputs[] = {
        &result->user_namespace,
        &result->pid_namespace,
        &result->mount_namespace,
    };
    size_t index;
    for (index = 0U; index < sizeof(names) / sizeof(names[0]); ++index) {
        char path[64];
        int amount = snprintf(path, sizeof(path), "%s/ns/%s", prefix, names[index]);
        if (amount < 0 || (size_t)amount >= sizeof(path) ||
                pf_tq_namespace_identity_path(proc_root_fd, path,
                    outputs[index], error, error_size) != 0) return -1;
    }
    return 0;
}

static int pf_tq_namespace_proc_validate(
    int proc_root_fd,
    char *error,
    size_t error_size
) {
    struct stat metadata;
    struct statfs filesystem;
    if (proc_root_fd <= 2 || fstat(proc_root_fd, &metadata) != 0 ||
            !S_ISDIR(metadata.st_mode) || fstatfs(proc_root_fd, &filesystem) != 0 ||
            (unsigned long)filesystem.f_type != (unsigned long)PROC_SUPER_MAGIC) {
        return pf_tq_namespace_error(error, error_size,
            "pinned proc root descriptor rejected");
    }
    if (((unsigned long)filesystem.f_flags & PF_TQ_NAMESPACE_ROOT_FLAGS) !=
            PF_TQ_NAMESPACE_ROOT_FLAGS) {
        return pf_tq_namespace_error(error, error_size,
            "pinned proc root is not readonly/nosuid/nodev/noexec");
    }
    return 0;
}

static int pf_tq_namespace_root_validate(
    char *error,
    size_t error_size
) {
    struct statfs filesystem;
    if (statfs("/", &filesystem) != 0 ||
            (unsigned long)filesystem.f_type != (unsigned long)TMPFS_MAGIC) {
        return pf_tq_namespace_error(error, error_size,
            "isolated root is not tmpfs");
    }
    if (((unsigned long)filesystem.f_flags & PF_TQ_NAMESPACE_ROOT_FLAGS) !=
            PF_TQ_NAMESPACE_ROOT_FLAGS) {
        return pf_tq_namespace_error(error, error_size,
            "isolated root is not readonly/nosuid/nodev/noexec");
    }
    return 0;
}

static int pf_tq_namespace_read_fixed(
    int proc_root_fd,
    const char *path,
    unsigned char *bytes,
    size_t capacity,
    size_t *size,
    char *error,
    size_t error_size
) {
    struct stat before;
    struct stat after;
    size_t offset = 0U;
    unsigned char extra;
    int fd = openat(proc_root_fd, path,
        O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    int status = -1;
    if (fd < 0 || fstat(fd, &before) != 0 || !S_ISREG(before.st_mode)) {
        if (fd >= 0) (void)close(fd);
        return pf_tq_namespace_error(error, error_size,
            "proc scalar open/fstat %s failed", path);
    }
    while (offset < capacity) {
        ssize_t amount = read(fd, bytes + offset, capacity - offset);
        if (amount < 0) {
            if (errno == EINTR) continue;
            (void)pf_tq_namespace_error(error, error_size,
                "proc scalar read %s failed: %s", path, strerror(errno));
            goto cleanup;
        }
        if (amount == 0) break;
        offset += (size_t)amount;
    }
    if (offset == capacity) {
        ssize_t amount;
        do {
            amount = read(fd, &extra, 1U);
        } while (amount < 0 && errno == EINTR);
        if (amount != 0) {
            (void)pf_tq_namespace_error(error, error_size,
                "proc scalar %s exceeds fixed bound", path);
            goto cleanup;
        }
    }
    if (fstat(fd, &after) != 0 || before.st_dev != after.st_dev ||
            before.st_ino != after.st_ino || before.st_mode != after.st_mode) {
        (void)pf_tq_namespace_error(error, error_size,
            "proc scalar %s identity changed", path);
        goto cleanup;
    }
    *size = offset;
    status = 0;
cleanup:
    if (close(fd) != 0 && status == 0) {
        return pf_tq_namespace_error(error, error_size,
            "proc scalar close %s failed: %s", path, strerror(errno));
    }
    return status;
}

static int pf_tq_namespace_decimal(
    const unsigned char *bytes,
    size_t size,
    size_t *offset,
    uint32_t *value,
    char *error,
    size_t error_size
) {
    uint64_t result = 0U;
    size_t start = *offset;
    while (*offset < size && bytes[*offset] >= '0' && bytes[*offset] <= '9') {
        unsigned digit = (unsigned)(bytes[*offset] - '0');
        if (result > (UINT32_MAX - digit) / 10U) {
            return pf_tq_namespace_error(error, error_size,
                "namespace map integer overflows uint32");
        }
        result = result * 10U + digit;
        ++*offset;
    }
    if (*offset == start) {
        return pf_tq_namespace_error(error, error_size,
            "namespace map integer is missing");
    }
    *value = (uint32_t)result;
    return 0;
}

static void pf_tq_namespace_skip_horizontal(
    const unsigned char *bytes,
    size_t size,
    size_t *offset
) {
    while (*offset < size && (bytes[*offset] == ' ' || bytes[*offset] == '\t')) {
        ++*offset;
    }
}

static int pf_tq_namespace_map_parse(
    const unsigned char *bytes,
    size_t size,
    pf_tq_namespace_id_map_entry_v2 output[2],
    char *error,
    size_t error_size
) {
    size_t offset = 0U;
    size_t row;
    for (row = 0U; row < 2U; ++row) {
        uint32_t length;
        pf_tq_namespace_skip_horizontal(bytes, size, &offset);
        if (pf_tq_namespace_decimal(bytes, size, &offset,
                &output[row].inside_id, error, error_size) != 0) return -1;
        if (offset >= size || (bytes[offset] != ' ' && bytes[offset] != '\t')) {
            return pf_tq_namespace_error(error, error_size,
                "namespace map field separator is missing");
        }
        pf_tq_namespace_skip_horizontal(bytes, size, &offset);
        if (pf_tq_namespace_decimal(bytes, size, &offset,
                &output[row].outside_id, error, error_size) != 0) return -1;
        if (offset >= size || (bytes[offset] != ' ' && bytes[offset] != '\t')) {
            return pf_tq_namespace_error(error, error_size,
                "namespace map length separator is missing");
        }
        pf_tq_namespace_skip_horizontal(bytes, size, &offset);
        if (pf_tq_namespace_decimal(bytes, size, &offset,
                &length, error, error_size) != 0 || length != 1U) {
            return pf_tq_namespace_error(error, error_size,
                "namespace map length is not one");
        }
        pf_tq_namespace_skip_horizontal(bytes, size, &offset);
        if (offset >= size || bytes[offset] != '\n') {
            return pf_tq_namespace_error(error, error_size,
                "namespace map row is not LF-terminated");
        }
        ++offset;
    }
    if (offset != size) {
        return pf_tq_namespace_error(error, error_size,
            "namespace map does not contain exactly two rows");
    }
    return 0;
}

static int pf_tq_namespace_map_input_validate(
    const pf_tq_namespace_id_map_entry_v2 uid_map[2],
    const pf_tq_namespace_id_map_entry_v2 gid_map[2],
    char *error,
    size_t error_size
) {
    const pf_tq_namespace_id_map_entry_v2 *maps[] = {uid_map, gid_map};
    uint32_t outside[4];
    size_t map_index;
    size_t cursor = 0U;
    if (uid_map == NULL || gid_map == NULL) {
        return pf_tq_namespace_error(error, error_size,
            "namespace expected maps are missing");
    }
    for (map_index = 0U; map_index < 2U; ++map_index) {
        size_t row;
        if (maps[map_index][0].inside_id >= maps[map_index][1].inside_id) {
            return pf_tq_namespace_error(error, error_size,
                "namespace expected map is not inside-ID sorted unique");
        }
        for (row = 0U; row < 2U; ++row) {
            uint32_t inside = maps[map_index][row].inside_id;
            uint32_t host = maps[map_index][row].outside_id;
            if (inside == 0U || inside > INT32_MAX || inside == 65534U ||
                    host == 0U || host == 65534U) {
                return pf_tq_namespace_error(error, error_size,
                    "namespace expected map contains reserved identity");
            }
            outside[cursor++] = host;
        }
    }
    for (map_index = 0U; map_index < 4U; ++map_index) {
        size_t right;
        for (right = map_index + 1U; right < 4U; ++right) {
            if (outside[map_index] == outside[right]) {
                return pf_tq_namespace_error(error, error_size,
                    "namespace outside subordinate IDs are not distinct");
            }
        }
    }
    return 0;
}

int pf_tq_namespace_validate_maps_v2(
    int proc_root_fd,
    const pf_tq_namespace_id_map_entry_v2 uid_map[2],
    const pf_tq_namespace_id_map_entry_v2 gid_map[2],
    char *error,
    size_t error_size
) {
    static const char *const paths[] = {"self/uid_map", "self/gid_map"};
    const pf_tq_namespace_id_map_entry_v2 *expected[] = {uid_map, gid_map};
    unsigned char bytes[PF_TQ_NAMESPACE_MAP_BYTES];
    size_t index;
    pf_tq_namespace_clear_error(error, error_size);
    if (pf_tq_namespace_proc_validate(proc_root_fd, error, error_size) != 0 ||
            pf_tq_namespace_map_input_validate(uid_map, gid_map,
                error, error_size) != 0) return -1;
    for (index = 0U; index < 2U; ++index) {
        pf_tq_namespace_id_map_entry_v2 actual[2];
        size_t size = 0U;
        if (pf_tq_namespace_read_fixed(proc_root_fd, paths[index], bytes,
                sizeof(bytes), &size, error, error_size) != 0 ||
                pf_tq_namespace_map_parse(bytes, size, actual,
                    error, error_size) != 0) return -1;
        if (actual[0].inside_id != expected[index][0].inside_id ||
                actual[0].outside_id != expected[index][0].outside_id ||
                actual[1].inside_id != expected[index][1].inside_id ||
                actual[1].outside_id != expected[index][1].outside_id) {
            return pf_tq_namespace_error(error, error_size,
                "namespace kernel map differs from signed map");
        }
    }
    {
        unsigned char setgroups[PF_TQ_NAMESPACE_SETGROUPS_BYTES];
        size_t size = 0U;
        if (pf_tq_namespace_read_fixed(proc_root_fd, "self/setgroups",
                setgroups, sizeof(setgroups), &size, error, error_size) != 0 ||
                size != 6U || memcmp(setgroups, "allow\n", 6U) != 0) {
            return pf_tq_namespace_error(error, error_size,
                "namespace setgroups gate is not exact allow-LF");
        }
    }
    return 0;
}

int pf_tq_namespace_current_v2(
    int proc_root_fd,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
) {
    pf_tq_namespace_clear_error(error, error_size);
    if (result == NULL) {
        return pf_tq_namespace_error(error, error_size,
            "namespace output is missing");
    }
    memset(result, 0, sizeof(*result));
    if (pf_tq_namespace_proc_validate(proc_root_fd, error, error_size) != 0 ||
            pf_tq_namespace_root_validate(error, error_size) != 0 ||
            pf_tq_namespace_capture_prefix(proc_root_fd, "self", result,
                error, error_size) != 0) return -1;
    return 0;
}

static int pf_tq_namespace_release_validate(
    int release_fd,
    char *error,
    size_t error_size
) {
    int flags;
    if (release_fd <= 2) {
        return pf_tq_namespace_error(error, error_size,
            "namespace proc-root release FD must exceed stderr");
    }
    flags = fcntl(release_fd, F_GETFD);
    if (flags < 0 || (flags & FD_CLOEXEC) == 0) {
        return pf_tq_namespace_error(error, error_size,
            "namespace proc-root release FD is invalid or not CLOEXEC");
    }
    return 0;
}

static void pf_tq_namespace_release_close(int release_fd) {
    if (release_fd >= 0) (void)close(release_fd);
}

static int pf_tq_namespace_create_empty_root(
    int *root_fd,
    char *error,
    size_t error_size
) {
    static const struct {
        const char *key;
        const char *value;
    } options[] = {
        {"mode", "0555"},
        {"size", "1048576"},
        {"nr_inodes", "64"},
    };
    int filesystem_fd;
    int mounted_fd;
    size_t index;
    filesystem_fd = (int)syscall(SYS_fsopen, "tmpfs", FSOPEN_CLOEXEC);
    if (filesystem_fd < 0) {
        return pf_tq_namespace_error(error, error_size,
            "service tmpfs fsopen failed: %s", strerror(errno));
    }
    for (index = 0U; index < sizeof(options) / sizeof(options[0]); ++index) {
        if (syscall(SYS_fsconfig, filesystem_fd, FSCONFIG_SET_STRING,
                options[index].key, options[index].value, 0) != 0) {
            int saved = errno;
            (void)close(filesystem_fd);
            return pf_tq_namespace_error(error, error_size,
                "service tmpfs fsconfig failed: %s", strerror(saved));
        }
    }
    if (syscall(SYS_fsconfig, filesystem_fd, FSCONFIG_CMD_CREATE,
            NULL, NULL, 0) != 0) {
        int saved = errno;
        (void)close(filesystem_fd);
        return pf_tq_namespace_error(error, error_size,
            "service tmpfs create failed: %s", strerror(saved));
    }
    mounted_fd = (int)syscall(SYS_fsmount, filesystem_fd, FSMOUNT_CLOEXEC,
        MOUNT_ATTR_NOSUID | MOUNT_ATTR_NODEV | MOUNT_ATTR_NOEXEC);
    if (mounted_fd < 0) {
        int saved = errno;
        (void)close(filesystem_fd);
        return pf_tq_namespace_error(error, error_size,
            "service tmpfs fsmount failed: %s", strerror(saved));
    }
    if (close(filesystem_fd) != 0) {
        int saved = errno;
        (void)close(mounted_fd);
        return pf_tq_namespace_error(error, error_size,
            "service tmpfs fs-context close failed: %s", strerror(saved));
    }
    *root_fd = mounted_fd;
    return 0;
}

static int pf_tq_namespace_proc_context(
    char *error,
    size_t error_size
) {
    int context_fd = (int)syscall(SYS_fsopen, "proc", FSOPEN_CLOEXEC);
    if (context_fd < 0) {
        (void)pf_tq_namespace_error(error, error_size,
            "procfs fsopen failed: %s", strerror(errno));
        return -1;
    }
    if (syscall(SYS_fsconfig, context_fd, FSCONFIG_CMD_CREATE,
            NULL, NULL, 0) != 0) {
        int saved = errno;
        (void)close(context_fd);
        (void)pf_tq_namespace_error(error, error_size,
            "procfs create failed: %s", strerror(saved));
        return -1;
    }
    return context_fd;
}

static int pf_tq_namespace_proc_mount(
    int context_fd,
    int release_fd,
    int expected_fd,
    char *error,
    size_t error_size
) {
    int mount_fd = (int)syscall(SYS_fsmount, context_fd, FSMOUNT_CLOEXEC,
        MOUNT_ATTR_RDONLY | MOUNT_ATTR_NOSUID |
        MOUNT_ATTR_NODEV | MOUNT_ATTR_NOEXEC);
    int proc_fd;
    if (mount_fd < 0) {
        int saved = errno;
        (void)close(context_fd);
        pf_tq_namespace_release_close(release_fd);
        return pf_tq_namespace_error(error, error_size,
            "procfs fsmount failed: %s", strerror(saved));
    }
    if (close(release_fd) != 0) {
        (void)close(mount_fd);
        (void)close(context_fd);
        return pf_tq_namespace_error(error, error_size,
            "procfs release FD close failed: %s", strerror(errno));
    }
    proc_fd = openat(mount_fd, ".",
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (proc_fd != expected_fd) {
        int actual = proc_fd;
        if (proc_fd >= 0) (void)close(proc_fd);
        (void)close(mount_fd);
        (void)close(context_fd);
        return pf_tq_namespace_error(error, error_size,
            "procfs regular root did not open at fixed FD (got %d)", actual);
    }
    {
        int close_failed = 0;
        int saved = 0;
        if (close(mount_fd) != 0) {
            close_failed = 1;
            saved = errno;
        }
        if (close(context_fd) != 0 && !close_failed) {
            close_failed = 1;
            saved = errno;
        }
        if (close_failed) {
            (void)close(proc_fd);
            return pf_tq_namespace_error(error, error_size,
                "procfs temporary FD close failed: %s", strerror(saved));
        }
    }
    return proc_fd;
}

int pf_tq_namespace_enter_service_v2(
    int proc_root_release_fd,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
) {
    int root_fd = -1;
    int proc_context_fd = -1;
    int proc_fd = -1;
    int proc_root_fd = proc_root_release_fd;
    pf_tq_namespace_clear_error(error, error_size);
    if (result == NULL || getpid() != 1 ||
            pf_tq_namespace_release_validate(proc_root_release_fd,
                error, error_size) != 0) {
        pf_tq_namespace_release_close(proc_root_release_fd);
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_namespace_error(error, error_size,
                "service namespace caller is not PID 1 in P");
        }
        return -1;
    }
    memset(result, 0, sizeof(*result));
    if (unshare(CLONE_NEWNS) != 0 ||
            mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) != 0) {
        pf_tq_namespace_release_close(proc_root_release_fd);
        return pf_tq_namespace_error(error, error_size,
            "service mount namespace/private propagation failed: %s",
            strerror(errno));
    }
    if (pf_tq_namespace_create_empty_root(
            &root_fd, error, error_size) != 0) {
        pf_tq_namespace_release_close(proc_root_release_fd);
        return -1;
    }
    if (fchdir(root_fd) != 0 || chroot(".") != 0 || chdir("/") != 0) {
        int saved = errno;
        (void)close(root_fd);
        pf_tq_namespace_release_close(proc_root_release_fd);
        return pf_tq_namespace_error(error, error_size,
            "service detached-root chroot failed: %s", strerror(saved));
    }
    {
        struct mount_attr attributes;
        memset(&attributes, 0, sizeof(attributes));
        attributes.attr_set = MOUNT_ATTR_RDONLY | MOUNT_ATTR_NOSUID |
            MOUNT_ATTR_NODEV | MOUNT_ATTR_NOEXEC;
        if (syscall(SYS_mount_setattr, root_fd, "", AT_EMPTY_PATH,
                &attributes, sizeof(attributes)) != 0) {
            int saved = errno;
            (void)close(root_fd);
            pf_tq_namespace_release_close(proc_root_release_fd);
            return pf_tq_namespace_error(error, error_size,
                "service detached-root readonly lockdown failed: %s",
                strerror(saved));
        }
    }
    proc_context_fd = pf_tq_namespace_proc_context(error, error_size);
    if (proc_context_fd < 0) {
        (void)close(root_fd);
        pf_tq_namespace_release_close(proc_root_release_fd);
        return -1;
    }
    if (close(root_fd) != 0) {
        (void)close(proc_context_fd);
        pf_tq_namespace_release_close(proc_root_release_fd);
        return pf_tq_namespace_error(error, error_size,
            "service detached-root FD close failed: %s", strerror(errno));
    }
    proc_fd = pf_tq_namespace_proc_mount(
        proc_context_fd, proc_root_release_fd, proc_root_fd,
        error, error_size);
    if (proc_fd < 0) return -1;
    if (pf_tq_namespace_current_v2(proc_root_fd, result,
            error, error_size) != 0) {
        (void)close(proc_root_fd);
        return -1;
    }
    return 0;
}

int pf_tq_namespace_prepare_adapter_pid_v2(
    int proc_root_fd,
    char *error,
    size_t error_size
) {
    pf_tq_namespace_set_v2 service;
    pf_tq_namespace_identity_v2 before;
    pf_tq_namespace_clear_error(error, error_size);
    if (getpid() != 1 || pf_tq_namespace_current_v2(proc_root_fd, &service,
            error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_namespace_error(error, error_size,
                "adapter PID namespace setup requires service PID 1");
        }
        return -1;
    }
    if (pf_tq_namespace_identity_path(proc_root_fd,
            "self/ns/pid_for_children", &before,
            error, error_size) != 0) return -1;
    if (!pf_tq_namespace_identity_equal(&service.pid_namespace, &before)) {
        return pf_tq_namespace_error(error, error_size,
            "adapter child PID namespace was already changed");
    }
    if (unshare(CLONE_NEWPID) != 0) {
        return pf_tq_namespace_error(error, error_size,
            "adapter child PID namespace creation failed: %s",
            strerror(errno));
    }
    return 0;
}

int pf_tq_namespace_enter_adapter_v2(
    int inherited_proc_root_fd,
    const pf_tq_namespace_set_v2 *service_namespaces,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
) {
    pf_tq_namespace_set_v2 before;
    int proc_context_fd;
    int proc_fd;
    pf_tq_namespace_clear_error(error, error_size);
    if (service_namespaces == NULL || result == NULL ||
            inherited_proc_root_fd <= 2 || getpid() != 1 ||
            pf_tq_namespace_current_v2(inherited_proc_root_fd, &before,
                error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_namespace_error(error, error_size,
                "adapter namespace caller/inputs rejected");
        }
        return -1;
    }
    if (!pf_tq_namespace_identity_equal(&before.user_namespace,
            &service_namespaces->user_namespace) ||
            pf_tq_namespace_identity_equal(&before.pid_namespace,
                &service_namespaces->pid_namespace) ||
            !pf_tq_namespace_identity_equal(&before.mount_namespace,
                &service_namespaces->mount_namespace)) {
        return pf_tq_namespace_error(error, error_size,
            "adapter inherited U/A/service-mount topology mismatch");
    }
    if (unshare(CLONE_NEWNS) != 0) {
        return pf_tq_namespace_error(error, error_size,
            "adapter mount namespace transition failed: %s",
            strerror(errno));
    }
    proc_context_fd = pf_tq_namespace_proc_context(error, error_size);
    if (proc_context_fd < 0) return -1;
    proc_fd = pf_tq_namespace_proc_mount(
        proc_context_fd, inherited_proc_root_fd, inherited_proc_root_fd,
        error, error_size);
    if (proc_fd < 0) return -1;
    if (pf_tq_namespace_current_v2(proc_fd, result,
            error, error_size) != 0) return -1;
    if (!pf_tq_namespace_identity_equal(&result->user_namespace,
            &service_namespaces->user_namespace) ||
            !pf_tq_namespace_identity_equal(&result->pid_namespace,
                &before.pid_namespace) ||
            pf_tq_namespace_identity_equal(&result->mount_namespace,
                &service_namespaces->mount_namespace)) {
        return pf_tq_namespace_error(error, error_size,
            "adapter final U/A/distinct-mount topology mismatch");
    }
    return 0;
}

int pf_tq_namespace_peer_v2(
    int proc_root_fd,
    pid_t peer_pid,
    pf_tq_namespace_set_v2 *result,
    char *error,
    size_t error_size
) {
    char prefix[32];
    int amount;
    pf_tq_namespace_clear_error(error, error_size);
    if (result == NULL || peer_pid <= 0 ||
            pf_tq_namespace_proc_validate(proc_root_fd,
                error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_namespace_error(error, error_size,
                "namespace peer arguments rejected");
        }
        return -1;
    }
    amount = snprintf(prefix, sizeof(prefix), "%ld", (long)peer_pid);
    if (amount <= 0 || (size_t)amount >= sizeof(prefix)) {
        return pf_tq_namespace_error(error, error_size,
            "namespace peer PID decimal overflow");
    }
    memset(result, 0, sizeof(*result));
    return pf_tq_namespace_capture_prefix(
        proc_root_fd, prefix, result, error, error_size);
}
