#ifndef PCR_PROTOCOL_H
#define PCR_PROTOCOL_H
#include <stdint.h>
#include <stdbool.h>
// Format v2: 24-bit header, nonzero 32-bit daemon session, reserved/mode byte.
// A session is freshness coordination, not authentication.
#define PCR_STATE_PREFIX UINT64_C(0x5043020000000000)
static inline uint64_t PCREncodeRequest(uint32_t session) {
    return PCR_STATE_PREFIX | ((uint64_t)session << 8) | UINT64_C(0xA5);
}
static inline bool PCRDecodeRequest(uint64_t state, uint32_t *session) {
    if ((state & UINT64_C(0xFFFFFF00000000FF)) != (PCR_STATE_PREFIX | UINT64_C(0xA5))) return false;
    uint32_t value = (uint32_t)(state >> 8);
    if (!value) return false;
    *session = value;
    return true;
}
static inline uint64_t PCREncodeMode(uint32_t session, unsigned mode) {
    return PCR_STATE_PREFIX | ((uint64_t)session << 8) | (mode <= 4 ? mode : 0);
}
static inline bool PCRDecodeMode(uint64_t state, uint32_t session, unsigned *mode) {
    if (!session || (state & UINT64_C(0xFFFFFFFFFFFFFF00)) !=
        (PCR_STATE_PREFIX | ((uint64_t)session << 8)) || (state & 255) > 4) return false;
    *mode = (unsigned)(state & 255);
    return true;
}
#endif
