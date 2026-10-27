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

static void Enqueue(uint64_t deadline, dispatch_block_t block) {
    [Tasks addObject:@{@"time": @(deadline), @"block": [block copy]}];
}
static dispatch_time_t TestTime(dispatch_time_t when, int64_t delta) {
    assert(when == DISPATCH_TIME_NOW && delta >= 0);
    return Clock + (uint64_t)delta;
}
static void TestAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    (void)queue; Enqueue(when, block);
}
static void TestAsync(dispatch_queue_t queue, dispatch_block_t block) {
    (void)queue; Enqueue(Clock, block);
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
        if (Respond) Enqueue(Clock, ^{ PCRPublish(YES); });
    } else if (strcmp(name, PCRThermalsChanged) == 0) {
        ++ModePosts;
        if (Deliver) Enqueue(Clock, ^{ PCRApplyAttempt(0, ++PCRApplyGeneration); });
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
static void Reset(void) {
    Tasks = [NSMutableArray new]; States = [NSMutableDictionary new];
    Preferences = @{@"PowerMode": @3}; Clock = 0;
    ReadFailures = SetFailures = PostFailures = ReadCalls = RequestPosts = ModePosts = 0;
    RegistrationStatus = 0; NextToken = 20;
    Respond = Deliver = YES; LowPower = NO;
    PCRLog = OS_LOG_DEFAULT; PCRQueue = dispatch_get_main_queue(); PCRProduct = nil;
    PCRApplyFailed = PCRAwaitingReply = PCRRecoveryRequested = NO;
    PCRStateToken = 1; PCRRequestStateToken = 2; PCRAppliedToken = 3;
    PCRHookToken = 4; PCRLoadedToken = 5; PCRSettingsToken = PCRRequestToken = -1;
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

int main(void) {
    @autoreleasepool {
        Reset();
        int token = -1;
        assert(PCRRegister(PCRSettingsChanged, &token) && token >= 0);
        assert(PCRObserve(PCRSettingsChanged, &token, ^(int value) { (void)value; }));
        RegistrationStatus = 1;
        assert(!PCRRegister(PCRSettingsChanged, &token) && token == -1);
        assert(!PCRObserve(PCRSettingsChanged, &token, ^(int value) { (void)value; }) && token == -1);
        puts("Core: notification registration failures fail closed PASS");

        Reset(); TestProduct *product = [TestProduct new];
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && [product.mode isEqual:@"moderate"] && Status() == 3);
        assert(!PCRAwaitingReply && RequestPosts == 1);
        PCRPublish(YES); Drain();
        assert(product.calls == 1);
        puts("Core: handshake, session response and same-mode private-call dedup PASS");

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

        Reset(); product = [TestProduct new]; Preferences = @{};
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && [product.mode isEqual:@"off"] && Status() == 0);
        puts("Core: missing preferences resolve to Off after finite retries PASS");

        Reset(); product = [TestProduct new]; product.fail = YES;
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && PCRApplyFailed && Status() == 98);
        PCRPublish(YES); Drain(); assert(product.calls == 1 && Status() == 98);
        TestProduct *replacement = [TestProduct new];
        PCRCaptureProduct(replacement); Drain();
        assert(replacement.calls == 1 && !PCRApplyFailed && Status() == 3);
        puts("Core: Objective-C exception is terminal for the object; replacement starts fresh PASS");

        Reset(); NSObject *unsupported = [NSObject new];
        PCRCaptureProduct(unsupported); Drain(); assert(PCRApplyFailed && Status() == 99);
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

        Reset(); product = [TestProduct new]; SetFailures = 2; PostFailures = 2;
        PCRCaptureProduct(product); Drain();
        assert(product.calls == 1 && Status() == 3 && RequestPosts <= 6);
        puts("Core: transient set/post failures recover within the request budget PASS");
    }
}
