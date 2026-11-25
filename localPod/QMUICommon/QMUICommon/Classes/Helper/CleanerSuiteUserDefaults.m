//
//  CleanerSuiteUserDefaults.m
//  CleanerASMonitor
//
//  
//  Copyright © 2019 Tencent. All rights reserved.
//

#import "CleanerSuiteUserDefaults.h"

#define MAIN_CLEANER_GROUP_ID @"group.com.cleaner.app"

@implementation CleanerSuiteUserDefaults

+(BOOL)getBool:(NSString *)key{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MAIN_CLEANER_GROUP_ID];
    return [defaults boolForKey:key];
}

+(void)putBool:(BOOL )value withKey:(NSString *)key{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MAIN_CLEANER_GROUP_ID];
    [defaults setBool:value forKey:key];
    [defaults synchronize];
}

+(NSData *) getData:(NSString *)key{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MAIN_CLEANER_GROUP_ID];
    return [defaults objectForKey:key];
}

+(void)putData:(NSData *)value withKey:(NSString *)key{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MAIN_CLEANER_GROUP_ID];
    [defaults setObject:value forKey:key];
    [defaults synchronize];
}

+(void)putString:(NSString *)value withKey:(NSString *)key{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MAIN_CLEANER_GROUP_ID];
    [defaults setObject:value forKey:key];
    [defaults synchronize];
}

+(NSString *) getString:(NSString *)key{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MAIN_CLEANER_GROUP_ID];
    return [defaults objectForKey:key];
}

@end
