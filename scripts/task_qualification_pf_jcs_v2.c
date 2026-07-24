#include "task_qualification_pf_jcs_v2.h"

#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PF_TQ_JCS_MAX_SAFE_INTEGER UINT64_C(9007199254740991)

struct pf_tq_jcs_parser {
    pf_tq_jcs_document_v2 *document;
    size_t offset;
    char *error;
    size_t error_size;
};

static int pf_tq_jcs_error(
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

static void pf_tq_jcs_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static int pf_tq_jcs_key_compare(
    const unsigned char *left,
    size_t left_size,
    const unsigned char *right,
    size_t right_size
) {
    size_t shared = left_size < right_size ? left_size : right_size;
    int comparison = memcmp(left, right, shared);
    if (comparison != 0) return comparison;
    if (left_size < right_size) return -1;
    if (left_size > right_size) return 1;
    return 0;
}

static size_t pf_tq_jcs_allocate_node(struct pf_tq_jcs_parser *parser) {
    pf_tq_jcs_document_v2 *document = parser->document;
    size_t index;
    if (document->node_count >= document->node_capacity) {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS node bound exceeded");
        return PF_TQ_JCS_NONE;
    }
    index = document->node_count++;
    memset(&document->nodes[index], 0, sizeof(document->nodes[index]));
    document->nodes[index].first_child = PF_TQ_JCS_NONE;
    document->nodes[index].last_child = PF_TQ_JCS_NONE;
    document->nodes[index].next_sibling = PF_TQ_JCS_NONE;
    document->nodes[index].first_member = PF_TQ_JCS_NONE;
    document->nodes[index].last_member = PF_TQ_JCS_NONE;
    return index;
}

static size_t pf_tq_jcs_allocate_member(struct pf_tq_jcs_parser *parser) {
    pf_tq_jcs_document_v2 *document = parser->document;
    size_t index;
    if (document->member_count >= document->member_capacity) {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS object-member bound exceeded");
        return PF_TQ_JCS_NONE;
    }
    index = document->member_count++;
    memset(&document->members[index], 0, sizeof(document->members[index]));
    document->members[index].next_member = PF_TQ_JCS_NONE;
    return index;
}

static int pf_tq_jcs_parse_string_range(
    struct pf_tq_jcs_parser *parser,
    size_t *start,
    size_t *size
) {
    const unsigned char *bytes = parser->document->bytes;
    size_t input_size = parser->document->size;
    size_t begin;
    if (parser->offset >= input_size || bytes[parser->offset] != '"') {
        return pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS string expected at byte %zu", parser->offset);
    }
    ++parser->offset;
    begin = parser->offset;
    while (parser->offset < input_size && bytes[parser->offset] != '"') {
        unsigned char character = bytes[parser->offset];
        if (character < 0x20U || character > 0x7eU || character == '\\') {
            return pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS protocol string escape/non-ASCII byte rejected at %zu",
                parser->offset);
        }
        ++parser->offset;
    }
    if (parser->offset >= input_size) {
        return pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS string is unterminated");
    }
    *start = begin;
    *size = parser->offset - begin;
    ++parser->offset;
    return 0;
}

static size_t pf_tq_jcs_parse_value(struct pf_tq_jcs_parser *parser, unsigned depth);

