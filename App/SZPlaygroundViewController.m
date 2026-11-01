#import "SZPlaygroundViewController.h"
#import "SZClassInfo.h"
#import "SZTraceEvent.h"
#import "SZValueParser.h"
#import <objc/runtime.h>

@implementation SZPlaygroundViewController {
    NSTextField *_classLabel;
    NSTextField *_instanceLabel;
    NSPopUpButton *_receiverPopup;
    NSTextField *_selectorField;
    NSTextField *_argsField;
    NSTextView *_output;
    NSButton *_createButton;
    NSButton *_invokeButton;
    NSButton *_ivarsButton;
    id _instance;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];

    _classLabel = [NSTextField labelWithString:@"No class selected"];
    _classLabel.font = [NSFont boldSystemFontOfSize:12];

    _createButton = [NSButton buttonWithTitle:@"Create Instance ([[Class alloc] init])" target:self action:@selector(createInstance:)];
    _createButton.controlSize = NSControlSizeSmall;
    _createButton.font = [NSFont systemFontOfSize:11];
    _ivarsButton = [NSButton buttonWithTitle:@"Dump Ivars" target:self action:@selector(dumpIvars:)];
    _ivarsButton.controlSize = NSControlSizeSmall;
    _ivarsButton.font = [NSFont systemFontOfSize:11];
    _instanceLabel = [NSTextField labelWithString:@"Instance: none"];
    _instanceLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _instanceLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *instanceRow = [NSStackView stackViewWithViews:@[_createButton, _ivarsButton, _instanceLabel]];
    instanceRow.spacing = 8;

    _receiverPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_receiverPopup addItemsWithTitles:@[@"Instance", @"Class"]];
    _receiverPopup.controlSize = NSControlSizeSmall;
    _receiverPopup.font = [NSFont systemFontOfSize:11];
    _selectorField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _selectorField.placeholderString = @"selector, e.g. addInt:toInt:";
    _selectorField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _selectorField.target = self;
    _selectorField.action = @selector(invoke:);
    _argsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _argsField.placeholderString = @"arguments, comma separated: 2, 3   |   \"text\", YES, {0, 0, 10, 10}, NSString, nil";
    _argsField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _argsField.target = self;
    _argsField.action = @selector(invoke:);
    _invokeButton = [NSButton buttonWithTitle:@"Invoke" target:self action:@selector(invoke:)];
    _invokeButton.controlSize = NSControlSizeSmall;
    _invokeButton.font = [NSFont systemFontOfSize:11];
    _invokeButton.keyEquivalent = @"\r";
    NSStackView *invokeRow = [NSStackView stackViewWithViews:@[_receiverPopup, _selectorField, _argsField, _invokeButton]];
    invokeRow.spacing = 8;
    [_selectorField.widthAnchor constraintEqualToConstant:220].active = YES;
    [_argsField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *hint = [NSTextField wrappingLabelWithString:
        @"Arguments: numbers, YES/NO, \"quoted strings\" (become NSString), JSON arrays or objects, nil, class names for Class, selector names for SEL, {x, y, w, h} for structs. Return values and ivars are rendered with the same describer the tracer uses."];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = NSColor.secondaryLabelColor;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    _output = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 800, 300)];
    _output.editable = NO;
    _output.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _output.textContainerInset = NSMakeSize(6, 6);
    _output.minSize = NSMakeSize(0, 0);
    _output.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _output.verticallyResizable = YES;
    _output.autoresizingMask = NSViewWidthSizable;
    _output.textContainer.widthTracksTextView = YES;
    scroll.documentView = _output;

    NSStackView *stack = [NSStackView stackViewWithViews:@[_classLabel, instanceRow, invokeRow, hint, scroll]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [invokeRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [instanceRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [hint.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24],
    ]];
    self.view = root;
}

- (void)setTargetClass:(Class)targetClass {
    if (targetClass == _targetClass) return;
    _targetClass = targetClass;
    _instance = nil;
    if (!self.viewLoaded) [self loadView];
    _classLabel.stringValue = targetClass ? [NSString stringWithFormat:@"Playground for %s", class_getName(targetClass)] : @"No class selected";
    _instanceLabel.stringValue = @"Instance: none";
    _createButton.enabled = targetClass != Nil;
    _invokeButton.enabled = targetClass != Nil;
    _ivarsButton.enabled = NO;
}

- (void)focusSelectorField {
    [self.view.window makeFirstResponder:_selectorField];
}

