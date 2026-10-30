//
//  LMInstallerCleanWindowController.m
//  Lemon
//

#import "LMInstallerCleanWindowController.h"
#import "LMInstallerScanner.h"
#import "LMInstallerItem.h"
#import <Masonry/Masonry.h>
#import <QMCoreFunction/NSColor+Extension.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/NSFontHelper.h>

typedef NS_ENUM(NSInteger, LMInstallerFilterTab) {
    LMInstallerFilterTabAll = 0,
    LMInstallerFilterTabInstalled = 1,
    LMInstallerFilterTabLocal = 2,
    LMInstallerFilterTabHomebrew = 3,
    LMInstallerFilterTabApps = 4
};

@interface LMInstallerCellView : NSTableCellView <LMToolHoverCellProtocol>
@property (nonatomic, strong) LMCheckboxButton *checkBox;
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) LMToolPillBadgeView *statusPill;
@property (nonatomic, strong) NSTextField *sourceLabel;
@property (nonatomic, strong) NSTextField *sizeLabel;
@property (nonatomic, strong) NSButton *finderBtn;
@property (nonatomic, copy) void (^onToggleCheck)(BOOL checked);
@property (nonatomic, copy) void (^onRevealFinder)(void);
@end

@implementation LMInstallerCellView

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
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_nameLabel];

        _statusPill = [[LMToolPillBadgeView alloc] init];
        [self addSubview:_statusPill];

        _sourceLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                  font:[NSFontHelper getLightSystemFont:12]
                                                                 color:[NSColor colorWithHex:0x94979B]];
        _sourceLabel.alignment = NSTextAlignmentCenter;
        [self addSubview:_sourceLabel];

        _sizeLabel = [LMModernToolBaseWindowController labelWithText:@"0 B"
                                                                font:[NSFontHelper getRegularSystemFont:13]
                                                               color:[LMAppThemeHelper getTitleColor]];
        _sizeLabel.alignment = NSTextAlignmentRight;
        [self addSubview:_sizeLabel];

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
            make.width.height.mas_equalTo(30);
        }];

        [_nameLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_iconView.mas_right).offset(12);
            make.centerY.equalTo(self);
            make.right.lessThanOrEqualTo(_statusPill.mas_left).offset(-14);
        }];

        [_statusPill mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(426);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(68);
            make.height.mas_equalTo(20);
        }];

        [_sourceLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(514);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(84);
        }];

        [_sizeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
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

@interface LMInstallerCleanWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) LMInstallerScanner *scanner;
@property (nonatomic, strong) NSArray<LMInstallerItem *> *allItems;
@property (nonatomic, strong) NSArray<LMInstallerItem *> *filteredItems;
@property (nonatomic, assign) LMInstallerFilterTab activeTab;
@property (nonatomic, copy) NSString *searchKeyword;
@property (nonatomic, assign) BOOL sortSizeAscending;
@property (nonatomic, assign) BOOL permanentDeleteMode;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, assign) BOOL isCleaning;

@property (nonatomic, strong) LMBorderButton *rescanButton;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) LMToolFilterBarView *filterBar;
@property (nonatomic, strong) NSTextField *sourceColLabel;
@property (nonatomic, strong) NSButton *sortSizeButton;

@property (nonatomic, strong) LMToolClickableTableView *tableView;
@property (nonatomic, strong) LMToolStatusOverlayView *statusOverlay;

@property (nonatomic, strong) LMCheckboxButton *selectAllCheck;
@property (nonatomic, strong) LMBorderButton *selectInstalledBtn;
@property (nonatomic, strong) LMBorderButton *cleanModeBtn;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) LMRectangleButton *cleanButton;

@end

@implementation LMInstallerCleanWindowController

- (instancetype)init {
    self = [super initWithToolTitle:LMToolLocalized(@"安装包清理", @"Installer Cleanup")
                         windowSize:NSMakeSize(780, 482)];
    return self;
}

