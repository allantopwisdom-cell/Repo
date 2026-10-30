// Execute the constructor extracted from Powercuff.x with isolated host adapters.
// No real notify registrations, hooks, power events or service operations occur.
#import <Foundation/Foundation.h>
#import <notify.h>
#import <os/log.h>
#import "PCRProtocol.h"
#import "PCRPreferences.h"
#import "PCRRuntime.h"
#include <assert.h>
#include <stdio.h>

static NSMutableArray<NSDictionary *> *Tasks, *Handlers;
static NSMutableDictionary<NSNumber *, NSString *> *Active;
static NSMutableDictionary<NSNumber *, NSNumber *> *States;
static NSDictionary *Preferences;
static NSString *ProcessName;
static const char *FailName;
static unsigned FailKind, Registrations, CancelCalls, ModePosts, RequestPosts, PreferenceReads, HookCalls;
static int NextToken;
static NSInteger MajorVersion;
static uint64_t Clock;
static BOOL FailCancellation, MissingLPMObserver, UnsupportedClasses, LowPower;
static void (^LPMHandler)(NSNotification *);

@interface PCRStartupDefaults : NSUserDefaults
@end
@implementation PCRStartupDefaults
- (NSDictionary *)persistentDomainForName:(NSString *)name {
    (void)name; ++PreferenceReads; return Preferences;
}
@end
@interface PCRStartupProcess : NSObject
+ (instancetype)processInfo;
- (NSString *)processName;
- (NSOperatingSystemVersion)operatingSystemVersion;
- (BOOL)lowPowerModeEnabled;
@end
@implementation PCRStartupProcess
+ (instancetype)processInfo { return [self new]; }
- (NSString *)processName { return ProcessName; }
- (NSOperatingSystemVersion)operatingSystemVersion {
    return (NSOperatingSystemVersion){MajorVersion, 5, 0};
}
- (BOOL)lowPowerModeEnabled { return LowPower; }
@end
@interface PCRStartupCenter : NSObject
+ (instancetype)defaultCenter;
- (id)addObserverForName:(NSString *)name object:(id)object queue:(NSOperationQueue *)queue
             usingBlock:(void (^)(NSNotification *))block;
@end
@implementation PCRStartupCenter
+ (instancetype)defaultCenter { return [self new]; }
- (id)addObserverForName:(NSString *)name object:(id)object queue:(NSOperationQueue *)queue
             usingBlock:(void (^)(NSNotification *))block {
    (void)name; (void)object; (void)queue;
    if (MissingLPMObserver) return nil;
    LPMHandler = [block copy]; return [NSObject new];
}
@end
@interface PCRStartupCommon : NSObject
- (id)initProduct:(id)argument;
- (void)putDeviceInThermalSimulationMode:(id)mode;
@end
@implementation PCRStartupCommon
- (id)initProduct:(id)argument { (void)argument; return self; }
- (void)putDeviceInThermalSimulationMode:(id)mode { (void)mode; assert(0 && "unexpected private dispatch"); }
@end
@interface PCRStartupInherited : PCRStartupCommon
@end
@implementation PCRStartupInherited
@end

static void Enqueue(uint64_t time, dispatch_block_t block) {
    [Tasks addObject:@{@"time": @(time), @"block": [block copy]}];
}
static dispatch_time_t TestTime(dispatch_time_t when, int64_t delta) {
    assert(when == DISPATCH_TIME_NOW && delta >= 0); return Clock + (uint64_t)delta;
}
static void TestAsync(dispatch_queue_t queue, dispatch_block_t block) { (void)queue; Enqueue(Clock, block); }
static void TestAfter(dispatch_time_t time, dispatch_queue_t queue, dispatch_block_t block) {
    (void)queue; Enqueue(time, block);
}
static uint32_t TestRegister(const char *name, int *token);
static uint32_t TestObserve(const char *name, int *token, dispatch_queue_t queue, void (^block)(int));
static uint32_t TestCancel(int token);
static uint32_t TestGetState(int token, uint64_t *state);
static uint32_t TestSetState(int token, uint64_t state);
static uint32_t TestPost(const char *name);
#define NSUserDefaults PCRStartupDefaults
#define NSProcessInfo PCRStartupProcess
#define dispatch_time TestTime
#define dispatch_async TestAsync
#define dispatch_after TestAfter
#define notify_register_check TestRegister
#define notify_register_dispatch TestObserve
#define notify_cancel TestCancel
#define notify_get_state TestGetState
#define notify_set_state TestSetState
#define notify_post TestPost
#import "PCRCore.h"

