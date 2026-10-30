//
//  LMAppSlimWindowController.m
//  Lemon
//

#import "LMAppSlimWindowController.h"
#import "LMAppSlimScanner.h"
#import "LMAppSlimItem.h"
#import <Masonry/Masonry.h>
#import <QMCoreFunction/NSColor+Extension.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/NSFontHelper.h>

typedef NS_ENUM(NSInteger, LMAppSlimSortField) {
    LMAppSlimSortFieldSavings = 0,
    LMAppSlimSortFieldTotalSize = 1,
    LMAppSlimSortFieldName = 2
};

@interface LMAppSlimCellView : NSTableCellView <LMToolHoverCellProtocol>
@property (nonatomic, strong) LMCheckboxButton *checkBox;
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) LMToolPillBadgeView *statusPill;
@property (nonatomic, strong) NSTextField *totalSizeLabel;
@property (nonatomic, strong) NSTextField *savingsLabel;
@property (nonatomic, strong) NSButton *finderBtn;
@property (nonatomic, copy) void (^onToggleCheck)(BOOL checked);
@property (nonatomic, copy) void (^onRevealFinder)(void);
@end

@implementation LMAppSlimCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _checkBox = [LMModernToolBaseWindowController checkboxWithMixed:NO
                                                                 target:self
                                                                 action:@selector(_handleCheck:)];
        [self addSubview:_checkBox];

        _iconView = [[NSImageView alloc] init];
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_iconView];

        _nameLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                font:[NSFontHelper getRegularSystemFont:13.5]
                                                               color:[LMAppThemeHelper getTitleColor]];
        [self addSubview:_nameLabel];

        _statusPill = [[LMToolPillBadgeView alloc] init];
        [self addSubview:_statusPill];

        _totalSizeLabel = [LMModernToolBaseWindowController labelWithText:@"0 B"
                                                                     font:[NSFontHelper getLightSystemFont:12.5]
                                                                    color:[NSColor colorWithHex:0x94979B]];
        _totalSizeLabel.alignment = NSTextAlignmentRight;
        [self addSubview:_totalSizeLabel];

        _savingsLabel = [LMModernToolBaseWindowController labelWithText:@"0 B"
                                                                   font:[NSFontHelper getMediumSystemFont:13]
                                                                  color:[NSColor colorWithHex:0x04D999]];
        _savingsLabel.alignment = NSTextAlignmentRight;
        [self addSubview:_savingsLabel];

        _finderBtn = [LMModernToolBaseWindowController finderHoverButtonWithTarget:self
                                                                            action:@selector(_handleReveal:)];
        [self addSubview:_finderBtn];

        [_checkBox mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(28);
            make.centerY.equalTo(self);
            make.width.height.mas_equalTo(15);
        }];

        [_iconView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_checkBox.mas_right).offset(14);
            make.centerY.equalTo(self);
            make.width.height.mas_equalTo(32);
        }];

        [_nameLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_iconView.mas_right).offset(12);
            make.centerY.equalTo(self);
            make.right.lessThanOrEqualTo(_statusPill.mas_left).offset(-16);
        }];

        [_statusPill mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(366);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(72);
            make.height.mas_equalTo(20);
        }];

        [_totalSizeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(492);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(88);
        }];

        [_savingsLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self).offset(-52);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(96);
        }];

        [_finderBtn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.right.equalTo(self).offset(-24);
            make.centerY.equalTo(self);
            make.width.height.mas_equalTo(18);
        }];
    }
    return self;
}

- (void)updateHoverState:(BOOL)isHovered {
    self.finderBtn.hidden = !isHovered;
}

- (void)_handleCheck:(LMCheckboxButton *)sender {
    if (self.onToggleCheck) {
        self.onToggleCheck(sender.state == NSControlStateValueOn);
    }
}

- (void)_handleReveal:(id)sender {
    if (self.onRevealFinder) {
        self.onRevealFinder();
    }
}

@end

@interface LMAppSlimWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) LMAppSlimScanner *scanner;
@property (nonatomic, strong) NSArray<LMAppSlimItem *> *items;
@property (nonatomic, strong) NSArray<LMAppSlimItem *> *filteredItems;
@property (nonatomic, copy) NSString *searchKeyword;
@property (nonatomic, assign) LMAppSlimSortField sortField;
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, assign) BOOL backupOriginalToTrash;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, assign) BOOL isSlimming;

