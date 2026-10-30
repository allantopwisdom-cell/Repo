// Execute the production core with an in-memory notify transport and virtual clock.
// No private system object, real notification registration, or device operation is used.
#import <Foundation/Foundation.h>
#import <notify.h>
#import <os/log.h>
#import "PCRProtocol.h"
#import "PCRPreferences.h"
#import "PCRRuntime.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

static NSMutableArray<NSDictionary *> *Tasks;
static NSMutableDictionary<NSNumber *, NSNumber *> *States;
static NSDictionary *Preferences;
static uint64_t Clock;
static unsigned ReadFailures, SetFailures, PostFailures, ReadCalls, RequestPosts, ModePosts;
static unsigned RegistrationStatus;
static BOOL Respond, Deliver, LowPower;
static int NextToken;
static uint32_t NextSession = 100;

@interface TestDefaults : NSUserDefaults
@end
@implementation TestDefaults
- (NSDictionary *)persistentDomainForName:(NSString *)name { (void)name; return Preferences; }
@end
@interface TestProcessInfo : NSObject
+ (instancetype)processInfo;
- (BOOL)lowPowerModeEnabled;
@end
@implementation TestProcessInfo
+ (instancetype)processInfo { return [self new]; }
- (BOOL)lowPowerModeEnabled { return LowPower; }
@end

static void PCRTestEnqueue(uint64_t deadline, dispatch_block_t block) {
    [Tasks addObject:@{@"time": @(deadline), @"block": [block copy]}];
}
static dispatch_time_t TestTime(dispatch_time_t when, int64_t delta) {
    assert(when == DISPATCH_TIME_NOW && delta >= 0);
    return Clock + (uint64_t)delta;
}
static void TestAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    (void)queue; PCRTestEnqueue(when, block);
}
static void TestAsync(dispatch_queue_t queue, dispatch_block_t block) {
    (void)queue; PCRTestEnqueue(Clock, block);
}
static void PCRPublish(BOOL force);
static void PCRApplyAttempt(unsigned attempt, NSUInteger generation);
static uint32_t TestGetState(int token, uint64_t *state);
static uint32_t TestSetState(int token, uint64_t state);
static uint32_t TestPost(const char *name);
static uint32_t TestRegister(const char *name, int *token) {
    (void)name;
    if (!RegistrationStatus) *token = NextToken++;
    return RegistrationStatus;
}
static uint32_t TestObserve(const char *name, int *token, dispatch_queue_t queue, void (^block)(int)) {
    (void)queue; (void)block; return TestRegister(name, token);
}
static uint32_t TestRandom(void) { return ++NextSession; }

// Headers were imported above, so these adapters replace only calls in the actual core.
#define NSUserDefaults TestDefaults
#define NSProcessInfo TestProcessInfo
#define dispatch_time TestTime
#define dispatch_after TestAfter
#define dispatch_async TestAsync
#define notify_get_state TestGetState
#define notify_set_state TestSetState
#define notify_post TestPost
#define notify_register_check TestRegister
#define notify_register_dispatch TestObserve
#define arc4random TestRandom
#import "PCRCore.h"
#undef NSUserDefaults
#undef NSProcessInfo
#undef dispatch_time
#undef dispatch_after
#undef dispatch_async
#undef notify_get_state
#undef notify_set_state
#undef notify_post
#undef notify_register_check
#undef notify_register_dispatch
#undef arc4random

