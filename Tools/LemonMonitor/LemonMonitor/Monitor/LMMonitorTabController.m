//
//  MainTabController.m
//  LemonMonitor
//

//  Copyright © 2019年 Tencent. All rights reserved.
//

#import "LMMonitorTabController.h"
#import "LMBaseLineSegmentedControl.h"
#include <sys/stat.h>
#import <QMUICommon/LMViewHelper.h>
#import <Masonry/Masonry.h>
#import <QMUICommon/LMOpenButton.h>
#import "QMDataConst.h"
#import "LemonDaemonConst.h"
#import "McStatInfoConst.h"
#import <QMUICommon/NSFontHelper.h>
#import <QMUICommon/QMBubble.h>
#import <QMCoreFunction/NSString+Extension.h>
#import <QMCoreFunction/LanguageHelper.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/SharedPrefrenceManager.h>
#import <QMUICommon/LMCommonHelper.h>
#import <QMUICommon/QMButton.h>
#import "AppDelegate.h"
#import "LMAboutWindow.h"
#import <LemonFileManager/NSObject+LMDataCheck.h>
#import <PrivacyProtect/PrivacyProtect.h>
#import <QMCoreFunction/QMCoreFunctionDef.h>

#define MONITOR_OPNE_LEMON_505      @"MONITOR_OPNE_LEMON_505" // 505活动入口标记

#define NORMAL_VIEW_HEIGHT      500

static const CGFloat kTopPadding = 10;


@interface LMMonitorTabController ()
{
    NSArray *_viewControllers;
    
    NSButton* launchSettingsBtn;
    NSBundle *myBundle;
    BOOL bNeedUpdate;
    NSImageView* mUpdateRedpointForSettings;
    LMSettingsViewController* _settingsViewController;
    QMBubble* _settingsBubble;
    NSView *bottomContainerView;
    
    id statusMonitorGlobal;
    id statusMonitorLocal;
    NSWindowController* _aboutWC;
}
@property (strong, nonatomic) NSTabViewItem *currentItem;
@property(weak)  NSView *divisionLineView;;
@property(nonatomic, assign) long timerNum;
@property(nonatomic, strong) QMButton *happyBirthBtn; // 三周年入口按钮
@property(nonatomic, strong) NSTimer *happyBirTimer; // 三周年动画定时器
@property(nonatomic, strong) NSString *currentGuid; // 当前用户guid
@property(nonatomic, strong) NSImageView *finishImageView;  //活动提醒红点
@property(nonatomic, strong) NSImageView *backImageView;
@property(nonatomic, strong) NSImageView *signImageView;

@end


@implementation LMMonitorTabController



- (instancetype)initWithControllers:(NSArray *)controllers titles:(NSArray *)titles
{
    if(controllers == nil || titles == nil || [controllers count] != [titles count]){
        NSLog(@"tabViewController controllers and titile must not be null and size must be equal");
        [NSException raise:@"MonitorTabControllerInitError" format:@"tabViewController controllers and titile must not be null and size must be equal"];
    }
    self = [self initWithNibName:NULL bundle:NULL];
    if (self) {
        _viewControllers = controllers;
        if (controllers.count > 0) {
            NSMutableArray *items = [NSMutableArray arrayWithCapacity:controllers.count];
            [_viewControllers enumerateObjectsUsingBlock:^(NSViewController *controller, NSUInteger idx, BOOL *stop) {
                NSString *title = titles[idx];
                NSString *identifier = [NSString stringWithFormat:@"%lu-%@[%p]", (unsigned long)idx, title, controller];
                NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:identifier];
                item.view = controller.view;
                item.label = title;
                [items addObject:item];
            }];
            self.tabItems = items;
            _tabIndex = 0;
        
        }
    }
    
    myBundle = [NSBundle bundleForClass:[self class]];

    return self;
}

- (void)dealloc
{
    if (_viewControllers.count > 0) {
        [self.segmentedControl unbind:@"selectedSegment"];
    }
}

- (void)loadView
{
    NSRect rect = NSMakeRect(0, 0, 340, NORMAL_VIEW_HEIGHT); //不包括箭头
    if ([[Owl2Manager sharedManager] guideViewShowType] != OWLShowGuideViewType_None) {
        // 展示隐私保护‘一键开启’引导视图
        rect.size.height += 54;
    }
    NSView *view = [[NSView alloc] initWithFrame:rect];
    self.view = view;
    view.wantsLayer = YES;
//    view.layer.backgroundColor = [NSColor whiteColor].CGColor;
    if ([LMCommonHelper isMacOS11]) {
        view.layer.cornerRadius = 10;
    } else {
        view.layer.cornerRadius = 5;
    }
    view.layer.masksToBounds = YES;
//    [self viewDidLoad];  // 这里不需要调用了 在调用 _tabViewController.view时会调用一次viewDidLoad.
}

- (void)setupSegment {
    NSView *divisionLineView = [[NSView alloc]init];
//    divisionLineView.wantsLayer = YES;
//    divisionLineView.layer.backgroundColor = [NSColor colorWithHex:0xF1F1F1].CGColor;
    self.divisionLineView = divisionLineView;
    [self.view addSubview:self.divisionLineView];
    
    _segmentedControl = [[LMBaseLineSegmentedControl alloc] init]; // 22px height
    [self.view addSubview:_segmentedControl];

    _segmentedControl.focusRingType = NSFocusRingTypeNone;
    [_segmentedControl setFrameSize:NSMakeSize(184, 43)];
    _segmentedControl.target = self;
    _segmentedControl.action = @selector(onClickSemgnetControl:);
    [_segmentedControl addObserver:self forKeyPath:@"selectedSegment" options:NSKeyValueObservingOptionNew context:NULL];
    [self.segmentedControl bind:@"selectedSegment" toObject:self withKeyPath:@"tabIndex" options:nil];
    NSSegmentedControl *segmentedControl = self.segmentedControl;
   
    [_segmentedControl setSegmentCount:_tabItems.count];
    CGFloat width = segmentedControl.frame.size.width / _viewControllers.count;
    [_tabItems enumerateObjectsUsingBlock:^(NSTabViewItem *item, NSUInteger idx, BOOL *stop) {
        //        [_segmentedControl setLabel:objc_msgSend(item, @selector(label)) forSegment:idx];  // obj msg_send 奇怪的方法.
        [_segmentedControl setLabel:item.label forSegment:idx];
        [_segmentedControl setWidth:width forSegment:idx];

        // 系统功能页要加红点
        if ([item.label isEqualToString:NSLocalizedString(@"系统功能", nil)]) {
            NSDictionary *dict = @{item.label: @"kLemonMonitorDidClickedSystemFunctionTabForAutomatic"};
            [(LMBaseLineSegmentedControl *)_segmentedControl updateRedPointInfo:dict];
        }
    }];
    
    if (self.tabItems.count > 0) {
        self.currentItem = self.tabItems[0];
    }
 
    
    [_segmentedControl mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.equalTo(@184);
        make.height.equalTo(@43);
        make.left.equalTo(self.view).offset(12);
        make.top.equalTo(self.view);
    }];
    
    [divisionLineView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.left.equalTo(self.view);
        make.height.equalTo(@1);
        make.top.equalTo(_segmentedControl.mas_bottom).offset(0);
    }];
    
}

