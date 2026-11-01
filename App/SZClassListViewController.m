#import "SZClassListViewController.h"
#import "SZRuntime.h"

@interface SZImageNode : NSObject
@property (nonatomic, strong) SZImage *image;
@property (nonatomic, copy, nullable) NSArray<NSString *> *loadedClassNames;
- (NSArray<NSString *> *)classNames;
@end

@implementation SZImageNode
- (NSArray<NSString *> *)classNames {
    if (!_loadedClassNames) _loadedClassNames = [SZRuntime classNamesInImagePath:_image.path];
    return _loadedClassNames;
}
@end

@interface SZClassListViewController () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation SZClassListViewController {
    NSOutlineView *_outline;
    NSScrollView *_scroll;
    NSTextField *_footer;
    NSArray<SZImageNode *> *_nodes;
    NSArray<NSString *> *_allNames;
    NSArray<NSString *> *_filtered;
    NSString *_filter;
    NSUInteger _searchGeneration;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 600)];

    _outline = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.title = @"Classes";
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_outline addTableColumn:column];
    _outline.outlineTableColumn = column;
    _outline.headerView = nil;
    _outline.dataSource = self;
    _outline.delegate = self;
    _outline.style = NSTableViewStyleSourceList;
    _outline.indentationPerLevel = 14;
    _outline.autoresizesOutlineColumn = YES;
    _outline.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _outline.allowsEmptySelection = YES;
    _outline.rowHeight = 20;

    _scroll = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scroll.documentView = _outline;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.drawsBackground = NO;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;

    _footer = [NSTextField labelWithString:@""];
    _footer.font = [NSFont systemFontOfSize:11];
    _footer.textColor = NSColor.secondaryLabelColor;
    _footer.lineBreakMode = NSLineBreakByTruncatingTail;
    _footer.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:_scroll];
    [root addSubview:_footer];
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_footer.topAnchor constraintEqualToAnchor:_scroll.bottomAnchor constant:4],
        [_footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:12],
        [_footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
        [_footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-6],
    ]];
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadImagesSelectingPath:nil];
}

- (void)viewDidLayout {
    [super viewDidLayout];
    // Keep the single column as wide as the scroll view so labels are not truncated.
    CGFloat width = NSWidth(_scroll.contentView.bounds) - 4;
    if (width > 50 && fabs(_outline.tableColumns.firstObject.width - width) > 1) {
        _outline.tableColumns.firstObject.width = width;
    }
}

