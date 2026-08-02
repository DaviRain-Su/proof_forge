#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1
#include <lean/lean.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__APPLE__)
#define MT_S(s) ((s).st_mtimespec.tv_sec)
#define MT_N(s) ((s).st_mtimespec.tv_nsec)
#define CT_S(s) ((s).st_ctimespec.tv_sec)
#define CT_N(s) ((s).st_ctimespec.tv_nsec)
#else
#define MT_S(s) ((s).st_mtim.tv_sec)
#define MT_N(s) ((s).st_mtim.tv_nsec)
#define CT_S(s) ((s).st_ctim.tv_sec)
#define CT_N(s) ((s).st_ctim.tv_nsec)
#endif

#define MANIFEST "proof-bundle.json"
#define MANIFEST_CAP UINT64_C(8388608)
#define MODULE_CAP UINT64_C(67108864)
#define TOTAL_CAP UINT64_C(268435456)
#define MODULE_COUNT_CAP 1024

typedef struct { uint8_t *p; size_t n; } bytes;
typedef struct { char *path; struct stat metadata; int directory; int seen; } snapshot_entry;
typedef struct { snapshot_entry *entries; size_t size; size_t capacity; } snapshot;

static lean_object *except_value(uint8_t tag, lean_object *value) {
  lean_object *result = lean_alloc_ctor(tag, 1, 0);
  lean_ctor_set(result, 0, value);
  return result;
}

static lean_object *error_result(const char *message) {
  return lean_io_result_mk_ok(except_value(0, lean_mk_string(message)));
}

static lean_object *byte_array(bytes value) {
  lean_object *result = lean_alloc_sarray(1, value.n, value.n);
  if (value.n != 0) memcpy(lean_sarray_cptr(result), value.p, value.n);
  return result;
}

static const char *open_fault(int error) {
  if (error == ENOENT) return "not-found";
  if (error == EACCES || error == EPERM) return "permission-denied";
  if (error == ELOOP || error == ENOTDIR) return "unsafe-path";
  return "io";
}

static int same_metadata(const struct stat *a, const struct stat *b) {
  return a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
    a->st_mode == b->st_mode && a->st_nlink == b->st_nlink &&
    a->st_size == b->st_size && MT_S(*a) == MT_S(*b) &&
    MT_N(*a) == MT_N(*b) && CT_S(*a) == CT_S(*b) && CT_N(*a) == CT_N(*b);
}

static int valid_component(const char *value) {
  return *value != 0 && strcmp(value, ".") != 0 && strcmp(value, "..") != 0 &&
    strchr(value, '/') == NULL;
}

static int open_root(const char *path, const char **fault) {
  if (path[0] != '/') { *fault = "invalid-root"; return -1; }
  int fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) { *fault = "io"; return -1; }
  if (path[1] == 0) return fd;
  char *copy = strdup(path + 1);
  char *part = copy;
  if (copy == NULL) { close(fd); *fault = "io"; return -1; }
  while (part != NULL) {
    char *slash = strchr(part, '/');
    if (slash != NULL) *slash = 0;
    if (!valid_component(part)) { *fault = "invalid-root"; goto fail; }
    int child = openat(fd, part,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (child < 0) { *fault = open_fault(errno); goto fail; }
    close(fd);
    fd = child;
    part = slash == NULL ? NULL : slash + 1;
  }
  free(copy);
  return fd;
fail:
  free(copy);
  close(fd);
  return -1;
}

static int valid_relative(const char *path) {
  if (*path == 0 || *path == '/' || path[strlen(path) - 1] == '/') return 0;
  char *copy = strdup(path);
  char *part = copy;
  if (copy == NULL) return 0;
  while (part != NULL) {
    char *slash = strchr(part, '/');
    if (slash != NULL) *slash = 0;
    if (!valid_component(part)) { free(copy); return 0; }
    part = slash == NULL ? NULL : slash + 1;
  }
  free(copy);
  return 1;
}

static snapshot_entry *snapshot_find(snapshot *tree, const char *path) {
  for (size_t i = 0; i < tree->size; ++i)
    if (strcmp(tree->entries[i].path, path) == 0) return &tree->entries[i];
  return NULL;
}

