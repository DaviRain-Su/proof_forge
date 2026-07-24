#define _GNU_SOURCE
#include "task_qualification_authority_policy_v2.h"

#include <openssl/bn.h>
#include <openssl/evp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PF_TQ_AUTHORITY_POLICY_DOMAIN_V2 "pf.bootstrap-authority-policy.v1"
#define PF_TQ_AUTHORITY_POLICY_STORE_SCHEMA_V2 \
    "proof-forge.authority-store-service.v1"

#define PF_TQ_ROLE_ARCHITECTURE PF_TQ_HANDOFF_ROLE_ARCHITECTURE_V2
#define PF_TQ_ROLE_QUALITY PF_TQ_HANDOFF_ROLE_QUALITY_V2
#define PF_TQ_ROLE_SECURITY PF_TQ_HANDOFF_ROLE_SECURITY_V2
#define PF_TQ_ROLE_RELEASE PF_TQ_HANDOFF_ROLE_RELEASE_V2

static int pf_tq_authority_error(
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

static void pf_tq_authority_clear_error(char *error, size_t error_size) {
    if (error != NULL && error_size > 0U) error[0] = '\0';
}

void pf_tq_authority_policy_free_v2(pf_tq_authority_policy_v2 *policy) {
    if (policy == NULL) return;
    free(policy->canonical_bytes);
    free(policy->principals);
    memset(policy, 0, sizeof(*policy));
}

static int pf_tq_authority_fixed_string(const char *value, size_t capacity) {
    return value != NULL && memchr(value, '\0', capacity) != NULL;
}

static int pf_tq_authority_digest(
    const unsigned char *bytes,
    size_t size,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    static const unsigned char zero = 0U;
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    unsigned int output_size = 0U;
    if (context == NULL || EVP_DigestInit_ex(context, EVP_sha256(), NULL) != 1 ||
            EVP_DigestUpdate(context, PF_TQ_AUTHORITY_POLICY_DOMAIN_V2,
                strlen(PF_TQ_AUTHORITY_POLICY_DOMAIN_V2)) != 1 ||
            EVP_DigestUpdate(context, &zero, 1U) != 1 ||
            EVP_DigestUpdate(context, bytes, size) != 1 ||
            EVP_DigestFinal_ex(context, output, &output_size) != 1 ||
            output_size != 32U) {
        EVP_MD_CTX_free(context);
        return pf_tq_authority_error(error, error_size,
            "authority policy SHA-256 failed");
    }
    EVP_MD_CTX_free(context);
    return 0;
}

static const pf_tq_jcs_node_v2 *pf_tq_authority_field(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field
) {
    return pf_tq_jcs_object_get_v2(document, object, field);
}

static int pf_tq_authority_copy_string(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    char *output,
    size_t output_size,
    char *error,
    size_t error_size
) {
    if (pf_tq_jcs_copy_string_v2(document,
            pf_tq_authority_field(document, object, field), output,
            output_size, error, error_size) != 0) {
        return pf_tq_authority_error(error, error_size,
            "authority policy string field rejected: %s", field);
    }
    return 0;
}

static int pf_tq_authority_string_exact(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *object,
    const char *field,
    const char *expected,
    char *error,
    size_t error_size
) {
    if (!pf_tq_jcs_string_equal_v2(document,
            pf_tq_authority_field(document, object, field), expected)) {
        return pf_tq_authority_error(error, error_size,
            "authority policy %s mismatch", field);
    }
    return 0;
}

static int pf_tq_authority_hex32(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    unsigned char output[32],
    char *error,
    size_t error_size
) {
    size_t written = 0U;
    if (pf_tq_jcs_decode_hex_v2(document, node, output, 32U, 32U,
            &written, error, error_size) != 0 || written != 32U) {
        return pf_tq_authority_error(error, error_size,
            "authority policy public key must be 32-byte lowercase hex");
    }
    return 0;
}

/* Strict public-data Ed25519 point validation. OpenSSL accepts arbitrary raw
 * 32-byte Ed25519 public keys in EVP_PKEY_public_check, so the policy owner
 * performs the canonical prime-subgroup test frozen by the Python authority
 * consumer. The BIGNUM path handles only public values and need not be
 * constant-time. */
typedef struct pf_tq_ed_point_v2 {
    BIGNUM *x;
    BIGNUM *y;
    BIGNUM *z;
    BIGNUM *t;
} pf_tq_ed_point_v2;

static int pf_tq_ed_point_init(pf_tq_ed_point_v2 *point) {
    if (point == NULL) return 0;
    memset(point, 0, sizeof(*point));
    point->x = BN_new();
    point->y = BN_new();
    point->z = BN_new();
    point->t = BN_new();
    return point->x != NULL && point->y != NULL &&
        point->z != NULL && point->t != NULL;
}

static void pf_tq_ed_point_free(pf_tq_ed_point_v2 *point) {
    if (point == NULL) return;
    BN_free(point->x);
    BN_free(point->y);
    BN_free(point->z);
    BN_free(point->t);
    memset(point, 0, sizeof(*point));
}

static int pf_tq_ed_point_copy(
    pf_tq_ed_point_v2 *output,
    const pf_tq_ed_point_v2 *input
) {
    return output != NULL && input != NULL &&
        BN_copy(output->x, input->x) != NULL &&
        BN_copy(output->y, input->y) != NULL &&
        BN_copy(output->z, input->z) != NULL &&
        BN_copy(output->t, input->t) != NULL;
}

static int pf_tq_ed_point_identity(pf_tq_ed_point_v2 *point) {
    if (point == NULL) return 0;
    BN_zero(point->x);
    BN_zero(point->t);
    return BN_one(point->y) == 1 && BN_one(point->z) == 1;
}

static int pf_tq_ed_point_add(
    pf_tq_ed_point_v2 *output,
    const pf_tq_ed_point_v2 *left,
    const pf_tq_ed_point_v2 *right,
    const BIGNUM *prime,
    const BIGNUM *curve_d,
    BN_CTX *context
) {
    BIGNUM *a;
    BIGNUM *b;
    BIGNUM *c;
    BIGNUM *d;
    BIGNUM *e;
    BIGNUM *f;
    BIGNUM *g;
    BIGNUM *h;
    BIGNUM *temporary_left;
    BIGNUM *temporary_right;
    int status = 0;
    if (output == NULL || left == NULL || right == NULL || prime == NULL ||
            curve_d == NULL || context == NULL) return 0;
    BN_CTX_start(context);
    a = BN_CTX_get(context);
    b = BN_CTX_get(context);
    c = BN_CTX_get(context);
    d = BN_CTX_get(context);
    e = BN_CTX_get(context);
    f = BN_CTX_get(context);
    g = BN_CTX_get(context);
    h = BN_CTX_get(context);
    temporary_left = BN_CTX_get(context);
    temporary_right = BN_CTX_get(context);
    if (temporary_right == NULL) goto cleanup;
    if (BN_mod_sub(temporary_left, left->y, left->x, prime, context) != 1 ||
            BN_mod_sub(temporary_right, right->y, right->x,
                prime, context) != 1 ||
            BN_mod_mul(a, temporary_left, temporary_right,
                prime, context) != 1 ||
            BN_mod_add(temporary_left, left->y, left->x,
                prime, context) != 1 ||
            BN_mod_add(temporary_right, right->y, right->x,
                prime, context) != 1 ||
            BN_mod_mul(b, temporary_left, temporary_right,
                prime, context) != 1 ||
            BN_mod_mul(temporary_left, left->t, right->t,
                prime, context) != 1 ||
            BN_mod_mul(temporary_right, curve_d, temporary_left,
                prime, context) != 1 ||
            BN_mod_add(c, temporary_right, temporary_right,
                prime, context) != 1 ||
            BN_mod_mul(temporary_left, left->z, right->z,
                prime, context) != 1 ||
            BN_mod_add(d, temporary_left, temporary_left,
                prime, context) != 1 ||
            BN_mod_sub(e, b, a, prime, context) != 1 ||
            BN_mod_sub(f, d, c, prime, context) != 1 ||
            BN_mod_add(g, d, c, prime, context) != 1 ||
            BN_mod_add(h, b, a, prime, context) != 1 ||
            BN_mod_mul(output->x, e, f, prime, context) != 1 ||
            BN_mod_mul(output->y, g, h, prime, context) != 1 ||
            BN_mod_mul(output->z, f, g, prime, context) != 1 ||
            BN_mod_mul(output->t, e, h, prime, context) != 1) goto cleanup;
    status = 1;
cleanup:
    BN_CTX_end(context);
    return status;
}

static int pf_tq_ed_point_equal(
    const pf_tq_ed_point_v2 *left,
    const pf_tq_ed_point_v2 *right,
    const BIGNUM *prime,
    BN_CTX *context
) {
    BIGNUM *left_value;
    BIGNUM *right_value;
    int equal = 0;
    if (left == NULL || right == NULL || prime == NULL || context == NULL) {
        return 0;
    }
    BN_CTX_start(context);
    left_value = BN_CTX_get(context);
    right_value = BN_CTX_get(context);
    if (right_value == NULL ||
            BN_mod_mul(left_value, left->x, right->z,
                prime, context) != 1 ||
            BN_mod_mul(right_value, right->x, left->z,
                prime, context) != 1 ||
            BN_cmp(left_value, right_value) != 0 ||
            BN_mod_mul(left_value, left->y, right->z,
                prime, context) != 1 ||
            BN_mod_mul(right_value, right->y, left->z,
                prime, context) != 1) goto cleanup;
    equal = BN_cmp(left_value, right_value) == 0;
cleanup:
    BN_CTX_end(context);
    return equal;
}

static int pf_tq_ed_scalar_multiply(
    pf_tq_ed_point_v2 *output,
    const BIGNUM *scalar,
    const pf_tq_ed_point_v2 *point,
    const BIGNUM *prime,
    const BIGNUM *curve_d,
    BN_CTX *context
) {
    pf_tq_ed_point_v2 result;
    pf_tq_ed_point_v2 addend;
    pf_tq_ed_point_v2 temporary;
    int bit;
    int status = 0;
    memset(&result, 0, sizeof(result));
    memset(&addend, 0, sizeof(addend));
    memset(&temporary, 0, sizeof(temporary));
    if (!pf_tq_ed_point_init(&result) || !pf_tq_ed_point_init(&addend) ||
            !pf_tq_ed_point_init(&temporary) ||
            !pf_tq_ed_point_identity(&result) ||
            !pf_tq_ed_point_copy(&addend, point)) goto cleanup;
    for (bit = 0; bit < BN_num_bits(scalar); ++bit) {
        if (BN_is_bit_set(scalar, bit)) {
            if (!pf_tq_ed_point_add(&temporary, &result, &addend,
                    prime, curve_d, context) ||
                    !pf_tq_ed_point_copy(&result, &temporary)) goto cleanup;
        }
        if (!pf_tq_ed_point_add(&temporary, &addend, &addend,
                prime, curve_d, context) ||
                !pf_tq_ed_point_copy(&addend, &temporary)) goto cleanup;
    }
    if (!pf_tq_ed_point_copy(output, &result)) goto cleanup;
    status = 1;
cleanup:
    pf_tq_ed_point_free(&temporary);
    pf_tq_ed_point_free(&addend);
    pf_tq_ed_point_free(&result);
    return status;
}

static int pf_tq_authority_prime_subgroup_key(
    const unsigned char encoded[32]
) {
    static const char curve_d_decimal[] =
        "37095705934669439343138083508754565189542113879843219016388785533085940283555";
    static const char sqrt_m1_decimal[] =
        "19681161376707505956807079304988542015446066515923890162744021073123829784752";
    static const char subgroup_order_decimal[] =
        "7237005577332262213973186563042994240857116359379907606001950938285454250989";
    unsigned char y_bytes[32];
    unsigned sign;
    BN_CTX *context = NULL;
    BIGNUM *prime = NULL;
    BIGNUM *curve_d = NULL;
    BIGNUM *sqrt_m1 = NULL;
    BIGNUM *subgroup_order = NULL;
    BIGNUM *eight = NULL;
    BIGNUM *one = NULL;
    BIGNUM *y = NULL;
    BIGNUM *y_squared = NULL;
    BIGNUM *numerator = NULL;
    BIGNUM *denominator = NULL;
    BIGNUM *inverse = NULL;
    BIGNUM *x_squared = NULL;
    BIGNUM *x = NULL;
    BIGNUM *exponent = NULL;
    BIGNUM *check = NULL;
    BIGNUM *temporary = NULL;
    pf_tq_ed_point_v2 point;
    pf_tq_ed_point_v2 identity;
    pf_tq_ed_point_v2 multiple;
    int status = 0;
    memset(&point, 0, sizeof(point));
    memset(&identity, 0, sizeof(identity));
    memset(&multiple, 0, sizeof(multiple));
    memcpy(y_bytes, encoded, sizeof(y_bytes));
    sign = (unsigned)(y_bytes[31] >> 7U);
    y_bytes[31] &= 0x7fU;
    context = BN_CTX_new();
    prime = BN_new();
    eight = BN_new();
    one = BN_new();
    y = BN_lebin2bn(y_bytes, sizeof(y_bytes), NULL);
    y_squared = BN_new();
    numerator = BN_new();
    denominator = BN_new();
    inverse = BN_new();
    x_squared = BN_new();
    x = BN_new();
    exponent = BN_new();
    check = BN_new();
    temporary = BN_new();
    if (context == NULL || prime == NULL || eight == NULL || one == NULL ||
            y == NULL || y_squared == NULL || numerator == NULL ||
            denominator == NULL || inverse == NULL || x_squared == NULL ||
            x == NULL || exponent == NULL || check == NULL || temporary == NULL ||
            BN_dec2bn(&curve_d, curve_d_decimal) == 0 ||
            BN_dec2bn(&sqrt_m1, sqrt_m1_decimal) == 0 ||
            BN_dec2bn(&subgroup_order, subgroup_order_decimal) == 0 ||
            !pf_tq_ed_point_init(&point) ||
            !pf_tq_ed_point_init(&identity) ||
            !pf_tq_ed_point_init(&multiple)) goto cleanup;
    if (BN_one(prime) != 1 || BN_lshift(prime, prime, 255) != 1 ||
            BN_sub_word(prime, 19U) != 1 || BN_one(one) != 1 ||
            BN_set_word(eight, 8U) != 1 || BN_cmp(y, prime) >= 0 ||
            BN_mod_sqr(y_squared, y, prime, context) != 1 ||
            BN_mod_sub(numerator, y_squared, one, prime, context) != 1 ||
            BN_mod_mul(denominator, curve_d, y_squared,
                prime, context) != 1 ||
            BN_mod_add(denominator, denominator, one,
                prime, context) != 1 || BN_is_zero(denominator) ||
            BN_mod_inverse(inverse, denominator, prime, context) == NULL ||
            BN_mod_mul(x_squared, numerator, inverse,
                prime, context) != 1 ||
            BN_copy(exponent, prime) == NULL ||
            BN_add_word(exponent, 3U) != 1 ||
            BN_rshift(exponent, exponent, 3) != 1 ||
            BN_mod_exp(x, x_squared, exponent, prime, context) != 1 ||
            BN_mod_sqr(check, x, prime, context) != 1) goto cleanup;
    if (BN_cmp(check, x_squared) != 0) {
        if (BN_mod_mul(x, x, sqrt_m1, prime, context) != 1 ||
                BN_mod_sqr(check, x, prime, context) != 1) goto cleanup;
    }
    if (BN_cmp(check, x_squared) != 0 || (BN_is_zero(x) && sign == 1U)) {
        goto cleanup;
    }
    if ((unsigned)BN_is_odd(x) != sign) {
        if (BN_sub(temporary, prime, x) != 1 ||
                BN_copy(x, temporary) == NULL) goto cleanup;
    }
    if (BN_copy(point.x, x) == NULL || BN_copy(point.y, y) == NULL ||
            BN_one(point.z) != 1 ||
            BN_mod_mul(point.t, x, y, prime, context) != 1 ||
            !pf_tq_ed_point_identity(&identity) ||
            pf_tq_ed_point_equal(&point, &identity, prime, context) ||
            !pf_tq_ed_scalar_multiply(&multiple, eight, &point,
                prime, curve_d, context) ||
            pf_tq_ed_point_equal(&multiple, &identity, prime, context) ||
            !pf_tq_ed_scalar_multiply(&multiple, subgroup_order, &point,
                prime, curve_d, context) ||
            !pf_tq_ed_point_equal(&multiple, &identity, prime, context)) {
        goto cleanup;
    }
    status = 1;
cleanup:
    pf_tq_ed_point_free(&multiple);
    pf_tq_ed_point_free(&identity);
    pf_tq_ed_point_free(&point);
    BN_free(temporary);
    BN_free(check);
    BN_free(exponent);
    BN_free(x);
    BN_free(x_squared);
    BN_free(inverse);
    BN_free(denominator);
    BN_free(numerator);
    BN_free(y_squared);
    BN_free(y);
    BN_free(one);
    BN_free(eight);
    BN_free(subgroup_order);
    BN_free(sqrt_m1);
    BN_free(curve_d);
    BN_free(prime);
    BN_CTX_free(context);
    return status;
}

static int pf_tq_authority_role(const char *value, unsigned *order, uint32_t *bit) {
    if (strcmp(value, "architecture") == 0) {
        *order = 0U;
        *bit = PF_TQ_ROLE_ARCHITECTURE;
    } else if (strcmp(value, "quality") == 0) {
        *order = 1U;
        *bit = PF_TQ_ROLE_QUALITY;
    } else if (strcmp(value, "security") == 0) {
        *order = 2U;
        *bit = PF_TQ_ROLE_SECURITY;
    } else if (strcmp(value, "release") == 0) {
        *order = 3U;
        *bit = PF_TQ_ROLE_RELEASE;
    } else {
        return 0;
    }
    return 1;
}

static int pf_tq_authority_parse_roles(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    uint32_t *roles,
    char *error,
    size_t error_size
) {
    size_t index;
    unsigned previous_order = 0U;
    uint32_t result = 0U;
    if (node == NULL || roles == NULL || node->type != PF_TQ_JCS_ARRAY ||
            node->child_count == 0U || node->child_count > 4U) {
        return pf_tq_authority_error(error, error_size,
            "authority roles must be a nonempty bounded array");
    }
    for (index = 0U; index < node->child_count; ++index) {
        const pf_tq_jcs_node_v2 *entry =
            pf_tq_jcs_array_at_v2(document, node, index);
        char role[16];
        unsigned order = 0U;
        uint32_t bit = 0U;
        if (pf_tq_jcs_copy_string_v2(document, entry, role, sizeof(role),
                error, error_size) != 0 ||
                !pf_tq_authority_role(role, &order, &bit) ||
                (index > 0U && order <= previous_order) ||
                (result & bit) != 0U) {
            return pf_tq_authority_error(error, error_size,
                "authority roles order/value rejected");
        }
        previous_order = order;
        result |= bit;
    }
    *roles = result;
    return 0;
}

static int pf_tq_authority_parse_rule(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_authority_rule_v2 *rule,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "minimumDistinctSigners", "requiredRoles"
    };
    const pf_tq_jcs_node_v2 *minimum;
    if (node == NULL || rule == NULL || node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_authority_error(error, error_size,
            "authority rule must be a closed object");
    }
    minimum = pf_tq_authority_field(document, node,
        "minimumDistinctSigners");
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 2U,
            error, error_size) != 0 || minimum == NULL ||
            minimum->type != PF_TQ_JCS_UINT || minimum->uint_value == 0U ||
            minimum->uint_value > UINT32_MAX ||
            pf_tq_authority_parse_roles(document,
                pf_tq_authority_field(document, node, "requiredRoles"),
                &rule->required_roles, error, error_size) != 0) {
        return pf_tq_authority_error(error, error_size,
            "authority rule fields rejected");
    }
    rule->minimum_distinct_signers = (uint32_t)minimum->uint_value;
    return 0;
}

