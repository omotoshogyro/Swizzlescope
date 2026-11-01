#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Bottom pane: drains the tracer's event buffer on a timer and renders one line per call.
@interface SZTraceLogViewController : NSViewController
- (void)appendNote:(NSString *)note;
- (IBAction)clearLog:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
