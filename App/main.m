#import <AppKit/AppKit.h>
#import "SZAppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        SZAppDelegate *delegate = [[SZAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