@property (nonatomic, strong) LMBorderButton *rescanButton;
@property (nonatomic, strong) NSSearchField *searchField;

@property (nonatomic, strong) NSButton *sortNameBtn;
@property (nonatomic, strong) NSButton *sortTotalBtn;
@property (nonatomic, strong) NSButton *sortSavingsBtn;

@property (nonatomic, strong) LMToolClickableTableView *tableView;
@property (nonatomic, strong) LMToolStatusOverlayView *statusOverlay;

@property (nonatomic, strong) LMCheckboxButton *selectAllCheck;
@property (nonatomic, strong) LMBorderButton *backupModeBtn;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) LMRectangleButton *slimButton;

@end

@implementation LMAppSlimWindowController

- (instancetype)init {
    self = [super initWithToolTitle:LMToolLocalized(@"应用架构瘦身", @"App Slimmer")
                         windowSize:NSMakeSize(780, 482)];
    return self;
}

- (void)setupToolContentView {
    self.scanner = [[LMAppSlimScanner alloc] init];
    self.items = @[];
    self.filteredItems = @[];
    self.searchKeyword = @"";
    self.sortField = LMAppSlimSortFieldSavings;
    self.sortAscending = NO;
    self.backupOriginalToTrash = YES;

    [self _setupTopRightAccessories];

    NSView *body = self.bodyContentView;

    // 40pt 列头栏（1:1 复刻开机启动项管理 LMLoginItemManageViewController）
    NSView *colHeader = [[NSView alloc] init];
    [body addSubview:colHeader];
    [colHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(body);
        make.height.mas_equalTo(40);
    }];

    NSView *hLine = [[NSView alloc] init];
    hLine.wantsLayer = YES;
    [LMAppThemeHelper setDivideLineColorFor:hLine];
    [colHeader addSubview:hLine];
    [hLine mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(colHeader);
        make.height.mas_equalTo(1);
    }];

    self.sortNameBtn = [LMModernToolBaseWindowController sortableColumnButtonWithTitle:LMToolLocalized(@"应用程序", @"Application")
                                                                             alignment:NSTextAlignmentLeft
                                                                                target:self
                                                                                action:@selector(_onSortName:)];
    [colHeader addSubview:self.sortNameBtn];
    [self.sortNameBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(colHeader).offset(56);
        make.centerY.equalTo(colHeader);
        make.width.mas_equalTo(110);
    }];

    NSTextField *statusHeader = [LMModernToolBaseWindowController labelWithText:LMToolLocalized(@"状态", @"Status")
                                                                           font:[NSFontHelper getRegularSystemFont:12]
                                                                          color:[NSColor colorWithHex:0x94979B]];
    statusHeader.alignment = NSTextAlignmentCenter;
    [colHeader addSubview:statusHeader];
    [statusHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(colHeader).offset(366);
        make.centerY.equalTo(colHeader);
        make.width.mas_equalTo(72);
    }];

    self.sortTotalBtn = [LMModernToolBaseWindowController sortableColumnButtonWithTitle:LMToolLocalized(@"当前体积", @"App Size")
                                                                              alignment:NSTextAlignmentRight
                                                                                 target:self
                                                                                 action:@selector(_onSortTotal:)];
    [colHeader addSubview:self.sortTotalBtn];
    [self.sortTotalBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(colHeader).offset(492);
        make.centerY.equalTo(colHeader);
        make.width.mas_equalTo(88);
    }];

    self.sortSavingsBtn = [LMModernToolBaseWindowController sortableColumnButtonWithTitle:LMToolLocalized(@"可省空间", @"Reclaimable")
                                                                                alignment:NSTextAlignmentRight
                                                                                   target:self
                                                                                   action:@selector(_onSortSavings:)];
    [colHeader addSubview:self.sortSavingsBtn];
    [self.sortSavingsBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(colHeader).offset(-52);
        make.centerY.equalTo(colHeader);
        make.width.mas_equalTo(96);
    }];
    [self _refreshSortColumnHeaders];

    // 52pt 底部操作栏
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

    self.backupModeBtn = [LMModernToolBaseWindowController ghostButtonWithTitle:[self _backupModeTitle]
                                                                       fontSize:12
                                                                         target:self
                                                                         action:@selector(_onShowBackupModeMenu:)];
    [bottomBar addSubview:self.backupModeBtn];

    self.summaryLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                   font:[NSFontHelper getLightSystemFont:12.5]
                                                                  color:[NSColor colorWithHex:0x94979B]];
    self.summaryLabel.alignment = NSTextAlignmentRight;
    [bottomBar addSubview:self.summaryLabel];

    self.slimButton = [LMModernToolBaseWindowController primaryButtonWithTitle:LMToolLocalized(@"开始瘦身", @"Slim")
                                                                        target:self
                                                                        action:@selector(_onSlimAction:)];
    self.slimButton.enabled = NO;
    [bottomBar addSubview:self.slimButton];

    [self.selectAllCheck mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(bottomBar).offset(28);
        make.centerY.equalTo(bottomBar);
        make.width.height.mas_equalTo(15);
    }];

    [allLabelBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.selectAllCheck.mas_right).offset(6);
        make.centerY.equalTo(bottomBar);
    }];

    [self.backupModeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(allLabelBtn.mas_right).offset(14);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(108);
        make.height.mas_equalTo(24);
    }];

    [self.slimButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(bottomBar).offset(-24);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(104);
        make.height.mas_equalTo(34);
    }];

    [self.summaryLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.slimButton.mas_left).offset(-16);
        make.centerY.equalTo(bottomBar);
        make.left.greaterThanOrEqualTo(self.backupModeBtn.mas_right).offset(12);
    }];

    __weak typeof(self) weakSelf = self;
    LMToolClickableTableView *tv = nil;
    NSScrollView *sv = [LMModernToolBaseWindowController cleanTableScrollViewWithTable:&tv
                                                                              delegate:self
                                                                             rowHeight:58.0];
    self.tableView = tv;
    tv.onRowBodyClicked = ^(NSInteger row) {
        [weakSelf _toggleRowAtIndex:row];
    };
    tv.onRowDoubleClicked = ^(NSInteger row) {
        [weakSelf _revealRowAtIndex:row];
    };
    [body addSubview:sv];
    [sv mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(colHeader.mas_bottom);
        make.left.right.equalTo(body);
        make.bottom.equalTo(bottomBar.mas_top);
    }];

    LMToolStatusOverlayView *overlay = [[LMToolStatusOverlayView alloc] init];
    [body addSubview:overlay];
    self.statusOverlay = overlay;
    [overlay mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(sv);
    }];

    [self _startScanning];
}

