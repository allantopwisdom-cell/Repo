#ifndef PCR_CORE_H
#define PCR_CORE_H
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
static BOOL PCRAwaitingReply, PCRRecoveryRequested;
static int PCRStateToken = -1, PCRSettingsToken = -1, PCRRequestToken = -1;
static int PCRUserSettingsToken = -1;
static int PCRRequestStateToken = -1;
static uint32_t PCRSession, PCRLastPublishedSession;
static NSUInteger PCRRequestGeneration;
static int PCRLoadedToken = -1, PCRHookToken = -1, PCRAppliedToken = -1;
static int PCRLastApplied = -1, PCRLastPublished = -1;
static NSUInteger PCRGeneration, PCRApplyGeneration, PCRRefreshGeneration;

static void PCRRequestFresh(unsigned attempt, NSUInteger generation);

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
        if (!product || PCRApplyFailed) return YES;
        PCRAwaitingReply = NO;
        PCRRecoveryRequested = NO;
        ++PCRRequestGeneration; // A matching response cancels any outstanding requests.
        if (PCRLastApplied == (int)mode) {
            PCRDiagnostic(PCRAppliedToken, mode); // Restore status after transport recovery.
            return YES;
        }
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
    if (PCRApplyThermals()) return;
    if (attempt < 5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
            PCRApplyAttempt(attempt + 1, generation);
        });
    } else if (PCRProduct && !PCRApplyFailed) {
        PCRDiagnostic(PCRAppliedToken, 11);
        os_log_error(PCRLog, "state reads exhausted; last applied mode may be stale");
        // One bounded fresh-response cycle per failure episode. Invalid replies must
        // not recursively start new cycles. A valid reply or new product rearms it.
        if (!PCRRecoveryRequested) {
            PCRRecoveryRequested = YES;
            PCRAwaitingReply = YES;
            PCRRequestFresh(0, ++PCRRequestGeneration);
        }
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
        // set_state can succeed even when post fails. Until BOTH succeed, the
        // shared word may differ from the last delivered value. Invalidate first
        // so a newer generation returning to that value repairs it instead of
        // skipping publication and leaving a stale (possibly non-Off) word.
        PCRLastPublished = -1;
        PCRLastPublishedSession = 0;
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

static void PCRScheduleStartupReplays(void) {
    dispatch_async(PCRQueue, ^{ PCRPublish(YES); });
    // A successful post is not an acknowledgement from the daemon. Replay a
    // finite number of times, reading current preferences on every attempt.
    for (NSNumber *delay in @[@3, @10, @30, @60]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       PCRQueue, ^{ PCRPublish(YES); });
    }
}

// Settings notification delivery, transport delivery and cfprefsd visibility
// need not coincide. A successful post is not a daemon acknowledgement.
// Reread AND republish during this finite window, even if the mode is unchanged.
// Private API calls remain deduplicated by the daemon. No idle polling is added.
static void PCRRefreshPreferences(void) {
    NSUInteger generation = ++PCRRefreshGeneration;
    PCRPublish(YES);
    for (NSNumber *delay in @[@0.15, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), PCRQueue, ^{
            if (generation == PCRRefreshGeneration) PCRPublish(YES);
        });
    }
}

static void PCRRequestFresh(unsigned attempt, NSUInteger generation) {
    if (generation != PCRRequestGeneration || !PCRProduct || !PCRAwaitingReply || PCRApplyFailed) return;
    if (notify_set_state(PCRRequestStateToken, PCREncodeRequest(PCRSession)) != NOTIFY_STATUS_OK ||
        notify_post(PCRRequest) != NOTIFY_STATUS_OK)
        os_log_error(PCRLog, "publisher request failed");
    // Bounded recovery for a lost startup request; no continuous polling.
    if (attempt < 5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
            PCRRequestFresh(attempt + 1, generation);
        });
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), PCRQueue, ^{
            if (generation == PCRRequestGeneration && PCRProduct && PCRAwaitingReply && !PCRApplyFailed) {
                PCRDiagnostic(PCRAppliedToken, 11);
                // Keep the latch: read retries from the last invalid reply can
                // outlive this timeout. They must not recursively start a cycle.
                os_log_error(PCRLog, "session response timed out; no further periodic requests");
            }
        });
    }
}

// settingschanged comes from a preference edit, not from our own request/reply
// transport. Only this explicit external event may rearm a failed recovery.
// The daemon still never reads the mobile preference domain itself.
static void PCRRequestForSettingsChange(void) {
    if (!PCRProduct || PCRApplyFailed) return;
    ++PCRApplyGeneration;
    PCRRecoveryRequested = YES;
    PCRAwaitingReply = YES;
    PCRRequestFresh(0, ++PCRRequestGeneration);
}

static void PCRCaptureProduct(id product) {
    __weak id candidate = product;
    dispatch_async(PCRQueue, ^{
        id current = candidate;
        if (!current || current == PCRProduct) return;
        PCRProduct = current; // All cache accesses confined to the daemon main queue.
        ++PCRApplyGeneration; // Invalidate reads queued for a previous product/session.
        ++PCRRequestGeneration; // Cancel old IPC even if this receiver fails preflight.
        PCRLastApplied = -1;
        PCRApplyFailed = NO;
        PCRAwaitingReply = NO;
        PCRRecoveryRequested = NO;
        PCRDiagnostic(PCRHookToken, 1);
        // The initializer may return a different/subclass receiver. Diagnose an
        // unsupported ABI before IPC, including when the publisher is absent.
        if (!PCRMethodMatches(object_getClass(current), @selector(putDeviceInThermalSimulationMode:), 'v')) {
            PCRApplyFailed = YES;
            PCRDiagnostic(PCRAppliedToken, 99);
            os_log_error(PCRLog, "captured receiver has unsupported thermal API ABI; requests disabled");
            return;
        }
        PCRAwaitingReply = YES;
        PCRDiagnostic(PCRAppliedToken, 10); // Waiting for a valid publisher state.
        do { PCRSession = arc4random(); } while (!PCRSession);
        PCRRequestFresh(0, PCRRequestGeneration);
        // Do not apply notify's cached value: only a reply matching this session is accepted.
    });
}


#endif
