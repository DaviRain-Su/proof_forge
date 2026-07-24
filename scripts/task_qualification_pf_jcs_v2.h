#ifndef PROOF_FORGE_TASK_QUALIFICATION_PF_JCS_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_PF_JCS_V2_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_JCS_NONE ((size_t)-1)
#define PF_TQ_JCS_MAX_DEPTH 64U
#define PF_TQ_JCS_MAX_NODES 65536U
#define PF_TQ_JCS_ERROR_BYTES 256U

typedef enum pf_tq_jcs_type_v2 {
    PF_TQ_JCS_NULL = 0,
    PF_TQ_JCS_BOOL = 1,
    PF_TQ_JCS_UINT = 2,
    PF_TQ_JCS_STRING = 3,
    PF_TQ_JCS_ARRAY = 4,
    PF_TQ_JCS_OBJECT = 5
} pf_tq_jcs_type_v2;

typedef struct pf_tq_jcs_node_v2 {
    pf_tq_jcs_type_v2 type;
    size_t raw_start;
    size_t raw_end;
    size_t string_start;
    size_t string_size;
    size_t string_decoded_size;
    int string_has_escape;
    uint64_t uint_value;
    int bool_value;
    size_t first_child;
    size_t last_child;
    size_t child_count;
    size_t next_sibling;
    size_t first_member;
    size_t last_member;
    size_t member_count;
} pf_tq_jcs_node_v2;

typedef struct pf_tq_jcs_member_v2 {
    size_t key_start;
    size_t key_size;
    size_t value_node;
    size_t next_member;
} pf_tq_jcs_member_v2;

typedef struct pf_tq_jcs_document_v2 {
    const unsigned char *bytes;
    size_t size;
    pf_tq_jcs_node_v2 *nodes;
    size_t node_count;
    size_t node_capacity;
    pf_tq_jcs_member_v2 *members;
    size_t member_count;
    size_t member_capacity;
    size_t root;
} pf_tq_jcs_document_v2;

typedef struct pf_tq_jcs_field_v2 {
    const char *key;
    const unsigned char *value;
    size_t value_size;
} pf_tq_jcs_field_v2;

/*
 * The default task-qualification v2 parser retains printable unescaped ASCII
 * strings, non-negative PF-JCS safe integers, bool, null, arrays and closed
 * ASCII-key objects. The explicit Unicode entrypoint below additionally allows
 * exact RFC-8785 escapes and shortest UTF-8 values for isolation mount paths.
 * Whitespace, negative/floating numbers, non-ASCII keys and duplicate or
 * unsorted keys are rejected in both modes.
 */
int pf_tq_jcs_parse_v2(
    const unsigned char *bytes,
    size_t size,
    pf_tq_jcs_document_v2 *document,
    char *error,
    size_t error_size
);

/* Isolation-policy-only extension: values may use shortest UTF-8 and exact
 * RFC-8785 escapes. Closed object keys remain ASCII. Existing protocol owners
 * intentionally stay on pf_tq_jcs_parse_v2 and retain the ASCII-only surface. */
int pf_tq_jcs_parse_unicode_v2(
    const unsigned char *bytes,
    size_t size,
    pf_tq_jcs_document_v2 *document,
    char *error,
    size_t error_size
);

void pf_tq_jcs_free_v2(pf_tq_jcs_document_v2 *document);

const pf_tq_jcs_node_v2 *pf_tq_jcs_root_v2(
    const pf_tq_jcs_document_v2 *document
);

const pf_tq_jcs_node_v2 *pf_tq_jcs_object_get_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *key
);

int pf_tq_jcs_object_exact_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *const *sorted_keys,
    size_t key_count,
    char *error,
    size_t error_size
);

const pf_tq_jcs_node_v2 *pf_tq_jcs_array_at_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *array,
    size_t index
);

int pf_tq_jcs_string_equal_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    const char *expected
);

int pf_tq_jcs_copy_string_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
);

int pf_tq_jcs_raw_equal_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    const unsigned char *expected,
    size_t expected_size
);

int pf_tq_jcs_encode_string_v2(
    const char *value,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
);

int pf_tq_jcs_encode_uint_v2(
    uint64_t value,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
);

int pf_tq_jcs_encode_object_v2(
    const pf_tq_jcs_field_v2 *fields,
    size_t field_count,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
);

int pf_tq_jcs_decode_hex_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    unsigned char *output,
    size_t minimum_bytes,
    size_t maximum_bytes,
    size_t *written,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