- (void)_setupTopRightAccessories {
    NSView *right = self.headerRightContainer;

    self.searchField = [LMModernToolBaseWindowController searchFieldWithPlaceholder:LMToolLocalized(@"搜索应用", @"Search")
                                                                             target:self
                                                                             action:@selector(_onSearchChanged:)];
    [right addSubview:self.searchField];

    self.rescanButton = [LMModernToolBaseWindowController ghostButtonWithTitle:LMToolLocalized(@"刷新", @"Refresh")
                                                                      fontSize:11
                                                                        target:self
                                                                        action:@selector(_onRescan:)];
    [right addSubview:self.rescanButton];

    [self.searchField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(right);
        make.centerY.equalTo(right);
        make.width.mas_equalTo(132);
        make.height.mas_equalTo(22);
    }];

    [self.rescanButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.searchField.mas_left).offset(-8);
        make.centerY.equalTo(right);
        make.width.mas_equalTo(46);
        make.height.mas_equalTo(22);
        make.left.equalTo(right);
    }];
}

- (void)toolWindowWillClose {
    [self.scanner cancelScan];
}

#pragma mark - Scanning & Filtering

- (void)_startScanning {
    if (self.isScanning || self.isSlimming) {
        return;
    }
    self.isScanning = YES;
    self.slimButton.enabled = NO;
    self.rescanButton.enabled = NO;
    [self.statusOverlay showLoadingWithTitle:LMToolLocalized(@"正在扫描通用应用...", @"Scanning Universal apps...")];

    __weak typeof(self) weakSelf = self;
    [self.scanner startScanWithProgress:^(NSString *currentAppName, NSUInteger foundCount) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *msg = (foundCount > 0)
            ? [NSString stringWithFormat:LMToolLocalized(@"已发现 %lu 款可瘦身应用...", @"Found %lu Universal apps..."), (unsigned long)foundCount]
            : LMToolLocalized(@"正在扫描通用应用...", @"Scanning Universal apps...");
        [strongSelf.statusOverlay showLoadingWithTitle:msg];
    } completion:^(NSArray<LMAppSlimItem *> *items, BOOL cancelled) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isScanning = NO;
        strongSelf.rescanButton.enabled = YES;
        if (!cancelled) {
            strongSelf.items = items ?: @[];
            [strongSelf _applyFilterAndReload];
        }
    }];
}