static int pf_tq_authority_parse_principals(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_authority_policy_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "keyId", "principalId", "publicKey", "roles"
    };
    size_t index;
    size_t other;
    if (node == NULL || node->type != PF_TQ_JCS_ARRAY ||
            node->child_count == 0U ||
            node->child_count > PF_TQ_AUTHORITY_POLICY_V2_MAX_PRINCIPALS) {
        return pf_tq_authority_error(error, error_size,
            "authority principals count must be 1..256");
    }
    result->principals = calloc(node->child_count,
        sizeof(*result->principals));
    if (result->principals == NULL) {
        return pf_tq_authority_error(error, error_size,
            "authority principal allocation failed");
    }
    result->principal_count = node->child_count;
    for (index = 0U; index < node->child_count; ++index) {
        const pf_tq_jcs_node_v2 *entry =
            pf_tq_jcs_array_at_v2(document, node, index);
        pf_tq_authority_principal_v2 *principal =
            &result->principals[index];
        if (entry == NULL || entry->type != PF_TQ_JCS_OBJECT ||
                pf_tq_jcs_object_exact_v2(document, entry, fields, 4U,
                    error, error_size) != 0 ||
                pf_tq_authority_copy_string(document, entry, "principalId",
                    principal->principal_id, sizeof(principal->principal_id),
                    error, error_size) != 0 ||
                pf_tq_authority_copy_string(document, entry, "keyId",
                    principal->key_id, sizeof(principal->key_id),
                    error, error_size) != 0 ||
                !pf_tq_wire_safe_id_v2(principal->principal_id) ||
                !pf_tq_wire_safe_id_v2(principal->key_id) ||
                (index > 0U && strcmp(result->principals[index - 1U].key_id,
                    principal->key_id) >= 0) ||
                pf_tq_authority_hex32(document,
                    pf_tq_authority_field(document, entry, "publicKey"),
                    principal->public_key, error, error_size) != 0 ||
                pf_tq_authority_parse_roles(document,
                    pf_tq_authority_field(document, entry, "roles"),
                    &principal->roles, error, error_size) != 0) {
            return pf_tq_authority_error(error, error_size,
                "authority principal fields/order rejected");
        }
        for (other = 0U; other < index; ++other) {
            if (memcmp(result->principals[other].public_key,
                    principal->public_key, 32U) == 0) {
                return pf_tq_authority_error(error, error_size,
                    "authority principal public keys must be unique");
            }
        }
    }
    return 0;
}

