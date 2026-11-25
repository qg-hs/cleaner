//
//  CleanerMonitorDNCClient.m
//  CleanerMonitor
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import "CleanerMonitorDNCClient.h"
#import "CleanerDNCDefine.h"

@implementation CleanerMonitorDNCClient

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance {
    static CleanerMonitorDNCClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)helpStart {
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    NSTimeInterval delay = 0.1;
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:appPath, @"appPath", @(delay), @"delay", nil];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:CleanerDNCHelpStartNotificationName object:nil userInfo:userInfo deliverImmediately:YES];
}

@end
