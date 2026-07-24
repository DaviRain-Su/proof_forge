#define _GNU_SOURCE
#include "task_qualification_durable_state_v2.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void usage(const char *program) {
    fprintf(stderr,
        "usage: %s ROOT recover TIMESTAMP\n"
        "       %s ROOT COMMAND TASK OPERATION RUN NONCE [ARG ...]\n",
        program, program);
}

static void print_snapshot(const pf_tq_durable_snapshot_v2 *snapshot) {
    printf(
        "state=%s sequence=%u undelivered=%d key=%s event=%s "
        "acceptance=%s response=%s timestamp=%s reason=%s\n",
        pf_tq_durable_state_name_v2(snapshot->state),
        snapshot->sequence,
        snapshot->accepted_response_undelivered,
        snapshot->key_hex,
        snapshot->event_digest[0] == '\0' ? "-" : snapshot->event_digest,
        snapshot->acceptance_digest[0] == '\0' ? "-" : snapshot->acceptance_digest,
        snapshot->response_digest[0] == '\0' ? "-" : snapshot->response_digest,
        snapshot->terminal_timestamp[0] == '\0' ? "-" : snapshot->terminal_timestamp,
        snapshot->reason[0] == '\0' ? "-" : snapshot->reason);
}

int main(int argc, char **argv) {
    int root_fd;
    struct stat root;
    char error[PF_TQ_DURABLE_ERROR_BYTES];
    pf_tq_durable_tuple_v2 tuple;
    pf_tq_durable_snapshot_v2 snapshot;
    int result = -1;
    if (argc < 4) {
        usage(argv[0]);
        return 2;
    }
    root_fd = open(argv[1], O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (root_fd < 0 || fstat(root_fd, &root) != 0) {
        fprintf(stderr, "durable-driver: root open failed: %s\n", strerror(errno));
        if (root_fd >= 0) close(root_fd);
        return 2;
    }
    if (strcmp(argv[2], "recover") == 0) {
        unsigned recovered = 0U;
        if (argc != 4) {
            usage(argv[0]);
            close(root_fd);
            return 2;
        }
        result = pf_tq_durable_recover_v2(
            root_fd, root.st_uid, root.st_gid, argv[3], &recovered,
            error, sizeof(error));
        if (result == 0) {
            printf("recovered=%u\n", recovered);
        }
    } else {
        if (argc < 7 || pf_tq_durable_tuple_init_v2(
                &tuple, argv[3], argv[4], argv[5], argv[6],
                error, sizeof(error)) != 0) {
            if (argc < 7) usage(argv[0]);
            else fprintf(stderr, "durable-driver: %s\n", error);
            close(root_fd);
            return 2;
        }
        if (strcmp(argv[2], "inspect") == 0 && argc == 7) {
            result = pf_tq_durable_inspect_v2(
                root_fd, root.st_uid, root.st_gid, &tuple, &snapshot,
                error, sizeof(error));
        } else if (strcmp(argv[2], "reserve") == 0 && argc == 7) {
            result = pf_tq_durable_reserve_v2(
                root_fd, root.st_uid, root.st_gid, &tuple, &snapshot,
                error, sizeof(error));
        } else if (strcmp(argv[2], "signing") == 0 && argc == 7) {
            result = pf_tq_durable_begin_signing_v2(
                root_fd, root.st_uid, root.st_gid, &tuple, &snapshot,
                error, sizeof(error));
        } else if (strcmp(argv[2], "accept") == 0 && argc == 10) {
            result = pf_tq_durable_accept_v2(
                root_fd, root.st_uid, root.st_gid, &tuple,
                argv[7], argv[8], argv[9], &snapshot,
                error, sizeof(error));
        } else if (strcmp(argv[2], "reject") == 0 && argc == 9) {
            result = pf_tq_durable_reject_v2(
                root_fd, root.st_uid, root.st_gid, &tuple,
                argv[7], argv[8], &snapshot, error, sizeof(error));
        } else if (strcmp(argv[2], "undelivered") == 0 && argc == 7) {
            result = pf_tq_durable_mark_undelivered_v2(
                root_fd, root.st_uid, root.st_gid, &tuple, &snapshot,
                error, sizeof(error));
        } else {
            usage(argv[0]);
            close(root_fd);
            return 2;
        }
        if (result == 0) print_snapshot(&snapshot);
    }
    close(root_fd);
    if (result != 0) {
        fprintf(stderr, "durable-driver: %s\n", error);
        return 1;
    }
    return 0;
}
