#define _GNU_SOURCE
#include "task_qualification_seed_custody_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/stat.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif

#ifndef AT_NO_AUTOMOUNT
#define AT_NO_AUTOMOUNT 0x800
#endif

#ifndef STATX_MNT_ID
#define STATX_MNT_ID 0x00001000U
#endif

struct pf_tq_linux_dirent64 {
    uint64_t d_ino;
    int64_t d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[];
};

static const char *const pf_tq_seed_names[PF_TQ_SEED_CUSTODY_V2_COUNT] = {
    "service.seed", "role-0.seed", "role-1.seed", "role-2.seed"
};

static const char *const pf_tq_seed_slots[PF_TQ_SEED_CUSTODY_V2_COUNT] = {
    "service", "role-0", "role-1", "role-2"
};

static const char *const pf_tq_fixture_public_keys[] = {
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
    "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
    "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"
};

static int pf_tq_seed_error(
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

static void pf_tq_seed_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static void pf_tq_seed_initialize_result(pf_tq_seed_custody_v2 *custody) {
    size_t index;
    if (custody == NULL) return;
    memset(custody, 0, sizeof(*custody));
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        custody->seeds[index].fd = -1;
    }
}

void pf_tq_seed_custody_close_v2(pf_tq_seed_custody_v2 *custody) {
    size_t index;
    if (custody == NULL) return;
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        OPENSSL_cleanse(custody->seeds[index].seed,
            sizeof(custody->seeds[index].seed));
        OPENSSL_cleanse(custody->seeds[index].public_key,
            sizeof(custody->seeds[index].public_key));
        if (custody->seeds[index].fd >= 0) {
            (void)close(custody->seeds[index].fd);
            custody->seeds[index].fd = -1;
        }
    }
    custody->initialized = 0;
}

