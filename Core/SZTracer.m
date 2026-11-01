#import "SZTracer.h"
#import <objc/message.h>
#import <os/lock.h>
#import <pthread.h>
#import <mach/mach_time.h>
#import <stdatomic.h>

NSErrorDomain const SZTracerErrorDomain = @"SZTracerErrorDomain";

static const NSUInteger kOSMaxBufferedEvents = 20000;

@interface SZTracedMethod : NSObject {
@public
    Class _targetClass;        // class, or metaclass for class methods
    SEL _selector;
    SEL _aliasSelector;
    IMP _originalIMP;
    IMP _forwardIMP;
    BOOL _isClassMethod;
    NSString *_typeEncoding;
    NSString *_className;
}
@end
@implementation SZTracedMethod
@end

// Table and event buffer use separate locks: the hook may enqueue an event (holding the event lock) while
// a nested call on the same thread needs a table lookup.
static os_unfair_lock gTableLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock gEventLock = OS_UNFAIR_LOCK_INIT;
static CFMutableDictionaryRef gTable;               // Class -> CFMutableDictionaryRef (SEL -> SZTracedMethod)
static NSMutableArray<SZTraceEvent *> *gEvents;
static uint64_t gDropped;
static uint64_t gTotal;
static _Atomic uint64_t gSequence;
static NSUInteger gTracedCount;
static SEL gAliasForwardSel;
static NSString *gOwnImagePath;
static mach_timebase_info_data_t gTimebase;
static _Thread_local BOOL tInHook;
static _Thread_local NSUInteger tDepth;

static void SZForwardInvocationHook(id self, SEL _cmd, NSInvocation *invocation);

static void SZTracerInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gTable = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        gEvents = [NSMutableArray array];
        gAliasForwardSel = sel_registerName("__swizzlescope_forwardInvocation:");
        mach_timebase_info(&gTimebase);
        const char *img = class_getImageName([SZTracer class]);
        gOwnImagePath = img ? @(img) : nil;
    });
}

#pragma mark - Table

static SZTracedMethod *SZLookupExact(Class target, SEL sel) {
    CFDictionaryRef sels = CFDictionaryGetValue(gTable, (__bridge const void *)target);
    return sels ? (__bridge SZTracedMethod *)CFDictionaryGetValue(sels, sel) : nil;
}

static SZTracedMethod *SZLookupRecord(Class cls, SEL sel) {
    SZTracedMethod *found = nil;
    os_unfair_lock_lock(&gTableLock);
    for (Class c = cls; c != Nil && !found; c = class_getSuperclass(c)) {
        found = SZLookupExact(c, sel);
    }
    os_unfair_lock_unlock(&gTableLock);
    return found;
}

static void SZInsertRecord(SZTracedMethod *record) {
    os_unfair_lock_lock(&gTableLock);
    CFMutableDictionaryRef sels = (CFMutableDictionaryRef)CFDictionaryGetValue(gTable, (__bridge const void *)record->_targetClass);
    if (!sels) {
        sels = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(gTable, (__bridge const void *)record->_targetClass, sels);
        CFRelease(sels);
    }
    CFDictionarySetValue(sels, record->_selector, (__bridge const void *)record);
    gTracedCount++;
    os_unfair_lock_unlock(&gTableLock);
}

static SZTracedMethod *SZRemoveRecord(Class target, SEL sel) {
    os_unfair_lock_lock(&gTableLock);
    SZTracedMethod *record = SZLookupExact(target, sel);
    if (record) {
        CFMutableDictionaryRef sels = (CFMutableDictionaryRef)CFDictionaryGetValue(gTable, (__bridge const void *)target);
        CFDictionaryRemoveValue(sels, sel);
        if (CFDictionaryGetCount(sels) == 0) CFDictionaryRemoveValue(gTable, (__bridge const void *)target);
        gTracedCount--;
    }
    os_unfair_lock_unlock(&gTableLock);
    return record;
}