- (void)viewWillLayout{
    [super viewWillLayout];
    [LMAppThemeHelper setDivideLineColorFor:self.divisionLineView];
    bottomContainerView.layer.backgroundColor = [LMAppThemeHelper getMonitorTabBottomBgColor].CGColor;
}

// viewDidLoad 可能被多次调用的原因:loadView 手动调用了一次, 调用_tabViewController.view时有调用了一次
- (void)viewDidLoad{
    [self setupSegment];
    [self setupLauncherView];
    
    
    // 监控更新
    [[NSNotificationCenter defaultCenter] addObserver:self
                                selector:@selector(receivedVersionUpdateNotification:)
                                            name:@"LemonHasNewVersion"
                                               object:nil];
    [[LMGitHubUpdater sharedUpdater] startPeriodicCheck];
    
    // 关于窗口
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                selector:@selector(receiveAboutOpenNotification:)
                                                     name:@"open_about"
                                                    object:nil];
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    
    // owl 引导试图显示和不显示window的高度要动态调整
    [self __updateWindowFrameWithShowOwlGuideState];

    [[LMGitHubUpdater sharedUpdater] checkForUpdatesWithManualTrigger:NO];

    if (mUpdateRedpointForSettings != nil)
    {
        if ([self CheckVersionUpdate])
        {
            mUpdateRedpointForSettings.hidden = false;
        }
        else
        {
            mUpdateRedpointForSettings.hidden = true;
        }
    }
    
}

- (void)__updateWindowFrameWithShowOwlGuideState {
    float currentViewH = self.view.frame.size.height;
    
    NSRect normalViewFrame = NSMakeRect(0, 0, 340, NORMAL_VIEW_HEIGHT); //不包括箭头
    if ([[Owl2Manager sharedManager] guideViewShowType] != OWLShowGuideViewType_None) {
        // 展示隐私保护‘一键开启’引导视图
        normalViewFrame.size.height += 54;
    }
    float newHeight = normalViewFrame.size.height;
    self.view.frame = normalViewFrame;

    if (fabs(currentViewH - newHeight) > 10) {  // 有变化，窗口大小也要相应改变，至少相差54
        NSRect windowFrame = self.view.window.frame;
        float topLeftY = NSMaxY(windowFrame);
        windowFrame.size.height = normalViewFrame.size.height + 6;
        windowFrame.origin.y = topLeftY - windowFrame.size.height;  // 左上角固定
        [self.view.window setFrame:windowFrame display:YES];
    }

}

- (void)viewDidDisappear {
    [super viewDidDisappear];
    if(self.happyBirthBtn) {
        [self.happyBirthBtn removeFromSuperview];
    }
    if(self.finishImageView) {
        [self.finishImageView removeFromSuperview];
    }
    if(self.backImageView) {
        [self.backImageView removeFromSuperview];
    }
    self.currentGuid = @"";
}

- (void)viewDidAppear {
    [super viewDidAppear];
//    获取云配参数保留
//    CFPreferencesAppSynchronize((__bridge CFStringRef)(MAIN_APP_BUNDLEID));
//    CFBooleanRef kAnniActivityEnter = CFPreferencesCopyAppValue((__bridge CFStringRef)(@"kAnniActivityEnter"), (__bridge CFStringRef)(MAIN_APP_BUNDLEID));
//     bug:偶现读取不到数据
//    if (kAnniActivityEnter == NULL) {
//        return;
//    }
}

- (void) setupLauncherView
{
    bottomContainerView = [LMViewHelper createPureColorView:[LMAppThemeHelper getMonitorTabBottomBgColor]];
    [self.view addSubview:bottomContainerView];
    
    launchSettingsBtn = [LMViewHelper createNormalButton];
    launchSettingsBtn.image = [myBundle imageForResource:@"lemon_setting"];
    [self.view addSubview:launchSettingsBtn];
    launchSettingsBtn.target = self;
    launchSettingsBtn.action = @selector(onLaunchSettings);
    [launchSettingsBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(self.view.mas_left).offset(13);
        make.centerY.equalTo(bottomContainerView);
        make.width.equalTo(@32);
        make.height.equalTo(@32);
    }];
    
    // redpoint for update
    NSImageView* updateRedpoint  = [[NSImageView alloc] init];
    [updateRedpoint setImage:[myBundle  imageForResource:@"redpoint2"]];
    [self.view addSubview:updateRedpoint];
    [updateRedpoint mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(launchSettingsBtn.mas_left).offset(20);
        make.bottom.mas_equalTo(launchSettingsBtn.mas_top).offset(8);
        make.width.equalTo(@6);
        make.height.equalTo(@6);
    }];
    
    if ([self CheckVersionUpdate])
    {
        updateRedpoint.hidden = false;
    }
    else
    {
        updateRedpoint.hidden = true;
    }
    
    mUpdateRedpointForSettings = updateRedpoint;
    
    // launch cleaner
    LMOpenButton *launchLemonBtn = [[LMOpenButton alloc] init];
    [launchLemonBtn setFont:[NSFontHelper getRegularSystemFont:12]];
    launchLemonBtn.title = NSLocalizedString(@"打开 cleaner", nil);
    launchLemonBtn.target = self;
    launchLemonBtn.action = @selector(onLaunchLemon);
    [self.view addSubview:launchLemonBtn];
    [launchLemonBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.mas_equalTo(self.view.mas_centerX);
        make.centerY.equalTo(bottomContainerView);
        make.width.equalTo(@130);
        make.height.equalTo(@28);
    }];
    
    NSImageView *signImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 6, 6)];
    NSImage *image = [NSImage imageNamed:@"Ellipse" withClass:self.class];
    signImageView.image = image;
    self.signImageView = signImageView;
    [launchLemonBtn addSubview:signImageView];
    [signImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(launchLemonBtn);
        make.left.equalTo(launchLemonBtn.mas_left).offset(20);
    }];
    self.signImageView.hidden = YES;
    
    // 右下角 GitHub 仓库入口按钮
    NSButton* launchFeebBackBtn = [LMViewHelper createNormalButton];
    launchFeebBackBtn.image = [myBundle imageForResource:@"lemon_feedback"];
    launchFeebBackBtn.toolTip = @"GitHub";
    launchFeebBackBtn.target = self;
    launchFeebBackBtn.action = @selector(onLaunchFeebBack);
    [launchFeebBackBtn setBordered:NO];
    [self.view addSubview:launchFeebBackBtn];
    [launchFeebBackBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.mas_equalTo(self.view).offset(-13);
        make.centerY.equalTo(bottomContainerView);
        make.width.equalTo(@32);
        make.height.equalTo(@32);
    }];
    
    [bottomContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.left.equalTo(self.view);
        make.height.equalTo(@50);
        make.bottom.equalTo(self.view);
    }];
}