- (void)setupToolContentView {
    self.scanner = [[LMInstallerScanner alloc] init];
    self.allItems = @[];
    self.filteredItems = @[];
    self.activeTab = LMInstallerFilterTabAll;
    self.searchKeyword = @"";
    self.sortSizeAscending = NO;
    self.permanentDeleteMode = NO;

    [self _setupTopRightAccessories];

    NSView *body = self.bodyContentView;

    NSArray<NSString *> *tabs = @[
        LMToolLocalized(@"全部", @"All"),
        LMToolLocalized(@"已安装", @"Installed"),
        LMToolLocalized(@"本地目录", @"Local"),
        @"Homebrew",
        LMToolLocalized(@"应用下载", @"Apps")
    ];
    LMToolFilterBarView *fBar = [[LMToolFilterBarView alloc] initWithTitles:tabs];
    __weak typeof(self) weakSelf = self;
    fBar.onSelectTab = ^(NSInteger index) {
        weakSelf.activeTab = (LMInstallerFilterTab)index;
        [weakSelf _applyFilterAndReload];
    };
    [body addSubview:fBar];
    self.filterBar = fBar;

    [fBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(body);
        make.height.mas_equalTo(40);
    }];

    NSTextField *srcHeader = [LMModernToolBaseWindowController labelWithText:LMToolLocalized(@"来源", @"Source")
                                                                        font:[NSFontHelper getRegularSystemFont:12]
                                                                       color:[NSColor colorWithHex:0x94979B]];
    srcHeader.alignment = NSTextAlignmentCenter;
    [fBar addSubview:srcHeader];
    self.sourceColLabel = srcHeader;
    [srcHeader mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(fBar).offset(514);
        make.centerY.equalTo(fBar);
        make.width.mas_equalTo(84);
    }];

    NSButton *sizeSortBtn = [LMModernToolBaseWindowController sortableColumnButtonWithTitle:LMToolLocalized(@"大小", @"Size")
                                                                                  alignment:NSTextAlignmentRight
                                                                                     target:self
                                                                                     action:@selector(_onToggleSortSize:)];
    [fBar addSubview:sizeSortBtn];
    self.sortSizeButton = sizeSortBtn;
    [sizeSortBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(fBar).offset(-52);
        make.centerY.equalTo(fBar);
        make.width.mas_equalTo(88);
    }];
    [self _refreshSortHeader];

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

    self.selectInstalledBtn = [LMModernToolBaseWindowController ghostButtonWithTitle:LMToolLocalized(@"仅选已安装", @"Installed Only")
                                                                            fontSize:12
                                                                              target:self
                                                                              action:@selector(_onSelectInstalledOnly:)];
    [bottomBar addSubview:self.selectInstalledBtn];

    self.cleanModeBtn = [LMModernToolBaseWindowController ghostButtonWithTitle:[self _cleanModeButtonTitle]
                                                                      fontSize:12
                                                                        target:self
                                                                        action:@selector(_onShowCleanModeMenu:)];
    [bottomBar addSubview:self.cleanModeBtn];

    self.summaryLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                   font:[NSFontHelper getLightSystemFont:12.5]
                                                                  color:[NSColor colorWithHex:0x94979B]];
    self.summaryLabel.alignment = NSTextAlignmentRight;
    [bottomBar addSubview:self.summaryLabel];

    self.cleanButton = [LMModernToolBaseWindowController primaryButtonWithTitle:LMToolLocalized(@"立即清理", @"Clean")
                                                                         target:self
                                                                         action:@selector(_onCleanAction:)];
    self.cleanButton.enabled = NO;
    [bottomBar addSubview:self.cleanButton];

    [self.selectAllCheck mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(bottomBar).offset(28);
        make.centerY.equalTo(bottomBar);
        make.width.height.mas_equalTo(15);
    }];

    [allLabelBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.selectAllCheck.mas_right).offset(6);
        make.centerY.equalTo(bottomBar);
    }];

    [self.selectInstalledBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(allLabelBtn.mas_right).offset(14);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(78);
        make.height.mas_equalTo(24);
    }];

    [self.cleanModeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.selectInstalledBtn.mas_right).offset(8);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(92);
        make.height.mas_equalTo(24);
    }];

    [self.cleanButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(bottomBar).offset(-24);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(104);
        make.height.mas_equalTo(34);
    }];

    [self.summaryLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.cleanButton.mas_left).offset(-16);
        make.centerY.equalTo(bottomBar);
        make.left.greaterThanOrEqualTo(self.cleanModeBtn.mas_right).offset(12);
    }];

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
        make.top.equalTo(fBar.mas_bottom);
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

    self.searchField = [LMModernToolBaseWindowController searchFieldWithPlaceholder:LMToolLocalized(@"搜索安装包", @"Search")
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
    if (self.isScanning || self.isCleaning) {
        return;
    }
    self.isScanning = YES;
    self.cleanButton.enabled = NO;
    self.rescanButton.enabled = NO;
    [self.statusOverlay showLoadingWithTitle:LMToolLocalized(@"正在扫描安装包...", @"Scanning installers...")];

    __weak typeof(self) weakSelf = self;
    [self.scanner startScanWithProgress:^(NSString *currentSource, NSUInteger foundCount) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *msg = (foundCount > 0)
            ? [NSString stringWithFormat:LMToolLocalized(@"已发现 %lu 个安装包...", @"Found %lu installers..."), (unsigned long)foundCount]
            : LMToolLocalized(@"正在扫描安装包...", @"Scanning installers...");
        [strongSelf.statusOverlay showLoadingWithTitle:msg];
    } completion:^(NSArray<LMInstallerItem *> *items, BOOL cancelled) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isScanning = NO;
        strongSelf.rescanButton.enabled = YES;
        if (!cancelled) {
            strongSelf.allItems = items ?: @[];
            [strongSelf _applyFilterAndReload];
        }
    }];
}