- (void)_applyFilterAndReload {
    NSMutableArray<LMAppSlimItem *> *matched = [NSMutableArray array];
    NSString *kw = [self.searchKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    NSUInteger i;
    for (i = 0; i < self.items.count; i++) {
        LMAppSlimItem *it = self.items[i];
        if (kw.length > 0) {
            NSString *aName = (it.appName ?: @"").lowercaseString;
            NSString *bId = (it.bundleIdentifier ?: @"").lowercaseString;
            if (![aName containsString:kw] && ![bId containsString:kw]) {
                continue;
            }
        }
        [matched addObject:it];
    }

    LMAppSlimSortField field = self.sortField;
    BOOL asc = self.sortAscending;
    [matched sortUsingComparator:^NSComparisonResult(LMAppSlimItem *a, LMAppSlimItem *b) {
        NSComparisonResult r = NSOrderedSame;
        if (field == LMAppSlimSortFieldName) {
            r = [a.appName localizedCaseInsensitiveCompare:b.appName];
            return asc ? r : -r;
        } else if (field == LMAppSlimSortFieldTotalSize) {
            if (a.totalAppBytes != b.totalAppBytes) {
                r = (a.totalAppBytes < b.totalAppBytes) ? NSOrderedAscending : NSOrderedDescending;
            }
        } else {
            if (a.estimatedSavingsBytes != b.estimatedSavingsBytes) {
                r = (a.estimatedSavingsBytes < b.estimatedSavingsBytes) ? NSOrderedAscending : NSOrderedDescending;
            }
        }
        if (r == NSOrderedSame) {
            r = [a.appName localizedCaseInsensitiveCompare:b.appName];
        }
        return asc ? r : -r;
    }];

    self.filteredItems = matched;
    [self.tableView reloadData];

    if (!self.isScanning) {
        if (self.filteredItems.count == 0) {
            NSString *emptyMsg = (self.items.count == 0)
                ? LMToolLocalized(@"很干净，所有应用均为原生单架构", @"All apps are already native single-arch")
                : LMToolLocalized(@"暂未搜索到相关应用", @"No matching apps");
            [self.statusOverlay showEmptyWithTitle:emptyMsg];
        } else {
            [self.statusOverlay dismissOverlay];
        }
    }
    [self _refreshSummaryBar];
}

- (void)_refreshSummaryBar {
    uint64_t selectedSavings = 0;
    NSUInteger selectedCount = 0;
    NSUInteger eligibleVisible = 0;
    NSUInteger selectedVisible = 0;
    NSUInteger i;
    for (i = 0; i < self.items.count; i++) {
        LMAppSlimItem *it = self.items[i];
        if (it.isSelected && !it.isRunning) {
            selectedCount++;
            selectedSavings += it.estimatedSavingsBytes;
        }
    }
    for (i = 0; i < self.filteredItems.count; i++) {
        LMAppSlimItem *it = self.filteredItems[i];
        if (!it.isRunning) {
            eligibleVisible++;
            if (it.isSelected) {
                selectedVisible++;
            }
        }
    }

    if (eligibleVisible == 0 || selectedVisible == 0) {
        self.selectAllCheck.state = NSControlStateValueOff;
    } else if (selectedVisible == eligibleVisible) {
        self.selectAllCheck.state = NSControlStateValueOn;
    } else {
        self.selectAllCheck.state = NSControlStateValueMixed;
    }

    if (selectedCount == 0) {
        self.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
            summaryAttributedWithPrefix:LMToolLocalized(@"未选择应用", @"None selected")
                              highlight:@""
                                 suffix:nil
                         highlightColor:[NSColor colorWithHex:0x94979B]];
    } else {
        NSString *prefix = [NSString stringWithFormat:LMToolLocalized(@"已选 %lu 款，预计省 ", @"%lu selected, save "), (unsigned long)selectedCount];
        self.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
            summaryAttributedWithPrefix:prefix
                              highlight:LMFormatByteCount(selectedSavings)
                                 suffix:nil
                         highlightColor:[NSColor colorWithHex:0x04D999]];
    }
    self.slimButton.enabled = (selectedCount > 0 && !self.isScanning && !self.isSlimming);
}

