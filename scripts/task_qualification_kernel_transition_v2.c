#define _GNU_SOURCE
#include "task_qualification_kernel_transition_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <linux/capability.h>
#include <linux/magic.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <unistd.h>

#define PF_TQ_KERNEL_STATUS_BYTES 65536U
#define PF_TQ_KERNEL_GROUPS_MAX 256U

static int pf_tq_kernel_error(
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

static void pf_tq_kernel_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static int pf_tq_kernel_proc_root_validate(
    int proc_root_fd,
    char *error,
    size_t error_size
) {
    struct stat status;
    struct statfs filesystem;
    int flags;
    if (proc_root_fd < 0 || fstat(proc_root_fd, &status) != 0 ||
            fstatfs(proc_root_fd, &filesystem) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "pinned procRootFd inspection failed: %s", strerror(errno));
    }
    flags = fcntl(proc_root_fd, F_GETFL);
    if (!S_ISDIR(status.st_mode) || filesystem.f_type != PROC_SUPER_MAGIC ||
            flags < 0 || (flags & O_ACCMODE) != O_RDONLY ||
            (flags & (O_DIRECTORY | O_NOFOLLOW)) !=
                (O_DIRECTORY | O_NOFOLLOW) ||
            (flags & (O_APPEND | O_NONBLOCK | O_PATH)) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "pinned procRootFd type/open flags rejected");
    }
    return 0;
}

