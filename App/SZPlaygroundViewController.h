#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Create an instance of the selected class, send it messages with typed arguments, and read its ivars.
@interface SZPlaygroundViewController : NSViewController
@property (nonatomic, nullable) Class targetClass;
- (void)focusSelectorField;
@end

NS_ASSUME_NONNULL_END
