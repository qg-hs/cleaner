//
//  LMProjectPurgeWindowController.m
//  Lemon
//

#import "LMProjectPurgeWindowController.h"
#import "LMProjectPurgeScanner.h"
#import "LMProjectPurgeItem.h"
#import <Masonry/Masonry.h>
#import <QMCoreFunction/NSColor+Extension.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/NSFontHelper.h>

typedef NS_ENUM(NSInteger, LMProjectSortField) {
    LMProjectSortFieldSize = 0,
    LMProjectSortFieldTime = 1
};

@interface LMProjectPurgeCellView : NSTableCellView <LMToolHoverCellProtocol>
@property (nonatomic, strong) LMCheckboxButton *checkBox;
@property (nonatomic, strong) NSImageView *folderIconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *pathLabel;
@property (nonatomic, strong) LMToolPillBadgeView *ecoPill;
@property (nonatomic, strong) NSTextField *ageLabel;
@property (nonatomic, strong) NSTextField *sizeLabel;
@property (nonatomic, strong) NSButton *finderBtn;
@property (nonatomic, copy) void (^onToggleCheck)(BOOL checked);
@property (nonatomic, copy) void (^onRevealFinder)(void);
@end

@implementation LMProjectPurgeCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _checkBox = [LMModernToolBaseWindowController checkboxWithMixed:NO
                                                                 target:self
                                                                 action:@selector(_handleCheck:)];
        [self addSubview:_checkBox];

        _folderIconView = [[NSImageView alloc] init];
        _folderIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_folderIconView];

        _titleLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                 font:[NSFontHelper getRegularSystemFont:13.5]
                                                                color:[LMAppThemeHelper getTitleColor]];
        [self addSubview:_titleLabel];

        _pathLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                                font:[NSFontHelper getLightSystemFont:11.5]
                                                               color:[NSColor colorWithHex:0x989A9E]];
        _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_pathLabel];

        _ecoPill = [[LMToolPillBadgeView alloc] init];
        [self addSubview:_ecoPill];

        _ageLabel = [LMModernToolBaseWindowController labelWithText:@""
                                                               font:[NSFontHelper getLightSystemFont:12]
                                                              color:[NSColor colorWithHex:0x94979B]];
        _ageLabel.alignment = NSTextAlignmentCenter;
        [self addSubview:_ageLabel];

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

        [_folderIconView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_checkBox.mas_right).offset(14);
            make.centerY.equalTo(self);
            make.width.height.mas_equalTo(28);
        }];

        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_folderIconView.mas_right).offset(12);
            make.top.equalTo(self).offset(11);
            make.right.lessThanOrEqualTo(_ecoPill.mas_left).offset(-14);
        }];

        [_pathLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(_titleLabel);
            make.top.equalTo(_titleLabel.mas_bottom).offset(2);
            make.right.lessThanOrEqualTo(_ecoPill.mas_left).offset(-14);
        }];

        [_ecoPill mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(422);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(76);
            make.height.mas_equalTo(20);
        }];

        [_ageLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.equalTo(self).offset(516);
            make.centerY.equalTo(self);
            make.width.mas_equalTo(78);
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

@interface LMProjectPurgeWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) LMProjectPurgeScanner *scanner;
@property (nonatomic, strong) NSMutableArray<NSString *> *scanDirs;
@property (nonatomic, strong) NSArray<LMProjectPurgeItem *> *allItems;
@property (nonatomic, strong) NSArray<LMProjectPurgeItem *> *filteredItems;
@property (nonatomic, assign) LMProjectEcosystem activeFilter;
@property (nonatomic, copy) NSString *searchKeyword;
@property (nonatomic, assign) LMProjectSortField sortField;
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, assign) BOOL permanentDeleteMode;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, assign) BOOL isCleaning;

@property (nonatomic, strong) LMBorderButton *addDirButton;
@property (nonatomic, strong) LMBorderButton *resetDirButton;
@property (nonatomic, strong) LMBorderButton *rescanButton;
@property (nonatomic, strong) NSSearchField *searchField;

@property (nonatomic, strong) LMToolFilterBarView *filterBar;
@property (nonatomic, strong) NSButton *sortTimeButton;
@property (nonatomic, strong) NSButton *sortSizeButton;

@property (nonatomic, strong) LMToolClickableTableView *tableView;
@property (nonatomic, strong) LMToolStatusOverlayView *statusOverlay;

