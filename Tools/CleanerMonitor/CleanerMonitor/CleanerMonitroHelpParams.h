//
//  CleanerMonitroHelpParams.h
//  CleanerMonitor
//

//  Copyright © 2018 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QMCoreFunction/McProcessInfoData.h>

@interface CleanerMonitroHelpParams : NSObject
+ (CleanerMonitroHelpParams*)sharedInstance;
@property NSInteger  startParamsCmd;
@property NSDictionary*  startParamsExtra;

@property (nonatomic, strong) NSMutableArray<McProcessInfoData*> *topMemoryArray;

- (void)startStatMemory;
- (void)stopStatMemory;

@end
