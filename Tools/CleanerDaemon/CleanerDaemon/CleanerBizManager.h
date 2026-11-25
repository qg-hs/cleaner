//
//  CleanerBizManager.h
//  CleanerDaemon
//

//  Copyright © 2018年 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CleanerBizManager : NSObject

@property (nonatomic, weak) NSXPCConnection *cleanerCennection;
@property (nonatomic, weak) NSXPCConnection *monitorCennection;

+ (CleanerBizManager *)shareInstance;

@end
