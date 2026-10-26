#import <Foundation/Foundation.h>
#import "PCRRuntime.h"
#include <assert.h>
#include <stdio.h>
static id SharedInit(id self, SEL cmd, id arg) { (void)cmd; (void)arg; return self; }
static Class MakeClass(const char *name, Class base, BOOL own) {
    Class cls = objc_allocateClassPair(base, name, 0);
    assert(cls);
    if (own) assert(class_addMethod(cls, sel_registerName("initProduct:"), (IMP)SharedInit, "@@:@"));
    objc_registerClassPair(cls);
    return cls;
}
int main(void) {
    @autoreleasepool {
        SEL init = sel_registerName("initProduct:");
        Class base = MakeClass("PCRTestBase", NSObject.class, YES);
        Class inherited = MakeClass("PCRTestInherited", base, NO);
        Class alias = MakeClass("PCRTestAlias", base, YES);
        Class unrelated = MakeClass("PCRTestUnrelated", NSObject.class, YES);
        assert(class_getMethodImplementation(base, init) == class_getMethodImplementation(alias, init));
        assert(class_getMethodImplementation(base, init) == class_getMethodImplementation(unrelated, init));
        assert(!PCRNeedsSeparateHook(base, base, init));
        assert(!PCRNeedsSeparateHook(inherited, base, init));
        assert(PCRNeedsSeparateHook(alias, base, init));
        assert(PCRNeedsSeparateHook(unrelated, base, init));
        assert(!PCRNeedsSeparateHook(Nil, base, init));
        puts("Runtime: inherited initializer skipped; aliased and unrelated equal-IMP methods require hooks PASS");
    }
}
