//
//  LMSystemOptimizeWindowController.m
//  Lemon
//

#import "LMSystemOptimizeWindowController.h"
#import "LMSystemOptimizeService.h"
#import "LMSystemOptimizeTask.h"
#import <Masonry/Masonry.h>
#import <QMCoreFunction/NSColor+Extension.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/NSFontHelper.h>

#pragma mark - Hoverable Switch Row (Image 1 Style)

@interface LMSysSwitchRowView : NSView {
    NSTrackingArea *_trackingArea;
    BOOL _hovered;
}
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *descLabel;
@property (nonatomic, strong) LMToolPillBadgeView *statusPill;
@property (nonatomic, strong) COSwitch *toggleSwitch;
@end

@implementation LMSysSwitchRowView

- (instancetype)initWithTitle:(NSString *)title desc:(NSString *)desc {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _titleLabel = [LMModernToolBaseWindowController labelWithText:title
                                                                 font:[NSFontHelper getRegularSystemFont:13.5]
                                                                color:[LMAppThemeHelper getTitleColor]];
        [self addSubview:_titleLabel];

        _descLabel = [LMModernToolBaseWindowController labelWithText:desc
                                                                font:[NSFontHelper getLightSystemFont:12]
                                                               color:[NSColor colorWithHex:0x989A9E]];
        [self addSubview:_descLabel];

        _statusPill = [[LMToolPillBadgeView alloc] init];
        [self addSubview:_statusPill];

        _toggleSwitch = [[COSwitch alloc] initWithFrame:NSMakeRect(0, 0, 32, 17)];
        [self addSubview:_toggleSwitch];

        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(28);
            make.centerY.equalTo(self);
        }];

        [_descLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_titleLabel.mas_right).offset(12);
            make.centerY.equalTo(self);
            make.right.lessThanOrEqualTo(_statusPill.mas_left).offset(-16);
        }];

        [_statusPill mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(516);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(68);
            make.height.mas_equalTo(20);
        }];

        [_toggleSwitch mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self).offset(-34);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(32);
            make.height.mas_equalTo(17);
        }];
    }
    return self;
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
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *bg = _hovered ? [LMAppThemeHelper getTableViewRowSelectedColor] : [LMAppThemeHelper getMainBgColor];
    [bg setFill];
    NSRectFill(self.bounds);
}

@end

#pragma mark - Single-Line Maintenance Task Row (Image 2/5 Style)

@interface LMSysTaskRowView : NSView {
    NSTrackingArea *_trackingArea;
    BOOL _hovered;
}
@property (nonatomic, strong) LMSystemOptimizeTask *task;
@property (nonatomic, strong) LMCheckboxButton *checkBox;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *descLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, copy) void (^onToggleSelection)(void);
- (void)refreshFromTask;
@end

@implementation LMSysTaskRowView

- (instancetype)initWithTask:(LMSystemOptimizeTask *)task {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _task = task;

        _checkBox = [LMModernToolBaseWindowController checkboxWithMixed:NO
                                                                 target:self
                                                                 action:@selector(_onCheckClicked:)];
        [self addSubview:_checkBox];

        _titleLabel = [LMModernToolBaseWindowController labelWithText:task.title
                                                                 font:[NSFontHelper getRegularSystemFont:13.5]
                                                                color:[LMAppThemeHelper getTitleColor]];
        [self addSubview:_titleLabel];

        _descLabel = [LMModernToolBaseWindowController labelWithText:task.subtitle
                                                                font:[NSFontHelper getLightSystemFont:12]
                                                               color:[NSColor colorWithHex:0x989A9E]];
        [self addSubview:_descLabel];

        _statusLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                  font:[NSFontHelper getRegularSystemFont:12]
                                                                 color:[NSColor colorWithHex:0x94979B]];
        _statusLabel.alignment = NSTextAlignmentRight;
        [self addSubview:_statusLabel];

        [_checkBox mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(28);
            make.centerY.equalTo(self);
            make.width.height.mas_equalTo(15);
        }];

        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_checkBox.mas_right).offset(12);
            make.centerY.equalTo(self);
        }];

        [_descLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_titleLabel.mas_right).offset(12);
            make.centerY.equalTo(self);
            make.right.lessThanOrEqualTo(_statusLabel.mas_left).offset(-16);
        }];

        [_statusLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self).offset(-28);
            make.centerY.equalTo(self);
            make.width.mas_greaterThanOrEqualTo(72);
        }];

        [self refreshFromTask];
    }
    return self;
}

