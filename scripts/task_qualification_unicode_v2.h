#ifndef PROOF_FORGE_TASK_QUALIFICATION_UNICODE_V2_H
#define PROOF_FORGE_TASK_QUALIFICATION_UNICODE_V2_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PF_TQ_UNICODE_V2_ERROR_BYTES 256U

/* Validate exact UTF-8 scalar encoding and require pinned Unicode 17.0.0 NFC.
 * The function never normalizes caller bytes and accepts embedded NUL as a
 * Unicode scalar; schema/path owners must apply their own lexical constraints. */
int pf_tq_unicode_require_nfc_v2(
    const unsigned char *bytes,
    size_t size,
    char *error,
    size_t error_size
);

#ifdef __cplusplus
}
#endif

#endif
