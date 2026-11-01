#import "SZClassDetailViewController.h"
#import "SZPlaygroundViewController.h"
#import "SZHeaderWriter.h"
#import "SZTracer.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SZClassDetailViewController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTabViewDelegate>
@end

@implementation SZClassDetailViewController {
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSPopUpButton *_lineagePopup;
    NSTabView *_tabView;
    NSTableView *_methodsTable;
    NSTableView *_ivarsTable;
    NSTableView *_propertiesTable;
    NSTableView *_protocolsTable;
    NSSearchField *_methodFilter;
    NSTextView *_headerText;
    SZPlaygroundViewController *_playground;
    NSArray<SZMethodInfo *> *_allMethods;
    NSArray<SZMethodInfo *> *_shownMethods;
}

#pragma mark - View construction

static NSTableView *SZMakeTable(NSArray<NSArray *> *columns, id owner, NSScrollView **outScroll) {
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    for (NSArray *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        column.minWidth = 30;
        column.resizingMask = NSTableColumnUserResizingMask | NSTableColumnAutoresizingMask;
        [table addTableColumn:column];
    }
    table.dataSource = owner;
    table.delegate = owner;
    table.usesAlternatingRowBackgroundColors = YES;
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    table.allowsColumnReordering = NO;
    table.rowHeight = 19;
    table.style = NSTableViewStylePlain;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    *outScroll = scroll;
    return table;
}