- (void)reloadImagesSelectingPath:(NSString *)path {
    NSMutableArray<SZImageNode *> *nodes = [NSMutableArray array];
    for (SZImage *image in [SZRuntime loadedImages]) {
        if (image.classCount == 0) continue;
        SZImageNode *node = [[SZImageNode alloc] init];
        node.image = image;
        [nodes addObject:node];
    }
    _nodes = nodes;
    _allNames = nil;
    [_outline reloadData];
    [_outline deselectAll:nil];
    [self updateFooter];
    if (path) {
        for (SZImageNode *node in _nodes) {
            if (![node.image.path isEqualToString:path]) continue;
            [self setFilter:@""];
            [self.delegate classListDidResetFilter:self];
            [_outline expandItem:node];
            NSInteger row = [_outline rowForItem:node];
            if (node.classNames.count) row = [_outline rowForItem:node.classNames.firstObject];
            if (row >= 0) {
                [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
                [_outline scrollRowToVisible:row];
            }
            break;
        }
    }
}

- (void)updateFooter {
    if (_filter.length) {
        _footer.stringValue = [NSString stringWithFormat:@"%lu match%@", (unsigned long)_filtered.count, _filtered.count == 1 ? @"" : @"es"];
        return;
    }
    NSUInteger classes = 0;
    for (SZImageNode *node in _nodes) classes += node.image.classCount;
    _footer.stringValue = [NSString stringWithFormat:@"%lu images · %lu classes", (unsigned long)_nodes.count, (unsigned long)classes];
}

- (void)setFilter:(NSString *)filter {
    filter = [filter stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
    if ([filter isEqualToString:_filter ?: @""]) return;
    _filter = filter;
    _searchGeneration++;
    if (filter.length == 0) {
        _filtered = nil;
        [_outline reloadData];
        [self updateFooter];
        return;
    }
    if ([filter.lowercaseString hasPrefix:@"sel:"]) {
        NSString *fragment = [filter substringFromIndex:4];
        if (fragment.length < 2) {
            _filtered = @[];
            [_outline reloadData];
            _footer.stringValue = @"Type at least two characters after sel:";
            return;
        }
        NSUInteger generation = _searchGeneration;
        _footer.stringValue = @"Searching selectors…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray<NSString *> *result = [SZRuntime classNamesImplementingSelectorContaining:fragment];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_searchGeneration) return;
                self->_filtered = result;
                [self->_outline reloadData];
                [self updateFooter];
            });
        });
        return;
    }
    if (!_allNames) _allNames = [SZRuntime allClassNames];
    NSMutableArray<NSString *> *prefix = [NSMutableArray array];
    NSMutableArray<NSString *> *contains = [NSMutableArray array];
    for (NSString *name in _allNames) {
        NSRange range = [name rangeOfString:filter options:NSCaseInsensitiveSearch];
        if (range.location == NSNotFound) continue;
        if (range.location == 0) [prefix addObject:name]; else [contains addObject:name];
        if (prefix.count + contains.count >= 4000) break;
    }
    _filtered = [prefix arrayByAddingObjectsFromArray:contains];
    [_outline reloadData];
    [self updateFooter];
}

- (void)selectClassNamed:(NSString *)name {
    Class cls = [SZRuntime classNamed:name];
    if (!cls) return;
    NSString *imagePath = [SZRuntime imagePathForClass:cls];
    if (_filter.length) {
        [self setFilter:@""];
        [self.delegate classListDidResetFilter:self];
    }
    for (SZImageNode *node in _nodes) {
        if (![node.image.path isEqualToString:imagePath]) continue;
        [_outline expandItem:node];
        NSUInteger index = [node.classNames indexOfObject:name];
        if (index == NSNotFound) return;
        NSInteger row = [_outline rowForItem:node.classNames[index]];
        if (row < 0) return;
        [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [_outline scrollRowToVisible:row];
        return;
    }
    // Class has no image (created at runtime): show it directly without changing the selection.
    [self.delegate classList:self didSelectClass:cls];
}

#pragma mark - Outline data source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) return (NSInteger)(_filter.length ? _filtered.count : _nodes.count);
    if ([item isKindOfClass:[SZImageNode class]]) return (NSInteger)[(SZImageNode *)item classNames].count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) return _filter.length ? _filtered[(NSUInteger)index] : _nodes[(NSUInteger)index];
    return [(SZImageNode *)item classNames][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[SZImageNode class]];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"SZClassCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
        cell.identifier = @"SZClassCell";
        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    if ([item isKindOfClass:[SZImageNode class]]) {
        SZImageNode *node = item;
        cell.textField.stringValue = [NSString stringWithFormat:@"%@  (%lu)", node.image.name, (unsigned long)node.image.classCount];
        cell.textField.font = [NSFont boldSystemFontOfSize:12];
        cell.textField.textColor = NSColor.labelColor;
        cell.toolTip = node.image.path;
    } else {
        cell.textField.stringValue = item;
        cell.textField.font = [NSFont systemFontOfSize:12];
        cell.textField.textColor = NSColor.labelColor;
        cell.toolTip = nil;
    }
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    id item = [_outline itemAtRow:_outline.selectedRow];
    if ([item isKindOfClass:[NSString class]]) {
        [self.delegate classList:self didSelectClass:[SZRuntime classNamed:item]];
    } else if (item == nil) {
        [self.delegate classList:self didSelectClass:Nil];
    }
}

@end
