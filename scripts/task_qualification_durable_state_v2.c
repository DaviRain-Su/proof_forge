#define _GNU_SOURCE
#include "task_qualification_durable_state_v2.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1U << 0)
#endif

#define PF_TQ_EVENT_SCHEMA "proof-forge.task-qualification-durable-event.v2"
#define PF_TQ_EVENT_VERSION "2.0.0"
#define PF_TQ_EVENT_DOMAIN "pf.taskqual.durable-key.v2"
#define PF_TQ_EVENT_MAX_BYTES 4096U
#define PF_TQ_EVENT_MAX_FILES 4096U
#define PF_TQ_EVENT_FILE_BYTES 128U
#define PF_TQ_LOCK_FILE ".lock"

struct pf_tq_event_record {
    pf_tq_durable_tuple_v2 tuple;
    char key_hex[PF_TQ_DURABLE_KEY_HEX_BYTES + 1];
    char status[PF_TQ_DURABLE_REASON_BYTES];
    unsigned sequence;
    char acceptance_digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
    char previous_digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
    char reason[PF_TQ_DURABLE_REASON_BYTES];
    char response_digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
    char terminal_timestamp[PF_TQ_DURABLE_TIMESTAMP_BYTES];
};

struct pf_tq_loaded_event {
    struct pf_tq_event_record record;
    unsigned char bytes[PF_TQ_EVENT_MAX_BYTES];
    size_t size;
    char digest[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1];
};

static unsigned long pf_tq_temp_counter;

static int pf_tq_error(char *error, size_t error_size, const char *format, ...) {
    if (error != NULL && error_size > 0U) {
        va_list arguments;
        va_start(arguments, format);
        (void)vsnprintf(error, error_size, format, arguments);
        va_end(arguments);
        error[error_size - 1U] = '\0';
    }
    return -1;
}

static void pf_tq_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) {
        error[0] = '\0';
    }
}

static int pf_tq_copy(
    char *destination,
    size_t destination_size,
    const char *source,
    const char *where,
    char *error,
    size_t error_size
) {
    size_t length;
    if (destination == NULL || source == NULL || destination_size == 0U) {
        return pf_tq_error(error, error_size, "%s is missing", where);
    }
    length = strlen(source);
    if (length == 0U || length >= destination_size) {
        return pf_tq_error(error, error_size, "%s length is out of bounds", where);
    }
    memcpy(destination, source, length + 1U);
    return 0;
}

static bool pf_tq_is_safe_id(const char *value) {
    size_t index;
    bool previous_separator = false;
    size_t length = value == NULL ? 0U : strlen(value);
    if (length == 0U || length > 127U || value[0] < 'a' || value[0] > 'z') {
        return false;
    }
    for (index = 0U; index < length; ++index) {
        unsigned char character = (unsigned char)value[index];
        bool alphanumeric =
            (character >= 'a' && character <= 'z') ||
            (character >= '0' && character <= '9');
        bool separator = character == '-' || character == '.';
        if (!alphanumeric && !separator) {
            return false;
        }
        if (separator && (index == 0U || index + 1U == length || previous_separator)) {
            return false;
        }
        previous_separator = separator;
    }
    return true;
}

static bool pf_tq_is_task_id(const char *value) {
    size_t index;
    bool component_has_character = false;
    size_t length = value == NULL ? 0U : strlen(value);
    if (length < 6U || length > 127U || strncmp(value, "TASK-", 5U) != 0) {
        return false;
    }
    for (index = 5U; index < length; ++index) {
        unsigned char character = (unsigned char)value[index];
        if ((character >= 'A' && character <= 'Z') ||
                (character >= '0' && character <= '9')) {
            component_has_character = true;
            continue;
        }
        if (character != '-' || !component_has_character || index + 1U == length) {
            return false;
        }
        component_has_character = false;
    }
    return component_has_character;
}

static bool pf_tq_is_operation(const char *value) {
    static const char *const operations[] = {
        "task-qualification",
        "task-completion",
        "d0-10-bootstrap-approval",
        "d0-10-bootstrap-receipt"
    };
    size_t index;
    if (value == NULL) {
        return false;
    }
    for (index = 0U; index < sizeof(operations) / sizeof(operations[0]); ++index) {
        if (strcmp(value, operations[index]) == 0) {
            return true;
        }
    }
    return false;
}

static bool pf_tq_is_lower_hex(const char *value, size_t length) {
    size_t index;
    if (value == NULL || strlen(value) != length) {
        return false;
    }
    for (index = 0U; index < length; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!((character >= '0' && character <= '9') ||
                (character >= 'a' && character <= 'f'))) {
            return false;
        }
    }
    return true;
}

static bool pf_tq_is_digest(const char *value) {
    return value != NULL && strncmp(value, "sha256:", 7U) == 0 &&
        pf_tq_is_lower_hex(value + 7U, 64U);
}

static bool pf_tq_is_reason(const char *value) {
    size_t index;
    size_t length = value == NULL ? 0U : strlen(value);
    if (length == 0U || length >= PF_TQ_DURABLE_REASON_BYTES ||
            value[0] < 'a' || value[0] > 'z') {
        return false;
    }
    for (index = 0U; index < length; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (!((character >= 'a' && character <= 'z') ||
                (character >= '0' && character <= '9') || character == '-')) {
            return false;
        }
    }
    return true;
}

static bool pf_tq_is_leap_year(unsigned year) {
    return (year % 4U == 0U && year % 100U != 0U) || year % 400U == 0U;
}

static bool pf_tq_is_timestamp(const char *value) {
    static const unsigned month_days[] = {
        0U, 31U, 28U, 31U, 30U, 31U, 30U,
        31U, 31U, 30U, 31U, 30U, 31U
    };
    unsigned year;
    unsigned month;
    unsigned day;
    unsigned hour;
    unsigned minute;
    unsigned second;
    unsigned maximum_day;
    size_t index;
    if (value == NULL || strlen(value) != 20U || value[4] != '-' ||
            value[7] != '-' || value[10] != 'T' || value[13] != ':' ||
            value[16] != ':' || value[19] != 'Z') {
        return false;
    }
    for (index = 0U; index < 20U; ++index) {
        if (index == 4U || index == 7U || index == 10U || index == 13U ||
                index == 16U || index == 19U) {
            continue;
        }
        if (value[index] < '0' || value[index] > '9') {
            return false;
        }
    }
    year = (unsigned)(value[0] - '0') * 1000U +
        (unsigned)(value[1] - '0') * 100U +
        (unsigned)(value[2] - '0') * 10U + (unsigned)(value[3] - '0');
    month = (unsigned)(value[5] - '0') * 10U + (unsigned)(value[6] - '0');
    day = (unsigned)(value[8] - '0') * 10U + (unsigned)(value[9] - '0');
    hour = (unsigned)(value[11] - '0') * 10U + (unsigned)(value[12] - '0');
    minute = (unsigned)(value[14] - '0') * 10U + (unsigned)(value[15] - '0');
    second = (unsigned)(value[17] - '0') * 10U + (unsigned)(value[18] - '0');
    if (year == 0U || month < 1U || month > 12U || hour > 23U ||
            minute > 59U || second > 59U) {
        return false;
    }
    maximum_day = month_days[month];
    if (month == 2U && pf_tq_is_leap_year(year)) {
        maximum_day = 29U;
    }
    return day >= 1U && day <= maximum_day;
}

