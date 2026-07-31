#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <lean/lean.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <libproc.h>
#include <sys/acl.h>
#include <sys/event.h>
#else
#include <dirent.h>
#include <sys/random.h>
#include <sys/syscall.h>
#endif
#include <pthread.h>
#include <sys/resource.h>

#if defined(__APPLE__)
#define PF_STAT_MTIME_SEC(st) ((st).st_mtimespec.tv_sec)
#define PF_STAT_MTIME_NSEC(st) ((st).st_mtimespec.tv_nsec)
#define PF_STAT_CTIME_SEC(st) ((st).st_ctimespec.tv_sec)
#define PF_STAT_CTIME_NSEC(st) ((st).st_ctimespec.tv_nsec)
#else
#define PF_STAT_MTIME_SEC(st) ((st).st_mtim.tv_sec)
#define PF_STAT_MTIME_NSEC(st) ((st).st_mtim.tv_nsec)
#define PF_STAT_CTIME_SEC(st) ((st).st_ctim.tv_sec)
#define PF_STAT_CTIME_NSEC(st) ((st).st_ctim.tv_nsec)
#endif

static lean_object *pf_except(uint8_t tag, lean_object *value) {
  lean_object *result = lean_alloc_ctor(tag, 1, 0);
  lean_ctor_set(result, 0, value);
  return result;
}

static lean_object *pf_io_error(const char *fault) {
  return lean_io_result_mk_ok(pf_except(0, lean_mk_string(fault)));
}

static lean_object *pf_io_success(const uint8_t *data, size_t size) {
  lean_object *bytes = lean_alloc_sarray(1, size, size);
  if (size != 0) {
    memcpy(lean_sarray_cptr(bytes), data, size);
  }
  return lean_io_result_mk_ok(pf_except(1, bytes));
}

static const char *pf_open_fault(int error) {
  switch (error) {
    case ENOENT:
      return "not-found";
    case EACCES:
    case EPERM:
      return "permission-denied";
    case ELOOP:
    case ENOTDIR:
      return "unsafe-path";
    default:
      return "io";
  }
}

static int pf_valid_component(const char *component) {
  return component[0] != '\0' && strcmp(component, ".") != 0 &&
         strcmp(component, "..") != 0;
}

static char *pf_copy_string(const char *input) {
  size_t size = strlen(input);
  char *copy = (char *)malloc(size + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, input, size + 1);
  return copy;
}

static int pf_open_directory_component(int parent_fd, const char *component,
                                       const char **fault) {
  int flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC;
  int next_fd = openat(parent_fd, component, flags);
  if (next_fd < 0) {
    *fault = pf_open_fault(errno);
    return -1;
  }
  struct stat metadata;
  if (fstat(next_fd, &metadata) != 0) {
    close(next_fd);
    *fault = "io";
    return -1;
  }
  if (!S_ISDIR(metadata.st_mode)) {
    close(next_fd);
    *fault = "unsafe-path";
    return -1;
  }
  return next_fd;
}

static int pf_open_absolute_root(const char *root, const char **fault) {
  if (root[0] != '/') {
    *fault = "invalid-root";
    return -1;
  }
  int current_fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (current_fd < 0) {
    *fault = "io";
    return -1;
  }
  if (root[1] == '\0') {
    return current_fd;
  }

  char *copy = pf_copy_string(root + 1);
  if (copy == NULL) {
    close(current_fd);
    *fault = "io";
    return -1;
  }
  char *cursor = copy;
  while (1) {
    char *slash = strchr(cursor, '/');
    if (slash != NULL) {
      *slash = '\0';
    }
    if (!pf_valid_component(cursor)) {
      free(copy);
      close(current_fd);
      *fault = "invalid-root";
      return -1;
    }
    int next_fd = pf_open_directory_component(current_fd, cursor, fault);
    if (next_fd < 0) {
      free(copy);
      close(current_fd);
      return -1;
    }
    close(current_fd);
    current_fd = next_fd;
    if (slash == NULL) {
      break;
    }
    cursor = slash + 1;
  }
  free(copy);
  return current_fd;
}

static int pf_open_relative_parent(int root_fd, char *relative, char **leaf,
                                   const char **fault) {
  if (relative[0] == '\0' || relative[0] == '/') {
    *fault = "unsafe-path";
    return -1;
  }
  int current_fd = root_fd;
  char *cursor = relative;
  while (1) {
    char *slash = strchr(cursor, '/');
    if (slash == NULL) {
      if (!pf_valid_component(cursor)) {
        if (current_fd != root_fd) {
          close(current_fd);
        }
        *fault = "unsafe-path";
        return -1;
      }
      *leaf = cursor;
      return current_fd;
    }
    *slash = '\0';
    if (!pf_valid_component(cursor)) {
      if (current_fd != root_fd) {
        close(current_fd);
      }
      *fault = "unsafe-path";
      return -1;
    }
    int next_fd = pf_open_directory_component(current_fd, cursor, fault);
    if (next_fd < 0) {
      if (current_fd != root_fd) {
        close(current_fd);
      }
      return -1;
    }
    if (current_fd != root_fd) {
      close(current_fd);
    }
    current_fd = next_fd;
    cursor = slash + 1;
  }
}

static int pf_same_snapshot(const struct stat *before, const struct stat *after) {
  return before->st_dev == after->st_dev && before->st_ino == after->st_ino &&
         before->st_mode == after->st_mode && before->st_nlink == after->st_nlink &&
         before->st_size == after->st_size &&
         PF_STAT_MTIME_SEC(*before) == PF_STAT_MTIME_SEC(*after) &&
         PF_STAT_MTIME_NSEC(*before) == PF_STAT_MTIME_NSEC(*after) &&
         PF_STAT_CTIME_SEC(*before) == PF_STAT_CTIME_SEC(*after) &&
         PF_STAT_CTIME_NSEC(*before) == PF_STAT_CTIME_NSEC(*after);
}

LEAN_EXPORT lean_obj_res proof_forge_safe_open_source_v1(
    b_lean_obj_arg root_object, b_lean_obj_arg relative_object, uint64_t max_bytes,
    lean_obj_arg world) {
  (void)world;
  const char *fault = "io";
  const char *root = lean_string_cstr(root_object);
  const char *relative_input = lean_string_cstr(relative_object);
  char *relative = NULL;
  char *leaf = NULL;
  uint8_t *buffer = NULL;
  int root_fd = -1;
  int parent_fd = -1;
  int file_fd = -1;
  lean_object *result = NULL;

  if (max_bytes > (uint64_t)(SIZE_MAX - 1)) {
    return pf_io_error("native-protocol");
  }
  root_fd = pf_open_absolute_root(root, &fault);
  if (root_fd < 0) {
    return pf_io_error(fault);
  }
  relative = pf_copy_string(relative_input);
  if (relative == NULL) {
    close(root_fd);
    return pf_io_error("io");
  }
  parent_fd = pf_open_relative_parent(root_fd, relative, &leaf, &fault);
  if (parent_fd < 0) {
    free(relative);
    close(root_fd);
    return pf_io_error(fault);
  }

  file_fd = openat(parent_fd, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (file_fd < 0) {
    fault = pf_open_fault(errno);
    goto cleanup_error;
  }

  struct stat before;
  if (fstat(file_fd, &before) != 0) {
    fault = "io";
    goto cleanup_error;
  }
  if (!S_ISREG(before.st_mode)) {
    fault = "non-regular";
    goto cleanup_error;
  }
  if (before.st_nlink != 1) {
    fault = "multiple-links";
    goto cleanup_error;
  }
  if (before.st_size < 0) {
    fault = "changed-during-read";
    goto cleanup_error;
  }
  uint64_t initial_size_u64 = (uint64_t)before.st_size;
  if (initial_size_u64 > max_bytes) {
    fault = "too-large";
    goto cleanup_error;
  }
  size_t initial_size = (size_t)initial_size_u64;
  buffer = (uint8_t *)malloc(initial_size + 1);
  if (buffer == NULL) {
    fault = "io";
    goto cleanup_error;
  }

  size_t total = 0;
  while (total <= initial_size) {
    size_t remaining = initial_size + 1 - total;
    size_t wanted = remaining < 65536 ? remaining : 65536;
    ssize_t count = read(file_fd, buffer + total, wanted);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      fault = "io";
      goto cleanup_error;
    }
    if (count == 0) {
      break;
    }
    total += (size_t)count;
  }
  if (total < initial_size) {
    fault = "short-read";
    goto cleanup_error;
  }
  if (total > initial_size) {
    fault = "grew-during-read";
    goto cleanup_error;
  }

  struct stat after;
  struct stat path_after;
  if (fstat(file_fd, &after) != 0 ||
      fstatat(parent_fd, leaf, &path_after, AT_SYMLINK_NOFOLLOW) != 0) {
    fault = "changed-during-read";
    goto cleanup_error;
  }
  if (!pf_same_snapshot(&before, &after) || !pf_same_snapshot(&before, &path_after)) {
    fault = "changed-during-read";
    goto cleanup_error;
  }

  result = pf_io_success(buffer, initial_size);
  free(buffer);
  close(file_fd);
  if (parent_fd != root_fd) {
    close(parent_fd);
  }
  close(root_fd);
  free(relative);
  return result;

cleanup_error:
  if (buffer != NULL) {
    free(buffer);
  }
  if (file_fd >= 0) {
    close(file_fd);
  }
  if (parent_fd >= 0 && parent_fd != root_fd) {
    close(parent_fd);
  }
  if (root_fd >= 0) {
    close(root_fd);
  }
  free(relative);
  return pf_io_error(fault);
}

/* -------------------------------------------------------------------------- */
/* Development-observed worker supervisor FFI. Darwin retains vnode/libproc
   observation; Linux uses private snapshots and /proc process-group sampling.
   Neither branch contains setsid or cgroup/controller escape. */
/* Closed frame: magic PFSUPV1\0 + event/cleanup + LE observations + payload. */
/* -------------------------------------------------------------------------- */

enum {
  PF_SUP_HEADER_SIZE = 36
};

