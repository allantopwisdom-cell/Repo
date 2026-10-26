#include "PCRProtocol.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    unsigned mode = 42;
    for (unsigned i = 0; i <= 4; ++i) {
        assert(PCRDecodeMode(PCREncodeMode(i), &mode) && mode == i);
        assert(!PCRDecodeMode(i, &mode)); // initial/legacy state
    }
    for (uint64_t i = 5; i < 65536; ++i)
        assert(!PCRDecodeMode(PCR_STATE_PREFIX | i, &mode));
    for (unsigned bit = 3; bit < 64; ++bit)
        assert(!PCRDecodeMode(PCREncodeMode(3) ^ (UINT64_C(1) << bit), &mode));
    assert(PCRDecodeMode(PCREncodeMode(99), &mode) && mode == 0);
    puts("protocol: round trips, legacy state, invalid modes and corrupt headers PASS");
    return 0;
}