static int pf_tq_kernel_read_fixed(
    int root_fd,
    const char *path,
    unsigned char *output,
    size_t capacity,
    size_t *written,
    char *error,
    size_t error_size
) {
    struct stat before;
    struct stat after;
    size_t offset = 0U;
    int fd = openat(root_fd, path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    int result = -1;
    if (fd < 0) {
        return pf_tq_kernel_error(error, error_size,
            "pinned proc read openat failed for %s: %s", path, strerror(errno));
    }
    if (fstat(fd, &before) != 0 || !S_ISREG(before.st_mode)) {
        (void)pf_tq_kernel_error(error, error_size,
            "pinned proc entry type rejected for %s", path);
        goto cleanup;
    }
    while (offset < capacity) {
        ssize_t amount = read(fd, output + offset, capacity - offset);
        if (amount < 0 && errno == EINTR) continue;
        if (amount < 0) {
            (void)pf_tq_kernel_error(error, error_size,
                "pinned proc read failed for %s: %s", path, strerror(errno));
            goto cleanup;
        }
        if (amount == 0) break;
        offset += (size_t)amount;
    }
    if (offset == capacity) {
        unsigned char extra;
        ssize_t amount;
        do {
            amount = read(fd, &extra, 1U);
        } while (amount < 0 && errno == EINTR);
        if (amount != 0) {
            (void)pf_tq_kernel_error(error, error_size,
                "pinned proc entry exceeds its bound for %s", path);
            goto cleanup;
        }
    }
    if (offset == 0U || fstat(fd, &after) != 0 ||
            before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
            before.st_mode != after.st_mode || before.st_uid != after.st_uid ||
            before.st_gid != after.st_gid) {
        (void)pf_tq_kernel_error(error, error_size,
            "pinned proc entry changed/empty for %s", path);
        goto cleanup;
    }
    *written = offset;
    result = 0;
cleanup:
    if (close(fd) != 0 && result == 0) {
        return pf_tq_kernel_error(error, error_size,
            "pinned proc entry close failed: %s", strerror(errno));
    }
    return result;
}

static int pf_tq_kernel_line_value(
    const unsigned char *bytes,
    size_t size,
    const char *name,
    const unsigned char **value,
    size_t *value_size,
    char *error,
    size_t error_size
) {
    size_t cursor = 0U;
    size_t name_size = strlen(name);
    unsigned matches = 0U;
    while (cursor < size) {
        size_t end = cursor;
        size_t start;
        while (end < size && bytes[end] != '\n') {
            if (bytes[end] == 0U || bytes[end] == '\r') {
                return pf_tq_kernel_error(error, error_size,
                    "proc status contains forbidden NUL/CR");
            }
            ++end;
        }
        if (end == size) {
            return pf_tq_kernel_error(error, error_size,
                "proc status has an unterminated line");
        }
        if (end > cursor + name_size &&
                memcmp(bytes + cursor, name, name_size) == 0 &&
                bytes[cursor + name_size] == ':') {
            if (++matches != 1U) {
                return pf_tq_kernel_error(error, error_size,
                    "proc status field %s is duplicated", name);
            }
            start = cursor + name_size + 1U;
            while (start < end && (bytes[start] == ' ' || bytes[start] == '\t')) {
                ++start;
            }
            while (end > start && (bytes[end - 1U] == ' ' ||
                    bytes[end - 1U] == '\t')) {
                --end;
            }
            *value = bytes + start;
            *value_size = end - start;
        }
        cursor = end + 1U;
    }
    if (matches != 1U) {
        return pf_tq_kernel_error(error, error_size,
            "proc status field %s is missing", name);
    }
    return 0;
}

static int pf_tq_kernel_hex_digit(unsigned char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

static int pf_tq_kernel_parse_mask(
    const unsigned char *value,
    size_t size,
    uint64_t *output,
    char *error,
    size_t error_size
) {
    uint64_t result = 0U;
    size_t index;
    if (size != 16U) {
        return pf_tq_kernel_error(error, error_size,
            "proc capability mask is not 16 lowercase hex digits");
    }
    for (index = 0U; index < size; ++index) {
        int digit = pf_tq_kernel_hex_digit(value[index]);
        if (digit < 0) {
            return pf_tq_kernel_error(error, error_size,
                "proc capability mask is not lowercase hex");
        }
        result = (result << 4U) | (unsigned)digit;
    }
    *output = result;
    return 0;
}

static int pf_tq_kernel_parse_uint_list(
    const unsigned char *value,
    size_t size,
    uint64_t *output,
    size_t capacity,
    size_t *count,
    char *error,
    size_t error_size
) {
    size_t cursor = 0U;
    size_t items = 0U;
    while (cursor < size) {
        uint64_t number = 0U;
        bool has_digit = false;
        while (cursor < size && (value[cursor] == ' ' || value[cursor] == '\t')) {
            ++cursor;
        }
        if (cursor == size) break;
        while (cursor < size && value[cursor] >= '0' && value[cursor] <= '9') {
            unsigned digit = (unsigned)(value[cursor] - '0');
            if (number > (UINT64_MAX - digit) / 10U) {
                return pf_tq_kernel_error(error, error_size,
                    "proc decimal integer overflow");
            }
            number = number * 10U + digit;
            has_digit = true;
            ++cursor;
        }
        if (!has_digit || items >= capacity ||
                (cursor < size && value[cursor] != ' ' && value[cursor] != '\t')) {
            return pf_tq_kernel_error(error, error_size,
                "proc decimal list grammar/bound rejected");
        }
        output[items++] = number;
    }
    *count = items;
    return 0;
}

static int pf_tq_kernel_status_parse(
    const unsigned char *bytes,
    size_t size,
    pf_tq_kernel_snapshot_v2 *snapshot,
    gid_t *status_groups,
    size_t *status_group_count,
    char *error,
    size_t error_size
) {
    static const char *const mask_names[] = {
        "CapInh", "CapPrm", "CapEff", "CapBnd", "CapAmb"
    };
    uint64_t *const masks[] = {
        &snapshot->inheritable, &snapshot->permitted, &snapshot->effective,
        &snapshot->bounding, &snapshot->ambient
    };
    const unsigned char *value;
    size_t value_size;
    uint64_t numbers[PF_TQ_KERNEL_GROUPS_MAX];
    size_t count;
    size_t index;
    for (index = 0U; index < sizeof(mask_names) / sizeof(mask_names[0]); ++index) {
        if (pf_tq_kernel_line_value(bytes, size, mask_names[index],
                &value, &value_size, error, error_size) != 0 ||
                pf_tq_kernel_parse_mask(value, value_size, masks[index],
                    error, error_size) != 0) return -1;
    }
    if (pf_tq_kernel_line_value(bytes, size, "Uid", &value, &value_size,
            error, error_size) != 0 ||
            pf_tq_kernel_parse_uint_list(value, value_size, numbers, 4U,
                &count, error, error_size) != 0 || count != 4U) return -1;
    for (index = 0U; index < 4U; ++index) {
        if (numbers[index] > UINT32_MAX) {
            return pf_tq_kernel_error(error, error_size,
                "proc UID exceeds uint32");
        }
        snapshot->uid[index] = (uid_t)numbers[index];
    }
    if (pf_tq_kernel_line_value(bytes, size, "Gid", &value, &value_size,
            error, error_size) != 0 ||
            pf_tq_kernel_parse_uint_list(value, value_size, numbers, 4U,
                &count, error, error_size) != 0 || count != 4U) return -1;
    for (index = 0U; index < 4U; ++index) {
        if (numbers[index] > UINT32_MAX) {
            return pf_tq_kernel_error(error, error_size,
                "proc GID exceeds uint32");
        }
        snapshot->gid[index] = (gid_t)numbers[index];
    }
    if (pf_tq_kernel_line_value(bytes, size, "Groups", &value, &value_size,
            error, error_size) != 0 ||
            pf_tq_kernel_parse_uint_list(value, value_size, numbers,
                PF_TQ_KERNEL_GROUPS_MAX, &count, error, error_size) != 0) return -1;
    for (index = 0U; index < count; ++index) {
        if (numbers[index] > UINT32_MAX) {
            return pf_tq_kernel_error(error, error_size,
                "proc supplementary GID exceeds uint32");
        }
        status_groups[index] = (gid_t)numbers[index];
    }
    *status_group_count = count;
    if (pf_tq_kernel_line_value(bytes, size, "NoNewPrivs", &value, &value_size,
            error, error_size) != 0 ||
            pf_tq_kernel_parse_uint_list(value, value_size, numbers, 1U,
                &count, error, error_size) != 0 || count != 1U ||
            numbers[0] > 1U) {
        return pf_tq_kernel_error(error, error_size,
            "proc NoNewPrivs field rejected");
    }
    snapshot->no_new_privs = (int)numbers[0];
    return 0;
}

static int pf_tq_kernel_capget(
    uint64_t *inheritable,
    uint64_t *permitted,
    uint64_t *effective,
    char *error,
    size_t error_size
) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));
    if (syscall(SYS_capget, &header, data) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "capget failed: %s", strerror(errno));
    }
    *effective = (uint64_t)data[0].effective |
        ((uint64_t)data[1].effective << 32U);
    *permitted = (uint64_t)data[0].permitted |
        ((uint64_t)data[1].permitted << 32U);
    *inheritable = (uint64_t)data[0].inheritable |
        ((uint64_t)data[1].inheritable << 32U);
    return 0;
}

