//
//  CleanerDNCClient.m
//  Cleaner
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import "CleanerDNCClient.h"

@implementation CleanerDNCClient

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance {
    static CleanerDNCClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)restart:(CleanerDNCRestartType)type reason:(CleanerDNCRestartReason)reason {
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:CleanerDNCRestartNotificationName object:nil userInfo:@{CleanerDNCRestartUserInfoTypeKey:@(type), CleanerDNCRestartUserInfoReasonKey: @(reason)} deliverImmediately:YES];
}

@end
