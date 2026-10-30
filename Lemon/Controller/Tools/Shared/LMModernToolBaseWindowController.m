//
//  LMModernToolBaseWindowController.m
//  Lemon
//

#import "LMModernToolBaseWindowController.h"
#import <Masonry/Masonry.h>
#import <QMCoreFunction/LanguageHelper.h>
#import <QMCoreFunction/NSColor+Extension.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/NSFontHelper.h>
#import <QMUICommon/MMScroller.h>
#import <QMUICommon/LMBigLoadingView.h>

NSString *LMToolLocalized(NSString *zhText, NSString *enText) {
    NSString *userLang = [LanguageHelper getCurrentUserLanguage];
    if (userLang != nil) {
        if ([userLang hasPrefix:@"zh"]) {
            return zhText ?: @"";
        }
        return enText ?: (zhText ?: @"");
    }
    if ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeChinese) {
        return zhText ?: @"";
    }
    return enText ?: (zhText ?: @"");
}

NSString *LMFormatByteCount(uint64_t bytes) {
    if (bytes == 0) {
        return @"0 B";
    }
    double val = (double)bytes;
    if (val < 1024.0) {
        return [NSString stringWithFormat:@"%llu B", (unsigned long long)bytes];
    } else if (val < 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f KB", val / 1024.0];
    } else if (val < 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MB", val / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.2f GB", val / (1024.0 * 1024.0 * 1024.0)];
    }
}

#pragma mark - LMToolPillBadgeView

@interface LMToolPillBadgeView ()
@property (nonatomic, strong, readwrite) NSTextField *textLabel;
@property (nonatomic, assign) LMToolPillTone currentTone;
@end

@implementation LMToolPillBadgeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10.0;
        self.layer.masksToBounds = YES;

        NSTextField *label = [[NSTextField alloc] init];
        label.bezeled = NO;
        label.bordered = NO;
        label.drawsBackground = NO;
        label.editable = NO;
        label.selectable = NO;
        label.alignment = NSTextAlignmentCenter;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.font = [NSFontHelper getRegularSystemFont:11.5];
        [self addSubview:label];
        _textLabel = label;

        [label mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerY.equalTo(self);
            make.left.equalTo(self).offset(8);
            make.right.equalTo(self).offset(-8);
        }];
    }
    return self;
}

- (void)configureWithText:(NSString *)text tone:(LMToolPillTone)tone {
    self.currentTone = tone;
    self.textLabel.stringValue = text ?: @"";
    [self _applyToneColors];
}

- (void)_applyToneColors {
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10.0;
    NSColor *fg = nil;
    NSColor *bg = nil;
    switch (self.currentTone) {
        case LMToolPillToneMint:
            fg = [NSColor colorWithHex:0x04D999];
            bg = [NSColor colorWithHex:0x04D999 alpha:0.14];
            break;
        case LMToolPillToneBlue:
            fg = [NSColor colorWithHex:0x1A83F7];
            bg = [NSColor colorWithHex:0x1A83F7 alpha:0.13];
            break;
        case LMToolPillToneAmber:
            fg = [NSColor colorWithHex:0xFF9A00];
            bg = [NSColor colorWithHex:0xFF9A00 alpha:0.14];
            break;
        case LMToolPillToneNeutral:
        default:
            fg = [NSColor colorWithHex:0x94979B];
            bg = [NSColor colorWithHex:0x94979B alpha:0.14];
            break;
    }
    self.textLabel.textColor = fg;
    self.layer.backgroundColor = bg.CGColor;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self _applyToneColors];
}

@end

#pragma mark - LMToolHoverRowView

@interface LMToolHoverRowView () {
    NSTrackingArea *_trackingArea;
    BOOL _hovered;
}
@end

@implementation LMToolHoverRowView

- (BOOL)isRowHovered {
    return _hovered;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _hovered = NO;
    [self _notifySubCellsHover:NO];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:(NSTrackingInVisibleRect | NSTrackingActiveInKeyWindow | NSTrackingMouseEnteredAndExited)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    _hovered = YES;
    [self _notifySubCellsHover:YES];
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    [self _notifySubCellsHover:NO];
    [self setNeedsDisplay:YES];
}