static NSArray<SZTracedMethod *> *SZAllRecords(void) {
    NSMutableArray<SZTracedMethod *> *out = [NSMutableArray array];
    os_unfair_lock_lock(&gTableLock);
    CFIndex classCount = CFDictionaryGetCount(gTable);
    if (classCount > 0) {
        const void **values = calloc((size_t)classCount, sizeof(void *));
        CFDictionaryGetKeysAndValues(gTable, NULL, values);
        for (CFIndex i = 0; i < classCount; i++) {
            CFDictionaryRef sels = values[i];
            CFIndex selCount = CFDictionaryGetCount(sels);
            const void **records = calloc((size_t)selCount, sizeof(void *));
            CFDictionaryGetKeysAndValues(sels, NULL, records);
            for (CFIndex j = 0; j < selCount; j++) [out addObject:(__bridge SZTracedMethod *)records[j]];
            free(records);
        }
        free(values);
    }
    os_unfair_lock_unlock(&gTableLock);
    return out;
}

#pragma mark - Events

static SZTraceEvent *SZBuildEvent(id self, SZTracedMethod *record, NSInvocation *invocation) {
    SZTraceEvent *event = [[SZTraceEvent alloc] init];
    event.sequence = atomic_fetch_add(&gSequence, 1) + 1;
    event.isClassMethod = record->_isClassMethod;
    event.className = record->_className;
    Class receiverClass = record->_isClassMethod ? (Class)self : object_getClass(self);
    event.receiverClassName = @(class_getName(receiverClass));
    event.receiverAddress = (uintptr_t)self;
    event.selectorName = NSStringFromSelector(record->_selector);
    if (pthread_main_np()) {
        event.threadName = @"main";
    } else {
        uint64_t tid = 0;
        pthread_threadid_np(NULL, &tid);
        event.threadName = [NSString stringWithFormat:@"thread %llu", tid];
    }
    NSMethodSignature *signature = invocation.methodSignature;
    NSUInteger count = signature.numberOfArguments;
    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 2; i < count; i++) {
        const char *type = [signature getArgumentTypeAtIndex:i];
        NSUInteger size = 0;
        @try { NSGetSizeAndAlignment(type, &size, NULL); } @catch (NSException *e) { size = 0; }
        if (size == 0) { [args addObject:@"?"]; continue; }
        void *buffer = calloc(1, size < 16 ? 16 : size);
        [invocation getArgument:buffer atIndex:(NSInteger)i];
        [args addObject:SZDescribeValue(type, buffer)];
        free(buffer);
    }
    event.argumentDescriptions = args;
    return event;
}

static void SZFinishEvent(SZTraceEvent *event, NSInvocation *invocation, uint64_t start, uint64_t end, NSUInteger depth) {
    NSMethodSignature *signature = invocation.methodSignature;
    const char *returnType = signature.methodReturnType;
    NSUInteger length = signature.methodReturnLength;
    if (length == 0) {
        event.returnDescription = @"void";
    } else {
        void *buffer = calloc(1, length < 16 ? 16 : length);
        [invocation getReturnValue:buffer];
        event.returnDescription = SZDescribeValue(returnType, buffer);
        free(buffer);
    }
    event.durationNanoseconds = (end - start) * gTimebase.numer / gTimebase.denom;
    event.depth = depth;
}

static void SZEnqueue(SZTraceEvent *event) {
    os_unfair_lock_lock(&gEventLock);
    if (gEvents.count >= kOSMaxBufferedEvents) {
        [gEvents removeObjectAtIndex:0];
        gDropped++;
    }
    [gEvents addObject:event];
    gTotal++;
    os_unfair_lock_unlock(&gEventLock);
}

#pragma mark - Hook

