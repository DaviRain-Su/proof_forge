#include "task_qualification_unicode_v2.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct pf_tq_unicode_ccc_v2 {
    uint32_t code;
    uint8_t combining_class;
};

struct pf_tq_unicode_decomposition_v2 {
    uint32_t code;
    uint32_t offset;
    uint8_t length;
};

struct pf_tq_unicode_composition_v2 {
    uint32_t first;
    uint32_t second;
    uint32_t composite;
};

#include "task_qualification_unicode_v2_tables.inc"

#define PF_TQ_UNICODE_SBASE_V2 UINT32_C(0xac00)
#define PF_TQ_UNICODE_LBASE_V2 UINT32_C(0x1100)
#define PF_TQ_UNICODE_VBASE_V2 UINT32_C(0x1161)
#define PF_TQ_UNICODE_TBASE_V2 UINT32_C(0x11a7)
#define PF_TQ_UNICODE_LCOUNT_V2 UINT32_C(19)
#define PF_TQ_UNICODE_VCOUNT_V2 UINT32_C(21)
#define PF_TQ_UNICODE_TCOUNT_V2 UINT32_C(28)
#define PF_TQ_UNICODE_NCOUNT_V2 UINT32_C(588)
#define PF_TQ_UNICODE_SCOUNT_V2 UINT32_C(11172)

_Static_assert(
    sizeof(pf_tq_unicode_ccc_table_v2) /
        sizeof(pf_tq_unicode_ccc_table_v2[0]) == PF_TQ_UNICODE_CCC_COUNT_V2,
    "Unicode CCC table count drift");
_Static_assert(
    sizeof(pf_tq_unicode_decomposition_table_v2) /
        sizeof(pf_tq_unicode_decomposition_table_v2[0]) ==
        PF_TQ_UNICODE_DECOMPOSITION_COUNT_V2,
    "Unicode decomposition table count drift");
_Static_assert(
    sizeof(pf_tq_unicode_composition_table_v2) /
        sizeof(pf_tq_unicode_composition_table_v2[0]) ==
        PF_TQ_UNICODE_COMPOSITION_COUNT_V2,
    "Unicode composition table count drift");
_Static_assert(
    sizeof(pf_tq_unicode_decomposition_values_v2) /
        sizeof(pf_tq_unicode_decomposition_values_v2[0]) ==
        PF_TQ_UNICODE_DECOMPOSITION_VALUE_COUNT_V2,
    "Unicode decomposition value count drift");