static uint32_t Register(const char *name, int *token, unsigned kind) {
    ++Registrations;
    if (FailKind == kind && FailName && strcmp(name, FailName) == 0) return 1;
    *token = NextToken++; Active[@(*token)] = [NSString stringWithUTF8String:name]; return NOTIFY_STATUS_OK;
}
static uint32_t TestRegister(const char *name, int *token) { return Register(name, token, 1); }
static uint32_t TestObserve(const char *name, int *token, dispatch_queue_t queue, void (^block)(int)) {
    assert(queue == PCRQueue);
    uint32_t status = Register(name, token, 2);
    if (status == NOTIFY_STATUS_OK) {
        int value = *token;
        [Handlers addObject:@{@"token": @(value), @"block": [block copy]}];
        // Emulate events already submitted to the queue while startup is incomplete.
        Enqueue(Clock, ^{ block(value); });
    }
    return status;
}
static uint32_t TestCancel(int token) {
    ++CancelCalls; assert(Active[@(token)]);
    if (FailCancellation) return 1;
    [Active removeObjectForKey:@(token)]; return NOTIFY_STATUS_OK;
}
static uint32_t TestGetState(int token, uint64_t *state) {
    NSNumber *value = States[@(token)];
    *state = value ? value.unsignedLongLongValue :
        ([Active[@(token)] isEqualToString:[NSString stringWithUTF8String:PCRRequest]] ? PCREncodeRequest(99) : 0);
    return NOTIFY_STATUS_OK;
}
static uint32_t TestSetState(int token, uint64_t state) {
    assert(token >= 0 && Active[@(token)]);
    States[@(token)] = @(state); return NOTIFY_STATUS_OK;
}
static uint32_t TestPost(const char *name) {
    if (strcmp(name, PCRThermalsChanged) == 0) ++ModePosts;
    if (strcmp(name, PCRRequest) == 0) ++RequestPosts;
    return NOTIFY_STATUS_OK;
}
static Class TestClass(const char *name) {
    if (UnsupportedClasses) return Nil;
    return strcmp(name, "CommonProduct") == 0 ? PCRStartupCommon.class : PCRStartupInherited.class;
}
static void TestInitCommon(void) { ++HookCalls; }
static void TestInitGP(void) { ++HookCalls; }
#define objc_getClass TestClass
#define NSNotificationCenter PCRStartupCenter
#include "startup-ctor.h"
#undef NSUserDefaults
#undef NSProcessInfo
#undef NSNotificationCenter
#undef objc_getClass
#undef dispatch_time
#undef dispatch_async
#undef dispatch_after
#undef notify_register_check
#undef notify_register_dispatch
#undef notify_cancel
#undef notify_get_state
#undef notify_set_state
#undef notify_post

