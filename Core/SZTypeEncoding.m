#import "SZTypeEncoding.h"

static NSString *SZParse(const char **pp, BOOL inNamedStruct);

static BOOL SZIsDigit(char c) { return c >= '0' && c <= '9'; }

static NSString *SZReadQuoted(const char **pp) {
    const char *p = *pp;
    if (*p != '"') return nil;
    p++;
    const char *start = p;
    while (*p && *p != '"') p++;
    NSString *s = [[NSString alloc] initWithBytes:start length:(NSUInteger)(p - start) encoding:NSUTF8StringEncoding] ?: @"";
    if (*p == '"') p++;
    *pp = p;
    return s;
}

static NSString *SZFriendlyStructName(NSString *name) {
    static NSDictionary<NSString *, NSString *> *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        known = @{
            @"_NSRange": @"NSRange", @"_NSZone": @"NSZone", @"_NSDecimal": @"NSDecimal",
            @"CGRect": @"CGRect", @"CGPoint": @"CGPoint", @"CGSize": @"CGSize", @"CGVector": @"CGVector",
            @"CGAffineTransform": @"CGAffineTransform", @"NSEdgeInsets": @"NSEdgeInsets",
            @"NSDirectionalEdgeInsets": @"NSDirectionalEdgeInsets", @"CATransform3D": @"CATransform3D",
            @"CMTime": @"CMTime", @"CMTimeRange": @"CMTimeRange", @"CGColorSpace": @"CGColorSpace",
        };
    });
    NSString *k = known[name];
    if (k) return k;
    return [@"struct " stringByAppendingString:name];
}

static NSString *SZParseAggregate(const char **pp, char close, BOOL isUnion) {
    const char *p = *pp + 1;
    const char *nameStart = p;
    while (*p && *p != '=' && *p != close) p++;
    NSString *name = [[NSString alloc] initWithBytes:nameStart length:(NSUInteger)(p - nameStart) encoding:NSUTF8StringEncoding] ?: @"";
    NSMutableArray<NSString *> *fields = [NSMutableArray array];
    if (*p == '=') {
        p++;
        BOOL hasNames = (*p == '"');
        NSUInteger index = 0;
        while (*p && *p != close) {
            NSString *fieldName = nil;
            if (*p == '"') fieldName = SZReadQuoted(&p);
            if (!*p || *p == close) break;
            const char *before = p;
            NSString *type = SZParse(&p, hasNames);
            if (p == before) break;
            if (!fieldName) fieldName = [NSString stringWithFormat:@"field%lu", (unsigned long)index];
            [fields addObject:[[SZTypeEncoding declarationWithType:type name:fieldName] stringByAppendingString:@";"]];
            index++;
        }
    }
    if (*p == close) p++;
    *pp = p;
    BOOL anonymous = (name.length == 0 || [name isEqualToString:@"?"]);
    NSString *keyword = isUnion ? @"union" : @"struct";
    if (anonymous) {
        if (fields.count == 0) return [keyword stringByAppendingString:@" { }"];
        return [NSString stringWithFormat:@"%@ { %@ }", keyword, [fields componentsJoinedByString:@" "]];
    }
    return isUnion ? [@"union " stringByAppendingString:name] : SZFriendlyStructName(name);
}

static NSString *SZParseBlock(const char **pp) {
    // *pp points just past "@?"
    const char *p = *pp;
    if (*p != '<') return @"id /* block */";
    p++;
    NSMutableArray<NSString *> *types = [NSMutableArray array];
    while (*p && *p != '>') {
        const char *before = p;
        [types addObject:SZParse(&p, NO)];
        while (SZIsDigit(*p)) p++;
        if (p == before) break;
    }
    if (*p == '>') p++;
    *pp = p;
    NSString *ret = types.count ? types[0] : @"void";
    NSArray *args = types.count > 2 ? [types subarrayWithRange:NSMakeRange(2, types.count - 2)] : @[];
    return [NSString stringWithFormat:@"%@ (^)(%@)", ret, args.count ? [args componentsJoinedByString:@", "] : @"void"];
}