- (void)refreshFromTask {
    self.checkBox.state = self.task.isSelected ? NSControlStateValueOn : NSControlStateValueOff;
    self.titleLabel.textColor = [LMAppThemeHelper getTitleColor];

    switch (self.task.state) {
        case LMSystemOptimizeTaskStateIdle:
            self.statusLabel.stringValue = LMToolLocalized(@"待执行", @"Ready");
            self.statusLabel.textColor = [NSColor colorWithHex:0x94979B];
            break;
        case LMSystemOptimizeTaskStateRunning:
            self.statusLabel.stringValue = LMToolLocalized(@"执行中...", @"Running...");
            self.statusLabel.textColor = [NSColor colorWithHex:0x1A83F7];
            break;
        case LMSystemOptimizeTaskStateSuccess:
            self.statusLabel.stringValue = self.task.resultText.length > 0 ? self.task.resultText : LMToolLocalized(@"已完成", @"Done");
            self.statusLabel.textColor = [NSColor colorWithHex:0x04D999];
            break;
        case LMSystemOptimizeTaskStateSkipped:
            self.statusLabel.stringValue = self.task.resultText.length > 0 ? self.task.resultText : LMToolLocalized(@"已跳过", @"Skipped");
            self.statusLabel.textColor = [NSColor colorWithHex:0xFF9A00];
            break;
        case LMSystemOptimizeTaskStateFailed:
            self.statusLabel.stringValue = self.task.resultText.length > 0 ? self.task.resultText : LMToolLocalized(@"失败", @"Failed");
            self.statusLabel.textColor = [NSColor colorWithHex:0xF25B3D];
            break;
    }
}

- (void)_onCheckClicked:(LMCheckboxButton *)sender {
    self.task.isSelected = (sender.state == NSControlStateValueOn);
    if (self.onToggleSelection) {
        self.onToggleSelection();
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    NSView *hit = [self hitTest:[self.superview convertPoint:pt fromView:self]];
    if ([hit isKindOfClass:[NSButton class]]) {
        [super mouseDown:event];
        return;
    }
    if (self.checkBox.isEnabled) {
        self.task.isSelected = !self.task.isSelected;
        self.checkBox.state = self.task.isSelected ? NSControlStateValueOn : NSControlStateValueOff;
        if (self.onToggleSelection) {
            self.onToggleSelection();
        }
    }
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
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *bg = _hovered ? [LMAppThemeHelper getTableViewRowSelectedColor] : [LMAppThemeHelper getMainBgColor];
    [bg setFill];
    NSRectFill(self.bounds);
}

@end

#pragma mark - LMSystemOptimizeWindowController

@interface LMSystemOptimizeWindowController ()

@property (nonatomic, strong) NSArray<LMSystemOptimizeTask *> *tasks;
@property (nonatomic, strong) NSMutableArray<LMSysTaskRowView *> *taskRows;
@property (nonatomic, assign) BOOL isExecuting;
@property (nonatomic, assign) BOOL isTogglingTouchID;

@property (nonatomic, strong) LMSysSwitchRowView *touchIDRow;
@property (nonatomic, strong) LMSysSwitchRowView *dsStoreRow;

@property (nonatomic, strong) LMCheckboxButton *selectAllCheck;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) LMRectangleButton *runButton;

@end

@implementation LMSystemOptimizeWindowController

- (instancetype)init {
    self = [super initWithToolTitle:LMToolLocalized(@"系统维护", @"System Maintenance")
                         windowSize:NSMakeSize(780, 482)];
    return self;
}

