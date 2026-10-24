#import <notify.h>
#import <Foundation/Foundation.h>
#import <roothide.h>

/* CommonProduct / GPProduct are internal Apple classes; we only declare the
   single selector we actually call at runtime. */
@interface CommonProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

@interface GPProduct : NSObject
- (void)putDeviceInThermalSimulationMode:(NSString *)mode;
@end

static const char *const PCR_SETTINGS_CHANGED =
    "com.minis.powercuff-baldaran-trusted.settingschanged";
static const char *const PCR_THERMALS_CHANGED =
    "com.minis.powercuff-baldaran-trusted.thermals";

static id currentTarget;
static int token;

static NSString *PCPreferencesPath(void) {
    NSString *raw = @"/var/mobile/Library/Preferences/"
                    @"com.minis.powercuff-baldaran-trusted.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:raw]) {
        return raw;
    }
    return jbroot(raw);
}

static void ApplyThermals(void) {
    uint64_t mode = 0;
    notify_get_state(token, &mode);

    NSArray *modes = @[@"off", @"nominal", @"light", @"moderate", @"heavy"];

    if (currentTarget) {
        if (mode == 0) {
            if ([currentTarget respondsToSelector:@selector(
                    putDeviceInThermalSimulationMode:)]) {
                [currentTarget putDeviceInThermalSimulationMode:nil];
                [currentTarget putDeviceInThermalSimulationMode:@"off"];
            }
        } else if (mode < modes.count) {
            if ([currentTarget respondsToSelector:@selector(
                    putDeviceInThermalSimulationMode:)]) {
                [currentTarget putDeviceInThermalSimulationMode:modes[mode]];
            }
        }
    }
}

static void LoadSettings(void) {
    NSString *path = PCPreferencesPath();
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];

    uint64_t mode = [[prefs objectForKey:@"PowerMode"] ?: @0
                         unsignedLongLongValue];

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
    if (obj && [obj isKindOfClass:[CommonProduct class]]) {
        currentTarget = obj;
        ApplyThermals();
    }
    return obj;
}
%end

%hook GPProduct
- (id)initProduct:(id)arg1 {
    id obj = %orig(arg1);
    if (obj && [obj isKindOfClass:[GPProduct class]]) {
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
            CFSTR(PCR_THERMALS_CHANGED), NULL,
            CFNotificationSuspensionBehaviorCoalesce);
        %init(thermalmonitord);
    } else {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, (CFNotificationCallback)LoadSettings,
            CFSTR(PCR_SETTINGS_CHANGED), NULL,
            CFNotificationSuspensionBehaviorCoalesce);

        if ([procName isEqualToString:@"SpringBoard"]) {
            LoadSettings();
        }
    }
}
