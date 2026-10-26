#ifndef PCR_RUNTIME_H
#define PCR_RUNTIME_H
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
// @? is a block, not a normal object argument. Never send a string to a block ABI.
static inline BOOL PCRObjectEncoding(const char *type) {
    if (!type || type[0] != '@') return NO;
    size_t length = strlen(type);
    return length == 1 || (length >= 3 && type[1] == '"' && type[length - 1] == '"');
}
static inline BOOL PCRMethodMatches(Class cls, SEL selector, char returnType) {
    if (!cls) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char *ret = method_copyReturnType(method);
    char *arg = method_copyArgumentType(method, 2);
    char *selfType = method_copyArgumentType(method, 0);
    char *cmdType = method_copyArgumentType(method, 1);
    BOOL valid = ret && arg && selfType && cmdType &&
        (returnType == '@' ? PCRObjectEncoding(ret) : strcmp(ret, "v") == 0 && returnType == 'v') &&
        PCRObjectEncoding(arg) && strcmp(selfType, "@") == 0 && strcmp(cmdType, ":") == 0;
    free(ret); free(arg); free(selfType); free(cmdType);
    return valid;
}
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