static NSString *SZParse(const char **pp, BOOL inNamedStruct) {
    const char *p = *pp;
    NSMutableString *prefix = [NSMutableString string];
    for (;;) {
        BOOL more = YES;
        switch (*p) {
            case 'r': [prefix appendString:@"const "]; break;
            case 'n': [prefix appendString:@"in "]; break;
            case 'N': [prefix appendString:@"inout "]; break;
            case 'o': [prefix appendString:@"out "]; break;
            case 'O': [prefix appendString:@"bycopy "]; break;
            case 'R': [prefix appendString:@"byref "]; break;
            case 'V': [prefix appendString:@"oneway "]; break;
            case 'A': [prefix appendString:@"_Atomic "]; break;
            case 'j': [prefix appendString:@"_Complex "]; break;
            default: more = NO; break;
        }
        if (!more) break;
        p++;
    }
    NSString *type = nil;
    char c = *p;
    switch (c) {
        case '\0': type = @"void"; break;
        case 'c': type = @"char"; p++; break;
        case 'i': type = @"int"; p++; break;
        case 's': type = @"short"; p++; break;
        case 'l': type = @"long"; p++; break;
        case 'q': type = @"long long"; p++; break;
        case 'C': type = @"unsigned char"; p++; break;
        case 'I': type = @"unsigned int"; p++; break;
        case 'S': type = @"unsigned short"; p++; break;
        case 'L': type = @"unsigned long"; p++; break;
        case 'Q': type = @"unsigned long long"; p++; break;
        case 'f': type = @"float"; p++; break;
        case 'd': type = @"double"; p++; break;
        case 'D': type = @"long double"; p++; break;
        case 'B': type = @"BOOL"; p++; break;
        case 'v': type = @"void"; p++; break;
        case '*': type = @"char *"; p++; break;
        case '#': type = @"Class"; p++; break;
        case ':': type = @"SEL"; p++; break;
        case '?': type = @"void /* unknown */"; p++; break;
        case 't': type = @"__int128"; p++; break;
        case 'T': type = @"unsigned __int128"; p++; break;
        case '@': {
            p++;
            if (*p == '?') {
                p++;
                type = SZParseBlock(&p);
            } else if (*p == '"') {
                const char *save = p;
                NSString *name = SZReadQuoted(&p);
                BOOL looksLikeFieldName = inNamedStruct && !(*p == '"' || *p == '}' || *p == ')' || *p == '\0');
                if (looksLikeFieldName) {
                    p = save;
                    type = @"id";
                } else if ([name hasPrefix:@"<"]) {
                    type = [@"id" stringByAppendingString:name];
                } else if (name.length == 0) {
                    type = @"id";
                } else {
                    type = [name stringByAppendingString:@" *"];
                }
            } else {
                type = @"id";
            }
            break;
        }
        case '^': {
            p++;
            if (*p == '?') {
                p++;
                type = @"void (*)(void)";
            } else {
                NSString *inner = SZParse(&p, inNamedStruct);
                type = [inner hasSuffix:@"*"] ? [inner stringByAppendingString:@"*"] : [inner stringByAppendingString:@" *"];
            }
            break;
        }
        case 'b': {
            p++;
            char *end = NULL;
            long n = strtol(p, &end, 10);
            p = end;
            type = [NSString stringWithFormat:@"unsigned int : %ld", n];
            break;
        }
        case '[': {
            p++;
            char *end = NULL;
            long n = strtol(p, &end, 10);
            p = end;
            NSString *inner = SZParse(&p, inNamedStruct);
            if (*p == ']') p++;
            NSRange br = [inner rangeOfString:@"["];
            if (br.location != NSNotFound) {
                type = [NSString stringWithFormat:@"%@[%ld]%@", [inner substringToIndex:br.location], n, [inner substringFromIndex:br.location]];
            } else {
                type = [NSString stringWithFormat:@"%@[%ld]", inner, n];
            }
            break;
        }
        case '{': type = SZParseAggregate(&p, '}', NO); break;
        case '(': type = SZParseAggregate(&p, ')', YES); break;
        case '"': SZReadQuoted(&p); type = @"id"; break;
        default: type = [NSString stringWithFormat:@"unknown_t /* '%c' */", c]; p++; break;
    }
    *pp = p;
    return prefix.length ? [prefix stringByAppendingString:type] : type;
}

@implementation SZTypeEncoding

+ (NSString *)decodeType:(NSString *)encoding {
    const char *p = encoding.UTF8String ?: "";
    return SZParse(&p, NO);
}

+ (NSArray<NSString *> *)decodeMethodTypes:(NSString *)methodEncoding {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    const char *p = methodEncoding.UTF8String ?: "";
    while (*p) {
        const char *before = p;
        NSString *t = SZParse(&p, NO);
        while (SZIsDigit(*p) || *p == '+' || *p == '-') p++;
        [out addObject:t];
        if (p == before) break;
    }
    return out;
}

