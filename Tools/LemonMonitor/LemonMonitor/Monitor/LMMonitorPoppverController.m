//
//  LMMonitorPoppverController.m
//  LemonMonitor
//

//  Copyright © 2019年 Tencent. All rights reserved.
//

#import "LMMonitorPoppverController.h"

#import "NSEvent+Extension.h"
#import "LMCleanViewController.h"
#import "LMSystemFeatureViewController.h"
#import "McStatInfoConst.h"
#import "McStatMonitor.h"
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMUICommon/LMCommonHelper.h>

static const CGFloat kDefaultBubbleMarginToScreen = 50;

@interface LMMonitorPoppverController ()
{
    /// global mouse event handlers
    id floatMonitor;
    id statusMonitorGlobal;
    id statusMonitorLocal;
    CGPoint _currentShowPoint;

}
@property (nonatomic, assign) float bubbleMarginToScreen;

@end


@implementation LMMonitorPoppverController



- (id)init
{
    self = [super init];
    if (self)
    {
        self.bubbleMarginToScreen = kDefaultBubbleMarginToScreen;
        [self setupBubble];
    }
    return self;
}

- (void)showBubble
{
    QMBubble *bubble = [self setupBubble];
    bubble.distance = 30;
    if (bubble.isVisible && !bubble.attachedToParentWindow) return;
    NSPoint showPoint = [self configBubbleWithCurrentState];
    _currentShowPoint = showPoint;
    [bubble showToPoint:showPoint ofWindow: nil];
}

- (NSPoint)configBubbleWithCurrentState
{
    QMBubble *bubble = [self bubble];
    double arrowDistance = 0;
    NSPoint showPoint = NSZeroPoint;
    QMArrowDirection direction = QMArrowTopLeft;
    NSRect screenFrame = [[NSScreen workScreen] frame];
    NSSize bubbleSize = [bubble.contentView frame].size;
    //设置泡泡的方向,坐标

    direction = QMArrowSideTop;
    
    //显示的参照点
    NSRect statusRect = [self.statusView convertRect:self.statusView.bounds toView:nil];
    statusRect = [self.statusView.window convertRectToScreen:statusRect];
    showPoint = NSMakePoint(NSMidX(statusRect), NSMinY(statusRect));
    
    // bubble 显示不全的时候.
    if(screenFrame.size.width - showPoint.x < bubbleSize.width / 2 ){
        direction = QMArrowTopRight;
        //
        CGFloat screenOffset = 30;
        arrowDistance = NSMaxX(screenFrame) - showPoint.x - screenOffset;
    }else{
        arrowDistance = bubbleSize.width / 2;
    }
    
    self.systemFeatureViewController.windowVisible = YES;
    //显示泡泡
    bubble.direction = direction;
    bubble.arrowDistance = arrowDistance;
    
    return showPoint;
}


- (QMBubble *)setupBubble
{
    if (!_bubble) {
        _bubble = [[QMBubble alloc] init];
        _bubble.distance = 30;
        _bubble.keyWindow = YES;
        _bubble.draggable = NO;
        if ([LMCommonHelper isMacOS11]) {
            [_bubble setCornerRadius:10.0];
        } else {
            [_bubble setCornerRadius:5];
        }
        
        [_bubble setArrowHeight:6.0];
        [_bubble setArrowWidth:10.0];
        [_bubble setBorderColor:[NSColor clearColor]];
        [_bubble setBackgroudColor:[LMAppThemeHelper getMainBgColor]];
        
        //进程的信息
        self.systemFeatureViewController = [[LMSystemFeatureViewController alloc] init];
        self.cleanViewController = [[LMCleanViewController alloc] init];
        self.tabViewController = [[LMMonitorTabController alloc]
                                  initWithControllers:@[ _cleanViewController,_systemFeatureViewController]
                                  titles:@[NSLocalizedString(@"清理释放", nil),
                NSLocalizedString(@"系统功能", nil)]];
        self.cleanViewController.tabController = self.tabViewController;
        self.memoryViewController = _cleanViewController;
        self.networkViewController = _systemFeatureViewController;
       
        
        [_bubble setContentView:_tabViewController.view];
    }
    return _bubble;
}

- (void)dismissPopover
{
    [self dismissBubbleWithCompletion:self.dismissCompletion];
}

- (void)dismissBubbleWithCompletion:(void(^)())completion
{
    if (!_bubble) {
        if (completion) completion();
        return;
    }
    //设置statmonitor 标志位
    [[McStatMonitor shareMonitor] setIsTrayPageOpen:NO];
    self.systemFeatureViewController.windowVisible = NO;
    [self.systemFeatureViewController stopMonitor];
    [self.cleanViewController stopMonitor];
    

    if (floatMonitor) {
        [NSEvent removeMonitor:floatMonitor];
        floatMonitor = nil;
    }
    if (statusMonitorGlobal) {
        [NSEvent removeMonitor:statusMonitorGlobal];
        statusMonitorGlobal = nil;
    }
    if (statusMonitorLocal) {
        [NSEvent removeMonitor:statusMonitorLocal];
        statusMonitorLocal = nil;
    }
    [self stopObservingBubbleWindow];
    __weak LMMonitorPoppverController *wself = self;
    //    [_bubble dismiss];
    
    [_bubble dismissWithCompletion:^(QMBubble *b) {
//        LMMonitorPoppverController *sself = wself;
        if (completion) {
            completion();
        }
        //        if (sself) {
        //            sself->tabViewController = nil;
        //            sself->networkVC = nil;
        //            sself->memoryVC = nil;
        //            sself->_bubble = nil;
        //        }
    }];
}



