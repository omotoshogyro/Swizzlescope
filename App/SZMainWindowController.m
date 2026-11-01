#import "SZMainWindowController.h"
#import "SZClassListViewController.h"
#import "SZClassDetailViewController.h"
#import "SZTraceLogViewController.h"
#import "SZLoader.h"
#import "SZRuntime.h"
#import "SZTracer.h"

static NSToolbarItemIdentifier const SZToolbarOpen = @"os.open";
static NSToolbarItemIdentifier const SZToolbarExport = @"os.export";
static NSToolbarItemIdentifier const SZToolbarUntraceAll = @"os.untraceAll";
static NSToolbarItemIdentifier const SZToolbarSearch = @"os.search";

@interface SZMainWindowController () <NSToolbarDelegate, NSSearchFieldDelegate, SZClassListDelegate, SZClassDetailDelegate>
@end

@implementation SZMainWindowController {
    SZClassListViewController *_list;
    SZClassDetailViewController *_detail;
    SZTraceLogViewController *_log;
    NSSplitViewController *_outer;
    NSSplitViewController *_inner;
    NSSearchField *_searchField;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1320, 860)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Swizzlescope";
    window.minSize = NSMakeSize(960, 600);
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    [window center];

    self = [super initWithWindow:window];
    if (!self) return nil;

    _list = [[SZClassListViewController alloc] init];
    _list.delegate = self;
    _detail = [[SZClassDetailViewController alloc] init];
    _detail.delegate = self;
    _log = [[SZTraceLogViewController alloc] init];

    _inner = [[NSSplitViewController alloc] init];
    _inner.splitView.autosaveName = @"SZInnerSplit";
    NSSplitViewItem *sidebar = [NSSplitViewItem sidebarWithViewController:_list];
    sidebar.minimumThickness = 240;
    sidebar.maximumThickness = 560;
    sidebar.canCollapse = NO;
    NSSplitViewItem *detail = [NSSplitViewItem splitViewItemWithViewController:_detail];
    detail.minimumThickness = 520;
    [_inner addSplitViewItem:sidebar];
    [_inner addSplitViewItem:detail];

    _outer = [[NSSplitViewController alloc] init];
    _outer.splitView.vertical = NO;
    _outer.splitView.autosaveName = @"SZOuterSplit";
    NSSplitViewItem *top = [NSSplitViewItem splitViewItemWithViewController:_inner];
    top.minimumThickness = 320;
    NSSplitViewItem *bottom = [NSSplitViewItem splitViewItemWithViewController:_log];
    bottom.minimumThickness = 140;
    bottom.canCollapse = YES;
    [_outer addSplitViewItem:top];
    [_outer addSplitViewItem:bottom];
    self.contentViewController = _outer;

    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"SZMainToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    window.toolbar = toolbar;

    [window setFrameAutosaveName:@"SZMainWindow"];
    return self;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyLaunchArguments];
        if (self->_inner.splitView.subviews.count > 1 && NSWidth(self->_inner.splitView.subviews[0].frame) < 100) {
            [self->_inner.splitView setPosition:320 ofDividerAtIndex:0];
        }
        if (self->_outer.splitView.subviews.count > 1 && NSHeight(self->_outer.splitView.subviews[1].frame) < 60) {
            [self->_outer.splitView setPosition:NSHeight(self->_outer.splitView.bounds) - 240 ofDividerAtIndex:0];
        }
    });
}

