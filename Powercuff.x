#import <notify.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <roothide.h>

static const char *const PCR_SETTINGS_CHANGED =
    "com.minis.powercuff-baldaran-trusted.settingschanged";
static const char *const PCR_THERMALS_CHANGED =
    "com.minis.powercuff-baldaran-trusted.thermals";

static Class gProductClass;
static id currentTarget;
static int token;

static NSString *PCPreferencesPath(void) {
    NSString *raw = @"/var/mobile/Library/Preferences/com.minis.powercuff-baldaran-trusted.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:raw]) {
        return raw;
    }
    return jbroot(raw);
}

static void ApplyThermals(void) {
    uint64_t mode = 0;
    notify_get_state(token, &mode);
    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];
    if (gProductClass && currentTarget && [currentTarget isKindOfClass:gProductClass]) {
        SEL sel = @selector(putDeviceInThermalSimulationMode:);
        if ([currentTarget respondsToSelector:sel]) {
            if (mode == 0) {
                ((void (*)(id, SEL, id))objc_msgSend)(currentTarget, sel, nil);
                ((void (*)(id, SEL, id))objc_msgSend)(currentTarget, sel, @"off");
            } else if (mode < (uint64_t)modes.count) {
                ((void (*)(id, SEL, id))objc_msgSend)(currentTarget, sel, modes[mode]);
            }
        }
    }
}

static void LoadSettings(void) {
    NSString *path = PCPreferencesPath();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    uint64_t mode = [[prefs objectForKey:@"PowerMode"] ?: @0 unsignedLongLongValue];
    if ([[prefs objectForKey:@"RequireLowPowerMode"] boolValue]) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            mode = 0;
        }
    }
    notify_set_state(token, mode);
    notify_post(PCR_THERMALS_CHANGED);
}

%group thermalmonitord
%hook CommonProduct
- (id)initProduct:(id)arg1 {
    id obj = %orig(arg1);
    if (!gProductClass) gProductClass = objc_getClass("CommonProduct");
    if (gProductClass && obj && [obj isKindOfClass:gProductClass]) {
        currentTarget = obj;
        ApplyThermals();
    }
    return obj;
}
%end

%hook GPProduct
- (id)initProduct:(id)arg1 {
    id obj = %orig(arg1);
    if (!gProductClass) gProductClass = objc_getClass("GPProduct");
    if (gProductClass && obj && [obj isKindOfClass:gProductClass]) {
        currentTarget = obj;
        ApplyThermals();
    }
    return obj;
}
%end
%end

%ctor {
    notify_register_check(PCR_THERMALS_CHANGED, &token);
    NSString *procName = [[NSProcessInfo processInfo] processName];

    if ([procName isEqualToString:@"thermalmonitord"]) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, (CFNotificationCallback)ApplyThermals,
            CFStringCreateWithCString(NULL, PCR_THERMALS_CHANGED, kCFStringEncodingUTF8),
            NULL, CFNotificationSuspensionBehaviorCoalesce);
        %init(thermalmonitord);
    } else {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, (CFNotificationCallback)LoadSettings,
            CFStringCreateWithCString(NULL, PCR_SETTINGS_CHANGED, kCFStringEncodingUTF8),
            NULL, CFNotificationSuspensionBehaviorCoalesce);
        if ([procName isEqualToString:@"SpringBoard"]) {
            LoadSettings();
        }
    }
}
