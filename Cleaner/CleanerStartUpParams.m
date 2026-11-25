//
//  CleanerStartUpParams.m
//  Cleaner
//

//  Copyright © 2018 Tencent. All rights reserved.
//

#import "CleanerStartUpParams.h"

NSString const *kMonitorRuning = @"kMonitorRuning";
@implementation CleanerStartUpParams
+ (CleanerStartUpParams*)sharedInstance
{
    static CleanerStartUpParams *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CleanerStartUpParams alloc] init];
    });
    return instance;
}
- (id)init{
    self = [super init];
    if (self) {
        _paramsCmd = 0;
        _paramsExtra = [[NSMutableDictionary alloc] init];
    }
    return self;
}
@end