/// Scriptable startup, mainly for testing:
///   Swizzlescope -load /path/To.framework -select NSWindow -tab Playground -trace '-[NSWindow sendEvent:],+[NSApplication sharedApplication]'
- (void)applyLaunchArguments {
    // Parsed by hand: NSUserDefaults would treat a value such as "-[NSWindow sendEvent:]" as the next flag.
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSString *load = nil, *select = nil, *trace = nil, *tab = nil;
    for (NSUInteger i = 1; i + 1 < arguments.count; i++) {
        if ([arguments[i] isEqualToString:@"-load"]) load = arguments[++i];
        else if ([arguments[i] isEqualToString:@"-select"]) select = arguments[++i];
        else if ([arguments[i] isEqualToString:@"-trace"]) trace = arguments[++i];
        else if ([arguments[i] isEqualToString:@"-tab"]) tab = arguments[++i];
    }
    if (load.length) [self loadBundleAtPath:load];
    if (select.length) [_list selectClassNamed:select];
    if (tab.length) [_detail selectTabLabeled:tab];
    for (NSString *rawSpec in [trace componentsSeparatedByString:@","]) {
        NSString *spec = [rawSpec stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (spec.length < 5 || [spec characterAtIndex:1] != '[' || ![spec hasSuffix:@"]"]) continue;
        BOOL isClassMethod = [spec characterAtIndex:0] == '+';
        NSString *inner = [spec substringWithRange:NSMakeRange(2, spec.length - 3)];
        NSRange space = [inner rangeOfString:@" "];
        if (space.location == NSNotFound) continue;
        Class cls = [SZRuntime classNamed:[inner substringToIndex:space.location]];
        SEL selector = NSSelectorFromString([inner substringFromIndex:space.location + 1]);
        NSError *error = nil;
        if (cls && [SZTracer.sharedTracer traceClass:cls selector:selector isClassMethod:isClassMethod error:&error]) {
            [_log appendNote:[NSString stringWithFormat:@"▶ tracing %@ (launch argument)", spec]];
        } else {
            [_log appendNote:[NSString stringWithFormat:@"✗ cannot trace %@: %@", spec, error.localizedDescription ?: @"class not loaded"]];
        }
    }
    if (trace.length) [_detail refreshTraceStates];
}

#pragma mark - Toolbar

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[SZToolbarOpen, SZToolbarExport, SZToolbarUntraceAll, NSToolbarFlexibleSpaceItemIdentifier, SZToolbarSearch];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([identifier isEqualToString:SZToolbarSearch]) {
        NSSearchToolbarItem *item = [[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier];
        item.label = @"Search";
        item.preferredWidthForSearchField = 300;
        item.searchField.placeholderString = @"Class name, or sel:fragment";
        item.searchField.delegate = self;
        item.searchField.target = self;
        item.searchField.action = @selector(searchChanged:);
        item.searchField.sendsWholeSearchString = NO;
        _searchField = item.searchField;
        return item;
    }
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.target = self;
    if ([identifier isEqualToString:SZToolbarOpen]) {
        item.label = @"Open Bundle";
        item.toolTip = @"Load a framework, dylib or plug-in bundle into Swizzlescope (⌘O)";
        item.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:@"Open"];
        item.action = @selector(openBundle:);
    } else if ([identifier isEqualToString:SZToolbarExport]) {
        item.label = @"Export Header";
        item.toolTip = @"Save a class-dump style header for the selected class (⇧⌘E)";
        item.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:@"Export"];
        item.action = @selector(exportHeader:);
    } else if ([identifier isEqualToString:SZToolbarUntraceAll]) {
        item.label = @"Untrace All";
        item.toolTip = @"Remove every trace and restore the original implementations (⇧⌘U)";
        item.image = [NSImage imageWithSystemSymbolName:@"stop.circle" accessibilityDescription:@"Untrace all"];
        item.action = @selector(untraceAll:);
    }
    return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if (item.action == @selector(exportHeader:)) return _detail.currentInfo != nil;
    if (item.action == @selector(untraceAll:)) return SZTracer.sharedTracer.tracedMethodCount > 0;
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(exportHeader:)) return _detail.currentInfo != nil;
    return YES;
}

#pragma mark - Actions

- (void)openBundle:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.message = @"Choose a .framework, .bundle or .dylib to load into Swizzlescope. App main executables cannot be loaded.";
    panel.prompt = @"Load";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        [self loadBundleAtPath:panel.URL.path];
    }];
}

- (void)loadBundleAtPath:(NSString *)path {
    NSError *error = nil;
    NSString *imagePath = nil;
    if (![SZLoader loadBundleAtPath:path loadedImagePath:&imagePath error:&error]) {
        NSAlert *alert = [NSAlert alertWithError:error];
        alert.messageText = [NSString stringWithFormat:@"Could not load %@", path.lastPathComponent];
        alert.informativeText = error.localizedDescription;
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        [_log appendNote:[NSString stringWithFormat:@"✗ load failed: %@", error.localizedDescription]];
        return;
    }
    NSUInteger count = [SZRuntime classNamesInImagePath:imagePath].count;
    [_log appendNote:[NSString stringWithFormat:@"✓ loaded %@ (%lu Objective-C classes)", imagePath, (unsigned long)count]];
    [_list reloadImagesSelectingPath:imagePath];
    if (count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Loaded, but no Objective-C classes";
        alert.informativeText = [NSString stringWithFormat:@"%@ was loaded into the process but contributes no Objective-C classes.", path.lastPathComponent];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

- (void)exportHeader:(id)sender {
    [_detail exportHeader:sender];
}

- (void)focusSearch:(id)sender {
    [self.window makeFirstResponder:_searchField];
}

- (void)untraceAll:(id)sender {
    NSUInteger count = SZTracer.sharedTracer.tracedMethodCount;
    [SZTracer.sharedTracer untraceAll];
    [_log appendNote:[NSString stringWithFormat:@"■ untraced %lu method(s)", (unsigned long)count]];
    [_detail refreshTraceStates];
}

- (void)clearLog:(id)sender {
    [_log clearLog:sender];
}

- (void)searchChanged:(id)sender {
    [_list setFilter:_searchField.stringValue];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _searchField) [_list setFilter:_searchField.stringValue];
}

#pragma mark - SZClassListDelegate

- (void)classList:(SZClassListViewController *)list didSelectClass:(Class)cls {
    [_detail showClass:cls];
}

- (void)classListDidResetFilter:(SZClassListViewController *)list {
    _searchField.stringValue = @"";
}

#pragma mark - SZClassDetailDelegate

- (void)classDetail:(SZClassDetailViewController *)detail requestsNavigationToClassNamed:(NSString *)name {
    [_list selectClassNamed:name];
}

- (void)classDetail:(SZClassDetailViewController *)detail didLogMessage:(NSString *)message {
    [_log appendNote:message];
}

@end
