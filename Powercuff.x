#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <time.h>
#include <unistd.h>
#import <os/log.h>

/*
 * PowerCuff Baldaran Trusted — thermal simulation profiles for RootHide.
 *
 *  - Settings are read through NSUserDefaults (cfprefsd). PreferenceLoader
 *    writes through cfprefsd too, and cfprefsd does not flush immediately, so
 *    reading the plist file directly can return stale values.
 *  - The cached product is weak; a strong static would retain a system object
 *    and keep a stale instance alive after the daemon rebuilds it.
 *  - Every entry point is funnelled through one serial queue.
 *  - Redundant work is skipped: the daemon remembers the last mode it pushed to
 *    the system and the publisher remembers the last state it broadcast, so
 *    identical notifications do not re-enter the private thermal API.
 *  - Only "off" is sent for mode 0; passing nil has no documented behavior.
 */

static NSString *const PCRDomain = @"com.minis.powercuff-baldaran-trusted";
static const char *const PCRSettingsChanged =
    "com.minis.powercuff-baldaran-trusted.settingschanged";
static const char *const PCRThermalsChanged =
    "com.minis.powercuff-baldaran-trusted.thermals";

#define PCR_UNSET (-1)

static const char *const PCRLoadedName  = "com.minis.powercuff-baldaran-trusted.loaded";
static const char *const PCRHookName    = "com.minis.powercuff-baldaran-trusted.hook";
static const char *const PCRAppliedName = "com.minis.powercuff-baldaran-trusted.applied";

static os_log_t PCRLog;
static dispatch_queue_t PCRQueue;
static __weak id PCRProduct;
static int PCRStateToken = -1;
static int PCRThermalObsToken = -1;
static int PCRSettingsObsToken = -1;
static id PCRLPMObserver;
static int PCRLastApplied = PCR_UNSET;    /* daemon side */
static int PCRLastPublished = PCR_UNSET;  /* publisher side */
static int PCRLoadedToken = -1;
static int PCRHookToken = -1;
static int PCRAppliedToken = -1;

/* notify state is kernel-side: it works even where the sandbox blocks file or
   preference writes, which is why diagnostics go through it. */
static void PCRSetState(int token, uint64_t value) {
    if (token >= 0) notify_set_state(token, value);
}

/* Diagnostics: written through cfprefsd so RootHide redirects them the same
   way as the panel's own keys. Read back with `defaults read`. */
static void PCRNote(NSString *key, NSInteger value) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PCRDomain];
    [defaults setInteger:value forKey:key];
}

/* Environment probes: recorded once per process so a single `defaults read`
   tells us whether the library loaded and which thermal API this OS exposes. */
static void PCRProbeEnvironment(BOOL isThermal) {
    /* Both processes share one preference domain, so every key is prefixed to
       avoid one process overwriting the other's result. */
    NSString *p = isThermal ? @"T_" : @"S_";

    PCRNote([p stringByAppendingString:@"LoaderSeen"], 1);

    Class common = objc_getClass("CommonProduct");
    Class gp = objc_getClass("GPProduct");
    SEL sel = @selector(putDeviceInThermalSimulationMode:);

    PCRNote([p stringByAppendingString:@"HasCommonProduct"], common ? 1 : 0);
    PCRNote([p stringByAppendingString:@"HasGPProduct"], gp ? 1 : 0);
    PCRNote([p stringByAppendingString:@"CommonHasSelector"],
            (common && class_getInstanceMethod(common, sel)) ? 1 : 0);
    PCRNote([p stringByAppendingString:@"GPHasSelector"],
            (gp && class_getInstanceMethod(gp, sel)) ? 1 : 0);
}

static NSString *PCRModeName(uint64_t mode) {
    switch (mode) {
        case 1: return @"nominal";
        case 2: return @"light";
        case 3: return @"moderate";
        case 4: return @"heavy";
        default: return @"off";
    }
}

/* thermalmonitord: push the published state into the system. */
static void PCRApplyThermals(BOOL force) {
    if (PCRStateToken < 0) return;

    uint64_t mode = 0;
    if (notify_get_state(PCRStateToken, &mode) != NOTIFY_STATUS_OK) {
        os_log_error(PCRLog, "notify_get_state failed");
        return;
    }
    if (mode > 4) mode = 0;

    id product = PCRProduct;
    if (!product) return;

    if (!force && PCRLastApplied == (int)mode) return;

    SEL selector = @selector(putDeviceInThermalSimulationMode:);
    if (![product respondsToSelector:selector]) {
        os_log_error(PCRLog, "thermal selector unavailable");
        PCRNote(@"SelectorMissing", 1);
        PCRSetState(PCRAppliedToken, 99);   /* 99 = selector missing */
        return;
    }

    NSString *name = PCRModeName(mode);
    ((void (*)(id, SEL, id))objc_msgSend)(product, selector, name);
    PCRLastApplied = (int)mode;

    PCRNote(@"SelectorMissing", 0);
    PCRNote(@"LastApplied", (NSInteger)mode);
    PCRNote(@"AppliedAt", (NSInteger)time(NULL));
    PCRSetState(PCRAppliedToken, mode);
    os_log(PCRLog, "applied mode=%llu (%{public}@)", mode, name);
}

