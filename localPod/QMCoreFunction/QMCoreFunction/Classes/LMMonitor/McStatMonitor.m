//
//  McStatMonitor.m
//  McStat
//
//  Created by developer on 12-4-6.
//  Copyright (c) 2012 Magican Software Ltd. All rights reserved.
//

#import "McStatMonitor.h"
#import "McStatInfoHelp.h"
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <sys/sysctl.h>
#import <libproc.h>
#import "McMonitorFuction.h"
#import "McStatInfoConst.h"
#import "QMSampleStorage.h"
#import "LMReferenceDefines.h"
#import "McCoreFunction.h"

#define STATUS_TYPE_LOGO (1 << 0)
#define STATUS_TYPE_MEM  (1 << 1)
#define STATUS_TYPE_DISK (1 << 2)
#define STATUS_TYPE_TEP  (1 << 3)
#define STATUS_TYPE_FAN  (1 << 4)
#define STATUS_TYPE_NET  (1 << 5)
#define STATUS_TYPE_CPU  (1 << 6)
#define STATUS_TYPE_GPU  (1 << 7)

@interface McStatMonitor()
{
    McMonitorFuction * m_monitorFunction;
    
    NSDictionary * m_cpuDict;
    NSDictionary * m_gpuDict;
    NSDictionary * m_fanDict;
    NSDictionary * m_memoryDict;
    NSDictionary * m_networkDict;
    NSDictionary * m_tempCpuDict;
    NSDictionary * m_diskDict;
    QMSampleStorage *storage;
}
@property int processSamplerLifeCounter;
// 串行队列
@property (nonatomic, strong) dispatch_queue_t loopQueue;
@property (nonatomic, strong) dispatch_source_t pollTimer;
@property (atomic, assign) BOOL isScreenSleepingOrLocked;

@end

@implementation McStatMonitor
@synthesize isTrayPageOpen = _isTrayPageOpen;

- (id)init
{
    if (self = [super init])
    {
        refreshInterval = 2;
        escThread = NO;
        _isScreenSleepingOrLocked = NO;
        storage = [[QMSampleStorage alloc] init];
        // 创建对象，用于线程调用
        m_monitorFunction = [[McMonitorFuction alloc] init];
        isExistBattery = [McStatInfoHelp checkBatteryExist];
        
        self.loopQueue = dispatch_queue_create("com.tecent.lemonmonitor.loopgetdataqueue", DISPATCH_QUEUE_SERIAL);
        [self _registerPowerAndLockNotifications];

        // 首次立即执行, 后续由可挂起的 Coalesced Dispatch Timer 驱动（熄屏/锁屏零唤醒）
        dispatch_async(self.loopQueue, ^{
            [self _collectAndSendSystemInfo];
        });
        [self _startPollTimerIfNeeded];
    }
    
    return self;
}


+ (McStatMonitor *)shareMonitor
{
    static dispatch_once_t onceToken = 0;
    __strong static id instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    
    return instance;
}

