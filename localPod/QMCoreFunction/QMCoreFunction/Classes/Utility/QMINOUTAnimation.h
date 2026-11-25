//
//  QMINOUTAnimation.h
//  Cleaner
//
//  
//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface QMINOUTAnimation : NSObject

+ (void)getOut:(NSView *)view completionBlock:(void(^)(void))block;
+ (void)getIn:(NSView *)view completionBlock:(void(^)(void))block;

@end