@property (nonatomic, strong) NSView *bottomDivider;
@property (nonatomic, strong) LMCheckboxButton *selectAllCheck;
@property (nonatomic, strong) NSButton *selectAllTitleBtn;
@property (nonatomic, strong) LMBorderButton *selectIdleBtn;
@property (nonatomic, strong) LMBorderButton *cleanModeBtn;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) LMRectangleButton *cleanButton;

@end

@implementation LMProjectPurgeWindowController

- (instancetype)init {
    self = [super initWithToolTitle:LMToolLocalized(@"项目构建清理", @"Project Purge")
                         windowSize:NSMakeSize(780, 482)];
    return self;
}

- (void)setupToolContentView {
    self.scanner = [[LMProjectPurgeScanner alloc] init];
    self.scanDirs = [[LMProjectPurgeScanner configuredScanDirectories] mutableCopy];
    self.allItems = @[];
    self.filteredItems = @[];
    self.activeFilter = LMProjectEcosystemAll;
    self.searchKeyword = @"";
    self.sortField = LMProjectSortFieldSize;
    self.sortAscending = NO;
    self.permanentDeleteMode = NO;

    [self _setupTopRightAccessories];

    NSView *body = self.bodyContentView;

    // 40pt 极简文字筛选栏 + 右侧列头
    NSArray<NSString *> *tabs = @[
        LMToolLocalized(@"全部", @"All"),
        @"Node.js",
        @"Rust / Go",
        @"Python",
        @"Xcode / JVM",
        LMToolLocalized(@"其他", @"Other")
    ];
    LMToolFilterBarView *fBar = [[LMToolFilterBarView alloc] initWithTitles:tabs];
    __weak typeof(self) weakSelf = self;
    fBar.onSelectTab = ^(NSInteger index) {
        weakSelf.activeFilter = (LMProjectEcosystem)index;
        [weakSelf _applyFilterAndReload];
    };
    [body addSubview:fBar];
    self.filterBar = fBar;

    [fBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(body);
        make.height.mas_equalTo(40);
    }];

    NSButton *timeSortBtn = [LMModernToolBaseWindowController sortableColumnButtonWithTitle:LMToolLocalized(@"状态", @"Age")
                                                                                  alignment:NSTextAlignmentCenter
                                                                                     target:self
                                                                                     action:@selector(_onToggleSortTime:)];
    [fBar addSubview:timeSortBtn];
    self.sortTimeButton = timeSortBtn;
    [timeSortBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(fBar).offset(516);
        make.centerY.equalTo(fBar);
        make.width.mas_equalTo(78);
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
    self.bottomDivider = bLine;
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
    self.selectAllTitleBtn = allLabelBtn;

    self.selectIdleBtn = [LMModernToolBaseWindowController ghostButtonWithTitle:LMToolLocalized(@"仅选闲置", @"Idle Only")
                                                                       fontSize:12
                                                                         target:self
                                                                         action:@selector(_onSelectIdleOnly:)];
    [bottomBar addSubview:self.selectIdleBtn];

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

    [self.selectIdleBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(allLabelBtn.mas_right).offset(14);
        make.centerY.equalTo(bottomBar);
        make.width.mas_equalTo(68);
        make.height.mas_equalTo(24);
    }];

    [self.cleanModeBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.selectIdleBtn.mas_right).offset(8);
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

    // 中间列表区域
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

    [self _updateDirButtonsVisibility];
    [self _startScanning];
}

- (void)_setupTopRightAccessories {
    NSView *right = self.headerRightContainer;

    self.searchField = [LMModernToolBaseWindowController searchFieldWithPlaceholder:LMToolLocalized(@"搜索项目", @"Search")
                                                                             target:self
                                                                             action:@selector(_onSearchChanged:)];
    [right addSubview:self.searchField];

    self.rescanButton = [LMModernToolBaseWindowController ghostButtonWithTitle:LMToolLocalized(@"刷新", @"Refresh")
                                                                      fontSize:11
                                                                        target:self
                                                                        action:@selector(_onRescan:)];
    [right addSubview:self.rescanButton];

    self.addDirButton = [LMModernToolBaseWindowController ghostButtonWithTitle:LMToolLocalized(@"添加目录", @"Add Folder")
                                                                      fontSize:11
                                                                        target:self
                                                                        action:@selector(_onAddDirectory:)];
    [right addSubview:self.addDirButton];

    self.resetDirButton = [LMModernToolBaseWindowController ghostButtonWithTitle:LMToolLocalized(@"重置", @"Reset")
                                                                        fontSize:11
                                                                          target:self
                                                                          action:@selector(_onResetDirectories:)];
    [right addSubview:self.resetDirButton];

    [self.searchField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(right);
        make.centerY.equalTo(right);
        make.width.mas_equalTo(124);
        make.height.mas_equalTo(22);
    }];

    [self.rescanButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.searchField.mas_left).offset(-8);
        make.centerY.equalTo(right);
        make.width.mas_equalTo(44);
        make.height.mas_equalTo(22);
    }];

    [self.addDirButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.rescanButton.mas_left).offset(-6);
        make.centerY.equalTo(right);
        make.width.mas_equalTo(64);
        make.height.mas_equalTo(22);
    }];

    [self.resetDirButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.addDirButton.mas_left).offset(-6);
        make.centerY.equalTo(right);
        make.width.mas_equalTo(44);
        make.height.mas_equalTo(22);
        make.left.equalTo(right);
    }];
}

