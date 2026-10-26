#ifndef PCR_RUNTIME_H
#define PCR_RUNTIME_H
#import <objc/runtime.h>
#include <stdlib.h>
// Determine actual method ownership. Equal IMPs do not prove inheritance.
static inline BOOL PCRDefinesMethod(Class cls, SEL selector) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned i = 0; i < count; ++i) {
        if (sel_isEqual(method_getName(methods[i]), selector)) { found = YES; break; }
    }
    free(methods);
    return found;
}
static inline BOOL PCRNeedsSeparateHook(Class candidate, Class hookedBase, SEL selector) {
    if (!candidate) return NO;
    for (Class cls = candidate; cls; cls = class_getSuperclass(cls)) {
        if (cls == hookedBase) return NO;
        if (PCRDefinesMethod(cls, selector)) return YES;
    }
    return YES;
}
#endif
