//
//  LMCleanerXPCClient.m
//  QMCoreFunction
//
//  
//  Copyright © 2018年 Tencent. All rights reserved.
//

#import "LMCleanerXPCClient.h"
#import "LMXpcClientManager.h"

@implementation LMCleanerXPCClient

// Replace the API of this protocol with an API appropriate to the service you are vending.
- (void)sendDataToCleaner:(NSData *)paramData withReply:(void (^)(NSData *))replyData{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[LMXpcClientManager sharedInstance].delegate respondsToSelector:@selector(receiveData:)]) {
            [[LMXpcClientManager sharedInstance].delegate receiveData:paramData];
        }
    });
}
- (void)sendDictionaryToCleaner:(NSDictionary *)paramDic withReply:(void (^)(NSDictionary *))replyDic{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[LMXpcClientManager sharedInstance].delegate respondsToSelector:@selector(receiveDictionary:)]) {
            [[LMXpcClientManager sharedInstance].delegate receiveDictionary:paramDic];
        }
    });
}

@end
