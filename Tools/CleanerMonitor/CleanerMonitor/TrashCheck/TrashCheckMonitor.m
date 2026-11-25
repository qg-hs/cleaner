//
//  TrashCheckMonitor.m
//  CleanerMonitor
//

//  Copyright © 2019 Tencent. All rights reserved.
//

#import "TrashCheckMonitor.h"
#import <AppKit/AppKit.h>
#import <sys/stat.h>
#import <fcntl.h>
#import "CleanerDaemonConst.h"
#import <QMUICommon/SharedPrefrenceManager.h>
#import <QMCoreFunction/NSFileManager+Extension.h>

static dispatch_queue_t sTrashWatchQueue = nil;
static dispatch_source_t sTrashWatchSource = nil;
static NSUInteger sTrashWatchGeneration = 0;

@implementation TrashCheckMonitor

+ (dispatch_queue_t)sharedWatchQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sTrashWatchQueue = dispatch_queue_create("com.cleaner.monitor.trashWatch", DISPATCH_QUEUE_SERIAL);
    });
    return sTrashWatchQueue;
}

+ (BOOL)isMonitorRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:MONITOR_APP_BUNDLEID].count > 0;
}

+ (BOOL)runTrashCheck {
    TrashCheckMonitor *trashCheck = [[TrashCheckMonitor alloc] init];
    NSArray *appTrashItems = [trashCheck getNewTashApps];

    BOOL isTrashWatchEnable = [SharedPrefrenceManager getBool:IS_ENABLE_TRASH_WATCH];
    if (!isTrashWatchEnable) {
        return NO;
    }

    if (appTrashItems.count > 0) {
        NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
        [info setObject:appTrashItems forKey:@"items"];
        [info setObject:@"this notify is from monitor" forKey:@"from"];

        if ([self isMonitorRunning]) {
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_TRASH_CHANGE_TO_MONITOR
                                                                           object:nil
                                                                         userInfo:info
                                                                          options:NSNotificationPostToAllSessions | NSDistributedNotificationDeliverImmediately];
        }
        return YES;
    }
    return NO;
}

+ (void)runTrashSizeCheck {
    TrashCheckMonitor *trashCheck = [[TrashCheckMonitor alloc] init];
    if (![trashCheck isTrashItemsChanged]) {
        return;
    }

    Boolean isTrashWatchHasSet = false;
    NSInteger watchStatus = 0;
    BOOL isTrashSizeWatchEnable = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)(IS_ENABLE_TRASH_SIZE_WATCH), (__bridge CFStringRef)(MAIN_APP_BUNDLEID), &isTrashWatchHasSet);
    if (!isTrashWatchHasSet) {
        isTrashSizeWatchEnable = YES;
        watchStatus = V_TRASH_SIZE_WATCH_WHEN_OVER_SIZE;
    }

    if (!isTrashSizeWatchEnable) {
        return;
    }

    if (watchStatus == 0) {
        watchStatus = CFPreferencesGetAppIntegerValue((__bridge CFStringRef)(K_TRASH_SIZE_WATCH_STATUS), (__bridge CFStringRef)(MAIN_APP_BUNDLEID), &isTrashWatchHasSet);
        if (!isTrashWatchHasSet) {
            watchStatus = V_TRASH_SIZE_WATCH_WHEN_OVER_SIZE;
        }
    }

    NSInteger thresholdSize = 1024;
    Boolean isThresholdSizeHasSet = false;
    if (watchStatus == V_TRASH_SIZE_WATCH_WHEN_DELETE_FILE) {
        thresholdSize = 0;
    } else {
        thresholdSize = CFPreferencesGetAppIntegerValue((__bridge CFStringRef)TRASH_SIZE_WATCH_THRESHOLD, (__bridge CFStringRef)(MAIN_APP_BUNDLEID), &isThresholdSizeHasSet);
        if (!isThresholdSizeHasSet) {
            thresholdSize = 1024;
        }
    }

    NSString *path = [@"~/.Trash" stringByExpandingTildeInPath];
    float actualSize = 0;
    BOOL resultStatus = NO;
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/du"];
        task.arguments = @[@"-sk", path];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSPipe pipe];
        if ([task launchAndReturnError:nil]) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSRange range = [result rangeOfString:@"\t"];
            if (range.location != NSNotFound) {
                NSString *subString = [result substringToIndex:range.location];
                if (subString.length > 0) {
                    actualSize = [subString floatValue] * 1024.0f;
                    resultStatus = YES;
                }
            }
        }
    } @catch (NSException *exception) {
        resultStatus = NO;
    }

    if (!resultStatus) {
        actualSize = (float)[[NSFileManager defaultManager] fileSizeAtPath:path];
    }

    if (actualSize >= thresholdSize * 1024.0f * 1024.0f) {
        if ([self isMonitorRunning]) {
            NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
            [info setObject:@(actualSize) forKey:@"trashSize"];
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_TRASH_SIZE_OVER_THRESHOLD
                                                                           object:nil
                                                                         userInfo:info
                                                                          options:NSNotificationPostToAllSessions | NSDistributedNotificationDeliverImmediately];
        }
    }
}