static int pf_tq_authority_parse_task_rules(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_authority_policy_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {"rule", "taskId"};
    static const char *const task_ids[PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES] = {
        "TASK-D0-01", "TASK-D0-02", "TASK-D0-03",
        "TASK-D0-04", "TASK-D0-05", "TASK-D0-06"
    };
    size_t index;
    if (node == NULL || node->type != PF_TQ_JCS_ARRAY ||
            node->child_count != PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES) {
        return pf_tq_authority_error(error, error_size,
            "authority taskRules must contain exact D0-01..06");
    }
    result->task_rule_count = node->child_count;
    for (index = 0U; index < node->child_count; ++index) {
        const pf_tq_jcs_node_v2 *entry =
            pf_tq_jcs_array_at_v2(document, node, index);
        pf_tq_authority_task_rule_v2 *task_rule =
            &result->task_rules[index];
        if (entry == NULL || entry->type != PF_TQ_JCS_OBJECT ||
                pf_tq_jcs_object_exact_v2(document, entry, fields, 2U,
                    error, error_size) != 0 ||
                pf_tq_authority_copy_string(document, entry, "taskId",
                    task_rule->task_id, sizeof(task_rule->task_id),
                    error, error_size) != 0 ||
                strcmp(task_rule->task_id, task_ids[index]) != 0 ||
                pf_tq_authority_parse_rule(document,
                    pf_tq_authority_field(document, entry, "rule"),
                    &task_rule->rule, error, error_size) != 0) {
            return pf_tq_authority_error(error, error_size,
                "authority taskRules shape/order rejected");
        }
    }
    return 0;
}

