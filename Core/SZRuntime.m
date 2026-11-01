#import "SZRuntime.h"

@implementation SZImage
- (instancetype)initWithPath:(NSString *)path classCount:(NSUInteger)count {
    if ((self = [super init])) {
        _path = [path copy];
        _name = [SZRuntime imageNameForPath:path];
        _classCount = count;
    }
    return self;
}
- (NSString *)description { return [NSString stringWithFormat:@"<SZImage %@ (%lu classes)>", _name, (unsigned long)_classCount]; }
@end

static NSArray<NSString *> *SZSortedNames(const char **names, unsigned count) {
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:count];
    for (unsigned i = 0; i < count; i++) {
        if (names[i]) [out addObject:@(names[i])];
    }
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

@implementation SZRuntime

+ (NSString *)imageNameForPath:(NSString *)path {
    NSString *last = path.lastPathComponent;
    return last.length ? last : path;
}

+ (NSArray<SZImage *> *)loadedImages {
    unsigned count = 0;
    const char **names = objc_copyImageNames(&count);
    NSMutableArray<SZImage *> *result = [NSMutableArray arrayWithCapacity:count];
    for (unsigned i = 0; i < count; i++) {
        unsigned classCount = 0;
        const char **classes = objc_copyClassNamesForImage(names[i], &classCount);
        free(classes);
        [result addObject:[[SZImage alloc] initWithPath:@(names[i]) classCount:classCount]];
    }
    free(names);
    [result sortUsingComparator:^NSComparisonResult(SZImage *a, SZImage *b) {
        NSComparisonResult r = [a.name caseInsensitiveCompare:b.name];
        return r != NSOrderedSame ? r : [a.path compare:b.path];
    }];
    return result;
}

+ (NSArray<NSString *> *)classNamesInImagePath:(NSString *)path {
    unsigned count = 0;
    const char **names = objc_copyClassNamesForImage(path.UTF8String, &count);
    NSArray *result = SZSortedNames(names, count);
    free(names);
    return result;
}

+ (NSArray<NSString *> *)allClassNames {
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:count];
    for (unsigned i = 0; i < count; i++) {
        [out addObject:@(class_getName(classes[i]))];
    }
    free(classes);
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

+ (Class)classNamed:(NSString *)name {
    return name.length ? objc_getClass(name.UTF8String) : Nil;
}

+ (NSString *)imagePathForClass:(Class)cls {
    const char *img = class_getImageName(cls);
    return img ? @(img) : nil;
}

static BOOL SZMethodListContains(Class cls, const char *fragment) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned i = 0; i < count && !found; i++) {
        const char *name = sel_getName(method_getName(methods[i]));
        if (name && strcasestr(name, fragment)) found = YES;
    }
    free(methods);
    return found;
}

+ (NSArray<NSString *> *)classNamesImplementingSelectorContaining:(NSString *)fragment {
    const char *frag = fragment.UTF8String;
    if (!frag || !*frag) return @[];
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (unsigned i = 0; i < count; i++) {
        Class cls = classes[i];
        if (SZMethodListContains(cls, frag) || SZMethodListContains(object_getClass(cls), frag)) {
            [out addObject:@(class_getName(cls))];
        }
    }
    free(classes);
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

@end
