#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SZMainWindowController : NSWindowController
- (void)loadBundleAtPath:(NSString *)path;
- (IBAction)openBundle:(nullable id)sender;
- (IBAction)exportHeader:(nullable id)sender;
- (IBAction)focusSearch:(nullable id)sender;
- (IBAction)untraceAll:(nullable id)sender;
- (IBAction)clearLog:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