- (NSViewController *)selectedController
{
    if (_viewControllers.count == 0) return nil;
    return _viewControllers[self.tabIndex];
}

- (void)setSelectedController:(NSViewController *)controller
{
    NSInteger idx = [_viewControllers indexOfObject:controller];
    if (idx != NSNotFound) {
        self.tabIndex = idx;
    }
}



#pragma mark - Action Responder
- (void)onClickSemgnetControl:(NSSegmentedControl *)sender
{
    if (_currentItem == [self _selectedItem]) return;
    self.currentItem = [self _selectedItem];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _segmentedControl && [keyPath isEqualToString:@"selectedSegment"]) {
        [self onClickSemgnetControl:object];
    }
}

#pragma mark - Private Methods
- (NSTabViewItem *)_selectedItem
{
    if (self.tabItems.count == 0) return nil;
    if (_segmentedControl.selectedSegment < 0 || _segmentedControl.selectedSegment >= self.tabItems.count) return nil;
    return self.tabItems[_segmentedControl.selectedSegment];
}

- (void)_configViewByTabItems
{
    [_segmentedControl setSegmentCount:_tabItems.count];
    [_tabItems enumerateObjectsUsingBlock:^(NSTabViewItem *item, NSUInteger idx, BOOL *stop) {
//        [_segmentedControl setLabel:objc_msgSend(item, @selector(label)) forSegment:idx];  // obj msg_send 奇怪的方法.
         [_segmentedControl setLabel:item.label forSegment:idx];
    }];
    if (_tabItems.count > 0) {
        _segmentedControl.selectedSegment = 0;
    }
    //    [_segmentedControl sizeToFit];
    [_segmentedControl setFrameOrigin:NSMakePoint((NSWidth(self.view.bounds) - NSWidth(_segmentedControl.frame)) / 2, NSHeight(self.view.bounds) - NSHeight(_segmentedControl.frame) - kTopPadding)];
}

- (void)setCurrentItem:(NSTabViewItem *)item
{
    if (_currentItem) {
        [_currentItem.view removeFromSuperview];
    }
    [self.view addSubview:item.view];
    [item.view mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.left.equalTo(self.view);
        make.top.equalTo(self.view).offset(44);
        make.bottom.equalTo(self.view).offset(-50);
    }];
    _currentItem = item;
}


#pragma mark - Getters



-(void)receiveAboutOpenNotification:(NSNotification *)notification
{
    [self rightAboutAction:nil];
}


-(void)receivedVersionUpdateNotification:(NSNotification *)notification
{
    bNeedUpdate = [self CheckVersionUpdate];
    if (mUpdateRedpointForSettings != nil) {
        mUpdateRedpointForSettings.hidden = !bNeedUpdate;
    }
}


-(BOOL)CheckVersionUpdate
{
    BOOL hasRemoteUpdate = [LMGitHubUpdater sharedUpdater].hasUpdate;
    bNeedUpdate = hasRemoteUpdate;
    return bNeedUpdate;
}



