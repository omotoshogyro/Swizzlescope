#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// A loaded Mach-O image that contributes Objective-C classes.
@interface SZImage : NSObject
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSUInteger classCount;
@end

/// Thin wrappers over the objc runtime enumeration functions. Nothing here messages the classes it enumerates.
@interface SZRuntime : NSObject
+ (NSArray<SZImage *> *)loadedImages;
+ (NSArray<NSString *> *)classNamesInImagePath:(NSString *)path;
+ (NSArray<NSString *> *)allClassNames;
+ (nullable Class)classNamed:(NSString *)name;
+ (nullable NSString *)imagePathForClass:(Class)cls;
/// Class names (sorted) that implement, on the class or metaclass, a selector whose name contains `fragment`.
+ (NSArray<NSString *> *)classNamesImplementingSelectorContaining:(NSString *)fragment;
+ (NSString *)imageNameForPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