static int pf_tq_sha256_parts(
    const unsigned char *const *parts,
    const size_t *sizes,
    size_t count,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    unsigned int output_size = 0U;
    size_t index;
    if (context == NULL) {
        return pf_tq_error(error, error_size, "SHA-256 context allocation failed");
    }
    if (EVP_DigestInit_ex(context, EVP_sha256(), NULL) != 1) {
        EVP_MD_CTX_free(context);
        return pf_tq_error(error, error_size, "SHA-256 initialization failed");
    }
    for (index = 0U; index < count; ++index) {
        if (EVP_DigestUpdate(context, parts[index], sizes[index]) != 1) {
            EVP_MD_CTX_free(context);
            return pf_tq_error(error, error_size, "SHA-256 update failed");
        }
    }
    if (EVP_DigestFinal_ex(context, output, &output_size) != 1 || output_size != 32U) {
        EVP_MD_CTX_free(context);
        return pf_tq_error(error, error_size, "SHA-256 finalization failed");
    }
    EVP_MD_CTX_free(context);
    return 0;
}

static void pf_tq_hex(const unsigned char *bytes, size_t size, char *output) {
    static const char alphabet[] = "0123456789abcdef";
    size_t index;
    for (index = 0U; index < size; ++index) {
        output[2U * index] = alphabet[bytes[index] >> 4U];
        output[2U * index + 1U] = alphabet[bytes[index] & 15U];
    }
    output[2U * size] = '\0';
}

static int pf_tq_raw_digest(
    const unsigned char *bytes,
    size_t size,
    char output[PF_TQ_DURABLE_DIGEST_WIRE_BYTES + 1],
    char *error,
    size_t error_size
) {
    const unsigned char *parts[] = {bytes};
    const size_t sizes[] = {size};
    unsigned char digest[32];
    if (pf_tq_sha256_parts(parts, sizes, 1U, digest, error, error_size) != 0) {
        return -1;
    }
    memcpy(output, "sha256:", 7U);
    pf_tq_hex(digest, sizeof(digest), output + 7U);
    return 0;
}

static int pf_tq_tuple_key(
    const pf_tq_durable_tuple_v2 *tuple,
    char output[PF_TQ_DURABLE_KEY_HEX_BYTES + 1],
    char *error,
    size_t error_size
) {
    static const unsigned char zero = 0U;
    const unsigned char *parts[] = {
        (const unsigned char *)PF_TQ_EVENT_DOMAIN, &zero,
        (const unsigned char *)tuple->task_id, &zero,
        (const unsigned char *)tuple->operation, &zero,
        (const unsigned char *)tuple->run_id, &zero,
        (const unsigned char *)tuple->nonce
    };
    const size_t sizes[] = {
        sizeof(PF_TQ_EVENT_DOMAIN) - 1U, 1U,
        strlen(tuple->task_id), 1U,
        strlen(tuple->operation), 1U,
        strlen(tuple->run_id), 1U,
        strlen(tuple->nonce)
    };
    unsigned char digest[32];
    if (pf_tq_sha256_parts(parts, sizes, sizeof(parts) / sizeof(parts[0]),
            digest, error, error_size) != 0) {
        return -1;
    }
    pf_tq_hex(digest, sizeof(digest), output);
    return 0;
}

const char *pf_tq_durable_state_name_v2(pf_tq_durable_state_v2 state) {
    switch (state) {
        case PF_TQ_DURABLE_ABSENT: return "absent";
        case PF_TQ_DURABLE_ACTIVE: return "active";
        case PF_TQ_DURABLE_SIGNING: return "signing";
        case PF_TQ_DURABLE_ACCEPTED: return "accepted";
        case PF_TQ_DURABLE_REJECTED: return "rejected";
        default: return "invalid";
    }
}

int pf_tq_durable_validate_root_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    char *error,
    size_t error_size
) {
    struct stat before;
    struct stat after;
    pf_tq_clear_error(error, error_size);
    if (root_fd < 0) {
        return pf_tq_error(error, error_size, "durable root FD is negative");
    }
    if (fstat(root_fd, &before) != 0 || fstat(root_fd, &after) != 0) {
        return pf_tq_error(error, error_size, "durable root fstat failed: %s", strerror(errno));
    }
    if (!S_ISDIR(before.st_mode) || before.st_nlink < 2 ||
            (before.st_mode & 07777) != 0700 || before.st_uid != expected_uid ||
            before.st_gid != expected_gid) {
        return pf_tq_error(error, error_size,
            "durable root must be owner-matched mode-0700 directory");
    }
    if (before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
            before.st_mode != after.st_mode || before.st_uid != after.st_uid ||
            before.st_gid != after.st_gid || before.st_nlink != after.st_nlink) {
        return pf_tq_error(error, error_size, "durable root metadata changed");
    }
    return 0;
}

int pf_tq_durable_tuple_init_v2(
    pf_tq_durable_tuple_v2 *tuple,
    const char *task_id,
    const char *operation,
    const char *run_id,
    const char *nonce,
    char *error,
    size_t error_size
) {
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL) {
        return pf_tq_error(error, error_size, "durable tuple output is missing");
    }
    memset(tuple, 0, sizeof(*tuple));
    if (!pf_tq_is_task_id(task_id)) {
        return pf_tq_error(error, error_size, "taskId grammar rejected");
    }
    if (!pf_tq_is_operation(operation)) {
        return pf_tq_error(error, error_size, "operation is not accepted");
    }
    if (!pf_tq_is_safe_id(run_id) || !pf_tq_is_safe_id(nonce)) {
        return pf_tq_error(error, error_size, "runId/nonce safe-id grammar rejected");
    }
    if (pf_tq_copy(tuple->task_id, sizeof(tuple->task_id), task_id,
            "taskId", error, error_size) != 0 ||
            pf_tq_copy(tuple->operation, sizeof(tuple->operation), operation,
                "operation", error, error_size) != 0 ||
            pf_tq_copy(tuple->run_id, sizeof(tuple->run_id), run_id,
                "runId", error, error_size) != 0 ||
            pf_tq_copy(tuple->nonce, sizeof(tuple->nonce), nonce,
                "nonce", error, error_size) != 0) {
        memset(tuple, 0, sizeof(*tuple));
        return -1;
    }
    return 0;
}

struct pf_tq_buffer {
    unsigned char *bytes;
    size_t size;
    size_t used;
};

