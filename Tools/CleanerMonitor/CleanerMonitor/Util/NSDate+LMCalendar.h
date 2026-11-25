//
//  NSDate+LMCalendar.h
//  CleanerMonitor
//
//  Copyright © 2025 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSDate (LMCalendar)

- (BOOL)lm_isSameDayAsDate:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