static uint32_t TestGetState(int token, uint64_t *state) {
    if (token == PCRStateToken) {
        ++ReadCalls;
        if (ReadFailures) { --ReadFailures; return 1; }
    }
    *state = [States[@(token)] unsignedLongLongValue];
    return NOTIFY_STATUS_OK;
}
static uint32_t TestSetState(int token, uint64_t state) {
    if (SetFailures && (token == PCRStateToken || token == PCRRequestStateToken)) {
        --SetFailures; return 1;
    }
    States[@(token)] = @(state);
    return NOTIFY_STATUS_OK;
}
static uint32_t TestPost(const char *name) {
    if (PostFailures) { --PostFailures; return 1; }
    if (strcmp(name, PCRRequest) == 0) {
        ++RequestPosts;
        if (Respond) PCRTestEnqueue(Clock, ^{ PCRPublish(YES); });
    } else if (strcmp(name, PCRThermalsChanged) == 0) {
        ++ModePosts;
        if (Deliver) PCRTestEnqueue(Clock, ^{ PCRApplyAttempt(0, ++PCRApplyGeneration); });
    }
    return NOTIFY_STATUS_OK;
}
static void RunOne(void) {
    assert(Tasks.count);
    NSUInteger first = 0;
    for (NSUInteger i = 1; i < Tasks.count; ++i)
        if ([Tasks[i][@"time"] unsignedLongLongValue] < [Tasks[first][@"time"] unsignedLongLongValue]) first = i;
    NSDictionary *task = Tasks[first];
    Clock = [task[@"time"] unsignedLongLongValue];
    dispatch_block_t block = task[@"block"];
    [Tasks removeObjectAtIndex:first];
    block();
}
static void Drain(void) {
    unsigned steps = 0;
    while (Tasks.count) { assert(++steps < 1000); RunOne(); }
}
static void RunUntil(uint64_t deadline) {
    assert(deadline >= Clock); // A virtual clock must never move backwards.
    unsigned steps = 0;
    while (Tasks.count) {
        uint64_t first = UINT64_MAX;
        for (NSDictionary *task in Tasks) first = MIN(first, [task[@"time"] unsignedLongLongValue]);
        if (first > deadline) break;
        assert(++steps < 1000); RunOne();
    }
    Clock = deadline;
}
static void Reset(void) {
    Tasks = [NSMutableArray new]; States = [NSMutableDictionary new];
    Preferences = @{@"PowerMode": @3}; Clock = 0;
    ReadFailures = SetFailures = PostFailures = ReadCalls = RequestPosts = ModePosts = 0;
    RegistrationStatus = 0; NextToken = 20;
    Respond = Deliver = YES; LowPower = NO;
    PCRLog = OS_LOG_DEFAULT; PCRQueue = dispatch_get_main_queue(); PCRProduct = nil;
    PCRApplyFailed = PCRAwaitingReply = PCRRecoveryRequested = NO;
    PCRStateToken = 1; PCRRequestStateToken = 2; PCRAppliedToken = 3;
    PCRHookToken = 4; PCRLoadedToken = 5; PCRSettingsToken = PCRRequestToken = PCRUserSettingsToken = -1;
    PCRSession = PCRLastPublishedSession = 0;
    PCRLastApplied = PCRLastPublished = -1;
    PCRRequestGeneration = PCRGeneration = PCRApplyGeneration = PCRRefreshGeneration = 0;
}
static uint64_t Status(void) { return [States[@(PCRAppliedToken)] unsignedLongLongValue]; }
@interface TestProduct : NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic, copy) NSString *mode;
@property(nonatomic) BOOL fail;
- (void)putDeviceInThermalSimulationMode:(id)mode;
@end
@implementation TestProduct
- (void)putDeviceInThermalSimulationMode:(id)mode {
    ++_calls;
    if (_fail) @throw [NSException exceptionWithName:@"SyntheticFault" reason:nil userInfo:nil];
    _mode = [mode copy];
}
@end

@interface TestBlockProduct : NSObject
@property(nonatomic) NSUInteger calls;
- (void)putDeviceInThermalSimulationMode:(dispatch_block_t)block;
@end
@implementation TestBlockProduct
- (void)putDeviceInThermalSimulationMode:(dispatch_block_t)block {
    (void)block; ++_calls;
}
@end