static int pf_tq_append(
    struct pf_tq_buffer *buffer,
    const char *text,
    char *error,
    size_t error_size
) {
    size_t length = strlen(text);
    if (length > buffer->size - buffer->used) {
        return pf_tq_error(error, error_size, "durable event encoding overflow");
    }
    memcpy(buffer->bytes + buffer->used, text, length);
    buffer->used += length;
    return 0;
}

static int pf_tq_append_nullable(
    struct pf_tq_buffer *buffer,
    const char *value,
    char *error,
    size_t error_size
) {
    if (value[0] == '\0') {
        return pf_tq_append(buffer, "null", error, error_size);
    }
    if (pf_tq_append(buffer, "\"", error, error_size) != 0 ||
            pf_tq_append(buffer, value, error, error_size) != 0 ||
            pf_tq_append(buffer, "\"", error, error_size) != 0) {
        return -1;
    }
    return 0;
}

static int pf_tq_encode_event(
    const struct pf_tq_event_record *record,
    unsigned char output[PF_TQ_EVENT_MAX_BYTES],
    size_t *output_size,
    char *error,
    size_t error_size
) {
    struct pf_tq_buffer buffer = {output, PF_TQ_EVENT_MAX_BYTES, 0U};
    char sequence[16];
    int written = snprintf(sequence, sizeof(sequence), "%u", record->sequence);
    if (written <= 0 || (size_t)written >= sizeof(sequence)) {
        return pf_tq_error(error, error_size, "durable sequence encoding failed");
    }
#define APPEND_LITERAL(value) do { \
    if (pf_tq_append(&buffer, (value), error, error_size) != 0) return -1; \
} while (0)
#define APPEND_NULLABLE(value) do { \
    if (pf_tq_append_nullable(&buffer, (value), error, error_size) != 0) return -1; \
} while (0)
    APPEND_LITERAL("{\"acceptanceDigest\":");
    APPEND_NULLABLE(record->acceptance_digest);
    APPEND_LITERAL(",\"eventSequence\":");
    APPEND_LITERAL(sequence);
    APPEND_LITERAL(",\"key\":\"");
    APPEND_LITERAL(record->key_hex);
    APPEND_LITERAL("\",\"nonce\":\"");
    APPEND_LITERAL(record->tuple.nonce);
    APPEND_LITERAL("\",\"operation\":\"");
    APPEND_LITERAL(record->tuple.operation);
    APPEND_LITERAL("\",\"previousDigest\":");
    APPEND_NULLABLE(record->previous_digest);
    APPEND_LITERAL(",\"reason\":");
    APPEND_NULLABLE(record->reason);
    APPEND_LITERAL(",\"responseDigest\":");
    APPEND_NULLABLE(record->response_digest);
    APPEND_LITERAL(",\"runId\":\"");
    APPEND_LITERAL(record->tuple.run_id);
    APPEND_LITERAL("\",\"schema\":\"");
    APPEND_LITERAL(PF_TQ_EVENT_SCHEMA);
    APPEND_LITERAL("\",\"status\":\"");
    APPEND_LITERAL(record->status);
    APPEND_LITERAL("\",\"taskId\":\"");
    APPEND_LITERAL(record->tuple.task_id);
    APPEND_LITERAL("\",\"terminalTimestamp\":");
    APPEND_NULLABLE(record->terminal_timestamp);
    APPEND_LITERAL(",\"version\":\"");
    APPEND_LITERAL(PF_TQ_EVENT_VERSION);
    APPEND_LITERAL("\"}");
#undef APPEND_LITERAL
#undef APPEND_NULLABLE
    *output_size = buffer.used;
    return 0;
}

struct pf_tq_cursor {
    const unsigned char *bytes;
    size_t size;
    size_t offset;
};

static int pf_tq_expect(
    struct pf_tq_cursor *cursor,
    const char *literal,
    char *error,
    size_t error_size
) {
    size_t length = strlen(literal);
    if (length > cursor->size - cursor->offset ||
            memcmp(cursor->bytes + cursor->offset, literal, length) != 0) {
        return pf_tq_error(error, error_size,
            "durable event is noncanonical near byte %zu", cursor->offset);
    }
    cursor->offset += length;
    return 0;
}

static int pf_tq_parse_string(
    struct pf_tq_cursor *cursor,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    size_t start;
    size_t length;
    if (cursor->offset >= cursor->size || cursor->bytes[cursor->offset] != '"') {
        return pf_tq_error(error, error_size, "durable event string expected");
    }
    ++cursor->offset;
    start = cursor->offset;
    while (cursor->offset < cursor->size && cursor->bytes[cursor->offset] != '"') {
        unsigned char character = cursor->bytes[cursor->offset];
        if (character < 0x20U || character > 0x7eU || character == '\\') {
            return pf_tq_error(error, error_size,
                "durable event string escape/control rejected");
        }
        ++cursor->offset;
    }
    if (cursor->offset >= cursor->size) {
        return pf_tq_error(error, error_size, "durable event string is unterminated");
    }
    length = cursor->offset - start;
    if (length == 0U || length >= output_size) {
        return pf_tq_error(error, error_size, "durable event string length rejected");
    }
    memcpy(output, cursor->bytes + start, length);
    output[length] = '\0';
    ++cursor->offset;
    return 0;
}

static int pf_tq_parse_nullable_string(
    struct pf_tq_cursor *cursor,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    if (cursor->size - cursor->offset >= 4U &&
            memcmp(cursor->bytes + cursor->offset, "null", 4U) == 0) {
        output[0] = '\0';
        cursor->offset += 4U;
        return 0;
    }
    return pf_tq_parse_string(cursor, output, output_size, error, error_size);
}

static int pf_tq_parse_sequence(
    struct pf_tq_cursor *cursor,
    unsigned *sequence,
    char *error,
    size_t error_size
) {
    unsigned char character;
    if (cursor->offset >= cursor->size) {
        return pf_tq_error(error, error_size, "durable event sequence missing");
    }
    character = cursor->bytes[cursor->offset++];
    if (character < '0' || character > '3') {
        return pf_tq_error(error, error_size, "durable event sequence rejected");
    }
    if (cursor->offset < cursor->size && cursor->bytes[cursor->offset] >= '0' &&
            cursor->bytes[cursor->offset] <= '9') {
        return pf_tq_error(error, error_size, "durable event sequence is noncanonical");
    }
    *sequence = (unsigned)(character - '0');
    return 0;
}

