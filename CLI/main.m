// swizzlescope: command-line twin of the Swizzlescope app. Doubles as the test harness.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "SZRuntime.h"
#import "SZClassInfo.h"
#import "SZHeaderWriter.h"
#import "SZLoader.h"
#import "SZTracer.h"
#import "SZValueParser.h"
#import "SZTraceEvent.h"

static void SZPrint(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void SZPrint(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fputs(s.UTF8String, stdout);
    fputs("\n", stdout);
}

static int SZFail(NSString *message) {
    fprintf(stderr, "swizzlescope: %s\n", message.UTF8String);
    return 1;
}

static void SZUsage(void) {
    fputs("usage:\n"
          "  swizzlescope images                         list loaded images with class counts\n"
          "  swizzlescope classes <image-or-path>        list classes in an image (substring) or a bundle to load\n"
          "  swizzlescope dump <Class> [bundle]          detailed metadata for a class\n"
          "  swizzlescope header <Class> [bundle]        class-dump style header\n"
          "  swizzlescope search <fragment> [bundle]     classes implementing a selector containing fragment\n"
          "  swizzlescope load <path>                    load a bundle and report what it contributed\n"
          "  swizzlescope trace <bundle|-> --run <spec> <spec>...\n"
          "                                           trace the methods named by specs, run the --run method, print events\n"
          "  swizzlescope call <bundle|-> <spec> [arg ...]   send a message with typed arguments and print the result\n"
          "  spec syntax: '-[Class selector:]' or '+[Class selector]'\n", stderr);
}

static BOOL SZLoad(NSString *path, NSString **imagePath) {
    NSError *error = nil;
    if (![SZLoader loadBundleAtPath:path loadedImagePath:imagePath error:&error]) {
        SZFail(error.localizedDescription);
        return NO;
    }
    return YES;
}

static BOOL SZParseSpec(NSString *spec, BOOL *isClassMethod, NSString **className, NSString **selectorName) {
    if (spec.length < 5) return NO;
    unichar kind = [spec characterAtIndex:0];
    if ((kind != '+' && kind != '-') || [spec characterAtIndex:1] != '[' || ![spec hasSuffix:@"]"]) return NO;
    NSString *inner = [spec substringWithRange:NSMakeRange(2, spec.length - 3)];
    NSRange space = [inner rangeOfString:@" "];
    if (space.location == NSNotFound) return NO;
    *className = [inner substringToIndex:space.location];
    *selectorName = [[inner substringFromIndex:space.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    *isClassMethod = (kind == '+');
    return className && selectorName && (*selectorName).length > 0;
}

static int SZCommandImages(void) {
    for (SZImage *image in [SZRuntime loadedImages]) {
        SZPrint(@"%6lu  %@", (unsigned long)image.classCount, image.path);
    }
    return 0;
}

static int SZCommandClasses(NSString *target) {
    if ([NSFileManager.defaultManager fileExistsAtPath:target]) {
        NSString *imagePath = nil;
        if (!SZLoad(target, &imagePath)) return 1;
        NSArray *names = [SZRuntime classNamesInImagePath:imagePath];
        if (names.count == 0) return SZFail([NSString stringWithFormat:@"%@ loaded but contributes no Objective-C classes", target]);
        for (NSString *name in names) SZPrint(@"%@", name);
        return 0;
    }
    BOOL any = NO;
    for (SZImage *image in [SZRuntime loadedImages]) {
        if ([image.path rangeOfString:target options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        any = YES;
        SZPrint(@"== %@", image.path);
        for (NSString *name in [SZRuntime classNamesInImagePath:image.path]) SZPrint(@"%@", name);
    }
    return any ? 0 : SZFail([NSString stringWithFormat:@"no loaded image matches '%@' and no file exists at that path", target]);
}

static SZClassInfo *SZInfoForArgs(NSArray<NSString *> *args, NSUInteger index) {
    if (args.count <= index) { SZUsage(); return nil; }
    if (args.count > index + 1 && !SZLoad(args[index + 1], NULL)) return nil;
    SZClassInfo *info = [SZClassInfo infoForClassNamed:args[index]];
    if (!info) SZFail([NSString stringWithFormat:@"class %@ is not loaded", args[index]]);
    return info;
}

static int SZCommandDump(NSArray<NSString *> *args) {
    SZClassInfo *info = SZInfoForArgs(args, 2);
    if (!info) return 1;
    SZPrint(@"Class: %@", info.name);
    SZPrint(@"Superclass chain: %@", info.superclassChain.count ? [info.superclassChain componentsJoinedByString:@" : "] : @"(root)");
    SZPrint(@"Image: %@", info.imagePath ?: @"(dynamic, no image)");
    SZPrint(@"Instance size: %zu bytes", info.instanceSize);
    SZPrint(@"Protocols: %@", info.protocolNames.count ? [info.protocolNames componentsJoinedByString:@", "] : @"(none)");
    SZPrint(@"\nIvars (%lu):", (unsigned long)info.ivars.count);
    for (SZIvarInfo *ivar in info.ivars) SZPrint(@"  @%-4ld %@\t// %@", (long)ivar.offset, ivar.declaration, ivar.typeEncoding);
    SZPrint(@"\nProperties (%lu):", (unsigned long)info.properties.count);
    for (SZPropertyInfo *prop in info.properties) SZPrint(@"  %@\t// %@", prop.declaration, prop.attributes);
    SZPrint(@"\nClass methods (%lu):", (unsigned long)info.classMethods.count);
    for (SZMethodInfo *m in info.classMethods) SZPrint(@"  %@\t// %@", m.declaration, m.typeEncoding);
    SZPrint(@"\nInstance methods (%lu):", (unsigned long)info.instanceMethods.count);
    for (SZMethodInfo *m in info.instanceMethods) SZPrint(@"  %@\t// %@", m.declaration, m.typeEncoding);
    return 0;
}

static int SZCommandHeader(NSArray<NSString *> *args) {
    SZClassInfo *info = SZInfoForArgs(args, 2);
    if (!info) return 1;
    fputs([SZHeaderWriter headerForClass:info].UTF8String, stdout);
    return 0;
}

static int SZCommandSearch(NSArray<NSString *> *args) {
    if (args.count < 3) { SZUsage(); return 2; }
    if (args.count > 3 && !SZLoad(args[3], NULL)) return 1;
    for (NSString *name in [SZRuntime classNamesImplementingSelectorContaining:args[2]]) SZPrint(@"%@", name);
    return 0;
}

static int SZCommandLoad(NSArray<NSString *> *args) {
    if (args.count < 3) { SZUsage(); return 2; }
    NSString *imagePath = nil;
    if (!SZLoad(args[2], &imagePath)) return 1;
    NSArray *names = [SZRuntime classNamesInImagePath:imagePath];
    SZPrint(@"loaded %@", imagePath);
    SZPrint(@"%lu Objective-C classes", (unsigned long)names.count);
    return 0;
}

static int SZCommandTrace(NSArray<NSString *> *args) {
    if (args.count < 5) { SZUsage(); return 2; }
    NSString *bundle = args[2];
    if (![bundle isEqualToString:@"-"] && !SZLoad(bundle, NULL)) return 1;

    NSString *runSpec = nil;
    NSMutableArray<NSString *> *specs = [NSMutableArray array];
    for (NSUInteger i = 3; i < args.count; i++) {
        if ([args[i] isEqualToString:@"--run"]) {
            if (i + 1 >= args.count) { SZUsage(); return 2; }
            runSpec = args[++i];
        } else {
            [specs addObject:args[i]];
        }
    }
    if (!runSpec || specs.count == 0) { SZUsage(); return 2; }

    SZTracer *tracer = [SZTracer sharedTracer];
    for (NSString *spec in specs) {
        BOOL isClassMethod = NO;
        NSString *className = nil, *selectorName = nil;
        if (!SZParseSpec(spec, &isClassMethod, &className, &selectorName)) return SZFail([NSString stringWithFormat:@"bad spec '%@'", spec]);
        Class cls = [SZRuntime classNamed:className];
        if (!cls) return SZFail([NSString stringWithFormat:@"class %@ is not loaded", className]);
        NSError *error = nil;
        if (![tracer traceClass:cls selector:NSSelectorFromString(selectorName) isClassMethod:isClassMethod error:&error]) {
            return SZFail([NSString stringWithFormat:@"cannot trace %@: %@", spec, error.localizedDescription]);
        }
    }

    BOOL runIsClassMethod = NO;
    NSString *runClass = nil, *runSelector = nil;
    if (!SZParseSpec(runSpec, &runIsClassMethod, &runClass, &runSelector)) return SZFail([NSString stringWithFormat:@"bad --run spec '%@'", runSpec]);
    if ([runSelector containsString:@":"]) return SZFail(@"--run method must take no arguments");
    Class cls = [SZRuntime classNamed:runClass];
    if (!cls) return SZFail([NSString stringWithFormat:@"class %@ is not loaded", runClass]);
    SEL sel = NSSelectorFromString(runSelector);
    id receiver = runIsClassMethod ? (id)cls : [[cls alloc] init];
    if (![receiver respondsToSelector:sel]) return SZFail([NSString stringWithFormat:@"%@ does not respond to %@", runClass, runSelector]);
    // Return value is discarded, so any scalar or void return is fine.
    ((void (*)(id, SEL))objc_msgSend)(receiver, sel);

    NSArray<SZTraceEvent *> *events = [tracer drainEvents];
    for (SZTraceEvent *event in events) SZPrint(@"%@", event.formattedLine);
    SZPrint(@"events: %lu, dropped: %llu, traced methods: %lu", (unsigned long)events.count, tracer.droppedEventCount, (unsigned long)tracer.tracedMethodCount);
    [tracer untraceAll];
    return 0;
}

static int SZCommandCall(NSArray<NSString *> *args) {
    if (args.count < 4) { SZUsage(); return 2; }
    if (![args[2] isEqualToString:@"-"] && !SZLoad(args[2], NULL)) return 1;
    BOOL isClassMethod = NO;
    NSString *className = nil, *selectorName = nil;
    if (!SZParseSpec(args[3], &isClassMethod, &className, &selectorName)) return SZFail([NSString stringWithFormat:@"bad spec '%@'", args[3]]);
    Class cls = [SZRuntime classNamed:className];
    if (!cls) return SZFail([NSString stringWithFormat:@"class %@ is not loaded", className]);
    id receiver = isClassMethod ? (id)cls : [[cls alloc] init];
    SEL selector = NSSelectorFromString(selectorName);
    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
    if (!signature) return SZFail([NSString stringWithFormat:@"%@ does not respond to %@", className, selectorName]);
    NSArray<NSString *> *argTexts = [args subarrayWithRange:NSMakeRange(4, args.count - 4)];
    NSUInteger expected = signature.numberOfArguments - 2;
    if (argTexts.count != expected) return SZFail([NSString stringWithFormat:@"%@ takes %lu argument(s), got %lu", selectorName, (unsigned long)expected, (unsigned long)argTexts.count]);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    NSMutableArray *retained = [NSMutableArray array];
    for (NSUInteger i = 0; i < expected; i++) {
        const char *type = [signature getArgumentTypeAtIndex:i + 2];
        NSUInteger size = 0;
        NSGetSizeAndAlignment(type, &size, NULL);
        void *buffer = calloc(1, size < 16 ? 16 : size);
        NSString *error = nil;
        BOOL ok = [SZValueParser parseText:argTexts[i] type:type intoBuffer:buffer length:size retaining:retained error:&error];
        if (ok) [invocation setArgument:buffer atIndex:(NSInteger)i + 2];
        free(buffer);
        if (!ok) return SZFail([NSString stringWithFormat:@"argument %lu: %@", (unsigned long)(i + 1), error]);
    }
    [invocation invoke];
    NSString *result = @"void";
    NSUInteger length = signature.methodReturnLength;
    if (length > 0) {
        void *buffer = calloc(1, length < 16 ? 16 : length);
        [invocation getReturnValue:buffer];
        result = SZDescribeValue(signature.methodReturnType, buffer);
        free(buffer);
    }
    SZPrint(@"%@ (%@) -> %@", args[3], [argTexts componentsJoinedByString:@", "], result);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
        if (args.count < 2) { SZUsage(); return 2; }
        NSString *command = args[1];
        if ([command isEqualToString:@"images"]) return SZCommandImages();
        if ([command isEqualToString:@"classes"]) {
            if (args.count < 3) { SZUsage(); return 2; }
            return SZCommandClasses(args[2]);
        }
        if ([command isEqualToString:@"dump"]) return SZCommandDump(args);
        if ([command isEqualToString:@"header"]) return SZCommandHeader(args);
        if ([command isEqualToString:@"search"]) return SZCommandSearch(args);
        if ([command isEqualToString:@"load"]) return SZCommandLoad(args);
        if ([command isEqualToString:@"trace"]) return SZCommandTrace(args);
        if ([command isEqualToString:@"call"]) return SZCommandCall(args);
        SZUsage();
        return 2;
    }
}