-(void) onLaunchSettings
{
    NSLog(@"onLaunchSettings enter.");
        
    if (false) {
        
        //    if (!settingsPopover) {
        //        //用于显示弹窗
        //        settingsPopover = [[QMMonitorPopover alloc] init];
        //        settingsPopover.floatWindow = self.view.window;
        //        settingsPopover.statusView = nil;
        //        settingsPopover.dismissCompletion = nil;
        //    }
        //
        //    [settingsPopover showPopover];
        _settingsViewController = [[LMSettingsViewController alloc] init];
        _settingsBubble = [[QMBubble alloc] init];
        _settingsBubble.distance = 30;
        _settingsBubble.direction = QMArrowCornerTopRight;
        _settingsBubble.keyWindow = YES;
        _settingsBubble.draggable = YES;
        [_settingsBubble setCornerRadius:2.0];
        //    [_settingsBubble setDrawArrow:NO];
        //    [_settingsBubble setArrowHeight:160.0];
        //    [_settingsBubble setArrowWidth:100.0];
        //    [_settingsBubble setArrowDistance:30];
        [_settingsBubble setBorderColor:[NSColor clearColor]];
        [_settingsBubble setContentView:_settingsViewController.view];
        
        //    _settingsBubble.arrowDistance = 100;
        //    _settingsBubble.arrowOffset = 0;
        _settingsBubble.titleMode = QMBubbleTitleModeArrow; //QMBubbleTitleModeTitleBar;
        if (_settingsBubble.isVisible && !_settingsBubble.attachedToParentWindow)
            return;
        //    convertPointToScreen:[NSEvent mouseLocation]
        //显示的参照点
        //    NSRect statusRect = [self.view convertRect:self.view.bounds toView:nil];
        //    statusRect = [self.view.window convertRectToScreen:statusRect];
        //    NSPoint showPoint = NSMakePoint(NSMidX(statusRect), NSMinY(statusRect));
        NSPoint showPoint;
//        NSPoint settingsBtnLoc = launchSettingsBtn.frame.origin;
        NSRect pointOnScreen = [[launchSettingsBtn window] convertRectToScreen:launchSettingsBtn.frame];
        showPoint = pointOnScreen.origin;
        [_settingsBubble showToPoint:showPoint ofWindow:nil];
        
        void (^handler)(NSEvent *) = ^void(NSEvent *event){
            //        QMFullViewController *sself = settings;
            NSRect frame = _settingsViewController.view.window.frame;
//            NSPoint point = [NSEvent mouseLocationInView:_settingsViewController.view];
            
            if (NSPointInRect([NSEvent mouseLocation], NSInsetRect(frame, -2, -2)))
            {
                return;
            }
            [_settingsBubble dismiss];
        };
        
        if (!statusMonitorGlobal) {
            statusMonitorGlobal = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:handler];
        }
        if (!statusMonitorLocal) {
            statusMonitorLocal = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
                handler(event);
                return event;
            }];
        }
        
        return;
    }
    
    
    // check version update
    bNeedUpdate = [self CheckVersionUpdate];
    
    // UI
    NSMenu* rightClickMenu = [[NSMenu alloc] init];
    NSMenuItem *itemUpdate = nil;
    if (bNeedUpdate && [LMGitHubUpdater sharedUpdater].latestVersion.length > 0) {
        NSString *updateTitle = [NSString stringWithFormat:@"发现新版本 v%@（点击热更）", [LMGitHubUpdater sharedUpdater].latestVersion];
        itemUpdate = [[NSMenuItem alloc] initWithTitle:updateTitle
                                                action:@selector(onRightUpdateAction:)
                                         keyEquivalent:@""];
        [itemUpdate setTarget:self];
    }

    NSMenuItem *itemCheckUpdate = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"检查更新...", @"")
                                                             action:@selector(onRightCheckUpdateAction:)
                                                      keyEquivalent:@""];
    [itemCheckUpdate setTarget:self];

    // 状态栏右键菜单统一品牌名称为 cleaner
    NSMenuItem *item1 = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(NSLocalizedString(@"关于 cleaner", nil),
                                                                            @"") action:@selector(rightAboutAction:) keyEquivalent:@""];
    NSMenuItem *item6 = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(NSLocalizedString(@"偏好设置", nil),
                                                                            @"") action:@selector(rightOpenPreference:) keyEquivalent:@""];
    NSMenuItem *item7 = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(NSLocalizedString(@"退出状态栏", nil),
                                                                            @"") action:@selector(rightQuitAction:) keyEquivalent:@""];
    if (bNeedUpdate) {
        if (itemUpdate) {
            itemUpdate.image = [myBundle imageForResource:@"redpoint"];
        }
        itemCheckUpdate.image = [myBundle imageForResource:@"redpoint_transparent"];
        item1.image = [myBundle imageForResource:@"redpoint_transparent"];
        item6.image = [myBundle imageForResource:@"redpoint_transparent"];
        item7.image = [myBundle imageForResource:@"redpoint_transparent"];
    }
    
    [item1 setTarget:self];
    [item6 setTarget:self];
    [item7 setTarget:self];

    if (itemUpdate) {
        [rightClickMenu addItem:[NSMenuItem separatorItem]];
        [rightClickMenu addItem:itemUpdate];
    }
    [rightClickMenu addItem:[NSMenuItem separatorItem]];
    [rightClickMenu addItem:itemCheckUpdate];
    [rightClickMenu addItem:[NSMenuItem separatorItem]];
    [rightClickMenu addItem:item1];
    [rightClickMenu addItem:[NSMenuItem separatorItem]];
    [rightClickMenu addItem:item6];
    [rightClickMenu addItem:[NSMenuItem separatorItem]];
    [rightClickMenu addItem:item7];
    
    id sender = launchSettingsBtn;
    NSRect frame = [(NSButton *)sender frame];
    NSPoint menuOrigin = [[(NSButton *)sender superview] convertPoint:NSMakePoint(frame.origin.x, frame.origin.y) toView:nil];
    
    NSEvent *event =  [NSEvent mouseEventWithType:NSLeftMouseDown
                                         location:menuOrigin
                                    modifierFlags:NSLeftMouseDownMask
                                        timestamp:0
                                     windowNumber:[[(NSButton *)sender window] windowNumber]
                                          context:[[(NSButton *)sender window] graphicsContext]
                                      eventNumber:0
                                       clickCount:1
                                         pressure:1];
    
    // contextMenu可以直接在XIB里初始化一个菜单
    NSMenu* contextMenu = rightClickMenu;
    [NSMenu popUpContextMenu:contextMenu withEvent:event forView:(NSButton *)sender];
}


- (void) onLaunchLemon
{
    NSLog(@"onLaunchLemon enter.");
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:MONITOR_OPNE_LEMON_505];
        
    [[NSWorkspace sharedWorkspace] launchApplication:DEFAULT_APP_PATH];
//    [[NSWorkspace sharedWorkspace] launchApplication:@"Calculator.app"];
    
    [self notifyDimissPopover];
}

- (void) onLaunchFeebBack
{
    NSURL *githubURL = [NSURL URLWithString:@"https://github.com/qg-hs/cleaner"];
    if (githubURL) {
        [[NSWorkspace sharedWorkspace] openURL:githubURL];
    }
    [self notifyDimissPopover];
}

- (void)notifyDimissPopover
{
    [[NSNotificationCenter defaultCenter] postNotificationName:QMPopoverDismiss object:nil];
}
-(void) onRightUpdateAction:(id)sender
{
    [self notifyDimissPopover];
    [[LMGitHubUpdater sharedUpdater] startHotUpdate];
}

-(void) onRightCheckUpdateAction:(id)sender
{
    [self notifyDimissPopover];
    [[LMGitHubUpdater sharedUpdater] checkForUpdatesWithManualTrigger:YES];
}

- (BOOL)hasNewVersion{
    return [LMGitHubUpdater sharedUpdater].hasUpdate;
}

-(void) rightOpenPreference:(id)sender
{
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:MAIN_APP_BUNDLEID].count == 0)
    {
        NSArray *arguments = @[[NSString stringWithFormat:@"2"]];
        [[NSWorkspace sharedWorkspace] launchApplicationAtURL:[NSURL fileURLWithPath:DEFAULT_APP_PATH]
                                                      options:NSWorkspaceLaunchWithoutAddingToRecents
                                                configuration:@{NSWorkspaceLaunchConfigurationArguments: arguments}
                                                        error:NULL];
    }
    else
    {
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:kShowPreferenceWindow
                                                                       object:nil
                                                                     userInfo:nil
                                                           deliverImmediately:YES];
    }
    
    [self notifyDimissPopover];
}

