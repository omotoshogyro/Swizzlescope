#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "SZTraceEvent.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const SZTracerErrorDomain;

/// Installs and removes method traces. A traced method's IMP is replaced with _objc_msgForward so every call
/// goes through the forwarding machinery; the tracer's forwardInvocation: hook records the call and then
/// invokes the original implementation, which is kept under an alias selector on the same class.
@interface SZTracer : NSObject
+ (instancetype)sharedTracer;

/// Returns NO with a reason when the method is not safe or possible to trace.
+ (BOOL)canTraceClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod reason:(NSString *_Nullable __autoreleasing *_Nullable)reason;

- (BOOL)traceClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod error:(NSError **)error;
- (BOOL)untraceClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod;
- (BOOL)isTracingClass:(Class)cls selector:(SEL)selector isClassMethod:(BOOL)isClassMethod;
- (void)untraceAll;

/// "+[Class sel]" / "-[Class sel]" for every traced method, sorted.
- (NSArray<NSString *> *)tracedMethodNames;
@property (nonatomic, readonly) NSUInteger tracedMethodCount;

/// Returns buffered events in order and clears the buffer. Thread-safe.
- (NSArray<SZTraceEvent *> *)drainEvents;
@property (nonatomic, readonly) uint64_t droppedEventCount;
@property (nonatomic, readonly) uint64_t totalEventCount;
@end

NS_ASSUME_NONNULL_END