#pragma mark - Sorting & Actions

- (void)_refreshSortColumnHeaders {
    [LMModernToolBaseWindowController styleSortableColumnButton:self.sortNameBtn
                                                          title:LMToolLocalized(@"应用程序", @"Application")
                                                         active:(self.sortField == LMAppSlimSortFieldName)
                                                      ascending:self.sortAscending
                                                      alignment:NSTextAlignmentLeft];
    [LMModernToolBaseWindowController styleSortableColumnButton:self.sortTotalBtn
                                                          title:LMToolLocalized(@"当前体积", @"App Size")
                                                         active:(self.sortField == LMAppSlimSortFieldTotalSize)
                                                      ascending:self.sortAscending
                                                      alignment:NSTextAlignmentRight];
    [LMModernToolBaseWindowController styleSortableColumnButton:self.sortSavingsBtn
                                                          title:LMToolLocalized(@"可省空间", @"Reclaimable")
                                                         active:(self.sortField == LMAppSlimSortFieldSavings)
                                                      ascending:self.sortAscending
                                                      alignment:NSTextAlignmentRight];
}

- (void)_onSortName:(id)sender {
    if (self.sortField == LMAppSlimSortFieldName) {
        self.sortAscending = !self.sortAscending;
    } else {
        self.sortField = LMAppSlimSortFieldName;
        self.sortAscending = YES;
    }
    [self _refreshSortColumnHeaders];
    [self _applyFilterAndReload];
}

- (void)_onSortTotal:(id)sender {
    if (self.sortField == LMAppSlimSortFieldTotalSize) {
        self.sortAscending = !self.sortAscending;
    } else {
        self.sortField = LMAppSlimSortFieldTotalSize;
        self.sortAscending = NO;
    }
    [self _refreshSortColumnHeaders];
    [self _applyFilterAndReload];
}

- (void)_onSortSavings:(id)sender {
    if (self.sortField == LMAppSlimSortFieldSavings) {
        self.sortAscending = !self.sortAscending;
    } else {
        self.sortField = LMAppSlimSortFieldSavings;
        self.sortAscending = NO;
    }
    [self _refreshSortColumnHeaders];
    [self _applyFilterAndReload];
}

- (void)_onSearchChanged:(NSSearchField *)sender {
    self.searchKeyword = sender.stringValue ?: @"";
    [self _applyFilterAndReload];
}

- (void)_onRescan:(id)sender {
    [self _startScanning];
}

- (void)_toggleRowAtIndex:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.filteredItems.count) {
        return;
    }
    LMAppSlimItem *item = self.filteredItems[(NSUInteger)row];
    if (item.isRunning) {
        return;
    }
    item.isSelected = !item.isSelected;
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                              columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [self _refreshSummaryBar];
}

- (void)_revealRowAtIndex:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.filteredItems.count) {
        return;
    }
    LMAppSlimItem *item = self.filteredItems[(NSUInteger)row];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:item.appPath]]];
}

- (void)_onToggleSelectAllCheck:(LMCheckboxButton *)sender {
    BOOL target = (sender.state == NSControlStateValueOn);
    NSUInteger i;
    for (i = 0; i < self.filteredItems.count; i++) {
        LMAppSlimItem *it = self.filteredItems[i];
        if (!it.isRunning) {
            it.isSelected = target;
        }
    }
    [self.tableView reloadData];
    [self _refreshSummaryBar];
}

- (void)_onClickSelectAllText:(id)sender {
    BOOL allChecked = YES;
    NSUInteger eligible = 0;
    NSUInteger i;
    for (i = 0; i < self.filteredItems.count; i++) {
        LMAppSlimItem *it = self.filteredItems[i];
        if (!it.isRunning) {
            eligible++;
            if (!it.isSelected) {
                allChecked = NO;
            }
        }
    }
    if (eligible == 0) {
        return;
    }
    for (i = 0; i < self.filteredItems.count; i++) {
        LMAppSlimItem *it = self.filteredItems[i];
        if (!it.isRunning) {
            it.isSelected = !allChecked;
        }
    }
    [self.tableView reloadData];
    [self _refreshSummaryBar];
}

