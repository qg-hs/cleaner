//
//  MonitorTrashScanManager.m
//  LemonMonitor
//

//  Copyright © 2019 Tencent. All rights reserved.
//

#import "LMMonitorTrashManager.h"
#import <AppKit/AppKit.h>
#import <LemonClener/QMLiteCleanerManager.h>
#import <LemonClener/CleanerCantant.h>
#import <QMCoreFunction/LMReferenceDefines.h>

#define ScanInterval 60*60  //s :1hour

@implementation LMMonitorTrashManager
{
    NSTimer          *scanTrashTimer;
    NSLock           *mTrashCleaningLock;
    NSTimeInterval   mLastCleanTime;
    NSTimeInterval   mLastScanTime;
    NSInteger        _trashSize;  // -1 代表还未扫描. 0-50M 以下代表很干净.
    BOOL             _isStarted;
    BOOL             _isScreenSleepingOrLocked;
}

-(instancetype)init{
    self = [super init];
    if(self){
        mTrashCleaningLock = [[NSLock alloc]init];
        NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
        [wsCenter addObserver:self selector:@selector(handleScreenSleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];
        [wsCenter addObserver:self selector:@selector(handleScreenSleep:) name:NSWorkspaceWillSleepNotification object:nil];
        [wsCenter addObserver:self selector:@selector(handleScreenWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
        [wsCenter addObserver:self selector:@selector(handleScreenWake:) name:NSWorkspaceDidWakeNotification object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(handleScreenSleep:) name:@"com.apple.screenIsLocked" object:nil];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(handleScreenWake:) name:@"com.apple.screenIsUnlocked" object:nil];
    }
    
    return self;
}

- (void)handleScreenSleep:(NSNotification *)note
{
    _isScreenSleepingOrLocked = YES;
    if (scanTrashTimer) {
        [scanTrashTimer invalidate];
        scanTrashTimer = nil;
    }
}

- (void)handleScreenWake:(NSNotification *)note
{
    _isScreenSleepingOrLocked = NO;
    if (_isStarted && !scanTrashTimer) {
        scanTrashTimer = [NSTimer scheduledTimerWithTimeInterval:ScanInterval target:self selector:@selector(onTrashScan) userInfo:nil repeats:YES];
        scanTrashTimer.tolerance = 300.0;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - mLastScanTime >= ScanInterval) {
            [self onTrashScan];
        }
    }
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"%s  %ld", __FUNCTION__, (long)_trashSize];
}


+ (instancetype)sharedManager
{
    static LMMonitorTrashManager * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!instance){
            instance = [[LMMonitorTrashManager alloc] init];
        }
    });
    return instance;
}

- (void)startTrashScan
{
    _isStarted = YES;
    _trashSize = -1;
    _trashPhase = TrashScanNotStart;
    if (scanTrashTimer) {
        [scanTrashTimer invalidate];
        scanTrashTimer = nil;
    }
    if (!_isScreenSleepingOrLocked) {
        scanTrashTimer = [NSTimer scheduledTimerWithTimeInterval:ScanInterval target:self selector:@selector(onTrashScan) userInfo:nil repeats:YES];
        scanTrashTimer.tolerance = 300.0; // 允许 XNU Timer Coalescing
        [scanTrashTimer fire];
    }
    // 注册主界面接收清理完成的通知.
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:MAIN_CLENER_CLEAN_SUCCESS object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(onReceiveLemonTrashClean:) name:MAIN_CLENER_CLEAN_SUCCESS object:nil];
}

- (void)dealloc{
    [scanTrashTimer invalidate];
    scanTrashTimer = nil;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}


- (void)onTrashScan
{
    if (_isScreenSleepingOrLocked) {
        return;
    }
    mLastScanTime = [[NSDate date] timeIntervalSince1970];
    NSLog(@"monitor trashScan enter.");
    @weakify(self);
    dispatch_async(kQMDEFAULT_GLOBAL_QUEUE, ^{
        @strongify(self);
        if (!self) return;
        [self->mTrashCleaningLock lock];
        self.trashPhase = TrashScaning;
        [[QMLiteCleanerManager sharedManger] startScan];
        // 同步获取扫描完直接获取 垃圾size.
        self->_trashSize = [[QMLiteCleanerManager sharedManger] resultSize];
        self.trashPhase = TrashScanEnd;
        [self->mTrashCleaningLock unlock];
        NSLog(@"monitor trash scan result size : is %ld", (long)_trashSize);
        dispatch_async(dispatch_get_main_queue(), ^{
            @strongify(self);
            if (!self) return;
            if(self.delegate){
                [self.delegate changeTrashViewState];
            }
        });
    });
}

-(void)cleanTrash
{
    [self onTrashClean];
}

- (void) onTrashClean
{
    NSLog(@"onTrashClean enter.");
    
    QMLiteCleanerManager* qmLiteCleanerManager = [QMLiteCleanerManager sharedManger];
    if(_delegate){
        qmLiteCleanerManager.delegate = (LMCleanViewController *)_delegate;
    }
    @weakify(self);
    dispatch_async(kQMDEFAULT_GLOBAL_QUEUE, ^{
        @strongify(self);
        if (!self) return;
        [self->mTrashCleaningLock lock];
        self.trashPhase = TrashCleaning;
        
        [qmLiteCleanerManager startScan];
        self->_trashSize = [qmLiteCleanerManager resultSize];
        [qmLiteCleanerManager startCleanWithActionSource:QMCleanerActionSourceMonitor];
        
        self->mLastCleanTime = [[NSDate date] timeIntervalSince1970];
        self->_trashSize = 0;
        self.trashPhase = TrashScanEnd;
        [self->mTrashCleaningLock unlock];
    });
}


- (void) onReceiveLemonTrashClean:(NSNotification *)notif
{
    NSLog(@"onReceiveLemonTrashClean. receive lemon app clean action, %@",notif);
    _trashSize = 0;
    mLastCleanTime = [[NSDate date] timeIntervalSince1970];
    if(_delegate){
        [_delegate changeTrashViewState];
    }
}

- (NSInteger) getTrashSize
{
    NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - mLastCleanTime;
    if(delta < 10 * 60){ //10分钟以内显示很干净
        return 0;
    }
    return _trashSize;
}
@end
