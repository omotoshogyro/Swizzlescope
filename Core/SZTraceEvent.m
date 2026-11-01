#import "SZTraceEvent.h"
#import <objc/runtime.h>

static const char *SZSkipQualifiers(const char *t) {
    while (*t && strchr("rnNoORVAj", *t)) t++;
    return t;
}

static BOOL SZClassIsKindOfNamed(Class cls, const char *name) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        if (strcmp(class_getName(c), name) == 0) return YES;
    }
    return NO;
}

static NSString *SZQuoted(NSString *s) {
    if (s.length > 120) s = [[s substringToIndex:117] stringByAppendingString:@"…"];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return [NSString stringWithFormat:@"\"%@\"", s];
}

NSString *SZDescribeObject(id object) {
    if (!object) return @"nil";
    Class cls = object_getClass(object);
    if (class_isMetaClass(cls)) return @(class_getName((Class)object));
    const char *name = class_getName(cls);
    if (SZClassIsKindOfNamed(cls, "NSString")) return SZQuoted((NSString *)object);
    if (SZClassIsKindOfNamed(cls, "NSNumber")) return [(NSNumber *)object description] ?: @"NSNumber";
    if (SZClassIsKindOfNamed(cls, "NSNull")) return @"NSNull";
    if (SZClassIsKindOfNamed(cls, "NSDate")) return [NSString stringWithFormat:@"<NSDate %@>", [(NSDate *)object description]];
    if (SZClassIsKindOfNamed(cls, "NSURL")) return [NSString stringWithFormat:@"<NSURL %@>", [(NSURL *)object absoluteString]];
    if (SZClassIsKindOfNamed(cls, "NSValue")) return [(NSValue *)object description] ?: @"NSValue";
    if (SZClassIsKindOfNamed(cls, "NSIndexPath")) return [(NSIndexPath *)object description] ?: @"NSIndexPath";
    if (SZClassIsKindOfNamed(cls, "NSArray")) return [NSString stringWithFormat:@"<%s: %p> (%lu items)", name, (void *)object, (unsigned long)[(NSArray *)object count]];
    if (SZClassIsKindOfNamed(cls, "NSDictionary")) return [NSString stringWithFormat:@"<%s: %p> (%lu entries)", name, (void *)object, (unsigned long)[(NSDictionary *)object count]];
    if (SZClassIsKindOfNamed(cls, "NSSet")) return [NSString stringWithFormat:@"<%s: %p> (%lu items)", name, (void *)object, (unsigned long)[(NSSet *)object count]];
    if (SZClassIsKindOfNamed(cls, "NSData")) return [NSString stringWithFormat:@"<%s: %p> (%lu bytes)", name, (void *)object, (unsigned long)[(NSData *)object length]];
    if (SZClassIsKindOfNamed(cls, "NSError")) return [NSString stringWithFormat:@"<NSError %@ %ld>", [(NSError *)object domain], (long)[(NSError *)object code]];
    return [NSString stringWithFormat:@"<%s: %p>", name, (void *)object];
}

static NSString *SZDescribeAggregate(const char *type, const void *buffer, char close) {
    const char *p = type + 1;
    const char *nameStart = p;
    while (*p && *p != '=' && *p != close) p++;
    if (*p != '=') {
        return [NSString stringWithFormat:@"{%.*s}", (int)(p - nameStart), nameStart];
    }
    p++;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    size_t offset = 0;
    @try {
        while (*p && *p != close) {
            if (*p == '"') {
                p++;
                while (*p && *p != '"') p++;
                if (*p == '"') p++;
                continue;
            }
            NSUInteger size = 0, align = 0;
            const char *next = NSGetSizeAndAlignment(p, &size, &align);
            if (align == 0) align = 1;
            if (close == '}') offset = (offset + align - 1) & ~(align - 1);
            [parts addObject:SZDescribeValue(p, (const uint8_t *)buffer + (close == '}' ? offset : 0))];
            if (close == '}') offset += size;
            if (next == p) break;
            p = next;
        }
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"{? %s}", type];
    }
    return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
}

