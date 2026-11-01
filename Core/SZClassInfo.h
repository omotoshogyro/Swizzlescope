#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

@interface SZMethodInfo : NSObject
@property (nonatomic, readonly) SEL selector;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *typeEncoding;
@property (nonatomic, readonly) BOOL isClassMethod;
@property (nonatomic, readonly) IMP implementation;
@property (nonatomic, readonly) Class ownerClass;
@property (nonatomic, readonly, copy) NSString *declaration;
/// "+[Class sel]" or "-[Class sel]"
@property (nonatomic, readonly, copy) NSString *qualifiedName;
@end

@interface SZIvarInfo : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *typeEncoding;
@property (nonatomic, readonly) ptrdiff_t offset;
@property (nonatomic, readonly, copy) NSString *decodedType;
@property (nonatomic, readonly, copy) NSString *declaration;
@end

@interface SZPropertyInfo : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *attributes;
@property (nonatomic, readonly) BOOL isClassProperty;
@property (nonatomic, readonly, copy) NSString *declaration;
@end

/// Lazily-populated snapshot of one class's runtime metadata. Reads metadata only; never sends the class a message.
@interface SZClassInfo : NSObject
+ (instancetype)infoForClass:(Class)cls;
+ (nullable instancetype)infoForClassNamed:(NSString *)name;

@property (nonatomic, readonly) Class cls;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, nullable) Class parentClass;
@property (nonatomic, readonly, copy, nullable) NSString *superclassName;
@property (nonatomic, readonly, copy, nullable) NSString *imagePath;
@property (nonatomic, readonly) size_t instanceSize;
@property (nonatomic, readonly, copy) NSArray<NSString *> *superclassChain;
@property (nonatomic, readonly, copy) NSArray<SZMethodInfo *> *instanceMethods;
@property (nonatomic, readonly, copy) NSArray<SZMethodInfo *> *classMethods;
@property (nonatomic, readonly, copy) NSArray<SZIvarInfo *> *ivars;
@property (nonatomic, readonly, copy) NSArray<SZPropertyInfo *> *properties;
@property (nonatomic, readonly, copy) NSArray<NSString *> *protocolNames;

- (nullable SZMethodInfo *)methodNamed:(NSString *)name isClassMethod:(BOOL)isClassMethod;
@end

NS_ASSUME_NONNULL_END