- (void)_applyFilterAndReload {
    NSMutableArray<LMInstallerItem *> *matched = [NSMutableArray array];
    NSString *kw = [self.searchKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    NSUInteger i;
    for (i = 0; i < self.allItems.count; i++) {
        LMInstallerItem *it = self.allItems[i];
        BOOL tabOk = NO;
        switch (self.activeTab) {
            case LMInstallerFilterTabAll:
                tabOk = YES;
                break;
            case LMInstallerFilterTabInstalled:
                tabOk = it.isAppAlreadyInstalled;
                break;
            case LMInstallerFilterTabLocal:
                tabOk = (it.sourceGroup == LMInstallerSourceGroupLocal);
                break;
            case LMInstallerFilterTabHomebrew:
                tabOk = (it.sourceGroup == LMInstallerSourceGroupHomebrew);
                break;
            case LMInstallerFilterTabApps:
                tabOk = (it.sourceGroup == LMInstallerSourceGroupApps);
                break;
        }
        if (!tabOk) {
            continue;
        }
        if (kw.length > 0) {
            NSString *dName = (it.displayName ?: @"").lowercaseString;
            NSString *sTag = (it.sourceTag ?: @"").lowercaseString;
            if (![dName containsString:kw] && ![sTag containsString:kw]) {
                continue;
            }
        }
        [matched addObject:it];
    }

    BOOL asc = self.sortSizeAscending;
    [matched sortUsingComparator:^NSComparisonResult(LMInstallerItem *a, LMInstallerItem *b) {
        if (a.sizeInBytes != b.sizeInBytes) {
            NSComparisonResult r = (a.sizeInBytes < b.sizeInBytes) ? NSOrderedAscending : NSOrderedDescending;
            return asc ? r : -r;
        }
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];

    self.filteredItems = matched;
    [self.tableView reloadData];

    if (!self.isScanning) {
        if (self.filteredItems.count == 0) {
            NSString *emptyMsg = (self.allItems.count == 0)
                ? LMToolLocalized(@"很干净，未发现残留离线安装包", @"Clean — no installer files found")
                : LMToolLocalized(@"当前分类下暂无安装包", @"No matching installers");
            [self.statusOverlay showEmptyWithTitle:emptyMsg];
        } else {
            [self.statusOverlay dismissOverlay];
        }
    }
    [self _refreshSummaryBar];
}

- (void)_refreshSummaryBar {
    uint64_t selectedBytes = 0;
    NSUInteger selectedCount = 0;
    NSUInteger visibleSelected = 0;
    NSUInteger i;
    for (i = 0; i < self.allItems.count; i++) {
        LMInstallerItem *it = self.allItems[i];
        if (it.isSelected) {
            selectedCount++;
            selectedBytes += it.sizeInBytes;
        }
    }
    for (i = 0; i < self.filteredItems.count; i++) {
        if (self.filteredItems[i].isSelected) {
            visibleSelected++;
        }
    }

    if (self.filteredItems.count == 0 || visibleSelected == 0) {
        self.selectAllCheck.state = NSControlStateValueOff;
    } else if (visibleSelected == self.filteredItems.count) {
        self.selectAllCheck.state = NSControlStateValueOn;
    } else {
        self.selectAllCheck.state = NSControlStateValueMixed;
    }

    if (selectedCount == 0) {
        self.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
            summaryAttributedWithPrefix:LMToolLocalized(@"未选择安装包", @"None selected")
                              highlight:@""
                                 suffix:nil
                         highlightColor:[NSColor colorWithHex:0x94979B]];
    } else {
        NSString *prefix = [NSString stringWithFormat:LMToolLocalized(@"已选 %lu 项，共 ", @"%lu selected, "), (unsigned long)selectedCount];
        self.summaryLabel.attributedStringValue = [LMModernToolBaseWindowController
            summaryAttributedWithPrefix:prefix
                              highlight:LMFormatByteCount(selectedBytes)
                                 suffix:nil
                         highlightColor:[NSColor colorWithHex:0x04D999]];
    }
    self.cleanButton.enabled = (selectedCount > 0 && !self.isScanning && !self.isCleaning);
}

#pragma mark - Actions

- (void)_refreshSortHeader {
    [LMModernToolBaseWindowController styleSortableColumnButton:self.sortSizeButton
                                                          title:LMToolLocalized(@"大小", @"Size")
                                                         active:YES
                                                      ascending:self.sortSizeAscending
                                                      alignment:NSTextAlignmentRight];
}

- (void)_onToggleSortSize:(id)sender {
    self.sortSizeAscending = !self.sortSizeAscending;
    [self _refreshSortHeader];
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
    LMInstallerItem *item = self.filteredItems[(NSUInteger)row];
    item.isSelected = !item.isSelected;
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                              columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [self _refreshSummaryBar];
}

- (void)_revealRowAtIndex:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.filteredItems.count) {
        return;
    }
    LMInstallerItem *item = self.filteredItems[(NSUInteger)row];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:item.filePath]]];
}