static int pf_tq_authority_parse_verifier(
    const pf_tq_jcs_document_v2 *document,
    const pf_tq_jcs_node_v2 *node,
    pf_tq_authority_verifier_v2 *verifier,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "executableDigest", "id", "receiptKeyId", "receiptPublicKey"
    };
    if (node == NULL || verifier == NULL || node->type != PF_TQ_JCS_OBJECT) {
        return pf_tq_authority_error(error, error_size,
            "authority verifier must be a closed object");
    }
    memset(verifier, 0, sizeof(*verifier));
    if (pf_tq_jcs_object_exact_v2(document, node, fields, 4U,
            error, error_size) != 0 ||
            pf_tq_authority_copy_string(document, node, "id", verifier->id,
                sizeof(verifier->id), error, error_size) != 0 ||
            pf_tq_authority_copy_string(document, node, "receiptKeyId",
                verifier->receipt_key_id, sizeof(verifier->receipt_key_id),
                error, error_size) != 0 ||
            !pf_tq_wire_safe_id_v2(verifier->id) ||
            !pf_tq_wire_safe_id_v2(verifier->receipt_key_id) ||
            pf_tq_wire_parse_digest_v2(document,
                pf_tq_authority_field(document, node, "executableDigest"),
                verifier->executable_digest, error, error_size) != 0 ||
            pf_tq_authority_hex32(document,
                pf_tq_authority_field(document, node, "receiptPublicKey"),
                verifier->receipt_public_key, error, error_size) != 0) {
        return pf_tq_authority_error(error, error_size,
            "authority verifier fields rejected");
    }
    return 0;
}

