#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Turns user-typed text into raw argument bytes for NSInvocation, driven by an @encode type.
/// Objects created while parsing (strings, numbers, JSON collections) are appended to `retained`
/// so they stay alive for the duration of the call.
@interface SZValueParser : NSObject
/// Splits "a, \"b, c\", {1, 2}" into top-level comma-separated pieces, respecting quotes, braces and brackets.
+ (NSArray<NSString *> *)splitArguments:(NSString *)text;
+ (BOOL)parseText:(NSString *)text
             type:(const char *)type
       intoBuffer:(void *)buffer
           length:(NSUInteger)length
        retaining:(NSMutableArray *)retained
            error:(NSString *_Nullable __autoreleasing *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