static int pf_tq_kernel_capset(
    uint64_t inheritable,
    uint64_t permitted,
    uint64_t effective,
    char *error,
    size_t error_size
) {
    struct __user_cap_header_struct header = {
        .version = _LINUX_CAPABILITY_VERSION_3,
        .pid = 0,
    };
    struct __user_cap_data_struct data[2];
    memset(data, 0, sizeof(data));
    data[0].effective = (uint32_t)effective;
    data[1].effective = (uint32_t)(effective >> 32U);
    data[0].permitted = (uint32_t)permitted;
    data[1].permitted = (uint32_t)(permitted >> 32U);
    data[0].inheritable = (uint32_t)inheritable;
    data[1].inheritable = (uint32_t)(inheritable >> 32U);
    if (syscall(SYS_capset, &header, data) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "capset failed: %s", strerror(errno));
    }
    return 0;
}

static int pf_tq_kernel_cap_last(
    int proc_root_fd,
    int *last,
    char *error,
    size_t error_size
) {
    unsigned char bytes[32];
    uint64_t values[1];
    size_t size = 0U;
    size_t count = 0U;
    if (pf_tq_kernel_read_fixed(proc_root_fd, "sys/kernel/cap_last_cap",
            bytes, sizeof(bytes), &size, error, error_size) != 0) return -1;
    while (size > 0U && (bytes[size - 1U] == '\n' || bytes[size - 1U] == ' ' ||
            bytes[size - 1U] == '\t')) --size;
    if (pf_tq_kernel_parse_uint_list(bytes, size, values, 1U, &count,
            error, error_size) != 0 || count != 1U || values[0] >= 64U) {
        return pf_tq_kernel_error(error, error_size,
            "cap_last_cap is outside 0..63");
    }
    *last = (int)values[0];
    return 0;
}

