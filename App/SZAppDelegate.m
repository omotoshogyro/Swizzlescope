#import "SZAppDelegate.h"
#import "SZMainWindowController.h"

@implementation SZAppDelegate {
    SZMainWindowController *_mainWindowController;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [self buildMenus];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _mainWindowController = [[SZMainWindowController alloc] init];
    [_mainWindowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    [_mainWindowController loadBundleAtPath:filename];
    return YES;
}

static NSMenuItem *SZItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSEventModifierFlags flags) {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    if (flags) item.keyEquivalentModifierMask = flags;
    return item;
}

- (void)buildMenus {
    NSMenu *menubar = [[NSMenu alloc] init];

    NSMenuItem *appItem = [menubar addItemWithTitle:@"Swizzlescope" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Swizzlescope"];
    SZItem(appMenu, @"About Swizzlescope", @selector(orderFrontStandardAboutPanel:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    SZItem(appMenu, @"Hide Swizzlescope", @selector(hide:), @"h", 0);
    SZItem(appMenu, @"Hide Others", @selector(hideOtherApplications:), @"h", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    SZItem(appMenu, @"Show All", @selector(unhideAllApplications:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    SZItem(appMenu, @"Quit Swizzlescope", @selector(terminate:), @"q", 0);
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [menubar addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    SZItem(fileMenu, @"Open Bundle…", @selector(openBundle:), @"o", 0);
    SZItem(fileMenu, @"Export Header…", @selector(exportHeader:), @"e", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    SZItem(fileMenu, @"Close", @selector(performClose:), @"w", 0);
    fileItem.submenu = fileMenu;

    NSMenuItem *editItem = [menubar addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    SZItem(editMenu, @"Undo", @selector(undo:), @"z", 0);
    SZItem(editMenu, @"Redo", @selector(redo:), @"z", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    [editMenu addItem:[NSMenuItem separatorItem]];
    SZItem(editMenu, @"Cut", @selector(cut:), @"x", 0);
    SZItem(editMenu, @"Copy", @selector(copy:), @"c", 0);
    SZItem(editMenu, @"Paste", @selector(paste:), @"v", 0);
    SZItem(editMenu, @"Select All", @selector(selectAll:), @"a", 0);
    [editMenu addItem:[NSMenuItem separatorItem]];
    SZItem(editMenu, @"Find Class…", @selector(focusSearch:), @"f", 0);
    editItem.submenu = editMenu;

    NSMenuItem *traceItem = [menubar addItemWithTitle:@"Trace" action:NULL keyEquivalent:@""];
    NSMenu *traceMenu = [[NSMenu alloc] initWithTitle:@"Trace"];
    SZItem(traceMenu, @"Untrace All", @selector(untraceAll:), @"u", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    SZItem(traceMenu, @"Clear Log", @selector(clearLog:), @"k", 0);
    traceItem.submenu = traceMenu;

    NSMenuItem *windowItem = [menubar addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    SZItem(windowMenu, @"Minimize", @selector(performMiniaturize:), @"m", 0);
    SZItem(windowMenu, @"Zoom", @selector(performZoom:), @"", 0);
    windowItem.submenu = windowMenu;

    NSApp.mainMenu = menubar;
    NSApp.windowsMenu = windowMenu;
}

@end
