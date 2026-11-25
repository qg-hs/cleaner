//
//  main.m
//  CleanerMonitor
//
//  Created by tanhao on 14-7-1.
//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "CleanerMonitroHelpParams.h"
#import "CleanerDaemonConst.h"
#import "TrashCheckMonitor.h"
#import "LMUtilFunc.h"
#import <QMUICommon/SharedPrefrenceManager.h>
#import <QMCoreFunction/QMShellExcuteHelper.h>

CFAbsoluteTime g_startTime = 0;

static BOOL hasOtherRunningMonitorInstance(void) {
    pid_t selfPid = [[NSProcessInfo processInfo] processIdentifier];
    NSArray<NSRunningApplication *> *runnings = [NSRunningApplication runningApplicationsWithBundleIdentifier:MONITOR_APP_BUNDLEID];
    for (NSRunningApplication *app in runnings) {
        if (app.processIdentifier != selfPid && !app.isTerminated) {
            return YES;
        }
    }
    return NO;
}

int main(int argc, const char * argv[])
{
//    trashSizeCheck();
#ifndef DEBUG
    redirctNSlog();
#endif
    // 记录启动时间
    g_startTime = CFAbsoluteTimeGetCurrent();
    
#ifdef DEBUG
    return NSApplicationMain(argc, argv);
#endif
    
    
    // command line
    for (int i=0; i<argc; i++)
    {
        NSLog(@"\n\n\n\n"); // 分隔之前的日志
        NSLog(@"CleanerMonitor main: argc=%d;argv[%d]=%@", argc, i, [NSString stringWithUTF8String:argv[i]]);
    }
    
    //
    if (argc==2)
    {
        if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", CleanerAppRunningNormal]])
        {
            [[CleanerMonitroHelpParams sharedInstance] setStartParamsCmd:CleanerAppRunningNormal];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", CleanerAppRunningFirstInstall]])
        {
            [[CleanerMonitroHelpParams sharedInstance] setStartParamsCmd:CleanerAppRunningFirstInstall];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", CleanerAppRunningReInstallAndMonitorExist]])
        {
            [[CleanerMonitroHelpParams sharedInstance] setStartParamsCmd:CleanerAppRunningReInstallAndMonitorExist];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", CleanerAppRunningReInstallAndMonitorNotExist]])
        {
            [[CleanerMonitroHelpParams sharedInstance] setStartParamsCmd:CleanerAppRunningReInstallAndMonitorNotExist];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", CleanerMonitorRunningOSBoot]])
        {
            [[CleanerMonitroHelpParams sharedInstance] setStartParamsCmd:CleanerMonitorRunningOSBoot];
        }
        else if ([[NSString stringWithUTF8String:argv[1]] isEqualToString:[NSString stringWithFormat:@"%lu", CleanerMonitorRunningMenu]])
        {
            [[CleanerMonitroHelpParams sharedInstance] setStartParamsCmd:CleanerMonitorRunningMenu];
        }
        else if(strcmp(argv[1], kTrashChanged_cstr) == 0){
            [TrashCheckMonitor performTrashCheckAndSizeCheck];
            usleep(100 * 1000);
            return 0;
        }
        else
        {
            return 0;
        }
    }
    else
    {
        return 0;
    }
    
    if (hasOtherRunningMonitorInstance()) {
        // 给 helpRestart 等重启场景的旧进程留出退出时间窗
        usleep(300 * 1000);
        if (hasOtherRunningMonitorInstance()) {
            NSLog(@"CleanerMonitor already running, exiting duplicate instance");
            return 0;
        }
    }
    
    return NSApplicationMain(argc, argv);
}