+ (void)performTrashCheckAndSizeCheck {
    [self runTrashCheck];
    [self runTrashSizeCheck];
}

+ (void)armVnodeWatcherOnQueue:(dispatch_queue_t)queue {
    if (sTrashWatchSource) {
        dispatch_source_cancel(sTrashWatchSource);
        sTrashWatchSource = nil;
    }

    NSString *trashPath = [@"~/.Trash" stringByExpandingTildeInPath];
    int fd = open([trashPath fileSystemRepresentation], O_EVTONLY);
    if (fd < 0) {
        NSLog(@"[TrashWatch] failed to open %@ for vnode watch (errno=%d)", trashPath, errno);
        return;
    }

    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,
                                                      (uintptr_t)fd,
                                                      DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
                                                      queue);
    if (!source) {
        close(fd);
        return;
    }

    sTrashWatchSource = source;
    dispatch_source_set_event_handler(source, ^{
        unsigned long flags = dispatch_source_get_data(source);
        if (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) {
            if (sTrashWatchSource == source) {
                dispatch_source_cancel(source);
                sTrashWatchSource = nil;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), queue, ^{
                [self armVnodeWatcherOnQueue:queue];
            });
        }

        sTrashWatchGeneration++;
        NSUInteger gen = sTrashWatchGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), queue, ^{
            if (gen != sTrashWatchGeneration) {
                return;
            }
            [self performTrashCheckAndSizeCheck];
        });
    });

    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    dispatch_resume(source);
    NSLog(@"[TrashWatch] started in-process vnode watcher on %@", trashPath);
}

+ (void)startTrashWatcher {
    dispatch_queue_t queue = [self sharedWatchQueue];
    dispatch_async(queue, ^{
        // 初始化基线记录，确保首次启动后拖入废纸篓的应用能立即被识别
        TrashCheckMonitor *baseline = [[TrashCheckMonitor alloc] init];
        if (![baseline getOldTrashApps]) {
            [baseline saveTrashApps:[baseline getTrashApps]];
        }
        if ([SharedPrefrenceManager getInteger:OLD_TRASH_SIZE] == 0) {
            [baseline isTrashItemsChanged];
        }
        [self armVnodeWatcherOnQueue:queue];
    });
}

+ (void)stopTrashWatcher {
    dispatch_queue_t queue = [self sharedWatchQueue];
    dispatch_sync(queue, ^{
        sTrashWatchGeneration++;
        if (sTrashWatchSource) {
            dispatch_source_cancel(sTrashWatchSource);
            sTrashWatchSource = nil;
        }
    });
}

- (NSString *)getWatchPath {
    return [@"~/.Trash" stringByExpandingTildeInPath];
}

- (NSString *)getTrashLogFile {
    NSString *path = [[@"~" stringByAppendingPathComponent:APP_SUPPORT_PATH2] stringByAppendingPathComponent:@"trashLog"];
    return [path stringByExpandingTildeInPath];
}

- (NSArray *)getOldTrashApps {
    NSArray *appTrashItem = [NSArray arrayWithContentsOfFile:[self getTrashLogFile]];
//    NSLog(@"[TrashDel] oldTrashApps: %@", appTrashItem);
    return appTrashItem;
}

- (void)saveTrashApps:(NSArray *)items {
    if (!items) {
        items = [[NSArray alloc] init];
    }
    
    if (items) {
        NSString *trashLog = [self getTrashLogFile];
        NSString *parentDir = [trashLog stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
//        NSLog(@"[TrashDel] wrtieTrashLog %@", trashLog);
        [items writeToFile:trashLog atomically:YES];
    }
}

- (NSArray *)getTrashApps {
    NSString *trashPath = [self getWatchPath];
    NSArray *trashItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashPath error:nil];
//    NSLog(@"[TrashDel] trashItems:%@", trashItems);
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app' "];
    NSArray *appTrashItems = [trashItems filteredArrayUsingPredicate:predicate];
    return appTrashItems;
}