static size_t pf_tq_jcs_parse_string_node(struct pf_tq_jcs_parser *parser) {
    size_t index = pf_tq_jcs_allocate_node(parser);
    pf_tq_jcs_node_v2 *node;
    if (index == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
    node = &parser->document->nodes[index];
    node->type = PF_TQ_JCS_STRING;
    node->raw_start = parser->offset;
    if (pf_tq_jcs_parse_string_range(parser, &node->string_start,
            &node->string_size) != 0) {
        return PF_TQ_JCS_NONE;
    }
    node->raw_end = parser->offset;
    return index;
}

static size_t pf_tq_jcs_parse_literal(
    struct pf_tq_jcs_parser *parser,
    const char *literal,
    pf_tq_jcs_type_v2 type,
    int bool_value
) {
    size_t length = strlen(literal);
    size_t index;
    pf_tq_jcs_node_v2 *node;
    if (length > parser->document->size - parser->offset ||
            memcmp(parser->document->bytes + parser->offset, literal, length) != 0) {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS literal expected at byte %zu", parser->offset);
        return PF_TQ_JCS_NONE;
    }
    index = pf_tq_jcs_allocate_node(parser);
    if (index == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
    node = &parser->document->nodes[index];
    node->type = type;
    node->bool_value = bool_value;
    node->raw_start = parser->offset;
    parser->offset += length;
    node->raw_end = parser->offset;
    return index;
}

static size_t pf_tq_jcs_parse_uint(struct pf_tq_jcs_parser *parser) {
    size_t index;
    pf_tq_jcs_node_v2 *node;
    uint64_t value = 0U;
    size_t start = parser->offset;
    const unsigned char *bytes = parser->document->bytes;
    size_t size = parser->document->size;
    if (start >= size || bytes[start] < '0' || bytes[start] > '9') {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS unsigned integer expected at byte %zu", start);
        return PF_TQ_JCS_NONE;
    }
    if (bytes[start] == '0' && start + 1U < size &&
            bytes[start + 1U] >= '0' && bytes[start + 1U] <= '9') {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS integer has a leading zero");
        return PF_TQ_JCS_NONE;
    }
    while (parser->offset < size && bytes[parser->offset] >= '0' &&
            bytes[parser->offset] <= '9') {
        unsigned digit = (unsigned)(bytes[parser->offset] - '0');
        if (value > (PF_TQ_JCS_MAX_SAFE_INTEGER - digit) / 10U) {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS integer exceeds 2^53-1");
            return PF_TQ_JCS_NONE;
        }
        value = value * 10U + digit;
        ++parser->offset;
    }
    index = pf_tq_jcs_allocate_node(parser);
    if (index == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
    node = &parser->document->nodes[index];
    node->type = PF_TQ_JCS_UINT;
    node->uint_value = value;
    node->raw_start = start;
    node->raw_end = parser->offset;
    return index;
}

static int pf_tq_jcs_append_child(
    struct pf_tq_jcs_parser *parser,
    pf_tq_jcs_node_v2 *array,
    size_t child
) {
    if (array->first_child == PF_TQ_JCS_NONE) {
        array->first_child = child;
    } else {
        parser->document->nodes[array->last_child].next_sibling = child;
    }
    array->last_child = child;
    ++array->child_count;
    return 0;
}

static size_t pf_tq_jcs_parse_array(
    struct pf_tq_jcs_parser *parser,
    unsigned depth
) {
    size_t index = pf_tq_jcs_allocate_node(parser);
    pf_tq_jcs_node_v2 *array;
    if (index == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
    array = &parser->document->nodes[index];
    array->type = PF_TQ_JCS_ARRAY;
    array->raw_start = parser->offset++;
    if (parser->offset < parser->document->size &&
            parser->document->bytes[parser->offset] == ']') {
        ++parser->offset;
        array->raw_end = parser->offset;
        return index;
    }
    for (;;) {
        size_t child = pf_tq_jcs_parse_value(parser, depth + 1U);
        if (child == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
        (void)pf_tq_jcs_append_child(parser, array, child);
        if (parser->offset >= parser->document->size) {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS array is unterminated");
            return PF_TQ_JCS_NONE;
        }
        if (parser->document->bytes[parser->offset] == ']') {
            ++parser->offset;
            array->raw_end = parser->offset;
            return index;
        }
        if (parser->document->bytes[parser->offset++] != ',') {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS array separator expected");
            return PF_TQ_JCS_NONE;
        }
    }
}

static int pf_tq_jcs_append_member(
    struct pf_tq_jcs_parser *parser,
    pf_tq_jcs_node_v2 *object,
    size_t member
) {
    if (object->first_member == PF_TQ_JCS_NONE) {
        object->first_member = member;
    } else {
        parser->document->members[object->last_member].next_member = member;
    }
    object->last_member = member;
    ++object->member_count;
    return 0;
}

static size_t pf_tq_jcs_parse_object(
    struct pf_tq_jcs_parser *parser,
    unsigned depth
) {
    size_t index = pf_tq_jcs_allocate_node(parser);
    pf_tq_jcs_node_v2 *object;
    size_t previous_key_start = 0U;
    size_t previous_key_size = 0U;
    bool has_previous = false;
    if (index == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
    object = &parser->document->nodes[index];
    object->type = PF_TQ_JCS_OBJECT;
    object->raw_start = parser->offset++;
    if (parser->offset < parser->document->size &&
            parser->document->bytes[parser->offset] == '}') {
        ++parser->offset;
        object->raw_end = parser->offset;
        return index;
    }
    for (;;) {
        size_t key_start;
        size_t key_size;
        size_t member;
        size_t value;
        if (pf_tq_jcs_parse_string_range(parser, &key_start, &key_size) != 0) {
            return PF_TQ_JCS_NONE;
        }
        if (key_size == 0U) {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS object key must be nonempty");
            return PF_TQ_JCS_NONE;
        }
        if (has_previous && pf_tq_jcs_key_compare(
                parser->document->bytes + previous_key_start, previous_key_size,
                parser->document->bytes + key_start, key_size) >= 0) {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS object keys are duplicate or not ASCII-sorted");
            return PF_TQ_JCS_NONE;
        }
        previous_key_start = key_start;
        previous_key_size = key_size;
        has_previous = true;
        if (parser->offset >= parser->document->size ||
                parser->document->bytes[parser->offset++] != ':') {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS object colon expected");
            return PF_TQ_JCS_NONE;
        }
        value = pf_tq_jcs_parse_value(parser, depth + 1U);
        if (value == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
        member = pf_tq_jcs_allocate_member(parser);
        if (member == PF_TQ_JCS_NONE) return PF_TQ_JCS_NONE;
        parser->document->members[member].key_start = key_start;
        parser->document->members[member].key_size = key_size;
        parser->document->members[member].value_node = value;
        (void)pf_tq_jcs_append_member(parser, object, member);
        if (parser->offset >= parser->document->size) {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS object is unterminated");
            return PF_TQ_JCS_NONE;
        }
        if (parser->document->bytes[parser->offset] == '}') {
            ++parser->offset;
            object->raw_end = parser->offset;
            return index;
        }
        if (parser->document->bytes[parser->offset++] != ',') {
            (void)pf_tq_jcs_error(parser->error, parser->error_size,
                "PF-JCS object separator expected");
            return PF_TQ_JCS_NONE;
        }
    }
}

static size_t pf_tq_jcs_parse_value(struct pf_tq_jcs_parser *parser, unsigned depth) {
    unsigned char character;
    if (depth > PF_TQ_JCS_MAX_DEPTH) {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS nesting depth exceeds %u", PF_TQ_JCS_MAX_DEPTH);
        return PF_TQ_JCS_NONE;
    }
    if (parser->offset >= parser->document->size) {
        (void)pf_tq_jcs_error(parser->error, parser->error_size,
            "PF-JCS value is truncated");
        return PF_TQ_JCS_NONE;
    }
    character = parser->document->bytes[parser->offset];
    if (character == '"') return pf_tq_jcs_parse_string_node(parser);
    if (character == '{') return pf_tq_jcs_parse_object(parser, depth);
    if (character == '[') return pf_tq_jcs_parse_array(parser, depth);
    if (character == 'n') return pf_tq_jcs_parse_literal(
        parser, "null", PF_TQ_JCS_NULL, 0);
    if (character == 't') return pf_tq_jcs_parse_literal(
        parser, "true", PF_TQ_JCS_BOOL, 1);
    if (character == 'f') return pf_tq_jcs_parse_literal(
        parser, "false", PF_TQ_JCS_BOOL, 0);
    if (character >= '0' && character <= '9') return pf_tq_jcs_parse_uint(parser);
    (void)pf_tq_jcs_error(parser->error, parser->error_size,
        "PF-JCS unsupported value byte 0x%02x at %zu", character, parser->offset);
    return PF_TQ_JCS_NONE;
}

int pf_tq_jcs_parse_v2(
    const unsigned char *bytes,
    size_t size,
    pf_tq_jcs_document_v2 *document,
    char *error,
    size_t error_size
) {
    struct pf_tq_jcs_parser parser;
    size_t capacity;
    pf_tq_jcs_clear_error(error, error_size);
    if (bytes == NULL || document == NULL || size == 0U || size > 4194304U) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS input/size must be exact 1..4194304 bytes");
    }
    memset(document, 0, sizeof(*document));
    capacity = size / 2U + 1U;
    if (capacity < 16U) capacity = 16U;
    if (capacity > PF_TQ_JCS_MAX_NODES) capacity = PF_TQ_JCS_MAX_NODES;
    document->nodes = calloc(capacity, sizeof(*document->nodes));
    document->members = calloc(capacity, sizeof(*document->members));
    if (document->nodes == NULL || document->members == NULL) {
        pf_tq_jcs_free_v2(document);
        return pf_tq_jcs_error(error, error_size, "PF-JCS arena allocation failed");
    }
    document->bytes = bytes;
    document->size = size;
    document->node_capacity = capacity;
    document->member_capacity = capacity;
    document->root = PF_TQ_JCS_NONE;
    parser.document = document;
    parser.offset = 0U;
    parser.error = error;
    parser.error_size = error_size;
    document->root = pf_tq_jcs_parse_value(&parser, 0U);
    if (document->root == PF_TQ_JCS_NONE) {
        pf_tq_jcs_free_v2(document);
        return -1;
    }
    if (parser.offset != size) {
        pf_tq_jcs_free_v2(document);
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS trailing bytes at %zu", parser.offset);
    }
    return 0;
}

void pf_tq_jcs_free_v2(pf_tq_jcs_document_v2 *document) {
    if (document != NULL) {
        free(document->nodes);
        free(document->members);
        memset(document, 0, sizeof(*document));
        document->root = PF_TQ_JCS_NONE;
    }
}

const pf_tq_jcs_node_v2 *pf_tq_jcs_root_v2(
    const pf_tq_jcs_document_v2 *document
) {
    if (document == NULL || document->nodes == NULL ||
            document->root == PF_TQ_JCS_NONE ||
            document->root >= document->node_count) return NULL;
    return &document->nodes[document->root];
}

const pf_tq_jcs_node_v2 *pf_tq_jcs_object_get_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *key
) {
    size_t member;
    size_t key_size;
    if (document == NULL || object == NULL || key == NULL ||
            object->type != PF_TQ_JCS_OBJECT) return NULL;
    key_size = strlen(key);
    member = object->first_member;
    while (member != PF_TQ_JCS_NONE) {
        const pf_tq_jcs_member_v2 *entry;
        if (member >= document->member_count) return NULL;
        entry = &document->members[member];
        if (entry->key_size == key_size && memcmp(
                document->bytes + entry->key_start, key, key_size) == 0) {
            if (entry->value_node >= document->node_count) return NULL;
            return &document->nodes[entry->value_node];
        }
        member = entry->next_member;
    }
    return NULL;
}

int pf_tq_jcs_object_exact_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *const *sorted_keys,
    size_t key_count,
    char *error,
    size_t error_size
) {
    size_t member;
    size_t index = 0U;
    if (document == NULL || object == NULL || sorted_keys == NULL ||
            object->type != PF_TQ_JCS_OBJECT || object->member_count != key_count) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS object field count/type mismatch");
    }
    member = object->first_member;
    while (member != PF_TQ_JCS_NONE && index < key_count) {
        const pf_tq_jcs_member_v2 *entry = &document->members[member];
        size_t expected_size = strlen(sorted_keys[index]);
        if (entry->key_size != expected_size || memcmp(
                document->bytes + entry->key_start,
                sorted_keys[index], expected_size) != 0) {
            return pf_tq_jcs_error(error, error_size,
                "PF-JCS object field manifest mismatch at index %zu", index);
        }
        member = entry->next_member;
        ++index;
    }
    if (member != PF_TQ_JCS_NONE || index != key_count) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS object member chain mismatch");
    }
    return 0;
}

const pf_tq_jcs_node_v2 *pf_tq_jcs_array_at_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *array,
    size_t index
) {
    size_t child;
    size_t cursor = 0U;
    if (document == NULL || array == NULL || array->type != PF_TQ_JCS_ARRAY ||
            index >= array->child_count) return NULL;
    child = array->first_child;
    while (child != PF_TQ_JCS_NONE && cursor < index) {
        if (child >= document->node_count) return NULL;
        child = document->nodes[child].next_sibling;
        ++cursor;
    }
    return child == PF_TQ_JCS_NONE || child >= document->node_count
        ? NULL : &document->nodes[child];
}

int pf_tq_jcs_string_equal_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    const char *expected
) {
    size_t expected_size;
    if (document == NULL || node == NULL || expected == NULL ||
            node->type != PF_TQ_JCS_STRING) return 0;
    expected_size = strlen(expected);
    return node->string_size == expected_size && memcmp(
        document->bytes + node->string_start, expected, expected_size) == 0;
}