static int pf_tq_kernel_masks(
    int proc_root_fd,
    uint64_t *bounding,
    uint64_t *ambient,
    char *error,
    size_t error_size
) {
    int last;
    int capability;
    uint64_t bnd = 0U;
    uint64_t amb = 0U;
    if (pf_tq_kernel_cap_last(proc_root_fd, &last,
            error, error_size) != 0) return -1;
    for (capability = 0; capability <= last; ++capability) {
        int in_bounding = prctl(PR_CAPBSET_READ, capability, 0, 0, 0);
        int in_ambient = prctl(
            PR_CAP_AMBIENT, PR_CAP_AMBIENT_IS_SET, capability, 0, 0);
        if (in_bounding < 0 || in_ambient < 0) {
            return pf_tq_kernel_error(error, error_size,
                "capability bounding/ambient query failed: %s", strerror(errno));
        }
        if (in_bounding == 1) bnd |= PF_TQ_KERNEL_V2_CAP_BIT(capability);
        if (in_ambient == 1) amb |= PF_TQ_KERNEL_V2_CAP_BIT(capability);
    }
    *bounding = bnd;
    *ambient = amb;
    return 0;
}

int pf_tq_kernel_snapshot_read_v2(
    int proc_root_fd,
    pf_tq_kernel_crosscheck_v2 crosscheck,
    pf_tq_kernel_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    unsigned char status_bytes[PF_TQ_KERNEL_STATUS_BYTES];
    gid_t status_groups[PF_TQ_KERNEL_GROUPS_MAX];
    gid_t kernel_groups[PF_TQ_KERNEL_GROUPS_MAX];
    uid_t real_uid, effective_uid, saved_uid;
    gid_t real_gid, effective_gid, saved_gid;
    uint64_t inheritable = 0U, permitted = 0U, effective = 0U;
    uint64_t bounding = 0U, ambient = 0U;
    size_t status_size = 0U;
    size_t status_group_count = 0U;
    int kernel_group_count;
    int no_new_privs;
    size_t index;
    pf_tq_kernel_clear_error(error, error_size);
    if (snapshot == NULL || (crosscheck != PF_TQ_KERNEL_CROSSCHECK_FULL_V2 &&
            crosscheck != PF_TQ_KERNEL_CROSSCHECK_FILTERED_V2)) {
        return pf_tq_kernel_error(error, error_size,
            "kernel snapshot arguments rejected");
    }
    memset(snapshot, 0, sizeof(*snapshot));
    if (pf_tq_kernel_proc_root_validate(proc_root_fd, error, error_size) != 0 ||
            pf_tq_kernel_read_fixed(proc_root_fd, "self/status", status_bytes,
                sizeof(status_bytes), &status_size, error, error_size) != 0 ||
            pf_tq_kernel_status_parse(status_bytes, status_size, snapshot,
                status_groups, &status_group_count, error, error_size) != 0 ||
            pf_tq_kernel_capget(&inheritable, &permitted, &effective,
                error, error_size) != 0) return -1;
    if (snapshot->inheritable != inheritable ||
            snapshot->permitted != permitted || snapshot->effective != effective) {
        return pf_tq_kernel_error(error, error_size,
            "proc capability fields do not match capget");
    }
    if (crosscheck == PF_TQ_KERNEL_CROSSCHECK_FULL_V2) {
        if (pf_tq_kernel_masks(proc_root_fd, &bounding, &ambient,
                error, error_size) != 0) return -1;
        if (snapshot->bounding != bounding || snapshot->ambient != ambient) {
            return pf_tq_kernel_error(error, error_size,
                "proc bounding/ambient fields do not match prctl");
        }
    }
    if (getresuid(&real_uid, &effective_uid, &saved_uid) != 0 ||
            getresgid(&real_gid, &effective_gid, &saved_gid) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "getresuid/getresgid failed: %s", strerror(errno));
    }
    if (snapshot->uid[0] != real_uid || snapshot->uid[1] != effective_uid ||
            snapshot->uid[2] != saved_uid ||
            snapshot->gid[0] != real_gid || snapshot->gid[1] != effective_gid ||
            snapshot->gid[2] != saved_gid) {
        return pf_tq_kernel_error(error, error_size,
            "proc real/effective/saved credentials mismatch kernel getters");
    }
    kernel_group_count = getgroups(0, NULL);
    if (kernel_group_count < 0 || kernel_group_count > (int)PF_TQ_KERNEL_GROUPS_MAX ||
            (kernel_group_count > 0 && getgroups(
                kernel_group_count, kernel_groups) != kernel_group_count) ||
            status_group_count != (size_t)kernel_group_count) {
        return pf_tq_kernel_error(error, error_size,
            "supplementary group count/read mismatch");
    }
    for (index = 0U; index < status_group_count; ++index) {
        if (status_groups[index] != kernel_groups[index]) {
            return pf_tq_kernel_error(error, error_size,
                "proc supplementary groups mismatch getgroups");
        }
    }
    snapshot->supplementary_group_count = kernel_group_count;
    if (crosscheck == PF_TQ_KERNEL_CROSSCHECK_FULL_V2) {
        no_new_privs = prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0);
        if (no_new_privs < 0 || no_new_privs != snapshot->no_new_privs) {
            return pf_tq_kernel_error(error, error_size,
                "proc NoNewPrivs does not match prctl");
        }
    }
    return 0;
}