-(void) rightAboutAction:(id)sender
{
    if (_aboutWC)
    {
        [_aboutWC showWindow:self];
        [self notifyDimissPopover];
        return;
    }
    
    NSString *versionTime =  [[NSUserDefaults standardUserDefaults] objectForKey:@"kLemon_Version_Time"];
    NSWindow* windowAbout = [LMAboutWindow windowWithVersionTimeString:versionTime];
    _aboutWC = [[NSWindowController alloc] initWithWindow:windowAbout];
    [windowAbout center];
    [_aboutWC showWindow:self];
                             
    [self notifyDimissPopover];
}
- (void)setTextFieldNormal:(NSTextField*) textField
{
    textField.font = [NSFontHelper getLightSystemFont:12];
    textField.textColor = [NSColor colorWithHex:0x7E7E7E alpha:1.0];
}
-(void) rightPrivacyAction:(id)sender
{
    // 纯本地零联网：禁用腾讯隐私外链
    [self notifyDimissPopover];
}

-(void) rightLanguageAction:(id)sender
{
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable ;
    NSWindow* _windowLanguage = [[NSWindow alloc]initWithContentRect:CGRectMake(0, 0, 600, 600) styleMask:style backing:NSBackingStoreBuffered defer:YES];
    
    [_windowLanguage center];
    _windowLanguage.title = NSLocalizedString(@"语言设置", nil);
    
    NSButton* radioButtonChinese = [NSButton radioButtonWithTitle:@"CHINESE" target:self action:@selector(languageSelected:)];
    radioButtonChinese.tag = 1;
    [radioButtonChinese setButtonType:NSButtonTypeRadio];
    [_windowLanguage.contentView addSubview:radioButtonChinese];
    [radioButtonChinese mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(_windowLanguage.contentView);
        make.centerY.equalTo(_windowLanguage.contentView);
    }];
    
    //
    NSButton* radioButtonEnglish = [NSButton radioButtonWithTitle:@"ENGLISH" target:self action:@selector(languageSelected:)];
    radioButtonEnglish.tag = 2;
    [radioButtonEnglish setButtonType:NSButtonTypeRadio];
    [_windowLanguage.contentView addSubview:radioButtonEnglish];
    [radioButtonEnglish mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(_windowLanguage.contentView);
        make.top.mas_equalTo(radioButtonChinese.mas_bottom);
    }];
    
    //
    NSWindowController *wc = [[NSWindowController alloc] initWithWindow:_windowLanguage];
    [wc showWindow:nil];
    
    //
    [self notifyDimissPopover];
}

-(void) rightQuitAction:(id)sender
{
    [self notifyDimissPopover];

    NSApplicationTerminateReply ttype = NSTerminateNow;
    
//    NSArray *runningApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:MAIN_APP_BUNDLEID];
//    if (runningApps.count > 0) {
//        ttype = NSTerminateNow;
//    } else
    Boolean isTrashWatchHasSet = false;
    BOOL isTrashSizeWatchEnable = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)(IS_ENABLE_TRASH_SIZE_WATCH), (__bridge CFStringRef)(MAIN_APP_BUNDLEID), &isTrashWatchHasSet);
    if(!isTrashWatchHasSet){
        isTrashSizeWatchEnable = YES;
    }
    
    if([SharedPrefrenceManager getBool:K_IS_WATCHING_VEDIO] ||
       [SharedPrefrenceManager getBool:K_IS_WATCHING_AUDIO] ||
       [SharedPrefrenceManager getBool:K_IS_WATCHING_SCREEN] ||
       [SharedPrefrenceManager getBool:IS_ENABLE_TRASH_WATCH] ||
       isTrashSizeWatchEnable)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = NSLocalizedString(@"关闭状态栏后，所有功能（包括自动检测卸载残留，摄像头使用提醒等）都不再生效。确定关闭吗？", nil);
        //alert.informativeText = @"确定要阻止吗？";
        [alert addButtonWithTitle:NSLocalizedString(@"取消", nil)];
        [alert addButtonWithTitle:NSLocalizedString(@"退出状态栏", nil)];
        NSInteger responseTag = [alert runModal];
        if (responseTag != NSAlertFirstButtonReturn) {
            ttype = NSTerminateNow;
        } else {
            ttype = NSTerminateCancel;
        }
    }

    if (ttype == NSTerminateNow) {
        NSLog(@"use select terminate monitor by click quit button ");
        [[NSApplication sharedApplication] terminate:nil];
    }
}

-(void) languageSelected:(id)sender
{
    NSButton* btn = (NSButton*)sender;
    
    if (btn.tag == 1)
    {
        NSLog(@"CHINESE language selected");
    }
    else if (btn.tag == 2)
    {
        NSLog(@"ENGLISH language selected");
    }
}
@end




@implementation LMSettingsViewController
- (void)loadView
{
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 116, 113)];
    self.view = contentView;
    self.view.wantsLayer = true;
    //    self.view.layer.backgroundColor = [NSColor redColor].CGColor;
    self.view.layer.backgroundColor = [NSColor colorWithHex:0xEFF0f0 alpha:0.9].CGColor;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}
@end


static NSString * const kGitHubLatestReleaseAPI = @"https://api.github.com/repos/qg-hs/cleaner/releases/latest";

@interface LMGitHubUpdater ()
@property (nonatomic, assign, readwrite) BOOL hasUpdate;
@property (nonatomic, copy, readwrite, nullable) NSString *latestVersion;
@property (nonatomic, copy, readwrite, nullable) NSString *downloadURL;
@property (nonatomic, copy, nullable) NSString *releaseNotes;
@property (nonatomic, assign) BOOL isChecking;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) NSTimeInterval lastCheckTimestamp;
@property (nonatomic, strong, nullable) NSTimer *periodicTimer;
@property (nonatomic, strong, nullable) NSWindow *progressWindow;
@property (nonatomic, strong, nullable) NSProgressIndicator *progressBar;
@property (nonatomic, strong, nullable) NSTextField *progressLabel;
@property (nonatomic, strong, nullable) NSTextField *detailLabel;
@property (nonatomic, strong, nullable) NSButton *actionButton;
@property (nonatomic, strong, nullable) NSButton *cancelButton;
@property (nonatomic, strong, nullable) NSURLSession *downloadSession;
@end

