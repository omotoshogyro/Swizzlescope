#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One recorded method call.
@interface SZTraceEvent : NSObject
@property (nonatomic) uint64_t sequence;
@property (nonatomic, copy) NSString *className;          // class the trace was installed on
@property (nonatomic, copy) NSString *receiverClassName;  // concrete class of the receiver
@property (nonatomic) uintptr_t receiverAddress;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic) BOOL isClassMethod;
@property (nonatomic, copy) NSArray<NSString *> *argumentDescriptions;
@property (nonatomic, copy, nullable) NSString *returnDescription;
@property (nonatomic) uint64_t durationNanoseconds;
@property (nonatomic) NSUInteger depth;
@property (nonatomic, copy) NSString *threadName;
- (NSString *)formattedLine;
@end

/// Renders a value of the given @encode type found at `buffer`. Safe for arbitrary objects: it only
/// calls -description on a small allowlist of Foundation value classes and never on anything else.
NSString *SZDescribeValue(const char *type, const void *buffer);
NSString *SZDescribeObject(id _Nullable object);
NSString *SZFormatNanoseconds(uint64_t ns);

NS_ASSUME_NONNULL_END