- (void)_onToggleSelectAllCheck:(LMCheckboxButton *)sender {
    BOOL target = (sender.state == NSControlStateValueOn);
    NSUInteger i;
    for (i = 0; i < self.filteredItems.count; i++) {
        self.filteredItems[i].isSelected = target;
    }
    [self.tableView reloadData];
    [self _refreshSummaryBar];
}

- (void)_onClickSelectAllText:(id)sender {
    BOOL allChecked = YES;
    NSUInteger i;
    for (i = 0; i < self.filteredItems.count; i++) {
        if (!self.filteredItems[i].isSelected) {
            allChecked = NO;
            break;
        }
    }
    for (i = 0; i < self.filteredItems.count; i++) {
        self.filteredItems[i].isSelected = !allChecked;
    }
    [self.tableView reloadData];
    [self _refreshSummaryBar];
}

- (void)_onSelectInstalledOnly:(id)sender {
    NSUInteger i;
    for (i = 0; i < self.allItems.count; i++) {
        self.allItems[i].isSelected = self.allItems[i].isAppAlreadyInstalled;
    }
    [self.tableView reloadData];
    [self _refreshSummaryBar];
}

- (NSString *)_cleanModeButtonTitle {
    return self.permanentDeleteMode
        ? LMToolLocalized(@"永久删除 ▾", @"Delete ▾")
        : LMToolLocalized(@"移入废纸篓 ▾", @"To Trash ▾");
}

- (void)_onShowCleanModeMenu:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"InstallerMode"];
    NSMenuItem *trashItem = [[NSMenuItem alloc] initWithTitle:LMToolLocalized(@"移入废纸篓（推荐）", @"Move to Trash (Recommended)")
                                                       action:@selector(_selectTrashMode:)
                                                keyEquivalent:@""];
    trashItem.target = self;
    trashItem.state = self.permanentDeleteMode ? NSControlStateValueOff : NSControlStateValueOn;
    [menu addItem:trashItem];

    NSMenuItem *delItem = [[NSMenuItem alloc] initWithTitle:LMToolLocalized(@"永久删除", @"Delete Permanently")
                                                     action:@selector(_selectPermanentMode:)
                                              keyEquivalent:@""];
    delItem.target = self;
    delItem.state = self.permanentDeleteMode ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:delItem];

    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height + 4) inView:sender];
}

- (void)_selectTrashMode:(id)sender {
    self.permanentDeleteMode = NO;
    self.cleanModeBtn.title = [self _cleanModeButtonTitle];
    [self.cleanModeBtn setNeedsDisplay:YES];
}

- (void)_selectPermanentMode:(id)sender {
    self.permanentDeleteMode = YES;
    self.cleanModeBtn.title = [self _cleanModeButtonTitle];
    [self.cleanModeBtn setNeedsDisplay:YES];
}