- (void)_notifySubCellsHover:(BOOL)hovered {
    NSArray<NSView *> *subs = self.subviews;
    NSUInteger i;
    for (i = 0; i < subs.count; i++) {
        NSView *sub = subs[i];
        if ([sub conformsToProtocol:@protocol(LMToolHoverCellProtocol)] &&
            [sub respondsToSelector:@selector(updateHoverState:)]) {
            [(id<LMToolHoverCellProtocol>)sub updateHoverState:hovered];
        }
    }
}

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
    NSColor *bg = _hovered ? [LMAppThemeHelper getTableViewRowSelectedColor] : [LMAppThemeHelper getMainBgColor];
    [bg setFill];
    NSRectFill(self.bounds);
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    [[LMAppThemeHelper getTableViewRowSelectedColor] setFill];
    NSRectFill(self.bounds);
}

@end

#pragma mark - LMToolClickableTableView

@implementation LMToolClickableTableView

- (void)mouseDown:(NSEvent *)event {
    NSPoint localPt = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:localPt];
    if (row >= 0 && row < self.numberOfRows) {
        NSView *hit = [self hitTest:[self.superview convertPoint:localPt fromView:self]];
        BOOL hitInteractiveControl = NO;
        NSView *cursor = hit;
        while (cursor != nil && cursor != self) {
            if ([cursor isKindOfClass:[NSButton class]] || [cursor isKindOfClass:[COSwitch class]]) {
                hitInteractiveControl = YES;
                break;
            }
            cursor = cursor.superview;
        }
        if (!hitInteractiveControl) {
            if (event.clickCount >= 2 && self.onRowDoubleClicked) {
                self.onRowDoubleClicked(row);
                return;
            } else if (event.clickCount == 1 && self.onRowBodyClicked) {
                self.onRowBodyClicked(row);
                return;
            }
        }
    }
    [super mouseDown:event];
}

@end

#pragma mark - LMToolFilterBarView

@interface LMToolFilterBarView ()
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSMutableArray<NSButton *> *tabButtons;
@property (nonatomic, strong) NSView *indicatorBar;
@property (nonatomic, strong) NSView *bottomLine;
@end

@implementation LMToolFilterBarView

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _titles = [titles copy];
        _tabButtons = [NSMutableArray arrayWithCapacity:titles.count];
        _selectedIndex = 0;
        self.wantsLayer = YES;
        [self _setupTabs];
    }
    return self;
}

- (void)_setupTabs {
    NSView *prevBtn = nil;
    NSUInteger i;
    for (i = 0; i < self.titles.count; i++) {
        NSButton *btn = [[NSButton alloc] init];
        btn.bordered = NO;
        [btn setButtonType:NSButtonTypeMomentaryChange];
        btn.focusRingType = NSFocusRingTypeNone;
        btn.tag = (NSInteger)i;
        btn.target = self;
        btn.action = @selector(_onTabClicked:);
        [self addSubview:btn];
        [self.tabButtons addObject:btn];

        [btn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerY.equalTo(self);
            if (prevBtn == nil) {
                make.left.equalTo(self).offset(28);
            } else {
                make.left.equalTo(prevBtn.mas_right).offset(26);
            }
            make.height.mas_equalTo(28);
        }];
        prevBtn = btn;
    }

    NSView *line = [[NSView alloc] init];
    line.wantsLayer = YES;
    [LMAppThemeHelper setDivideLineColorFor:line];
    [self addSubview:line];
    self.bottomLine = line;
    [line mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self);
        make.height.mas_equalTo(1);
    }];

    NSView *indicator = [[NSView alloc] init];
    indicator.wantsLayer = YES;
    indicator.layer.backgroundColor = [NSColor colorWithHex:0x00D899].CGColor;
    indicator.layer.cornerRadius = 1.0;
    [self addSubview:indicator];
    self.indicatorBar = indicator;

    [self _refreshTabStyles];
}

