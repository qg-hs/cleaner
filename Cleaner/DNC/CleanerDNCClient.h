//
//  CleanerDNCClient.h
//  Cleaner
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CleanerDNCDefine.h"

NS_ASSUME_NONNULL_BEGIN

@interface CleanerDNCClient : NSObject

+ (instancetype)sharedInstance;

- (void)restart:(CleanerDNCRestartType)type reason:(CleanerDNCRestartReason)reason;

@end

NS_ASSUME_NONNULL_END
