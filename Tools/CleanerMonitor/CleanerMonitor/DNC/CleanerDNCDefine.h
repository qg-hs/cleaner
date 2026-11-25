//
//  CleanerDNCDefine.h
//  CleanerMonitor
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#ifndef CleanerDNCDefine_h
#define CleanerDNCDefine_h

#define CleanerDNCRestartNotificationName @"CleanerDNCRestartNotificationName" // 重启当前进程
#define CleanerDNCHelpStartNotificationName @"CleanerDNCHelpStartNotificationName" // 帮助拉起通知

#define CleanerDNCRestartUserInfoTypeKey @"type" // CleanerDNCRestartType 在userInfo中的key值
typedef NS_ENUM(NSUInteger, CleanerDNCRestartType) {
    CleanerDNCRestartTypeMonitor = 1, // 重启monitor
};

#define CleanerDNCRestartUserInfoReasonKey @"reason" // CleanerDNCRestartReason 在userInfo中的key值
typedef NS_OPTIONS(NSUInteger, CleanerDNCRestartReason) {
    CleanerDNCRestartReasonFullDiskAccess = 1 << 0, // 完全磁盘访问权限
    CleanerDNCRestartReasonMonitorHasUpdated = 1 << 1, // monitor有更新
};

#endif /* CleanerDNCDefine_h */