- (void)setupToolContentView {
    self.tasks = [LMSystemOptimizeService defaultMaintenanceTasks];
    self.taskRows = [NSMutableArray arrayWithCapacity:self.tasks.count];
    NSView *body = self.bodyContentView;

    // 1. 顶部列头：系统偏好 (34pt)
    NSView *secHeader1 = [self _createSectionHeaderLeft:LMToolLocalized(@"系统偏好", @"System Preferences")
                                                 middle:LMToolLocalized(@"当前状态", @"Status")
                                                  right:LMToolLocalized(@"开关", @"Toggle")
                                              topBorder:NO];
    [body addSubview:secHeader1];
    [secHeader1 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(body);
        make.height.mas_equalTo(34);
    }];

    // 2. 两行偏好开关 (2 * 52pt = 104pt)
    LMSysSwitchRowView *tidRow = [[LMSysSwitchRowView alloc]
        initWithTitle:LMToolLocalized(@"终端 Touch ID 免密", @"Sudo Touch ID")
                 desc:LMToolLocalized(@"sudo 命令支持指纹授权", @"Authorize sudo via Touch ID")];
    [body addSubview:tidRow];
    self.touchIDRow = tidRow;
    [tidRow mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(secHeader1.mas_bottom);
        make.left.right.equalTo(body);
        make.height.mas_equalTo(52);
    }];

    LMSysSwitchRowView *dsRow = [[LMSysSwitchRowView alloc]
        initWithTitle:LMToolLocalized(@"禁写外接盘 .DS_Store", @"Suppress .DS_Store")
                 desc:LMToolLocalized(@"U 盘与共享目录免生成隐藏文件", @"Skip .DS_Store on USB & SMB volumes")];
    [body addSubview:dsRow];
    self.dsStoreRow = dsRow;
    [dsRow mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(tidRow.mas_bottom);
        make.left.right.equalTo(body);
        make.height.mas_equalTo(52);
    }];

    __weak typeof(self) weakSelf = self;
    [tidRow.toggleSwitch setOnValueChanged:^(COSwitch *sw) {
        [weakSelf _onToggleTouchID:sw];
    }];
    [dsRow.toggleSwitch setOnValueChanged:^(COSwitch *sw) {
        [weakSelf _onToggleDSStore:sw];
    }];

    // 3. 第二段列头：一键维护项 (34pt)
    NSView *secHeader2 = [self _createSectionHeaderLeft:LMToolLocalized(@"一键维护项", @"Maintenance Tasks")
                                                 middle:nil
                                                  right:LMToolLocalized(@"状态", @"Status")
                                              topBorder:YES];
    [body addSubview:secHeader2];
    [secHeader2 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(dsRow.mas_bottom);
        make.left.right.equalTo(body);
        make.height.mas_equalTo(34);
    }];

    // 4. 五行单行极简维护任务 (5 * 44pt = 220pt)
    NSView *prevAnchor = secHeader2;
    NSUInteger i;
    for (i = 0; i < self.tasks.count; i++) {
        LMSysTaskRowView *rowView = [[LMSysTaskRowView alloc] initWithTask:self.tasks[i]];
        rowView.onToggleSelection = ^{
            [weakSelf _refreshSummaryBar];
        };
        [body addSubview:rowView];
        [self.taskRows addObject:rowView];

        [rowView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(prevAnchor.mas_bottom);
            make.left.right.equalTo(body);
            make.height.mas_equalTo(44);
        }];
        prevAnchor = rowView;
    }

    // 5. 底部操作栏 (52pt)
    NSView *bottomBar = [[NSView alloc] init];
    [body addSubview:bottomBar];
    [bottomBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(body);
        make.height.mas_equalTo(52);
    }];

    NSView *bLine = [[NSView alloc] init];
    bLine.wantsLayer = YES;
    [LMAppThemeHelper setDivideLineColorFor:bLine];
    [bottomBar addSubview:bLine];
    [bLine mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(bottomBar);
        make.height.mas_equalTo(1);
    }];

    self.selectAllCheck = [LMModernToolBaseWindowController checkboxWithMixed:YES
                                                                       target:self
                                                                       action:@selector(_onToggleSelectAllCheck:)];
    [bottomBar addSubview:self.selectAllCheck];

    NSButton *allLabelBtn = [[NSButton alloc] init];
    allLabelBtn.bordered = NO;
    [allLabelBtn setButtonType:NSButtonTypeMomentaryChange];
    allLabelBtn.focusRingType = NSFocusRingTypeNone;
    allLabelBtn.attributedTitle = [[NSAttributedString alloc] initWithString:LMToolLocalized(@"全选", @"All") attributes:@{
        NSFontAttributeName: [NSFontHelper getRegularSystemFont:12.5],
        NSForegroundColorAttributeName: [LMAppThemeHelper getTitleColor]
    }];
    allLabelBtn.target = self;
    allLabelBtn.action = @selector(_onClickSelectAllText:);
    [bottomBar addSubview:allLabelBtn];

    self.summaryLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                   font:[NSFontHelper getLightSystemFont:12.5]
                                                                  color:[NSColor colorWithHex:0x94979B]];
    self.summaryLabel.alignment = NSTextAlignmentRight;
    [bottomBar addSubview:self.summaryLabel];

    self.runButton = [LMModernToolBaseWindowController primaryButtonWithTitle:LMToolLocalized(@"立即优化", @"Optimize")
                                                                       target:self
                                                                       action:@selector(_onRunMaintenance:)];
    [bottomBar addSubview:self.runButton];

    [self.selectAllCheck mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(bottomBar).offset(28);
        make.centerY.equalTo(bottomBar);
        make.width.height.mas_equalTo(15);
    }];

    [allLabelBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.selectAllCheck.mas_right).offset(6);
        make.centerY.equalTo(bottomBar);
    }];

    [self.runButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(bottomBar).offset(-24);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(104);
        make.height.mas_equalTo(34);
    }];

    [self.summaryLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.runButton.mas_left).offset(-16);
        make.centerY.equalTo(bottomBar);
        make.left.greaterThanOrEqualTo(allLabelBtn.mas_right).offset(16);
    }];

    [self _refreshSwitchStatesAsync];
    [self _refreshSummaryBar];
}