- (void)_onTabClicked:(NSButton *)sender {
    NSInteger idx = sender.tag;
    if (idx == self.selectedIndex) {
        return;
    }
    self.selectedIndex = idx;
    if (self.onSelectTab) {
        self.onSelectTab(idx);
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (selectedIndex < 0 || (NSUInteger)selectedIndex >= self.tabButtons.count) {
        return;
    }
    _selectedIndex = selectedIndex;
    [self _refreshTabStyles];
}

- (void)_refreshTabStyles {
    NSUInteger i;
    for (i = 0; i < self.tabButtons.count; i++) {
        NSButton *btn = self.tabButtons[i];
        BOOL active = ((NSInteger)i == _selectedIndex);
        NSFont *font = active ? [NSFontHelper getMediumSystemFont:13] : [NSFontHelper getLightSystemFont:13];
        NSColor *color = active ? [LMAppThemeHelper getTitleColor] : [NSColor colorWithHex:0x94979B];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: color
        };
        btn.attributedTitle = [[NSAttributedString alloc] initWithString:self.titles[i] attributes:attrs];
    }

    if ((NSUInteger)_selectedIndex < self.tabButtons.count) {
        NSButton *activeBtn = self.tabButtons[(NSUInteger)_selectedIndex];
        [self.indicatorBar mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.bottom.equalTo(self);
            make.centerX.equalTo(activeBtn);
            make.width.mas_equalTo(18);
            make.height.mas_equalTo(2);
        }];
    }
}

- (void)layout {
    [super layout];
    [LMAppThemeHelper setDivideLineColorFor:self.bottomLine];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [LMAppThemeHelper setDivideLineColorFor:self.bottomLine];
    [self _refreshTabStyles];
}

@end

#pragma mark - LMToolStatusOverlayView

@interface LMToolStatusOverlayView ()
@property (nonatomic, strong, nullable) LMBigLoadingView *loadingView;
@property (nonatomic, strong) NSImageView *emptyIconView;
@property (nonatomic, strong) NSTextField *messageLabel;
@end

@implementation LMToolStatusOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.hidden = YES;

        NSImageView *emptyIcon = [[NSImageView alloc] init];
        emptyIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
        NSImage *cleanImg = [NSImage imageNamed:@"lemon_normal_icon"];
        if (!cleanImg) {
            cleanImg = [NSImage imageNamed:NSImageNameStatusAvailable];
        }
        emptyIcon.image = cleanImg;
        emptyIcon.hidden = YES;
        [self addSubview:emptyIcon];
        _emptyIconView = emptyIcon;

        [emptyIcon mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerX.equalTo(self);
            make.centerY.equalTo(self).offset(-20);
            make.width.height.mas_equalTo(64);
        }];

        NSTextField *msg = [[NSTextField alloc] init];
        msg.bezeled = NO;
        msg.bordered = NO;
        msg.drawsBackground = NO;
        msg.editable = NO;
        msg.selectable = NO;
        msg.alignment = NSTextAlignmentCenter;
        msg.font = [NSFontHelper getLightSystemFont:12.5];
        msg.textColor = [NSColor colorWithHex:0x94979B];
        [self addSubview:msg];
        _messageLabel = msg;

        [msg mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerX.equalTo(self);
            make.centerY.equalTo(self).offset(56);
            make.left.greaterThanOrEqualTo(self).offset(40);
            make.right.lessThanOrEqualTo(self).offset(-40);
        }];
    }
    return self;
}

- (void)layout {
    [super layout];
    self.layer.backgroundColor = [LMAppThemeHelper getMainBgColor].CGColor;
}

- (void)showLoadingWithTitle:(NSString *)title {
    self.hidden = NO;
    self.emptyIconView.hidden = YES;
    self.messageLabel.stringValue = title ?: @"";

    if (!self.loadingView) {
        LMBigLoadingView *lv = [[LMBigLoadingView alloc] initWithFrame:NSMakeRect(0, 0, 128, 128)];
        [self addSubview:lv];
        self.loadingView = lv;
        [lv mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerX.equalTo(self);
            make.centerY.equalTo(self).offset(-22);
            make.width.height.mas_equalTo(128);
        }];
    }
    [self.messageLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self);
        make.top.equalTo(self.loadingView.mas_bottom).offset(6);
    }];
}

- (void)showEmptyWithTitle:(NSString *)title {
    if (self.loadingView) {
        [self.loadingView invalidate];
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
    }
    self.hidden = NO;
    self.emptyIconView.hidden = NO;
    self.messageLabel.stringValue = title ?: @"";
    [self.messageLabel mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self);
        make.top.equalTo(self.emptyIconView.mas_bottom).offset(12);
    }];
}