static int pf_tq_kernel_require_exact(
    int proc_root_fd,
    pf_tq_kernel_crosscheck_v2 crosscheck,
    uint64_t inheritable,
    uint64_t permitted,
    uint64_t effective,
    uint64_t bounding,
    uint64_t ambient,
    uid_t uid,
    gid_t gid,
    int no_new_privs,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_snapshot_v2 snapshot;
    size_t index;
    if (pf_tq_kernel_snapshot_read_v2(proc_root_fd, crosscheck, &snapshot,
            error, error_size) != 0) return -1;
    if (snapshot.inheritable != inheritable || snapshot.permitted != permitted ||
            snapshot.effective != effective || snapshot.bounding != bounding ||
            snapshot.ambient != ambient ||
            snapshot.supplementary_group_count != 0 ||
            snapshot.no_new_privs != no_new_privs) {
        return pf_tq_kernel_error(error, error_size,
            "kernel capability/group/no_new_privs checkpoint mismatch");
    }
    for (index = 0U; index < 4U; ++index) {
        if (snapshot.uid[index] != uid || snapshot.gid[index] != gid) {
            return pf_tq_kernel_error(error, error_size,
                "kernel real/effective/saved/fs credential checkpoint mismatch");
        }
    }
    return 0;
}

static int pf_tq_kernel_drop_bounding_except(
    int proc_root_fd,
    uint64_t keep,
    char *error,
    size_t error_size
) {
    int last;
    int capability;
    if (pf_tq_kernel_cap_last(proc_root_fd, &last,
            error, error_size) != 0) return -1;
    for (capability = 0; capability <= last; ++capability) {
        if ((keep & PF_TQ_KERNEL_V2_CAP_BIT(capability)) != 0U) continue;
        if (prctl(PR_CAPBSET_DROP, capability, 0, 0, 0) != 0) {
            return pf_tq_kernel_error(error, error_size,
                "PR_CAPBSET_DROP(%d) failed: %s", capability, strerror(errno));
        }
    }
    return 0;
}

static int pf_tq_kernel_require_masks(
    int proc_root_fd,
    uint64_t inheritable,
    uint64_t permitted,
    uint64_t effective,
    uint64_t bounding,
    uint64_t ambient,
    int no_new_privs,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_snapshot_v2 snapshot;
    if (pf_tq_kernel_snapshot_read_v2(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2, &snapshot,
            error, error_size) != 0) return -1;
    if (snapshot.inheritable != inheritable || snapshot.permitted != permitted ||
            snapshot.effective != effective || snapshot.bounding != bounding ||
            snapshot.ambient != ambient || snapshot.no_new_privs != no_new_privs) {
        return pf_tq_kernel_error(error, error_size,
            "kernel capability/no_new_privs mask checkpoint mismatch");
    }
    return 0;
}

static int pf_tq_kernel_drop_credentials(
    uid_t uid,
    gid_t gid,
    char *error,
    size_t error_size
) {
    if (setgroups(0, NULL) != 0 || setresgid(gid, gid, gid) != 0 ||
            setresuid(uid, uid, uid) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "setgroups/setresgid/setresuid transition failed: %s", strerror(errno));
    }
    return 0;
}

