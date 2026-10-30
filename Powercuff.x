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
        if (!PCRPrepareCommunication(isThermal)) return;
        if (isThermal) {
            Class common = objc_getClass("CommonProduct"), gp = objc_getClass("GPProduct");
            SEL init = @selector(initProduct:), apply = @selector(putDeviceInThermalSimulationMode:);
            BOOL commonOK = PCRMethodMatches(common, init, '@') && PCRMethodMatches(common, apply, 'v');
            // Compare BEFORE hooking: an inherited method needs only the base-class hook.
            BOOL gpOK = PCRMethodMatches(gp, init, '@') && PCRMethodMatches(gp, apply, 'v') &&
                (!commonOK || PCRNeedsSeparateHook(gp, common, init));
            if (!commonOK && !gpOK) {
                PCRDiagnostic(PCRAppliedToken, 99);
                os_log_error(PCRLog, "no supported thermal initializer/API ABI; hooks disabled");
                PCRAbortCommunicationSetup();
                return;
            }
            // Queue activation before installing hooks so captured products are
            // queued after readiness on the daemon's main queue.
            PCRActivateCommunication(YES);
            if (commonOK) { %init(PCRCommonHooks); }
            if (gpOK) { %init(PCRGPHooks); }
        } else {
            PCRLPMObserver = [NSNotificationCenter.defaultCenter
                addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
                    (void)note; dispatch_async(PCRQueue, ^{
                        if (PCRCommunicationReady) PCRRefreshPreferences();
                    });
                }];
            if (!PCRLPMObserver) {
                os_log_error(PCRLog, "LPM observer unavailable; publisher disabled");
                PCRAbortCommunicationSetup();
                return;
            }
            PCRActivateCommunication(NO);
        }
    }
}