- (void)dismissOverlay {
    if (self.loadingView) {
        [self.loadingView invalidate];
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
    }
    self.emptyIconView.hidden = YES;
    self.hidden = YES;
}

- (void)dealloc {
    if (_loadingView) {
        [_loadingView invalidate];
    }
}

@end

#pragma mark - LMModernToolRootView

@interface LMModernToolRootView : NSView
@end

@implementation LMModernToolRootView
- (void)layout {
    [super layout];
    self.wantsLayer = YES;
    self.layer.backgroundColor = [LMAppThemeHelper getMainBgColor].CGColor;
}
@end

#pragma mark - LMModernToolBaseWindowController

@interface LMModernToolBaseWindowController ()
@property (nonatomic, copy) NSString *initialTitle;
@property (nonatomic, assign) NSSize initialWindowSize;

@property (nonatomic, strong, readwrite) NSView *rootContainerView;
@property (nonatomic, strong, readwrite) NSView *headerBarView;
@property (nonatomic, strong, readwrite) NSTextField *headerTitleLabel;
@property (nonatomic, strong, readwrite) NSView *headerRightContainer;
@property (nonatomic, strong, readwrite) NSView *headerDividerView;
@property (nonatomic, strong, readwrite) NSView *bodyContentView;
@end

@implementation LMModernToolBaseWindowController

- (instancetype)initWithToolTitle:(NSString *)title
                       windowSize:(NSSize)windowSize {
    NSRect frame = NSMakeRect(0, 0, windowSize.width, windowSize.height);
    NSWindowStyleMask mask = (NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskFullSizeContentView);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                                styleMask:mask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.titlebarAppearsTransparent = YES;
    win.titleVisibility = NSWindowTitleHidden;
    win.movableByWindowBackground = YES;
    win.releasedWhenClosed = NO;

    self = [super initWithWindow:win];
    if (self) {
        _initialTitle = [title copy];
        _initialWindowSize = windowSize;
        win.delegate = self;
        [self _buildBaseChrome];
        [self setupToolContentView];
    }
    return self;
}

- (instancetype)initWithToolTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                         iconName:(NSString *)iconName
                       windowSize:(NSSize)windowSize {
    return [self initWithToolTitle:title windowSize:windowSize];
}

- (void)_buildBaseChrome {
    LMModernToolRootView *root = [[LMModernToolRootView alloc] initWithFrame:NSMakeRect(0, 0, self.initialWindowSize.width, self.initialWindowSize.height)];
    root.wantsLayer = YES;
    self.window.contentView = root;
    self.rootContainerView = root;

    // 38pt 极简原生居中标题栏（1:1 对齐开机启动项管理 LMLoginItemManageViewController）
    NSView *header = [[NSView alloc] init];
    header.wantsLayer = YES;
    [root addSubview:header];
    self.headerBarView = header;

    [header mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(root);
        make.height.mas_equalTo(38);
    }];

    NSTextField *titleLabel = [LMModernToolBaseWindowController labelWithText:self.initialTitle
                                                                         font:[NSFontHelper getRegularSystemFont:15]
                                                                        color:[LMAppThemeHelper getTitleColor]];
    titleLabel.alignment = NSTextAlignmentCenter;
    [header addSubview:titleLabel];
    self.headerTitleLabel = titleLabel;

    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(header);
        make.centerY.equalTo(header);
    }];

    NSView *rightBox = [[NSView alloc] init];
    [header addSubview:rightBox];
    self.headerRightContainer = rightBox;
    [rightBox mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(header).offset(-20);
        make.centerY.equalTo(header);
        make.height.mas_equalTo(24);
        make.left.greaterThanOrEqualTo(titleLabel.mas_right).offset(12);
    }];

    NSView *divider = [[NSView alloc] init];
    divider.wantsLayer = YES;
    [LMAppThemeHelper setDivideLineColorFor:divider];
    [header addSubview:divider];
    self.headerDividerView = divider;

    [divider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(header);
        make.height.mas_equalTo(1);
    }];

    NSView *body = [[NSView alloc] init];
    body.wantsLayer = YES;
    [root addSubview:body];
    self.bodyContentView = body;

    [body mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(header.mas_bottom);
        make.left.right.bottom.equalTo(root);
    }];
}

