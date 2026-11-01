#import "SZValueParser.h"
#import <objc/runtime.h>

static NSString *SZTrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static const char *SZSkipQualifiers(const char *t) {
    while (*t && strchr("rnNoORVAj", *t)) t++;
    return t;
}

static BOOL SZFail(NSString **error, NSString *message) {
    if (error) *error = message;
    return NO;
}

/// Pulls every number out of "{1, 2, {3, 4}}" in order.
static NSArray<NSNumber *> *SZNumbersIn(NSString *text) {
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSCharacterSet *skip = [NSCharacterSet characterSetWithCharactersInString:@"{}[](), \t\n"];
    scanner.charactersToBeSkipped = skip;
    while (!scanner.atEnd) {
        double value = 0;
        if ([scanner scanDouble:&value]) {
            [out addObject:@(value)];
        } else {
            scanner.scanLocation += 1;
        }
    }
    return out;
}

static BOOL SZFillStruct(const char *type, NSArray<NSNumber *> *numbers, NSUInteger *index, void *buffer, NSString **error);

static BOOL SZFillScalar(const char *type, NSNumber *number, void *buffer, NSString **error) {
    switch (*type) {
        case 'c': *(char *)buffer = (char)number.intValue; return YES;
        case 'i': *(int *)buffer = number.intValue; return YES;
        case 's': *(short *)buffer = (short)number.intValue; return YES;
        case 'l': *(long *)buffer = number.longValue; return YES;
        case 'q': *(long long *)buffer = number.longLongValue; return YES;
        case 'C': *(unsigned char *)buffer = (unsigned char)number.unsignedIntValue; return YES;
        case 'I': *(unsigned int *)buffer = number.unsignedIntValue; return YES;
        case 'S': *(unsigned short *)buffer = (unsigned short)number.unsignedIntValue; return YES;
        case 'L': *(unsigned long *)buffer = number.unsignedLongValue; return YES;
        case 'Q': *(unsigned long long *)buffer = number.unsignedLongLongValue; return YES;
        case 'f': *(float *)buffer = number.floatValue; return YES;
        case 'd': *(double *)buffer = number.doubleValue; return YES;
        case 'B': *(bool *)buffer = number.boolValue; return YES;
        default: return SZFail(error, [NSString stringWithFormat:@"Cannot fill type '%c' from a number", *type]);
    }
}

static BOOL SZFillStruct(const char *type, NSArray<NSNumber *> *numbers, NSUInteger *index, void *buffer, NSString **error) {
    const char *p = type + 1;
    while (*p && *p != '=' && *p != '}') p++;
    if (*p != '=') return SZFail(error, @"Opaque struct cannot be filled");
    p++;
    size_t offset = 0;
    while (*p && *p != '}') {
        if (*p == '"') { p++; while (*p && *p != '"') p++; if (*p == '"') p++; continue; }
        NSUInteger size = 0, align = 0;
        const char *next = NSGetSizeAndAlignment(p, &size, &align);
        if (align == 0) align = 1;
        offset = (offset + align - 1) & ~(align - 1);
        if (*p == '{') {
            if (!SZFillStruct(p, numbers, index, (uint8_t *)buffer + offset, error)) return NO;
        } else {
            if (*index >= numbers.count) return SZFail(error, @"Not enough numbers for struct fields");
            if (!SZFillScalar(SZSkipQualifiers(p), numbers[(*index)++], (uint8_t *)buffer + offset, error)) return NO;
        }
        offset += size;
        p = next;
    }
    return YES;
}

@implementation SZValueParser

+ (NSArray<NSString *> *)splitArguments:(NSString *)text {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    NSInteger depth = 0;
    BOOL inQuote = NO;
    BOOL any = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        any = YES;
        if (inQuote) {
            [current appendFormat:@"%C", c];
            if (c == '\\' && i + 1 < text.length) { [current appendFormat:@"%C", [text characterAtIndex:++i]]; continue; }
            if (c == '"') inQuote = NO;
            continue;
        }
        if (c == '"') { inQuote = YES; [current appendFormat:@"%C", c]; continue; }
        if (c == '{' || c == '[' || c == '(') depth++;
        if (c == '}' || c == ']' || c == ')') depth--;
        if (c == ',' && depth <= 0) {
            [parts addObject:SZTrim(current)];
            [current setString:@""];
            continue;
        }
        [current appendFormat:@"%C", c];
    }
    if (any && (SZTrim(current).length || parts.count)) [parts addObject:SZTrim(current)];
    return parts;
}