- (void)_updateDirButtonsVisibility {
    NSArray<NSString *> *defaults = [LMProjectPurgeScanner defaultScanDirectories];
    BOOL isCustom = ![self.scanDirs isEqualToArray:defaults];
    self.resetDirButton.hidden = !isCustom;
}

- (void)toolWindowWillClose {
    [self.scanner cancelScan];
}

#pragma mark - Scanning

- (void)_startScanning {
    if (self.isScanning || self.isCleaning) {
        return;
    }
    self.isScanning = YES;
    self.cleanButton.enabled = NO;
    self.rescanButton.enabled = NO;
    self.addDirButton.enabled = NO;
    [self.statusOverlay showLoadingWithTitle:LMToolLocalized(@"正在扫描构建产物...", @"Scanning build artifacts...")];

    __weak typeof(self) weakSelf = self;
    [self.scanner startScanWithDirectories:[self.scanDirs copy]
                                  progress:^(NSString *currentPath, NSUInteger discoveredCount) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *msg = (discoveredCount > 0)
            ? [NSString stringWithFormat:LMToolLocalized(@"已发现 %lu 项...", @"Found %lu items..."), (unsigned long)discoveredCount]
            : LMToolLocalized(@"正在扫描构建产物...", @"Scanning build artifacts...");
        [strongSelf.statusOverlay showLoadingWithTitle:msg];
    } completion:^(NSArray<LMProjectPurgeItem *> *items, BOOL cancelled) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isScanning = NO;
        strongSelf.rescanButton.enabled = YES;
        strongSelf.addDirButton.enabled = YES;
        if (!cancelled) {
            strongSelf.allItems = items ?: @[];
            [strongSelf _applyFilterAndReload];
        }
    }];
}