@implementation LMGitHubUpdater

+ (instancetype)sharedUpdater {
    static LMGitHubUpdater *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LMGitHubUpdater alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self restoreCachedUpdateState];
    }
    return self;
}

- (NSString *)targetAppBundlePath {
    // 若 LemonMonitor 运行在 <App>.app/Contents/Library/LoginItems/LemonMonitor.app 下，向上回溯定位外层宿主 .app 路径
    NSString *cursor = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
    while (cursor.length > 1 && ![cursor isEqualToString:@"/"]) {
        if ([cursor hasSuffix:@".app"] && [[NSFileManager defaultManager] fileExistsAtPath:cursor]) {
            return cursor;
        }
        cursor = [cursor stringByDeletingLastPathComponent];
    }
    return DEFAULT_APP_PATH;
}

- (NSString *)currentInstalledVersion {
    NSBundle *targetBundle = [NSBundle bundleWithPath:[self targetAppBundlePath]];
    NSString *ver = [[targetBundle infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (ver.length == 0) {
        ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    }
    return ver ?: @"1.0.2";
}

- (NSString *)normalizeVersionString:(NSString *)rawVersion {
    if (![rawVersion isKindOfClass:[NSString class]] || rawVersion.length == 0) {
        return @"";
    }
    NSString *trimmed = [rawVersion stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmed hasPrefix:@"v"] || [trimmed hasPrefix:@"V"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    return trimmed;
}

- (BOOL)isVersion:(NSString *)remoteVersion newerThan:(NSString *)localVersion {
    NSString *cleanRemote = [self normalizeVersionString:remoteVersion];
    NSString *cleanLocal  = [self normalizeVersionString:localVersion];
    if (cleanRemote.length == 0 || cleanLocal.length == 0) {
        return NO;
    }
    return ([cleanRemote compare:cleanLocal options:NSNumericSearch] == NSOrderedDescending);
}

- (void)restoreCachedUpdateState {
    NSDictionary *cachedInfo = [[NSUserDefaults standardUserDefaults] objectForKey:kLemonNewVersionInfo];
    if ([cachedInfo isKindOfClass:[NSDictionary class]]) {
        NSString *cachedVer = cachedInfo[@"version"];
        NSString *cachedURL = cachedInfo[@"downloadURL"];
        if ([self isVersion:cachedVer newerThan:[self currentInstalledVersion]] &&
            [cachedURL isKindOfClass:[NSString class]] &&
            [cachedURL hasPrefix:@"https://github.com/qg-hs/cleaner/"]) {
            self.hasUpdate = YES;
            self.latestVersion = [self normalizeVersionString:cachedVer];
            self.downloadURL = cachedURL;
            self.releaseNotes = cachedInfo[@"body"];
            return;
        }
    }
    // 清理非本仓库或已过期的残留版本缓存
    self.hasUpdate = NO;
    self.latestVersion = nil;
    self.downloadURL = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersion];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionInfo];
}

- (void)startPeriodicCheck {
    if (self.periodicTimer) {
        return;
    }
    [self checkForUpdatesWithManualTrigger:NO];
    self.periodicTimer = [NSTimer scheduledTimerWithTimeInterval:14400.0
                                                          target:self
                                                        selector:@selector(onPeriodicTimerFired:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)onPeriodicTimerFired:(NSTimer *)timer {
    [self checkForUpdatesWithManualTrigger:NO];
}

- (NSString *)selectBestAssetDownloadURLFromAssets:(NSArray *)assets {
    if (![assets isKindOfClass:[NSArray class]] || assets.count == 0) {
        return nil;
    }
#if defined(__arm64__) || defined(__aarch64__)
    NSString *preferredArchToken = @"arm64";
#else
    NSString *preferredArchToken = @"x86_64";
#endif
    NSString *archMatchURL = nil;
    NSString *universalMatchURL = nil;
    NSString *fallbackZipURL = nil;

    for (NSDictionary *asset in assets) {
        if (![asset isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [asset[@"name"] lowercaseString];
        NSString *url  = asset[@"browser_download_url"];
        if (![name isKindOfClass:[NSString class]] || ![url isKindOfClass:[NSString class]] || ![name hasSuffix:@".zip"]) {
            continue;
        }
        if ([name containsString:preferredArchToken] && !archMatchURL) {
            archMatchURL = url;
        } else if ([name containsString:@"universal"] && !universalMatchURL) {
            universalMatchURL = url;
        } else if (!fallbackZipURL) {
            fallbackZipURL = url;
        }
    }
    return archMatchURL ?: (universalMatchURL ?: fallbackZipURL);
}

- (void)ensureUpdaterWindow {
    if (self.progressWindow) {
        return;
    }
    NSRect rect = NSMakeRect(0, 0, 380, 140);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:rect
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = @"cleaner 版本更新";
    win.level = NSStatusWindowLevel + 1;
    win.releasedWhenClosed = NO;

    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(22, 94, 336, 22)];
    titleLabel.editable = NO;
    titleLabel.selectable = NO;
    titleLabel.bezeled = NO;
    titleLabel.drawsBackground = NO;
    titleLabel.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold];
    [win.contentView addSubview:titleLabel];
    self.progressLabel = titleLabel;

    NSTextField *subLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(22, 54, 336, 34)];
    subLabel.editable = NO;
    subLabel.selectable = NO;
    subLabel.bezeled = NO;
    subLabel.drawsBackground = NO;
    subLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    subLabel.textColor = [NSColor secondaryLabelColor];
    subLabel.usesSingleLineMode = NO;
    subLabel.cell.wraps = YES;
    [win.contentView addSubview:subLabel];
    self.detailLabel = subLabel;

    NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(22, 22, 336, 18)];
    bar.indeterminate = NO;
    bar.minValue = 0.0;
    bar.maxValue = 100.0;
    bar.doubleValue = 0.0;
    [win.contentView addSubview:bar];
    self.progressBar = bar;

    NSButton *primaryBtn = [[NSButton alloc] initWithFrame:NSMakeRect(248, 14, 110, 28)];
    primaryBtn.bezelStyle = NSBezelStyleRounded;
    primaryBtn.title = @"立即热更";
    primaryBtn.keyEquivalent = @"\r";
    primaryBtn.target = self;
    primaryBtn.action = @selector(onConfirmHotUpdateClicked:);
    [win.contentView addSubview:primaryBtn];
    self.actionButton = primaryBtn;

    NSButton *closeBtn = [[NSButton alloc] initWithFrame:NSMakeRect(156, 14, 84, 28)];
    closeBtn.bezelStyle = NSBezelStyleRounded;
    closeBtn.title = @"确定";
    closeBtn.target = self;
    closeBtn.action = @selector(onDismissWindowClicked:);
    [win.contentView addSubview:closeBtn];
    self.cancelButton = closeBtn;

    [win center];
    self.progressWindow = win;
}

- (void)showCheckingWindow {
    [self ensureUpdaterWindow];
    self.progressLabel.stringValue = @"正在检查更新...";
    self.detailLabel.stringValue = [NSString stringWithFormat:@"当前版本 v%@，正在连接 GitHub Releases...", [self currentInstalledVersion]];
    self.actionButton.hidden = YES;
    self.cancelButton.hidden = YES;
    self.progressBar.hidden = NO;
    self.progressBar.indeterminate = YES;
    [self.progressBar startAnimation:nil];
    if (!self.progressWindow.isVisible) {
        [self.progressWindow center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.progressWindow makeKeyAndOrderFront:nil];
}

- (void)showResultWindowWithTitle:(NSString *)title
                           detail:(NSString *)detail
                 showUpdateButton:(BOOL)showUpdateButton {
    [self ensureUpdaterWindow];
    [self.progressBar stopAnimation:nil];
    self.progressBar.hidden = YES;
    self.progressLabel.stringValue = title ?: @"";
    self.detailLabel.stringValue = detail ?: @"";

    if (showUpdateButton) {
        self.actionButton.hidden = NO;
        self.actionButton.frame = NSMakeRect(248, 14, 110, 28);
        self.cancelButton.hidden = NO;
        self.cancelButton.title = @"稍后";
        self.cancelButton.frame = NSMakeRect(156, 14, 84, 28);
    } else {
        self.actionButton.hidden = YES;
        self.cancelButton.hidden = NO;
        self.cancelButton.title = @"确定";
        self.cancelButton.frame = NSMakeRect(274, 14, 84, 28);
    }
    if (!self.progressWindow.isVisible) {
        [self.progressWindow center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.progressWindow makeKeyAndOrderFront:nil];
}

- (void)onConfirmHotUpdateClicked:(id)sender {
    [self startHotUpdate];
}

- (void)onDismissWindowClicked:(id)sender {
    [self.progressBar stopAnimation:nil];
    [self.progressWindow orderOut:nil];
}

- (void)checkForUpdatesWithManualTrigger:(BOOL)isManual {
    if (self.isChecking) {
        if (isManual && self.progressWindow) {
            [NSApp activateIgnoringOtherApps:YES];
            [self.progressWindow makeKeyAndOrderFront:nil];
        }
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (!isManual && (now - self.lastCheckTimestamp < 300.0)) {
        return;
    }
    self.isChecking = YES;
    self.lastCheckTimestamp = now;

    if (isManual) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showCheckingWindow];
        });
    }

    NSURL *url = [NSURL URLWithString:kGitHubLatestReleaseAPI];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15.0];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"cleaner-macos-updater" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.isChecking = NO;

        NSHTTPURLResponse *httpResp = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (error || !data || (httpResp && httpResp.statusCode != 200)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isManual) {
                    if (httpResp && httpResp.statusCode == 404) {
                        [strongSelf showResultWindowWithTitle:@"当前已是最新版本"
                                                       detail:[NSString stringWithFormat:@"当前版本 v%@ 已是最新版本（GitHub 仓库暂无更高版本 Release）。", [strongSelf currentInstalledVersion]]
                                             showUpdateButton:NO];
                    } else {
                        [strongSelf showResultWindowWithTitle:@"检查更新失败"
                                                       detail:[NSString stringWithFormat:@"无法连接 GitHub Releases 接口（%@）。", error.localizedDescription ?: @"HTTP 状态异常"]
                                             showUpdateButton:NO];
                    }
                }
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isManual) {
                    [strongSelf showResultWindowWithTitle:@"检查更新失败"
                                                   detail:@"返回数据格式异常，请稍后重试。"
                                         showUpdateButton:NO];
                }
            });
            return;
        }

        NSString *tagName = json[@"tag_name"];
        NSString *cleanRemoteVer = [strongSelf normalizeVersionString:tagName];
        NSString *localVer = [strongSelf currentInstalledVersion];
        NSString *matchedZipURL = [strongSelf selectBestAssetDownloadURLFromAssets:json[@"assets"]];
        NSString *releaseBody = [json[@"body"] isKindOfClass:[NSString class]] ? json[@"body"] : @"";

        BOOL newer = [strongSelf isVersion:cleanRemoteVer newerThan:localVer] && (matchedZipURL.length > 0);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (newer) {
                strongSelf.hasUpdate = YES;
                strongSelf.latestVersion = cleanRemoteVer;
                strongSelf.downloadURL = matchedZipURL;
                strongSelf.releaseNotes = releaseBody;

                NSDictionary *infoDict = @{
                    @"version": cleanRemoteVer,
                    @"downloadURL": matchedZipURL,
                    @"body": releaseBody
                };
                [[NSUserDefaults standardUserDefaults] setObject:cleanRemoteVer forKey:kLemonNewVersion];
                [[NSUserDefaults standardUserDefaults] setObject:infoDict forKey:kLemonNewVersionInfo];
                [[NSUserDefaults standardUserDefaults] synchronize];

                [[NSNotificationCenter defaultCenter] postNotificationName:@"LemonHasNewVersion" object:nil];

                if (isManual) {
                    NSString *detailText = releaseBody.length > 0
                        ? releaseBody
                        : [NSString stringWithFormat:@"当前版本 v%@，是否立即下载 v%@ 并自动替换重启？", localVer, cleanRemoteVer];
                    [strongSelf showResultWindowWithTitle:[NSString stringWithFormat:@"发现新版本 v%@", cleanRemoteVer]
                                                   detail:detailText
                                         showUpdateButton:YES];
                }
            } else {
                strongSelf.hasUpdate = NO;
                strongSelf.latestVersion = nil;
                strongSelf.downloadURL = nil;
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersion];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionInfo];
                [[NSUserDefaults standardUserDefaults] synchronize];

                [[NSNotificationCenter defaultCenter] postNotificationName:@"LemonHasNewVersion" object:nil];

                if (isManual) {
                    [strongSelf showResultWindowWithTitle:@"当前已是最新版本"
                                                   detail:[NSString stringWithFormat:@"当前版本 v%@ 已是最新发行版。", localVer]
                                         showUpdateButton:NO];
                }
            }
        });
    }];
    [task resume];
}