+ (BOOL)parseText:(NSString *)text type:(const char *)type intoBuffer:(void *)buffer length:(NSUInteger)length retaining:(NSMutableArray *)retained error:(NSString **)error {
    text = SZTrim(text);
    type = SZSkipQualifiers(type);
    memset(buffer, 0, length);
    switch (*type) {
        case '@': {
            if ([text isEqualToString:@"nil"] || [text isEqualToString:@"NULL"] || text.length == 0) return YES;
            id object = nil;
            if ([text hasPrefix:@"\""] && [text hasSuffix:@"\""] && text.length >= 2) {
                NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
                object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:NULL]
                      ?: [text substringWithRange:NSMakeRange(1, text.length - 2)];
            } else if ([text hasPrefix:@"["] || [text hasPrefix:@"{"]) {
                NSError *jsonError = nil;
                object = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonError];
                if (!object) return SZFail(error, [NSString stringWithFormat:@"Invalid JSON: %@", jsonError.localizedDescription]);
            } else if ([text isEqualToString:@"YES"] || [text isEqualToString:@"true"]) {
                object = @YES;
            } else if ([text isEqualToString:@"NO"] || [text isEqualToString:@"false"]) {
                object = @NO;
            } else {
                NSScanner *scanner = [NSScanner scannerWithString:text];
                double d = 0;
                if ([scanner scanDouble:&d] && scanner.atEnd) {
                    object = [text containsString:@"."] || [text containsString:@"e"] ? @(d) : @((long long)d);
                } else {
                    object = text;
                }
            }
            [retained addObject:object];
            *(void **)buffer = (__bridge void *)object;
            return YES;
        }
        case '#': {
            if ([text isEqualToString:@"Nil"] || [text isEqualToString:@"nil"] || text.length == 0) return YES;
            Class cls = objc_getClass(text.UTF8String);
            if (!cls) return SZFail(error, [NSString stringWithFormat:@"No class named %@", text]);
            *(Class *)buffer = cls;
            return YES;
        }
        case ':': {
            if (text.length == 0 || [text isEqualToString:@"NULL"]) return YES;
            *(SEL *)buffer = sel_registerName(text.UTF8String);
            return YES;
        }
        case '*': {
            if ([text isEqualToString:@"NULL"] || [text isEqualToString:@"nil"]) return YES;
            if ([text hasPrefix:@"\""] && [text hasSuffix:@"\""] && text.length >= 2) text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
            NSData *bytes = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            NSMutableData *buf = [NSMutableData dataWithData:bytes];
            [buf appendBytes:"" length:1];
            [retained addObject:buf];
            *(const char **)buffer = buf.bytes;
            return YES;
        }
        case '^': {
            if ([text isEqualToString:@"NULL"] || [text isEqualToString:@"nil"] || text.length == 0) return YES;
            unsigned long long value = strtoull(text.UTF8String, NULL, 0);
            *(void **)buffer = (void *)(uintptr_t)value;
            return YES;
        }
        case 'B': {
            NSString *lower = text.lowercaseString;
            *(bool *)buffer = [lower isEqualToString:@"yes"] || [lower isEqualToString:@"true"] || [lower isEqualToString:@"1"];
            return YES;
        }
        case 'c': case 'i': case 's': case 'l': case 'q':
        case 'C': case 'I': case 'S': case 'L': case 'Q':
        case 'f': case 'd': {
            NSString *lower = text.lowercaseString;
            if ([lower isEqualToString:@"yes"] || [lower isEqualToString:@"true"]) return SZFillScalar(type, @1, buffer, error);
            if ([lower isEqualToString:@"no"] || [lower isEqualToString:@"false"]) return SZFillScalar(type, @0, buffer, error);
            if ([text hasPrefix:@"0x"] || [text hasPrefix:@"0X"]) return SZFillScalar(type, @(strtoull(text.UTF8String, NULL, 16)), buffer, error);
            NSScanner *scanner = [NSScanner scannerWithString:text];
            double d = 0;
            if (![scanner scanDouble:&d] || !scanner.atEnd) return SZFail(error, [NSString stringWithFormat:@"'%@' is not a number", text]);
            if (*type == 'q' || *type == 'Q' || *type == 'l' || *type == 'L') {
                return SZFillScalar(type, @(strtoll(text.UTF8String, NULL, 10)), buffer, error);
            }
            return SZFillScalar(type, @(d), buffer, error);
        }
        case '{': {
            NSArray<NSNumber *> *numbers = SZNumbersIn(text);
            NSUInteger index = 0;
            return SZFillStruct(type, numbers, &index, buffer, error);
        }
        default:
            return SZFail(error, [NSString stringWithFormat:@"Arguments of type '%s' cannot be entered as text", type]);
    }
}

@end