- (NSString *)_backupModeTitle {
    return self.backupOriginalToTrash
        ? LMToolLocalized(@"原包进废纸篓 ▾", @"Backup Trash ▾")
        : LMToolLocalized(@"直接替换原包 ▾", @"Direct Slim ▾");
}

- (void)_onShowBackupModeMenu:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"SlimMode"];
    NSMenuItem *trashItem = [[NSMenuItem alloc] initWithTitle:LMToolLocalized(@"原包移入废纸篓（推荐，可还原）", @"Backup Original to Trash (Recommended)")
                                                       action:@selector(_selectBackupTrash:)
                                                keyEquivalent:@""];
    trashItem.target = self;
    trashItem.state = self.backupOriginalToTrash ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:trashItem];

    NSMenuItem *directItem = [[NSMenuItem alloc] initWithTitle:LMToolLocalized(@"直接替换原包（立即释放空间）", @"Replace Original Directly")
                                                        action:@selector(_selectDirectSlim:)
                                                 keyEquivalent:@""];
    directItem.target = self;
    directItem.state = self.backupOriginalToTrash ? NSControlStateValueOff : NSControlStateValueOn;
    [menu addItem:directItem];

    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height + 4) inView:sender];
}

- (void)_selectBackupTrash:(id)sender {
    self.backupOriginalToTrash = YES;
    self.backupModeBtn.title = [self _backupModeTitle];
    [self.backupModeBtn setNeedsDisplay:YES];
}

- (void)_selectDirectSlim:(id)sender {
    self.backupOriginalToTrash = NO;
    self.backupModeBtn.title = [self _backupModeTitle];
    [self.backupModeBtn setNeedsDisplay:YES];
}

- (void)_onSlimAction:(id)sender {
    NSMutableArray<LMAppSlimItem *> *targets = [NSMutableArray array];
    uint64_t estBytes = 0;
    NSUInteger i;
    for (i = 0; i < self.items.count; i++) {
        LMAppSlimItem *it = self.items[i];
        if (it.isSelected && !it.isRunning) {
            [targets addObject:it];
            estBytes += it.estimatedSavingsBytes;
        }
    }
    if (targets.count == 0) {
        return;
    }

    BOOL backupToTrash = self.backupOriginalToTrash;
    NSString *removeArch = [LMAppSlimScanner removableArchitectureName];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = backupToTrash ? NSAlertStyleInformational : NSAlertStyleWarning;
    alert.messageText = LMToolLocalized(@"确认执行应用架构瘦身？", @"Slim selected Universal apps?");
    alert.informativeText = backupToTrash
        ? [NSString stringWithFormat:LMToolLocalized(@"将剥离 %lu 款应用中的 %@ 冗余架构（预计省 %@），原包将备份至废纸篓。",
                                                     @"Strip %@ slices from %lu apps (~%@). Originals backed up to Trash."),
           (unsigned long)targets.count, removeArch, LMFormatByteCount(estBytes)]
        : [NSString stringWithFormat:LMToolLocalized(@"将剥离 %lu 款应用中的 %@ 冗余架构（立即释放 %@），不保留废纸篓备份。",
                                                     @"Strip %@ slices from %lu apps (~%@) without Trash backup."),
           (unsigned long)targets.count, removeArch, LMFormatByteCount(estBytes)];
    [alert addButtonWithTitle:LMToolLocalized(@"开始瘦身", @"Slim")];
    [alert addButtonWithTitle:LMToolLocalized(@"取消", @"Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf _executeSlimmingOnTargets:targets moveToTrash:backupToTrash];
        }
    }];
}