- (void)setupToolContentView {
    // Subclass hook
}

- (void)toolWindowWillClose {
    // Subclass hook
}

- (void)windowWillClose:(NSNotification *)notification {
    [self toolWindowWillClose];
    if (self.delegate) {
        [self.delegate windowWillDismiss:NSStringFromClass(self.class)];
    }
}

#pragma mark - Factories

+ (NSTextField *)labelWithText:(NSString *)text
                          font:(NSFont *)font
                         color:(NSColor *)color {
    NSTextField *tf = [[NSTextField alloc] init];
    tf.stringValue = text ?: @"";
    tf.font = font;
    tf.textColor = color;
    tf.bezeled = NO;
    tf.bordered = NO;
    tf.drawsBackground = NO;
    tf.editable = NO;
    tf.selectable = NO;
    tf.lineBreakMode = NSLineBreakByTruncatingTail;
    return tf;
}

+ (LMCheckboxButton *)checkboxWithMixed:(BOOL)allowsMixed
                                 target:(id)target
                                 action:(SEL)action {
    LMCheckboxButton *cb = [[LMCheckboxButton alloc] initWithFrame:NSMakeRect(0, 0, 14, 14)];
    cb.imageScaling = NSImageScaleProportionallyDown;
    cb.title = @"";
    [cb setButtonType:NSButtonTypeSwitch];
    cb.bordered = NO;
    cb.focusRingType = NSFocusRingTypeNone;
    cb.allowsMixedState = allowsMixed;
    cb.target = target;
    cb.action = action;
    return cb;
}

+ (LMRectangleButton *)primaryButtonWithTitle:(NSString *)title
                                       target:(id)target
                                       action:(SEL)action {
    LMRectangleButton *btn = [[LMRectangleButton alloc] initWithFrame:NSMakeRect(0, 0, 108, 34)];
    btn.imageScaling = NSImageScaleProportionallyUpOrDown;
    [btn setBezelStyle:NSBezelStyleRegularSquare];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    btn.imagePosition = NSImageOverlaps;
    btn.bordered = NO;
    btn.focusRingType = NSFocusRingTypeNone;
    btn.radius = 4.0f;
    btn.font = [NSFontHelper getRegularSystemFont:13.5];
    btn.alignment = NSTextAlignmentCenter;
    btn.title = title ?: @"";
    btn.target = target;
    btn.action = action;
    return btn;
}

+ (LMBorderButton *)ghostButtonWithTitle:(NSString *)title
                                fontSize:(int)fontSize
                                  target:(id)target
                                  action:(SEL)action {
    LMBorderButton *btn = [[LMBorderButton alloc] init];
    btn.title = title ?: @"";
    btn.fontSize = fontSize;
    btn.radius = 3;
    btn.isFontLight = NO;
    btn.target = target;
    btn.action = action;
    return btn;
}

+ (NSButton *)finderHoverButtonWithTarget:(id)target action:(SEL)action {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 18, 18)];
    btn.bordered = NO;
    [btn setButtonType:NSButtonTypeMomentaryChange];
    btn.focusRingType = NSFocusRingTypeNone;
    btn.imageScaling = NSImageScaleProportionallyDown;
    btn.imagePosition = NSImageOnly;
    NSImage *img = [NSImage imageNamed:@"btn_show_in_finder"];
    if (!img) {
        img = [NSImage imageNamed:NSImageNameRevealFreestandingTemplate];
    }
    btn.image = img;
    btn.toolTip = LMToolLocalized(@"在访达中显示", @"Reveal in Finder");
    btn.target = target;
    btn.action = action;
    btn.hidden = YES;
    return btn;
}

+ (NSSearchField *)searchFieldWithPlaceholder:(NSString *)placeholder
                                       target:(id)target
                                       action:(SEL)action {
    NSSearchField *sf = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 136, 22)];
    sf.placeholderString = placeholder ?: LMToolLocalized(@"搜索", @"Search");
    sf.font = [NSFontHelper getLightSystemFont:12];
    sf.focusRingType = NSFocusRingTypeNone;
    if ([sf.cell isKindOfClass:[NSSearchFieldCell class]]) {
        NSSearchFieldCell *cell = (NSSearchFieldCell *)sf.cell;
        cell.sendsSearchStringImmediately = YES;
        cell.sendsWholeSearchString = NO;
    }
    sf.target = target;
    sf.action = action;
    return sf;
}

