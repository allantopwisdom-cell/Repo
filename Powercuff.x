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

static const NSString *const PCRSettingsChanged =
    @"com.minis.powercuff-baldaran-trusted.settingschanged";
static const NSString *const PCRThermalsChanged   =
    @"com.minis.powercuff-baldaran-trusted.thermals";

static id<NSObject> currentTarget;
static int token;

/* Read the user's preference key from the trusted domain. The path is only
   consulted at runtime, so on a RootHide device we must prefix it with the
   actual jailbreak root returned by the Roohide jbroot() API. */
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

    NSArray<NSString *> *modes =
        @[@"off", @"nominal", @"light", @"moderate", @"heavy"];

    if (currentTarget) {
        if (mode == 0) {
            /* Explicit OFF: clear any prior simulation state before forcing
               the canonical off string so the system fully resets. */
            if ([currentTarget respondsToSelector:@selector(
                    putDeviceInThermalSimulationMode:)]) {
                [currentTarget putDeviceInThermalSimulationMode:nil];
                [currentTarget putDeviceInThermalSimulationMode:@"off"];
            }
        } else if (mode < modes.count) {
            NSString *modeStr = modes[mode];
            if ([currentTarget respondsToSelector:@selector(
                    putDeviceInThermalSimulationMode:)]) {
                [currentTarget putDeviceInThermalSimulationMode:modeStr];
            }
        }
    }
}

static void LoadSettings(void) {
    NSString *path = PCPreferencesPath();
    NSDictionary *prefs =
        [NSDictionary dictionaryWithContentsOfFile:path];

    uint64_t mode = [[prefs objectForKey:@"PowerMode"]
                         ?: @0 unsignedLongLongValue];

    if ([[prefs objectForKey:@"RequireLowPowerMode"] boolValue]) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            mode = 0;
        }
    }

    notify_set_state(token, mode);
    notify_post(PCRThermalsChanged);
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
    notify_register_check(PCRThermalsChanged, &token);

    NSString *procName = [[NSProcessInfo processInfo] processName];

    if ([procName isEqualToString:@"thermalmonitord"]) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, (CFNotificationCallback)ApplyThermals,
            PCRThermalsChanged, NULL,
            CFNotificationSuspensionBehaviorCoalesce);
        %init(thermalmonitord);
    } else {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL, (CFNotificationCallback)LoadSettings,
            PCRSettingsChanged, NULL,
            CFNotificationSuspensionBehaviorCoalesce);

        if ([procName isEqualToString:@"SpringBoard"]) {
            LoadSettings();
        }
    }
}