static void SZForwardInvocationHook(id self, SEL _cmd, NSInvocation *invocation) {
    SEL selector = invocation.selector;
    Class cls = object_getClass(self);
    SZTracedMethod *record = SZLookupRecord(cls, selector);
    if (!record) {
        ((void (*)(id, SEL, NSInvocation *))objc_msgSend)(self, gAliasForwardSel, invocation);
        return;
    }
    if (tInHook) {
        // Re-entered while describing or enqueueing an event: call through silently.
        invocation.selector = record->_aliasSelector;
        [invocation invoke];
        return;
    }
    tInHook = YES;
    SZTraceEvent *event = SZBuildEvent(self, record, invocation);
    tInHook = NO;

    NSUInteger depth = tDepth++;
    uint64_t start = mach_absolute_time();
    uint64_t end = start;
    invocation.selector = record->_aliasSelector;
    @try {
        [invocation invoke];
    } @finally {
        end = mach_absolute_time();
        tDepth--;
    }

    tInHook = YES;
    SZFinishEvent(event, invocation, start, end, depth);
    SZEnqueue(event);
    tInHook = NO;
}

static BOOL SZInstallForwardingHook(Class target) {
    SEL forwardSel = @selector(forwardInvocation:);
    Method method = class_getInstanceMethod(target, forwardSel);
    if (!method) return NO;
    IMP original = method_getImplementation(method);
    if (original == (IMP)SZForwardInvocationHook) return YES;   // already hooked here or on an ancestor
    const char *encoding = method_getTypeEncoding(method);
    if (!class_addMethod(target, gAliasForwardSel, original, encoding)) {
        class_replaceMethod(target, gAliasForwardSel, original, encoding);
    }
    class_replaceMethod(target, forwardSel, (IMP)SZForwardInvocationHook, encoding);
    return YES;
}

static IMP SZForwardIMPForEncoding(const char *encoding) {
#if defined(__x86_64__)
    const char *p = encoding;
    while (*p && strchr("rnNoORVAj", *p)) p++;
    if (*p == '{' || *p == '(') {
        NSUInteger size = 0;
        @try { NSGetSizeAndAlignment(p, &size, NULL); } @catch (NSException *e) { size = 0; }
        if (size > 16) return (IMP)_objc_msgForward_stret;
    }
#else
    (void)encoding;
#endif
    return (IMP)_objc_msgForward;
}

static SEL SZAliasSelector(SEL selector) {
    char buffer[1024];
    snprintf(buffer, sizeof buffer, "__swizzlescope_%s", sel_getName(selector));
    return sel_registerName(buffer);
}

static BOOL SZIsSubclass(Class cls, Class ancestor) {
    for (Class c = class_getSuperclass(cls); c != Nil; c = class_getSuperclass(c)) {
        if (c == ancestor) return YES;
    }
    return NO;
}

#pragma mark - Public API

@implementation SZTracer

+ (instancetype)sharedTracer {
    static SZTracer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SZTracerInit();
        shared = [[SZTracer alloc] init];
    });
    return shared;
}