- (void)_applyFilterAndReload {
    NSMutableArray<LMProjectPurgeItem *> *matched = [NSMutableArray array];
    NSString *kw = [self.searchKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    NSUInteger i;
    for (i = 0; i < self.allItems.count; i++) {
        LMProjectPurgeItem *item = self.allItems[i];
        if (self.activeFilter != LMProjectEcosystemAll && item.ecosystem != self.activeFilter) {
            continue;
        }
        if (kw.length > 0) {
            NSString *pName = (item.projectName ?: @"").lowercaseString;
            NSString *aName = (item.artifactName ?: @"").lowercaseString;
            NSString *aPath = (item.artifactPath ?: @"").lowercaseString;
            if (![pName containsString:kw] && ![aName containsString:kw] && ![aPath containsString:kw]) {
                continue;
            }
        }
        [matched addObject:item];
    }

    LMProjectSortField field = self.sortField;
    BOOL asc = self.sortAscending;
    [matched sortUsingComparator:^NSComparisonResult(LMProjectPurgeItem *a, LMProjectPurgeItem *b) {
        NSComparisonResult res = NSOrderedSame;
        if (field == LMProjectSortFieldTime) {
            if (a.daysSinceActive != b.daysSinceActive) {
                res = (a.daysSinceActive < b.daysSinceActive) ? NSOrderedAscending : NSOrderedDescending;
            }
        } else {
            if (a.sizeInBytes != b.sizeInBytes) {
                res = (a.sizeInBytes < b.sizeInBytes) ? NSOrderedAscending : NSOrderedDescending;
            }
        }
        if (res == NSOrderedSame) {
            res = [a.projectName localizedCaseInsensitiveCompare:b.projectName];
        }
        return asc ? res : -res;
    }];

    self.filteredItems = matched;
    [self.tableView reloadData];

    if (!self.isScanning) {
        if (self.filteredItems.count == 0) {
            NSString *emptyMsg = (self.allItems.count == 0)
                ? LMToolLocalized(@"很干净，未发现冗余项目构建产物", @"Clean — no build artifacts found")
                : LMToolLocalized(@"当前筛选条件下暂无项目", @"No matching items");
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
        LMProjectPurgeItem *it = self.allItems[i];
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
            summaryAttributedWithPrefix:LMToolLocalized(@"未选择项目", @"None selected")
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

#pragma mark - Sorting & Filtering Actions

- (void)_refreshSortColumnHeaders {
    [LMModernToolBaseWindowController styleSortableColumnButton:self.sortTimeButton
                                                          title:LMToolLocalized(@"状态", @"Age")
                                                         active:(self.sortField == LMProjectSortFieldTime)
                                                      ascending:self.sortAscending
                                                      alignment:NSTextAlignmentCenter];
    [LMModernToolBaseWindowController styleSortableColumnButton:self.sortSizeButton
                                                          title:LMToolLocalized(@"大小", @"Size")
                                                         active:(self.sortField == LMProjectSortFieldSize)
                                                      ascending:self.sortAscending
                                                      alignment:NSTextAlignmentRight];
}

- (void)_onToggleSortTime:(id)sender {
    if (self.sortField == LMProjectSortFieldTime) {
        self.sortAscending = !self.sortAscending;
    } else {
        self.sortField = LMProjectSortFieldTime;
        self.sortAscending = NO;
    }
    [self _refreshSortColumnHeaders];
    [self _applyFilterAndReload];
}

- (void)_onToggleSortSize:(id)sender {
    if (self.sortField == LMProjectSortFieldSize) {
        self.sortAscending = !self.sortAscending;
    } else {
        self.sortField = LMProjectSortFieldSize;
        self.sortAscending = NO;
    }
    [self _refreshSortColumnHeaders];
    [self _applyFilterAndReload];
}

- (void)_onSearchChanged:(NSSearchField *)sender {
    self.searchKeyword = sender.stringValue ?: @"";
    [self _applyFilterAndReload];
}

#pragma mark - User Actions

- (void)_onAddDirectory:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = YES;
    panel.prompt = LMToolLocalized(@"添加", @"Add");
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            BOOL added = NO;
            NSUInteger i;
            for (i = 0; i < panel.URLs.count; i++) {
                NSString *p = panel.URLs[i].path;
                if (p.length > 0 && ![strongSelf.scanDirs containsObject:p]) {
                    [strongSelf.scanDirs addObject:p];
                    added = YES;
                }
            }
            if (added) {
                [LMProjectPurgeScanner saveConfiguredScanDirectories:strongSelf.scanDirs];
                [strongSelf _updateDirButtonsVisibility];
                [strongSelf _startScanning];
            }
        }
    }];
}

- (void)_onResetDirectories:(id)sender {
    self.scanDirs = [[LMProjectPurgeScanner defaultScanDirectories] mutableCopy];
    [LMProjectPurgeScanner saveConfiguredScanDirectories:self.scanDirs];
    [self _updateDirButtonsVisibility];
    [self _startScanning];
}

- (void)_onRescan:(id)sender {
    [self _startScanning];
}

- (void)_toggleRowAtIndex:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.filteredItems.count) {
        return;
    }
    LMProjectPurgeItem *item = self.filteredItems[(NSUInteger)row];
    item.isSelected = !item.isSelected;
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                              columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [self _refreshSummaryBar];
}

- (void)_revealRowAtIndex:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.filteredItems.count) {
        return;
    }
    LMProjectPurgeItem *item = self.filteredItems[(NSUInteger)row];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:item.artifactPath]]];
}