static int pf_tq_authority_rule_satisfiable(
    const pf_tq_authority_policy_v2 *policy,
    const pf_tq_authority_rule_v2 *rule
) {
    size_t distinct = 0U;
    size_t index;
    uint32_t covered = 0U;
    for (index = 0U; index < policy->principal_count; ++index) {
        size_t other;
        int seen = 0;
        covered |= policy->principals[index].roles;
        for (other = 0U; other < index; ++other) {
            if (strcmp(policy->principals[other].principal_id,
                    policy->principals[index].principal_id) == 0) {
                seen = 1;
                break;
            }
        }
        if (!seen) ++distinct;
    }
    return rule->minimum_distinct_signers <= distinct &&
        (covered & rule->required_roles) == rule->required_roles;
}

static int pf_tq_authority_rule_minimum(
    const pf_tq_authority_policy_v2 *policy,
    const pf_tq_authority_rule_v2 *rule,
    uint32_t required_roles,
    uint32_t minimum
) {
    return (rule->required_roles & required_roles) == required_roles &&
        rule->minimum_distinct_signers >= minimum &&
        pf_tq_authority_rule_satisfiable(policy, rule);
}

static int pf_tq_authority_semantics(
    const pf_tq_authority_policy_v2 *policy,
    char *error,
    size_t error_size
) {
    static const uint32_t task_roles[PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES] = {
        PF_TQ_ROLE_ARCHITECTURE | PF_TQ_ROLE_QUALITY,
        PF_TQ_ROLE_ARCHITECTURE | PF_TQ_ROLE_QUALITY,
        PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY,
        PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY | PF_TQ_ROLE_RELEASE,
        PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY,
        PF_TQ_ROLE_ARCHITECTURE | PF_TQ_ROLE_QUALITY
    };
    static const uint32_t task_minimum[PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES] = {
        2U, 2U, 2U, 3U, 2U, 2U
    };
    size_t index;
    for (index = 0U; index < PF_TQ_AUTHORITY_POLICY_V2_TASK_RULES; ++index) {
        if (!pf_tq_authority_rule_minimum(policy,
                &policy->task_rules[index].rule,
                task_roles[index], task_minimum[index])) {
            return pf_tq_authority_error(error, error_size,
                "authority task rule weak or unsatisfiable");
        }
    }
    if (!pf_tq_authority_rule_minimum(policy,
            &policy->required_test_set_rule,
            PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY, 2U) ||
            !pf_tq_authority_rule_minimum(policy,
                &policy->formal_catalog_rule,
                PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY, 2U) ||
            !pf_tq_authority_rule_minimum(policy,
                &policy->bootstrap_set_rule,
                PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY | PF_TQ_ROLE_RELEASE,
                3U) ||
            !pf_tq_authority_rule_minimum(policy,
                &policy->session_containment_rule,
                PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY, 2U) ||
            !pf_tq_authority_rule_minimum(policy,
                &policy->freshness_authority_rule,
                PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_RELEASE, 2U) ||
            !pf_tq_authority_rule_minimum(policy,
                &policy->private_scan_rule,
                PF_TQ_ROLE_QUALITY | PF_TQ_ROLE_SECURITY, 2U) ||
            !pf_tq_authority_rule_minimum(policy,
                &policy->revocation_snapshot_rule,
                PF_TQ_ROLE_SECURITY | PF_TQ_ROLE_RELEASE, 2U)) {
        return pf_tq_authority_error(error, error_size,
            "authority named rule weak or unsatisfiable");
    }
    return 0;
}

