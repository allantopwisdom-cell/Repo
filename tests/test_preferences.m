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
        NSString *domain = [@"com.powercuff.test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:domain];
        [defaults registerDefaults:@{@"PowerMode": @4, @"RequireLowPowerMode": @YES}];
        @try {
            // Reproduce the old search-list collision without changing global preferences.
            assert([[defaults objectForKey:@"PowerMode"] integerValue] == 4);
            assert(PCRPreferenceSnapshot(defaults, domain)[@"PowerMode"] == nil);
            [defaults setPersistentDomain:@{@"PowerMode": @2} forName:domain];
            NSDictionary *snapshot = PCRPreferenceSnapshot(defaults, domain);
            assert([snapshot[@"PowerMode"] integerValue] == 2);
            assert(snapshot[@"RequireLowPowerMode"] == nil);
            assert(PCRValidatedMode(snapshot[@"PowerMode"], snapshot[@"RequireLowPowerMode"], NO) == 2);
            [defaults setPersistentDomain:@{@"PowerMode": @0, @"RequireLowPowerMode": @YES} forName:domain];
            assert([snapshot[@"PowerMode"] integerValue] == 2); // retained snapshot stays coherent
            assert([PCRPreferenceSnapshot(defaults, domain)[@"PowerMode"] integerValue] == 0);
        } @finally {
            [defaults removePersistentDomainForName:domain];
        }
        puts("Foundation preferences: exact persistent domain excludes fallback keys; coherent snapshot PASS");
        puts("Foundation preferences: types, finite integer bounds, LPM gating PASS");
    }
}