+ (NSButton *)sortableColumnButtonWithTitle:(NSString *)title
                                  alignment:(NSTextAlignment)alignment
                                     target:(id)target
                                     action:(SEL)action {
    NSButton *btn = [[NSButton alloc] init];
    btn.bordered = NO;
    [btn setButtonType:NSButtonTypeMomentaryChange];
    btn.focusRingType = NSFocusRingTypeNone;
    btn.target = target;
    btn.action = action;
    [self styleSortableColumnButton:btn title:title active:NO ascending:NO alignment:alignment];
    return btn;
}

+ (void)styleSortableColumnButton:(NSButton *)button
                            title:(NSString *)title
                           active:(BOOL)active
                        ascending:(BOOL)ascending
                        alignment:(NSTextAlignment)alignment {
    NSString *arrow = active ? (ascending ? @" ⌃" : @" ⌄") : @"";
    NSString *full = [NSString stringWithFormat:@"%@%@", title ?: @"", arrow];
    NSColor *fg = active ? [LMAppThemeHelper getTitleColor] : [NSColor colorWithHex:0x94979B];
    NSFont *font = [NSFontHelper getRegularSystemFont:12];
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.alignment = alignment;
    button.alignment = alignment;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:full attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: fg,
        NSParagraphStyleAttributeName: pStyle
    }];
}

+ (NSScrollView *)cleanTableScrollViewWithTable:(LMToolClickableTableView * _Nullable * _Nonnull)outTable
                                       delegate:(id<NSTableViewDelegate, NSTableViewDataSource>)delegate
                                      rowHeight:(CGFloat)rowHeight {
    NSScrollView *sv = [[NSScrollView alloc] init];
    sv.hasVerticalScroller = YES;
    sv.hasHorizontalScroller = NO;
    sv.autohidesScrollers = YES;
    sv.drawsBackground = NO;
    sv.borderType = NSNoBorder;
    MMScroller *scroller = [[MMScroller alloc] init];
    [sv setVerticalScroller:scroller];

    LMToolClickableTableView *tv = [[LMToolClickableTableView alloc] initWithFrame:NSMakeRect(0, 0, 780, 320)];
    tv.headerView = nil;
    tv.rowHeight = rowHeight;
    tv.intercellSpacing = NSMakeSize(0, 0);
    tv.backgroundColor = [NSColor clearColor];
    tv.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    if (@available(macOS 11.0, *)) {
        tv.style = NSTableViewStyleFullWidth;
    }
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"MainColumn"];
    col.width = 780;
    col.resizingMask = NSTableColumnAutoresizingMask;
    [tv addTableColumn:col];
    tv.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    tv.delegate = delegate;
    tv.dataSource = delegate;

    sv.documentView = tv;
    if (outTable) {
        *outTable = tv;
    }
    return sv;
}

+ (NSAttributedString *)summaryAttributedWithPrefix:(NSString *)prefix
                                          highlight:(NSString *)highlight
                                             suffix:(NSString *)suffix
                                     highlightColor:(NSColor *)highlightColor {
    NSMutableAttributedString *res = [[NSMutableAttributedString alloc] init];
    NSDictionary *grayAttrs = @{
        NSFontAttributeName: [NSFontHelper getLightSystemFont:12.5],
        NSForegroundColorAttributeName: [NSColor colorWithHex:0x94979B]
    };
    NSDictionary *hiAttrs = @{
        NSFontAttributeName: [NSFontHelper getMediumSystemFont:13.5],
        NSForegroundColorAttributeName: highlightColor ?: [NSColor colorWithHex:0x04D999]
    };
    if (prefix.length > 0) {
        [res appendAttributedString:[[NSAttributedString alloc] initWithString:prefix attributes:grayAttrs]];
    }
    if (highlight.length > 0) {
        [res appendAttributedString:[[NSAttributedString alloc] initWithString:highlight attributes:hiAttrs]];
    }
    if (suffix.length > 0) {
        [res appendAttributedString:[[NSAttributedString alloc] initWithString:suffix attributes:grayAttrs]];
    }
    return res;
}

@end