-(BOOL)isTrashItemsChanged{
    NSInteger oldTrashSize = [SharedPrefrenceManager getInteger:OLD_TRASH_SIZE];
//    NSLog(@"%s,old trash size : %ld",__FUNCTION__, (long)oldTrashSize);
    NSString *trashPath = [self getWatchPath];
    NSArray *trashItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:trashPath error:nil];
    NSInteger newTrashSize = trashItems.count;
//    NSLog(@"%s,new trash size : %ld",__FUNCTION__, (long)newTrashSize);
    [SharedPrefrenceManager putInteger:newTrashSize withKey:OLD_TRASH_SIZE];
    if(newTrashSize > oldTrashSize)
        return YES;
    return NO;
}



//检测是否系统重新命名的文件
//如果移到垃圾桶时有相同的文件，会将旧的重命名，在后面加上时间，例如 xxxx.app会变成 xxxx 下午1.30.23.app
//这样检测出来的实际上就是旧的重命名后的app

// 这里的判断不准:原因: 1.不同系统下样式不同. 2.时间字符串的长度不同.(长度为7或者8)
//       DerivedData 下午8.53.20
//       NetworkExtension 15.04.30 PM.app
//
- (BOOL) isSystemRenameFileName:(NSString *)fileName {
    NSString *name = [self removeAppExtensionOf:fileName];
    NSInteger len = [name length];
    // pattern like "1.12.30"
    if (len <= 7) {
        return NO;
    }
    NSString *endStr = [name substringFromIndex:len - 7];
//    NSLog(@"[TrashDel] %s endstr:%@", __FUNCTION__, endStr);
    NSString *regx = @"\\d\\.\\d\\d\\.\\d\\d";
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regx];
    BOOL isMatch = [pred evaluateWithObject:endStr];
//    NSLog(@"[TrashDel] %s fileName: %@, match:%d", __FUNCTION__, fileName, isMatch);
    return isMatch;
}

- (NSString *)truncTimeStrFromName:(NSString *)fileName {
    if (![self isSystemRenameFileName:fileName])
        return fileName;
    NSString *name = [self removeAppExtensionOf:fileName];
    
    NSArray *strArray = [name componentsSeparatedByString:@" "];
    NSString *nameWithOutTime = @"";
    if ([strArray count] == 1) {
        nameWithOutTime = name;
    } else {
        for (int i = 0; i < [strArray count] - 1; i++) {
            nameWithOutTime = [nameWithOutTime stringByAppendingString:strArray[i]];
        }
    }
    
    NSString* ret = [self appendAppExtensionTo:nameWithOutTime];
    
//    NSLog(@"[TrashDel] %s, return str:%@", __FUNCTION__, ret);
    return ret;
}



- (NSString *)removeAppExtensionOf:(NSString *)fileName {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app' "];
    BOOL isEndWithApp = [predicate evaluateWithObject:fileName];
    if (isEndWithApp) {
        return [fileName substringToIndex:[fileName length] - 4];
    }
    return fileName;
}

- (NSString *)appendAppExtensionTo:(NSString *)appName {
    return [appName stringByAppendingString:@".app"];
}


