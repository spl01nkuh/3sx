#ifndef SHA256_H
#define SHA256_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#if CRS_PLATFORM_IOS
#include <CommonCrypto/CommonDigest.h>
#else
#include <psa/crypto.h>
#endif

#define SHA256_HEX_SIZE (64 + 1)
#define SHA256_BYTES_SIZE 32

typedef struct sha256 {
#if CRS_PLATFORM_IOS
    CC_SHA256_CTX operation;
#else
    psa_hash_operation_t operation;
#endif
    bool active;
    bool finished;
} sha256;

bool sha256_init(sha256* sha);
bool sha256_append(sha256* sha, const void* data, size_t n_bytes);
bool sha256_finalize_hex(sha256* sha, char* dst_hex65);
bool sha256_finalize_bytes(sha256* sha, void* dst_bytes32);

#endif
