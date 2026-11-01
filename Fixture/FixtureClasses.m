// Test fixture loaded by the CLI tests and available to the app via File > Open.
#import <Foundation/Foundation.h>

typedef struct {
    double x, y, z;
} FXVector;

@protocol FXProtocol <NSObject>
- (void)protocolMethod;
@end

@interface FXBase : NSObject <FXProtocol> {
    NSString *_name;
    int _counter;
    double _ratio;
    char _flags[4];
    __weak id _delegate;
    void *_opaque;
    CGRect _frame;
}
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) int counter;
@property (nonatomic, readonly) double ratio;
@property (nonatomic, weak) id delegate;

+ (instancetype)fixture;
- (void)noArgs;
- (int)addInt:(int)a toInt:(int)b;
- (BOOL)isEnabled:(BOOL)flag;
- (double)scale:(double)value by:(float)factor;
- (NSString *)greet:(NSString *)who;
- (CGRect)insetRect:(CGRect)rect by:(CGFloat)amount;
- (NSRange)rangeOf:(NSString *)needle;
- (FXVector)vectorScaled:(FXVector)vector by:(double)k;
- (const char *)cString:(const char *)s;
- (void)performBlock:(void (^)(void))block;
- (SEL)echoSelector:(SEL)selector;
- (Class)echoClass:(Class)cls;
- (void *)pointer:(int *)p;
- (unsigned long long)big:(unsigned long long)value;
@end

@interface FXChild : FXBase
- (void)childOnly;
+ (NSUInteger)runSelfTest;
@end

@implementation FXBase

+ (instancetype)fixture { return [[self alloc] init]; }

- (instancetype)init {
    if ((self = [super init])) {
        _name = @"base";
        _ratio = 0.5;
        _frame = CGRectMake(1, 2, 3, 4);
        memcpy(_flags, "abc", 4);
    }
    return self;
}

- (void)noArgs {}
- (int)addInt:(int)a toInt:(int)b { return a + b; }
- (BOOL)isEnabled:(BOOL)flag { return flag; }
- (double)scale:(double)value by:(float)factor { return value * factor; }
- (NSString *)greet:(NSString *)who { return [NSString stringWithFormat:@"Hello, %@", who]; }
- (CGRect)insetRect:(CGRect)rect by:(CGFloat)amount { return CGRectInset(rect, amount, amount); }
- (NSRange)rangeOf:(NSString *)needle { return [@"fixture" rangeOfString:needle]; }
- (FXVector)vectorScaled:(FXVector)vector by:(double)k { return (FXVector){vector.x * k, vector.y * k, vector.z * k}; }
- (const char *)cString:(const char *)s { return s; }
- (void)performBlock:(void (^)(void))block { if (block) block(); }
- (SEL)echoSelector:(SEL)selector { return selector; }
- (Class)echoClass:(Class)cls { return cls; }
- (void *)pointer:(int *)p { return p; }
- (unsigned long long)big:(unsigned long long)value { return value; }
- (void)protocolMethod {}

@end

@implementation FXChild

- (void)childOnly {}
- (int)addInt:(int)a toInt:(int)b { return [super addInt:a toInt:b] + 100; }

+ (NSUInteger)runSelfTest {
    FXChild *c = [[FXChild alloc] init];
    c.name = @"fixture";
    NSUInteger n = 0;
    [c noArgs]; n++;
    (void)[c addInt:2 toInt:3]; n++;
    (void)[c isEnabled:YES]; n++;
    (void)[c scale:1.5 by:2.0f]; n++;
    (void)[c greet:@"world"]; n++;
    (void)[c insetRect:CGRectMake(0, 0, 100, 50) by:5]; n++;
    (void)[c rangeOf:@"fix"]; n++;
    FXVector v = {1, 2, 3};
    (void)[c vectorScaled:v by:2]; n++;
    (void)[c cString:"hello"]; n++;
    [c performBlock:^{}]; n++;
    (void)[c echoSelector:@selector(noArgs)]; n++;
    (void)[c echoClass:[NSString class]]; n++;
    int x = 7;
    (void)[c pointer:&x]; n++;
    (void)[c big:1ULL << 40]; n++;
    [c childOnly]; n++;
    [c protocolMethod]; n++;
    return n;
}

@end
