//
//  CleanerMonitorDNCClient.h
//  CleanerMonitor
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CleanerMonitorDNCClient : NSObject

+ (instancetype)sharedInstance;

// 让其他进程，目前是cleaner主进程帮助重启cleanerMonitor
- (void)helpStart;

@end

NS_ASSUME_NONNULL_END