static int snapshot_add(snapshot *tree, const char *path, const struct stat *metadata,
    int directory, const char **fault) {
  if (tree->size == tree->capacity) {
    size_t capacity = tree->capacity == 0 ? 16 : tree->capacity * 2;
    snapshot_entry *entries = realloc(tree->entries, capacity * sizeof(*entries));
    if (entries == NULL) { *fault = "io"; return -1; }
    tree->entries = entries;
    tree->capacity = capacity;
  }
  snapshot_entry *entry = &tree->entries[tree->size++];
  entry->path = strdup(path);
  if (entry->path == NULL) { --tree->size; *fault = "io"; return -1; }
  entry->metadata = *metadata;
  entry->directory = directory;
  entry->seen = 0;
  return 0;
}

static void snapshot_free(snapshot *tree) {
  for (size_t i = 0; i < tree->size; ++i) free(tree->entries[i].path);
  free(tree->entries);
}

static int expected_path(const char *path, char **paths, size_t count, int *directory) {
  if (strcmp(path, MANIFEST) == 0) { *directory = 0; return 1; }
  size_t length = strlen(path);
  for (size_t i = 0; i < count; ++i) {
    size_t expected_length = strlen(paths[i]);
    if (strcmp(path, paths[i]) == 0) { *directory = 0; return 1; }
    if (length < expected_length && strncmp(paths[i], path, length) == 0 &&
        paths[i][length] == '/') {
      *directory = 1;
      return 1;
    }
  }
  return 0;
}