int pf_tq_kernel_converge_preseed_v2(
    int proc_root_fd,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_snapshot_v2 before;
    pf_tq_kernel_clear_error(error, error_size);
    if (pf_tq_kernel_snapshot_read_v2(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2, &before,
            error, error_size) != 0) return -1;
    if ((before.permitted & PF_TQ_KERNEL_V2_PRESEED_MASK) !=
            PF_TQ_KERNEL_V2_PRESEED_MASK ||
            (before.effective & PF_TQ_KERNEL_V2_PRESEED_MASK) !=
                PF_TQ_KERNEL_V2_PRESEED_MASK ||
            (before.bounding & PF_TQ_KERNEL_V2_PRESEED_MASK) !=
                PF_TQ_KERNEL_V2_PRESEED_MASK || before.no_new_privs != 0) {
        return pf_tq_kernel_error(error, error_size,
            "namespace setup lacks the exact pre-seed capability minimum");
    }
    if (pf_tq_kernel_drop_bounding_except(proc_root_fd,
            PF_TQ_KERNEL_V2_PRESEED_MASK, error, error_size) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0 ||
            pf_tq_kernel_capset(0U, PF_TQ_KERNEL_V2_PRESEED_MASK,
                PF_TQ_KERNEL_V2_PRESEED_MASK, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_kernel_error(error, error_size,
                "pre-seed capability convergence failed: %s", strerror(errno));
        }
        return -1;
    }
    return pf_tq_kernel_require_masks(proc_root_fd,
        0U, PF_TQ_KERNEL_V2_PRESEED_MASK, PF_TQ_KERNEL_V2_PRESEED_MASK,
        PF_TQ_KERNEL_V2_PRESEED_MASK, 0U, 0, error, error_size);
}

int pf_tq_kernel_isolate_adapter_v2(
    int proc_root_fd,
    uid_t adapter_uid,
    gid_t adapter_gid,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_snapshot_v2 before;
    pf_tq_kernel_clear_error(error, error_size);
    if (adapter_uid == 0U || adapter_gid == 0U || adapter_uid > INT32_MAX ||
            adapter_gid > INT32_MAX || adapter_uid == 65534U ||
            adapter_gid == 65534U) {
        return pf_tq_kernel_error(error, error_size,
            "adapter UID/GID configuration rejected");
    }
    if (pf_tq_kernel_snapshot_read_v2(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2, &before,
            error, error_size) != 0) return -1;
    if (before.inheritable != 0U ||
            before.permitted != PF_TQ_KERNEL_V2_PRESEED_MASK ||
            before.effective != PF_TQ_KERNEL_V2_PRESEED_MASK ||
            before.bounding != PF_TQ_KERNEL_V2_PRESEED_MASK ||
            before.ambient != 0U || before.no_new_privs != 0) {
        return pf_tq_kernel_error(error, error_size,
            "adapter setup capability/no_new_privs precondition rejected");
    }
    if (pf_tq_kernel_drop_bounding_except(proc_root_fd, 0U,
            error, error_size) != 0 ||
            pf_tq_kernel_drop_credentials(adapter_uid, adapter_gid,
                error, error_size) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0 ||
            pf_tq_kernel_capset(0U, 0U, 0U, error, error_size) != 0 ||
            prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_kernel_error(error, error_size,
                "adapter ambient/no_new_privs transition failed: %s", strerror(errno));
        }
        return -1;
    }
    return pf_tq_kernel_require_exact(proc_root_fd,
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2, 0U, 0U, 0U, 0U, 0U,
        adapter_uid, adapter_gid, 1, error, error_size);
}