static int pf_tq_validate_record(
    const struct pf_tq_event_record *record,
    char *error,
    size_t error_size
) {
    char key[PF_TQ_DURABLE_KEY_HEX_BYTES + 1];
    if (pf_tq_tuple_key(&record->tuple, key, error, error_size) != 0) {
        return -1;
    }
    if (strcmp(key, record->key_hex) != 0) {
        return pf_tq_error(error, error_size, "durable event tuple/key mismatch");
    }
    if (strcmp(record->status, "active") == 0) {
        if (record->sequence != 0U || record->acceptance_digest[0] != '\0' ||
                record->previous_digest[0] != '\0' || record->reason[0] != '\0' ||
                record->response_digest[0] != '\0' ||
                record->terminal_timestamp[0] != '\0') {
            return pf_tq_error(error, error_size, "active durable event fields rejected");
        }
        return 0;
    }
    if (strcmp(record->status, "signing") == 0) {
        if (record->sequence != 1U || record->acceptance_digest[0] != '\0' ||
                !pf_tq_is_digest(record->previous_digest) || record->reason[0] != '\0' ||
                record->response_digest[0] != '\0' ||
                record->terminal_timestamp[0] != '\0') {
            return pf_tq_error(error, error_size, "signing durable event fields rejected");
        }
        return 0;
    }
    if (strcmp(record->status, "accepted") == 0) {
        if (record->sequence != 2U || !pf_tq_is_digest(record->acceptance_digest) ||
                !pf_tq_is_digest(record->previous_digest) || record->reason[0] != '\0' ||
                !pf_tq_is_digest(record->response_digest) ||
                !pf_tq_is_timestamp(record->terminal_timestamp)) {
            return pf_tq_error(error, error_size, "accepted durable event fields rejected");
        }
        return 0;
    }
    if (strcmp(record->status, "rejected") == 0) {
        if ((record->sequence != 1U && record->sequence != 2U) ||
                record->acceptance_digest[0] != '\0' ||
                !pf_tq_is_digest(record->previous_digest) ||
                !pf_tq_is_reason(record->reason) ||
                record->response_digest[0] != '\0' ||
                !pf_tq_is_timestamp(record->terminal_timestamp)) {
            return pf_tq_error(error, error_size, "rejected durable event fields rejected");
        }
        return 0;
    }
    if (strcmp(record->status, "accepted-response-undelivered") == 0) {
        if (record->sequence != 3U || !pf_tq_is_digest(record->acceptance_digest) ||
                !pf_tq_is_digest(record->previous_digest) ||
                strcmp(record->reason, "accepted-response-undelivered") != 0 ||
                !pf_tq_is_digest(record->response_digest) ||
                !pf_tq_is_timestamp(record->terminal_timestamp)) {
            return pf_tq_error(error, error_size, "undelivered audit event fields rejected");
        }
        return 0;
    }
    return pf_tq_error(error, error_size, "durable event status rejected");
}

static int pf_tq_parse_event(
    const unsigned char *bytes,
    size_t size,
    struct pf_tq_event_record *record,
    char *error,
    size_t error_size
) {
    struct pf_tq_cursor cursor = {bytes, size, 0U};
    unsigned char encoded[PF_TQ_EVENT_MAX_BYTES];
    size_t encoded_size = 0U;
    memset(record, 0, sizeof(*record));
#define EXPECT(value) do { if (pf_tq_expect(&cursor, (value), error, error_size) != 0) return -1; } while (0)
#define STRING(field) do { if (pf_tq_parse_string(&cursor, (field), sizeof(field), error, error_size) != 0) return -1; } while (0)
#define NULLABLE(field) do { if (pf_tq_parse_nullable_string(&cursor, (field), sizeof(field), error, error_size) != 0) return -1; } while (0)
    EXPECT("{\"acceptanceDigest\":");
    NULLABLE(record->acceptance_digest);
    EXPECT(",\"eventSequence\":");
    if (pf_tq_parse_sequence(&cursor, &record->sequence, error, error_size) != 0) return -1;
    EXPECT(",\"key\":");
    STRING(record->key_hex);
    EXPECT(",\"nonce\":");
    STRING(record->tuple.nonce);
    EXPECT(",\"operation\":");
    STRING(record->tuple.operation);
    EXPECT(",\"previousDigest\":");
    NULLABLE(record->previous_digest);
    EXPECT(",\"reason\":");
    NULLABLE(record->reason);
    EXPECT(",\"responseDigest\":");
    NULLABLE(record->response_digest);
    EXPECT(",\"runId\":");
    STRING(record->tuple.run_id);
    EXPECT(",\"schema\":\"");
    EXPECT(PF_TQ_EVENT_SCHEMA);
    EXPECT("\",\"status\":");
    STRING(record->status);
    EXPECT(",\"taskId\":");
    STRING(record->tuple.task_id);
    EXPECT(",\"terminalTimestamp\":");
    NULLABLE(record->terminal_timestamp);
    EXPECT(",\"version\":\"");
    EXPECT(PF_TQ_EVENT_VERSION);
    EXPECT("\"}");
#undef EXPECT
#undef STRING
#undef NULLABLE
    if (cursor.offset != cursor.size) {
        return pf_tq_error(error, error_size, "durable event has trailing bytes");
    }
    if (!pf_tq_is_task_id(record->tuple.task_id) ||
            !pf_tq_is_operation(record->tuple.operation) ||
            !pf_tq_is_safe_id(record->tuple.run_id) ||
            !pf_tq_is_safe_id(record->tuple.nonce) ||
            !pf_tq_is_lower_hex(record->key_hex, 64U)) {
        return pf_tq_error(error, error_size, "durable event identity grammar rejected");
    }
    if (pf_tq_validate_record(record, error, error_size) != 0) {
        return -1;
    }
    if (pf_tq_encode_event(record, encoded, &encoded_size, error, error_size) != 0) {
        return -1;
    }
    if (encoded_size != size || memcmp(encoded, bytes, size) != 0) {
        return pf_tq_error(error, error_size, "durable event is not canonical PF-JCS");
    }
    return 0;
}

static int pf_tq_event_filename(
    const char *key,
    unsigned sequence,
    const char *status,
    char output[PF_TQ_EVENT_FILE_BYTES],
    char *error,
    size_t error_size
) {
    int written = snprintf(output, PF_TQ_EVENT_FILE_BYTES,
        "%s.%03u.%s.json", key, sequence, status);
    if (written <= 0 || written >= (int)PF_TQ_EVENT_FILE_BYTES) {
        return pf_tq_error(error, error_size, "durable event filename overflow");
    }
    return 0;
}

