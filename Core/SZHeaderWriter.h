#import <Foundation/Foundation.h>
#import "SZClassInfo.h"

NS_ASSUME_NONNULL_BEGIN

/// Produces class-dump style @interface text for a class.
@interface SZHeaderWriter : NSObject
+ (NSString *)headerForClass:(SZClassInfo *)info;
@end

NS_ASSUME_NONNULL_END