// 找出最新的删除 App.
- (NSArray *)getNewTashApps {
//    NSLog(@"%s", __FUNCTION__);
    NSArray *oldTrashApps = [self getOldTrashApps];  //写在 ~/Library/Application Support/com.cleaner.app/trashLog
    NSArray *curTrashApps = [self getTrashApps];
    [self saveTrashApps:curTrashApps];
    // 初次启动
    // oldTrashApps为nil, 代表应用刚启动第一次检测，所以直接返回nil
    // oldTrashApps为大小为0的array，代表上一次检测垃圾桶里没有app
    if (!oldTrashApps) {
//        NSLog(@"%s oldTrash is nil, stop scan", __FUNCTION__);
        return nil;
    }
    
    // 无新增
    if (curTrashApps.count == 0) {
        return nil;
    }
    
    // 有值无变化
    if (oldTrashApps && curTrashApps) {
        NSSet *oldTrashAppsSet = [NSSet setWithArray:oldTrashApps];
        NSSet *curTrashAppsSet = [NSSet setWithArray:curTrashApps];
        if ([oldTrashAppsSet isEqualToSet:curTrashAppsSet]) {
            return nil;
        }
    }

//    NSLog(@"%s oldTrash Apps is \n %@", __FUNCTION__,  [oldTrashApps componentsJoinedByString:@",  "]);
//    NSLog(@"%s nowTrash Apps is \n %@", __FUNCTION__,  [curTrashApps componentsJoinedByString:@",  "]);
    
    NSMutableArray *newApps = [[NSMutableArray alloc] init];
    
    NSMutableArray<NSString*> *oldTrashContainsApps = [NSMutableArray array];
    for (NSString *newItem in curTrashApps) {
        
        // 过滤老应用
        if ([oldTrashApps containsObject:newItem]) {
            [oldTrashContainsApps addObject:newItem];
            continue;
        }
        
        NSString *appPath = [[self getWatchPath] stringByAppendingPathComponent:newItem];
        NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
        
        if (!appBundle || !appBundle.bundleIdentifier) {
//            NSLog(@"%s stop uninstall this app:%@ is valid, appBundle is %@", __FUNCTION__, newItem, appBundle);
            continue;
        }
        
        if ([appBundle.bundleIdentifier hasPrefix:@"com.apple."]
            || [appBundle.bundleIdentifier hasPrefix:MAIN_APP_BUNDLEID]
            || [appBundle.bundleIdentifier hasPrefix:MONITOR_APP_BUNDLEID])
        {
//            NSLog(@"%s stop uninstall this type app:%@, id:%@ ", __FUNCTION__, newItem, appBundle.bundleIdentifier);
            continue;
        }
        
        // 当该bundleID的软件仍然在运行，不处理
        NSArray *runApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:appBundle.bundleIdentifier];
        if (runApps.count > 0){
//            NSLog(@"%s stop uninstall this app:%@, id:%@ because still running", __FUNCTION__, newItem, appBundle.bundleIdentifier);
            continue;
        }
        

        // 当还安装有同bundleID的软件(且未被删除)，不处理 =>注意有些 DMG 挂载后,会生成 /Volumes/xxxx/abc.app 这种情形下abc.app删除时不应该算还存在其
        //osascript -e "POSIX path of (path to application id \"com.iqiyi.player \")" 可以用shell的命令获取此 bundleId 的软件的安装位置.
        NSString *otherPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:appBundle.bundleIdentifier];
        NSPredicate *dmgPathPredicate = [NSPredicate predicateWithFormat:@"SELF MATCHES[c] %@", @"/Volumes/[^/]*/[^/]*[.]app"];
        if (otherPath
            &&![otherPath hasPrefix:[self getWatchPath]]
              && ![dmgPathPredicate evaluateWithObject:otherPath]){
//            NSLog(@"%s stop uninstall this app:%@, id:%@ because have other app at: %@", __FUNCTION__, newItem, appBundle.bundleIdentifier, otherPath);
            continue;
        }
        
        NSString *trashPath = [self getWatchPath];
        NSURL *itemUrl = [[NSURL alloc]initFileURLWithPath:[trashPath stringByAppendingPathComponent:newItem]];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if(![fileManager fileExistsAtPath:[itemUrl path]]){
//            NSLog(@"%s file not exist %@ ", __FUNCTION__, newItem);
            continue;
        }
        [newApps addObject:newItem];
//        struct stat fileStat;
//        if (lstat([itemUrl fileSystemRepresentation], &fileStat) == noErr){
//            struct timespec atime = fileStat.st_atimespec;
//
//            NSTimeInterval now = [[[NSDate alloc] init] timeIntervalSince1970];
//            if( fabs(now - atime.tv_sec) < 10){
//                [newApps addObject:newItem];
//            }else{
//                NSLog(@"%s file %@ ctime changed over 10s ,now is %f, atime is %ld", __FUNCTION__, [itemUrl path] , now, (long)atime.tv_sec);
//            }
//        }else{
//             NSLog(@"%s lstat() called error", __FUNCTION__);
//        }
    }
    
    if(oldTrashContainsApps.count > 0){
//        NSLog(@"oldTrashContainsApps:%@", [oldTrashContainsApps componentsJoinedByString:@", "]);
    }
    return newApps;
    
}


@end
