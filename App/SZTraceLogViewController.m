#import "SZTraceLogViewController.h"
#import "SZTracer.h"

static const NSUInteger kOSMaxLogLines = 20000;
static const NSUInteger kOSTrimLogLines = 5000;

@implementation SZTraceLogViewController {
    NSTextView *_textView;
    NSScrollView *_scroll;
    NSButton *_pauseButton;
    NSTextField *_status;
    NSTimer *_timer;
    NSUInteger _lineCount;
    uint64_t _shownEvents;
    BOOL _followTail;
    BOOL _scrollingProgrammatically;
    NSDictionary<NSAttributedStringKey, id> *_eventAttributes;
    NSDictionary<NSAttributedStringKey, id> *_noteAttributes;
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 240)];

    NSTextField *title = [NSTextField labelWithString:@"Trace Log"];
    title.font = [NSFont boldSystemFontOfSize:12];

    _pauseButton = [NSButton checkboxWithTitle:@"Pause" target:nil action:NULL];
    _pauseButton.font = [NSFont systemFontOfSize:12];

    NSButton *clear = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearLog:)];
    clear.bezelStyle = NSBezelStyleRounded;
    clear.controlSize = NSControlSizeSmall;
    clear.font = [NSFont systemFontOfSize:11];

    NSButton *untrace = [NSButton buttonWithTitle:@"Untrace All" target:nil action:@selector(untraceAll:)];
    untrace.bezelStyle = NSBezelStyleRounded;
    untrace.controlSize = NSControlSizeSmall;
    untrace.font = [NSFont systemFontOfSize:11];

    _status = [NSTextField labelWithString:@""];
    _status.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _status.textColor = NSColor.secondaryLabelColor;
    _status.alignment = NSTextAlignmentRight;
    [_status setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *bar = [NSStackView stackViewWithViews:@[title, _pauseButton, clear, untrace, _status]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.spacing = 10;
    bar.edgeInsets = NSEdgeInsetsMake(6, 12, 6, 12);
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scroll.hasVerticalScroller = YES;
    _scroll.hasHorizontalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.borderType = NSNoBorder;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;

    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 900, 200)];
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.richText = NO;
    _textView.usesFindBar = YES;
    _textView.incrementalSearchingEnabled = YES;
    _textView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _textView.textContainerInset = NSMakeSize(6, 6);
    _textView.minSize = NSMakeSize(0, 0);
    _textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _textView.verticallyResizable = YES;
    _textView.horizontallyResizable = YES;
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _textView.textContainer.widthTracksTextView = NO;
    _scroll.documentView = _textView;
    _followTail = YES;
    _scroll.contentView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clipBoundsChanged:) name:NSViewBoundsDidChangeNotification object:_scroll.contentView];

    _eventAttributes = @{NSFontAttributeName: _textView.font, NSForegroundColorAttributeName: NSColor.labelColor};
    _noteAttributes = @{NSFontAttributeName: _textView.font, NSForegroundColorAttributeName: NSColor.systemBlueColor};

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:bar];
    [root addSubview:separator];
    [root addSubview:_scroll];
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [separator.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scroll.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf flush];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSEventTrackingRunLoopMode];
    [self appendNote:@"Swizzlescope ready. Tick a method's Trace box to start logging its calls; a line appears when the call returns."];
    [self updateStatus];
}

- (void)dealloc {
    [_timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

/// Follow the newest line unless the user has scrolled up; resume following when they scroll back down.
- (void)clipBoundsChanged:(NSNotification *)notification {
    if (_scrollingProgrammatically) return;
    NSClipView *clip = _scroll.contentView;
    CGFloat distanceFromBottom = NSHeight(_textView.frame) - NSMaxY(clip.bounds);
    _followTail = distanceFromBottom < 30;
}

- (void)scrollToTail {
    _scrollingProgrammatically = YES;
    [_textView.layoutManager ensureLayoutForTextContainer:_textView.textContainer];
    [_textView scrollToEndOfDocument:nil];
    _scrollingProgrammatically = NO;
}

- (void)flush {
    if (_pauseButton.state == NSControlStateValueOn) {
        [self updateStatus];
        return;
    }
    NSArray<SZTraceEvent *> *events = [SZTracer.sharedTracer drainEvents];
    if (events.count == 0) {
        [self updateStatus];
        return;
    }
    NSMutableString *text = [NSMutableString string];
    for (SZTraceEvent *event in events) {
        [text appendString:event.formattedLine];
        [text appendString:@"\n"];
    }
    _shownEvents += events.count;
    [self appendText:text attributes:_eventAttributes lines:events.count];
    [self updateStatus];
}

- (void)appendNote:(NSString *)note {
    [self appendText:[note stringByAppendingString:@"\n"] attributes:_noteAttributes lines:1];
}

- (void)appendText:(NSString *)text attributes:(NSDictionary *)attributes lines:(NSUInteger)lines {
    if (!self.viewLoaded) [self loadView];
    NSTextStorage *storage = _textView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    _lineCount += lines;
    if (_lineCount > kOSMaxLogLines) {
        NSString *all = storage.string;
        NSUInteger cut = 0, seen = 0;
        while (seen < kOSTrimLogLines && cut < all.length) {
            NSRange nl = [all rangeOfString:@"\n" options:0 range:NSMakeRange(cut, all.length - cut)];
            if (nl.location == NSNotFound) break;
            cut = NSMaxRange(nl);
            seen++;
        }
        [storage deleteCharactersInRange:NSMakeRange(0, cut)];
        _lineCount -= seen;
    }
    [storage endEditing];
    if (_followTail) [self scrollToTail];
}

- (void)updateStatus {
    SZTracer *tracer = SZTracer.sharedTracer;
    _status.stringValue = [NSString stringWithFormat:@"%lu traced · %llu events · %llu dropped",
                           (unsigned long)tracer.tracedMethodCount, tracer.totalEventCount, tracer.droppedEventCount];
}

- (void)clearLog:(id)sender {
    [_textView.textStorage deleteCharactersInRange:NSMakeRange(0, _textView.textStorage.length)];
    _lineCount = 0;
}

@end
