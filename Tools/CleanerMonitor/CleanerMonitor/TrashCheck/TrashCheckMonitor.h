//
//  TrashCheckMonitor.h
//  CleanerMonitor
//
//  Created by junior on 2019/10/31.
//  Copyright © 2019 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrashCheckMonitor : NSObject

+ (void)startTrashWatcher;
+ (void)stopTrashWatcher;
+ (void)performTrashCheckAndSizeCheck;

- (NSArray *)getNewTashApps;

-(BOOL)isTrashItemsChanged;

@end

NS_ASSUME_NONNULL_END