- (void)showProgressWindowWithVersion:(NSString *)version {
    [self ensureUpdaterWindow];
    self.actionButton.hidden = YES;
    self.cancelButton.hidden = YES;
    self.progressLabel.stringValue = [NSString stringWithFormat:@"正在下载新版本 v%@ (0%%)...", version ?: @""];
    self.detailLabel.stringValue = @"下载完成后将自动替换 cleaner.app 并重启应用";
    self.progressBar.hidden = NO;
    self.progressBar.indeterminate = NO;
    self.progressBar.doubleValue = 0.0;
    if (!self.progressWindow.isVisible) {
        [self.progressWindow center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.progressWindow makeKeyAndOrderFront:nil];
}

- (void)startHotUpdate {
    if (self.isDownloading) {
        if (self.progressWindow) {
            [self.progressWindow makeKeyAndOrderFront:nil];
        }
        return;
    }
    if (self.downloadURL.length == 0) {
        [self checkForUpdatesWithManualTrigger:YES];
        return;
    }
    NSURL *url = [NSURL URLWithString:self.downloadURL];
    if (!url) {
        return;
    }

    self.isDownloading = YES;
    [self showProgressWindowWithVersion:self.latestVersion];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.downloadSession = [NSURLSession sessionWithConfiguration:config
                                                         delegate:self
                                                    delegateQueue:[NSOperationQueue mainQueue]];
    NSURLSessionDownloadTask *downloadTask = [self.downloadSession downloadTaskWithURL:url];
    [downloadTask resume];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite > 0) {
        double pct = (double)totalBytesWritten * 100.0 / (double)totalBytesExpectedToWrite;
        self.progressBar.doubleValue = pct;
        self.progressLabel.stringValue = [NSString stringWithFormat:@"正在下载新版本 v%@ (%.0f%%)...", self.latestVersion ?: @"", pct];
    } else {
        self.progressBar.indeterminate = YES;
        [self.progressBar startAnimation:nil];
        self.progressLabel.stringValue = [NSString stringWithFormat:@"正在下载新版本 v%@...", self.latestVersion ?: @""];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"cleaner_hotupdate_%d", getpid()]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:tempRoot error:nil];
    [fm createDirectoryAtPath:tempRoot withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *zipPath = [tempRoot stringByAppendingPathComponent:@"cleaner-update.zip"];
    NSError *moveErr = nil;
    if (![fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:zipPath] error:&moveErr]) {
        self.isDownloading = NO;
        [self.progressWindow orderOut:nil];
        return;
    }

    self.progressLabel.stringValue = @"正在解压并校验安装包...";
    self.progressBar.indeterminate = YES;
    [self.progressBar startAnimation:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *extractDir = [tempRoot stringByAppendingPathComponent:@"extracted"];
        [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSTask *unzipTask = [[NSTask alloc] init];
        unzipTask.launchPath = @"/usr/bin/ditto";
        unzipTask.arguments = @[@"-x", @"-k", zipPath, extractDir];
        [unzipTask launch];
        [unzipTask waitUntilExit];

        NSString *extractedAppPath = [extractDir stringByAppendingPathComponent:@"cleaner.app"];
        NSString *extractedExecPath = [extractedAppPath stringByAppendingPathComponent:@"Contents/MacOS/cleaner"];
        if (unzipTask.terminationStatus != 0 || ![fm isExecutableFileAtPath:extractedExecPath]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isDownloading = NO;
                [self showResultWindowWithTitle:@"热更新包校验失败"
                                         detail:@"下载的压缩包内未找到有效的 cleaner.app，请稍后重试。"
                               showUpdateButton:NO];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressLabel.stringValue = @"正在替换应用并自动重启...";
        });

        // 清理已更新版本的缓存标记
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersion];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionInfo];
        [[NSUserDefaults standardUserDefaults] synchronize];

        NSString *targetAppPath = [self targetAppBundlePath];
        NSString *scriptPath = [tempRoot stringByAppendingPathComponent:@"apply_update.sh"];
        NSString *scriptContent = [NSString stringWithFormat:
            @"#!/bin/sh\n"
            @"sleep 0.8\n"
            @"killall -9 LemonMonitor cleaner 2>/dev/null || true\n"
            @"sleep 0.4\n"
            @"rm -rf \"%@\"\n"
            @"/usr/bin/ditto \"%@\" \"%@\"\n"
            @"if [ \"%@\" != \"/Applications/cleaner.app\" ] && [ -d \"/Applications/cleaner.app\" ]; then\n"
            @"  rm -rf \"/Applications/cleaner.app\"\n"
            @"  /usr/bin/ditto \"%@\" \"/Applications/cleaner.app\"\n"
            @"fi\n"
            @"/usr/bin/xattr -cr \"%@\" 2>/dev/null || true\n"
            @"/usr/bin/open \"%@\"\n"
            @"if [ -d \"%@/Contents/Library/LoginItems/LemonMonitor.app\" ]; then\n"
            @"  /usr/bin/open -a \"%@/Contents/Library/LoginItems/LemonMonitor.app\" --args 1 2>/dev/null || true\n"
            @"fi\n"
            @"rm -rf \"%@\"\n",
            targetAppPath,
            extractedAppPath, targetAppPath,
            targetAppPath,
            extractedAppPath,
            targetAppPath,
            targetAppPath,
            targetAppPath,
            targetAppPath,
            tempRoot];

        [scriptContent writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([scriptPath fileSystemRepresentation], 0755);

        // 启动独立脱离的后台替换重启脚本
        NSString *launchCmd = [NSString stringWithFormat:@"nohup /bin/sh \"%@\" >/dev/null 2>&1 &", scriptPath];
        system([launchCmd UTF8String]);

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSApplication sharedApplication] terminate:nil];
        });
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error) {
        self.isDownloading = NO;
        [self showResultWindowWithTitle:@"下载新版本失败"
                                 detail:error.localizedDescription ?: @"网络连接中断，请稍后重试。"
                       showUpdateButton:NO];
    }
}

@end
