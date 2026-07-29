#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <lean/lean.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
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
#include <pthread.h>
#include <sys/resource.h>
#endif

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
/* B11b1 Darwin development-only worker supervisor FFI                        */
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

#if defined(__APPLE__)

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
  return fcntl(fd, F_SETNOSIGPIPE, 1) == 0 ? 0 : -1;
}

static void pf_close_fd(int *fd) {
  if (fd != NULL && *fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

static int pf_snapshot_pgroup(pid_t pgid, pid_t **out_pids, int *out_count) {
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
    struct rusage_info_v4 info;
    memset(&info, 0, sizeof(info));
    if (proc_pid_rusage((int)member, RUSAGE_INFO_V4, (rusage_info_t *)&info) !=
        0) {
      /* list→rusage races with exit are expected; count remains conservative. */
      continue;
    }
    if (total > UINT64_MAX - info.ri_phys_footprint) {
      total = UINT64_MAX;
    } else {
      total += info.ri_phys_footprint;
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

static lean_object *pf_supervise_worker_darwin(
    const char *worker_path, const uint8_t *input_data, size_t input_size,
    uint64_t max_wall_ms, uint64_t max_memory_bytes, uint32_t max_processes,
    uint64_t max_protocol_bytes, uint64_t max_stderr_bytes,
    uint64_t prior_elapsed_ms) {
  size_t protocol_cap_sz = 0;
  size_t stderr_cap_sz = 0;
  if (!pf_u64_to_size(max_protocol_bytes, &protocol_cap_sz) ||
      !pf_u64_to_size(max_stderr_bytes, &stderr_cap_sz) ||
      pf_size_add_overflows(protocol_cap_sz, 1) ||
      pf_size_add_overflows(stderr_cap_sz, 1)) {
    return pf_io_error("invalid-argument");
  }
  size_t stdout_store_cap = protocol_cap_sz + 1;
  size_t stderr_store_cap = stderr_cap_sz + 1;

  /* Shared monotonic budget: prior_elapsed_ms carries open-phase consumption
     so the worker cannot re-arm a fresh wall. Local start is still taken before
     allocation/pipe/spawn for the residual phase. */
  uint64_t start_ms = 0;
  if (pf_clock_ms(&start_ms) != 0) {
    return pf_io_error("io");
  }

  uint8_t *stdout_buf =
      (uint8_t *)malloc(stdout_store_cap == 0 ? 1 : stdout_store_cap);
  if (stdout_buf == NULL) {
    return pf_io_error("io");
  }

  int in_pipe[2] = {-1, -1};
  int out_pipe[2] = {-1, -1};
  int err_pipe[2] = {-1, -1};
  pid_t child = -1;
  pid_t pgid = -1;
  posix_spawn_file_actions_t actions;
  posix_spawnattr_t attr;
  int actions_inited = 0;
  int attr_inited = 0;
  char *lean_sysroot_env = NULL;
  char *lean_path_env = NULL;

  if (pipe(in_pipe) != 0 || pipe(out_pipe) != 0 || pipe(err_pipe) != 0) {
    pf_close_fd(&in_pipe[0]);
    pf_close_fd(&in_pipe[1]);
    pf_close_fd(&out_pipe[0]);
    pf_close_fd(&out_pipe[1]);
    pf_close_fd(&err_pipe[0]);
    pf_close_fd(&err_pipe[1]);
    free(stdout_buf);
    return pf_io_error("spawn-failed");
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

  short spawn_flags =
      (short)(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT);
  if (posix_spawnattr_setflags(&attr, spawn_flags) != 0 ||
      posix_spawnattr_setpgroup(&attr, 0) != 0) {
    goto spawn_fail;
  }

  char *argv[2];
  argv[0] = (char *)(uintptr_t)worker_path;
  argv[1] = NULL;

  /* Keep the worker environment deny-by-default, but pass the two trusted
     Lake/Lean search values required by Loader.findSysroot/importModules.
     Omitting them causes findSysroot to launch a helper, which would violate
     the frontend maxProcesses=1 contract. */
  lean_sysroot_env = pf_env_assignment("LEAN_SYSROOT", getenv("LEAN_SYSROOT"));
  lean_path_env = pf_env_assignment("LEAN_PATH", getenv("LEAN_PATH"));
  if (lean_sysroot_env == NULL || lean_path_env == NULL) {
    goto spawn_fail;
  }
  char *worker_env[] = {
      lean_sysroot_env, lean_path_env, "HOME=/var/empty", "PATH=/usr/bin:/bin",
      "LC_ALL=C", "TZ=UTC", NULL};
  int spawn_rc =
      posix_spawn(&child, worker_path, &actions, &attr, argv, worker_env);
  free(lean_sysroot_env);
  lean_sysroot_env = NULL;
  free(lean_path_env);
  lean_path_env = NULL;
  if (spawn_rc != 0) {
    goto spawn_fail;
  }
  pgid = child;

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

  int decided = 0;
  uint8_t event = PF_SUP_EV_FAULT;
  uint8_t cleanup = PF_SUP_CLEAN_INCOMPLETE;
  uint64_t cleanup_start_ms = 0;
  uint32_t cleanup_slices = 0;

  uint64_t peak_memory = 0;
  uint32_t peak_processes = 0;
  uint64_t elapsed_ms = prior_elapsed_ms;
  uint64_t now_ms = start_ms;

  if (stdin_done) {
    pf_close_fd(&in_pipe[1]);
  }

  for (;;) {
    if (pf_clock_ms(&now_ms) != 0) {
      io_fault = 1;
      if (!decided) {
        event = PF_SUP_EV_FAULT;
        decided = 1;
        cleanup_start_ms = start_ms;
      }
    } else {
      uint64_t local = pf_elapsed_ms(start_ms, now_ms);
      if (prior_elapsed_ms > UINT64_MAX - local) {
        elapsed_ms = UINT64_MAX;
      } else {
        elapsed_ms = prior_elapsed_ms + local;
      }
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

    if (pf_sample_group(pgid, &peak_processes, &peak_memory) != 0) {
      io_fault = 1;
      if (!decided) {
        event = PF_SUP_EV_FAULT;
        decided = 1;
        cleanup_start_ms = now_ms;
      }
    }
    if (pf_clock_ms(&now_ms) == 0) {
      uint64_t local = pf_elapsed_ms(start_ms, now_ms);
      if (prior_elapsed_ms > UINT64_MAX - local) {
        elapsed_ms = UINT64_MAX;
      } else {
        elapsed_ms = prior_elapsed_ms + local;
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
      (void)kill(-pgid, SIGKILL);
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
      pid_t wr = waitpid(child, NULL, WNOHANG);
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
        pid_t wr = waitpid(child, NULL, WNOHANG);
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
    uint64_t local = pf_elapsed_ms(start_ms, now_ms);
    if (prior_elapsed_ms > UINT64_MAX - local) {
      elapsed_ms = UINT64_MAX;
    } else {
      elapsed_ms = prior_elapsed_ms + local;
    }
  }

  pf_close_fd(&in_pipe[1]);
  pf_close_fd(&out_pipe[0]);
  pf_close_fd(&err_pipe[0]);

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
  free(stdout_buf);
  return pf_io_error("spawn-failed");
}

#endif /* __APPLE__ */

LEAN_EXPORT lean_obj_res proof_forge_supervise_worker_v1(
    b_lean_obj_arg worker_object, b_lean_obj_arg input_object,
    uint64_t max_wall_millis, uint64_t max_memory_bytes, uint32_t max_processes,
    uint64_t max_protocol_bytes, uint64_t max_stderr_bytes,
    uint64_t prior_elapsed_ms, lean_obj_arg world) {
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
      prior_elapsed_ms == UINT64_MAX ||
      prior_elapsed_ms >= max_wall_millis) {
    /* prior >= wall: caller must mint deadline without spawn (no re-arm). */
    return pf_io_error("invalid-argument");
  }
  if ((uint64_t)input_size > max_protocol_bytes) {
    return pf_io_error("invalid-argument");
  }
  if (max_protocol_bytes > (uint64_t)UINT32_MAX ||
      max_protocol_bytes > UINT64_MAX - (uint64_t)PF_SUP_HEADER_SIZE) {
    return pf_io_error("invalid-argument");
  }

#if defined(__APPLE__)
  return pf_supervise_worker_darwin(worker_path, input_data, input_size,
                                    max_wall_millis, max_memory_bytes,
                                    max_processes, max_protocol_bytes,
                                    max_stderr_bytes, prior_elapsed_ms);
#else
  (void)input_data;
  (void)prior_elapsed_ms;
  return pf_io_error("unsupported-platform");
#endif
}