static int pf_tq_open_lock(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    char *error,
    size_t error_size
) {
    int descriptor = openat(root_fd, PF_TQ_LOCK_FILE,
        O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    struct stat metadata;
    if (descriptor < 0) {
        (void)pf_tq_error(error, error_size, "durable lock open failed: %s", strerror(errno));
        return -1;
    }
    if (fstat(descriptor, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
            metadata.st_nlink != 1 || (metadata.st_mode & 07777) != 0600 ||
            metadata.st_uid != expected_uid || metadata.st_gid != expected_gid) {
        close(descriptor);
        (void)pf_tq_error(error, error_size, "durable lock metadata rejected");
        return -1;
    }
    if (flock(descriptor, LOCK_EX) != 0) {
        close(descriptor);
        (void)pf_tq_error(error, error_size, "durable lock acquisition failed: %s", strerror(errno));
        return -1;
    }
    return descriptor;
}

static void pf_tq_close_lock(int descriptor) {
    if (descriptor >= 0) {
        (void)flock(descriptor, LOCK_UN);
        (void)close(descriptor);
    }
}

static int pf_tq_read_event(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const char *filename,
    struct pf_tq_loaded_event *event,
    bool *exists,
    char *error,
    size_t error_size
) {
    int descriptor;
    struct stat before;
    struct stat after;
    ssize_t amount;
    unsigned char extra;
    descriptor = openat(root_fd, filename, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        if (errno == ENOENT) {
            *exists = false;
            return 0;
        }
        return pf_tq_error(error, error_size,
            "durable event open failed for %s: %s", filename, strerror(errno));
    }
    *exists = true;
    if (fstat(descriptor, &before) != 0 || !S_ISREG(before.st_mode) ||
            before.st_nlink != 1 || (before.st_mode & 07777) != 0600 ||
            before.st_uid != expected_uid || before.st_gid != expected_gid ||
            before.st_size <= 0 || before.st_size > (off_t)PF_TQ_EVENT_MAX_BYTES) {
        close(descriptor);
        return pf_tq_error(error, error_size,
            "durable event metadata rejected for %s", filename);
    }
    amount = pread(descriptor, event->bytes, (size_t)before.st_size, 0);
    if (amount != before.st_size || pread(descriptor, &extra, 1U, before.st_size) != 0 ||
            fstat(descriptor, &after) != 0) {
        close(descriptor);
        return pf_tq_error(error, error_size,
            "durable event stable exact read failed for %s", filename);
    }
    close(descriptor);
    if (before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
            before.st_mode != after.st_mode || before.st_uid != after.st_uid ||
            before.st_gid != after.st_gid || before.st_nlink != after.st_nlink ||
            before.st_size != after.st_size) {
        return pf_tq_error(error, error_size,
            "durable event metadata changed for %s", filename);
    }
    event->size = (size_t)before.st_size;
    if (pf_tq_parse_event(event->bytes, event->size, &event->record,
            error, error_size) != 0 ||
            pf_tq_raw_digest(event->bytes, event->size, event->digest,
                error, error_size) != 0) {
        return -1;
    }
    return 0;
}

static int pf_tq_write_event_locked(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const struct pf_tq_event_record *record,
    char *error,
    size_t error_size
) {
    unsigned char bytes[PF_TQ_EVENT_MAX_BYTES];
    size_t size = 0U;
    char filename[PF_TQ_EVENT_FILE_BYTES];
    char temporary[PF_TQ_EVENT_FILE_BYTES];
    int descriptor = -1;
    int attempt;
    struct stat metadata;
    ssize_t amount;
    size_t offset = 0U;
    if (pf_tq_validate_record(record, error, error_size) != 0 ||
            pf_tq_encode_event(record, bytes, &size, error, error_size) != 0 ||
            pf_tq_event_filename(record->key_hex, record->sequence,
                record->status, filename, error, error_size) != 0) {
        return -1;
    }
    for (attempt = 0; attempt < 32; ++attempt) {
        unsigned long counter = ++pf_tq_temp_counter;
        int written = snprintf(temporary, sizeof(temporary),
            ".tmp-%ld-%lu-%.16s", (long)getpid(), counter, record->key_hex);
        if (written <= 0 || written >= (int)sizeof(temporary)) {
            return pf_tq_error(error, error_size, "durable temp filename overflow");
        }
        descriptor = openat(root_fd, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (descriptor >= 0) {
            break;
        }
        if (errno != EEXIST) {
            return pf_tq_error(error, error_size,
                "durable temp create failed: %s", strerror(errno));
        }
    }
    if (descriptor < 0) {
        return pf_tq_error(error, error_size, "durable temp name attempts exhausted");
    }
    while (offset < size) {
        amount = write(descriptor, bytes + offset, size - offset);
        if (amount <= 0) {
            int saved = errno;
            close(descriptor);
            (void)unlinkat(root_fd, temporary, 0);
            return pf_tq_error(error, error_size,
                "durable temp write failed: %s", strerror(saved));
        }
        offset += (size_t)amount;
    }
    if (fstat(descriptor, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
            metadata.st_nlink != 1 || (metadata.st_mode & 07777) != 0600 ||
            metadata.st_uid != expected_uid || metadata.st_gid != expected_gid ||
            metadata.st_size != (off_t)size || fsync(descriptor) != 0) {
        int saved = errno;
        close(descriptor);
        (void)unlinkat(root_fd, temporary, 0);
        return pf_tq_error(error, error_size,
            "durable temp metadata/fsync failed: %s", strerror(saved));
    }
    if (close(descriptor) != 0) {
        (void)unlinkat(root_fd, temporary, 0);
        return pf_tq_error(error, error_size, "durable temp close failed: %s", strerror(errno));
    }
    if (syscall(SYS_renameat2, root_fd, temporary, root_fd, filename,
            RENAME_NOREPLACE) != 0) {
        int saved = errno;
        (void)unlinkat(root_fd, temporary, 0);
        return pf_tq_error(error, error_size,
            "durable no-replace rename failed: %s", strerror(saved));
    }
    if (fsync(root_fd) != 0) {
        return pf_tq_error(error, error_size,
            "durable directory fsync failed after publish: %s", strerror(errno));
    }
    return 0;
}

static void pf_tq_snapshot_absent(
    const char *key,
    pf_tq_durable_snapshot_v2 *snapshot
) {
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->state = PF_TQ_DURABLE_ABSENT;
    memcpy(snapshot->key_hex, key, strlen(key) + 1U);
}

static void pf_tq_snapshot_from_event(
    const struct pf_tq_loaded_event *event,
    pf_tq_durable_snapshot_v2 *snapshot
) {
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->sequence = event->record.sequence;
    memcpy(snapshot->key_hex, event->record.key_hex,
        strlen(event->record.key_hex) + 1U);
    memcpy(snapshot->event_digest, event->digest, strlen(event->digest) + 1U);
    memcpy(snapshot->acceptance_digest, event->record.acceptance_digest,
        strlen(event->record.acceptance_digest) + 1U);
    memcpy(snapshot->response_digest, event->record.response_digest,
        strlen(event->record.response_digest) + 1U);
    memcpy(snapshot->terminal_timestamp, event->record.terminal_timestamp,
        strlen(event->record.terminal_timestamp) + 1U);
    memcpy(snapshot->reason, event->record.reason,
        strlen(event->record.reason) + 1U);
    if (strcmp(event->record.status, "active") == 0) {
        snapshot->state = PF_TQ_DURABLE_ACTIVE;
    } else if (strcmp(event->record.status, "signing") == 0) {
        snapshot->state = PF_TQ_DURABLE_SIGNING;
    } else if (strcmp(event->record.status, "rejected") == 0) {
        snapshot->state = PF_TQ_DURABLE_REJECTED;
    } else {
        snapshot->state = PF_TQ_DURABLE_ACCEPTED;
        snapshot->accepted_response_undelivered =
            strcmp(event->record.status, "accepted-response-undelivered") == 0;
    }
}

static int pf_tq_require_same_tuple(
    const struct pf_tq_event_record *record,
    const pf_tq_durable_tuple_v2 *tuple,
    char *error,
    size_t error_size
) {
    if (strcmp(record->tuple.task_id, tuple->task_id) != 0 ||
            strcmp(record->tuple.operation, tuple->operation) != 0 ||
            strcmp(record->tuple.run_id, tuple->run_id) != 0 ||
            strcmp(record->tuple.nonce, tuple->nonce) != 0) {
        return pf_tq_error(error, error_size, "durable event tuple substitution rejected");
    }
    return 0;
}

static int pf_tq_inspect_locked(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    static const struct {
        unsigned sequence;
        const char *status;
    } candidates[] = {
        {0U, "active"},
        {1U, "signing"},
        {1U, "rejected"},
        {2U, "accepted"},
        {2U, "rejected"},
        {3U, "accepted-response-undelivered"}
    };
    struct pf_tq_loaded_event events[4];
    bool present[4] = {false, false, false, false};
    size_t candidate_index;
    size_t found_count = 0U;
    char key[PF_TQ_DURABLE_KEY_HEX_BYTES + 1];
    if (pf_tq_tuple_key(tuple, key, error, error_size) != 0) {
        return -1;
    }
    memset(events, 0, sizeof(events));
    for (candidate_index = 0U;
            candidate_index < sizeof(candidates) / sizeof(candidates[0]);
            ++candidate_index) {
        char filename[PF_TQ_EVENT_FILE_BYTES];
        struct pf_tq_loaded_event loaded;
        bool exists = false;
        unsigned sequence = candidates[candidate_index].sequence;
        if (pf_tq_event_filename(key, sequence, candidates[candidate_index].status,
                filename, error, error_size) != 0 ||
                pf_tq_read_event(root_fd, expected_uid, expected_gid, filename,
                    &loaded, &exists, error, error_size) != 0) {
            return -1;
        }
        if (!exists) {
            continue;
        }
        if (present[sequence]) {
            return pf_tq_error(error, error_size,
                "multiple durable events exist at sequence %u", sequence);
        }
        if (strcmp(loaded.record.key_hex, key) != 0 ||
                loaded.record.sequence != sequence ||
                strcmp(loaded.record.status, candidates[candidate_index].status) != 0 ||
                pf_tq_require_same_tuple(&loaded.record, tuple, error, error_size) != 0) {
            return pf_tq_error(error, error_size,
                "durable event filename/content mismatch");
        }
        events[sequence] = loaded;
        present[sequence] = true;
        ++found_count;
    }
    if (found_count == 0U) {
        pf_tq_snapshot_absent(key, snapshot);
        return 0;
    }
    if (!present[0]) {
        return pf_tq_error(error, error_size, "durable event chain lacks active root");
    }
    if ((present[2] && !present[1]) || (present[3] && !present[2])) {
        return pf_tq_error(error, error_size, "durable event chain has a sequence gap");
    }
    for (candidate_index = 1U; candidate_index < 4U; ++candidate_index) {
        if (present[candidate_index] &&
                strcmp(events[candidate_index].record.previous_digest,
                    events[candidate_index - 1U].digest) != 0) {
            return pf_tq_error(error, error_size,
                "durable event previousDigest chain mismatch");
        }
    }
    if (present[1] && strcmp(events[1].record.status, "rejected") == 0 &&
            (present[2] || present[3])) {
        return pf_tq_error(error, error_size, "rejected durable state has successors");
    }
    if (present[2] && strcmp(events[1].record.status, "signing") != 0) {
        return pf_tq_error(error, error_size, "durable terminal state lacks signing predecessor");
    }
    if (present[3] && strcmp(events[2].record.status, "accepted") != 0) {
        return pf_tq_error(error, error_size, "undelivered audit lacks accepted predecessor");
    }
    if (present[3]) {
        if (strcmp(events[3].record.acceptance_digest,
                events[2].record.acceptance_digest) != 0 ||
                strcmp(events[3].record.response_digest,
                    events[2].record.response_digest) != 0 ||
                strcmp(events[3].record.terminal_timestamp,
                    events[2].record.terminal_timestamp) != 0) {
            return pf_tq_error(error, error_size,
                "undelivered audit does not preserve accepted terminal values");
        }
        pf_tq_snapshot_from_event(&events[3], snapshot);
    } else if (present[2]) {
        pf_tq_snapshot_from_event(&events[2], snapshot);
    } else if (present[1]) {
        pf_tq_snapshot_from_event(&events[1], snapshot);
    } else {
        pf_tq_snapshot_from_event(&events[0], snapshot);
    }
    return 0;
}

int pf_tq_durable_inspect_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    int lock_descriptor;
    int result;
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL || snapshot == NULL ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return tuple == NULL || snapshot == NULL
            ? pf_tq_error(error, error_size, "durable inspect arguments missing") : -1;
    }
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) {
        return -1;
    }
    result = pf_tq_inspect_locked(root_fd, expected_uid, expected_gid, tuple,
        snapshot, error, error_size);
    pf_tq_close_lock(lock_descriptor);
    return result;
}

static void pf_tq_init_record(
    struct pf_tq_event_record *record,
    const pf_tq_durable_tuple_v2 *tuple,
    const char *key,
    unsigned sequence,
    const char *status
) {
    memset(record, 0, sizeof(*record));
    record->tuple = *tuple;
    memcpy(record->key_hex, key, strlen(key) + 1U);
    memcpy(record->status, status, strlen(status) + 1U);
    record->sequence = sequence;
}

static int pf_tq_publish_and_reload(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    const struct pf_tq_event_record *record,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    if (pf_tq_write_event_locked(root_fd, expected_uid, expected_gid, record,
            error, error_size) != 0) {
        return -1;
    }
    return pf_tq_inspect_locked(root_fd, expected_uid, expected_gid, tuple,
        snapshot, error, error_size);
}

int pf_tq_durable_reserve_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    int lock_descriptor;
    int result;
    pf_tq_durable_snapshot_v2 current;
    struct pf_tq_event_record record;
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL || snapshot == NULL ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return tuple == NULL || snapshot == NULL
            ? pf_tq_error(error, error_size, "durable reserve arguments missing") : -1;
    }
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) return -1;
    result = pf_tq_inspect_locked(root_fd, expected_uid, expected_gid, tuple,
        &current, error, error_size);
    if (result == 0 && current.state != PF_TQ_DURABLE_ABSENT) {
        result = pf_tq_error(error, error_size,
            "durable nonce replay rejected from state %s",
            pf_tq_durable_state_name_v2(current.state));
    }
    if (result == 0) {
        pf_tq_init_record(&record, tuple, current.key_hex, 0U, "active");
        result = pf_tq_publish_and_reload(root_fd, expected_uid, expected_gid,
            tuple, &record, snapshot, error, error_size);
    }
    pf_tq_close_lock(lock_descriptor);
    return result;
}

