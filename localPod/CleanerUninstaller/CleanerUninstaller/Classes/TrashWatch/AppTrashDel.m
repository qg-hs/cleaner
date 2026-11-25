//
//  AppTrashDel.m
//  CleanerMonitor
//
//  
//  Copyright © 2018 Tencent. All rights reserved.
//

#import "AppTrashDel.h"
#import "LmTrashWatchUninstallWindowController.h"
#import "CleanerDaemonConst.h"
#import "LMLocalApp.h"
#import <QMCoreFunction/QMShellExcuteHelper.h>

@interface AppTrashDel() <McUninstallWindowControllerDelegate>{
    dispatch_queue_t checkQueue;
    NSMutableArray<LmTrashWatchUninstallWindowController*> *uninstallWndControllers;
}     

@end

@implementation AppTrashDel

// 废纸篓监控已收敛至常驻 CleanerMonitor 进程内 DispatchSource 监听；此方法仅清理历史遗留的 ~/Library/LaunchAgents/com.cleaner.trash.plist，避免系统设置出现重复 CleanerMonitor 条目。
+ (BOOL)enableTrashWatch:(BOOL)isEnable{
    NSLog(@"%s, enable:%d (in-process watcher active, cleaning legacy plist if present)", __FUNCTION__, isEnable);
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSArray<NSDictionary<NSString *, NSString *> *> *legacyItems = @[
        @{@"path": TRASH_MONITOR_LAUNCHD_PATH, @"label": TRASH_MONITOR_LAUNCHD_LABLE},
        @{@"path": @"/Library/LaunchAgents/com.tencent.Lemon.trash.plist", @"label": @"com.tencent.Lemon.trash"}
    ];
    for (NSDictionary<NSString *, NSString *> *item in legacyItems) {
        NSString *plistDstPath = [[@"~" stringByAppendingPathComponent:item[@"path"]] stringByExpandingTildeInPath];
        NSString *label = item[@"label"];
        if ([fileMgr fileExistsAtPath:plistDstPath]) {
            NSString *bootoutCmd = [NSString stringWithFormat:@"launchctl bootout gui/%u \"%@\" 2>/dev/null", getuid(), plistDstPath];
            system([bootoutCmd UTF8String]);
            [fileMgr removeItemAtPath:plistDstPath error:nil];
        }
        NSString *removeCmd = [NSString stringWithFormat:@"launchctl remove %@ 2>/dev/null", label];
        system([removeCmd UTF8String]);
    }
    return YES;
}

#pragma mark - check trash watcher enable

+ (BOOL)isTrashWatcherEnable {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:MONITOR_APP_BUNDLEID].count > 0;
}

+ (void)keepTrashWatcherAlive {
    [self enableTrashWatch:YES];
}

//+ (BOOL)enableTrashWatchFromMonitor:(BOOL)isEnable{
//    NSLog(@"%s, enable:%d", __FUNCTION__, isEnable);
//    NSString *cmd = nil;
//    NSString *plistDstPath = [[@"~" stringByAppendingPathComponent:TRASH_MONITOR_LAUNCHD_PATH_FROM_MONITOR] stringByExpandingTildeInPath];
//    NSFileManager *fileMgr = [NSFileManager defaultManager];
//    if (isEnable) {
//
//        NSString *srcPath = [DEFAULT_APP_PATH stringByAppendingPathComponent:@"Contents/Resources"];
//        srcPath = [srcPath stringByAppendingPathComponent:[TRASH_MONITOR_LAUNCHD_PATH_FROM_MONITOR lastPathComponent]];
//
//        [fileMgr removeItemAtPath:plistDstPath error:nil];
//
//        NSMutableDictionary *trashMonitorConfig = [[NSMutableDictionary alloc] initWithContentsOfFile:srcPath];
//
//        NSString *userTrashPath = [@"~/.Trash" stringByExpandingTildeInPath];
//        [trashMonitorConfig setObject:@[userTrashPath] forKey:@"WatchPaths"];
//        if (![trashMonitorConfig writeToFile:plistDstPath atomically:NO]) {
//            NSLog(@"trash plist write to ~/Library/LaunchAgents/com.cleaner.monitor.trash.plist MONITOR Monitor failed: dstPath:%@, src path is %@", plistDstPath, srcPath);
//            NSLog(@"print  trashMonitorConfig ....");
//            for(NSString *key in [trashMonitorConfig allKeys]) {
//                NSLog(@"%@",[trashMonitorConfig objectForKey:key]);
//            }
//            return NO;
//        }
//
//        if(![fileMgr fileExistsAtPath:plistDstPath]){
//            NSLog(@"after write,but plist not exist ");
//            return NO;
//        }
//
//        cmd = [NSString stringWithFormat:@"launchctl load  %@", plistDstPath];
//        system([cmd UTF8String]);
//    } else {
//        cmd = [NSString stringWithFormat:@"launchctl remove %@", TRASH_MONITOR_LAUNCHD_LABLE_FROM_MONITOR];
//        system([cmd UTF8String]);
//        [fileMgr removeItemAtPath:plistDstPath error:nil];
//    }
//    return YES;
//}

