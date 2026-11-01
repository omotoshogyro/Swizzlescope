#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SZClassListViewController;

@protocol SZClassListDelegate <NSObject>
- (void)classList:(SZClassListViewController *)list didSelectClass:(nullable Class)cls;
- (void)classListDidResetFilter:(SZClassListViewController *)list;
@end

/// Sidebar: loaded images with their classes, plus a flat filtered view when searching.
@interface SZClassListViewController : NSViewController
@property (nonatomic, weak) id<SZClassListDelegate> delegate;
/// Empty string shows the image tree. "sel:frag" searches selectors; anything else filters class names.
- (void)setFilter:(NSString *)filter;
- (void)reloadImagesSelectingPath:(nullable NSString *)path;
- (void)selectClassNamed:(NSString *)name;
@end

NS_ASSUME_NONNULL_END
