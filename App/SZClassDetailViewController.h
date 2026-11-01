#import <AppKit/AppKit.h>
#import "SZClassInfo.h"

NS_ASSUME_NONNULL_BEGIN

@class SZClassDetailViewController;

@protocol SZClassDetailDelegate <NSObject>
- (void)classDetail:(SZClassDetailViewController *)detail requestsNavigationToClassNamed:(NSString *)name;
- (void)classDetail:(SZClassDetailViewController *)detail didLogMessage:(NSString *)message;
@end

/// Right pane: header with lineage, then tabs for methods (with trace toggles), ivars, properties,
/// protocols, the generated header, and the playground.
@interface SZClassDetailViewController : NSViewController
@property (nonatomic, weak) id<SZClassDetailDelegate> delegate;
@property (nonatomic, readonly, nullable) SZClassInfo *currentInfo;
- (void)showClass:(nullable Class)cls;
- (void)refreshTraceStates;
/// Selects the tab with the given label (Methods, Ivars, Properties, Protocols, Header, Playground).
- (void)selectTabLabeled:(NSString *)label;
- (IBAction)exportHeader:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