- (instancetype)init
{
    self = [super init];
    if (self) {
        checkQueue = dispatch_queue_create("checkQueue", NULL);
    }
    return self;
}

- (void)delTrashOfApps:(NSArray *)apps {
    if ( [apps count] == 0)
        return;
    
    dispatch_async(checkQueue, ^{
        NSString *trashPath = [@"~/.Trash" stringByExpandingTildeInPath];
        NSMutableArray<LMLocalApp *> *appTrashs = [[NSMutableArray alloc] init];
        for (NSString *appItem in apps) {
            NSString *appPath = [trashPath stringByAppendingPathComponent:appItem];
            
            NSTimeInterval now = [[[NSDate alloc]init] timeIntervalSince1970];
            NSLog(@"delTrashOfApps start to scan %@ trash leftover, start time is %f ", appPath, now);
            NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
            if (!appBundle || !appBundle.bundleIdentifier){
                NSLog(@"delTrashOfApps %@ no need show scan result because appBundle or identifier not valid", appPath );
                continue;
            }
            
            LMLocalApp *localSoft = [[LMLocalApp alloc] initWithPath:appPath];
            if (!localSoft){
                NSLog(@"delTrashOfApps %@ no need show scan result because can't init LMLocalApp ", appPath);
                continue;
            }
            [localSoft scanFileItems:AppTrashLeftover];
            if ([localSoft fileItemCount] < 1){
                NSLog(@"delTrashOfApps %@ no need show scan result because no trash leftover ", appPath);
                continue;
            }
            [appTrashs addObject:localSoft];
        }
        
        if (appTrashs.count > 0)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showUninstaller:appTrashs];
                NSTimeInterval showTime = [[[NSDate alloc]init] timeIntervalSince1970];
                NSArray *appBundles = [appTrashs valueForKey:@"bundleID"];
                NSLog(@"delTrashOfApps end scan trash leftover, end time is %f , show apps is %@", showTime , [appBundles componentsJoinedByString:@","]);

            });
        }
    });
}

- (void)showUninstaller:(NSArray<LMLocalApp *> *)softs
{
    if (!uninstallWndControllers)
    {
        uninstallWndControllers  = [NSMutableArray array];
    }
    
    for(LMLocalApp *itemApp in softs){
        LmTrashWatchUninstallWindowController *uninstallWndController = [[LmTrashWatchUninstallWindowController alloc] init];
        [uninstallWndControllers addObject:uninstallWndController];
        
        uninstallWndController.delegate = self;
        uninstallWndController.soft = itemApp;
        [uninstallWndController show];
    }
}

#pragma mark - McUninstallWindowControllerDelegate

- (void)uninstallFinished:(id)sender
{
    if([sender isKindOfClass:LmTrashWatchUninstallWindowController.class]){
        LmTrashWatchUninstallWindowController *uninstallFinshWindow = sender;
        [uninstallWndControllers removeObject:uninstallFinshWindow];
    }
}

@end