+ (BOOL)canTraceClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod reason:(NSString *__autoreleasing *)reason {
    SZTracerInit();
    NSString *why = nil;
    Class target = isClassMethod ? object_getClass(cls) : cls;
    const char *className = cls ? class_getName(cls) : "";
    const char *selName = selector ? sel_getName(selector) : "";

    static NSSet<NSString *> *blockedClasses;
    static NSSet<NSString *> *blockedSelectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        blockedClasses = [NSSet setWithArray:@[@"NSObject", @"NSProxy", @"NSInvocation", @"NSMethodSignature",
                                              @"NSAutoreleasePool", @"__NSAtom", @"Object"]];
        blockedSelectors = [NSSet setWithArray:@[
            @"retain", @"release", @"autorelease", @"dealloc", @"retainCount", @"_tryRetain", @"_isDeallocating",
            @"allowsWeakReference", @"retainWeakReference", @"initialize", @"load", @"class", @"self", @"superclass",
            @"isKindOfClass:", @"isMemberOfClass:", @"respondsToSelector:", @"conformsToProtocol:",
            @"forwardInvocation:", @"methodSignatureForSelector:", @"forwardingTargetForSelector:",
            @"doesNotRecognizeSelector:", @"resolveInstanceMethod:", @"resolveClassMethod:",
            @"instanceMethodSignatureForSelector:", @"instancesRespondToSelector:", @"isProxy", @"zone",
            @"methodForSelector:", @"instanceMethodForSelector:", @"performSelector:", @"performSelector:withObject:",
            @"performSelector:withObject:withObject:", @"alloc", @"allocWithZone:", @"new", @"copy", @"mutableCopy",
            @"copyWithZone:", @"mutableCopyWithZone:", @"hash", @"isEqual:",
        ]];
    });

    if (!cls || !selector) {
        why = @"Missing class or selector";
    } else if ([blockedClasses containsObject:@(className)]) {
        why = [NSString stringWithFormat:@"%s is a root or forwarding-machinery class and cannot be traced", className];
    } else if ([blockedSelectors containsObject:@(selName)] || selName[0] == '.') {
        why = [NSString stringWithFormat:@"%s is used by the runtime or the tracer itself and cannot be traced", selName];
    } else if (strncmp(selName, "__swizzlescope_", 12) == 0) {
        why = @"Swizzlescope alias selectors cannot be traced";
    } else {
        const char *img = class_getImageName(cls);
        if (img && gOwnImagePath && strcmp(img, gOwnImagePath.UTF8String) == 0) {
            why = @"Swizzlescope's own classes cannot be traced";
        }
    }
    Method method = why ? NULL : class_getInstanceMethod(target, selector);
    if (!why && !method) {
        why = [NSString stringWithFormat:@"%s does not implement or inherit %c%s", className, isClassMethod ? '+' : '-', selName];
    }
    if (!why) {
        Class root = objc_getClass("NSObject");
        if (method == class_getInstanceMethod(root, selector) || method == class_getInstanceMethod(object_getClass(root), selector)) {
            why = [NSString stringWithFormat:@"%c%s resolves to NSObject's root implementation, which cannot be traced safely", isClassMethod ? '+' : '-', selName];
        }
    }
    if (!why && !class_getInstanceMethod(target, @selector(forwardInvocation:))) {
        why = [NSString stringWithFormat:@"%s does not support message forwarding", className];
    }
    if (!why) {
        const char *encoding = method_getTypeEncoding(method);
        NSMethodSignature *signature = nil;
        @try { signature = encoding ? [NSMethodSignature signatureWithObjCTypes:encoding] : nil; } @catch (NSException *e) { signature = nil; }
        if (!signature) why = [NSString stringWithFormat:@"Type encoding %s is not supported by NSInvocation", encoding ?: "(null)"];
    }
    if (!why) {
        os_unfair_lock_lock(&gTableLock);
        for (Class c = class_getSuperclass(target); c != Nil && !why; c = class_getSuperclass(c)) {
            if (SZLookupExact(c, selector)) {
                why = [NSString stringWithFormat:@"%s is already traced on superclass %s; untrace it first", selName, class_getName(c)];
            }
        }
        if (!why) {
            CFIndex count = CFDictionaryGetCount(gTable);
            const void **keys = calloc((size_t)(count ?: 1), sizeof(void *));
            CFDictionaryGetKeysAndValues(gTable, keys, NULL);
            for (CFIndex i = 0; i < count && !why; i++) {
                Class other = (__bridge Class)keys[i];
                if (other != target && SZIsSubclass(other, target) && SZLookupExact(other, selector)) {
                    why = [NSString stringWithFormat:@"%s is already traced on subclass %s; untrace it first", selName, class_getName(other)];
                }
            }
            free(keys);
        }
        os_unfair_lock_unlock(&gTableLock);
    }
    if (reason) *reason = why;
    return why == nil;
}