static int pf_tq_authority_expectation_validate(
    const pf_tq_authority_policy_expectation_v2 *expected,
    char *error,
    size_t error_size
) {
    if (expected == NULL ||
            !pf_tq_authority_fixed_string(expected->claimed_ref.schema,
                sizeof(expected->claimed_ref.schema)) ||
            !pf_tq_authority_fixed_string(expected->claimed_ref.id,
                sizeof(expected->claimed_ref.id)) ||
            !pf_tq_authority_fixed_string(expected->claimed_ref.version,
                sizeof(expected->claimed_ref.version)) ||
            strcmp(expected->claimed_ref.schema,
                PF_TQ_AUTHORITY_POLICY_V2_SCHEMA) != 0 ||
            !pf_tq_wire_profile_id_v2(expected->claimed_ref.id) ||
            !pf_tq_wire_semver_v2(expected->claimed_ref.version)) {
        return pf_tq_authority_error(error, error_size,
            "authority policy claimed ContentRef rejected");
    }
    return 0;
}

int pf_tq_authority_policy_parse_v2(
    const unsigned char *bytes,
    size_t size,
    const pf_tq_authority_policy_expectation_v2 *expected,
    pf_tq_authority_policy_v2 *result,
    char *error,
    size_t error_size
) {
    static const char *const fields[] = {
        "authorityStoreService", "bootstrapSetRule", "formalCatalogRule",
        "freshnessAuthorityRule", "id", "principals", "privateScanPolicy",
        "privateScanRule", "requiredTestSetRule", "revocationSnapshotRule",
        "schema", "sessionContainmentRule", "taskRules", "verifier", "version"
    };
    pf_tq_jcs_document_v2 document;
    const pf_tq_jcs_node_v2 *root = NULL;
    pf_tq_wire_content_ref_v2 actual_ref;
    size_t index;
    int document_initialized = 0;
    int status = -1;
    pf_tq_authority_clear_error(error, error_size);
    if (bytes == NULL || size == 0U ||
            size > PF_TQ_AUTHORITY_POLICY_V2_MAX_BYTES ||
            expected == NULL || result == NULL) {
        return pf_tq_authority_error(error, error_size,
            "authority policy input/expectation/result rejected");
    }
    memset(result, 0, sizeof(*result));
    memset(&actual_ref, 0, sizeof(actual_ref));
    if (pf_tq_authority_expectation_validate(expected,
            error, error_size) != 0) return -1;
    if (pf_tq_jcs_parse_v2(bytes, size, &document,
            error, error_size) != 0) return -1;
    document_initialized = 1;
    root = pf_tq_jcs_root_v2(&document);
    if (root == NULL || root->type != PF_TQ_JCS_OBJECT) {
        (void)pf_tq_authority_error(error, error_size,
            "authority policy root must be a closed object");
        goto cleanup;
    }
    if (pf_tq_jcs_object_exact_v2(&document, root, fields, 15U,
            error, error_size) != 0 ||
            pf_tq_authority_string_exact(&document, root, "schema",
                PF_TQ_AUTHORITY_POLICY_V2_SCHEMA,
                error, error_size) != 0 ||
            pf_tq_authority_copy_string(&document, root, "id", result->id,
                sizeof(result->id), error, error_size) != 0 ||
            pf_tq_authority_copy_string(&document, root, "version",
                result->version, sizeof(result->version),
                error, error_size) != 0 ||
            !pf_tq_wire_profile_id_v2(result->id) ||
            !pf_tq_wire_semver_v2(result->version) ||
            pf_tq_authority_digest(bytes, size, result->digest,
                error, error_size) != 0) {
        (void)pf_tq_authority_error(error, error_size,
            "authority policy root identity rejected");
        goto cleanup;
    }
    (void)snprintf(actual_ref.schema, sizeof(actual_ref.schema),
        "%s", PF_TQ_AUTHORITY_POLICY_V2_SCHEMA);
    (void)snprintf(actual_ref.id, sizeof(actual_ref.id), "%s", result->id);
    (void)snprintf(actual_ref.version, sizeof(actual_ref.version),
        "%s", result->version);
    memcpy(actual_ref.digest, result->digest, 32U);
    if (!pf_tq_wire_content_ref_equal_v2(
            &actual_ref, &expected->claimed_ref)) {
        (void)pf_tq_authority_error(error, error_size,
            "authority policy bytes do not equal expected activated ContentRef");
        goto cleanup;
    }
    if (pf_tq_authority_parse_principals(&document,
            pf_tq_authority_field(&document, root, "principals"), result,
            error, error_size) != 0 ||
            pf_tq_authority_parse_task_rules(&document,
                pf_tq_authority_field(&document, root, "taskRules"), result,
                error, error_size) != 0 ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root, "requiredTestSetRule"),
                &result->required_test_set_rule, error, error_size) != 0 ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root, "formalCatalogRule"),
                &result->formal_catalog_rule, error, error_size) != 0 ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root, "bootstrapSetRule"),
                &result->bootstrap_set_rule, error, error_size) != 0 ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root,
                    "sessionContainmentRule"),
                &result->session_containment_rule, error, error_size) != 0 ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root,
                    "freshnessAuthorityRule"),
                &result->freshness_authority_rule, error, error_size) != 0 ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root, "privateScanRule"),
                &result->private_scan_rule, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(&document,
                pf_tq_authority_field(&document, root, "privateScanPolicy"),
                &result->private_scan_policy, error, error_size) != 0 ||
            !pf_tq_wire_profile_id_v2(result->private_scan_policy.id) ||
            pf_tq_authority_parse_rule(&document,
                pf_tq_authority_field(&document, root,
                    "revocationSnapshotRule"),
                &result->revocation_snapshot_rule, error, error_size) != 0 ||
            pf_tq_wire_parse_content_ref_v2(&document,
                pf_tq_authority_field(&document, root,
                    "authorityStoreService"),
                &result->authority_store_service, error, error_size) != 0 ||
            strcmp(result->authority_store_service.schema,
                PF_TQ_AUTHORITY_POLICY_STORE_SCHEMA_V2) != 0 ||
            !pf_tq_wire_profile_id_v2(result->authority_store_service.id) ||
            pf_tq_authority_parse_verifier(&document,
                pf_tq_authority_field(&document, root, "verifier"),
                &result->verifier, error, error_size) != 0 ||
            pf_tq_authority_semantics(result, error, error_size) != 0) {
        (void)pf_tq_authority_error(error, error_size,
            "authority policy complete typed projection rejected");
        goto cleanup;
    }
    for (index = 0U; index < result->principal_count; ++index) {
        if (strcmp(result->principals[index].key_id,
                result->verifier.receipt_key_id) == 0 ||
                memcmp(result->principals[index].public_key,
                    result->verifier.receipt_public_key, 32U) == 0) {
            (void)pf_tq_authority_error(error, error_size,
                "authority verifier key collides with principal registry");
            goto cleanup;
        }
    }
    /* Curve work is deliberately last, after the complete bounded closed
     * shape, expected activated ref, rule and collision checks. */
    for (index = 0U; index < result->principal_count; ++index) {
        if (!pf_tq_authority_prime_subgroup_key(
                result->principals[index].public_key)) {
            (void)pf_tq_authority_error(error, error_size,
                "authority principal key is not canonical prime-subgroup Ed25519");
            goto cleanup;
        }
    }
    if (!pf_tq_authority_prime_subgroup_key(
            result->verifier.receipt_public_key)) {
        (void)pf_tq_authority_error(error, error_size,
            "authority verifier key is not canonical prime-subgroup Ed25519");
        goto cleanup;
    }
    result->canonical_bytes = malloc(size);
    if (result->canonical_bytes == NULL) {
        (void)pf_tq_authority_error(error, error_size,
            "authority policy canonical-byte allocation failed");
        goto cleanup;
    }
    memcpy(result->canonical_bytes, bytes, size);
    result->canonical_size = size;
    status = 0;