static int walk_tree(int fd, const char *prefix, char **paths, size_t count,
    snapshot *baseline, int compare, const char **fault) {
  /* openat(".") creates an independent directory stream; dup would share the
     directory offset and make a later verification walk incorrectly see EOF. */
  int scan_fd = openat(fd, ".",
    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (scan_fd < 0) { *fault = "io"; return -1; }
  DIR *directory = fdopendir(scan_fd);
  if (directory == NULL) { close(scan_fd); *fault = "io"; return -1; }
  errno = 0;
  struct dirent *item;
  while ((item = readdir(directory)) != NULL) {
    if (strcmp(item->d_name, ".") == 0 || strcmp(item->d_name, "..") == 0) continue;
    size_t prefix_length = strlen(prefix);
    size_t name_length = strlen(item->d_name);
    char *path = malloc(prefix_length + name_length + 2);
    if (path == NULL) { *fault = "io"; closedir(directory); return -1; }
    if (prefix_length == 0) memcpy(path, item->d_name, name_length + 1);
    else {
      memcpy(path, prefix, prefix_length);
      path[prefix_length] = '/';
      memcpy(path + prefix_length + 1, item->d_name, name_length + 1);
    }
    int want_directory = 0;
    if (!expected_path(path, paths, count, &want_directory)) {
      free(path); *fault = "extra-entry"; closedir(directory); return -1;
    }
    struct stat child_link;
    if (fstatat(fd, item->d_name, &child_link, AT_SYMLINK_NOFOLLOW) != 0) {
      free(path); *fault = "changed-during-read"; closedir(directory); return -1;
    }
    if ((want_directory && !S_ISDIR(child_link.st_mode)) ||
        (!want_directory && !S_ISREG(child_link.st_mode))) {
      free(path); *fault = want_directory ? "unsafe-path" : "non-regular";
      closedir(directory); return -1;
    }
    snapshot_entry *record = snapshot_find(baseline, path);
    if (compare) {
      if (record == NULL || record->directory != want_directory ||
          !same_metadata(&record->metadata, &child_link)) {
        free(path); *fault = "changed-during-read"; closedir(directory); return -1;
      }
      record->seen = 1;
    } else if (snapshot_add(baseline, path, &child_link, want_directory, fault) != 0) {
      free(path); closedir(directory); return -1;
    }
    if (want_directory) {
      int child = openat(fd, item->d_name,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
      struct stat opened;
      if (child < 0) { free(path); *fault = open_fault(errno); closedir(directory); return -1; }
      if (fstat(child, &opened) != 0 || !same_metadata(&child_link, &opened)) {
        close(child); free(path); *fault = "changed-during-read";
        closedir(directory); return -1;
      }
      if (walk_tree(child, path, paths, count, baseline, compare, fault) != 0) {
        close(child); free(path); closedir(directory); return -1;
      }
      close(child);
    }
    free(path);
    errno = 0;
  }
  if (errno != 0) { *fault = "io"; closedir(directory); return -1; }
  closedir(directory);
  return 0;
}

static int complete_snapshot(snapshot *tree, char **paths, size_t count, const char **fault) {
  snapshot_entry *manifest = snapshot_find(tree, MANIFEST);
  if (manifest == NULL || manifest->directory) { *fault = "not-found"; return -1; }
  for (size_t i = 0; i < count; ++i) {
    snapshot_entry *entry = snapshot_find(tree, paths[i]);
    if (entry == NULL || entry->directory) { *fault = "not-found"; return -1; }
  }
  return 0;
}

static int read_snapshotted_file(int root, const char *path, snapshot *tree,
    uint64_t cap, bytes *output, const char **fault) {
  char *copy = strdup(path);
  char *part = copy;
  char *walked = strdup("");
  int parent = dup(root);
  int file = -1;
  if (copy == NULL || walked == NULL || parent < 0) { *fault = "io"; goto fail; }
  for (;;) {
    char *slash = strchr(part, '/');
    if (slash != NULL) *slash = 0;
    size_t old_length = strlen(walked), part_length = strlen(part);
    char *next_path = realloc(walked, old_length + part_length + 2);
    if (next_path == NULL) { *fault = "io"; goto fail; }
    walked = next_path;
    if (old_length != 0) walked[old_length++] = '/';
    memcpy(walked + old_length, part, part_length + 1);
    snapshot_entry *record = snapshot_find(tree, walked);
    struct stat linked, opened;
    if (record == NULL || fstatat(parent, part, &linked, AT_SYMLINK_NOFOLLOW) != 0 ||
        !same_metadata(&record->metadata, &linked)) {
      *fault = "changed-during-read"; goto fail;
    }
    int flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC;
    if (slash != NULL) flags |= O_DIRECTORY;
    file = openat(parent, part, flags);
    if (file < 0) { *fault = open_fault(errno); goto fail; }
    if (fstat(file, &opened) != 0 || !same_metadata(&record->metadata, &opened)) {
      *fault = "changed-during-read"; goto fail;
    }
    if (slash == NULL) break;
    if (!record->directory) { *fault = "unsafe-path"; goto fail; }
    close(parent);
    parent = file;
    file = -1;
    part = slash + 1;
  }
  struct stat before = snapshot_find(tree, path)->metadata;
  if (!S_ISREG(before.st_mode)) { *fault = "non-regular"; goto fail; }
  if (before.st_nlink != 1) { *fault = "multiple-links"; goto fail; }
  if (before.st_size < 0 || (uint64_t)before.st_size > cap) { *fault = "too-large"; goto fail; }
  output->n = (size_t)before.st_size;
  output->p = malloc(output->n + 1);
  if (output->p == NULL) { *fault = "io"; goto fail; }
  size_t read_count = 0;
  while (read_count <= output->n) {
    ssize_t amount = read(file, output->p + read_count, output->n + 1 - read_count);
    if (amount < 0 && errno == EINTR) continue;
    if (amount < 0) { *fault = "io"; goto fail_bytes; }
    if (amount == 0) break;
    read_count += (size_t)amount;
  }
  struct stat after, linked_after;
  if (read_count < output->n) { *fault = "short-read"; goto fail_bytes; }
  if (read_count > output->n) { *fault = "grew-during-read"; goto fail_bytes; }
  if (fstat(file, &after) != 0 ||
      fstatat(parent, part, &linked_after, AT_SYMLINK_NOFOLLOW) != 0 ||
      !same_metadata(&before, &after) || !same_metadata(&before, &linked_after)) {
    *fault = "changed-during-read"; goto fail_bytes;
  }
  close(file); close(parent); free(copy); free(walked);
  return 0;
fail_bytes:
  free(output->p); output->p = NULL; output->n = 0;
fail:
  if (file >= 0) close(file);
  if (parent >= 0) close(parent);
  free(copy); free(walked);
  return -1;
}

LEAN_EXPORT lean_obj_res proof_forge_read_proof_bundle_manifest_v1(b_lean_obj_arg root_object) {
  const char *root = lean_string_cstr(root_object);
  size_t root_size = lean_string_size(root_object);
  const char *fault = "io";
  if (root_size == 0 || memchr(root, 0, root_size - 1) != NULL) return error_result("invalid-root");
  int fd = open_root(root, &fault);
  if (fd < 0) return error_result(fault);
  bytes contents = {0};
  /* Manifest paths have no nested component; this phase is only for decoding paths. */
  snapshot tree = {0};
  struct stat metadata;
  if (fstatat(fd, MANIFEST, &metadata, AT_SYMLINK_NOFOLLOW) != 0 ||
      snapshot_add(&tree, MANIFEST, &metadata, 0, &fault) != 0 ||
      read_snapshotted_file(fd, MANIFEST, &tree, MANIFEST_CAP, &contents, &fault) != 0) {
    snapshot_free(&tree); close(fd); return error_result(fault);
  }
  snapshot_free(&tree); close(fd);
  lean_object *value = byte_array(contents); free(contents.p);
  return lean_io_result_mk_ok(except_value(1, value));
}

LEAN_EXPORT lean_obj_res proof_forge_read_proof_bundle_files_v1(
    b_lean_obj_arg root_object, b_lean_obj_arg paths_object) {
  const char *root = lean_string_cstr(root_object);
  size_t root_size = lean_string_size(root_object);
  size_t count = lean_array_size(paths_object);
  const char *fault = "io";
  if (root_size == 0 || memchr(root, 0, root_size - 1) != NULL ||
      count == 0 || count > MODULE_COUNT_CAP) return error_result("native-protocol");
  char **paths = calloc(count, sizeof(*paths));
  bytes *contents = calloc(count + 1, sizeof(*contents));
  snapshot tree = {0};
  int root_fd = -1;
  if (paths == NULL || contents == NULL) { fault = "io"; goto fail; }
  for (size_t i = 0; i < count; ++i) {
    lean_object *path_object = lean_array_get_core(paths_object, i);
    size_t size = lean_string_size(path_object);
    const char *path = lean_string_cstr(path_object);
    if (size == 0 || memchr(path, 0, size - 1) != NULL || !valid_relative(path) ||
        strncmp(path, "modules/", 8) != 0) { fault = "unsafe-path"; goto fail; }
    paths[i] = strdup(path);
    if (paths[i] == NULL) { fault = "io"; goto fail; }
    for (size_t j = 0; j < i; ++j)
      if (strcmp(paths[i], paths[j]) == 0) { fault = "unsafe-path"; goto fail; }
  }
  root_fd = open_root(root, &fault);
  if (root_fd < 0) goto fail;
  struct stat root_before, root_after;
  if (fstat(root_fd, &root_before) != 0) { fault = "io"; goto fail; }
  if (walk_tree(root_fd, "", paths, count, &tree, 0, &fault) != 0 ||
      complete_snapshot(&tree, paths, count, &fault) != 0) goto fail;
  if (read_snapshotted_file(root_fd, MANIFEST, &tree, MANIFEST_CAP,
      &contents[0], &fault) != 0) goto fail;
  uint64_t total = 0;
  for (size_t i = 0; i < count; ++i) {
    uint64_t remaining = TOTAL_CAP - total;
    uint64_t cap = remaining < MODULE_CAP ? remaining : MODULE_CAP;
    if (read_snapshotted_file(root_fd, paths[i], &tree, cap,
        &contents[i + 1], &fault) != 0) goto fail;
    total += contents[i + 1].n;
  }
  for (size_t i = 0; i < tree.size; ++i) tree.entries[i].seen = 0;
  if (walk_tree(root_fd, "", paths, count, &tree, 1, &fault) != 0) goto fail;
  for (size_t i = 0; i < tree.size; ++i)
    if (!tree.entries[i].seen) { fault = "changed-during-read"; goto fail; }
  if (fstat(root_fd, &root_after) != 0 || !same_metadata(&root_before, &root_after)) {
    fault = "changed-during-read"; goto fail;
  }
  close(root_fd); root_fd = -1;
  lean_object *array = lean_mk_empty_array_with_capacity(lean_box(count));
  for (size_t i = 0; i < count; ++i) array = lean_array_push(array, byte_array(contents[i + 1]));
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, byte_array(contents[0]));
  lean_ctor_set(pair, 1, array);
  for (size_t i = 0; i < count; ++i) free(paths[i]);
  for (size_t i = 0; i <= count; ++i) free(contents[i].p);
  free(paths); free(contents); snapshot_free(&tree);
  return lean_io_result_mk_ok(except_value(1, pair));
fail:
  if (root_fd >= 0) close(root_fd);
  if (paths != NULL) for (size_t i = 0; i < count; ++i) free(paths[i]);
  if (contents != NULL) for (size_t i = 0; i <= count; ++i) free(contents[i].p);
  free(paths); free(contents); snapshot_free(&tree);
  return error_result(fault);
}