- (void)log:(NSString *)line {
    NSDictionary *attrs = @{NSFontAttributeName: _output.font, NSForegroundColorAttributeName: NSColor.labelColor};
    [_output.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"] attributes:attrs]];
    [_output scrollRangeToVisible:NSMakeRange(_output.textStorage.length, 0)];
}

- (void)createInstance:(id)sender {
    if (!_targetClass) return;
    @try {
        _instance = [[_targetClass alloc] init];
    } @catch (NSException *exception) {
        [self log:[NSString stringWithFormat:@"✗ init threw %@: %@", exception.name, exception.reason]];
        return;
    }
    if (!_instance) {
        [self log:@"✗ init returned nil"];
        return;
    }
    _instanceLabel.stringValue = [NSString stringWithFormat:@"Instance: %@", SZDescribeObject(_instance)];
    _ivarsButton.enabled = YES;
    [self log:[NSString stringWithFormat:@"✓ created %@", SZDescribeObject(_instance)]];
}

- (void)dumpIvars:(id)sender {
    if (!_instance) return;
    const uint8_t *base = (const uint8_t *)(__bridge void *)_instance;
    for (Class cls = object_getClass(_instance); cls != Nil; cls = class_getSuperclass(cls)) {
        SZClassInfo *info = [SZClassInfo infoForClass:cls];
        if (info.ivars.count == 0) continue;
        [self log:[NSString stringWithFormat:@"— ivars of %@", info.name]];
        for (SZIvarInfo *ivar in info.ivars) {
            if (ivar.typeEncoding.length == 0) {
                [self log:[NSString stringWithFormat:@"  %@ = (no type encoding)", ivar.name]];
                continue;
            }
            NSString *value = SZDescribeValue(ivar.typeEncoding.UTF8String, base + ivar.offset);
            [self log:[NSString stringWithFormat:@"  %@ %@ = %@", ivar.decodedType, ivar.name, value]];
        }
    }
}

- (void)invoke:(id)sender {
    if (!_targetClass) return;
    BOOL useClass = _receiverPopup.indexOfSelectedItem == 1;
    if (!useClass && !_instance) [self createInstance:nil];
    id receiver = useClass ? (id)_targetClass : _instance;
    if (!receiver) {
        [self log:@"✗ No instance available. Switch the receiver to Class or fix init."];
        return;
    }
    NSString *selectorName = [_selectorField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (selectorName.length == 0) return;
    SEL selector = NSSelectorFromString(selectorName);
    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
    if (!signature) {
        [self log:[NSString stringWithFormat:@"✗ %@ does not respond to %@", SZDescribeObject(receiver), selectorName]];
        return;
    }
    NSArray<NSString *> *argTexts = [SZValueParser splitArguments:_argsField.stringValue];
    NSUInteger expected = signature.numberOfArguments - 2;
    if (argTexts.count != expected) {
        [self log:[NSString stringWithFormat:@"✗ %@ takes %lu argument(s), got %lu", selectorName, (unsigned long)expected, (unsigned long)argTexts.count]];
        return;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    NSMutableArray *retained = [NSMutableArray array];
    for (NSUInteger i = 0; i < expected; i++) {
        const char *type = [signature getArgumentTypeAtIndex:i + 2];
        NSUInteger size = 0;
        @try { NSGetSizeAndAlignment(type, &size, NULL); } @catch (NSException *e) { size = 0; }
        if (size == 0) {
            [self log:[NSString stringWithFormat:@"✗ argument %lu has an unsupported type %s", (unsigned long)(i + 1), type]];
            return;
        }
        void *buffer = calloc(1, size < 16 ? 16 : size);
        NSString *error = nil;
        BOOL ok = [SZValueParser parseText:argTexts[i] type:type intoBuffer:buffer length:size retaining:retained error:&error];
        if (ok) [invocation setArgument:buffer atIndex:(NSInteger)i + 2];
        free(buffer);
        if (!ok) {
            [self log:[NSString stringWithFormat:@"✗ argument %lu: %@", (unsigned long)(i + 1), error]];
            return;
        }
    }
    @try {
        [invocation invoke];
    } @catch (NSException *exception) {
        [self log:[NSString stringWithFormat:@"✗ %@ threw %@: %@", selectorName, exception.name, exception.reason]];
        return;
    }
    NSString *result = @"void";
    NSUInteger length = signature.methodReturnLength;
    if (length > 0) {
        void *buffer = calloc(1, length < 16 ? 16 : length);
        [invocation getReturnValue:buffer];
        result = SZDescribeValue(signature.methodReturnType, buffer);
        free(buffer);
    }
    [self log:[NSString stringWithFormat:@"%@[%s %@] (%@) -> %@", useClass ? @"+" : @"-", class_getName(_targetClass), selectorName,
               [argTexts componentsJoinedByString:@", "], result]];
}

@end