int pf_tq_jcs_copy_string_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    if (document == NULL || node == NULL || output == NULL ||
            node->type != PF_TQ_JCS_STRING ||
            node->string_size == 0U || node->string_size >= output_size) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS string copy type/size rejected");
    }
    memcpy(output, document->bytes + node->string_start, node->string_size);
    output[node->string_size] = '\0';
    return 0;
}

int pf_tq_jcs_raw_equal_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    const unsigned char *expected,
    size_t expected_size
) {
    size_t actual_size;
    if (document == NULL || node == NULL || expected == NULL ||
            node->raw_end < node->raw_start) return 0;
    actual_size = node->raw_end - node->raw_start;
    return actual_size == expected_size && memcmp(
        document->bytes + node->raw_start, expected, expected_size) == 0;
}

static bool pf_tq_jcs_safe_string(const char *value) {
    size_t index;
    size_t size = value == NULL ? 0U : strlen(value);
    for (index = 0U; index < size; ++index) {
        unsigned char character = (unsigned char)value[index];
        if (character < 0x20U || character > 0x7eU ||
                character == '"' || character == '\\') return false;
    }
    return value != NULL;
}

int pf_tq_jcs_encode_string_v2(
    const char *value,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
) {
    size_t size;
    if (!pf_tq_jcs_safe_string(value) || output == NULL || written == NULL) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS protocol string encoding rejected");
    }
    size = strlen(value);
    if (size > output_size || output_size - size < 2U) {
        return pf_tq_jcs_error(error, error_size, "PF-JCS string output overflow");
    }
    output[0] = '"';
    memcpy(output + 1U, value, size);
    output[size + 1U] = '"';
    *written = size + 2U;
    return 0;
}

