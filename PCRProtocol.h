#ifndef PCR_PROTOCOL_H
#define PCR_PROTOCOL_H
#include <stdint.h>
#include <stdbool.h>
// Versioned state: reject initial zero and values written by older publishers.
#define PCR_STATE_PREFIX UINT64_C(0x5043520100000000)
static inline uint64_t PCREncodeMode(unsigned mode) {
    return PCR_STATE_PREFIX | (mode <= 4 ? mode : 0);
}
static inline bool PCRDecodeMode(uint64_t state, unsigned *mode) {
    if ((state & ~UINT64_C(7)) != PCR_STATE_PREFIX || (state & 7) > 4) return false;
    *mode = (unsigned)(state & 7);
    return true;
}
#endif
