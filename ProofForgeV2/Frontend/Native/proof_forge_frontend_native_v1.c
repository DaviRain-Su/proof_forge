#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <lean/lean.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

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