static void SZPin(NSView *child, NSView *parent, NSEdgeInsets insets) {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:insets.top],
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:insets.left],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-insets.right],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-insets.bottom],
    ]];
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 600)];

    _titleLabel = [NSTextField labelWithString:@"Select a class"];
    _titleLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _subtitleLabel = [NSTextField labelWithString:@"Pick an image in the sidebar, or search by class name or sel:fragment."];
    _subtitleLabel.font = [NSFont systemFontOfSize:11];
    _subtitleLabel.textColor = NSColor.secondaryLabelColor;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _subtitleLabel.selectable = YES;

    _lineagePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    _lineagePopup.controlSize = NSControlSizeSmall;
    _lineagePopup.font = [NSFont systemFontOfSize:11];
    [_lineagePopup addItemWithTitle:@"Superclasses"];
    _lineagePopup.target = self;
    _lineagePopup.action = @selector(lineageChosen:);

    NSStackView *titleRow = [NSStackView stackViewWithViews:@[_titleLabel, _lineagePopup]];
    titleRow.spacing = 12;
    [_titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *header = [NSStackView stackViewWithViews:@[titleRow, _subtitleLabel]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeLeading;
    header.spacing = 4;
    header.edgeInsets = NSEdgeInsetsMake(12, 16, 8, 16);
    header.translatesAutoresizingMaskIntoConstraints = NO;

    _tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
    _tabView.translatesAutoresizingMaskIntoConstraints = NO;
    _tabView.controlSize = NSControlSizeSmall;
    _tabView.font = [NSFont systemFontOfSize:11];
    _tabView.delegate = self;

    // Methods tab: filter bar + table.
    NSScrollView *methodsScroll = nil;
    _methodsTable = SZMakeTable(@[@[@"trace", @"Trace", @44], @[@"kind", @"", @24], @[@"selector", @"Selector", @260],
                                  @[@"declaration", @"Declaration", @420], @[@"encoding", @"Encoding", @160]], self, &methodsScroll);
    _methodFilter = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _methodFilter.placeholderString = @"Filter selectors";
    _methodFilter.controlSize = NSControlSizeSmall;
    _methodFilter.font = [NSFont systemFontOfSize:11];
    _methodFilter.delegate = self;
    _methodFilter.sendsWholeSearchString = NO;
    NSButton *traceShown = [NSButton buttonWithTitle:@"Trace Shown" target:self action:@selector(traceShown:)];
    NSButton *untraceShown = [NSButton buttonWithTitle:@"Untrace Shown" target:self action:@selector(untraceShown:)];
    for (NSButton *button in @[traceShown, untraceShown]) {
        button.controlSize = NSControlSizeSmall;
        button.font = [NSFont systemFontOfSize:11];
    }
    NSStackView *methodBar = [NSStackView stackViewWithViews:@[_methodFilter, traceShown, untraceShown]];
    methodBar.spacing = 8;
    methodBar.edgeInsets = NSEdgeInsetsMake(6, 6, 6, 6);
    methodBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_methodFilter.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
    NSView *methodsView = [[NSView alloc] initWithFrame:NSZeroRect];
    [methodsView addSubview:methodBar];
    [methodsView addSubview:methodsScroll];
    [NSLayoutConstraint activateConstraints:@[
        [methodBar.topAnchor constraintEqualToAnchor:methodsView.topAnchor],
        [methodBar.leadingAnchor constraintEqualToAnchor:methodsView.leadingAnchor],
        [methodsScroll.topAnchor constraintEqualToAnchor:methodBar.bottomAnchor],
        [methodsScroll.leadingAnchor constraintEqualToAnchor:methodsView.leadingAnchor],
        [methodsScroll.trailingAnchor constraintEqualToAnchor:methodsView.trailingAnchor],
        [methodsScroll.bottomAnchor constraintEqualToAnchor:methodsView.bottomAnchor],
    ]];
    [self addTab:@"Methods" view:methodsView];

    NSScrollView *scroll = nil;
    _ivarsTable = SZMakeTable(@[@[@"name", @"Name", @200], @[@"type", @"Type", @260], @[@"offset", @"Offset", @70], @[@"encoding", @"Encoding", @200]], self, &scroll);
    [self addTab:@"Ivars" view:scroll];
    _propertiesTable = SZMakeTable(@[@[@"name", @"Name", @180], @[@"declaration", @"Declaration", @460], @[@"attributes", @"Attributes", @200]], self, &scroll);
    [self addTab:@"Properties" view:scroll];
    _protocolsTable = SZMakeTable(@[@[@"name", @"Protocol", @400]], self, &scroll);
    [self addTab:@"Protocols" view:scroll];

    NSScrollView *headerScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    headerScroll.hasVerticalScroller = YES;
    headerScroll.hasHorizontalScroller = YES;
    _headerText = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 800, 400)];
    _headerText.editable = NO;
    _headerText.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _headerText.textContainerInset = NSMakeSize(8, 8);
    _headerText.minSize = NSMakeSize(0, 0);
    _headerText.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _headerText.verticallyResizable = YES;
    _headerText.horizontallyResizable = YES;
    _headerText.autoresizingMask = NSViewWidthSizable;
    _headerText.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _headerText.textContainer.widthTracksTextView = NO;
    headerScroll.documentView = _headerText;
    [self addTab:@"Header" view:headerScroll];

    _playground = [[SZPlaygroundViewController alloc] init];
    NSTabViewItem *playItem = [NSTabViewItem tabViewItemWithViewController:_playground];
    playItem.label = @"Playground";
    [_tabView addTabViewItem:playItem];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:header];
    [root addSubview:separator];
    [root addSubview:_tabView];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [titleRow.widthAnchor constraintEqualToAnchor:header.widthAnchor constant:-32],
        [_subtitleLabel.widthAnchor constraintEqualToAnchor:header.widthAnchor constant:-32],
        [separator.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_tabView.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:4],
        [_tabView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:8],
        [_tabView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-8],
        [_tabView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-8],
    ]];
    self.view = root;
}

- (void)addTab:(NSString *)label view:(NSView *)view {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:label];
    item.label = label;
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    [container addSubview:view];
    SZPin(view, container, NSEdgeInsetsMake(0, 0, 0, 0));
    item.view = container;
    [_tabView addTabViewItem:item];
}

#pragma mark - Content