-(void)dealloc
{
    escThread = YES;
    [self _stopPollTimer];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_registerPowerAndLockNotifications
{
    NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter addObserver:self selector:@selector(_handleScreenOrSystemSleep:) name:NSWorkspaceScreensDidSleepNotification object:nil];
    [wsCenter addObserver:self selector:@selector(_handleScreenOrSystemSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [wsCenter addObserver:self selector:@selector(_handleScreenOrSystemWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    [wsCenter addObserver:self selector:@selector(_handleScreenOrSystemWake:) name:NSWorkspaceDidWakeNotification object:nil];

    NSDistributedNotificationCenter *distCenter = [NSDistributedNotificationCenter defaultCenter];
    [distCenter addObserver:self selector:@selector(_handleScreenOrSystemSleep:) name:@"com.apple.screenIsLocked" object:nil];
    [distCenter addObserver:self selector:@selector(_handleScreenOrSystemWake:) name:@"com.apple.screenIsUnlocked" object:nil];
}

- (void)_handleScreenOrSystemSleep:(NSNotification *)note
{
    self.isScreenSleepingOrLocked = YES;
    [self _stopPollTimer];
}

- (void)_handleScreenOrSystemWake:(NSNotification *)note
{
    self.isScreenSleepingOrLocked = NO;
    if (!self->escThread) {
        [self _startPollTimerIfNeeded];
        dispatch_async(self.loopQueue, ^{
            [self _collectAndSendSystemInfo];
        });
    }
}

- (void)_startPollTimerIfNeeded
{
    dispatch_async(self.loopQueue, ^{
        if (self->escThread || self.isScreenSleepingOrLocked) {
            return;
        }
        if (self.pollTimer != nil) {
            return;
        }
        int intervalSec = self->refreshInterval > 0 ? self->refreshInterval : 2;
        uint64_t intervalNs = (uint64_t)intervalSec * NSEC_PER_SEC;
        // 20% Leeway 允许 XNU 内核合并时钟中断（Timer Coalescing），显著降低能效核唤醒功耗
        uint64_t leewayNs = intervalNs / 5;

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.loopQueue);
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNs),
                                  intervalNs,
                                  leewayNs);
        @weakify(self);
        dispatch_source_set_event_handler(timer, ^{
            @strongify(self);
            if (!self || self->escThread || self.isScreenSleepingOrLocked) {
                return;
            }
            @autoreleasepool {
                [self _collectAndSendSystemInfo];
            }
        });
        self.pollTimer = timer;
        dispatch_resume(timer);
    });
}

- (void)_stopPollTimer
{
    dispatch_async(self.loopQueue, ^{
        if (self.pollTimer != nil) {
            dispatch_source_cancel(self.pollTimer);
            self.pollTimer = nil;
        }
    });
}

- (void)setIsTrayPageOpen:(BOOL)isTrayPageOpen
{
    BOOL changedToOpen = (!_isTrayPageOpen && isTrayPageOpen);
    _isTrayPageOpen = isTrayPageOpen;
    if (changedToOpen && !self->escThread && !self.isScreenSleepingOrLocked) {
        dispatch_async(self.loopQueue, ^{
            @autoreleasepool {
                [self _collectAndSendSystemInfo];
            }
        });
    }
}

- (BOOL)isTrayPageOpen
{
    return _isTrayPageOpen;
}

- (void)_collectAndSendSystemInfo
{
    if (!self->escThread && !self.isScreenSleepingOrLocked)
    {
        if ((self.trayType & STATUS_TYPE_NET) || (self.isTrayPageOpen)) {
            [self networkInfo];
        }
        if ((self.trayType & STATUS_TYPE_MEM) || (self.isTrayPageOpen)) {
            [self memoryInfo];
        }
#ifndef APPSTORE_VERSION
        if (LMDeviceHasPhysicalFan() && ((self.trayType & STATUS_TYPE_FAN) || (self.isTrayPageOpen))) {
            [self fanInfo];
        }
#endif
        if ((self.trayType & STATUS_TYPE_CPU) || (self.isTrayPageOpen)) {
            [self cpuInfo];
        }
        if ((self.trayType & STATUS_TYPE_DISK) || (self.isTrayPageOpen)) {
            [self diskInfo];
        }
#ifndef APPSTORE_VERSION
        if ((self.trayType & STATUS_TYPE_TEP) || (self.isTrayPageOpen)) {
            [self tempInfo];
        }
#endif
        if ((self.trayType & STATUS_TYPE_GPU) || (self.isTrayPageOpen)) {
            [self gpuInfo];
        }
        if (self.processSamplerOn) {
            self.processSamplerLifeCounter -= 1;
            [self->storage sample];
        }
        [self sendStatInfoNotification];
    }
}

- (void)startRunMonitor
{
    escThread = NO;
    [self _startPollTimerIfNeeded];
}
- (void)stopRunMonitor
{
    escThread = YES;
    [self _stopPollTimer];
}

- (void)refreshTime:(NSNotification *)notification
{
    int newInterval = [[notification object] intValue];
    if (newInterval > 0 && newInterval != refreshInterval) {
        refreshInterval = newInterval;
        [self _stopPollTimer];
        [self _startPollTimerIfNeeded];
    }
}

- (void)sendStatInfoNotification
{
    // 网络信息（仅在勾选网速或浮窗展开时投递）
    if (m_networkDict) {
        if ((self.trayType & STATUS_TYPE_NET) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kNetworkInfoNotification object:m_networkDict];
        }
    }
    
    // 内存信息
    if (m_memoryDict) {
        if ((self.trayType & STATUS_TYPE_MEM) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kMemoryCPUInfoNotification object:m_memoryDict];
            //            [statDict setObject:m_memoryDict forKey:kMemoryCPUInfoNotification];
        }
    }
    
    //CPU温度
    if (m_tempCpuDict) {
        if ((self.trayType & STATUS_TYPE_TEP) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kTempCpuInfoNotification object:m_tempCpuDict];
        }
    }
    //风扇转速
    if (m_fanDict) {
        if ((self.trayType & STATUS_TYPE_FAN) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kFanCpuInfoNotification object:m_fanDict];
        }
    }
    
    //
    if (m_diskDict) {
        if ((self.trayType & STATUS_TYPE_DISK) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kDiskInfoNotification object:m_diskDict];
        }
    }
    
    if (m_cpuDict) {
        if ((self.trayType & STATUS_TYPE_CPU) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kStatCPUInfoNotification object:m_cpuDict];
        }
    }
    
    if (m_gpuDict) {
        if ((self.trayType & STATUS_TYPE_GPU) || (self.isTrayPageOpen)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kStatGpuInfoNotification object:m_gpuDict];
        }
    }
    
    // 发送到主程序
    //    [[QMPipeServer getInstance] sendCmd:statDict
    //                                command:QMPIPE_CMD_STATINFO];
}