int pf_tq_durable_begin_signing_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    int lock_descriptor;
    int result;
    pf_tq_durable_snapshot_v2 current;
    struct pf_tq_event_record record;
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL || snapshot == NULL ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return tuple == NULL || snapshot == NULL
            ? pf_tq_error(error, error_size, "durable signing arguments missing") : -1;
    }
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) return -1;
    result = pf_tq_inspect_locked(root_fd, expected_uid, expected_gid, tuple,
        &current, error, error_size);
    if (result == 0 && current.state != PF_TQ_DURABLE_ACTIVE) {
        result = pf_tq_error(error, error_size,
            "durable active-to-signing CAS rejected from state %s",
            pf_tq_durable_state_name_v2(current.state));
    }
    if (result == 0) {
        pf_tq_init_record(&record, tuple, current.key_hex, 1U, "signing");
        memcpy(record.previous_digest, current.event_digest,
            strlen(current.event_digest) + 1U);
        result = pf_tq_publish_and_reload(root_fd, expected_uid, expected_gid,
            tuple, &record, snapshot, error, error_size);
    }
    pf_tq_close_lock(lock_descriptor);
    return result;
}

int pf_tq_durable_accept_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    const char *acceptance_digest,
    const char *response_digest,
    const char *terminal_timestamp,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    int lock_descriptor;
    int result;
    pf_tq_durable_snapshot_v2 current;
    struct pf_tq_event_record record;
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL || snapshot == NULL || !pf_tq_is_digest(acceptance_digest) ||
            !pf_tq_is_digest(response_digest) || !pf_tq_is_timestamp(terminal_timestamp) ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return pf_tq_error(error, error_size, "durable accept arguments rejected");
    }
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) return -1;
    result = pf_tq_inspect_locked(root_fd, expected_uid, expected_gid, tuple,
        &current, error, error_size);
    if (result == 0 && current.state != PF_TQ_DURABLE_SIGNING) {
        result = pf_tq_error(error, error_size,
            "durable signing-to-accepted CAS rejected from state %s",
            pf_tq_durable_state_name_v2(current.state));
    }
    if (result == 0) {
        pf_tq_init_record(&record, tuple, current.key_hex, 2U, "accepted");
        memcpy(record.previous_digest, current.event_digest,
            strlen(current.event_digest) + 1U);
        memcpy(record.acceptance_digest, acceptance_digest,
            strlen(acceptance_digest) + 1U);
        memcpy(record.response_digest, response_digest,
            strlen(response_digest) + 1U);
        memcpy(record.terminal_timestamp, terminal_timestamp,
            strlen(terminal_timestamp) + 1U);
        result = pf_tq_publish_and_reload(root_fd, expected_uid, expected_gid,
            tuple, &record, snapshot, error, error_size);
    }
    pf_tq_close_lock(lock_descriptor);
    return result;
}

