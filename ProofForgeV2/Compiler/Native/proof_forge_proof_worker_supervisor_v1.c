#define _GNU_SOURCE 1
#include <lean/lean.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/syscall.h>
#endif

#ifdef __linux__
enum pf_event {
  PF_SUCCESS = 0,
  PF_STDOUT_LIMIT = 1,
  PF_STDERR_LIMIT = 2,
  PF_DEADLINE = 3,
  PF_SIGNALED = 4,
  PF_NONZERO_EXIT = 5,
  PF_SUPERVISOR_FAULT = 7
};
#endif

static lean_object *pf_except(uint8_t tag, lean_object *value) {
  lean_object *result = lean_alloc_ctor(tag, 1, 0);
  lean_ctor_set(result, 0, value);
  return result;
}

static lean_object *pf_error(const char *fault) {
  return lean_io_result_mk_ok(pf_except(0, lean_mk_string(fault)));
}

#ifdef __linux__
static lean_object *pf_ok(uint8_t *bytes, size_t size) {
  lean_object *array = lean_alloc_sarray(1, size, size);
  if (size != 0) {
    memcpy(lean_sarray_cptr(array), bytes, size);
  }
  free(bytes);
  return lean_io_result_mk_ok(pf_except(1, array));
}

static int pf_monotonic_millis(uint64_t *result) {
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) {
    return -1;
  }
  if ((uint64_t)time.tv_sec > (UINT64_MAX / 1000U)) {
    return -1;
  }
  *result = (uint64_t)time.tv_sec * 1000U +
            (uint64_t)time.tv_nsec / 1000000U;
  return 0;
}

static void pf_put_u32le(uint8_t *bytes, uint32_t value) {
  for (unsigned index = 0; index < 4; ++index) {
    bytes[index] = (uint8_t)(value >> (8U * index));
  }
}

static void pf_put_u64le(uint8_t *bytes, uint64_t value) {
  for (unsigned index = 0; index < 8; ++index) {
    bytes[index] = (uint8_t)(value >> (8U * index));
  }
}

static void pf_close(int *fd) {
  if (*fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

static int pf_normalize_fd(int *fd) {
  if (*fd >= 3) {
    return 0;
  }
  int replacement = fcntl(*fd, F_DUPFD_CLOEXEC, 3);
  if (replacement < 0) {
    return -1;
  }
  pf_close(fd);
  *fd = replacement;
  return 0;
}

static int pf_pipe(int pair[2]) {
  pair[0] = -1;
  pair[1] = -1;
  if (pipe2(pair, O_CLOEXEC) != 0) {
    return -1;
  }
  if (pf_normalize_fd(&pair[0]) != 0 || pf_normalize_fd(&pair[1]) != 0) {
    pf_close(&pair[0]);
    pf_close(&pair[1]);
    return -1;
  }
  return 0;
}

static int pf_open_executable(const char *path) {
  char *copy = NULL;
  char *save = NULL;
  int current = -1;

  if (path == NULL || path[0] != '/' || path[1] == '\0') {
    return -1;
  }
  copy = strdup(path);
  if (copy == NULL) {
    return -1;
  }
  current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (current < 0) {
    free(copy);
    return -1;
  }

  for (char *component = strtok_r(copy, "/", &save); component != NULL;
       component = strtok_r(NULL, "/", &save)) {
    int next;
    int last = save == NULL || *save == '\0';
    int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
    if (!last) {
      flags |= O_DIRECTORY;
    }
    if (strcmp(component, ".") == 0 || strcmp(component, "..") == 0) {
      pf_close(&current);
      free(copy);
      return -1;
    }
    next = openat(current, component, flags);
    pf_close(&current);
    if (next < 0) {
      free(copy);
      return -1;
    }
    current = next;
  }
  free(copy);

  struct stat status;
  if (fstat(current, &status) != 0 || !S_ISREG(status.st_mode) ||
      status.st_nlink != 1 || (status.st_mode & 0111) == 0) {
    pf_close(&current);
    return -1;
  }
  if (pf_normalize_fd(&current) != 0) {
    pf_close(&current);
    return -1;
  }
  return current;
}

static int pf_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    return -1;
  }
  return 0;
}

