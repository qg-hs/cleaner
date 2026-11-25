//
//  CleanerDNCServier.h
//  Cleaner
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CleanerDNCServier : NSObject

+ (instancetype)sharedInstance;

- (void)addServer;

@end

NS_ASSUME_NONNULL_END