static int pf_tq_reject_locked(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    const char *reason,
    const char *terminal_timestamp,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    pf_tq_durable_snapshot_v2 current;
    struct pf_tq_event_record record;
    unsigned sequence;
    int result = pf_tq_inspect_locked(root_fd, expected_uid, expected_gid,
        tuple, &current, error, error_size);
    if (result != 0) return -1;
    if (current.state != PF_TQ_DURABLE_ACTIVE &&
            current.state != PF_TQ_DURABLE_SIGNING) {
        return pf_tq_error(error, error_size,
            "durable rejection transition rejected from state %s",
            pf_tq_durable_state_name_v2(current.state));
    }
    sequence = current.state == PF_TQ_DURABLE_ACTIVE ? 1U : 2U;
    pf_tq_init_record(&record, tuple, current.key_hex, sequence, "rejected");
    memcpy(record.previous_digest, current.event_digest,
        strlen(current.event_digest) + 1U);
    memcpy(record.reason, reason, strlen(reason) + 1U);
    memcpy(record.terminal_timestamp, terminal_timestamp,
        strlen(terminal_timestamp) + 1U);
    return pf_tq_publish_and_reload(root_fd, expected_uid, expected_gid,
        tuple, &record, snapshot, error, error_size);
}

int pf_tq_durable_reject_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    const char *reason,
    const char *terminal_timestamp,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    int lock_descriptor;
    int result;
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL || snapshot == NULL || !pf_tq_is_reason(reason) ||
            !pf_tq_is_timestamp(terminal_timestamp) ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return pf_tq_error(error, error_size, "durable reject arguments rejected");
    }
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) return -1;
    result = pf_tq_reject_locked(root_fd, expected_uid, expected_gid, tuple,
        reason, terminal_timestamp, snapshot, error, error_size);
    pf_tq_close_lock(lock_descriptor);
    return result;
}

int pf_tq_durable_mark_undelivered_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const pf_tq_durable_tuple_v2 *tuple,
    pf_tq_durable_snapshot_v2 *snapshot,
    char *error,
    size_t error_size
) {
    int lock_descriptor;
    int result;
    pf_tq_durable_snapshot_v2 current;
    struct pf_tq_event_record record;
    pf_tq_clear_error(error, error_size);
    if (tuple == NULL || snapshot == NULL ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return pf_tq_error(error, error_size, "durable undelivered arguments rejected");
    }
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) return -1;
    result = pf_tq_inspect_locked(root_fd, expected_uid, expected_gid, tuple,
        &current, error, error_size);
    if (result == 0 && (current.state != PF_TQ_DURABLE_ACCEPTED ||
            current.accepted_response_undelivered)) {
        result = pf_tq_error(error, error_size,
            "durable undelivered audit requires a non-audited accepted state");
    }
    if (result == 0) {
        pf_tq_init_record(&record, tuple, current.key_hex, 3U,
            "accepted-response-undelivered");
        memcpy(record.previous_digest, current.event_digest,
            strlen(current.event_digest) + 1U);
        memcpy(record.acceptance_digest, current.acceptance_digest,
            strlen(current.acceptance_digest) + 1U);
        memcpy(record.response_digest, current.response_digest,
            strlen(current.response_digest) + 1U);
        memcpy(record.terminal_timestamp, current.terminal_timestamp,
            strlen(current.terminal_timestamp) + 1U);
        memcpy(record.reason, "accepted-response-undelivered",
            sizeof("accepted-response-undelivered"));
        result = pf_tq_publish_and_reload(root_fd, expected_uid, expected_gid,
            tuple, &record, snapshot, error, error_size);
    }
    pf_tq_close_lock(lock_descriptor);
    return result;
}

