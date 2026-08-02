#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1

#include <lean/lean.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#if defined(__APPLE__)
#define PF_MTIME_SEC(st) ((st).st_mtimespec.tv_sec)
#define PF_MTIME_NSEC(st) ((st).st_mtimespec.tv_nsec)
#define PF_CTIME_SEC(st) ((st).st_ctimespec.tv_sec)
#define PF_CTIME_NSEC(st) ((st).st_ctimespec.tv_nsec)
#else
#define PF_MTIME_SEC(st) ((st).st_mtim.tv_sec)
#define PF_MTIME_NSEC(st) ((st).st_mtim.tv_nsec)
#define PF_CTIME_SEC(st) ((st).st_ctim.tv_sec)
#define PF_CTIME_NSEC(st) ((st).st_ctim.tv_nsec)
#endif

#define PF_SUBJECT_MAX_BYTES UINT64_C(67108864)
#define PF_SEMANTIC_NAME "proof-subject.pfsem"
#define PF_PROVENANCE_NAME "proof-subject.pfprov"

typedef struct {
  int fd;
  const char *name;
  const char *scope;
  struct stat before;
  uint8_t *bytes;
  size_t size;
} pf_subject_file;

static lean_object *pf_except(uint8_t tag, lean_object *value) {
  lean_object *result = lean_alloc_ctor(tag, 1, 0);
  lean_ctor_set(result, 0, value);
  return result;
}

static lean_object *pf_io_error(const char *fault) {
  return lean_io_result_mk_ok(pf_except(0, lean_mk_string(fault)));
}

static lean_object *pf_io_scoped_error(const char *scope, const char *fault) {
  char wire[96];
  int count = snprintf(wire, sizeof(wire), "%s:%s", scope, fault);
  if (count < 0 || (size_t)count >= sizeof(wire)) {
    return pf_io_error("native-protocol");
  }
  return pf_io_error(wire);
}

static lean_object *pf_byte_array(const uint8_t *bytes, size_t size) {
  lean_object *result = lean_alloc_sarray(1, size, size);
  if (size != 0) {
    memcpy(lean_sarray_cptr(result), bytes, size);
  }
  return result;
}

static lean_object *pf_io_success_pair(const pf_subject_file *semantic,
                                       const pf_subject_file *provenance) {
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, pf_byte_array(semantic->bytes, semantic->size));
  lean_ctor_set(pair, 1, pf_byte_array(provenance->bytes, provenance->size));
  return lean_io_result_mk_ok(pf_except(1, pair));
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
  if (copy != NULL) {
    memcpy(copy, input, size + 1);
  }
  return copy;
}

static int pf_same_snapshot(const struct stat *left, const struct stat *right) {
  return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
         left->st_mode == right->st_mode && left->st_nlink == right->st_nlink &&
         left->st_size == right->st_size &&
         PF_MTIME_SEC(*left) == PF_MTIME_SEC(*right) &&
         PF_MTIME_NSEC(*left) == PF_MTIME_NSEC(*right) &&
         PF_CTIME_SEC(*left) == PF_CTIME_SEC(*right) &&
         PF_CTIME_NSEC(*left) == PF_CTIME_NSEC(*right);
}

static int pf_open_directory_component(int parent_fd, const char *component,
                                       const char **fault) {
  int flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC;
  int fd = openat(parent_fd, component, flags);
  if (fd < 0) {
    *fault = pf_open_fault(errno);
    return -1;
  }
  struct stat metadata;
  if (fstat(fd, &metadata) != 0) {
    close(fd);
    *fault = "io";
    return -1;
  }
  if (!S_ISDIR(metadata.st_mode)) {
    close(fd);
    *fault = "unsafe-path";
    return -1;
  }
  return fd;
}

static int pf_open_absolute_root(const char *root, const char **fault) {
  if (root[0] != '/') {
    *fault = "invalid-root";
    return -1;
  }
  int current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (current < 0) {
    *fault = "io";
    return -1;
  }
  if (root[1] == '\0') {
    return current;
  }
  char *copy = pf_copy_string(root + 1);
  if (copy == NULL) {
    close(current);
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
      close(current);
      *fault = "invalid-root";
      return -1;
    }
    int next = pf_open_directory_component(current, cursor, fault);
    if (next < 0) {
      free(copy);
      close(current);
      return -1;
    }
    close(current);
    current = next;
    if (slash == NULL) {
      break;
    }
    cursor = slash + 1;
  }
  free(copy);
  return current;
}

