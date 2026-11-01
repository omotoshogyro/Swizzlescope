#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Decodes Objective-C @encode strings into readable C/Objective-C type names.
@interface SZTypeEncoding : NSObject

/// Decode a single type encoding such as "@\"NSString\"" or "{CGRect={CGPoint=dd}{CGSize=dd}}".
+ (NSString *)decodeType:(NSString *)encoding;

/// Decode a method type encoding ("v24@0:8@16") into [return, self, _cmd, arg1, ...].
+ (NSArray<NSString *> *)decodeMethodTypes:(NSString *)methodEncoding;

/// "- (void)setFrame:(CGRect)arg1 display:(BOOL)arg2;"
+ (NSString *)methodDeclarationForSelector:(NSString *)selectorName
                              typeEncoding:(nullable NSString *)encoding
                             isClassMethod:(BOOL)isClassMethod;

/// "@property (nonatomic, copy) NSString *name;" from the raw attribute string "T@\"NSString\",C,N,V_name".
+ (NSString *)propertyDeclarationForName:(NSString *)name
                              attributes:(NSString *)attributes
                         isClassProperty:(BOOL)isClassProperty;

/// "NSString *_name;" or "char _flags[4];"
+ (NSString *)ivarDeclarationForName:(NSString *)name typeEncoding:(nullable NSString *)encoding;

/// Joins a decoded type and a variable name, placing array brackets and function-pointer stars correctly.
+ (NSString *)declarationWithType:(NSString *)type name:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