+ (NSString *)methodDeclarationForSelector:(NSString *)selectorName
                              typeEncoding:(NSString *)encoding
                             isClassMethod:(BOOL)isClassMethod {
    NSArray<NSString *> *types = encoding.length ? [self decodeMethodTypes:encoding] : @[];
    NSString *ret = types.count ? types[0] : @"void";
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@ (%@)", isClassMethod ? @"+" : @"-", ret];
    if (![selectorName containsString:@":"]) {
        [out appendString:selectorName];
    } else {
        NSArray<NSString *> *parts = [selectorName componentsSeparatedByString:@":"];
        NSUInteger argCount = parts.count - 1;
        for (NSUInteger i = 0; i < argCount; i++) {
            NSString *argType = (i + 3 < types.count) ? types[i + 3] : @"id /* ? */";
            [out appendFormat:@"%@%@:(%@)arg%lu", i ? @" " : @"", parts[i], argType, (unsigned long)(i + 1)];
        }
        if (types.count > argCount + 3) [out appendString:@", ..."];
    }
    [out appendString:@";"];
    return out;
}

+ (NSString *)propertyDeclarationForName:(NSString *)name
                              attributes:(NSString *)attributes
                         isClassProperty:(BOOL)isClassProperty {
    NSString *type = @"id";
    NSMutableArray<NSString *> *mods = [NSMutableArray array];
    BOOL readonly = NO, copy = NO, strong = NO, weak = NO, nonatomic = NO, dynamic = NO;
    NSString *getter = nil, *setter = nil;
    for (NSString *attr in [attributes componentsSeparatedByString:@","]) {
        if (attr.length == 0) continue;
        unichar key = [attr characterAtIndex:0];
        NSString *value = [attr substringFromIndex:1];
        switch (key) {
            case 'T': type = [self decodeType:value]; break;
            case 'R': readonly = YES; break;
            case 'C': copy = YES; break;
            case '&': strong = YES; break;
            case 'N': nonatomic = YES; break;
            case 'W': weak = YES; break;
            case 'D': dynamic = YES; break;
            case 'G': getter = value; break;
            case 'S': setter = value; break;
            default: break;
        }
    }
    if (isClassProperty) [mods addObject:@"class"];
    if (nonatomic) [mods addObject:@"nonatomic"];
    if (readonly) [mods addObject:@"readonly"];
    if (copy) [mods addObject:@"copy"];
    if (strong) [mods addObject:@"strong"];
    if (weak) [mods addObject:@"weak"];
    if (getter) [mods addObject:[@"getter=" stringByAppendingString:getter]];
    if (setter) [mods addObject:[@"setter=" stringByAppendingString:setter]];
    NSString *decl = [self declarationWithType:type name:name];
    NSString *line = mods.count
        ? [NSString stringWithFormat:@"@property (%@) %@;", [mods componentsJoinedByString:@", "], decl]
        : [NSString stringWithFormat:@"@property %@;", decl];
    if (dynamic) line = [line stringByAppendingString:@" // @dynamic"];
    return line;
}

+ (NSString *)ivarDeclarationForName:(NSString *)name typeEncoding:(NSString *)encoding {
    NSString *type = encoding.length ? [self decodeType:encoding] : @"void /* no encoding */";
    return [[self declarationWithType:type name:name] stringByAppendingString:@";"];
}

+ (NSString *)declarationWithType:(NSString *)type name:(NSString *)name {
    NSRange fp = [type rangeOfString:@"(*)"];
    if (fp.location != NSNotFound) {
        return [type stringByReplacingCharactersInRange:fp withString:[NSString stringWithFormat:@"(*%@)", name]];
    }
    NSRange bp = [type rangeOfString:@"(^)"];
    if (bp.location != NSNotFound) {
        return [type stringByReplacingCharactersInRange:bp withString:[NSString stringWithFormat:@"(^%@)", name]];
    }
    NSRange br = [type rangeOfString:@"["];
    if (br.location != NSNotFound && ![type hasPrefix:@"struct {"] && ![type hasPrefix:@"union {"]) {
        NSString *base = [[type substringToIndex:br.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        return [NSString stringWithFormat:@"%@ %@%@", base, name, [type substringFromIndex:br.location]];
    }
    if ([type hasSuffix:@"*"]) return [type stringByAppendingString:name];
    return [NSString stringWithFormat:@"%@ %@", type, name];
}

@end