static bool pf_tq_is_event_filename(const char *name, char key[65]) {
    size_t length = name == NULL ? 0U : strlen(name);
    const char *sequence;
    const char *status;
    const char *suffix;
    if (length < 64U + 1U + 3U + 1U + 6U + 5U ||
            !pf_tq_is_lower_hex(name, 64U)) {
        /* pf_tq_is_lower_hex needs an exact-length string, so inspect prefix below. */
        size_t index;
        if (length < 64U) return false;
        for (index = 0U; index < 64U; ++index) {
            unsigned char character = (unsigned char)name[index];
            if (!((character >= '0' && character <= '9') ||
                    (character >= 'a' && character <= 'f'))) return false;
        }
    }
    if (name[64] != '.') return false;
    sequence = name + 65U;
    if (sequence[0] != '0' || sequence[1] != '0' ||
            sequence[2] < '0' || sequence[2] > '3' || sequence[3] != '.') {
        return false;
    }
    status = sequence + 4U;
    suffix = strrchr(status, '.');
    if (suffix == NULL || strcmp(suffix, ".json") != 0) return false;
    if (!((strncmp(status, "active", 6U) == 0 && suffix == status + 6U) ||
            (strncmp(status, "signing", 7U) == 0 && suffix == status + 7U) ||
            (strncmp(status, "accepted", 8U) == 0 && suffix == status + 8U) ||
            (strncmp(status, "rejected", 8U) == 0 && suffix == status + 8U) ||
            (strncmp(status, "accepted-response-undelivered", 29U) == 0 &&
                suffix == status + 29U))) {
        return false;
    }
    memcpy(key, name, 64U);
    key[64] = '\0';
    return true;
}

static bool pf_tq_is_temp_filename(const char *name) {
    return name != NULL && strncmp(name, ".tmp-", 5U) == 0;
}

static int pf_tq_cleanup_temp(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const char *name,
    char *error,
    size_t error_size
) {
    struct stat metadata;
    if (fstatat(root_fd, name, &metadata, AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISREG(metadata.st_mode) || metadata.st_nlink != 1 ||
            (metadata.st_mode & 07777) != 0600 ||
            metadata.st_uid != expected_uid || metadata.st_gid != expected_gid) {
        return pf_tq_error(error, error_size, "durable stale temp metadata rejected");
    }
    if (unlinkat(root_fd, name, 0) != 0) {
        return pf_tq_error(error, error_size,
            "durable stale temp cleanup failed: %s", strerror(errno));
    }
    return 0;
}

int pf_tq_durable_recover_v2(
    int root_fd,
    uid_t expected_uid,
    gid_t expected_gid,
    const char *terminal_timestamp,
    unsigned *recovered_count,
    char *error,
    size_t error_size
) {
    int lock_descriptor = -1;
    int directory_fd = -1;
    DIR *directory = NULL;
    struct dirent *entry;
    char (*keys)[65] = NULL;
    size_t key_count = 0U;
    bool removed_temp = false;
    size_t index;
    int result = -1;
    pf_tq_clear_error(error, error_size);
    if (recovered_count == NULL || !pf_tq_is_timestamp(terminal_timestamp) ||
            pf_tq_durable_validate_root_v2(root_fd, expected_uid, expected_gid,
                error, error_size) != 0) {
        return pf_tq_error(error, error_size, "durable recovery arguments rejected");
    }
    *recovered_count = 0U;
    lock_descriptor = pf_tq_open_lock(root_fd, expected_uid, expected_gid,
        error, error_size);
    if (lock_descriptor < 0) return -1;
    directory_fd = dup(root_fd);
    if (directory_fd < 0 || (directory = fdopendir(directory_fd)) == NULL) {
        if (directory_fd >= 0) close(directory_fd);
        pf_tq_close_lock(lock_descriptor);
        return pf_tq_error(error, error_size, "durable recovery directory open failed");
    }
    keys = calloc(PF_TQ_EVENT_MAX_FILES, sizeof(*keys));
    if (keys == NULL) {
        closedir(directory);
        pf_tq_close_lock(lock_descriptor);
        return pf_tq_error(error, error_size, "durable recovery key allocation failed");
    }
    errno = 0;
    while ((entry = readdir(directory)) != NULL) {
        char key[65];
        size_t existing;
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0 ||
                strcmp(entry->d_name, PF_TQ_LOCK_FILE) == 0) {
            continue;
        }
        if (pf_tq_is_temp_filename(entry->d_name)) {
            if (pf_tq_cleanup_temp(root_fd, expected_uid, expected_gid,
                    entry->d_name, error, error_size) != 0) goto cleanup;
            removed_temp = true;
            continue;
        }
        if (!pf_tq_is_event_filename(entry->d_name, key)) {
            (void)pf_tq_error(error, error_size,
                "durable root contains unknown entry");
            goto cleanup;
        }
        for (existing = 0U; existing < key_count; ++existing) {
            if (strcmp(keys[existing], key) == 0) break;
        }
        if (existing == key_count) {
            if (key_count >= PF_TQ_EVENT_MAX_FILES) {
                (void)pf_tq_error(error, error_size,
                    "durable recovery event-key bound exceeded");
                goto cleanup;
            }
            memcpy(keys[key_count++], key, 65U);
        }
    }
    if (errno != 0) {
        (void)pf_tq_error(error, error_size,
            "durable recovery directory read failed: %s", strerror(errno));
        goto cleanup;
    }
    closedir(directory);
    directory = NULL;
    if (removed_temp && fsync(root_fd) != 0) {
        (void)pf_tq_error(error, error_size,
            "durable directory fsync failed after temp cleanup");
        goto cleanup;
    }
    for (index = 0U; index < key_count; ++index) {
        char active_name[PF_TQ_EVENT_FILE_BYTES];
        struct pf_tq_loaded_event active;
        bool exists = false;
        pf_tq_durable_snapshot_v2 snapshot;
        const char *reason;
        if (pf_tq_event_filename(keys[index], 0U, "active", active_name,
                error, error_size) != 0 ||
                pf_tq_read_event(root_fd, expected_uid, expected_gid,
                    active_name, &active, &exists, error, error_size) != 0 ||
                !exists) {
            if (!exists) (void)pf_tq_error(error, error_size,
                "durable recovery chain lacks active root");
            goto cleanup;
        }
        if (pf_tq_inspect_locked(root_fd, expected_uid, expected_gid,
                &active.record.tuple, &snapshot, error, error_size) != 0) goto cleanup;
        if (snapshot.state != PF_TQ_DURABLE_ACTIVE &&
                snapshot.state != PF_TQ_DURABLE_SIGNING) {
            continue;
        }
        reason = snapshot.state == PF_TQ_DURABLE_ACTIVE
            ? "recovered-stale-active" : "recovered-stale-signing";
        if (pf_tq_reject_locked(root_fd, expected_uid, expected_gid,
                &active.record.tuple, reason, terminal_timestamp, &snapshot,
                error, error_size) != 0) goto cleanup;
        ++*recovered_count;
    }
    result = 0;
cleanup:
    if (directory != NULL) closedir(directory);
    free(keys);
    pf_tq_close_lock(lock_descriptor);
    return result;
}
