#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

/*
 * PowerCuff Baldaran Trusted — thermal simulation profiles for RootHide.
 *
 * Design notes:
 *  - Preferences are read through NSUserDefaults (cfprefsd), never by reading
 *    the plist file directly. PreferenceLoader writes through cfprefsd, which
 *    does not guarantee an immediate flush, so a raw file read can be stale.
 *    Going through cfprefsd also avoids hardcoding a jailbreak-dependent path.
 *  - The cached product is held weakly; a strong static reference would retain
 *    a system object and keep a stale instance alive across rebuilds.
 *  - All work runs on one serial queue: notify callbacks, LPM changes and hook
 *    entry points can otherwise race on the same state.
 *  - Only "off" is sent for mode 0. Passing nil to the private selector has no
 *    documented behavior and is avoided.
 */

static NSString *const PCRDomain = @"com.minis.powercuff-baldaran-trusted";
static const char *const PCRSettingsChanged =
    "com.minis.powercuff-baldaran-trusted.settingschanged";
static const char *const PCRThermalsChanged =
    "com.minis.powercuff-baldaran-trusted.thermals";

static os_log_t PCRLog;
static dispatch_queue_t PCRQueue;
static __weak id PCRProduct;
static int PCRStateToken = -1;
static int PCRThermalObsToken = -1;
static int PCRSettingsObsToken = -1;

static NSString *PCRModeName(uint64_t mode) {
    switch (mode) {
        case 1: return @"nominal";
        case 2: return @"light";
        case 3: return @"moderate";
        case 4: return @"heavy";
        default: return @"off";
    }
}

/* Runs in thermalmonitord: push the published state into the system. */
static void PCRApplyThermals(void) {
    if (PCRStateToken < 0) return;

    uint64_t mode = 0;
    if (notify_get_state(PCRStateToken, &mode) != NOTIFY_STATUS_OK) {
        os_log_error(PCRLog, "notify_get_state failed");
        return;
    }

    id product = PCRProduct;
    if (!product) return;

    SEL selector = @selector(putDeviceInThermalSimulationMode:);
    if (![product respondsToSelector:selector]) return;

    NSString *name = PCRModeName(mode);
    ((void (*)(id, SEL, id))objc_msgSend)(product, selector, name);
    os_log_debug(PCRLog, "applied mode=%llu (%{public}@)", mode, name);
}

/* Runs in SpringBoard: resolve preferences into an effective mode. */
static NSInteger PCREffectiveMode(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PCRDomain];

    NSInteger mode = [defaults integerForKey:@"PowerMode"];
    if (mode < 0 || mode > 4) mode = 0;

    if ([defaults boolForKey:@"RequireLowPowerMode"] &&
        ![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
        mode = 0;
    }
    return mode;
}

/* Runs in SpringBoard: publish the effective mode to the daemon. */
static void PCRPublishMode(void) {
    if (PCRStateToken < 0) return;

    NSInteger mode = PCREffectiveMode();
    notify_set_state(PCRStateToken, (uint64_t)mode);
    notify_post(PCRThermalsChanged);
    os_log_debug(PCRLog, "published mode=%ld", (long)mode);
}

%group PCRThermalHooks
%hook CommonProduct
- (id)initProduct:(id)arg1 {
    id product = %orig(arg1);
    if (product) {
        PCRProduct = product;
        dispatch_async(PCRQueue, ^{ PCRApplyThermals(); });
    }
    return product;
}
%end

/* GPProduct is a fallback used by some iOS builds; harmless when absent. */
%hook GPProduct
- (id)initProduct:(id)arg1 {
    id product = %orig(arg1);
    if (product) {
        PCRProduct = product;
        dispatch_async(PCRQueue, ^{ PCRApplyThermals(); });
    }
    return product;
}
%end
%end

%group PCRSpringBoardHooks
%hook SpringBoard
- (void)_batterySaverModeChanged:(NSInteger)arg1 {
    %orig;
    dispatch_async(PCRQueue, ^{ PCRPublishMode(); });
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process = [[NSProcessInfo processInfo] processName];
        BOOL isThermal = [process isEqualToString:@"thermalmonitord"];
        BOOL isSpringBoard = [process isEqualToString:@"SpringBoard"];
        if (!isThermal && !isSpringBoard) return;

        PCRLog = os_log_create("com.minis.powercuff-baldaran-trusted", "tweak");
        PCRQueue = dispatch_queue_create("com.minis.powercuff-baldaran-trusted.queue",
                                         DISPATCH_QUEUE_SERIAL);

        if (notify_register_check(PCRThermalsChanged, &PCRStateToken) != NOTIFY_STATUS_OK) {
            os_log_error(PCRLog, "notify_register_check failed");
            PCRStateToken = -1;
        }

        if (isThermal) {
            notify_register_dispatch(PCRThermalsChanged, &PCRThermalObsToken, PCRQueue,
                                     ^(int token) { (void)token; PCRApplyThermals(); });
            %init(PCRThermalHooks);
        } else {
            notify_register_dispatch(PCRSettingsChanged, &PCRSettingsObsToken, PCRQueue,
                                     ^(int token) { (void)token; PCRPublishMode(); });

            [[NSNotificationCenter defaultCenter]
                addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                            object:nil
                             queue:nil
                        usingBlock:^(NSNotification *note) {
                (void)note;
                dispatch_async(PCRQueue, ^{ PCRPublishMode(); });
            }];

            dispatch_async(PCRQueue, ^{ PCRPublishMode(); });
            %init(PCRSpringBoardHooks);
        }
    }
}