static int pf_open_subject_file(int root_fd, pf_subject_file *file,
                                uint64_t max_bytes, const char **fault) {
  file->fd = openat(root_fd, file->name,
                    O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (file->fd < 0) {
    *fault = pf_open_fault(errno);
    return -1;
  }
  if (fstat(file->fd, &file->before) != 0) {
    *fault = "io";
    return -1;
  }
  if (!S_ISREG(file->before.st_mode)) {
    *fault = "non-regular";
    return -1;
  }
  if (file->before.st_nlink != 1) {
    *fault = "multiple-links";
    return -1;
  }
  if (file->before.st_size < 0) {
    *fault = "changed-during-read";
    return -1;
  }
  uint64_t size = (uint64_t)file->before.st_size;
  if (size > max_bytes || size > PF_SUBJECT_MAX_BYTES) {
    *fault = "too-large";
    return -1;
  }
  file->size = (size_t)size;
  file->bytes = (uint8_t *)malloc(file->size + 1);
  if (file->bytes == NULL) {
    *fault = "io";
    return -1;
  }
  return 0;
}

static int pf_read_subject_file(pf_subject_file *file, const char **fault) {
  size_t total = 0;
  while (total <= file->size) {
    size_t remaining = file->size + 1 - total;
    size_t wanted = remaining < 65536 ? remaining : 65536;
    ssize_t count = read(file->fd, file->bytes + total, wanted);
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      *fault = "io";
      return -1;
    }
    if (count == 0) {
      break;
    }
    total += (size_t)count;
  }
  if (total < file->size) {
    *fault = "short-read";
    return -1;
  }
  if (total > file->size) {
    *fault = "grew-during-read";
    return -1;
  }
  return 0;
}

static int pf_recheck_subject_file(int root_fd, const pf_subject_file *file,
                                   const char **fault) {
  struct stat fd_after;
  struct stat path_after;
  if (fstat(file->fd, &fd_after) != 0 ||
      fstatat(root_fd, file->name, &path_after, AT_SYMLINK_NOFOLLOW) != 0) {
    *fault = "changed-during-read";
    return -1;
  }
  if (!pf_same_snapshot(&file->before, &fd_after) ||
      !pf_same_snapshot(&file->before, &path_after)) {
    *fault = "changed-during-read";
    return -1;
  }
  return 0;
}

static void pf_close_subject_file(pf_subject_file *file) {
  if (file->fd >= 0) {
    close(file->fd);
  }
  free(file->bytes);
  file->fd = -1;
  file->bytes = NULL;
}

LEAN_EXPORT lean_obj_res proof_forge_read_proof_subject_files_v1(
    b_lean_obj_arg root_object, uint64_t max_bytes) {
  const char *root = lean_string_cstr(root_object);
  size_t root_size = lean_string_size(root_object);
  if (max_bytes != PF_SUBJECT_MAX_BYTES || root_size == 0 ||
      memchr(root, '\0', root_size - 1) != NULL) {
    return pf_io_error("native-protocol");
  }

  const char *fault = "io";
  int root_fd = -1;
  struct stat root_before;
  struct stat root_after;
  pf_subject_file semantic = {
      -1, PF_SEMANTIC_NAME, "semantic-program", {0}, NULL, 0};
  pf_subject_file provenance = {
      -1, PF_PROVENANCE_NAME, "semantic-provenance", {0}, NULL, 0};
  lean_object *result = NULL;

  root_fd = pf_open_absolute_root(root, &fault);
  if (root_fd < 0) {
    if (strcmp(fault, "invalid-root") == 0) {
      return pf_io_error(fault);
    }
    return pf_io_scoped_error("root", fault);
  }
  if (fstat(root_fd, &root_before) != 0) {
    result = pf_io_scoped_error("root", "io");
    goto cleanup;
  }
  if (pf_open_subject_file(root_fd, &semantic, max_bytes, &fault) != 0) {
    result = pf_io_scoped_error(semantic.scope, fault);
    goto cleanup;
  }
  if (pf_open_subject_file(root_fd, &provenance, max_bytes, &fault) != 0) {
    result = pf_io_scoped_error(provenance.scope, fault);
    goto cleanup;
  }
  if (pf_read_subject_file(&semantic, &fault) != 0) {
    result = pf_io_scoped_error(semantic.scope, fault);
    goto cleanup;
  }
  if (pf_read_subject_file(&provenance, &fault) != 0) {
    result = pf_io_scoped_error(provenance.scope, fault);
    goto cleanup;
  }
  if (pf_recheck_subject_file(root_fd, &semantic, &fault) != 0) {
    result = pf_io_scoped_error(semantic.scope, fault);
    goto cleanup;
  }
  if (pf_recheck_subject_file(root_fd, &provenance, &fault) != 0) {
    result = pf_io_scoped_error(provenance.scope, fault);
    goto cleanup;
  }
  if (fstat(root_fd, &root_after) != 0 ||
      !pf_same_snapshot(&root_before, &root_after)) {
    result = pf_io_scoped_error("root", "changed-during-read");
    goto cleanup;
  }
  result = pf_io_success_pair(&semantic, &provenance);

cleanup:
  pf_close_subject_file(&semantic);
  pf_close_subject_file(&provenance);
  if (root_fd >= 0) {
    close(root_fd);
  }
  return result;
}
