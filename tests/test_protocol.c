#include "PCRProtocol.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    unsigned mode = 42;
    uint32_t out = 0;
    uint32_t sessions[] = {1, 0xFFFFFFFF, 0x01020304};
    for (unsigned n = 0; n < 3; ++n) {
        uint32_t session = sessions[n];
        assert(PCRDecodeRequest(PCREncodeRequest(session), &out) && out == session);
        assert(!PCRDecodeMode(PCREncodeRequest(session), session, &mode));
        for (unsigned i = 0; i <= 4; ++i) {
            uint64_t state = PCREncodeMode(session, i);
            assert(PCRDecodeMode(state, session, &mode) && mode == i);
            assert(!PCRDecodeRequest(state, &out));
            assert(!PCRDecodeMode(state, session ^ 1, &mode));
            for (unsigned bit = 8; bit < 64; ++bit)
                assert(!PCRDecodeMode(state ^ (UINT64_C(1) << bit), session, &mode));
        }
        for (unsigned i = 5; i < 256; ++i)
            assert(!PCRDecodeMode(PCREncodeMode(session, 0) | i, session, &mode));
    }
    assert(!PCRDecodeRequest(PCREncodeRequest(0), &out));
    assert(!PCRDecodeMode(PCREncodeMode(0, 3), 0, &mode));
    for (unsigned i = 0; i <= 4; ++i) {
        assert(!PCRDecodeMode(i, 1, &mode));
        assert(!PCRDecodeMode(UINT64_C(0x5043520100000000) | i, 1, &mode));
    }
    puts("protocol: session freshness, legacy states, corrupt headers, reserved bits PASS");
}