// 显示大浮窗
- (void)showPopover
{
    NSLog(@"%s", __FUNCTION__);
    
    if (self.bubble.isVisible && !self.bubble.attachedToParentWindow) return;
    [self showBubble];
    NSLog(@"McNetInfo,%s,startMonitor before", __FUNCTION__);
    [self.systemFeatureViewController startMonitor];
    
    NSLog(@"McNetInfo,%s,startMonitor end", __FUNCTION__);
    [self.cleanViewController startMonitor];
    __weak LMMonitorPoppverController *wself = self;

    void (^handler)(NSEvent *) = ^void(NSEvent *event){
        LMMonitorPoppverController *sself = wself;
        NSRect frame = sself.tabViewController.view.window.frame;
        NSRect bounds = NSMakeRect(0, 0, frame.size.width, frame.size.height);
        
        NSPoint event_location = [event locationInWindow]; // 当时事件 event 在 window 中的位置.
//            NSPoint event_location = [NSEvent mouseLocation]; //当前鼠标在坐标轴中的位置
        
        //如果 事件在 Monitor窗口触发,并且是在 Monitor 窗口内.则不dismiss 窗口.
        if (event.window == sself.tabViewController.view.window && NSPointInRect(event_location, NSInsetRect(bounds, -2, -2)))
        {
            return;
        }
        if (sself.bubble.titleMode == QMBubbleTitleModeArrow) {
            [sself dismissBubbleWithCompletion:sself.dismissCompletion];
        }
    };
    
    if (!statusMonitorGlobal) {
        statusMonitorGlobal = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:handler];
        statusMonitorLocal  = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown  handler:^NSEvent *(NSEvent *event) {
            handler(event);
            return event;
        }];
        }
        
    
    [self startObservingBubbleWindow];


    _bubbleWindow = _bubble.contentView.window;
}

// 状态栏上窗口位置变化时，保持托盘弹窗稳定，不再因相邻状态栏图标（如实时网速）宽度微调而自动关闭弹窗
- (void)statusBarWindowDidMove:(NSNotification *)note
{
    NSWindow *window = note.object;
    if (!window || !_bubble || !_bubble.isVisible) {
        return;
    }

    NSRect screenFrame = [[NSScreen workScreen] frame];
    // 若状态栏图标被第三方菜单栏折叠工具（如 Hidden Bar）移出屏幕可见区，保持当前弹窗位置不自动关闭
    if (window.frame.origin.x < NSMinX(screenFrame) || NSMaxX(window.frame) > NSMaxX(screenFrame)) {
        return;
    }

    CGFloat statusBarCenterX = NSMidX(window.frame);
    CGFloat deltaX = statusBarCenterX - _currentShowPoint.x;

    // 30pt 以内的微移（如右侧网速指示器数字位数变化引起的 4~15pt 抖动）保持弹窗静止，避免按钮抖动
    if (fabs(deltaX) <= 30.0) {
        return;
    }

    // 超过 30pt 的显著位置变化（如增删状态栏图标），平滑平移弹窗跟随图标，不关闭弹窗
    _currentShowPoint.x = statusBarCenterX;
    if (_bubbleWindow) {
        NSRect bubbleFrame = _bubbleWindow.frame;
        bubbleFrame.origin.x += deltaX;
        if (NSMaxX(bubbleFrame) > NSMaxX(screenFrame) - 10) {
            bubbleFrame.origin.x = NSMaxX(screenFrame) - 10 - NSWidth(bubbleFrame);
        }
        if (bubbleFrame.origin.x < NSMinX(screenFrame) + 10) {
            bubbleFrame.origin.x = NSMinX(screenFrame) + 10;
        }
        [_bubbleWindow setFrameOrigin:bubbleFrame.origin];
    }
}

- (void)startObservingBubbleWindow
{

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onPopoverPopup:)
                                                 name:QMPopoverDismiss
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarWindowDidMove:)
                name:NSWindowDidMoveNotification object:self.statusView.window];
}
- (void)stopObservingBubbleWindow
{
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:QMPopoverDismiss
                                                  object:nil];
    
    // 移除自己的关于 状态栏移动时的 bug.
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowDidMoveNotification
                                                  object:nil];
}

- (void)onPopoverPopup:(NSNotification *)notification
{
    [self dismissPopover];
}


@end