- (void)_onToggleSelectAllCheck:(LMCheckboxButton *)sender {
    BOOL targetState = (sender.state == NSControlStateValueOn);
    NSUInteger i;
    for (i = 0; i < self.filteredItems.count; i++) {
        self.filteredItems[i].isSelected = targetState;
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
    BOOL next = !allChecked;
    for (i = 0; i < self.filteredItems.count; i++) {
        self.filteredItems[i].isSelected = next;
    }
    [self.tableView reloadData];
    [self _refreshSummaryBar];
}

- (void)_onSelectIdleOnly:(id)sender {
    NSUInteger i;
    for (i = 0; i < self.allItems.count; i++) {
        LMProjectPurgeItem *it = self.allItems[i];
        it.isSelected = !it.isRecent;
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
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"CleanMode"];
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
    NSMutableArray<LMProjectPurgeItem *> *targets = [NSMutableArray array];
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
        ? LMToolLocalized(@"确认永久删除所选构建产物？", @"Permanently delete selected artifacts?")
        : LMToolLocalized(@"确认将所选构建产物移入废纸篓？", @"Move selected artifacts to Trash?");
    alert.informativeText = [NSString stringWithFormat:LMToolLocalized(@"共 %lu 项（%@），项目源码不受影响。",
                                                                       @"%lu items (%@). Source code remains untouched."),
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

- (void)_executeCleanOnTargets:(NSArray<LMProjectPurgeItem *> *)targets permanent:(BOOL)permanent {
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
                NSString *path = targets[i].artifactPath;
                if ([fm removeItemAtPath:path error:nil]) {
                    [cleanedPaths addObject:path];
                }
            }
        } else {
            NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:targets.count];
            NSUInteger i;
            for (i = 0; i < targets.count; i++) {
                [urls addObject:[NSURL fileURLWithPath:targets[i].artifactPath]];
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

            NSMutableArray<LMProjectPurgeItem *> *remaining = [NSMutableArray array];
            NSUInteger i;
            for (i = 0; i < strongSelf.allItems.count; i++) {
                LMProjectPurgeItem *it = strongSelf.allItems[i];
                if (![cleanedPaths containsObject:it.artifactPath]) {
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
    LMProjectPurgeItem *item = self.filteredItems[(NSUInteger)row];
    LMProjectPurgeCellView *cell = [tableView makeViewWithIdentifier:@"PurgeCell" owner:nil];
    if (!cell) {
        cell = [[LMProjectPurgeCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 58)];
        cell.identifier = @"PurgeCell";
    }

    cell.checkBox.state = item.isSelected ? NSControlStateValueOn : NSControlStateValueOff;
    cell.folderIconView.image = [[NSWorkspace sharedWorkspace] iconForFile:item.artifactPath];
    cell.titleLabel.stringValue = [NSString stringWithFormat:@"%@ / %@", item.projectName ?: @"", item.artifactName ?: @""];
    cell.titleLabel.textColor = [LMAppThemeHelper getTitleColor];
    cell.pathLabel.stringValue = [(item.projectRootPath ?: item.artifactPath) stringByAbbreviatingWithTildeInPath];
    cell.sizeLabel.stringValue = LMFormatByteCount(item.sizeInBytes);
    cell.sizeLabel.textColor = [LMAppThemeHelper getTitleColor];

    LMToolPillTone tone = LMToolPillToneNeutral;
    switch (item.ecosystem) {
        case LMProjectEcosystemNode:
            tone = LMToolPillToneMint;
            break;
        case LMProjectEcosystemRustGo:
            tone = LMToolPillToneAmber;
            break;
        case LMProjectEcosystemPython:
        case LMProjectEcosystemAppleJVM:
            tone = LMToolPillToneBlue;
            break;
        default:
            tone = LMToolPillToneNeutral;
            break;
    }
    [cell.ecoPill configureWithText:(item.ecosystemTag ?: @"Build") tone:tone];

    if (item.isRecent) {
        cell.ageLabel.stringValue = LMToolLocalized(@"近期活跃", @"Active");
        cell.ageLabel.textColor = [NSColor colorWithHex:0xFF9A00];
    } else if (item.daysSinceActive <= 0) {
        cell.ageLabel.stringValue = LMToolLocalized(@"今天", @"Today");
        cell.ageLabel.textColor = [NSColor colorWithHex:0x94979B];
    } else {
        cell.ageLabel.stringValue = [NSString stringWithFormat:LMToolLocalized(@"%ld 天前", @"%ldd ago"), (long)item.daysSinceActive];
        cell.ageLabel.textColor = [NSColor colorWithHex:0x94979B];
    }

    cell.finderBtn.hidden = YES;

    __weak typeof(self) weakSelf = self;
    cell.onToggleCheck = ^(BOOL checked) {
        item.isSelected = checked;
        [weakSelf _refreshSummaryBar];
    };
    cell.onRevealFinder = ^{
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:item.artifactPath]]];
    };

    return cell;
}

@end