static int pf_close_range(unsigned first, unsigned last) {
  if (first > last) {
    return 0;
  }
  return syscall(SYS_close_range, first, last, 0) == 0 ? 0 : -1;
}

static int pf_child_close_others(int executable_fd, int exec_error_fd) {
  unsigned low = (unsigned)(executable_fd < exec_error_fd ?
      executable_fd : exec_error_fd);
  unsigned high = (unsigned)(executable_fd > exec_error_fd ?
      executable_fd : exec_error_fd);
  if ((low > 3 && pf_close_range(3, low - 1) != 0) ||
      (high > low + 1 && pf_close_range(low + 1, high - 1) != 0) ||
      (high < UINT_MAX && pf_close_range(high + 1, UINT_MAX) != 0)) {
    return -1;
  }
  return 0;
}

static void pf_child_fail(int exec_error_fd) {
  uint8_t byte = 1;
  ssize_t ignored;
  do {
    ignored = write(exec_error_fd, &byte, 1);
  } while (ignored < 0 && errno == EINTR);
  _exit(127);
}

static int pf_drain_fd(int fd, uint8_t *output, uint64_t capacity,
                       uint64_t *count, int *eof) {
  uint8_t scratch[8192];
  uint64_t observation_limit = capacity + 1;
  if (*count >= observation_limit) {
    return 0;
  }
  size_t request = sizeof(scratch);
  uint64_t remaining = observation_limit - *count;
  if (remaining < request) {
    request = (size_t)remaining;
  }
  for (;;) {
    ssize_t read_size = read(fd, scratch, request);
    if (read_size > 0) {
      uint64_t chunk = (uint64_t)read_size;
      uint64_t before = *count;
      *count = before + chunk;
      if (output != NULL && before < capacity) {
        uint64_t available = capacity - before;
        size_t keep = (size_t)(chunk < available ? chunk : available);
        memcpy(output + (size_t)before, scratch, keep);
      }
      return 0;
    }
    if (read_size == 0) {
      *eof = 1;
      return 0;
    }
    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return 0;
    }
    return -1;
  }
}

static void pf_kill_group(pid_t pid) {
  if (pid > 0) {
    if (kill(-pid, SIGKILL) != 0 && errno != ESRCH) {
      /* Cleanup status records whether the group remains observable. */
    }
  }
}

static int pf_group_empty(pid_t pid) {
  if (kill(-pid, 0) == 0) {
    return 0;
  }
  return errno == ESRCH;
}