- (NSView *)_createSectionHeaderLeft:(NSString *)leftText
                              middle:(NSString *)middleText
                               right:(NSString *)rightText
                           topBorder:(BOOL)topBorder {
    NSView *bar = [[NSView alloc] init];
    if (topBorder) {
        NSView *tLine = [[NSView alloc] init];
        tLine.wantsLayer = YES;
        [LMAppThemeHelper setDivideLineColorFor:tLine];
        [bar addSubview:tLine];
        [tLine mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.equalTo(bar);
            make.height.mas_equalTo(1);
        }];
    }
    NSView *bLine = [[NSView alloc] init];
    bLine.wantsLayer = YES;
    [LMAppThemeHelper setDivideLineColorFor:bLine];
    [bar addSubview:bLine];
    [bLine mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.left.right.equalTo(bar);
        make.height.mas_equalTo(1);
    }];

    NSTextField *lLbl = [LMModernToolBaseWindowController labelWithText:leftText
                                                                   font:[NSFontHelper getRegularSystemFont:12]
                                                                  color:[NSColor colorWithHex:0x94979B]];
    [bar addSubview:lLbl];
    [lLbl mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(bar).offset(28);
        make.centerY.equalTo(bar);
    }];

    if (middleText.length > 0) {
        NSTextField *mLbl = [LMModernToolBaseWindowController labelWithText:middleText
                                                                       font:[NSFontHelper getRegularSystemFont:12]
                                                                      color:[NSColor colorWithHex:0x94979B]];
        mLbl.alignment = NSTextAlignmentCenter;
        [bar addSubview:mLbl];
        [mLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(bar).offset(516);
            make.centerY.equalTo(bar);
            make.width.mas_equalTo(68);
        }];
    }

    if (rightText.length > 0) {
        NSTextField *rLbl = [LMModernToolBaseWindowController labelWithText:rightText
                                                                       font:[NSFontHelper getRegularSystemFont:12]
                                                                      color:[NSColor colorWithHex:0x94979B]];
        rLbl.alignment = NSTextAlignmentRight;
        [bar addSubview:rLbl];
        [rLbl mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(bar).offset(-32);
            make.centerY.equalTo(bar);
        }];
    }
    return bar;
}

