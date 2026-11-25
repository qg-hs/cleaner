//
//  CleanerStartUpParams.h
//  Cleaner
//

//  Copyright © 2018 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

#define CLEANER_PARAMS_CMD_START_OWL_WINDOW           0x1
#define CLEANER_PARAMS_CMD_START_PREFERENCES_WINDOW   0x2

extern NSString const *kMonitorRuning;

@interface CleanerStartUpParams : NSObject{
    
}
@property (assign) NSInteger  paramsCmd;
@property (strong) NSMutableDictionary*  paramsExtra;

+ (CleanerStartUpParams*)sharedInstance;

@end