NSString *SZDescribeValue(const char *type, const void *buffer) {
    type = SZSkipQualifiers(type);
    switch (*type) {
        case '\0':
        case 'v': return @"void";
        case 'c': return [NSString stringWithFormat:@"%d", *(const char *)buffer];
        case 'i': return [NSString stringWithFormat:@"%d", *(const int *)buffer];
        case 's': return [NSString stringWithFormat:@"%d", *(const short *)buffer];
        case 'l': return [NSString stringWithFormat:@"%ld", *(const long *)buffer];
        case 'q': return [NSString stringWithFormat:@"%lld", *(const long long *)buffer];
        case 'C': return [NSString stringWithFormat:@"%u", *(const unsigned char *)buffer];
        case 'I': return [NSString stringWithFormat:@"%u", *(const unsigned int *)buffer];
        case 'S': return [NSString stringWithFormat:@"%u", *(const unsigned short *)buffer];
        case 'L': return [NSString stringWithFormat:@"%lu", *(const unsigned long *)buffer];
        case 'Q': return [NSString stringWithFormat:@"%llu", *(const unsigned long long *)buffer];
        case 'f': return [NSString stringWithFormat:@"%g", *(const float *)buffer];
        case 'd': return [NSString stringWithFormat:@"%g", *(const double *)buffer];
        case 'D': return [NSString stringWithFormat:@"%Lg", *(const long double *)buffer];
        case 'B': return *(const bool *)buffer ? @"YES" : @"NO";
        case '*': {
            const char *s = *(const char *const *)buffer;
            if (!s) return @"NULL";
            return SZQuoted(@(s) ?: @"<invalid utf8>");
        }
        case ':': {
            SEL sel = *(const SEL *)buffer;
            return sel ? [NSString stringWithFormat:@"@selector(%s)", sel_getName(sel)] : @"NULL";
        }
        case '#': {
            Class cls = *(Class const *)buffer;
            return cls ? @(class_getName(cls)) : @"Nil";
        }
        case '@': {
            id __unsafe_unretained object = *(id __unsafe_unretained const *)buffer;
            if (type[1] == '?') return object ? [NSString stringWithFormat:@"<block %p>", (void *)object] : @"nil";
            return SZDescribeObject(object);
        }
        case '^': {
            const void *ptr = *(const void *const *)buffer;
            return ptr ? [NSString stringWithFormat:@"%p", ptr] : @"NULL";
        }
        case '{': return SZDescribeAggregate(type, buffer, '}');
        case '(': return SZDescribeAggregate(type, buffer, ')');
        case '[': {
            const char *p = type + 1;
            char *end = NULL;
            long n = strtol(p, &end, 10);
            p = end;
            NSUInteger size = 0;
            @try { NSGetSizeAndAlignment(p, &size, NULL); } @catch (NSException *e) { return @"[?]"; }
            NSMutableArray<NSString *> *parts = [NSMutableArray array];
            long shown = n < 8 ? n : 8;
            for (long i = 0; i < shown; i++) [parts addObject:SZDescribeValue(p, (const uint8_t *)buffer + (size_t)i * size)];
            if (n > shown) [parts addObject:@"…"];
            return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@", "]];
        }
        case 'b': return @"(bitfield)";
        default: {
            NSUInteger size = 0;
            @try { NSGetSizeAndAlignment(type, &size, NULL); } @catch (NSException *e) { size = 0; }
            if (size == 0 || size > 32) return [NSString stringWithFormat:@"(%s)", type];
            NSMutableString *hex = [NSMutableString stringWithString:@"0x"];
            for (NSUInteger i = 0; i < size; i++) [hex appendFormat:@"%02x", ((const uint8_t *)buffer)[i]];
            return hex;
        }
    }
}

NSString *SZFormatNanoseconds(uint64_t ns) {
    if (ns < 1000) return [NSString stringWithFormat:@"%llu ns", ns];
    if (ns < 1000000) return [NSString stringWithFormat:@"%.1f µs", ns / 1000.0];
    return [NSString stringWithFormat:@"%.2f ms", ns / 1000000.0];
}

@implementation SZTraceEvent

- (NSString *)formattedLine {
    NSMutableString *line = [NSMutableString stringWithFormat:@"#%llu [%@] ", self.sequence, self.threadName ?: @"?"];
    for (NSUInteger i = 0; i < self.depth; i++) [line appendString:@"  "];
    [line appendFormat:@"%@[%@ %@]", self.isClassMethod ? @"+" : @"-", self.className, self.selectorName];
    if (!self.isClassMethod) {
        [line appendFormat:@" <%@: %p>", self.receiverClassName, (void *)self.receiverAddress];
    } else if (![self.receiverClassName isEqualToString:self.className]) {
        [line appendFormat:@" (as %@)", self.receiverClassName];
    }
    [line appendFormat:@" (%@)", [self.argumentDescriptions componentsJoinedByString:@", "]];
    [line appendFormat:@" -> %@", self.returnDescription ?: @"?"];
    [line appendFormat:@"  %@", SZFormatNanoseconds(self.durationNanoseconds)];
    return line;
}

- (NSString *)description { return [self formattedLine]; }

@end