static void Drain(void) {
    unsigned steps = 0;
    while (Tasks.count) {
        assert(++steps < 1000);
        NSUInteger first = 0;
        for (NSUInteger i = 1; i < Tasks.count; ++i)
            if ([Tasks[i][@"time"] unsignedLongLongValue] < [Tasks[first][@"time"] unsignedLongLongValue]) first = i;
        NSDictionary *task = Tasks[first]; Clock = [task[@"time"] unsignedLongLongValue];
        dispatch_block_t block = task[@"block"]; [Tasks removeObjectAtIndex:first]; block();
    }
}
static void Reset(NSString *name) {
    Tasks = [NSMutableArray new]; Handlers = [NSMutableArray new];
    Active = [NSMutableDictionary new]; States = [NSMutableDictionary new];
    Preferences = @{@"PowerMode": @2, @"RequireLowPowerMode": @YES};
    ProcessName = name; MajorVersion = 16; LowPower = YES;
    FailName = NULL; FailKind = Registrations = CancelCalls = ModePosts = RequestPosts = PreferenceReads = HookCalls = 0;
    FailCancellation = MissingLPMObserver = UnsupportedClasses = NO;
    NextToken = 20; Clock = 0; LPMHandler = nil; PCRLPMObserver = nil;
    PCRQueue = nil; PCRProduct = nil; PCRLog = OS_LOG_DEFAULT;
    PCRApplyFailed = PCRAwaitingReply = PCRRecoveryRequested = NO;
    PCRStateToken = PCRSettingsToken = PCRRequestToken = PCRUserSettingsToken = PCRRequestStateToken = -1;
    PCRLoadedToken = PCRHookToken = PCRAppliedToken = -1;
    PCRSession = PCRLastPublishedSession = 0; PCRLastApplied = PCRLastPublished = -1;
    PCRRequestGeneration = PCRGeneration = PCRApplyGeneration = PCRRefreshGeneration = 0;
    (void)TestCancel; (void)PCRCaptureProduct;
}
static void AssertLocalClosed(void) {
    assert(PCRStateToken == -1 && PCRRequestStateToken == -1 && PCRSettingsToken == -1 &&
           PCRRequestToken == -1 && PCRUserSettingsToken == -1);
}
static void AssertClosed(void) {
    AssertLocalClosed();
    for (NSString *name in Active.allValues)
        assert([name hasSuffix:@".loaded.s"] || [name hasSuffix:@".loaded.t"] ||
               [name hasSuffix:@".hook"] || [name hasSuffix:@".applied"]);
}
static void ReplayHandlers(void) {
    for (NSDictionary *entry in Handlers) {
        void (^block)(int) = entry[@"block"]; block([entry[@"token"] intValue]);
    }
    Drain();
}
int main(void) {
    @autoreleasepool {
        const char *publisherFailures[] = {PCRRequest, PCRSettingsChanged, PCRThermalsChanged, PCRRequest};
        unsigned kinds[] = {2, 2, 1, 1};
        for (unsigned i = 0; i < 4; ++i) {
            Reset(@"SpringBoard"); FailName = publisherFailures[i]; FailKind = kinds[i];
            PCRTestInitialize(); Drain();
            assert(ModePosts == 0 && RequestPosts == 0 && PreferenceReads == 0 && !LPMHandler);
            ReplayHandlers(); assert(ModePosts == 0 && RequestPosts == 0);
            AssertClosed(); assert(HookCalls == 0 && Tasks.count == 0);
        }
        puts("Startup: four publisher registration failures cannot leave a partial publisher PASS");

        const char *thermalFailures[] = {PCRThermalsChanged, PCRSettingsChanged, PCRThermalsChanged, PCRRequest};
        for (unsigned i = 0; i < 4; ++i) {
            Reset(@"thermalmonitord"); FailName = thermalFailures[i]; FailKind = i < 2 ? 2 : 1;
            PCRTestInitialize(); Drain(); ReplayHandlers();
            AssertClosed(); assert(HookCalls == 0 && ModePosts == 0 && RequestPosts == 0);
        }
        puts("Startup: four daemon registration failures leave no hooks or communication PASS");

        Reset(@"SpringBoard"); MissingLPMObserver = YES; PCRTestInitialize(); Drain(); ReplayHandlers();
        AssertClosed(); assert(ModePosts == 0 && PreferenceReads == 0 && Tasks.count == 0);
        puts("Startup: missing LPM observer disables the publisher before any profile is sent PASS");

        Reset(@"SpringBoard"); PCRTestInitialize(); Drain();
        assert(LPMHandler && ModePosts == 5 && PreferenceReads == 5 && Clock == 60 * NSEC_PER_SEC);
        unsigned mode = 99;
        assert(PCRDecodeMode([States[@(PCRStateToken)] unsignedLongLongValue], 99, &mode) && mode == 2);
        LowPower = NO; LPMHandler(nil); Drain();
        assert(ModePosts == 8 && PCRDecodeMode([States[@(PCRStateToken)] unsignedLongLongValue], 99, &mode) && mode == 0);
        assert([Preferences[@"PowerMode"] integerValue] == 2);
        puts("Startup: early queued events wait for activation; finite startup and LPM Off still work PASS");

        Reset(@"SpringBoard"); FailName = PCRRequest; FailKind = 2; FailCancellation = YES;
        PCRTestInitialize(); Drain(); ReplayHandlers();
        AssertLocalClosed(); assert(CancelCalls == 3 && ModePosts == 0 && RequestPosts == 0 && Tasks.count == 0);
        puts("Startup: failed cancellation and already queued callbacks cannot reactivate a failed publisher PASS");

        Reset(@"thermalmonitord"); UnsupportedClasses = YES; PCRTestInitialize(); Drain(); ReplayHandlers();
        AssertClosed(); assert(HookCalls == 0 && ModePosts == 0 && RequestPosts == 0);
        assert([States[@(PCRAppliedToken)] unsignedLongLongValue] == 99);
        puts("Startup: unsupported thermal classes retain ABI diagnostic and close communication PASS");

        for (unsigned i = 0; i < 2; ++i) {
            Reset(i ? @"SpringBoard" : @"other-process"); if (i) MajorVersion = 17;
            PCRTestInitialize(); Drain(); assert(Registrations == 0 && ModePosts == 0 && HookCalls == 0);
        }
        puts("Startup: unsupported process or OS performs no registration or publication PASS");

        const char *diagnostics[] = {"com.minis.powercuff-baldaran-trusted.loaded.t",
                                    "com.minis.powercuff-baldaran-trusted.hook",
                                    "com.minis.powercuff-baldaran-trusted.applied"};
        for (unsigned i = 0; i < 3; ++i) {
            Reset(@"thermalmonitord"); FailName = diagnostics[i]; FailKind = 1;
            PCRTestInitialize(); Drain();
            assert(HookCalls == 1 && PCRStateToken >= 0 && PCRRequestStateToken >= 0 &&
                   PCRSettingsToken >= 0 && PCRUserSettingsToken >= 0);
        }
        puts("Startup: optional diagnostic failures do not replace mandatory readiness checks PASS");
    }
}