- (void)_onCleanAction:(id)sender {
    NSMutableArray<LMInstallerItem *> *targets = [NSMutableArray array];
    uint64_t totalBytes = 0;
    NSUInteger i;
    for (i = 0; i < self.allItems.count; i++) {
        if (self.allItems[i].isSelected) {
            [targets addObject:self.allItems[i]];
            totalBytes += self.allItems[i].sizeInBytes;
        }
    }
    if (targets.count == 0) {
        return;
    }

    BOOL permanent = self.permanentDeleteMode;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = permanent ? NSAlertStyleCritical : NSAlertStyleInformational;
    alert.messageText = permanent
        ? LMToolLocalized(@"确认永久删除所选安装包？", @"Permanently delete selected installers?")
        : LMToolLocalized(@"确认将所选安装包移入废纸篓？", @"Move selected installers to Trash?");
    alert.informativeText = [NSString stringWithFormat:LMToolLocalized(@"共 %lu 个文件（%@），已安装的应用程序不受影响。",
                                                                       @"%lu files (%@). Installed applications remain unaffected."),
                             (unsigned long)targets.count, LMFormatByteCount(totalBytes)];
    [alert addButtonWithTitle:LMToolLocalized(@"确认清理", @"Clean")];
    [alert addButtonWithTitle:LMToolLocalized(@"取消", @"Cancel")];

    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf _executeCleanOnTargets:targets permanent:permanent];
        }
    }];
}

- (void)_executeCleanOnTargets:(NSArray<LMInstallerItem *> *)targets permanent:(BOOL)permanent {
    self.isCleaning = YES;
    self.cleanButton.enabled = NO;
    self.rescanButton.enabled = NO;
    [self.statusOverlay showLoadingWithTitle:LMToolLocalized(@"正在清理...", @"Cleaning...")];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableSet<NSString *> *cleanedPaths = [NSMutableSet set];
        if (permanent) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSUInteger i;
            for (i = 0; i < targets.count; i++) {
                NSString *p = targets[i].filePath;
                if ([fm removeItemAtPath:p error:nil]) {
                    [cleanedPaths addObject:p];
                }
            }
        } else {
            NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:targets.count];
            NSUInteger i;
            for (i = 0; i < targets.count; i++) {
                [urls addObject:[NSURL fileURLWithPath:targets[i].filePath]];
            }
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            [[NSWorkspace sharedWorkspace] recycleURLs:urls completionHandler:^(NSDictionary<NSURL *,NSURL *> *newURLs, NSError *error) {
                for (NSURL *origURL in newURLs.allKeys) {
                    if (origURL.path) {
                        [cleanedPaths addObject:origURL.path];
                    }
                }
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf.isCleaning = NO;
            strongSelf.rescanButton.enabled = YES;

            NSMutableArray<LMInstallerItem *> *remaining = [NSMutableArray array];
            NSUInteger i;
            for (i = 0; i < strongSelf.allItems.count; i++) {
                LMInstallerItem *it = strongSelf.allItems[i];
                if (![cleanedPaths containsObject:it.filePath]) {
                    [remaining addObject:it];
                }
            }
            strongSelf.allItems = remaining;
            [strongSelf _applyFilterAndReload];
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
    LMInstallerItem *item = self.filteredItems[(NSUInteger)row];
    LMInstallerCellView *cell = [tableView makeViewWithIdentifier:@"InstallerCell" owner:nil];
    if (!cell) {
        cell = [[LMInstallerCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 58)];
        cell.identifier = @"InstallerCell";
    }

    cell.checkBox.state = item.isSelected ? NSControlStateValueOn : NSControlStateValueOff;
    cell.iconView.image = item.fileIcon ?: [[NSWorkspace sharedWorkspace] iconForFile:item.filePath];
    cell.nameLabel.stringValue = item.displayName ?: [item.filePath lastPathComponent];
    cell.nameLabel.textColor = [LMAppThemeHelper getTitleColor];
    cell.sourceLabel.stringValue = item.sourceTag ?: @"";
    cell.sizeLabel.stringValue = LMFormatByteCount(item.sizeInBytes);
    cell.sizeLabel.textColor = [LMAppThemeHelper getTitleColor];

    if (item.isAppAlreadyInstalled) {
        [cell.statusPill configureWithText:LMToolLocalized(@"已安装", @"Installed") tone:LMToolPillToneMint];
    } else {
        [cell.statusPill configureWithText:LMToolLocalized(@"未安装", @"Uninstalled") tone:LMToolPillToneNeutral];
    }

    cell.finderBtn.hidden = YES;

    __weak typeof(self) weakSelf = self;
    cell.onToggleCheck = ^(BOOL checked) {
        item.isSelected = checked;
        [weakSelf _refreshSummaryBar];
    };
    cell.onRevealFinder = ^{
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:item.filePath]]];
    };

    return cell;
}

@end