- (void)showClass:(Class)cls {
    if (!self.viewLoaded) [self loadView];
    _currentInfo = cls ? [SZClassInfo infoForClass:cls] : nil;
    _playground.targetClass = cls;
    [_lineagePopup removeAllItems];
    [_lineagePopup addItemWithTitle:@"Superclasses"];
    if (!_currentInfo) {
        _titleLabel.stringValue = @"Select a class";
        _subtitleLabel.stringValue = @"Pick an image in the sidebar, or search by class name or sel:fragment.";
        _allMethods = _shownMethods = @[];
        _headerText.string = @"";
        [self reloadTables];
        return;
    }
    SZClassInfo *info = _currentInfo;
    _titleLabel.stringValue = info.name;
    NSMutableArray<NSString *> *facts = [NSMutableArray array];
    [facts addObject:info.superclassChain.count ? [@": " stringByAppendingString:[info.superclassChain componentsJoinedByString:@" : "]] : @"(root class)"];
    [facts addObject:[NSString stringWithFormat:@"%zu bytes/instance", info.instanceSize]];
    [facts addObject:[NSString stringWithFormat:@"%lu ivars", (unsigned long)info.ivars.count]];
    [facts addObject:[NSString stringWithFormat:@"%lu + %lu methods", (unsigned long)info.classMethods.count, (unsigned long)info.instanceMethods.count]];
    [facts addObject:info.imagePath ?: @"no image (created at runtime)"];
    _subtitleLabel.stringValue = [facts componentsJoinedByString:@"  ·  "];
    _subtitleLabel.toolTip = info.imagePath;
    for (NSString *name in info.superclassChain) [_lineagePopup addItemWithTitle:name];
    _lineagePopup.enabled = info.superclassChain.count > 0;

    NSMutableArray<SZMethodInfo *> *methods = [NSMutableArray arrayWithArray:info.classMethods];
    [methods addObjectsFromArray:info.instanceMethods];
    _allMethods = methods;
    [self applyMethodFilter];
    _headerText.string = [SZHeaderWriter headerForClass:info];
    [self reloadTables];
}

- (void)reloadTables {
    [_methodsTable reloadData];
    [_ivarsTable reloadData];
    [_propertiesTable reloadData];
    [_protocolsTable reloadData];
}

- (void)applyMethodFilter {
    NSString *filter = [_methodFilter.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (filter.length == 0) {
        _shownMethods = _allMethods;
    } else {
        NSMutableArray *shown = [NSMutableArray array];
        for (SZMethodInfo *m in _allMethods) {
            if ([m.name rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) [shown addObject:m];
        }
        _shownMethods = shown;
    }
    [_methodsTable reloadData];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _methodFilter) [self applyMethodFilter];
}

- (void)refreshTraceStates {
    [_methodsTable reloadData];
}

- (void)selectTabLabeled:(NSString *)label {
    if (!self.viewLoaded) [self loadView];
    for (NSTabViewItem *item in _tabView.tabViewItems) {
        if ([item.label caseInsensitiveCompare:label] == NSOrderedSame) {
            [_tabView selectTabViewItem:item];
            return;
        }
    }
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if (tabViewItem.viewController == _playground) [_playground focusSelectorField];
}

- (void)lineageChosen:(NSPopUpButton *)sender {
    NSString *name = sender.selectedItem.title;
    if (name.length && sender.indexOfSelectedItem > 0) [self.delegate classDetail:self requestsNavigationToClassNamed:name];
}

#pragma mark - Tracing

- (BOOL)isTraced:(SZMethodInfo *)method {
    return [SZTracer.sharedTracer isTracingClass:_currentInfo.cls selector:method.selector isClassMethod:method.isClassMethod];
}

- (BOOL)setMethod:(SZMethodInfo *)method traced:(BOOL)traced reportErrors:(BOOL)report {
    SZTracer *tracer = SZTracer.sharedTracer;
    if (!traced) {
        if ([tracer untraceClass:_currentInfo.cls selector:method.selector isClassMethod:method.isClassMethod]) {
            [self.delegate classDetail:self didLogMessage:[NSString stringWithFormat:@"■ untraced %@", method.qualifiedName]];
        }
        return YES;
    }
    NSError *error = nil;
    if ([tracer traceClass:_currentInfo.cls selector:method.selector isClassMethod:method.isClassMethod error:&error]) {
        [self.delegate classDetail:self didLogMessage:[NSString stringWithFormat:@"▶ tracing %@", method.qualifiedName]];
        return YES;
    }
    [self.delegate classDetail:self didLogMessage:[NSString stringWithFormat:@"✗ cannot trace %@: %@", method.qualifiedName, error.localizedDescription]];
    if (report) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Cannot trace %@", method.qualifiedName];
        alert.informativeText = error.localizedDescription ?: @"";
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    }
    return NO;
}

- (void)toggleTrace:(NSButton *)sender {
    NSInteger row = [_methodsTable rowForView:sender];
    if (row < 0 || (NSUInteger)row >= _shownMethods.count) return;
    SZMethodInfo *method = _shownMethods[(NSUInteger)row];
    BOOL wantTraced = sender.state == NSControlStateValueOn;
    if (![self setMethod:method traced:wantTraced reportErrors:YES]) sender.state = NSControlStateValueOff;
}