LEAN_EXPORT lean_obj_res proof_forge_supervise_proof_worker_v1(
    b_lean_obj_arg path_object, b_lean_obj_arg input_object,
    uint64_t wall_millis, uint64_t stdout_cap, uint64_t stderr_cap) {
  uint64_t start = 0;
  uint64_t now = 0;
  int executable_fd = -1;
  int input_pipe[2] = {-1, -1};
  int output_pipe[2] = {-1, -1};
  int error_pipe[2] = {-1, -1};
  int exec_pipe[2] = {-1, -1};
  pid_t pid = -1;
  int status = 0;
  siginfo_t leader_info;
  int leader_exited = 0;
  int reaped = 0;
  int output_eof = 0;
  int error_eof = 0;
  int exec_eof = 0;
  int event = -1;
  uint64_t input_offset = 0;
  uint64_t output_count = 0;
  uint64_t error_count = 0;
  uint8_t *output = NULL;
  sigset_t blocked;
  sigset_t previous;
  sigset_t pending_before;
  int signal_masked = 0;
  int sigpipe_was_pending = 0;
  int generated_sigpipe = 0;

  if (wall_millis == 0 || stdout_cap == 0 || stderr_cap == 0 ||
      stdout_cap > UINT32_MAX || stderr_cap >= UINT64_MAX ||
      stdout_cap > SIZE_MAX - 30U) {
    return pf_error("native");
  }
  if (pf_monotonic_millis(&start) != 0) {
    return pf_error("native");
  }
  output = malloc((size_t)stdout_cap);
  if (output == NULL) {
    return pf_error("native");
  }
  executable_fd = pf_open_executable(lean_string_cstr(path_object));
  if (executable_fd < 0) {
    free(output);
    return pf_error("invalid-worker");
  }
  if (pf_pipe(input_pipe) != 0 || pf_pipe(output_pipe) != 0 ||
      pf_pipe(error_pipe) != 0 || pf_pipe(exec_pipe) != 0) {
    event = PF_SUPERVISOR_FAULT;
    goto finish;
  }

  sigemptyset(&blocked);
  sigaddset(&blocked, SIGPIPE);
  if (pthread_sigmask(SIG_BLOCK, &blocked, &previous) != 0) {
    event = PF_SUPERVISOR_FAULT;
    goto finish;
  }
  signal_masked = 1;
  if (sigpending(&pending_before) != 0) {
    event = PF_SUPERVISOR_FAULT;
    goto finish;
  }
  sigpipe_was_pending = sigismember(&pending_before, SIGPIPE) == 1;

  struct sigaction child_action;
  if (sigaction(SIGCHLD, NULL, &child_action) != 0 ||
      child_action.sa_handler == SIG_IGN ||
      (child_action.sa_flags & SA_NOCLDWAIT) != 0) {
    event = PF_SUPERVISOR_FAULT;
    goto finish;
  }

  pid = fork();
  if (pid < 0) {
    event = PF_SUPERVISOR_FAULT;
    goto finish;
  }
  if (pid == 0) {
    char *argv[] = {(char *)"proof-forge-compiler-proof-worker-v1", NULL};
    char *envp[] = {(char *)"HOME=/var/empty", (char *)"LC_ALL=C",
                    (char *)"TZ=UTC", NULL};
    struct sigaction default_action;
    sigset_t empty_mask;
    pf_close(&input_pipe[1]);
    pf_close(&output_pipe[0]);
    pf_close(&error_pipe[0]);
    pf_close(&exec_pipe[0]);
    if (setpgid(0, 0) != 0 || dup2(input_pipe[0], STDIN_FILENO) < 0 ||
        dup2(output_pipe[1], STDOUT_FILENO) < 0 ||
        dup2(error_pipe[1], STDERR_FILENO) < 0 || chdir("/") != 0) {
      pf_child_fail(exec_pipe[1]);
    }
    memset(&default_action, 0, sizeof(default_action));
    default_action.sa_handler = SIG_DFL;
    sigemptyset(&default_action.sa_mask);
    for (int signal_number = 1; signal_number < NSIG; ++signal_number) {
      if (signal_number != SIGKILL && signal_number != SIGSTOP) {
        if (sigaction(signal_number, &default_action, NULL) != 0 &&
            errno != EINVAL) {
          pf_child_fail(exec_pipe[1]);
        }
      }
    }
    sigemptyset(&empty_mask);
    if (sigprocmask(SIG_SETMASK, &empty_mask, NULL) != 0) {
      pf_child_fail(exec_pipe[1]);
    }
    if (pf_child_close_others(executable_fd, exec_pipe[1]) != 0) {
      pf_child_fail(exec_pipe[1]);
    }
    syscall(SYS_execveat, executable_fd, "", argv, envp, AT_EMPTY_PATH);
    pf_child_fail(exec_pipe[1]);
  }

  pf_close(&executable_fd);
  pf_close(&input_pipe[0]);
  pf_close(&output_pipe[1]);
  pf_close(&error_pipe[1]);
  pf_close(&exec_pipe[1]);
  if ((setpgid(pid, pid) != 0 && errno != EACCES && errno != ESRCH) ||
      pf_set_nonblocking(input_pipe[1]) != 0 ||
      pf_set_nonblocking(output_pipe[0]) != 0 ||
      pf_set_nonblocking(error_pipe[0]) != 0 ||
      pf_set_nonblocking(exec_pipe[0]) != 0) {
    event = PF_SUPERVISOR_FAULT;
    goto finish;
  }

  size_t input_size = lean_sarray_size(input_object);
  if (input_size == 0) {
    pf_close(&input_pipe[1]);
  }

  while (event < 0) {
    struct pollfd poll_fds[4] = {
        {input_pipe[1], input_pipe[1] >= 0 ? POLLOUT : 0, 0},
        {output_pipe[0], output_eof ? 0 : POLLIN, 0},
        {error_pipe[0], error_eof ? 0 : POLLIN, 0},
        {exec_pipe[0], exec_eof ? 0 : POLLIN, 0}};

    if (pf_monotonic_millis(&now) != 0) {
      event = PF_SUPERVISOR_FAULT;
      break;
    }
    if (now - start >= wall_millis) {
      event = PF_DEADLINE;
      break;
    }
    uint64_t remaining = wall_millis - (now - start);
    int timeout = remaining > 10 ? 10 : (int)remaining;
    int poll_result = poll(poll_fds, 4, timeout);
    if (poll_result < 0 && errno != EINTR) {
      event = PF_SUPERVISOR_FAULT;
      break;
    }

    if (input_pipe[1] >= 0 &&
        (poll_fds[0].revents & (POLLOUT | POLLERR | POLLHUP)) != 0) {
      ssize_t written = write(input_pipe[1],
          lean_sarray_cptr(input_object) + (size_t)input_offset,
          input_size - (size_t)input_offset);
      if (written > 0) {
        input_offset += (uint64_t)written;
        if (input_offset == input_size) {
          pf_close(&input_pipe[1]);
        }
      } else if (written < 0 && errno != EINTR && errno != EAGAIN &&
                 errno != EWOULDBLOCK && errno != EPIPE) {
        event = PF_SUPERVISOR_FAULT;
      } else if (written < 0 && errno == EPIPE) {
        generated_sigpipe = 1;
        pf_close(&input_pipe[1]);
      }
    }
    if ((poll_fds[1].revents & (POLLIN | POLLERR | POLLHUP)) != 0 &&
        pf_drain_fd(output_pipe[0], output, stdout_cap, &output_count,
                    &output_eof) != 0) {
      event = PF_SUPERVISOR_FAULT;
    }
    if ((poll_fds[2].revents & (POLLIN | POLLERR | POLLHUP)) != 0 &&
        pf_drain_fd(error_pipe[0], NULL, stderr_cap, &error_count,
                    &error_eof) != 0) {
      event = PF_SUPERVISOR_FAULT;
    }
    if ((poll_fds[3].revents & (POLLIN | POLLERR | POLLHUP)) != 0) {
      uint64_t exec_count = 0;
      if (pf_drain_fd(exec_pipe[0], NULL, 0, &exec_count, &exec_eof) != 0) {
        event = PF_SUPERVISOR_FAULT;
      } else if (exec_count != 0) {
        event = PF_SUPERVISOR_FAULT;
      }
    }
    if (pf_monotonic_millis(&now) != 0) {
      event = PF_SUPERVISOR_FAULT;
    } else if (event < 0 && now - start >= wall_millis) {
      event = PF_DEADLINE;
    } else if (event < 0 && output_count > stdout_cap) {
      event = PF_STDOUT_LIMIT;
    } else if (event < 0 && error_count > stderr_cap) {
      event = PF_STDERR_LIMIT;
    }

    if (!leader_exited) {
      memset(&leader_info, 0, sizeof(leader_info));
      if (waitid(P_PID, (id_t)pid, &leader_info,
                 WEXITED | WNOHANG | WNOWAIT) != 0) {
        if (errno != EINTR) {
          event = PF_SUPERVISOR_FAULT;
        }
      } else if (leader_info.si_pid == pid) {
        leader_exited = 1;
      }
    }
    if (event < 0 && leader_exited && output_eof && error_eof && exec_eof) {
      if (leader_info.si_code == CLD_KILLED ||
          leader_info.si_code == CLD_DUMPED) {
        event = PF_SIGNALED;
      } else if (leader_info.si_code != CLD_EXITED ||
                 leader_info.si_status != 0) {
        event = PF_NONZERO_EXIT;
      } else {
        event = PF_SUCCESS;
      }
    }
  }

finish:
  if (pid > 0) {
    pf_kill_group(pid);
    if (pf_monotonic_millis(&now) == 0) {
      uint64_t cleanup_start = now;
      for (;;) {
        if (!reaped) {
          pid_t waited = waitpid(pid, &status, WNOHANG);
          if (waited == pid) {
            reaped = 1;
          } else if (waited < 0 && errno != EINTR) {
            break;
          }
        }
        if (reaped && pf_group_empty(pid)) {
          break;
        }
        if (pf_monotonic_millis(&now) != 0 || now - cleanup_start >= 1000) {
          break;
        }
        struct timespec pause = {0, 1000000};
        while (nanosleep(&pause, &pause) != 0 && errno == EINTR) {
        }
      }
    }
  }

  int cleanup_complete = pid > 0 && reaped && pf_group_empty(pid);
  pf_close(&executable_fd);
  pf_close(&input_pipe[0]);
  pf_close(&input_pipe[1]);
  pf_close(&output_pipe[0]);
  pf_close(&output_pipe[1]);
  pf_close(&error_pipe[0]);
  pf_close(&error_pipe[1]);
  pf_close(&exec_pipe[0]);
  pf_close(&exec_pipe[1]);

  if (signal_masked) {
    if (generated_sigpipe && !sigpipe_was_pending) {
      struct timespec zero = {0, 0};
      int signal_result;
      do {
        signal_result = sigtimedwait(&blocked, NULL, &zero);
      } while (signal_result < 0 && errno == EINTR);
      if (signal_result != SIGPIPE) {
        event = PF_SUPERVISOR_FAULT;
      }
    }
    if (pthread_sigmask(SIG_SETMASK, &previous, NULL) != 0) {
      event = PF_SUPERVISOR_FAULT;
    }
  }
  if (event < 0) {
    event = PF_SUPERVISOR_FAULT;
  }

  uint32_t payload_size = event == PF_SUCCESS ? (uint32_t)output_count : 0;
  size_t wire_size = 30U + (size_t)payload_size;
  uint8_t *wire = calloc(1, wire_size);
  if (wire == NULL) {
    free(output);
    return pf_error("native");
  }
  memcpy(wire, "PFPWSV1\0", 8);
  wire[8] = (uint8_t)event;
  wire[9] = cleanup_complete ? 0 : 1;
  pf_put_u64le(wire + 10, output_count);
  pf_put_u64le(wire + 18, error_count);
  pf_put_u32le(wire + 26, payload_size);
  if (payload_size != 0) {
    memcpy(wire + 30, output, payload_size);
  }
  free(output);
  return pf_ok(wire, wire_size);
}
#else
LEAN_EXPORT lean_obj_res proof_forge_supervise_proof_worker_v1(
    b_lean_obj_arg path, b_lean_obj_arg input, uint64_t wall_millis,
    uint64_t stdout_cap, uint64_t stderr_cap) {
  (void)path;
  (void)input;
  (void)wall_millis;
  (void)stdout_cap;
  (void)stderr_cap;
  return pf_error("unsupported");
}
#endif