static int pf_worker_path_invalid(b_lean_obj_arg worker_object,
                                  const char *path) {
  if (path == NULL || path[0] == '\0') {
    return 1;
  }
  /* lean_string_size includes the terminating NUL. Mismatch ⇒ embedded NUL. */
  size_t reported = lean_string_size(worker_object);
  if (reported == 0) {
    return 1;
  }
  size_t content = reported - 1;
  if (strlen(path) != content) {
    return 1;
  }
  return 0;
}

#if defined(__APPLE__) || defined(__linux__)

enum {
  PF_SUP_EV_RESPONSE = 0,
  PF_SUP_EV_PROCESS = 1,
  PF_SUP_EV_MEMORY = 2,
  PF_SUP_EV_OUTPUT = 3,
  PF_SUP_EV_DEADLINE = 4,
  PF_SUP_EV_EXIT = 5,
  PF_SUP_EV_SIGNAL = 6,
  PF_SUP_EV_FAULT = 7
};

enum {
  PF_SUP_CLEAN_COMPLETE = 0,
  PF_SUP_CLEAN_INCOMPLETE = 1
};

enum {
  PF_SUP_CLEANUP_BUDGET_MS = 2000,
  PF_SUP_POLL_SLICE_MS = 10,
  PF_SUP_CLEANUP_MAX_SLICES = 208
};

static char *pf_env_assignment(const char *key, const char *value) {
  if (key == NULL || value == NULL || value[0] == '\0') {
    return NULL;
  }
  size_t key_len = strlen(key);
  size_t value_len = strlen(value);
  if (key_len > SIZE_MAX - value_len - 2) {
    return NULL;
  }
  size_t total = key_len + 1 + value_len + 1;
  char *entry = (char *)malloc(total);
  if (entry == NULL) {
    return NULL;
  }
  memcpy(entry, key, key_len);
  entry[key_len] = '=';
  memcpy(entry + key_len + 1, value, value_len + 1);
  return entry;
}

static void pf_write_u32_le(uint8_t *dst, uint32_t value) {
  dst[0] = (uint8_t)(value & 0xffu);
  dst[1] = (uint8_t)((value >> 8) & 0xffu);
  dst[2] = (uint8_t)((value >> 16) & 0xffu);
  dst[3] = (uint8_t)((value >> 24) & 0xffu);
}

static void pf_write_u64_le(uint8_t *dst, uint64_t value) {
  dst[0] = (uint8_t)(value & 0xffu);
  dst[1] = (uint8_t)((value >> 8) & 0xffu);
  dst[2] = (uint8_t)((value >> 16) & 0xffu);
  dst[3] = (uint8_t)((value >> 24) & 0xffu);
  dst[4] = (uint8_t)((value >> 32) & 0xffu);
  dst[5] = (uint8_t)((value >> 40) & 0xffu);
  dst[6] = (uint8_t)((value >> 48) & 0xffu);
  dst[7] = (uint8_t)((value >> 56) & 0xffu);
}

static int pf_size_add_overflows(size_t a, size_t b) {
  return b > SIZE_MAX - a;
}

static int pf_u64_to_size(uint64_t value, size_t *out) {
  if (value > (uint64_t)SIZE_MAX) {
    return 0;
  }
  *out = (size_t)value;
  return 1;
}

static uint64_t pf_saturate_u64_plus_one(uint64_t value) {
  if (value == UINT64_MAX) {
    return value;
  }
  return value + 1u;
}

static uint32_t pf_saturate_u32_plus_one(uint32_t value) {
  if (value == UINT32_MAX) {
    return value;
  }
  return value + 1u;
}

static uint64_t pf_clamp_u64(uint64_t value, uint64_t limit) {
  return value > limit ? limit : value;
}

static uint32_t pf_clamp_u32(uint32_t value, uint32_t limit) {
  return value > limit ? limit : value;
}

static int pf_clock_ms(uint64_t *out_ms) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
    return -1;
  }
  if ((uint64_t)ts.tv_sec > UINT64_MAX / 1000u) {
    *out_ms = UINT64_MAX;
    return 0;
  }
  uint64_t ms = (uint64_t)ts.tv_sec * 1000u;
  uint64_t nsec_ms = (uint64_t)ts.tv_nsec / 1000000u;
  if (ms > UINT64_MAX - nsec_ms) {
    *out_ms = UINT64_MAX;
  } else {
    *out_ms = ms + nsec_ms;
  }
  return 0;
}

static uint64_t pf_elapsed_ms(uint64_t start_ms, uint64_t now_ms) {
  if (now_ms < start_ms) {
    return 0;
  }
  return now_ms - start_ms;
}

static int pf_set_cloexec(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) {
    return -1;
  }
  return fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0 ? 0 : -1;
}

static int pf_set_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) {
    return -1;
  }
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 ? 0 : -1;
}

static int pf_set_cloexec_nonblock(int fd) {
  return pf_set_cloexec(fd) == 0 && pf_set_nonblock(fd) == 0 ? 0 : -1;
}

static int pf_set_nosigpipe(int fd) {
#if defined(__APPLE__)
  return fcntl(fd, F_SETNOSIGPIPE, 1) == 0 ? 0 : -1;
#else
  (void)fd;
  return 0;
#endif
}