- (void)traceShown:(id)sender {
    NSUInteger ok = 0, failed = 0;
    for (SZMethodInfo *method in _shownMethods) {
        if ([self setMethod:method traced:YES reportErrors:NO]) ok++; else failed++;
    }
    [self.delegate classDetail:self didLogMessage:[NSString stringWithFormat:@"▶ traced %lu method(s), %lu refused", (unsigned long)ok, (unsigned long)failed]];
    [_methodsTable reloadData];
}

- (void)untraceShown:(id)sender {
    for (SZMethodInfo *method in _shownMethods) [self setMethod:method traced:NO reportErrors:NO];
    [_methodsTable reloadData];
}

#pragma mark - Export

- (void)exportHeader:(id)sender {
    if (!_currentInfo) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = [_currentInfo.name stringByAppendingPathExtension:@"h"];
    panel.allowedContentTypes = @[UTTypeCHeader];
    NSString *header = [SZHeaderWriter headerForClass:_currentInfo];
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        NSError *error = nil;
        if ([header writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            [self.delegate classDetail:self didLogMessage:[NSString stringWithFormat:@"✓ exported %@", panel.URL.path]];
        } else {
            [self.delegate classDetail:self didLogMessage:[NSString stringWithFormat:@"✗ export failed: %@", error.localizedDescription]];
        }
    }];
}

#pragma mark - Tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _methodsTable) return (NSInteger)_shownMethods.count;
    if (tableView == _ivarsTable) return (NSInteger)_currentInfo.ivars.count;
    if (tableView == _propertiesTable) return (NSInteger)_currentInfo.properties.count;
    if (tableView == _protocolsTable) return (NSInteger)_currentInfo.protocolNames.count;
    return 0;
}

- (NSString *)textForTable:(NSTableView *)tableView column:(NSString *)column row:(NSUInteger)row {
    if (tableView == _methodsTable) {
        SZMethodInfo *m = _shownMethods[row];
        if ([column isEqualToString:@"kind"]) return m.isClassMethod ? @"+" : @"-";
        if ([column isEqualToString:@"selector"]) return m.name;
        if ([column isEqualToString:@"declaration"]) return m.declaration;
        return m.typeEncoding;
    }
    if (tableView == _ivarsTable) {
        SZIvarInfo *ivar = _currentInfo.ivars[row];
        if ([column isEqualToString:@"name"]) return ivar.name;
        if ([column isEqualToString:@"type"]) return ivar.decodedType;
        if ([column isEqualToString:@"offset"]) return [NSString stringWithFormat:@"%ld", (long)ivar.offset];
        return ivar.typeEncoding;
    }
    if (tableView == _propertiesTable) {
        SZPropertyInfo *prop = _currentInfo.properties[row];
        if ([column isEqualToString:@"name"]) return prop.name;
        if ([column isEqualToString:@"declaration"]) return prop.declaration;
        return prop.attributes;
    }
    return _currentInfo.protocolNames[row];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *column = tableColumn.identifier;
    if (tableView == _methodsTable && [column isEqualToString:@"trace"]) {
        NSButton *box = [tableView makeViewWithIdentifier:@"SZTraceBox" owner:self];
        if (!box) {
            box = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleTrace:)];
            box.identifier = @"SZTraceBox";
            box.controlSize = NSControlSizeSmall;
        }
        box.state = [self isTraced:_shownMethods[(NSUInteger)row]] ? NSControlStateValueOn : NSControlStateValueOff;
        return box;
    }
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"SZTextCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 19)];
        cell.identifier = @"SZTextCell";
        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.selectable = YES;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    BOOL mono = [column isEqualToString:@"declaration"] || [column isEqualToString:@"encoding"] || [column isEqualToString:@"attributes"]
             || [column isEqualToString:@"type"] || [column isEqualToString:@"selector"];
    cell.textField.font = mono ? [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular] : [NSFont systemFontOfSize:11];
    NSString *text = [self textForTable:tableView column:column row:(NSUInteger)row];
    cell.textField.stringValue = text;
    cell.toolTip = text;
    return cell;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return tableView != _methodsTable;
}

@end