#pragma mark - Switch States

- (void)_refreshSwitchStatesAsync {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL pamAvailable = [LMSystemOptimizeService isTouchIDPamModuleAvailable];
        BOOL tidOn = pamAvailable && [LMSystemOptimizeService isSudoTouchIDEnabled];
        BOOL netOff = [LMSystemOptimizeService isNetworkDSStoreSuppressed];
        BOOL usbOff = [LMSystemOptimizeService isUSBDSStoreSuppressed];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf _applyTouchIDState:tidOn available:pamAvailable];
            [strongSelf _applyDSStoreState:(netOff && usbOff) partial:(netOff != usbOff)];
        });
    });
}

- (void)_applyTouchIDState:(BOOL)enabled available:(BOOL)available {
    self.touchIDRow.toggleSwitch.isEnable = available;
    [self.touchIDRow.toggleSwitch updateSwitchState:enabled];
    if (!available) {
        [self.touchIDRow.statusPill configureWithText:LMToolLocalized(@"不支持", @"N/A") tone:LMToolPillToneNeutral];
    } else if (enabled) {
        [self.touchIDRow.statusPill configureWithText:LMToolLocalized(@"已开启", @"Enabled") tone:LMToolPillToneMint];
    } else {
        [self.touchIDRow.statusPill configureWithText:LMToolLocalized(@"未开启", @"Disabled") tone:LMToolPillToneNeutral];
    }
}

- (void)_applyDSStoreState:(BOOL)bothEnabled partial:(BOOL)partial {
    [self.dsStoreRow.toggleSwitch updateSwitchState:(bothEnabled || partial)];
    if (bothEnabled) {
        [self.dsStoreRow.statusPill configureWithText:LMToolLocalized(@"已开启", @"Enabled") tone:LMToolPillToneMint];
    } else if (partial) {
        [self.dsStoreRow.statusPill configureWithText:LMToolLocalized(@"部分开启", @"Partial") tone:LMToolPillToneBlue];
    } else {
        [self.dsStoreRow.statusPill configureWithText:LMToolLocalized(@"未开启", @"Default") tone:LMToolPillToneNeutral];
    }
}

- (void)_onToggleTouchID:(COSwitch *)sender {
    if (self.isTogglingTouchID) {
        return;
    }
    BOOL targetOn = sender.isOn;
    self.isTogglingTouchID = YES;
    sender.isEnable = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *errMsg = nil;
        BOOL ok = [LMSystemOptimizeService setSudoTouchIDEnabled:targetOn errorMessage:&errMsg];
        BOOL finalOn = [LMSystemOptimizeService isSudoTouchIDEnabled];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.isTogglingTouchID = NO;
            [strongSelf _applyTouchIDState:finalOn available:YES];
            if (!ok && errMsg.length > 0) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleWarning;
                alert.messageText = LMToolLocalized(@"Touch ID 设置未变更", @"Touch ID Unchanged");
                alert.informativeText = errMsg;
                [alert addButtonWithTitle:LMToolLocalized(@"知道了", @"OK")];
                [alert beginSheetModalForWindow:strongSelf.window completionHandler:nil];
            }
        });
    });
}

- (void)_onToggleDSStore:(COSwitch *)sender {
    BOOL targetOn = sender.isOn;
    sender.isEnable = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [LMSystemOptimizeService setSuppressNetworkDSStore:targetOn suppressUSBDSStore:targetOn];
        BOOL netOff = [LMSystemOptimizeService isNetworkDSStoreSuppressed];
        BOOL usbOff = [LMSystemOptimizeService isUSBDSStoreSuppressed];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.dsStoreRow.toggleSwitch.isEnable = YES;
            [strongSelf _applyDSStoreState:(netOff && usbOff) partial:(netOff != usbOff)];
        });
    });
}

#pragma mark - Selection & Execution

- (void)_refreshTaskRows {
    NSUInteger i;
    for (i = 0; i < self.taskRows.count; i++) {
        [self.taskRows[i] refreshFromTask];
    }
}

