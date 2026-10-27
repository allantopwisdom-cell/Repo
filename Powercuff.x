#import "PCRCore.h"

static id PCRLPMObserver;

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