- (BOOL)traceClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod error:(NSError **)error {
    SZTracerInit();
    Class target = isClassMethod ? object_getClass(cls) : cls;
    if ([self isTracingClass:cls selector:selector isClassMethod:isClassMethod]) return YES;

    NSString *reason = nil;
    if (![SZTracer canTraceClass:cls selector:selector isClassMethod:isClassMethod reason:&reason]) {
        if (error) *error = [NSError errorWithDomain:SZTracerErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: reason ?: @"Cannot trace"}];
        return NO;
    }

    Method method = class_getInstanceMethod(target, selector);
    const char *encoding = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);
    IMP forward = SZForwardIMPForEncoding(encoding);
    if (original == forward || original == (IMP)_objc_msgForward) {
        if (error) *error = [NSError errorWithDomain:SZTracerErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Method already forwards; something else has hooked it"}];
        return NO;
    }
    if (!SZInstallForwardingHook(target)) {
        if (error) *error = [NSError errorWithDomain:SZTracerErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Could not install forwardInvocation: hook"}];
        return NO;
    }

    Class superTarget = class_getSuperclass(target);
    BOOL inherited = superTarget && class_getInstanceMethod(superTarget, selector) == method;
    SEL alias = SZAliasSelector(selector);
    if (!class_addMethod(target, alias, original, encoding)) {
        class_replaceMethod(target, alias, original, encoding);
    }
    if (inherited) {
        class_addMethod(target, selector, forward, encoding);
    } else {
        method_setImplementation(method, forward);
    }

    SZTracedMethod *record = [[SZTracedMethod alloc] init];
    record->_targetClass = target;
    record->_selector = selector;
    record->_aliasSelector = alias;
    record->_originalIMP = original;
    record->_forwardIMP = forward;
    record->_isClassMethod = isClassMethod;
    record->_typeEncoding = @(encoding);
    record->_className = @(class_getName(cls));
    SZInsertRecord(record);
    return YES;
}

- (BOOL)untraceClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod {
    SZTracerInit();
    Class target = isClassMethod ? object_getClass(cls) : cls;
    SZTracedMethod *record = SZRemoveRecord(target, selector);
    if (!record) return NO;
    class_replaceMethod(target, selector, record->_originalIMP, record->_typeEncoding.UTF8String);
    return YES;
}

- (BOOL)isTracingClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod {
    SZTracerInit();
    Class target = isClassMethod ? object_getClass(cls) : cls;
    os_unfair_lock_lock(&gTableLock);
    BOOL tracing = SZLookupExact(target, selector) != nil;
    os_unfair_lock_unlock(&gTableLock);
    return tracing;
}

- (void)untraceAll {
    SZTracerInit();
    for (SZTracedMethod *record in SZAllRecords()) {
        SZRemoveRecord(record->_targetClass, record->_selector);
        class_replaceMethod(record->_targetClass, record->_selector, record->_originalIMP, record->_typeEncoding.UTF8String);
    }
}

- (NSArray<NSString *> *)tracedMethodNames {
    SZTracerInit();
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (SZTracedMethod *record in SZAllRecords()) {
        [names addObject:[NSString stringWithFormat:@"%@[%@ %@]", record->_isClassMethod ? @"+" : @"-", record->_className, NSStringFromSelector(record->_selector)]];
    }
    [names sortUsingSelector:@selector(compare:)];
    return names;
}

- (NSUInteger)tracedMethodCount {
    SZTracerInit();
    os_unfair_lock_lock(&gTableLock);
    NSUInteger count = gTracedCount;
    os_unfair_lock_unlock(&gTableLock);
    return count;
}

- (NSArray<SZTraceEvent *> *)drainEvents {
    SZTracerInit();
    os_unfair_lock_lock(&gEventLock);
    NSArray *events = [gEvents copy];
    [gEvents removeAllObjects];
    os_unfair_lock_unlock(&gEventLock);
    return events;
}

- (uint64_t)droppedEventCount {
    SZTracerInit();
    os_unfair_lock_lock(&gEventLock);
    uint64_t dropped = gDropped;
    os_unfair_lock_unlock(&gEventLock);
    return dropped;
}

- (uint64_t)totalEventCount {
    SZTracerInit();
    os_unfair_lock_lock(&gEventLock);
    uint64_t total = gTotal;
    os_unfair_lock_unlock(&gEventLock);
    return total;
}

@end
