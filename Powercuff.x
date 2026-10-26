#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#include <stdlib.h>
#include "PCRProtocol.h"
#import "PCRPreferences.h"
#import "PCRRuntime.h"

static NSString *const PCRDomain = @"com.minis.powercuff-baldaran-trusted";
static const char *const PCRSettingsChanged = "com.minis.powercuff-baldaran-trusted.settingschanged";
static const char *const PCRThermalsChanged = "com.minis.powercuff-baldaran-trusted.thermals";
static const char *const PCRRequest = "com.minis.powercuff-baldaran-trusted.request";
static os_log_t PCRLog;
// Private system objects use the daemon's main queue; thread affinity needs device validation.
static dispatch_queue_t PCRQueue;
static __weak id PCRProduct;
static BOOL PCRApplyFailed;
static int PCRStateToken = -1, PCRSettingsToken = -1, PCRRequestToken = -1;
static int PCRRequestStateToken = -1;
static uint32_t PCRSession, PCRLastPublishedSession;
static NSUInteger PCRRequestGeneration;
static int PCRLoadedToken = -1, PCRHookToken = -1, PCRAppliedToken = -1;
static int PCRLastApplied = -1, PCRLastPublished = -1;
static NSUInteger PCRGeneration, PCRApplyGeneration, PCRRefreshGeneration;
static id PCRLPMObserver;

static BOOL PCRRegister(const char *name, int *token) {
    int candidate = -1;
    uint32_t status = notify_register_check(name, &candidate);
    if (status != NOTIFY_STATUS_OK) {
        os_log_error(PCRLog, "notify registration failed: %{public}s status=%u", name, status);
        *token = -1;
        return NO;
    }
    *token = candidate;
    return YES;
}

static void PCRDiagnostic(int token, uint64_t value) {
    if (token >= 0) notify_set_state(token, value);
}

static BOOL PCRObserve(const char *name, int *token, void (^block)(int)) {
    uint32_t status = notify_register_dispatch(name, token, PCRQueue, block);
    if (status == NOTIFY_STATUS_OK) return YES;
    *token = -1;
    os_log_error(PCRLog, "notify observer failed: %{public}s status=%u", name, status);
    return NO;
}

static BOOL PCRApplyThermals(void) {
    @autoreleasepool {
        uint64_t state = 0;
        unsigned mode = 0;
        if (PCRStateToken < 0 || notify_get_state(PCRStateToken, &state) != NOTIFY_STATUS_OK ||
            !PCRDecodeMode(state, PCRSession, &mode)) return NO;
        id product = PCRProduct;
        if (!product || PCRApplyFailed || PCRLastApplied == (int)mode) return YES;
        SEL selector = @selector(putDeviceInThermalSimulationMode:);
        if (!PCRMethodMatches(object_getClass(product), selector, 'v')) {
            PCRApplyFailed = YES;
            PCRDiagnostic(PCRAppliedToken, 99);
            return YES;
        }
        NSString *names[] = {@"off", @"nominal", @"light", @"moderate", @"heavy"};
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(product, selector, names[mode]);
            PCRLastApplied = (int)mode;
            PCRDiagnostic(PCRAppliedToken, mode);
            os_log(PCRLog, "thermal API returned for mode=%u", mode);
        } @catch (NSException *exception) {
            // Does not catch SIGBUS, SIGSEGV or watchdog termination.
            PCRApplyFailed = YES;
            PCRDiagnostic(PCRAppliedToken, 98);
            os_log_error(PCRLog, "thermal API exception: %{public}@", exception.name);
        }
        return YES; // API faults are terminal for this object; do not retry private calls.
    }
}

static void PCRApplyAttempt(unsigned attempt, NSUInteger generation) {
    if (generation != PCRApplyGeneration) return;
    if (!PCRApplyThermals() && attempt < 5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
            PCRApplyAttempt(attempt + 1, generation);
        });
    }
}

static BOOL PCRReadMode(NSInteger *mode) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PCRDomain];
    NSDictionary *snapshot = PCRPreferenceSnapshot(defaults, PCRDomain);
    id raw = snapshot[@"PowerMode"];
    if (!raw) return NO;
    *mode = PCRValidatedMode(raw, snapshot[@"RequireLowPowerMode"],
                             NSProcessInfo.processInfo.lowPowerModeEnabled);
    return YES;
}

static void PCRPublishAttempt(BOOL force, unsigned attempt, NSUInteger generation) {
    @autoreleasepool {
        if (generation != PCRGeneration || PCRStateToken < 0) return;
        uint64_t request = 0;
        uint32_t session = 0;
        BOOL haveSession = notify_get_state(PCRRequestStateToken, &request) == NOTIFY_STATUS_OK &&
                           PCRDecodeRequest(request, &session);
        NSInteger mode = 0;
        BOOL havePrefs = PCRReadMode(&mode);
        if ((!haveSession || !havePrefs) && attempt < 5) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
                PCRPublishAttempt(force, attempt + 1, generation);
            });
            return;
        }
        if (!haveSession) return; // Never publish a value without a daemon session.
        // A missing key remains the first-install default, after bounded retries.
        if (!force && PCRLastPublished == mode && PCRLastPublishedSession == session) return;
        if (notify_set_state(PCRStateToken, PCREncodeMode(session, (unsigned)mode)) != NOTIFY_STATUS_OK ||
            notify_post(PCRThermalsChanged) != NOTIFY_STATUS_OK) {
            os_log_error(PCRLog, "mode publication failed");
            if (attempt < 5) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
                    PCRPublishAttempt(force, attempt + 1, generation);
                });
            }
            return;
        }
        PCRLastPublished = (int)mode;
        PCRLastPublishedSession = session;
        os_log(PCRLog, "published mode=%ld session=%u", (long)mode, session);
    }
}