static bool pf_tq_seed_ascii_id(const char *value) {
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

static int pf_tq_seed_hex_value(unsigned char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

static int pf_tq_seed_decode_hex32(
    const unsigned char *input,
    unsigned char output[32]
) {
    size_t index;
    for (index = 0U; index < 32U; ++index) {
        int high = pf_tq_seed_hex_value(input[2U * index]);
        int low = pf_tq_seed_hex_value(input[2U * index + 1U]);
        if (high < 0 || low < 0) return -1;
        output[index] = (unsigned char)((unsigned)high * 16U + (unsigned)low);
    }
    return 0;
}

static bool pf_tq_seed_fixture_key(const unsigned char public_key[32]) {
    size_t fixture;
    unsigned char decoded[32];
    bool result = false;
    for (fixture = 0U; fixture < sizeof(pf_tq_fixture_public_keys) /
            sizeof(pf_tq_fixture_public_keys[0]); ++fixture) {
        if (pf_tq_seed_decode_hex32(
                (const unsigned char *)pf_tq_fixture_public_keys[fixture],
                decoded) != 0) {
            result = true;
            break;
        }
        if (memcmp(public_key, decoded, sizeof(decoded)) == 0) {
            result = true;
            break;
        }
    }
    OPENSSL_cleanse(decoded, sizeof(decoded));
    return result;
}

static bool pf_tq_seed_stat_equal(const struct stat *left, const struct stat *right) {
    return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
        left->st_mode == right->st_mode && left->st_uid == right->st_uid &&
        left->st_gid == right->st_gid && left->st_nlink == right->st_nlink &&
        left->st_size == right->st_size &&
        left->st_mtim.tv_sec == right->st_mtim.tv_sec &&
        left->st_mtim.tv_nsec == right->st_mtim.tv_nsec &&
        left->st_ctim.tv_sec == right->st_ctim.tv_sec &&
        left->st_ctim.tv_nsec == right->st_ctim.tv_nsec;
}

static int pf_tq_seed_statx_fd(
    int fd,
    struct statx *status,
    char *error,
    size_t error_size
) {
    memset(status, 0, sizeof(*status));
    if (syscall(SYS_statx, fd, "", AT_EMPTY_PATH | AT_NO_AUTOMOUNT,
            STATX_BASIC_STATS | STATX_MNT_ID, status) != 0) {
        return pf_tq_seed_error(error, error_size,
            "seed custody statx failed: %s", strerror(errno));
    }
    if ((status->stx_mask & (STATX_TYPE | STATX_MODE | STATX_INO |
            STATX_UID | STATX_GID | STATX_MNT_ID)) !=
            (STATX_TYPE | STATX_MODE | STATX_INO |
             STATX_UID | STATX_GID | STATX_MNT_ID)) {
        return pf_tq_seed_error(error, error_size,
            "seed custody statx result is incomplete");
    }
    return 0;
}

static int pf_tq_seed_root_not_mount(
    int root_fd,
    char *error,
    size_t error_size
) {
    struct statx root;
    struct statx parent;
    int parent_fd = -1;
    int result = -1;
    if (pf_tq_seed_statx_fd(root_fd, &root, error, error_size) != 0) return -1;
    parent_fd = openat(root_fd, "..",
        O_PATH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (parent_fd < 0) {
        return pf_tq_seed_error(error, error_size,
            "seed root parent inspection failed: %s", strerror(errno));
    }
    if (pf_tq_seed_statx_fd(parent_fd, &parent, error, error_size) != 0) {
        goto cleanup;
    }
    if (root.stx_mnt_id != parent.stx_mnt_id ||
            (root.stx_dev_major == parent.stx_dev_major &&
             root.stx_dev_minor == parent.stx_dev_minor &&
             root.stx_ino == parent.stx_ino)) {
        (void)pf_tq_seed_error(error, error_size,
            "seed root is a mount/filesystem root");
        goto cleanup;
    }
    result = 0;
cleanup:
    if (close(parent_fd) != 0 && result == 0) {
        return pf_tq_seed_error(error, error_size,
            "seed root parent close failed: %s", strerror(errno));
    }
    return result;
}

static int pf_tq_seed_root_entries(
    int root_fd,
    char *error,
    size_t error_size
) {
    unsigned counts[PF_TQ_SEED_CUSTODY_V2_COUNT] = {0U, 0U, 0U, 0U};
    unsigned char buffer[4096];
    if (lseek(root_fd, 0, SEEK_SET) != 0) {
        return pf_tq_seed_error(error, error_size,
            "seed root directory rewind failed: %s", strerror(errno));
    }
    for (;;) {
        ssize_t amount = syscall(SYS_getdents64, root_fd, buffer, sizeof(buffer));
        size_t offset = 0U;
        if (amount < 0) {
            return pf_tq_seed_error(error, error_size,
                "seed root enumeration failed: %s", strerror(errno));
        }
        if (amount == 0) break;
        while (offset < (size_t)amount) {
            const struct pf_tq_linux_dirent64 *entry =
                (const struct pf_tq_linux_dirent64 *)(const void *)(buffer + offset);
            size_t minimum = offsetof(struct pf_tq_linux_dirent64, d_name) + 1U;
            size_t name_capacity;
            const char *terminator;
            size_t index;
            bool matched = false;
            if (entry->d_reclen < minimum ||
                    entry->d_reclen > (size_t)amount - offset) {
                return pf_tq_seed_error(error, error_size,
                    "seed root directory record is malformed");
            }
            name_capacity = entry->d_reclen -
                offsetof(struct pf_tq_linux_dirent64, d_name);
            terminator = memchr(entry->d_name, '\0', name_capacity);
            if (terminator == NULL || entry->d_ino == 0U) {
                return pf_tq_seed_error(error, error_size,
                    "seed root directory name/inode is malformed");
            }
            if (strcmp(entry->d_name, ".") != 0 &&
                    strcmp(entry->d_name, "..") != 0) {
                for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
                    if (strcmp(entry->d_name, pf_tq_seed_names[index]) == 0) {
                        ++counts[index];
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    return pf_tq_seed_error(error, error_size,
                        "seed root contains an extra entry");
                }
            }
            offset += entry->d_reclen;
        }
    }
    for (size_t index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        if (counts[index] != 1U) {
            return pf_tq_seed_error(error, error_size,
                "seed root literal entry set is incomplete/duplicate");
        }
    }
    return 0;
}

static int pf_tq_seed_derive_public(
    const unsigned char seed[32],
    unsigned char public_key[32],
    char *error,
    size_t error_size
) {
    EVP_PKEY *key = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_ED25519, NULL, seed, 32U);
    size_t size = 32U;
    if (key == NULL || EVP_PKEY_get_raw_public_key(
            key, public_key, &size) != 1 || size != 32U) {
        EVP_PKEY_free(key);
        return pf_tq_seed_error(error, error_size,
            "seed Ed25519 public-key derivation failed");
    }
    EVP_PKEY_free(key);
    return 0;
}

static int pf_tq_seed_config_validate(
    const pf_tq_seed_custody_config_v2 *config,
    char *error,
    size_t error_size
) {
    size_t index;
    size_t other;
    if (config->seed_root_fd < 0 || config->service_uid == 0U ||
            config->service_gid == 0U || config->service_uid > INT32_MAX ||
            config->service_gid > INT32_MAX || config->service_uid == 65534U ||
            config->service_gid == 65534U || geteuid() != config->service_uid ||
            getegid() != config->service_gid) {
        return pf_tq_seed_error(error, error_size,
            "seed custody root/service identity configuration rejected");
    }
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        const pf_tq_seed_expectation_v2 *seed = &config->seeds[index];
        if (seed->slot == NULL || strcmp(seed->slot, pf_tq_seed_slots[index]) != 0 ||
                !pf_tq_seed_ascii_id(seed->key_id) || seed->fd <= 2 ||
                seed->fd == config->seed_root_fd ||
                (index == 0U && strcmp(seed->key_id, "service") != 0) ||
                (index > 0U && strcmp(seed->key_id, "service") == 0) ||
                pf_tq_seed_fixture_key(seed->public_key)) {
            return pf_tq_seed_error(error, error_size,
                "seed custody slot/key/fd configuration rejected at %zu", index);
        }
        if (index > 1U && strcmp(config->seeds[index - 1U].key_id,
                seed->key_id) >= 0) {
            return pf_tq_seed_error(error, error_size,
                "role seed key IDs must be strictly ASCII-sorted");
        }
        for (other = 0U; other < index; ++other) {
            if (config->seeds[other].fd == seed->fd || memcmp(
                    config->seeds[other].public_key,
                    seed->public_key, 32U) == 0) {
                return pf_tq_seed_error(error, error_size,
                    "seed custody FD/public-key reuse rejected");
            }
        }
        errno = 0;
        if (fcntl(seed->fd, F_GETFD) != -1 || errno != EBADF) {
            return pf_tq_seed_error(error, error_size,
                "policy-fixed seed FD is not initially unused");
        }
    }
    return 0;
}

static int pf_tq_seed_root_validate(
    const pf_tq_seed_custody_config_v2 *config,
    struct stat *status,
    char *error,
    size_t error_size
) {
    int descriptor_flags;
    int status_flags;
    if (fstat(config->seed_root_fd, status) != 0) {
        return pf_tq_seed_error(error, error_size,
            "seed root fstat failed: %s", strerror(errno));
    }
    descriptor_flags = fcntl(config->seed_root_fd, F_GETFD);
    status_flags = fcntl(config->seed_root_fd, F_GETFL);
    if (!S_ISDIR(status->st_mode) || (status->st_mode & 07777U) != 0700U ||
            status->st_uid != config->service_uid ||
            status->st_gid != config->service_gid ||
            status->st_dev != config->seed_root_device ||
            status->st_ino != config->seed_root_inode ||
            descriptor_flags != FD_CLOEXEC || status_flags < 0 ||
            (status_flags & O_ACCMODE) != O_RDONLY ||
            (status_flags & (O_DIRECTORY | O_NOFOLLOW)) !=
                (O_DIRECTORY | O_NOFOLLOW) ||
            (status_flags & (O_APPEND | O_NONBLOCK | O_PATH)) != 0) {
        return pf_tq_seed_error(error, error_size,
            "seed root identity/mode/open-flags rejected");
    }
    if (pf_tq_seed_root_not_mount(config->seed_root_fd,
            error, error_size) != 0 ||
            pf_tq_seed_root_entries(config->seed_root_fd,
                error, error_size) != 0) return -1;
    return 0;
}

static int pf_tq_seed_read_one(
    int root_fd,
    const pf_tq_seed_expectation_v2 *expected,
    const char *basename,
    uid_t service_uid,
    gid_t service_gid,
    pf_tq_custodied_seed_v2 *result,
    char *error,
    size_t error_size
) {
    unsigned char content[65];
    struct stat before;
    struct stat after;
    int descriptor_flags;
    int status_flags;
    ssize_t amount;
    int outcome = -1;
    int fd;
    memset(content, 0, sizeof(content));
    fd = openat(root_fd, basename,
        O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        (void)pf_tq_seed_error(error, error_size,
            "seed openat failed for %s: %s", basename, strerror(errno));
        goto cleanup;
    }
    result->fd = fd;
    if (fd != expected->fd) {
        (void)pf_tq_seed_error(error, error_size,
            "seed open did not return its policy-fixed FD");
        goto cleanup;
    }
    if (fstat(fd, &before) != 0) {
        (void)pf_tq_seed_error(error, error_size,
            "seed pre-read fstat failed: %s", strerror(errno));
        goto cleanup;
    }
    descriptor_flags = fcntl(fd, F_GETFD);
    status_flags = fcntl(fd, F_GETFL);
    if (!S_ISREG(before.st_mode) || (before.st_mode & 07777U) != 0400U ||
            before.st_uid != service_uid || before.st_gid != service_gid ||
            before.st_nlink != 1U ||
            (before.st_size != 32 && before.st_size != 64 && before.st_size != 65) ||
            descriptor_flags != FD_CLOEXEC || status_flags < 0 ||
            (status_flags & O_ACCMODE) != O_RDONLY ||
            (status_flags & (O_NOFOLLOW | O_NONBLOCK)) !=
                (O_NOFOLLOW | O_NONBLOCK) ||
            (status_flags & (O_APPEND | O_PATH)) != 0) {
        (void)pf_tq_seed_error(error, error_size,
            "seed file identity/mode/open-flags rejected");
        goto cleanup;
    }
    amount = pread(fd, content, (size_t)before.st_size, 0);
    if (amount != before.st_size || pread(fd, content, 1U, before.st_size) != 0) {
        (void)pf_tq_seed_error(error, error_size,
            "seed exact read failed");
        goto cleanup;
    }
    if (fstat(fd, &after) != 0 || !pf_tq_seed_stat_equal(&before, &after)) {
        (void)pf_tq_seed_error(error, error_size,
            "seed file changed during read");
        goto cleanup;
    }
    if (before.st_size == 32) {
        memcpy(result->seed, content, 32U);
    } else {
        if (before.st_size == 65 && content[64] != '\n') {
            (void)pf_tq_seed_error(error, error_size,
                "seed hex file has an invalid terminator");
            goto cleanup;
        }
        if (pf_tq_seed_decode_hex32(content, result->seed) != 0) {
            (void)pf_tq_seed_error(error, error_size,
                "seed hex file is not 64 lowercase hex bytes");
            goto cleanup;
        }
    }
    if (pf_tq_seed_derive_public(result->seed, result->public_key,
            error, error_size) != 0 || memcmp(result->public_key,
                expected->public_key, 32U) != 0 ||
            pf_tq_seed_fixture_key(result->public_key)) {
        (void)pf_tq_seed_error(error, error_size,
            "seed public key does not match the non-fixture expectation");
        goto cleanup;
    }
    result->device = before.st_dev;
    result->inode = before.st_ino;
    outcome = 0;
cleanup:
    OPENSSL_cleanse(content, sizeof(content));
    return outcome;
}

int pf_tq_seed_custody_open_v2(
    const pf_tq_seed_custody_config_v2 *config,
    pf_tq_seed_custody_v2 *custody,
    char *error,
    size_t error_size
) {
    pf_tq_seed_custody_v2 local;
    struct stat root_before;
    struct stat root_after;
    int root_fd = config == NULL ? -1 : config->seed_root_fd;
    size_t index;
    int result = -1;
    pf_tq_seed_clear_error(error, error_size);
    pf_tq_seed_initialize_result(custody);
    pf_tq_seed_initialize_result(&local);
    if (config == NULL || custody == NULL) {
        (void)pf_tq_seed_error(error, error_size,
            "seed custody arguments are missing");
        goto cleanup;
    }
    if (pf_tq_seed_config_validate(config, error, error_size) != 0 ||
            pf_tq_seed_root_validate(config, &root_before,
                error, error_size) != 0) goto cleanup;
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        size_t other;
        if (pf_tq_seed_read_one(root_fd, &config->seeds[index],
                pf_tq_seed_names[index], config->service_uid,
                config->service_gid, &local.seeds[index],
                error, error_size) != 0) goto cleanup;
        for (other = 0U; other < index; ++other) {
            if (local.seeds[other].device == local.seeds[index].device &&
                    local.seeds[other].inode == local.seeds[index].inode) {
                (void)pf_tq_seed_error(error, error_size,
                    "seed files reuse an inode");
                goto cleanup;
            }
        }
    }
    if (fstat(root_fd, &root_after) != 0 ||
            !pf_tq_seed_stat_equal(&root_before, &root_after) ||
            pf_tq_seed_root_entries(root_fd, error, error_size) != 0) {
        if (error != NULL && error_size > 0U && error[0] == '\0') {
            (void)pf_tq_seed_error(error, error_size,
                "seed root changed during custody open");
        }
        goto cleanup;
    }
    for (index = 0U; index < PF_TQ_SEED_CUSTODY_V2_COUNT; ++index) {
        if (fcntl(local.seeds[index].fd, F_SETFD, 0) != 0 ||
                fcntl(local.seeds[index].fd, F_GETFD) != 0) {
            (void)pf_tq_seed_error(error, error_size,
                "seed FD_CLOEXEC clear/recheck failed");
            goto cleanup;
        }
    }
    if (close(root_fd) != 0) {
        root_fd = -1;
        (void)pf_tq_seed_error(error, error_size,
            "seed root close failed: %s", strerror(errno));
        goto cleanup;
    }
    root_fd = -1;
    local.initialized = 1;
    *custody = local;
    OPENSSL_cleanse(&local, sizeof(local));
    result = 0;
cleanup:
    if (root_fd >= 0) (void)close(root_fd);
    if (result != 0) pf_tq_seed_custody_close_v2(&local);
    return result;
}