int pf_tq_jcs_encode_uint_v2(
    uint64_t value,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
) {
    char temporary[32];
    int size;
    if (value > PF_TQ_JCS_MAX_SAFE_INTEGER || output == NULL || written == NULL) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS safe integer encoding rejected");
    }
    size = snprintf(temporary, sizeof(temporary), "%llu",
        (unsigned long long)value);
    if (size <= 0 || (size_t)size > output_size) {
        return pf_tq_jcs_error(error, error_size, "PF-JCS integer output overflow");
    }
    memcpy(output, temporary, (size_t)size);
    *written = (size_t)size;
    return 0;
}

static int pf_tq_jcs_output_append(
    unsigned char *output,
    size_t output_size,
    size_t *offset,
    const unsigned char *value,
    size_t value_size,
    char *error,
    size_t error_size
) {
    if (value == NULL || value_size > output_size - *offset) {
        return pf_tq_jcs_error(error, error_size, "PF-JCS object output overflow");
    }
    memcpy(output + *offset, value, value_size);
    *offset += value_size;
    return 0;
}

int pf_tq_jcs_encode_object_v2(
    const pf_tq_jcs_field_v2 *fields,
    size_t field_count,
    unsigned char *output,
    size_t output_size,
    size_t *written,
    char *error,
    size_t error_size
) {
    size_t index;
    size_t offset = 0U;
    if (fields == NULL || field_count == 0U || output == NULL ||
            written == NULL || output_size == 0U) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS object encoder arguments rejected");
    }
    if (pf_tq_jcs_output_append(output, output_size, &offset,
            (const unsigned char *)"{", 1U, error, error_size) != 0) return -1;
    for (index = 0U; index < field_count; ++index) {
        size_t key_size;
        if (!pf_tq_jcs_safe_string(fields[index].key) ||
                fields[index].key[0] == '\0' || fields[index].value == NULL ||
                fields[index].value_size == 0U) {
            return pf_tq_jcs_error(error, error_size,
                "PF-JCS object field rejected at index %zu", index);
        }
        if (index > 0U && strcmp(fields[index - 1U].key, fields[index].key) >= 0) {
            return pf_tq_jcs_error(error, error_size,
                "PF-JCS object fields are duplicate or unsorted");
        }
        if (index > 0U && pf_tq_jcs_output_append(output, output_size, &offset,
                (const unsigned char *)",", 1U, error, error_size) != 0) return -1;
        key_size = strlen(fields[index].key);
        if (pf_tq_jcs_output_append(output, output_size, &offset,
                (const unsigned char *)"\"", 1U, error, error_size) != 0 ||
                pf_tq_jcs_output_append(output, output_size, &offset,
                    (const unsigned char *)fields[index].key, key_size,
                    error, error_size) != 0 ||
                pf_tq_jcs_output_append(output, output_size, &offset,
                    (const unsigned char *)"\":", 2U, error, error_size) != 0 ||
                pf_tq_jcs_output_append(output, output_size, &offset,
                    fields[index].value, fields[index].value_size,
                    error, error_size) != 0) return -1;
    }
    if (pf_tq_jcs_output_append(output, output_size, &offset,
            (const unsigned char *)"}", 1U, error, error_size) != 0) return -1;
    *written = offset;
    return 0;
}