cleanup:
    if (document_initialized) pf_tq_jcs_free_v2(&document);
    if (status != 0) pf_tq_authority_policy_free_v2(result);
    return status;
}

int pf_tq_authority_policy_handoff_registry_v2(
    const pf_tq_authority_policy_v2 *policy,
    pf_tq_handoff_principal_v2 *principals,
    size_t capacity,
    size_t *written,
    char *error,
    size_t error_size
) {
    size_t index;
    pf_tq_authority_clear_error(error, error_size);
    if (written != NULL) *written = 0U;
    if (policy == NULL || policy->canonical_bytes == NULL ||
            policy->canonical_size == 0U || policy->principals == NULL ||
            policy->principal_count == 0U ||
            policy->principal_count > PF_TQ_AUTHORITY_POLICY_V2_MAX_PRINCIPALS ||
            principals == NULL || capacity < policy->principal_count ||
            written == NULL) {
        return pf_tq_authority_error(error, error_size,
            "authority handoff-registry projection arguments rejected");
    }
    for (index = 0U; index < policy->principal_count; ++index) {
        principals[index].principal_id = policy->principals[index].principal_id;
        principals[index].key_id = policy->principals[index].key_id;
        memcpy(principals[index].public_key,
            policy->principals[index].public_key, 32U);
        principals[index].roles = policy->principals[index].roles;
        principals[index].current = 1;
    }
    *written = policy->principal_count;
    return 0;
}