int pf_tq_kernel_prepare_custody_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_snapshot_v2 before;
    pf_tq_kernel_clear_error(error, error_size);
    if (service_uid == 0U || service_gid == 0U || service_uid > INT32_MAX ||
            service_gid > INT32_MAX || service_uid == 65534U ||
            service_gid == 65534U) {
        return pf_tq_kernel_error(error, error_size,
            "service UID/GID configuration rejected");
    }
    if (pf_tq_kernel_snapshot_read_v2(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2, &before,
            error, error_size) != 0) return -1;
    if (before.inheritable != 0U ||
            before.permitted != PF_TQ_KERNEL_V2_PRESEED_MASK ||
            before.effective != PF_TQ_KERNEL_V2_PRESEED_MASK ||
            before.bounding != PF_TQ_KERNEL_V2_PRESEED_MASK ||
            before.ambient != 0U || before.no_new_privs != 0) {
        return pf_tq_kernel_error(error, error_size,
            "pre-seed capability/no_new_privs precondition rejected");
    }
    if (pf_tq_kernel_drop_bounding_except(proc_root_fd,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, error, error_size) != 0 ||
            prctl(PR_SET_KEEPCAPS, 1, 0, 0, 0) != 0 ||
            pf_tq_kernel_drop_credentials(service_uid, service_gid,
                error, error_size) != 0 ||
            pf_tq_kernel_capset(PF_TQ_KERNEL_V2_CUSTODY_MASK,
                PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
                error, error_size) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE,
                PF_TQ_KERNEL_V2_CAP_SETPCAP, 0, 0) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE,
                PF_TQ_KERNEL_V2_CAP_SYS_PTRACE, 0, 0) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_kernel_error(error, error_size,
                "custody credential/capability/ambient transition failed: %s",
                strerror(errno));
        }
        return -1;
    }
    return pf_tq_kernel_require_exact(proc_root_fd,
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2,
        PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
        PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
        PF_TQ_KERNEL_V2_CUSTODY_MASK, service_uid, service_gid, 0,
        error, error_size);
}

int pf_tq_kernel_custody_no_new_privs_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_clear_error(error, error_size);
    if (pf_tq_kernel_require_exact(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, service_uid, service_gid, 0,
            error, error_size) != 0) return -1;
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "PR_SET_NO_NEW_PRIVS failed: %s", strerror(errno));
    }
    return pf_tq_kernel_require_exact(proc_root_fd,
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2,
        PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
        PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
        PF_TQ_KERNEL_V2_CUSTODY_MASK, service_uid, service_gid, 1,
        error, error_size);
}

int pf_tq_kernel_service_post_exec_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_clear_error(error, error_size);
    if (pf_tq_kernel_require_exact(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FULL_V2,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, PF_TQ_KERNEL_V2_CUSTODY_MASK,
            PF_TQ_KERNEL_V2_CUSTODY_MASK, service_uid, service_gid, 1,
            error, error_size) != 0) return -1;
    if (prctl(PR_CAPBSET_DROP, PF_TQ_KERNEL_V2_CAP_SYS_PTRACE, 0, 0, 0) != 0 ||
            prctl(PR_CAPBSET_DROP, PF_TQ_KERNEL_V2_CAP_SETPCAP, 0, 0, 0) != 0 ||
            prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0) {
        return pf_tq_kernel_error(error, error_size,
            "post-exec bounding/ambient transition failed: %s", strerror(errno));
    }
    if (pf_tq_kernel_capset(0U, PF_TQ_KERNEL_V2_STEADY_MASK,
            PF_TQ_KERNEL_V2_STEADY_MASK, error, error_size) != 0) return -1;
    return pf_tq_kernel_require_exact(proc_root_fd,
        PF_TQ_KERNEL_CROSSCHECK_FULL_V2,
        0U, PF_TQ_KERNEL_V2_STEADY_MASK, PF_TQ_KERNEL_V2_STEADY_MASK,
        0U, 0U, service_uid, service_gid, 1, error, error_size);
}

int pf_tq_kernel_terminal_lockdown_v2(
    int proc_root_fd,
    uid_t service_uid,
    gid_t service_gid,
    char *error,
    size_t error_size
) {
    pf_tq_kernel_clear_error(error, error_size);
    if (pf_tq_kernel_require_exact(proc_root_fd,
            PF_TQ_KERNEL_CROSSCHECK_FILTERED_V2,
            0U, PF_TQ_KERNEL_V2_STEADY_MASK, PF_TQ_KERNEL_V2_STEADY_MASK,
            0U, 0U, service_uid, service_gid, 1,
            error, error_size) != 0) return -1;
    if (pf_tq_kernel_capset(0U, 0U, 0U, error, error_size) != 0) return -1;
    return pf_tq_kernel_require_exact(proc_root_fd,
        PF_TQ_KERNEL_CROSSCHECK_FILTERED_V2,
        0U, 0U, 0U, 0U, 0U, service_uid, service_gid, 1,
        error, error_size);
}