static int pf_tq_jcs_hex_value(unsigned char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
}

int pf_tq_jcs_decode_hex_v2(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    unsigned char *output,
    size_t minimum_bytes,
    size_t maximum_bytes,
    size_t *written,
    char *error,
    size_t error_size
) {
    size_t decoded_size;
    size_t index;
    if (document == NULL || node == NULL || output == NULL || written == NULL ||
            node->type != PF_TQ_JCS_STRING || node->string_size % 2U != 0U) {
        return pf_tq_jcs_error(error, error_size, "PF-JCS lowercase hex rejected");
    }
    decoded_size = node->string_size / 2U;
    if (decoded_size < minimum_bytes || decoded_size > maximum_bytes) {
        return pf_tq_jcs_error(error, error_size,
            "PF-JCS lowercase hex decoded size rejected");
    }
    for (index = 0U; index < decoded_size; ++index) {
        int high = pf_tq_jcs_hex_value(
            document->bytes[node->string_start + 2U * index]);
        int low = pf_tq_jcs_hex_value(
            document->bytes[node->string_start + 2U * index + 1U]);
        if (high < 0 || low < 0) {
            return pf_tq_jcs_error(error, error_size,
                "PF-JCS lowercase hex character rejected");
        }
        output[index] = (unsigned char)((unsigned)high * 16U + (unsigned)low);
    }
    *written = decoded_size;
    return 0;
}