int main(void) {
    @autoreleasepool {
        Reset();
        int token = -1;
        assert(PCRRegister(PCRSettingsChanged, &token) && token >= 0);
        assert(PCRObserve(PCRSettingsChanged, &token, ^(int value) { (void)value; }));
        RegistrationStatus = 1;
        assert(!PCRRegister(PCRSettingsChanged, &token) && token == -1);
        assert(!PCRObserve(PCRSettingsChanged, &token, ^(int value) { (void)value; }) && token == -1);
        PCRRequestForSettingsChange(); Drain(); assert(RequestPosts == 0);
        puts("Core: notification registration failures fail closed PASS");

        Reset(); TestProduct *product = [TestProduct new];
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && [product.mode isEqual:@"moderate"] && Status() == 3);
        assert(!PCRAwaitingReply && RequestPosts == 1);
        PCRPublish(YES); Drain();
        assert(product.calls == 1);
        puts("Core: handshake, session response and same-mode private-call dedup PASS");

        // A successful state write followed by a failed post is not a publication.
        // Returning to the previously delivered value must repair the shared state.
        Reset(); product = [TestProduct new]; Preferences = @{@"PowerMode": @0};
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && Status() == 0);
        PostFailures = 1; Preferences = @{@"PowerMode": @4}; PCRPublish(NO);
        Preferences = @{@"PowerMode": @0}; PCRPublish(NO); Drain();
        unsigned repairedMode = 99;
        assert(PCRDecodeMode([States[@(PCRStateToken)] unsignedLongLongValue], PCRSession, &repairedMode));
        assert(repairedMode == 0 && PCRLastPublished == 0);
        PCRApplyAttempt(0, ++PCRApplyGeneration); Drain();
        assert(product.calls == 1 && Status() == 0 && [product.mode isEqual:@"off"]);
        puts("Core: failed mode post then return to Off repairs state and cancels stale retry PASS");

        Reset(); product = [TestProduct new]; PCRCaptureProduct(product); Drain();

        // Invalid state after an initial success used to leave the old mode silently.
        States[@(PCRStateToken)] = @(PCREncodeMode(PCRSession + 1, 4));
        unsigned before = RequestPosts;
        PCRApplyAttempt(0, ++PCRApplyGeneration); Drain();
        assert(RequestPosts > before && product.calls == 1 && Status() == 3);
        puts("Core: stale session reacquires current state without repeating the private call PASS");

        ReadFailures = 10000; before = RequestPosts;
        PCRApplyAttempt(0, ++PCRApplyGeneration); Drain();
        assert(Status() == 11 && product.calls == 1);
        assert(RequestPosts - before <= 6 && ReadCalls < 100 && Tasks.count == 0);
        before = RequestPosts; PCRRequestForSettingsChange(); Drain();
        assert(RequestPosts - before == 6 && Status() == 11 && Tasks.count == 0);
        ReadFailures = 0; Preferences = @{@"PowerMode": @0};
        PCRPublish(YES); Drain();
        assert(Status() == 0 && product.calls == 2 && [product.mode isEqual:@"off"]);
        puts("Core: permanent read failure is bounded, exposes stale status, later Off recovers PASS");

        Reset(); product = [TestProduct new]; Respond = NO;
        PCRCaptureProduct(product); Drain();
        assert(RequestPosts == 6 && product.calls == 0 && Status() == 11);
        Respond = YES; PCRPublish(YES); Drain();
        assert(product.calls == 1 && Status() == 3);
        puts("Core: missing publisher times out without polling; late valid reply recovers PASS");

        // Transport replies cannot rearm themselves after timeout. A preference
        // edit is independently observed and can explicitly start a finite cycle.
        Reset(); product = [TestProduct new]; PCRCaptureProduct(product); Drain();
        Respond = NO; States[@(PCRStateToken)] = @(0);
        before = RequestPosts; PCRApplyAttempt(0, ++PCRApplyGeneration); Drain();
        assert(RequestPosts - before == 6 && Status() == 11 && PCRRecoveryRequested);
        Respond = YES; before = RequestPosts;
        PCRApplyAttempt(0, ++PCRApplyGeneration); Drain();
        assert(RequestPosts == before && Status() == 11);
        PCRRequestForSettingsChange(); Drain();
        assert(RequestPosts > before && Status() == 3 && product.calls == 1 && Tasks.count == 0);
        puts("Core: invalid transport cannot rearm recovery; an explicit settings event recovers PASS");

        // Execute the actual startup schedule rather than invoking Publish by hand.
        // Lost deliveries outlast the handshake, and preferences change before replay.
        Reset(); product = [TestProduct new]; Deliver = NO;
        PCRCaptureProduct(product); PCRScheduleStartupReplays();
        RunUntil(2500 * NSEC_PER_MSEC); assert(product.calls == 0 && Status() == 11);
        Deliver = YES; Preferences = @{@"PowerMode": @0}; before = ModePosts; Drain();
        assert(ModePosts == before + 4 && product.calls == 1 && Status() == 0);
        assert([product.mode isEqual:@"off"] && Clock == 60 * NSEC_PER_SEC && Tasks.count == 0);
        puts("Core: four actual startup replays recover lost delivery using current Off, then stop PASS");

        Reset(); product = [TestProduct new]; Preferences = @{};
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && [product.mode isEqual:@"off"] && Status() == 0);
        puts("Core: missing preferences resolve to Off after finite retries PASS");

        Reset(); product = [TestProduct new]; product.fail = YES;
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && PCRApplyFailed && Status() == 98);
        PCRPublish(YES); Drain(); assert(product.calls == 1 && Status() == 98);
        before = RequestPosts; PCRRequestForSettingsChange(); Drain();
        assert(RequestPosts == before && product.calls == 1 && Status() == 98);
        TestProduct *replacement = [TestProduct new];
        PCRCaptureProduct(replacement); Drain();
        assert(replacement.calls == 1 && !PCRApplyFailed && Status() == 3);
        puts("Core: Objective-C exception is terminal for the object; replacement starts fresh PASS");

        // ABI validation must not depend on an unrelated publisher replying.
        Reset(); Respond = NO; NSObject *offlineUnsupported = [NSObject new];
        PCRCaptureProduct(offlineUnsupported); Drain();
        assert(PCRApplyFailed && Status() == 99 && RequestPosts == 0 && !PCRAwaitingReply);
        before = RequestPosts; PCRRequestForSettingsChange(); Drain();
        assert(RequestPosts == before && Status() == 99 && Tasks.count == 0);
        puts("Core: unsupported receiver is rejected before IPC even without a publisher PASS");

        Reset(); product = [TestProduct new]; Respond = NO;
        PCRCaptureProduct(product); RunOne(); before = RequestPosts;
        TestBlockProduct *blockProduct = [TestBlockProduct new];
        PCRCaptureProduct(blockProduct); Drain();
        assert(PCRApplyFailed && Status() == 99 && RequestPosts == before && !PCRAwaitingReply);
        assert(product.calls == 0 && blockProduct.calls == 0 && Tasks.count == 0);
        PCRPublish(YES); Drain();
        assert(blockProduct.calls == 0 && Status() == 99);
        Respond = YES; TestProduct *afterBadReceiver = [TestProduct new];
        PCRCaptureProduct(afterBadReceiver); Drain();
        assert(!PCRApplyFailed && afterBadReceiver.calls == 1 && Status() == 3);
        puts("Core: block-ABI replacement cancels old requests; a valid replacement starts fresh PASS");

        Reset(); NSObject *unsupported = [NSObject new];
        PCRCaptureProduct(unsupported); Drain(); assert(PCRApplyFailed && Status() == 99);
        before = RequestPosts; PCRRequestForSettingsChange(); Drain();
        assert(RequestPosts == before && Status() == 99);
        puts("Core: unsupported product ABI is disabled before private dispatch PASS");

        Reset(); product = [TestProduct new]; replacement = [TestProduct new]; Respond = NO;
        PCRCaptureProduct(product); RunOne(); uint32_t oldSession = PCRSession;
        PCRCaptureProduct(replacement); Drain(); assert(PCRSession != oldSession);
        Respond = YES; PCRPublish(YES); Drain();
        assert(product.calls == 0 && replacement.calls == 1);
        puts("Core: product replacement invalidates old asynchronous requests PASS");

        Reset();
        @autoreleasepool {
            TestProduct *temporary = [TestProduct new]; PCRCaptureProduct(temporary); temporary = nil;
        }
        Drain(); assert(!PCRProduct && RequestPosts == 0);
        puts("Core: deferred capture does not retain a discarded product PASS");

        Reset(); product = [TestProduct new]; PCRCaptureProduct(product); Drain();
        Preferences = @{@"PowerMode": @4}; PCRRefreshPreferences();
        Preferences = @{@"PowerMode": @0}; PCRRefreshPreferences(); Drain();
        assert([product.mode isEqual:@"off"] && Status() == 0 && !PCRAwaitingReply);
        Preferences = @{@"PowerMode": @2, @"RequireLowPowerMode": @YES};
        PCRRefreshPreferences(); Drain(); assert([product.mode isEqual:@"off"]);
        LowPower = YES; PCRRefreshPreferences(); Drain(); assert([product.mode isEqual:@"light"]);
        LowPower = NO; PCRRefreshPreferences(); Drain(); assert([product.mode isEqual:@"off"]);
        puts("Core: rapid preference changes and LPM use current values, not stale delayed modes PASS");

        // notify_post success is not delivery acknowledgement. After startup has
        // ended, a lost first change must be repaired by the finite reread window.
        Reset(); product = [TestProduct new]; PCRCaptureProduct(product); Drain();
        Clock = 120 * NSEC_PER_SEC; Deliver = NO; before = ModePosts;
        Preferences = @{@"PowerMode": @0}; PCRRefreshPreferences();
        RunUntil(Clock + 100 * NSEC_PER_MSEC);
        assert(product.calls == 1 && [product.mode isEqual:@"moderate"]);
        Deliver = YES; Drain();
        assert(product.calls == 2 && [product.mode isEqual:@"off"] && Status() == 0);
        assert(ModePosts - before == 3 && Tasks.count == 0);
        puts("Core: lost first settings delivery recovers Off after startup without polling PASS");

        Reset(); product = [TestProduct new]; LowPower = YES;
        Preferences = @{@"PowerMode": @2, @"RequireLowPowerMode": @YES};
        PCRCaptureProduct(product); Drain(); assert([product.mode isEqual:@"light"]);
        for (unsigned transition = 0; transition < 2; ++transition) {
            LowPower = transition == 1; Deliver = NO; before = ModePosts;
            PCRRefreshPreferences(); RunUntil(Clock + 100 * NSEC_PER_MSEC);
            Deliver = YES; Drain();
            assert([product.mode isEqual:(LowPower ? @"light" : @"off")]);
            assert(ModePosts - before == 3 && Tasks.count == 0);
        }
        assert(product.calls == 3);
        puts("Core: lost first LPM entry/exit delivery recovers with no repeated private call PASS");

        Reset(); product = [TestProduct new]; PCRCaptureProduct(product); Drain();
        uint64_t refreshStart = Clock;
        before = ModePosts; Preferences = @{@"PowerMode": @4}; PCRRefreshPreferences();
        RunUntil(refreshStart + 100 * NSEC_PER_MSEC);
        assert([product.mode isEqual:@"heavy"]);
        Preferences = @{@"PowerMode": @0}; PCRRefreshPreferences(); Drain();
        assert([product.mode isEqual:@"off"] && product.calls == 3 && Status() == 0);
        assert(ModePosts - before == 4 && Clock == refreshStart + 700 * NSEC_PER_MSEC && Tasks.count == 0);
        puts("Core: newer Off cancels earlier Heavy replays; finite refresh stops at 600ms PASS");

        Reset(); product = [TestProduct new]; PCRCaptureProduct(product); Drain();
        PCRRefreshPreferences(); RunUntil(Clock + 300 * NSEC_PER_MSEC);
        Preferences = @{@"PowerMode": @0}; Drain();
        assert([product.mode isEqual:@"off"] && product.calls == 2 && Status() == 0);
        puts("Core: delayed preference visibility is reread at the last refresh, not captured PASS");

        Reset(); product = [TestProduct new]; product.fail = YES;
        PCRCaptureProduct(product); Drain();
        Preferences = @{@"PowerMode": @0}; PCRRefreshPreferences(); Drain();
        assert(product.calls == 1 && PCRApplyFailed && Status() == 98 && Tasks.count == 0);
        puts("Core: finite refresh replays cannot bypass the private API exception fuse PASS");

        Reset(); product = [TestProduct new]; SetFailures = 2; PostFailures = 2;
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && Status() == 3 && RequestPosts <= 6);
        puts("Core: transient set/post failures recover within the request budget PASS");
    }
}