- (void)_refreshSummaryBar {
    NSUInteger selectedCount = 0;
    NSUInteger i;
    for (i = 0; i < self.tasks.count; i++) {
        if (self.tasks[i].isSelected) {
            selectedCount++;
        }
    }

    if (selectedCount == 0) {
        self.selectAllCheck.state = NSControlStateValueOff;
    } else if (selectedCount == self.tasks.count) {
        self.selectAllCheck.state = NSControlStateValueOn;
    } else {
        self.selectAllCheck.state = NSControlStateValueMixed;
    }

    BOOL vpn = [LMSystemOptimizeService hasActiveVPNTunnel];
    NSString *vpnSuffix = vpn ? LMToolLocalized(@" · VPN 保护中", @" · VPN Safe") : nil;

    if (selectedCount == 0) {
        self.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
            summaryAttributedWithPrefix:LMToolLocalized(@"未选择维护项", @"None selected")
                              highlight:@""
                                 suffix:vpnSuffix
                         highlightColor:[NSColor colorWithHex:0x94979B]];
    } else {
        NSString *hi = [NSString stringWithFormat:LMToolLocalized(@"%lu 项", @"%lu tasks"), (unsigned long)selectedCount];
        self.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
            summaryAttributedWithPrefix:LMToolLocalized(@"已选择 ", @"Selected ")
                              highlight:hi
                                 suffix:vpnSuffix
                         highlightColor:[NSColor colorWithHex:0x04D999]];
    }
    self.runButton.enabled = (selectedCount > 0 && !self.isExecuting);
}

- (void)_onToggleSelectAllCheck:(LMCheckboxButton *)sender {
    BOOL target = (sender.state == NSControlStateValueOn);
    NSUInteger i;
    for (i = 0; i < self.tasks.count; i++) {
        self.tasks[i].isSelected = target;
    }
    [self _refreshTaskRows];
    [self _refreshSummaryBar];
}

- (void)_onClickSelectAllText:(id)sender {
    BOOL allChecked = YES;
    NSUInteger i;
    for (i = 0; i < self.tasks.count; i++) {
        if (!self.tasks[i].isSelected) {
            allChecked = NO;
            break;
        }
    }
    for (i = 0; i < self.tasks.count; i++) {
        self.tasks[i].isSelected = !allChecked;
    }
    [self _refreshTaskRows];
    [self _refreshSummaryBar];
}

- (void)_onRunMaintenance:(id)sender {
    if (self.isExecuting) {
        return;
    }
    NSMutableArray<LMSystemOptimizeTask *> *selected = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < self.tasks.count; i++) {
        if (self.tasks[i].isSelected) {
            [selected addObject:self.tasks[i]];
        }
    }
    if (selected.count == 0) {
        return;
    }

    self.isExecuting = YES;
    self.runButton.enabled = NO;
    self.runButton.title = LMToolLocalized(@"优化中...", @"Running...");

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        uint64_t totalFreed = 0;
        NSUInteger idx;
        for (idx = 0; idx < selected.count; idx++) {
            LMSystemOptimizeTask *task = selected[idx];
            dispatch_sync(dispatch_get_main_queue(), ^{
                task.state = LMSystemOptimizeTaskStateRunning;
                [weakSelf _refreshTaskRows];
            });

            [LMSystemOptimizeService executeTask:task allowPrivilegedDNS:NO];
            totalFreed += task.reclaimedBytes;

            dispatch_sync(dispatch_get_main_queue(), ^{
                [weakSelf _refreshTaskRows];
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.isExecuting = NO;
            strongSelf.runButton.enabled = YES;
            strongSelf.runButton.title = LMToolLocalized(@"立即优化", @"Optimize");

            NSString *doneHi = (totalFreed > 0)
                ? [NSString stringWithFormat:LMToolLocalized(@"完成，释放 %@", @"Done, freed %@"), LMFormatByteCount(totalFreed)]
                : LMToolLocalized(@"全部维护项已完成", @"All tasks completed");
            strongSelf.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
                summaryAttributedWithPrefix:@""
                                  highlight:doneHi
                                     suffix:nil
                             highlightColor:[NSColor colorWithHex:0x04D999]];
        });
    });
}

@end
