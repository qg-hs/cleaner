//
//  QMNetworkSpeedFormatter.m
//  CleanerMonitor
//
//  
//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import "QMNetworkSpeedFormatter.h"
#import "NSString+Extension.h"

@implementation QMNetworkSpeedFormatter
- (NSString *)stringForObjectValue:(NSNumber *)obj
{
    if (![obj isKindOfClass:NSNumber.class]) {
        return @"";
    }
    NSString *ret = [NSString stringFromNetSpeed:[obj longLongValue]];
    return ret;
}
@end