- (void)_executeSlimmingOnTargets:(NSArray<LMAppSlimItem *> *)targets moveToTrash:(BOOL)moveToTrash {
    self.isSlimming = YES;
    self.slimButton.enabled = NO;
    self.rescanButton.enabled = NO;
    [self.statusOverlay showLoadingWithTitle:LMToolLocalized(@"正在瘦身并校验签名...", @"Slimming & verifying signatures...")];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableSet<NSString *> *succeededPaths = [NSMutableSet set];
        NSMutableArray<NSString *> *failedMessages = [NSMutableArray array];
        uint64_t totalReclaimed = 0;

        NSUInteger i;
        for (i = 0; i < targets.count; i++) {
            LMAppSlimItem *app = targets[i];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.statusOverlay showLoadingWithTitle:
                    [NSString stringWithFormat:LMToolLocalized(@"正在处理 %@ (%lu/%lu)...", @"Slimming %@ (%lu/%lu)..."),
                     app.appName, (unsigned long)(i + 1), (unsigned long)targets.count]];
            });

            uint64_t saved = 0;
            NSString *err = nil;
            if ([LMAppSlimScanner slimApplicationItem:app moveOriginalToTrash:moveToTrash reclaimedBytes:&saved errorMessage:&err]) {
                [succeededPaths addObject:app.appPath];
                totalReclaimed += saved;
            } else {
                [failedMessages addObject:[NSString stringWithFormat:@"%@: %@", app.appName, err ?: @"Failed"]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.isSlimming = NO;
            strongSelf.rescanButton.enabled = YES;

            NSMutableArray<LMAppSlimItem *> *remaining = [NSMutableArray array];
            NSUInteger idx;
            for (idx = 0; idx < strongSelf.items.count; idx++) {
                LMAppSlimItem *it = strongSelf.items[idx];
                if (![succeededPaths containsObject:it.appPath]) {
                    [remaining addObject:it];
                }
            }
            strongSelf.items = remaining;
            [strongSelf _applyFilterAndReload];

            if (failedMessages.count > 0) {
                NSAlert *resAlert = [[NSAlert alloc] init];
                resAlert.alertStyle = NSAlertStyleInformational;
                resAlert.messageText = [NSString stringWithFormat:LMToolLocalized(@"完成 %lu 款应用瘦身（释放 %@）", @"Slimmed %lu apps (%@)"),
                                        (unsigned long)succeededPaths.count, LMFormatByteCount(totalReclaimed)];
                resAlert.informativeText = [failedMessages componentsJoinedByString:@"\n"];
                [resAlert addButtonWithTitle:LMToolLocalized(@"知道了", @"OK")];
                [resAlert beginSheetModalForWindow:strongSelf.window completionHandler:nil];
            }
        });
    });
}

#pragma mark - NSTableViewDataSource & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.filteredItems.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    LMToolHoverRowView *rv = [tableView makeViewWithIdentifier:@"HoverRow" owner:nil];
    if (!rv) {
        rv = [[LMToolHoverRowView alloc] initWithFrame:NSZeroRect];
        rv.identifier = @"HoverRow";
    }
    return rv;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.filteredItems.count) {
        return nil;
    }
    LMAppSlimItem *item = self.filteredItems[(NSUInteger)row];
    LMAppSlimCellView *cell = [tableView makeViewWithIdentifier:@"AppSlimCell" owner:nil];
    if (!cell) {
        cell = [[LMAppSlimCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 58)];
        cell.identifier = @"AppSlimCell";
    }

    cell.checkBox.enabled = !item.isRunning;
    cell.checkBox.state = (item.isSelected && !item.isRunning) ? NSControlStateValueOn : NSControlStateValueOff;
    cell.iconView.image = item.appIcon ?: [[NSWorkspace sharedWorkspace] iconForFile:item.appPath];
    cell.nameLabel.stringValue = item.appName ?: [[item.appPath lastPathComponent] stringByDeletingPathExtension];
    cell.nameLabel.textColor = [LMAppThemeHelper getTitleColor];
    cell.totalSizeLabel.stringValue = LMFormatByteCount(item.totalAppBytes);
    cell.savingsLabel.stringValue = LMFormatByteCount(item.estimatedSavingsBytes);

    if (item.isRunning) {
        [cell.statusPill configureWithText:LMToolLocalized(@"运行中", @"Running") tone:LMToolPillToneAmber];
    } else {
        [cell.statusPill configureWithText:LMToolLocalized(@"可瘦身", @"Universal") tone:LMToolPillToneMint];
    }

    cell.finderBtn.hidden = YES;

    __weak typeof(self) weakSelf = self;
    cell.onToggleCheck = ^(BOOL checked) {
        if (!item.isRunning) {
            item.isSelected = checked;
            [weakSelf _refreshSummaryBar];
        }
    };
    cell.onRevealFinder = ^{
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:item.appPath]]];
    };

    return cell;
}

@end
