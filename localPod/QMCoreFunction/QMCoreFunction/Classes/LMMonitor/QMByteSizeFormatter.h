//
//  QMMiniWindowFileSizeFormatter.h
//  CleanerMonitor
//
//  
//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface QMByteSizeFormatter : NSFormatter
@property (strong, nonatomic) NSString *suffix;
+ (instancetype)networkSpeedFormatter;
@end
