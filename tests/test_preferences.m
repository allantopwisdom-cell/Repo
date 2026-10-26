#import "PCRPreferences.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        for (NSInteger i = 0; i <= 4; ++i) {
            assert(PCRValidatedMode(@(i), nil, NO) == i);
            assert(PCRValidatedMode(@(i), @YES, YES) == i);
            assert(PCRValidatedMode(@(i), @YES, NO) == 0);
        }
        for (id raw in @[@"3", @[], @{}, @YES, @(-1), @5, @2.5, @(NAN), @(INFINITY), NSNull.null])
            assert(PCRValidatedMode(raw, nil, YES) == 0);
        for (id gate in @[@"1", @[], @{}, @2, @(-1), @0.5, @(NAN), NSNull.null])
            assert(PCRValidatedMode(@3, gate, YES) == 0);
        assert(PCRValidatedMode(nil, nil, YES) == 0);
        assert(PCRValidatedMode(@3, @NO, NO) == 3);
        puts("Foundation preferences: types, finite integer bounds, LPM gating PASS");
    }
}