#pragma mark-
#pragma mark get monitro data

- (void)batteryStateInfo
{
    if (!isExistBattery)
        return;
    NSDictionary *dic = [m_monitorFunction batteryStateInfo];
    if (!dic)
        return;
}

- (void)cpuInfo
{
    NSDictionary * result = [m_monitorFunction cpuStateInfo];
    if (result && [result isKindOfClass:[NSDictionary class]])
        m_cpuDict = result;
}

- (void)gpuInfo 
{
    NSDictionary * result = [m_monitorFunction gpuStateInfo];
    if (result && [result isKindOfClass:[NSDictionary class]])
        m_gpuDict = result;
}

- (void)fanInfo{
    __weak __typeof(self) weakSelf = self;
    [m_monitorFunction fanStateInfo:^(NSDictionary *info) {
        __strong __typeof(self) strongSelf = weakSelf;
        strongSelf->m_fanDict = info;
    }];
        
}

- (void)diskInfo
{
    NSDictionary * diskDict = [m_monitorFunction diskStateInfo];
    if (!diskDict)
        return;
    m_diskDict = diskDict;
}

- (NSDictionary*)getDiskInfoDict
{
    if (m_diskDict){
        return m_diskDict;
    }else{
        [self diskInfo];
        return m_diskDict;
    }
}


- (void)memoryInfo
{
    NSDictionary * result = [m_monitorFunction memoryStateInfo];
    if (result && [result isKindOfClass:[NSDictionary class]])
        m_memoryDict = result;
}

- (void)networkInfo
{
    NSDictionary * result = [m_monitorFunction netStateInfo:YES];
    if (result && [result isKindOfClass:[NSDictionary class]])
        m_networkDict = result;
}

- (void)tempInfo
{
    __weak __typeof(self) weakSelf = self;
    [m_monitorFunction tempSateInfo:^(NSDictionary *info) {
        __strong __typeof(self) strongSelf = weakSelf;
        strongSelf->m_tempCpuDict = info;
    }];
}

- (NSArray *)processInfo
{
    if (self.processSamplerLifeCounter == 0) {
        [storage sample];
    }
    self.processSamplerLifeCounter = 2;
    return storage.processInfoArray;
}
- (NSArray *)fetchCacheProcessInfo
{
    if (storage.originProcessInfoArray.count == 0) {
        return storage.processInfoArray;
    }
    return storage.originProcessInfoArray;
}
- (void)setProcessPortStat:(BOOL)isStat{
    [storage setProcessPortStat:isStat];
}

- (void)refreshProcessInfo
{
    [storage sample];
}

- (BOOL)isProcessSamplerOn
{
    return self.processSamplerLifeCounter > 0;
}
@end