int pf_tq_authority_policy_bind_handoff_v2(
    const pf_tq_authority_policy_v2 *policy,
    pf_tq_handoff_expectation_v2 *handoff,
    pf_tq_handoff_principal_v2 *principal_storage,
    size_t principal_capacity,
    char *error,
    size_t error_size
) {
    pf_tq_wire_content_ref_v2 policy_ref;
    size_t principal_count = 0U;
    pf_tq_authority_clear_error(error, error_size);
    if (policy == NULL || handoff == NULL ||
            policy->canonical_bytes == NULL || policy->canonical_size == 0U ||
            !pf_tq_authority_fixed_string(policy->id, sizeof(policy->id)) ||
            !pf_tq_authority_fixed_string(policy->version,
                sizeof(policy->version)) ||
            !pf_tq_wire_profile_id_v2(policy->id) ||
            !pf_tq_wire_semver_v2(policy->version) ||
            !pf_tq_authority_fixed_string(handoff->authority_policy.schema,
                sizeof(handoff->authority_policy.schema)) ||
            !pf_tq_authority_fixed_string(handoff->authority_policy.id,
                sizeof(handoff->authority_policy.id)) ||
            !pf_tq_authority_fixed_string(handoff->authority_policy.version,
                sizeof(handoff->authority_policy.version)) ||
            strcmp(handoff->authority_policy.schema,
                PF_TQ_AUTHORITY_POLICY_V2_SCHEMA) != 0 ||
            !pf_tq_wire_profile_id_v2(handoff->authority_policy.id) ||
            !pf_tq_wire_semver_v2(handoff->authority_policy.version)) {
        return pf_tq_authority_error(error, error_size,
            "authority policy/handoff bind arguments rejected");
    }
    memset(&policy_ref, 0, sizeof(policy_ref));
    (void)snprintf(policy_ref.schema, sizeof(policy_ref.schema),
        "%s", PF_TQ_AUTHORITY_POLICY_V2_SCHEMA);
    (void)snprintf(policy_ref.id, sizeof(policy_ref.id), "%s", policy->id);
    (void)snprintf(policy_ref.version, sizeof(policy_ref.version),
        "%s", policy->version);
    memcpy(policy_ref.digest, policy->digest, 32U);
    if (!pf_tq_wire_content_ref_equal_v2(
            &policy_ref, &handoff->authority_policy) ||
            pf_tq_authority_policy_handoff_registry_v2(
                policy, principal_storage, principal_capacity,
                &principal_count, error, error_size) != 0) {
        return pf_tq_authority_error(error, error_size,
            "handoff authorityPolicy does not equal activated policy bytes/ref");
    }
    handoff->principals = principal_storage;
    handoff->principal_count = principal_count;
    return 0;
}
