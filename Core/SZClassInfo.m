#import "SZClassInfo.h"
#import "SZTypeEncoding.h"

@implementation SZMethodInfo
- (instancetype)initWithMethod:(Method)method isClassMethod:(BOOL)isClassMethod owner:(Class)owner {
    if ((self = [super init])) {
        _selector = method_getName(method);
        _name = NSStringFromSelector(_selector) ?: @"";
        const char *enc = method_getTypeEncoding(method);
        _typeEncoding = enc ? @(enc) : @"";
        _implementation = method_getImplementation(method);
        _isClassMethod = isClassMethod;
        _ownerClass = owner;
        _declaration = [SZTypeEncoding methodDeclarationForSelector:_name typeEncoding:_typeEncoding isClassMethod:isClassMethod];
        _qualifiedName = [NSString stringWithFormat:@"%@[%s %@]", isClassMethod ? @"+" : @"-", class_getName(owner), _name];
    }
    return self;
}
- (NSString *)description { return _qualifiedName; }
@end

@implementation SZIvarInfo
- (instancetype)initWithIvar:(Ivar)ivar {
    if ((self = [super init])) {
        const char *name = ivar_getName(ivar);
        const char *enc = ivar_getTypeEncoding(ivar);
        _name = name ? @(name) : @"";
        _typeEncoding = enc ? @(enc) : @"";
        _offset = ivar_getOffset(ivar);
        _decodedType = _typeEncoding.length ? [SZTypeEncoding decodeType:_typeEncoding] : @"?";
        _declaration = [SZTypeEncoding ivarDeclarationForName:_name typeEncoding:_typeEncoding];
    }
    return self;
}
@end

@implementation SZPropertyInfo
- (instancetype)initWithProperty:(objc_property_t)property isClassProperty:(BOOL)isClassProperty {
    if ((self = [super init])) {
        const char *name = property_getName(property);
        const char *attrs = property_getAttributes(property);
        _name = name ? @(name) : @"";
        _attributes = attrs ? @(attrs) : @"";
        _isClassProperty = isClassProperty;
        _declaration = [SZTypeEncoding propertyDeclarationForName:_name attributes:_attributes isClassProperty:isClassProperty];
    }
    return self;
}
@end

@implementation SZClassInfo {
    NSArray<SZMethodInfo *> *_instanceMethods;
    NSArray<SZMethodInfo *> *_classMethods;
    NSArray<SZIvarInfo *> *_ivars;
    NSArray<SZPropertyInfo *> *_properties;
    NSArray<NSString *> *_protocolNames;
    NSArray<NSString *> *_superclassChain;
}

+ (instancetype)infoForClass:(Class)cls {
    return [[self alloc] initWithClass:cls];
}

+ (instancetype)infoForClassNamed:(NSString *)name {
    Class cls = name.length ? objc_getClass(name.UTF8String) : Nil;
    return cls ? [self infoForClass:cls] : nil;
}

- (instancetype)initWithClass:(Class)cls {
    if ((self = [super init])) {
        _cls = cls;
        _name = @(class_getName(cls));
        _parentClass = class_getSuperclass(cls);
        _superclassName = _parentClass ? @(class_getName(_parentClass)) : nil;
        const char *img = class_getImageName(cls);
        _imagePath = img ? @(img) : nil;
        _instanceSize = class_getInstanceSize(cls);
    }
    return self;
}

static NSArray<SZMethodInfo *> *SZCopyMethods(Class target, Class owner, BOOL isClassMethod) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<SZMethodInfo *> *out = [NSMutableArray arrayWithCapacity:count];
    for (unsigned i = 0; i < count; i++) {
        [out addObject:[[SZMethodInfo alloc] initWithMethod:methods[i] isClassMethod:isClassMethod owner:owner]];
    }
    free(methods);
    [out sortUsingComparator:^NSComparisonResult(SZMethodInfo *a, SZMethodInfo *b) { return [a.name compare:b.name]; }];
    return out;
}

- (NSArray<SZMethodInfo *> *)instanceMethods {
    if (!_instanceMethods) _instanceMethods = SZCopyMethods(_cls, _cls, NO);
    return _instanceMethods;
}

- (NSArray<SZMethodInfo *> *)classMethods {
    if (!_classMethods) _classMethods = SZCopyMethods(object_getClass(_cls), _cls, YES);
    return _classMethods;
}

- (NSArray<SZIvarInfo *> *)ivars {
    if (!_ivars) {
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(_cls, &count);
        NSMutableArray<SZIvarInfo *> *out = [NSMutableArray arrayWithCapacity:count];
        for (unsigned i = 0; i < count; i++) [out addObject:[[SZIvarInfo alloc] initWithIvar:ivars[i]]];
        free(ivars);
        _ivars = out;
    }
    return _ivars;
}

- (NSArray<SZPropertyInfo *> *)properties {
    if (!_properties) {
        NSMutableArray<SZPropertyInfo *> *out = [NSMutableArray array];
        unsigned count = 0;
        objc_property_t *props = class_copyPropertyList(_cls, &count);
        for (unsigned i = 0; i < count; i++) [out addObject:[[SZPropertyInfo alloc] initWithProperty:props[i] isClassProperty:NO]];
        free(props);
        count = 0;
        props = class_copyPropertyList(object_getClass(_cls), &count);
        for (unsigned i = 0; i < count; i++) [out addObject:[[SZPropertyInfo alloc] initWithProperty:props[i] isClassProperty:YES]];
        free(props);
        // The runtime can list a property twice when a class declares one that a protocol also declares.
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSMutableArray<SZPropertyInfo *> *unique = [NSMutableArray arrayWithCapacity:out.count];
        for (SZPropertyInfo *prop in out) {
            NSString *key = [NSString stringWithFormat:@"%d:%@", prop.isClassProperty, prop.name];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [unique addObject:prop];
        }
        out = unique;
        [out sortUsingComparator:^NSComparisonResult(SZPropertyInfo *a, SZPropertyInfo *b) {
            if (a.isClassProperty != b.isClassProperty) return a.isClassProperty ? NSOrderedAscending : NSOrderedDescending;
            return [a.name compare:b.name];
        }];
        _properties = out;
    }
    return _properties;
}

- (NSArray<NSString *> *)protocolNames {
    if (!_protocolNames) {
        unsigned count = 0;
        Protocol * __unsafe_unretained *protocols = class_copyProtocolList(_cls, &count);
        NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:count];
        for (unsigned i = 0; i < count; i++) [out addObject:@(protocol_getName(protocols[i]))];
        free(protocols);
        [out sortUsingSelector:@selector(compare:)];
        _protocolNames = out;
    }
    return _protocolNames;
}

- (NSArray<NSString *> *)superclassChain {
    if (!_superclassChain) {
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        for (Class c = class_getSuperclass(_cls); c != Nil; c = class_getSuperclass(c)) [out addObject:@(class_getName(c))];
        _superclassChain = out;
    }
    return _superclassChain;
}

- (SZMethodInfo *)methodNamed:(NSString *)name isClassMethod:(BOOL)isClassMethod {
    for (SZMethodInfo *m in (isClassMethod ? self.classMethods : self.instanceMethods)) {
        if ([m.name isEqualToString:name]) return m;
    }
    return nil;
}

@end