static int pf_tq_unicode_error(
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

static void pf_tq_unicode_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

static int pf_tq_unicode_continuation(unsigned char value) {
    return value >= 0x80U && value <= 0xbfU;
}

static int pf_tq_unicode_decode_one(
    const unsigned char *bytes,
    size_t size,
    size_t *offset,
    uint32_t *code,
    char *error,
    size_t error_size
) {
    size_t start = *offset;
    unsigned char first;
    if (start >= size) {
        return pf_tq_unicode_error(error, error_size, "UTF-8 scalar is truncated");
    }
    first = bytes[start];
    if (first <= 0x7fU) {
        *code = first;
        *offset = start + 1U;
        return 0;
    }
    if (first >= 0xc2U && first <= 0xdfU) {
        if (size - start < 2U || !pf_tq_unicode_continuation(bytes[start + 1U])) {
            return pf_tq_unicode_error(error, error_size,
                "UTF-8 two-byte scalar rejected at byte %zu", start);
        }
        *code = ((uint32_t)(first & 0x1fU) << 6U) |
            (uint32_t)(bytes[start + 1U] & 0x3fU);
        *offset = start + 2U;
        return 0;
    }
    if (first >= 0xe0U && first <= 0xefU) {
        unsigned char second;
        if (size - start < 3U ||
                !pf_tq_unicode_continuation(bytes[start + 1U]) ||
                !pf_tq_unicode_continuation(bytes[start + 2U])) {
            return pf_tq_unicode_error(error, error_size,
                "UTF-8 three-byte scalar rejected at byte %zu", start);
        }
        second = bytes[start + 1U];
        if ((first == 0xe0U && second < 0xa0U) ||
                (first == 0xedU && second > 0x9fU)) {
            return pf_tq_unicode_error(error, error_size,
                "UTF-8 overlong/surrogate scalar rejected at byte %zu", start);
        }
        *code = ((uint32_t)(first & 0x0fU) << 12U) |
            ((uint32_t)(second & 0x3fU) << 6U) |
            (uint32_t)(bytes[start + 2U] & 0x3fU);
        *offset = start + 3U;
        return 0;
    }
    if (first >= 0xf0U && first <= 0xf4U) {
        unsigned char second;
        if (size - start < 4U ||
                !pf_tq_unicode_continuation(bytes[start + 1U]) ||
                !pf_tq_unicode_continuation(bytes[start + 2U]) ||
                !pf_tq_unicode_continuation(bytes[start + 3U])) {
            return pf_tq_unicode_error(error, error_size,
                "UTF-8 four-byte scalar rejected at byte %zu", start);
        }
        second = bytes[start + 1U];
        if ((first == 0xf0U && second < 0x90U) ||
                (first == 0xf4U && second > 0x8fU)) {
            return pf_tq_unicode_error(error, error_size,
                "UTF-8 overlong/out-of-range scalar rejected at byte %zu", start);
        }
        *code = ((uint32_t)(first & 0x07U) << 18U) |
            ((uint32_t)(second & 0x3fU) << 12U) |
            ((uint32_t)(bytes[start + 2U] & 0x3fU) << 6U) |
            (uint32_t)(bytes[start + 3U] & 0x3fU);
        *offset = start + 4U;
        return 0;
    }
    return pf_tq_unicode_error(error, error_size,
        "UTF-8 leading byte rejected at byte %zu", start);
}

static uint8_t pf_tq_unicode_ccc(uint32_t code) {
    size_t low = 0U;
    size_t high = PF_TQ_UNICODE_CCC_COUNT_V2;
    while (low < high) {
        size_t middle = low + (high - low) / 2U;
        if (pf_tq_unicode_ccc_table_v2[middle].code < code) {
            low = middle + 1U;
        } else {
            high = middle;
        }
    }
    if (low < PF_TQ_UNICODE_CCC_COUNT_V2 &&
            pf_tq_unicode_ccc_table_v2[low].code == code) {
        return pf_tq_unicode_ccc_table_v2[low].combining_class;
    }
    return 0U;
}

static const struct pf_tq_unicode_decomposition_v2 *pf_tq_unicode_decomposition(
    uint32_t code
) {
    size_t low = 0U;
    size_t high = PF_TQ_UNICODE_DECOMPOSITION_COUNT_V2;
    while (low < high) {
        size_t middle = low + (high - low) / 2U;
        if (pf_tq_unicode_decomposition_table_v2[middle].code < code) {
            low = middle + 1U;
        } else {
            high = middle;
        }
    }
    return low < PF_TQ_UNICODE_DECOMPOSITION_COUNT_V2 &&
        pf_tq_unicode_decomposition_table_v2[low].code == code
        ? &pf_tq_unicode_decomposition_table_v2[low] : NULL;
}

static int pf_tq_unicode_table_composition(
    uint32_t first,
    uint32_t second,
    uint32_t *composite
) {
    size_t low = 0U;
    size_t high = PF_TQ_UNICODE_COMPOSITION_COUNT_V2;
    while (low < high) {
        size_t middle = low + (high - low) / 2U;
        const struct pf_tq_unicode_composition_v2 *row =
            &pf_tq_unicode_composition_table_v2[middle];
        if (row->first < first || (row->first == first && row->second < second)) {
            low = middle + 1U;
        } else {
            high = middle;
        }
    }
    if (low < PF_TQ_UNICODE_COMPOSITION_COUNT_V2 &&
            pf_tq_unicode_composition_table_v2[low].first == first &&
            pf_tq_unicode_composition_table_v2[low].second == second) {
        *composite = pf_tq_unicode_composition_table_v2[low].composite;
        return 1;
    }
    return 0;
}

static int pf_tq_unicode_hangul_composition(
    uint32_t first,
    uint32_t second,
    uint32_t *composite
) {
    if (first >= PF_TQ_UNICODE_LBASE_V2 &&
            first < PF_TQ_UNICODE_LBASE_V2 + PF_TQ_UNICODE_LCOUNT_V2 &&
            second >= PF_TQ_UNICODE_VBASE_V2 &&
            second < PF_TQ_UNICODE_VBASE_V2 + PF_TQ_UNICODE_VCOUNT_V2) {
        uint32_t leading = first - PF_TQ_UNICODE_LBASE_V2;
        uint32_t vowel = second - PF_TQ_UNICODE_VBASE_V2;
        *composite = PF_TQ_UNICODE_SBASE_V2 +
            (leading * PF_TQ_UNICODE_VCOUNT_V2 + vowel) *
                PF_TQ_UNICODE_TCOUNT_V2;
        return 1;
    }
    if (first >= PF_TQ_UNICODE_SBASE_V2 &&
            first < PF_TQ_UNICODE_SBASE_V2 + PF_TQ_UNICODE_SCOUNT_V2 &&
            (first - PF_TQ_UNICODE_SBASE_V2) % PF_TQ_UNICODE_TCOUNT_V2 == 0U &&
            second > PF_TQ_UNICODE_TBASE_V2 &&
            second < PF_TQ_UNICODE_TBASE_V2 + PF_TQ_UNICODE_TCOUNT_V2) {
        *composite = first + second - PF_TQ_UNICODE_TBASE_V2;
        return 1;
    }
    return 0;
}

static int pf_tq_unicode_composition(
    uint32_t first,
    uint32_t second,
    uint32_t *composite
) {
    return pf_tq_unicode_hangul_composition(first, second, composite) ||
        pf_tq_unicode_table_composition(first, second, composite);
}

static size_t pf_tq_unicode_decompose_one(uint32_t code, uint32_t output[4]) {
    const struct pf_tq_unicode_decomposition_v2 *row;
    if (code >= PF_TQ_UNICODE_SBASE_V2 &&
            code < PF_TQ_UNICODE_SBASE_V2 + PF_TQ_UNICODE_SCOUNT_V2) {
        uint32_t index = code - PF_TQ_UNICODE_SBASE_V2;
        uint32_t trailing = index % PF_TQ_UNICODE_TCOUNT_V2;
        output[0] = PF_TQ_UNICODE_LBASE_V2 + index / PF_TQ_UNICODE_NCOUNT_V2;
        output[1] = PF_TQ_UNICODE_VBASE_V2 +
            (index % PF_TQ_UNICODE_NCOUNT_V2) / PF_TQ_UNICODE_TCOUNT_V2;
        if (trailing != 0U) {
            output[2] = PF_TQ_UNICODE_TBASE_V2 + trailing;
            return 3U;
        }
        return 2U;
    }
    row = pf_tq_unicode_decomposition(code);
    if (row == NULL) {
        output[0] = code;
        return 1U;
    }
    for (size_t index = 0U; index < row->length; ++index) {
        output[index] = pf_tq_unicode_decomposition_values_v2[row->offset + index];
    }
    return row->length;
}

static void pf_tq_unicode_reorder(uint32_t *codes, size_t count) {
    size_t index;
    for (index = 1U; index < count; ++index) {
        uint32_t code = codes[index];
        uint8_t combining_class = pf_tq_unicode_ccc(code);
        size_t position = index;
        if (combining_class == 0U) continue;
        while (position > 0U) {
            uint8_t previous_class = pf_tq_unicode_ccc(codes[position - 1U]);
            if (previous_class == 0U || previous_class <= combining_class) break;
            codes[position] = codes[position - 1U];
            --position;
        }
        codes[position] = code;
    }
}

static size_t pf_tq_unicode_compose(uint32_t *codes, size_t count) {
    size_t output_count;
    size_t starter_position = SIZE_MAX;
    uint32_t starter = 0U;
    uint8_t last_class;
    size_t index;
    if (count == 0U) return 0U;
    output_count = 1U;
    last_class = pf_tq_unicode_ccc(codes[0]);
    if (last_class == 0U) {
        starter_position = 0U;
        starter = codes[0];
    }
    for (index = 1U; index < count; ++index) {
        uint32_t code = codes[index];
        uint8_t combining_class = pf_tq_unicode_ccc(code);
        uint32_t composite = 0U;
        int composed = starter_position != SIZE_MAX &&
            (last_class == 0U || last_class < combining_class) &&
            pf_tq_unicode_composition(starter, code, &composite);
        if (composed) {
            codes[starter_position] = composite;
            starter = composite;
            continue;
        }
        if (combining_class == 0U) {
            starter_position = output_count;
            starter = code;
        }
        codes[output_count++] = code;
        last_class = combining_class;
    }
    return output_count;
}

int pf_tq_unicode_require_nfc_v2(
    const unsigned char *bytes,
    size_t size,
    char *error,
    size_t error_size
) {
    uint32_t *original = NULL;
    uint32_t *normalized = NULL;
    size_t original_count = 0U;
    size_t normalized_count = 0U;
    size_t normalized_capacity;
    size_t offset = 0U;
    int result = -1;
    pf_tq_unicode_clear_error(error, error_size);
    if (bytes == NULL || size > SIZE_MAX / (4U * sizeof(uint32_t))) {
        return pf_tq_unicode_error(error, error_size,
            "Unicode NFC input pointer/size rejected");
    }
    original = malloc((size == 0U ? 1U : size) * sizeof(*original));
    normalized_capacity = size == 0U ? 1U : size * 4U;
    normalized = malloc(normalized_capacity * sizeof(*normalized));
    if (original == NULL || normalized == NULL) {
        (void)pf_tq_unicode_error(error, error_size,
            "Unicode NFC allocation failed");
        goto cleanup;
    }
    while (offset < size) {
        uint32_t code = 0U;
        uint32_t mapping[4];
        size_t mapping_count;
        if (pf_tq_unicode_decode_one(bytes, size, &offset, &code,
                error, error_size) != 0) goto cleanup;
        original[original_count++] = code;
        mapping_count = pf_tq_unicode_decompose_one(code, mapping);
        if (mapping_count > normalized_capacity - normalized_count) {
            (void)pf_tq_unicode_error(error, error_size,
                "Unicode NFC decomposition bound exceeded");
            goto cleanup;
        }
        memcpy(normalized + normalized_count, mapping,
            mapping_count * sizeof(*mapping));
        normalized_count += mapping_count;
    }
    pf_tq_unicode_reorder(normalized, normalized_count);
    normalized_count = pf_tq_unicode_compose(normalized, normalized_count);
    if (normalized_count != original_count || memcmp(
            normalized, original, original_count * sizeof(*original)) != 0) {
        (void)pf_tq_unicode_error(error, error_size,
            "string must already be NFC under Unicode 17.0.0");
        goto cleanup;
    }
    result = 0;
cleanup:
    free(original);
    free(normalized);
    return result;
}