static void PCRPublish(BOOL force) {
    PCRPublishAttempt(force, 0, ++PCRGeneration);
}

// Settings notification delivery and cfprefsd visibility need not coincide.
// Reread the current domain twice; never capture a stale mode in a delayed block.
static void PCRRefreshPreferences(void) {
    NSUInteger generation = ++PCRRefreshGeneration;
    PCRPublish(NO);
    for (NSNumber *delay in @[@0.15, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), PCRQueue, ^{
            if (generation == PCRRefreshGeneration) PCRPublish(NO);
        });
    }
}

static void PCRRequestFresh(unsigned attempt, NSUInteger generation) {
    if (generation != PCRRequestGeneration || !PCRProduct || PCRLastApplied >= 0 || PCRApplyFailed) return;
    if (notify_set_state(PCRRequestStateToken, PCREncodeRequest(PCRSession)) != NOTIFY_STATUS_OK ||
        notify_post(PCRRequest) != NOTIFY_STATUS_OK)
        os_log_error(PCRLog, "publisher request failed");
    // Bounded recovery for a lost startup request; no continuous polling.
    if (attempt < 5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
            PCRRequestFresh(attempt + 1, generation);
        });
    }
}

static void PCRCaptureProduct(id product) {
    __weak id candidate = product;
    dispatch_async(PCRQueue, ^{
        id current = candidate;
        if (!current || current == PCRProduct) return;
        PCRProduct = current; // All cache accesses confined to the daemon main queue.
        ++PCRApplyGeneration; // Invalidate reads queued for a previous product/session.
        PCRLastApplied = -1;
        PCRApplyFailed = NO;
        PCRDiagnostic(PCRHookToken, 1);
        PCRDiagnostic(PCRAppliedToken, 10); // Waiting for a valid publisher state.
        do { PCRSession = arc4random(); } while (!PCRSession);
        PCRRequestFresh(0, ++PCRRequestGeneration);
        // Do not apply notify's cached value: only a reply matching this session is accepted.
    });
}

%group PCRCommonHooks
%hook CommonProduct
- (id)initProduct:(id)arg1 {
    id result = %orig(arg1);
    if (result) PCRCaptureProduct(result);
    return result;
}
%end
%end

%group PCRGPHooks
%hook GPProduct
- (id)initProduct:(id)arg1 {
    id result = %orig(arg1);
    if (result) PCRCaptureProduct(result);
    return result;
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *name = NSProcessInfo.processInfo.processName;
        BOOL isThermal = [name isEqualToString:@"thermalmonitord"];
        if (!isThermal && ![name isEqualToString:@"SpringBoard"]) return;
        PCRLog = os_log_create("com.minis.powercuff-baldaran-trusted", "tweak");
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 16) {
            os_log_error(PCRLog, "unsupported iOS major version; leaving stock behavior");
            return;
        }
        PCRQueue = isThermal ? dispatch_get_main_queue() :
            dispatch_queue_create("com.minis.powercuff-baldaran-trusted.publisher", DISPATCH_QUEUE_SERIAL);
        PCRRegister(isThermal ? "com.minis.powercuff-baldaran-trusted.loaded.t" :
                    "com.minis.powercuff-baldaran-trusted.loaded.s", &PCRLoadedToken);
        PCRDiagnostic(PCRLoadedToken, 1);
        if (!PCRRegister(PCRThermalsChanged, &PCRStateToken) ||
            !PCRRegister(PCRRequest, &PCRRequestStateToken)) return;
        if (isThermal) {
            PCRRegister("com.minis.powercuff-baldaran-trusted.hook", &PCRHookToken);
            PCRRegister("com.minis.powercuff-baldaran-trusted.applied", &PCRAppliedToken);
            PCRDiagnostic(PCRHookToken, 0);
            PCRDiagnostic(PCRAppliedToken, 10);
            if (!PCRObserve(PCRThermalsChanged, &PCRSettingsToken, ^(int token) {
                (void)token; PCRApplyAttempt(0, ++PCRApplyGeneration);
            })) return;
            Class common = objc_getClass("CommonProduct"), gp = objc_getClass("GPProduct");
            SEL init = @selector(initProduct:), apply = @selector(putDeviceInThermalSimulationMode:);
            BOOL commonOK = PCRMethodMatches(common, init, '@') && PCRMethodMatches(common, apply, 'v');
            // Compare BEFORE hooking: an inherited method needs only the base-class hook.
            BOOL gpOK = PCRMethodMatches(gp, init, '@') && PCRMethodMatches(gp, apply, 'v') &&
                (!commonOK || PCRNeedsSeparateHook(gp, common, init));
            if (!commonOK && !gpOK) {
                PCRDiagnostic(PCRAppliedToken, 99);
                os_log_error(PCRLog, "no supported thermal initializer/API ABI; hooks disabled");
                return;
            }
            if (commonOK) { %init(PCRCommonHooks); }
            if (gpOK) { %init(PCRGPHooks); }
        } else {
            if (!PCRObserve(PCRSettingsChanged, &PCRSettingsToken, ^(int token) {
                (void)token; PCRRefreshPreferences();
            }) || !PCRObserve(PCRRequest, &PCRRequestToken, ^(int token) {
                (void)token; PCRPublish(YES);
            })) return;
            PCRLPMObserver = [NSNotificationCenter.defaultCenter
                addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
                    (void)note; dispatch_async(PCRQueue, ^{ PCRRefreshPreferences(); });
                }];
            dispatch_async(PCRQueue, ^{ PCRPublish(YES); });
            for (NSNumber *delay in @[@3, @10, @30, @60]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               PCRQueue, ^{ PCRPublish(NO); });
            }
        }
    }
}
