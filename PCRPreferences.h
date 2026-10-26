#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
// Read one persistent-domain snapshot. objectForKey: also searches unrelated domains.
static inline NSDictionary *PCRPreferenceSnapshot(NSUserDefaults *defaults, NSString *domain) {
    return [[defaults persistentDomainForName:domain] copy];
}
// Pure preference parsing, shared by the tweak and macOS Foundation regression tests.
static inline NSInteger PCRValidatedMode(id raw, id gate, BOOL lowPower) {
    if (![raw isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)raw) == CFBooleanGetTypeID()) return 0;
    double number = [raw doubleValue];
    if (!(number >= 0 && number <= 4) || number != (double)[raw integerValue]) return 0;
    if (gate) {
        if (![gate isKindOfClass:NSNumber.class]) return 0;
        double flag = [gate doubleValue];
        if (flag != 0 && flag != 1) return 0;
        if (flag == 1 && !lowPower) return 0;
    }
    return [raw integerValue];
}