/* SpringBoard: resolve preferences into an effective mode. */
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

/* SpringBoard: publish the effective mode to the daemon. */
static void PCRPublishMode(BOOL force) {
    if (PCRStateToken < 0) return;

    NSInteger mode = PCREffectiveMode();
    if (!force && PCRLastPublished == (int)mode) return;

    notify_set_state(PCRStateToken, (uint64_t)mode);
    notify_post(PCRThermalsChanged);
    PCRLastPublished = (int)mode;
    os_log(PCRLog, "published mode=%ld", (long)mode);
}

%group PCRThermalHooks
%hook CommonProduct
- (id)initProduct:(id)arg1 {
    id product = %orig(arg1);
    if (product) {
        PCRProduct = product;
        dispatch_async(PCRQueue, ^{
            PCRLastApplied = PCR_UNSET;   /* fresh object, no simulation yet */
            PCRNote(@"HookSeen", 1);
            PCRSetState(PCRHookToken, 1);
            PCRApplyThermals(YES);
        });
    }
    return product;
}
%end

/* Some builds expose the thermal product under a different class. */
%hook GPProduct
- (id)initProduct:(id)arg1 {
    id product = %orig(arg1);
    if (product) {
        PCRProduct = product;
        dispatch_async(PCRQueue, ^{
            PCRLastApplied = PCR_UNSET;
            PCRNote(@"HookSeen", 1);
            PCRSetState(PCRHookToken, 1);
            PCRApplyThermals(YES);
        });
    }
    return product;
}
%end
%end

%group PCRSpringBoardHooks
%hook SpringBoard
- (void)_batterySaverModeChanged:(NSInteger)arg1 {
    %orig;
    dispatch_async(PCRQueue, ^{ PCRPublishMode(NO); });
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process = [[NSProcessInfo processInfo] processName];
        BOOL isThermal = [process isEqualToString:@"thermalmonitord"];
        BOOL isSpringBoard = [process isEqualToString:@"SpringBoard"];

        /* Load markers, written before any filtering, through two channels, so
           "library not loaded" can be told apart from "prefs write denied". */
        NSString *markerPath = [NSString stringWithFormat:@"/var/tmp/powercuff-%@.marker", process];
        NSString *markerText = [NSString stringWithFormat:@"pid=%d role=%@", getpid(), process];
        [markerText writeToFile:markerPath atomically:YES
                       encoding:NSUTF8StringEncoding error:NULL];
        PCRNote([@"SEEN_" stringByAppendingString:process], 1);

        if (!isThermal && !isSpringBoard) return;

        PCRLog = os_log_create("com.minis.powercuff-baldaran-trusted", "tweak");
        PCRQueue = dispatch_queue_create("com.minis.powercuff-baldaran-trusted.queue",
                                         DISPATCH_QUEUE_SERIAL);

        notify_register_check(PCRLoadedName, &PCRLoadedToken);
        notify_register_check(PCRHookName, &PCRHookToken);
        notify_register_check(PCRAppliedName, &PCRAppliedToken);
        PCRSetState(PCRLoadedToken, isThermal ? 1 : 2);   /* 1 = daemon, 2 = SpringBoard */

        if (notify_register_check(PCRThermalsChanged, &PCRStateToken) != NOTIFY_STATUS_OK) {
            os_log_error(PCRLog, "notify_register_check failed");
            PCRStateToken = -1;
        }

        PCRProbeEnvironment(isThermal);

        if (isThermal) {
            notify_register_dispatch(PCRThermalsChanged, &PCRThermalObsToken, PCRQueue,
                                     ^(int token) {
                (void)token;
                PCRApplyThermals(NO);
            });
            %init(PCRThermalHooks);
        } else {
            notify_register_dispatch(PCRSettingsChanged, &PCRSettingsObsToken, PCRQueue,
                                     ^(int token) {
                (void)token;
                PCRPublishMode(NO);
            });

            /* _batterySaverModeChanged: is private and may be absent; its
               notification is the documented, guaranteed path. */
            PCRLPMObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                            object:nil
                             queue:nil
                        usingBlock:^(NSNotification *note) {
                (void)note;
                dispatch_async(PCRQueue, ^{ PCRPublishMode(NO); });
            }];

            dispatch_async(PCRQueue, ^{ PCRPublishMode(YES); });
            %init(PCRSpringBoardHooks);
        }
    }
}
