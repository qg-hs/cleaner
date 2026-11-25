//
//  CleanerDNCServer.m
//  CleanerMonitor
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import "CleanerMonitorDNCServer.h"
#import "CleanerMonitorDNCClient.h"
#import "CleanerDNCDefine.h"
#import <QMCoreFunction/QMFullDiskAccessManager.h>

@implementation CleanerMonitorDNCServer

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance {
    static CleanerMonitorDNCServer *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)addServer {
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(restartNotification:) name:CleanerDNCRestartNotificationName object:nil];
}

- (void)restartNotification:(NSNotification *)notify {
    CleanerDNCRestartType type = [notify.userInfo[CleanerDNCRestartUserInfoTypeKey] unsignedIntegerValue];
    CleanerDNCRestartReason reason = [notify.userInfo[CleanerDNCRestartUserInfoReasonKey] unsignedIntegerValue];
    
    if (type == CleanerDNCRestartTypeMonitor) {
        if (reason & CleanerDNCRestartReasonFullDiskAccess) {
            if ([QMFullDiskAccessManager getFullDiskAuthorationStatus] != QMFullDiskAuthorationStatusAuthorized) {
                // 无完全磁盘访问权限，无法拉起自己。让其他进程帮助拉起自己
                [self helpRestart];
                return;
            }
        }
        if (reason & CleanerDNCRestartReasonMonitorHasUpdated) {
            // 检查运行中的monitor和硬盘中的monitor的版本号是否一致，如果不一致则重启
            BOOL restart = [self restartForVersionIfNeeded];
            if (restart) {
                [self helpRestart];
                return;
            }
        }
    }
}

- (BOOL)restartForVersionIfNeeded {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *localPlistPath = [mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"];
    if (localPlistPath) {
        NSDictionary *localPlist = [NSDictionary dictionaryWithContentsOfFile:localPlistPath];
        if (localPlist) {
            NSString *mainVersion = mainBundle.infoDictionary[@"CFBundleVersion"];
            NSString *localVersion = localPlist[@"CFBundleVersion"];
            if (mainVersion && localVersion) {
                return ![mainVersion isEqualToString:localVersion];
            }
        }
    }
    return NO;
}

- (void)helpRestart {
    [[CleanerMonitorDNCClient sharedInstance] helpStart];
    [NSApp terminate:nil];
}

@end
