//
//  LMCleanerXPCProtocol.h
//  QMCoreFunction
//

//  Copyright © 2018年 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "McPipeStruct.h"

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol LMCleanerXPCProtocol <NSObject>

// Replace the API of this protocol with an API appropriate to the service you are vending.
- (void)sendDataToCleaner:(NSData *)paramData withReply:(void (^)(NSData *))replyData;
- (void)sendDictionaryToCleaner:(NSDictionary *)paramDic withReply:(void (^)(NSDictionary *))replyDic;

@end