static void pf_close_fd(int *fd) {
  if (fd != NULL && *fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

enum {
  PF_SUP_MAX_WORKER_BYTES = 512 * 1024 * 1024,
  PF_SUP_SNAPSHOT_RANDOM_BYTES = 16,
  PF_SUP_SNAPSHOT_RANDOM_HEX = PF_SUP_SNAPSHOT_RANDOM_BYTES * 2
};

#define PF_SUP_SNAPSHOT_PREFIX ".proof-forge-worker-"
#define PF_SUP_SNAPSHOT_NAME "worker"

typedef struct {
  int source_fd;
  int directory_fd;
  int worker_fd;
  int watch_fd;
  int directory_created;
  int worker_created;
  char directory_path[PATH_MAX];
  char worker_path[PATH_MAX];
  struct stat directory_expected;
  struct stat worker_expected;
} pf_worker_snapshot;

static void pf_worker_snapshot_init(pf_worker_snapshot *snapshot) {
  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->source_fd = -1;
  snapshot->directory_fd = -1;
  snapshot->worker_fd = -1;
  snapshot->watch_fd = -1;
}

static int pf_same_file_identity(const struct stat *left,
                                 const struct stat *right) {
  return left->st_dev == right->st_dev && left->st_ino == right->st_ino;
}

/* A fresh inode may inherit an extended ACL from its parent. POSIX mode bits
   alone therefore cannot establish a private snapshot on Darwin. Replace any
   inherited ACL with the empty ACL and require the kernel to report no ACL. */
static int pf_clear_and_verify_extended_acl(int fd) {
#if defined(__APPLE__)
  acl_t empty_acl = acl_init(0);
  if (empty_acl == NULL) {
    return -1;
  }
  int set_result = acl_set_fd_np(fd, empty_acl, ACL_TYPE_EXTENDED);
  (void)acl_free(empty_acl);
  if (set_result != 0) {
    return -1;
  }

  errno = 0;
  acl_t observed = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
  if (observed == NULL) {
    return errno == ENOENT ? 0 : -1;
  }
  acl_entry_t first_entry = NULL;
  int first_result = acl_get_entry(observed, ACL_FIRST_ENTRY, &first_entry);
  (void)acl_free(observed);
  return first_result == 0 ? 0 : -1;
#else
  (void)fd;
  return 0;
#endif
}

static int pf_create_snapshot_directory(pf_worker_snapshot *snapshot,
                                        const char *worker_path) {
#if defined(__APPLE__)
  static const char hex[] = "0123456789abcdef";
  const size_t prefix_len = sizeof(PF_SUP_SNAPSHOT_PREFIX) - 1;
  const size_t worker_name_len = sizeof(PF_SUP_SNAPSHOT_NAME) - 1;
  uint8_t random_bytes[PF_SUP_SNAPSHOT_RANDOM_BYTES];
  char source_path[PATH_MAX];
  if (fcntl(snapshot->source_fd, F_GETPATH, source_path) != 0 ||
      source_path[0] != '/') {
    return -1;
  }
  char *last_slash = strrchr(source_path, '/');
  if (last_slash == NULL || last_slash[1] == '\0') {
    return -1;
  }
  size_t parent_len =
      last_slash == source_path ? 1 : (size_t)(last_slash - source_path);
  size_t separator_len = parent_len == 1 ? 0 : 1;
  if (parent_len + separator_len + prefix_len + PF_SUP_SNAPSHOT_RANDOM_HEX + 1 >
      sizeof(snapshot->directory_path)) {
    return -1;
  }

  int attempt;
  for (attempt = 0; attempt < 16; attempt++) {
    arc4random_buf(random_bytes, sizeof(random_bytes));
    memcpy(snapshot->directory_path, source_path, parent_len);
    size_t cursor = parent_len;
    if (separator_len != 0) {
      snapshot->directory_path[cursor++] = '/';
    }
    memcpy(snapshot->directory_path + cursor, PF_SUP_SNAPSHOT_PREFIX,
           prefix_len);
    cursor += prefix_len;
    int i;
    for (i = 0; i < PF_SUP_SNAPSHOT_RANDOM_BYTES; i++) {
      snapshot->directory_path[cursor + (size_t)i * 2] =
          hex[random_bytes[i] >> 4];
      snapshot->directory_path[cursor + (size_t)i * 2 + 1] =
          hex[random_bytes[i] & 0x0fu];
    }
    snapshot->directory_path[cursor + PF_SUP_SNAPSHOT_RANDOM_HEX] = '\0';
    if (mkdir(snapshot->directory_path, 0700) == 0) {
      snapshot->directory_created = 1;
      break;
    }
    if (errno != EEXIST) {
      return -1;
    }
  }
  if (!snapshot->directory_created) {
    return -1;
  }

  snapshot->directory_fd =
      open(snapshot->directory_path,
           O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (snapshot->directory_fd < 0) {
    return -1;
  }
  struct stat directory_metadata;
  if (fstat(snapshot->directory_fd, &directory_metadata) != 0 ||
      !S_ISDIR(directory_metadata.st_mode) ||
      directory_metadata.st_uid != geteuid() ||
      fchmod(snapshot->directory_fd, 0700) != 0 ||
      pf_clear_and_verify_extended_acl(snapshot->directory_fd) != 0) {
    return -1;
  }

  size_t directory_len = strlen(snapshot->directory_path);
  if (directory_len + 1 + worker_name_len + 1 >
      sizeof(snapshot->worker_path)) {
    return -1;
  }
  memcpy(snapshot->worker_path, snapshot->directory_path, directory_len);
  snapshot->worker_path[directory_len] = '/';
  memcpy(snapshot->worker_path + directory_len + 1, PF_SUP_SNAPSHOT_NAME,
         worker_name_len + 1);
  return 0;
#else
  (void)worker_path;
  static const char hex[] = "0123456789abcdef";
  static const char snapshot_root[] = "/tmp";
  uint8_t random_bytes[PF_SUP_SNAPSHOT_RANDOM_BYTES];
  struct stat root_metadata;
  int root_fd = open(snapshot_root,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (root_fd < 0 || fstat(root_fd, &root_metadata) != 0 ||
      !S_ISDIR(root_metadata.st_mode) || root_metadata.st_uid != 0 ||
      (root_metadata.st_mode & S_ISVTX) == 0) {
    if (root_fd >= 0) close(root_fd);
    return -1;
  }
  char leaf[sizeof(PF_SUP_SNAPSHOT_PREFIX) + PF_SUP_SNAPSHOT_RANDOM_HEX];
  memcpy(leaf, PF_SUP_SNAPSHOT_PREFIX, sizeof(PF_SUP_SNAPSHOT_PREFIX) - 1);
  int created = 0;
  for (int attempt = 0; attempt < 16 && !created; attempt++) {
    ssize_t random_count;
    do {
      random_count = getrandom(random_bytes, sizeof(random_bytes), 0);
    } while (random_count < 0 && errno == EINTR);
    if (random_count != (ssize_t)sizeof(random_bytes)) {
      close(root_fd);
      return -1;
    }
    size_t cursor = sizeof(PF_SUP_SNAPSHOT_PREFIX) - 1;
    for (int i = 0; i < PF_SUP_SNAPSHOT_RANDOM_BYTES; i++) {
      leaf[cursor + (size_t)i * 2] = hex[random_bytes[i] >> 4];
      leaf[cursor + (size_t)i * 2 + 1] = hex[random_bytes[i] & 0x0fu];
    }
    leaf[cursor + PF_SUP_SNAPSHOT_RANDOM_HEX] = '\0';
    if (mkdirat(root_fd, leaf, 0700) == 0) {
      created = 1;
    } else if (errno != EEXIST) {
      close(root_fd);
      return -1;
    }
  }
  if (!created) {
    close(root_fd);
    return -1;
  }
  snapshot->directory_created = 1;
  int written = snprintf(snapshot->directory_path,
      sizeof(snapshot->directory_path), "%s/%s", snapshot_root, leaf);
  if (written < 0 || (size_t)written >= sizeof(snapshot->directory_path)) {
    (void)unlinkat(root_fd, leaf, AT_REMOVEDIR);
    close(root_fd);
    return -1;
  }
  snapshot->directory_fd = openat(root_fd, leaf,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  close(root_fd);
  if (snapshot->directory_fd < 0 || fchmod(snapshot->directory_fd, 0700) != 0) {
    return -1;
  }
  written = snprintf(snapshot->worker_path, sizeof(snapshot->worker_path),
                     "%s/%s", snapshot->directory_path, PF_SUP_SNAPSHOT_NAME);
  return written >= 0 && (size_t)written < sizeof(snapshot->worker_path) ? 0 : -1;
#endif
}

static int pf_budget_status(uint64_t budget_start_ms, uint64_t max_wall_ms) {
  uint64_t now_ms = 0;
  if (pf_clock_ms(&now_ms) != 0 || now_ms < budget_start_ms) {
    return -1;
  }
  return pf_elapsed_ms(budget_start_ms, now_ms) >= max_wall_ms ? 1 : 0;
}

static int pf_copy_worker_bytes(int source_fd, int destination_fd,
                                off_t expected_size,
                                uint64_t budget_start_ms,
                                uint64_t max_wall_ms) {
  uint8_t buffer[64 * 1024];
  off_t offset = 0;
  while (offset < expected_size) {
    off_t remaining = expected_size - offset;
    size_t wanted = remaining > (off_t)sizeof(buffer)
                        ? sizeof(buffer)
                        : (size_t)remaining;
    ssize_t read_count;
    do {
      read_count = pread(source_fd, buffer, wanted, offset);
    } while (read_count < 0 && errno == EINTR);
    if (read_count <= 0) {
      return -1;
    }

    ssize_t written = 0;
    while (written < read_count) {
      ssize_t write_count;
      do {
        write_count = pwrite(destination_fd, buffer + written,
                             (size_t)(read_count - written), offset + written);
      } while (write_count < 0 && errno == EINTR);
      if (write_count <= 0) {
        return -1;
      }
      written += write_count;
    }
    offset += read_count;
    int budget = pf_budget_status(budget_start_ms, max_wall_ms);
    if (budget != 0) {
      return budget;
    }
  }

  uint8_t probe = 0;
  ssize_t probe_count;
  do {
    probe_count = pread(source_fd, &probe, 1, expected_size);
  } while (probe_count < 0 && errno == EINTR);
  return probe_count == 0 ? 0 : -1;
}

static int pf_arm_snapshot_watch(pf_worker_snapshot *snapshot) {
#if defined(__APPLE__)
  snapshot->watch_fd = kqueue();
  if (snapshot->watch_fd < 0 || pf_set_cloexec(snapshot->watch_fd) != 0) {
    return -1;
  }
  /* Executing a vnode may emit NOTE_ATTRIB for atime bookkeeping. Attribute-
     only churn cannot change the bound bytes; static mode/link changes are
     still caught by the metadata comparisons, while any content/path swap
     emits one of the byte- or directory-mutation flags below. */
  const uint32_t watch_flags = NOTE_WRITE | NOTE_EXTEND | NOTE_LINK |
                               NOTE_RENAME | NOTE_DELETE | NOTE_REVOKE;
  struct kevent changes[2];
  EV_SET(&changes[0], (uintptr_t)snapshot->directory_fd, EVFILT_VNODE,
         EV_ADD | EV_ENABLE | EV_CLEAR, watch_flags, 0, NULL);
  EV_SET(&changes[1], (uintptr_t)snapshot->worker_fd, EVFILT_VNODE,
         EV_ADD | EV_ENABLE | EV_CLEAR, watch_flags, 0, NULL);
  return kevent(snapshot->watch_fd, changes, 2, NULL, 0, NULL) == 0 ? 0 : -1;
#else
  (void)snapshot;
  return 0;
#endif
}

static int pf_snapshot_events_pending(pf_worker_snapshot *snapshot) {
#if defined(__APPLE__)
  struct kevent events[2];
  struct timespec timeout;
  timeout.tv_sec = 0;
  timeout.tv_nsec = 0;
  int count;
  do {
    count = kevent(snapshot->watch_fd, NULL, 0, events, 2, &timeout);
  } while (count < 0 && errno == EINTR);
  if (count < 0) {
    return -1;
  }
  return count == 0 ? 0 : 1;
#else
  (void)snapshot;
  return 0;
#endif
}

/* Check before and after metadata reads so a path swap cannot hide between the
   vnode event probe and fstatat. A second call after suspended spawn binds the
   executable image to the exact private snapshot before any worker code runs. */
static int pf_worker_snapshot_changed(pf_worker_snapshot *snapshot) {
  int events = pf_snapshot_events_pending(snapshot);
  if (events != 0) {
    return events;
  }
  struct stat directory_metadata;
  struct stat directory_path_metadata;
  struct stat worker_metadata;
  struct stat worker_path_metadata;
  if (fstat(snapshot->directory_fd, &directory_metadata) != 0 ||
      lstat(snapshot->directory_path, &directory_path_metadata) != 0 ||
      fstat(snapshot->worker_fd, &worker_metadata) != 0 ||
      fstatat(snapshot->directory_fd, PF_SUP_SNAPSHOT_NAME,
              &worker_path_metadata, AT_SYMLINK_NOFOLLOW) != 0) {
    return -1;
  }
  if (!pf_same_snapshot(&snapshot->directory_expected, &directory_metadata) ||
      !pf_same_file_identity(&directory_metadata, &directory_path_metadata) ||
      !pf_same_snapshot(&snapshot->worker_expected, &worker_metadata) ||
      !pf_same_snapshot(&snapshot->worker_expected, &worker_path_metadata)) {
    return 1;
  }
  events = pf_snapshot_events_pending(snapshot);
  return events;
}

/* Return 0 on success, 1 if the absolute wall expired, and -1 on a closed
   snapshot fault. The source fd, not its pathname, is the sole byte authority. */
static int pf_prepare_worker_snapshot(const char *worker_path,
                                      uint64_t budget_start_ms,
                                      uint64_t max_wall_ms,
                                      pf_worker_snapshot *snapshot) {
  snapshot->source_fd =
      open(worker_path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (snapshot->source_fd < 0) {
    return -1;
  }
  struct stat source_before;
  if (fstat(snapshot->source_fd, &source_before) != 0 ||
      !S_ISREG(source_before.st_mode) || source_before.st_nlink != 1 ||
      source_before.st_size <= 0 ||
      source_before.st_size > (off_t)PF_SUP_MAX_WORKER_BYTES ||
      (source_before.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) == 0) {
    return -1;
  }
  int budget = pf_budget_status(budget_start_ms, max_wall_ms);
  if (budget != 0) {
    return budget;
  }
  if (pf_create_snapshot_directory(snapshot, worker_path) != 0) {
    return -1;
  }

  int destination_fd =
      openat(snapshot->directory_fd, PF_SUP_SNAPSHOT_NAME,
             O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (destination_fd < 0) {
    return -1;
  }
  snapshot->worker_created = 1;
  int copy_result = pf_clear_and_verify_extended_acl(destination_fd);
  if (copy_result == 0) {
    copy_result = pf_copy_worker_bytes(snapshot->source_fd, destination_fd,
                                       source_before.st_size, budget_start_ms,
                                       max_wall_ms);
  }
  if (copy_result == 0 && fsync(destination_fd) != 0) {
    copy_result = -1;
  }
  close(destination_fd);
  if (copy_result != 0) {
    return copy_result;
  }

  snapshot->worker_fd =
      openat(snapshot->directory_fd, PF_SUP_SNAPSHOT_NAME,
             O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (snapshot->worker_fd < 0 || fchmod(snapshot->worker_fd, 0500) != 0 ||
      pf_clear_and_verify_extended_acl(snapshot->worker_fd) != 0 ||
      fsync(snapshot->worker_fd) != 0) {
    return -1;
  }
  struct stat source_after;
  if (fstat(snapshot->source_fd, &source_after) != 0 ||
      !pf_same_snapshot(&source_before, &source_after) ||
      fstat(snapshot->worker_fd, &snapshot->worker_expected) != 0 ||
      !S_ISREG(snapshot->worker_expected.st_mode) ||
      snapshot->worker_expected.st_nlink != 1 ||
      snapshot->worker_expected.st_size != source_before.st_size ||
      (snapshot->worker_expected.st_mode & 0777) != 0500) {
    return -1;
  }
  pf_close_fd(&snapshot->source_fd);

  if (fchmod(snapshot->directory_fd, 0500) != 0 ||
      pf_clear_and_verify_extended_acl(snapshot->directory_fd) != 0 ||
      fsync(snapshot->directory_fd) != 0 ||
      fstat(snapshot->directory_fd, &snapshot->directory_expected) != 0 ||
      (snapshot->directory_expected.st_mode & 0777) != 0500 ||
      pf_arm_snapshot_watch(snapshot) != 0) {
    return -1;
  }
  budget = pf_budget_status(budget_start_ms, max_wall_ms);
  if (budget != 0) {
    return budget;
  }
  return pf_worker_snapshot_changed(snapshot) == 0 ? 0 : -1;
}

static int pf_cleanup_worker_snapshot(pf_worker_snapshot *snapshot) {
  int clean = 1;
  pf_close_fd(&snapshot->watch_fd);
  pf_close_fd(&snapshot->source_fd);
  pf_close_fd(&snapshot->worker_fd);
  if (snapshot->directory_fd >= 0) {
    if (fchmod(snapshot->directory_fd, 0700) != 0) {
      clean = 0;
    }
    if (snapshot->worker_created &&
        unlinkat(snapshot->directory_fd, PF_SUP_SNAPSHOT_NAME, 0) != 0) {
      clean = 0;
    }
    struct stat held_directory;
    struct stat path_directory;
    int identity_ok =
        fstat(snapshot->directory_fd, &held_directory) == 0 &&
        lstat(snapshot->directory_path, &path_directory) == 0 &&
        pf_same_file_identity(&held_directory, &path_directory);
    pf_close_fd(&snapshot->directory_fd);
    if (!identity_ok || rmdir(snapshot->directory_path) != 0) {
      clean = 0;
    }
  } else if (snapshot->directory_created) {
    if (rmdir(snapshot->directory_path) != 0) {
      clean = 0;
    }
  }
  snapshot->worker_created = 0;
  snapshot->directory_created = 0;
  return clean ? 0 : -1;
}

static int pf_snapshot_pgroup(pid_t pgid, pid_t **out_pids, int *out_count) {
#if defined(__APPLE__)
  *out_pids = NULL;
  *out_count = 0;
  errno = 0;
  int needed = proc_listpids(PROC_PGRP_ONLY, (uint32_t)pgid, NULL, 0);
  if (needed < 0 || (needed == 0 && errno != 0)) {
    return -1;
  }
  if (needed == 0) {
    return 0;
  }
  int extra = (int)sizeof(pid_t) * 16;
  if (needed > INT_MAX - extra) {
    return -1;
  }
  int alloc = needed + extra;
  int attempt;
  for (attempt = 0; attempt < 4; attempt++) {
    pid_t *pids = (pid_t *)malloc((size_t)alloc);
    if (pids == NULL) {
      return -1;
    }
    errno = 0;
    int got = proc_listpids(PROC_PGRP_ONLY, (uint32_t)pgid, pids, alloc);
    if (got < 0 || (got == 0 && errno != 0) ||
        got % (int)sizeof(pid_t) != 0) {
      free(pids);
      return -1;
    }
    if (got < alloc) {
      *out_pids = pids;
      *out_count = got / (int)sizeof(pid_t);
      return 0;
    }
    free(pids);
    if (alloc > INT_MAX / 2) {
      return -1;
    }
    alloc *= 2;
  }
  return -1;
#else
  DIR *proc = opendir("/proc");
  if (proc == NULL) return -1;
  size_t cap = 16;
  size_t count = 0;
  pid_t *pids = malloc(cap * sizeof(*pids));
  if (pids == NULL) { closedir(proc); return -1; }
  struct dirent *entry;
  for (;;) {
    errno = 0;
    entry = readdir(proc);
    if (entry == NULL) {
      if (errno != 0) { free(pids); closedir(proc); return -1; }
      break;
    }
    char *end = NULL;
    long value = strtol(entry->d_name, &end, 10);
    if (entry->d_name[0] == '\0' || *end != '\0' || value <= 0 || value > INT_MAX)
      continue;
    pid_t pid = (pid_t)value;
    pid_t observed_pgid = getpgid(pid);
    if (observed_pgid < 0) {
      if (errno == ESRCH) continue;
      free(pids);
      closedir(proc);
      return -1;
    }
    if (observed_pgid != pgid) continue;
    if (count == cap) {
      if (cap > SIZE_MAX / 2 / sizeof(*pids)) { free(pids); closedir(proc); return -1; }
      cap *= 2;
      pid_t *grown = realloc(pids, cap * sizeof(*pids));
      if (grown == NULL) { free(pids); closedir(proc); return -1; }
      pids = grown;
    }
    pids[count++] = pid;
  }
  closedir(proc);
  *out_pids = pids;
  *out_count = (int)count;
  return 0;
#endif
}

static int pf_sample_pgroup(pid_t pgid, uint32_t *out_count,
                            uint64_t *out_memory) {
  pid_t *pids = NULL;
  int n = 0;
  if (pf_snapshot_pgroup(pgid, &pids, &n) != 0) {
    return -1;
  }
  uint32_t count = 0;
  uint64_t total = 0;
#if defined(__linux__)
  long page_size = sysconf(_SC_PAGESIZE);
  if (page_size <= 0) {
    free(pids);
    return -1;
  }
#endif
  int i;
  for (i = 0; i < n; i++) {
    pid_t member = pids[i];
    if (member == 0) {
      continue;
    }
    if (count == UINT32_MAX) {
      free(pids);
      return -1;
    }
    count++;
#if defined(__APPLE__)
    struct rusage_info_v4 info;
    memset(&info, 0, sizeof(info));
    if (proc_pid_rusage((int)member, RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) {
      /* list→rusage races with exit are expected; count remains conservative. */
      continue;
    }
    uint64_t rss = info.ri_phys_footprint;
#else
    char statm_path[64];
    int path_len = snprintf(statm_path, sizeof(statm_path), "/proc/%d/statm", member);
    FILE *statm = path_len > 0 && (size_t)path_len < sizeof(statm_path)
                      ? fopen(statm_path, "r") : NULL;
    unsigned long pages_total = 0, pages_rss = 0;
    if (statm == NULL || fscanf(statm, "%lu %lu", &pages_total, &pages_rss) != 2) {
      if (statm != NULL) fclose(statm);
      if (kill(member, 0) != 0 && errno == ESRCH) continue;
      free(pids);
      return -1;
    }
    fclose(statm);
    (void)pages_total;
    if (pages_rss > UINT64_MAX / (uint64_t)page_size) {
      free(pids);
      return -1;
    }
    uint64_t rss = (uint64_t)pages_rss * (uint64_t)page_size;
#endif
    if (total > UINT64_MAX - rss) {
      total = UINT64_MAX;
    } else {
      total += rss;
    }
  }
  free(pids);
  *out_count = count;
  *out_memory = total;
  return 0;
}

static int pf_count_other_pgroup(pid_t pgid, pid_t leader,
                                 uint32_t *out_count) {
  pid_t *pids = NULL;
  int n = 0;
  if (pf_snapshot_pgroup(pgid, &pids, &n) != 0) {
    return -1;
  }
  uint32_t count = 0;
  int i;
  for (i = 0; i < n; i++) {
    if (pids[i] != 0 && pids[i] != leader) {
      if (count == UINT32_MAX) {
        free(pids);
        return -1;
      }
      count++;
    }
  }
  free(pids);
  *out_count = count;
  return 0;
}

static int pf_observe_child_exit(pid_t child, int *exited, int *status_valid,
                                 int *signaled, int *exit_value) {
  siginfo_t info;
  memset(&info, 0, sizeof(info));
  int rc;
  do {
    rc = waitid(P_PID, (id_t)child, &info, WEXITED | WNOHANG | WNOWAIT);
  } while (rc < 0 && errno == EINTR);
  if (rc < 0) {
    return errno == ECHILD ? 1 : -1;
  }
  if (info.si_pid == 0) {
    return 0;
  }
  *exited = 1;
  *status_valid = 1;
  if (info.si_code == CLD_EXITED) {
    *signaled = 0;
    *exit_value = info.si_status;
  } else if (info.si_code == CLD_KILLED || info.si_code == CLD_DUMPED) {
    *signaled = 1;
    *exit_value = info.si_status;
  } else {
    *status_valid = 0;
  }
  return 0;
}

static pid_t pf_waitpid_nohang(pid_t child) {
  pid_t result;
  do {
    result = waitpid(child, NULL, WNOHANG);
  } while (result < 0 && errno == EINTR);
  return result;
}

static void *pf_reap_child_thread(void *arg) {
  pid_t child = (pid_t)(intptr_t)arg;
  pid_t wr;
  do {
    wr = waitpid(child, NULL, 0);
  } while (wr < 0 && errno == EINTR);
  return NULL;
}

static int pf_schedule_child_reaper(pid_t child) {
  pthread_attr_t attr;
  pthread_t thread;
  if (pthread_attr_init(&attr) != 0) {
    return -1;
  }
  if (pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED) != 0) {
    pthread_attr_destroy(&attr);
    return -1;
  }
  int rc = pthread_create(&thread, &attr, pf_reap_child_thread,
                          (void *)(intptr_t)child);
  pthread_attr_destroy(&attr);
  return rc == 0 ? 0 : -1;
}

static lean_object *pf_build_supervisor_frame(
    uint8_t event, uint8_t cleanup, uint64_t elapsed_ms, uint64_t peak_memory,
    uint32_t peak_processes, const uint8_t *payload, uint32_t payload_len) {
  size_t total = (size_t)PF_SUP_HEADER_SIZE + (size_t)payload_len;
  uint8_t *frame = (uint8_t *)malloc(total == 0 ? 1 : total);
  if (frame == NULL) {
    return NULL;
  }
  memcpy(frame, "PFSUPV1", 7);
  frame[7] = 0;
  frame[8] = event;
  frame[9] = cleanup;
  frame[10] = 0;
  frame[11] = 0;
  pf_write_u64_le(frame + 12, elapsed_ms);
  pf_write_u64_le(frame + 20, peak_memory);
  pf_write_u32_le(frame + 28, peak_processes);
  pf_write_u32_le(frame + 32, payload_len);
  if (payload_len != 0 && payload != NULL) {
    memcpy(frame + PF_SUP_HEADER_SIZE, payload, payload_len);
  }
  lean_object *result = pf_io_success(frame, total);
  free(frame);
  return result;
}

static void pf_apply_observation_contract(
    uint8_t event, uint64_t max_wall_ms, uint64_t max_memory_bytes,
    uint32_t max_processes, uint64_t *elapsed_ms, uint64_t *peak_memory,
    uint32_t *peak_processes) {
  switch (event) {
    case PF_SUP_EV_PROCESS:
      *peak_processes = pf_saturate_u32_plus_one(max_processes);
      *elapsed_ms = pf_clamp_u64(*elapsed_ms, max_wall_ms);
      *peak_memory = pf_clamp_u64(*peak_memory, max_memory_bytes);
      break;
    case PF_SUP_EV_MEMORY:
      *peak_memory = pf_saturate_u64_plus_one(max_memory_bytes);
      *elapsed_ms = pf_clamp_u64(*elapsed_ms, max_wall_ms);
      *peak_processes = pf_clamp_u32(*peak_processes, max_processes);
      break;
    case PF_SUP_EV_DEADLINE:
      *elapsed_ms = pf_saturate_u64_plus_one(max_wall_ms);
      *peak_memory = pf_clamp_u64(*peak_memory, max_memory_bytes);
      *peak_processes = pf_clamp_u32(*peak_processes, max_processes);
      break;
    case PF_SUP_EV_OUTPUT:
    case PF_SUP_EV_RESPONSE:
    case PF_SUP_EV_EXIT:
    case PF_SUP_EV_SIGNAL:
    case PF_SUP_EV_FAULT:
    default:
      *elapsed_ms = pf_clamp_u64(*elapsed_ms, max_wall_ms);
      *peak_memory = pf_clamp_u64(*peak_memory, max_memory_bytes);
      *peak_processes = pf_clamp_u32(*peak_processes, max_processes);
      break;
  }
}

static ssize_t pf_read_into_capped(int fd, uint8_t *buf, size_t *len,
                                   size_t store_cap, int *eof_flag,
                                   int *overflow_flag) {
  if (*eof_flag || fd < 0) {
    return 0;
  }
  uint8_t discard[4096];
  for (;;) {
    size_t space = store_cap > *len ? store_cap - *len : 0;
    uint8_t *dest = space > 0 ? buf + *len : discard;
    size_t want = space > 0 ? space : sizeof(discard);
    if (want > 65536) {
      want = 65536;
    }
    ssize_t n = read(fd, dest, want);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return 0;
      }
      return -1;
    }
    if (n == 0) {
      *eof_flag = 1;
      return 0;
    }
    if (space > 0) {
      *len += (size_t)n;
      if (*len >= store_cap) {
        /* store_cap == limit+1 ⇒ reaching it means strictly over limit. */
        *overflow_flag = 1;
      }
    } else {
      *overflow_flag = 1;
    }
    if ((size_t)n < want) {
      return 0;
    }
    if (space == 0) {
      return 0;
    }
  }
}

static ssize_t pf_read_count_capped(int fd, size_t *len, size_t count_cap,
                                    int *eof_flag, int *overflow_flag) {
  if (*eof_flag || fd < 0) {
    return 0;
  }
  uint8_t discard[4096];
  for (;;) {
    size_t remaining = count_cap > *len ? count_cap - *len : 0;
    size_t want = remaining > 0 && remaining < sizeof(discard)
                      ? remaining
                      : sizeof(discard);
    ssize_t n = read(fd, discard, want);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return 0;
      }
      return -1;
    }
    if (n == 0) {
      *eof_flag = 1;
      return 0;
    }
    size_t observed = (size_t)n;
    size_t counted = observed < remaining ? observed : remaining;
    *len += counted;
    if (observed > counted || *len >= count_cap) {
      *overflow_flag = 1;
    }
    if (observed < want || remaining == 0) {
      return 0;
    }
  }
}

static int pf_write_stdin_progress(int fd, const uint8_t *data, size_t total,
                                   size_t *offset, int *done_flag) {
  if (*done_flag || fd < 0) {
    return 0;
  }
  while (*offset < total) {
    size_t remaining = total - *offset;
    size_t want = remaining > 65536 ? 65536 : remaining;
    ssize_t n = write(fd, data + *offset, want);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return 0;
      }
      if (errno == EPIPE) {
        *done_flag = 1;
        return 0;
      }
      return -1;
    }
    if (n == 0) {
      return 0;
    }
    *offset += (size_t)n;
  }
  *done_flag = 1;
  return 0;
}

static int pf_sample_group(pid_t pgid, uint32_t *peak_processes,
                           uint64_t *peak_memory) {
  uint32_t procs = 0;
  uint64_t mem = 0;
  if (pf_sample_pgroup(pgid, &procs, &mem) != 0) {
    return -1;
  }
  if (procs > *peak_processes) {
    *peak_processes = procs;
  }
  if (mem > *peak_memory) {
    *peak_memory = mem;
  }
  return 0;
}

static int pf_controller_event(uint32_t peak_processes, uint32_t max_processes,
                               uint64_t peak_memory, uint64_t max_memory_bytes,
                               int stdout_overflow, int stderr_overflow,
                               size_t stdout_len, size_t stderr_len,
                               size_t protocol_cap_sz, size_t stderr_cap_sz,
                               uint64_t elapsed_ms, uint64_t max_wall_ms,
                               uint8_t *out_event) {
  if ((uint64_t)peak_processes > (uint64_t)max_processes) {
    *out_event = PF_SUP_EV_PROCESS;
    return 1;
  }
  if (peak_memory > max_memory_bytes) {
    *out_event = PF_SUP_EV_MEMORY;
    return 1;
  }
  if (stdout_overflow || stderr_overflow || stdout_len > protocol_cap_sz ||
      stderr_len > stderr_cap_sz) {
    *out_event = PF_SUP_EV_OUTPUT;
    return 1;
  }
  if (elapsed_ms > max_wall_ms) {
    *out_event = PF_SUP_EV_DEADLINE;
    return 1;
  }
  return 0;
}

static lean_object *pf_supervise_worker_platform(
    const char *worker_path, const uint8_t *input_data, size_t input_size,
    uint64_t max_wall_ms, uint64_t max_memory_bytes, uint32_t max_processes,
    uint64_t max_protocol_bytes, uint64_t max_stderr_bytes,
    uint64_t budget_start_ms) {
  size_t protocol_cap_sz = 0;
  size_t stderr_cap_sz = 0;
  if (!pf_u64_to_size(max_protocol_bytes, &protocol_cap_sz) ||
      !pf_u64_to_size(max_stderr_bytes, &stderr_cap_sz) ||
      pf_size_add_overflows(protocol_cap_sz, 1) ||
      pf_size_add_overflows(stderr_cap_sz, 1)) {
    return pf_io_error("invalid-argument");
  }

  /* The private capability carries one absolute CLOCK_MONOTONIC origin across
     parent request construction and both child stages. Check it before the
     first stage allocation/pipe/spawn; an exhausted budget never spawns. */
  uint64_t stage_start_ms = 0;
  if (pf_clock_ms(&stage_start_ms) != 0 || stage_start_ms < budget_start_ms) {
    return pf_io_error("io");
  }
  uint64_t initial_elapsed = pf_elapsed_ms(budget_start_ms, stage_start_ms);
  if (initial_elapsed >= max_wall_ms) {
    lean_object *deadline = pf_build_supervisor_frame(
        PF_SUP_EV_DEADLINE, PF_SUP_CLEAN_COMPLETE,
        pf_saturate_u64_plus_one(max_wall_ms), 0, 0, NULL, 0);
    return deadline == NULL ? pf_io_error("io") : deadline;
  }

  /* Bind execution to an exact fd-derived private snapshot before any pipe or
     spawn. The existing absolute wall includes copy, ACL clearing, and verification. */
  pf_worker_snapshot worker_snapshot;
  pf_worker_snapshot_init(&worker_snapshot);
  int snapshot_result = pf_prepare_worker_snapshot(
      worker_path, budget_start_ms, max_wall_ms, &worker_snapshot);
  if (snapshot_result != 0) {
    int snapshot_cleanup = pf_cleanup_worker_snapshot(&worker_snapshot);
    if (snapshot_cleanup != 0) {
      return pf_io_error("io");
    }
    if (snapshot_result == 1) {
      lean_object *deadline = pf_build_supervisor_frame(
          PF_SUP_EV_DEADLINE, PF_SUP_CLEAN_COMPLETE,
          pf_saturate_u64_plus_one(max_wall_ms), 0, 0, NULL, 0);
      return deadline == NULL ? pf_io_error("io") : deadline;
    }
    return pf_io_error("spawn-failed");
  }

  size_t stdout_store_cap = protocol_cap_sz + 1;
  size_t stderr_store_cap = stderr_cap_sz + 1;
  uint8_t *stdout_buf =
      (uint8_t *)malloc(stdout_store_cap == 0 ? 1 : stdout_store_cap);
  if (stdout_buf == NULL) {
    if (pf_cleanup_worker_snapshot(&worker_snapshot) != 0) {
      return pf_io_error("io");
    }
    return pf_io_error("io");
  }

  int in_pipe[2] = {-1, -1};
  int out_pipe[2] = {-1, -1};
  int err_pipe[2] = {-1, -1};
  int launch_pipe[2] = {-1, -1};
  pid_t child = -1;
  pid_t pgid = -1;
  posix_spawn_file_actions_t actions;
  posix_spawnattr_t attr;
  int actions_inited = 0;
  int attr_inited = 0;
  char *lean_sysroot_env = NULL;
  char *lean_path_env = NULL;
  int pre_spawn_deadline = 0;
  int pre_spawn_io_fault = 0;

#if defined(__linux__)
  int pipe_setup_failed =
      pipe2(in_pipe, O_CLOEXEC) != 0 || pipe2(out_pipe, O_CLOEXEC) != 0 ||
      pipe2(err_pipe, O_CLOEXEC) != 0 || pipe2(launch_pipe, O_CLOEXEC) != 0;
#else
  int pipe_setup_failed =
      pipe(in_pipe) != 0 || pipe(out_pipe) != 0 || pipe(err_pipe) != 0;
#endif
  if (pipe_setup_failed) {
    pf_close_fd(&in_pipe[0]);
    pf_close_fd(&in_pipe[1]);
    pf_close_fd(&out_pipe[0]);
    pf_close_fd(&out_pipe[1]);
    pf_close_fd(&err_pipe[0]);
    pf_close_fd(&err_pipe[1]);
    pf_close_fd(&launch_pipe[0]);
    pf_close_fd(&launch_pipe[1]);
    int snapshot_cleanup = pf_cleanup_worker_snapshot(&worker_snapshot);
    free(stdout_buf);
    return pf_io_error(snapshot_cleanup == 0 ? "spawn-failed" : "io");
  }

  /* Darwin has no pipe2: immediately mark all six ends CLOEXEC, reject fd
     collisions with host stdio, and make only the parent-owned ends nonblock.
     F_SETNOSIGPIPE avoids a process-global SIGPIPE disposition change. */
  if (in_pipe[0] <= STDERR_FILENO || in_pipe[1] <= STDERR_FILENO ||
      out_pipe[0] <= STDERR_FILENO || out_pipe[1] <= STDERR_FILENO ||
      err_pipe[0] <= STDERR_FILENO || err_pipe[1] <= STDERR_FILENO ||
      pf_set_cloexec(in_pipe[0]) != 0 || pf_set_cloexec(out_pipe[1]) != 0 ||
      pf_set_cloexec(err_pipe[1]) != 0 ||
      pf_set_cloexec_nonblock(in_pipe[1]) != 0 ||
      pf_set_nosigpipe(in_pipe[1]) != 0 ||
      pf_set_cloexec_nonblock(out_pipe[0]) != 0 ||
      pf_set_cloexec_nonblock(err_pipe[0]) != 0) {
    goto spawn_fail;
  }

  if (posix_spawn_file_actions_init(&actions) != 0) {
    goto spawn_fail;
  }
  actions_inited = 1;
  if (posix_spawnattr_init(&attr) != 0) {
    goto spawn_fail;
  }
  attr_inited = 1;

  if (posix_spawn_file_actions_adddup2(&actions, in_pipe[0], STDIN_FILENO) != 0 ||
      posix_spawn_file_actions_adddup2(&actions, out_pipe[1], STDOUT_FILENO) !=
          0 ||
      posix_spawn_file_actions_adddup2(&actions, err_pipe[1], STDERR_FILENO) !=
          0 ||
      posix_spawn_file_actions_addclose(&actions, in_pipe[0]) != 0 ||
      posix_spawn_file_actions_addclose(&actions, in_pipe[1]) != 0 ||
      posix_spawn_file_actions_addclose(&actions, out_pipe[0]) != 0 ||
      posix_spawn_file_actions_addclose(&actions, out_pipe[1]) != 0 ||
      posix_spawn_file_actions_addclose(&actions, err_pipe[0]) != 0 ||
      posix_spawn_file_actions_addclose(&actions, err_pipe[1]) != 0) {
    goto spawn_fail;
  }
  short spawn_flags = (short)(POSIX_SPAWN_SETPGROUP
#if defined(__APPLE__)
                              |
                              POSIX_SPAWN_CLOEXEC_DEFAULT |
                              POSIX_SPAWN_START_SUSPENDED
#endif
                              );
  if (posix_spawnattr_setflags(&attr, spawn_flags) != 0 ||
      posix_spawnattr_setpgroup(&attr, 0) != 0) {
    goto spawn_fail;
  }

  char *argv[2];
  argv[0] = worker_snapshot.worker_path;
  argv[1] = NULL;

  /* Keep the worker environment deny-by-default. The two selectively inherited
     development search values are required by Loader.findSysroot/importModules;
     omitting them would launch a helper and violate maxProcesses=1. They are not
     a formal locked import closure and are documented as a remaining boundary. */
  lean_sysroot_env = pf_env_assignment("LEAN_SYSROOT", getenv("LEAN_SYSROOT"));
  lean_path_env = pf_env_assignment("LEAN_PATH", getenv("LEAN_PATH"));
  if (lean_sysroot_env == NULL || lean_path_env == NULL) {
    goto spawn_fail;
  }
  char *worker_env[] = {
      lean_sysroot_env, lean_path_env, "HOME=/var/empty", "PATH=/usr/bin:/bin",
      "LC_ALL=C", "TZ=UTC", NULL};
  int final_budget = pf_budget_status(budget_start_ms, max_wall_ms);
  if (final_budget != 0) {
    pre_spawn_deadline = final_budget == 1;
    pre_spawn_io_fault = final_budget < 0;
    goto spawn_fail;
  }
#if defined(__linux__)
  struct sigaction child_action;
  if (sigaction(SIGCHLD, NULL, &child_action) != 0 ||
      child_action.sa_handler != SIG_DFL ||
      (child_action.sa_flags & SA_NOCLDWAIT) != 0) {
    goto spawn_fail;
  }
#endif
#if defined(__APPLE__)
  int spawn_rc = posix_spawn(&child, worker_snapshot.worker_path, &actions,
                             &attr, argv, worker_env);
#else
  /* The locked Linux link profile does not expose glibc's closefrom spawn
     action. fork is safe here because the child performs only async-signal-safe
     syscalls before execve. close_range prevents ambient host capabilities
     from leaking into either supervised worker. */
  child = fork();
  int spawn_rc = 0;
  if (child == 0) {
    int launch_fault[2] = {0, 0};
    if (setpgid(0, 0) != 0) {
      launch_fault[0] = 1; launch_fault[1] = errno;
    } else if (dup2(in_pipe[0], STDIN_FILENO) < 0 ||
               dup2(out_pipe[1], STDOUT_FILENO) < 0 ||
               dup2(err_pipe[1], STDERR_FILENO) < 0) {
      launch_fault[0] = 2; launch_fault[1] = errno;
    } else if ((launch_pipe[1] > 3 &&
                syscall(SYS_close_range, 3u,
                        (unsigned int)launch_pipe[1] - 1u, 0u) != 0) ||
               syscall(SYS_close_range,
                       (unsigned int)launch_pipe[1] + 1u, ~0u, 0u) != 0) {
      launch_fault[0] = 3; launch_fault[1] = errno;
    }
    if (launch_fault[0] != 0) {
      (void)write(launch_pipe[1], launch_fault, sizeof(launch_fault));
      _exit(127);
    }
    execve(worker_snapshot.worker_path, argv, worker_env);
    launch_fault[0] = 4; launch_fault[1] = errno;
    (void)write(launch_pipe[1], launch_fault, sizeof(launch_fault));
    _exit(127);
  }
  if (child < 0) {
    spawn_rc = errno == 0 ? EIO : errno;
  } else if (setpgid(child, child) != 0 &&
             !(errno == EACCES && getpgid(child) == child)) {
    (void)kill(child, SIGKILL);
    do {
      spawn_rc = waitpid(child, NULL, 0) < 0 && errno == EINTR ? EINTR : EIO;
    } while (spawn_rc == EINTR);
    child = -1;
  }
  pf_close_fd(&launch_pipe[1]);
  if (spawn_rc == 0) {
    int launch_fault[2] = {0, 0};
    size_t launch_read = 0;
    for (;;) {
      ssize_t n = read(launch_pipe[0],
          (uint8_t *)launch_fault + launch_read,
          sizeof(launch_fault) - launch_read);
      if (n < 0 && errno == EINTR) continue;
      if (n < 0) { spawn_rc = EIO; break; }
      if (n == 0) break;
      launch_read += (size_t)n;
      if (launch_read == sizeof(launch_fault)) {
        spawn_rc = launch_fault[1] == 0 ? EIO : launch_fault[1];
        break;
      }
    }
    if (launch_read != 0 && launch_read != sizeof(launch_fault)) {
      spawn_rc = EIO;
    }
  }
  pf_close_fd(&launch_pipe[0]);
  if (spawn_rc != 0 && child > 0) {
    (void)kill(child, SIGKILL);
    pid_t wr;
    do { wr = waitpid(child, NULL, 0); } while (wr < 0 && errno == EINTR);
    child = -1;
  }
#endif
  free(lean_sysroot_env);
  lean_sysroot_env = NULL;
  free(lean_path_env);
  lean_path_env = NULL;
  if (spawn_rc != 0) {
    goto spawn_fail;
  }
  pgid = child;

  /* Darwin activates the image while START_SUSPENDED prevents worker code from
     running. Recheck the watched vnode/path and the original absolute budget,
     then release only the verified child. */
  int pre_run_decided = 0;
  uint8_t pre_run_event = PF_SUP_EV_FAULT;
  int snapshot_changed = pf_worker_snapshot_changed(&worker_snapshot);
  int post_spawn_budget = pf_budget_status(budget_start_ms, max_wall_ms);
  if (snapshot_changed != 0 || post_spawn_budget < 0) {
    pre_run_decided = 1;
    pre_run_event = PF_SUP_EV_FAULT;
  } else if (post_spawn_budget == 1) {
    pre_run_decided = 1;
    pre_run_event = PF_SUP_EV_DEADLINE;
#if defined(__APPLE__)
  } else if (kill(child, SIGCONT) != 0) {
    pre_run_decided = 1;
    pre_run_event = PF_SUP_EV_FAULT;
#endif
  }

  posix_spawn_file_actions_destroy(&actions);
  posix_spawnattr_destroy(&attr);

  pf_close_fd(&in_pipe[0]);
  pf_close_fd(&out_pipe[1]);
  pf_close_fd(&err_pipe[1]);

  size_t stdin_off = 0;
  int stdin_done = (input_size == 0) ? 1 : 0;
  size_t stdout_len = 0;
  size_t stderr_len = 0;
  int stdout_eof = 0;
  int stderr_eof = 0;
  int stdout_overflow = 0;
  int stderr_overflow = 0;
  int leader_exited = 0;
  int leader_status_valid = 0;
  int leader_signaled = 0;
  int leader_exit_value = 0;
  int leader_reaped = 0;
  int leader_reap_lost = 0;
  int io_fault = 0;

  int decided = pre_run_decided;
  uint8_t event = pre_run_decided ? pre_run_event : PF_SUP_EV_FAULT;
  uint8_t cleanup = PF_SUP_CLEAN_INCOMPLETE;
  uint64_t cleanup_start_ms = pre_run_decided ? stage_start_ms : 0;
  uint32_t cleanup_slices = 0;

  uint64_t peak_memory = 0;
  uint32_t peak_processes = 0;
  uint64_t elapsed_ms = initial_elapsed;
  uint64_t now_ms = stage_start_ms;

  if (stdin_done) {
    pf_close_fd(&in_pipe[1]);
  }

  for (;;) {
    if (pf_clock_ms(&now_ms) != 0) {
      io_fault = 1;
      if (!decided) {
        event = PF_SUP_EV_FAULT;
        decided = 1;
        cleanup_start_ms = stage_start_ms;
      }
    } else {
      elapsed_ms = pf_elapsed_ms(budget_start_ms, now_ms);
    }

    if (!decided && pf_worker_snapshot_changed(&worker_snapshot) != 0) {
      io_fault = 1;
      event = PF_SUP_EV_FAULT;
      decided = 1;
      cleanup_start_ms = now_ms;
    }

    if (pf_sample_group(pgid, &peak_processes, &peak_memory) != 0) {
      io_fault = 1;
      if (!decided) {
        event = PF_SUP_EV_FAULT;
        decided = 1;
        cleanup_start_ms = now_ms;
      }
    }

    if (!decided) {
      uint8_t ctl = 0;
      if (pf_controller_event(peak_processes, max_processes, peak_memory,
                              max_memory_bytes, stdout_overflow, stderr_overflow,
                              stdout_len, stderr_len, protocol_cap_sz,
                              stderr_cap_sz, elapsed_ms, max_wall_ms, &ctl)) {
        event = ctl;
        decided = 1;
        cleanup_start_ms = now_ms;
      }
    }

    if (!leader_exited && !leader_reaped) {
      int observe_rc = pf_observe_child_exit(
          child, &leader_exited, &leader_status_valid, &leader_signaled,
          &leader_exit_value);
      if (observe_rc != 0) {
        io_fault = 1;
        if (observe_rc == 1) {
          /* Another host reaper consumed our child; never reuse its bare PGID. */
          leader_reaped = 1;
          leader_reap_lost = 1;
          leader_exited = 1;
        }
        if (!decided) {
          event = PF_SUP_EV_FAULT;
          decided = 1;
          cleanup_start_ms = now_ms;
        }
      }
    }

    {
      struct pollfd pfds[3];
      nfds_t nfds = 0;
      int idx_in = -1;
      int idx_out = -1;
      int idx_err = -1;
      if (!stdin_done && in_pipe[1] >= 0) {
        idx_in = (int)nfds;
        pfds[nfds].fd = in_pipe[1];
        pfds[nfds].events = POLLOUT;
        pfds[nfds].revents = 0;
        nfds++;
      }
      if (!stdout_eof && out_pipe[0] >= 0) {
        idx_out = (int)nfds;
        pfds[nfds].fd = out_pipe[0];
        pfds[nfds].events = POLLIN | POLLHUP;
        pfds[nfds].revents = 0;
        nfds++;
      }
      if (!stderr_eof && err_pipe[0] >= 0) {
        idx_err = (int)nfds;
        pfds[nfds].fd = err_pipe[0];
        pfds[nfds].events = POLLIN | POLLHUP;
        pfds[nfds].revents = 0;
        nfds++;
      }

      int timeout_ms = PF_SUP_POLL_SLICE_MS;
      if (!decided && max_wall_ms >= elapsed_ms) {
        uint64_t remain = (max_wall_ms - elapsed_ms) + 1u;
        if (remain < (uint64_t)timeout_ms) {
          timeout_ms = remain == 0 ? 1 : (int)remain;
        }
      }

      if (nfds > 0) {
        int pr = poll(pfds, nfds, timeout_ms);
        if (pr < 0 && errno != EINTR) {
          io_fault = 1;
          if (!decided) {
            event = PF_SUP_EV_FAULT;
            decided = 1;
            cleanup_start_ms = now_ms;
          }
        } else if (pr > 0) {
          if (idx_in >= 0 &&
              (pfds[idx_in].revents & (POLLOUT | POLLERR | POLLHUP | POLLNVAL)) !=
                  0) {
            if (pf_write_stdin_progress(in_pipe[1], input_data, input_size,
                                        &stdin_off, &stdin_done) != 0) {
              io_fault = 1;
            }
            if (stdin_done) {
              pf_close_fd(&in_pipe[1]);
            }
          }
          if (idx_out >= 0 &&
              (pfds[idx_out].revents &
               (POLLIN | POLLHUP | POLLERR | POLLNVAL)) != 0) {
            if (pf_read_into_capped(out_pipe[0], stdout_buf, &stdout_len,
                                    stdout_store_cap, &stdout_eof,
                                    &stdout_overflow) != 0) {
              io_fault = 1;
            }
            if (stdout_eof) {
              pf_close_fd(&out_pipe[0]);
            }
          }
          if (idx_err >= 0 &&
              (pfds[idx_err].revents &
               (POLLIN | POLLHUP | POLLERR | POLLNVAL)) != 0) {
            if (pf_read_count_capped(err_pipe[0], &stderr_len, stderr_store_cap,
                                     &stderr_eof, &stderr_overflow) != 0) {
              io_fault = 1;
            }
            if (stderr_eof) {
              pf_close_fd(&err_pipe[0]);
            }
          }
        }
      } else {
        (void)poll(NULL, 0, timeout_ms);
      }

      /* Always attempt nonblocking progress (covers edge HUP/EAGAIN). */
      if (!stdin_done && in_pipe[1] >= 0) {
        if (pf_write_stdin_progress(in_pipe[1], input_data, input_size,
                                    &stdin_off, &stdin_done) != 0) {
          io_fault = 1;
        }
        if (stdin_done) {
          pf_close_fd(&in_pipe[1]);
        }
      }
      if (!stdout_eof && out_pipe[0] >= 0) {
        if (pf_read_into_capped(out_pipe[0], stdout_buf, &stdout_len,
                                stdout_store_cap, &stdout_eof,
                                &stdout_overflow) != 0) {
          io_fault = 1;
        }
        if (stdout_eof) {
          pf_close_fd(&out_pipe[0]);
        }
      }
      if (!stderr_eof && err_pipe[0] >= 0) {
        if (pf_read_count_capped(err_pipe[0], &stderr_len, stderr_store_cap,
                                 &stderr_eof, &stderr_overflow) != 0) {
          io_fault = 1;
        }
        if (stderr_eof) {
          pf_close_fd(&err_pipe[0]);
        }
      }
    }

    if (!decided && pf_worker_snapshot_changed(&worker_snapshot) != 0) {
      io_fault = 1;
      event = PF_SUP_EV_FAULT;
      decided = 1;
      cleanup_start_ms = now_ms;
    }
    if (pf_sample_group(pgid, &peak_processes, &peak_memory) != 0) {
      io_fault = 1;
      if (!decided) {
        event = PF_SUP_EV_FAULT;
        decided = 1;
        cleanup_start_ms = now_ms;
      }
    }
    if (pf_clock_ms(&now_ms) == 0) {
      elapsed_ms = pf_elapsed_ms(budget_start_ms, now_ms);
    }

    if (!decided) {
      uint8_t ctl = 0;
      if (pf_controller_event(peak_processes, max_processes, peak_memory,
                              max_memory_bytes, stdout_overflow, stderr_overflow,
                              stdout_len, stderr_len, protocol_cap_sz,
                              stderr_cap_sz, elapsed_ms, max_wall_ms, &ctl)) {
        event = ctl;
        decided = 1;
        cleanup_start_ms = now_ms;
      } else if (leader_exited && stdin_done && stdout_eof && stderr_eof) {
        /* Exit attribution only after pipes drain; controller wins otherwise. */
        if (leader_status_valid && leader_signaled) {
          event = PF_SUP_EV_SIGNAL;
        } else if (leader_status_valid && leader_exit_value == 0) {
          event = PF_SUP_EV_RESPONSE;
        } else {
          /* Missing status or a nonzero exit can never certify a response. */
          event = PF_SUP_EV_EXIT;
        }
        decided = 1;
        cleanup_start_ms = now_ms;
      } else if (io_fault) {
        event = PF_SUP_EV_FAULT;
        decided = 1;
        cleanup_start_ms = now_ms;
      }
    }

    if (!decided) {
      continue;
    }

    if (cleanup_slices < UINT32_MAX) {
      cleanup_slices++;
    }

    /* Refresh wait ownership immediately before every group kill, even after
       WNOWAIT has already observed leader exit. An external SIGCHLD handler or
       waitpid consumer may otherwise reap the zombie and permit PGID reuse.
       ECHILD (or any unverifiable waitid fault) suppresses this kill attempt;
       only an owned live child or owned unreaped zombie authorizes killpg. */
    int kill_identity_verified = 0;
    if (!leader_reaped) {
      int observe_rc = pf_observe_child_exit(
          child, &leader_exited, &leader_status_valid, &leader_signaled,
          &leader_exit_value);
      if (observe_rc == 0) {
        kill_identity_verified = 1;
      } else {
        io_fault = 1;
        if (observe_rc == 1) {
          leader_reaped = 1;
          leader_reap_lost = 1;
          leader_exited = 1;
        }
      }
    }
    if (pgid > 0 && !leader_reaped && !leader_reap_lost &&
        kill_identity_verified) {
      /* Darwin 25.4 (macOS 26.4) returns EPERM for killpg on a zombie-led
         group; older kernels returned 0/ESRCH. Both mean "no killable member
         remains": cleanup completeness is still gated by the group sampling
         below, so tolerating EPERM cannot mint a false COMPLETE — if EPERM
         ever meant live unkillable members, other_processes > 0 still fails
         closed to INCOMPLETE. */
      if (kill(-pgid, SIGKILL) != 0 && errno != ESRCH && errno != EPERM) {
        io_fault = 1;
        event = PF_SUP_EV_FAULT;
      }
    }

    if (!stdout_eof && out_pipe[0] >= 0) {
      (void)pf_read_into_capped(out_pipe[0], stdout_buf, &stdout_len,
                                stdout_store_cap, &stdout_eof, &stdout_overflow);
      if (stdout_eof) {
        pf_close_fd(&out_pipe[0]);
      }
    }
    if (!stderr_eof && err_pipe[0] >= 0) {
      (void)pf_read_count_capped(err_pipe[0], &stderr_len, stderr_store_cap,
                                 &stderr_eof, &stderr_overflow);
      if (stderr_eof) {
        pf_close_fd(&err_pipe[0]);
      }
    }
    if (!stdin_done) {
      pf_close_fd(&in_pipe[1]);
      stdin_done = 1;
    }

    if (leader_reap_lost) {
      cleanup = PF_SUP_CLEAN_INCOMPLETE;
      break;
    }

    uint32_t other_processes = 0;
    int group_sample_ok =
        pf_count_other_pgroup(pgid, child, &other_processes) == 0;
    if (group_sample_ok && other_processes == 0 && !leader_reaped) {
      pid_t wr = pf_waitpid_nohang(child);
      if (wr == child) {
        leader_reaped = 1;
      } else if (wr < 0 && errno == ECHILD) {
        leader_reaped = 1;
        leader_reap_lost = 1;
      }
    }
    if (group_sample_ok && other_processes == 0 && leader_reaped &&
        !leader_reap_lost) {
      cleanup = PF_SUP_CLEAN_COMPLETE;
      break;
    }

    int cleanup_timed_out =
        cleanup_slices >= (uint32_t)PF_SUP_CLEANUP_MAX_SLICES;
    if (pf_clock_ms(&now_ms) == 0 &&
        pf_elapsed_ms(cleanup_start_ms, now_ms) >=
            (uint64_t)PF_SUP_CLEANUP_BUDGET_MS) {
      cleanup_timed_out = 1;
    }
    if (cleanup_timed_out) {
      if (!leader_reaped) {
        pid_t wr = pf_waitpid_nohang(child);
        if (wr == child) {
          leader_reaped = 1;
        } else if (wr < 0 && errno == ECHILD) {
          leader_reaped = 1;
          leader_reap_lost = 1;
        } else if (wr == 0) {
          /* Preserve waitpid ownership without blocking the Lean supervisor. */
          (void)pf_schedule_child_reaper(child);
        }
      }
      cleanup =
          group_sample_ok && other_processes == 0 && leader_reaped &&
                  !leader_reap_lost
              ? PF_SUP_CLEAN_COMPLETE
              : PF_SUP_CLEAN_INCOMPLETE;
      break;
    }
  }

  if (pf_clock_ms(&now_ms) == 0) {
    elapsed_ms = pf_elapsed_ms(budget_start_ms, now_ms);
  }

  pf_close_fd(&in_pipe[1]);
  pf_close_fd(&out_pipe[0]);
  pf_close_fd(&err_pipe[0]);

  if (pf_cleanup_worker_snapshot(&worker_snapshot) != 0) {
    event = PF_SUP_EV_FAULT;
    cleanup = PF_SUP_CLEAN_INCOMPLETE;
    stdout_len = 0;
  }

  if (event == PF_SUP_EV_RESPONSE && stdout_len > protocol_cap_sz) {
    event = PF_SUP_EV_OUTPUT;
  }
  pf_apply_observation_contract(event, max_wall_ms, max_memory_bytes,
                                max_processes, &elapsed_ms, &peak_memory,
                                &peak_processes);

  const uint8_t *payload = NULL;
  uint32_t payload_len = 0;
  if (event == PF_SUP_EV_RESPONSE) {
    if (stdout_len > (size_t)UINT32_MAX) {
      free(stdout_buf);
      return pf_io_error("io");
    }
    payload = stdout_buf;
    payload_len = (uint32_t)stdout_len;
  }

  lean_object *result = pf_build_supervisor_frame(
      event, cleanup, elapsed_ms, peak_memory, peak_processes, payload,
      payload_len);
  free(stdout_buf);
  if (result == NULL) {
    return pf_io_error("io");
  }
  return result;

spawn_fail:
  free(lean_sysroot_env);
  free(lean_path_env);
  if (actions_inited) {
    posix_spawn_file_actions_destroy(&actions);
  }
  if (attr_inited) {
    posix_spawnattr_destroy(&attr);
  }
  pf_close_fd(&in_pipe[0]);
  pf_close_fd(&in_pipe[1]);
  pf_close_fd(&out_pipe[0]);
  pf_close_fd(&out_pipe[1]);
  pf_close_fd(&err_pipe[0]);
  pf_close_fd(&err_pipe[1]);
  pf_close_fd(&launch_pipe[0]);
  pf_close_fd(&launch_pipe[1]);
  int snapshot_cleanup = pf_cleanup_worker_snapshot(&worker_snapshot);
  free(stdout_buf);
  if (snapshot_cleanup != 0 || pre_spawn_io_fault) {
    return pf_io_error("io");
  }
  if (pre_spawn_deadline) {
    lean_object *deadline = pf_build_supervisor_frame(
        PF_SUP_EV_DEADLINE, PF_SUP_CLEAN_COMPLETE,
        pf_saturate_u64_plus_one(max_wall_ms), 0, 0, NULL, 0);
    return deadline == NULL ? pf_io_error("io") : deadline;
  }
  return pf_io_error("spawn-failed");
}

#endif /* __APPLE__ || __linux__ */

LEAN_EXPORT lean_obj_res proof_forge_start_frontend_budget_v1(
    lean_obj_arg world) {
  (void)world;
#if defined(__APPLE__) || defined(__linux__)
  uint64_t started_at_ms = 0;
  if (pf_clock_ms(&started_at_ms) != 0 || started_at_ms == UINT64_MAX) {
    return pf_io_error("io");
  }
  uint8_t frame[8];
  pf_write_u64_le(frame, started_at_ms);
  return pf_io_success(frame, sizeof(frame));
#else
  return pf_io_error("unsupported-platform");
#endif
}

LEAN_EXPORT lean_obj_res proof_forge_supervise_worker_v1(
    b_lean_obj_arg worker_object, b_lean_obj_arg input_object,
    uint64_t max_wall_millis, uint64_t max_memory_bytes, uint32_t max_processes,
    uint64_t max_protocol_bytes, uint64_t max_stderr_bytes,
    uint64_t budget_start_ms, lean_obj_arg world) {
  (void)world;
  const char *worker_path = lean_string_cstr(worker_object);
  size_t input_size = lean_sarray_size(input_object);
  const uint8_t *input_data =
      input_size == 0 ? NULL : (const uint8_t *)lean_sarray_cptr(input_object);

  if (pf_worker_path_invalid(worker_object, worker_path) ||
      max_wall_millis == 0 || max_wall_millis == UINT64_MAX ||
      max_memory_bytes == 0 || max_memory_bytes == UINT64_MAX ||
      max_processes == 0 || max_processes == UINT32_MAX ||
      max_protocol_bytes == 0 || max_stderr_bytes == 0 ||
      budget_start_ms == UINT64_MAX) {
    return pf_io_error("invalid-argument");
  }
  if ((uint64_t)input_size > max_protocol_bytes) {
    return pf_io_error("invalid-argument");
  }
  if (max_protocol_bytes > (uint64_t)UINT32_MAX ||
      max_protocol_bytes > UINT64_MAX - (uint64_t)PF_SUP_HEADER_SIZE) {
    return pf_io_error("invalid-argument");
  }

#if defined(__APPLE__) || defined(__linux__)
  return pf_supervise_worker_platform(worker_path, input_data, input_size,
                                    max_wall_millis, max_memory_bytes,
                                    max_processes, max_protocol_bytes,
                                    max_stderr_bytes, budget_start_ms);
#else
  (void)input_data;
  (void)budget_start_ms;
  return pf_io_error("unsupported-platform");
#endif
}
