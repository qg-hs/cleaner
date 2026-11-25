//
//  main.m
//  Cleaner
//

//  Copyright © 2018  Tencent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#ifndef APPSTORE_VERSION
#import "CleanerStartUpParams.h"
#import "CleanerDaemonConst.h"
#import <QMCoreFunction/NSBundle+LMLanguage.h>
#import <QMCoreFunction/LanguageHelper.h>
#endif
#import "AppDelegate.h"

int main(int argc, const char * argv[]) {
    NSLog(@"Cleaner main: %d", argc);
    
#ifndef APPSTORE_VERSION
    NSString *language = [LanguageHelper getCurrentUserLanguage];
    if(language != nil){
        //hook 主工程多语言
        [NSBundle setLanguage:language bundle:[NSBundle mainBundle]];
    }
    if (argc == 2) {
        NSLog(@"Cleaner main1: %@", [NSString stringWithUTF8String:argv[1]]);
        
        if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:@"1"]) {
            [[CleanerStartUpParams sharedInstance] setParamsCmd:1];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:@"2"])
        {
            [[CleanerStartUpParams sharedInstance] setParamsCmd:2];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:@"1030"]) /// monitor打开磁盘空间分析
        {
            [[CleanerStartUpParams sharedInstance] setParamsCmd:1030];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", (unsigned long)CleanerAppRunningReInstallAndMonitorExist]])
        {
            [[CleanerStartUpParams sharedInstance] setParamsCmd:CleanerAppRunningReInstallAndMonitorExist];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", (unsigned long)CleanerAppRunningReInstallAndMonitorNotExist]])
        {
            [[CleanerStartUpParams sharedInstance] setParamsCmd:CleanerAppRunningReInstallAndMonitorNotExist];
        }
    }
#endif

    return NSApplicationMain(argc, argv);
}

