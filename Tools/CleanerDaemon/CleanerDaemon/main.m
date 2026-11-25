//
//  main.m
//  CleanerDaemon
//

//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import "CleanerDaemonConst.h"
#import "CmcSystem.h"
#import "CmcProcess.h"
#import "McPipeThread.h"
#import "McUninstall.h"
#import "OwlManageDaemon.h"
#import "CleanerBizManager.h"
#import "LMDaemonListenerDelegate.h"
#import "DaemonStartup.h"
#import "CleanerBizManager.h"
#import "LMPlistHelper.h"
#import "CmcFileAction.h"

void redirectLogToFile(NSString *path, NSInteger persistDays, unsigned long long maxSize) {
    
    if (!path || persistDays <= 0 || maxSize <= 0) return;
    
    NSString *logPath = path;
    id fileHandle = nil;
    
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    if (![fileMgr fileExistsAtPath:logPath]) {
        [fileMgr createFileAtPath:logPath contents:[NSData data] attributes:nil];
    } else {
        NSDictionary *fileAttributes = [fileMgr attributesOfItemAtPath:logPath error:nil];
        if (fileAttributes) {
            unsigned long long fileSize = [fileAttributes fileSize];
            NSDate *date = [fileAttributes fileCreationDate];
            NSTimeInterval createTimeInterval = [date timeIntervalSince1970];
            NSTimeInterval todayTimeInterval = [[NSDate date] timeIntervalSince1970];

            // 日志文件大小限制
            BOOL isFileSizeExceeded = fileSize > (maxSize * 1024 * 1024);
            
            // 日志创建时间限制
            // createTimeInterval is 0，属于异常，重新创建文件也合理
            BOOL isExpired = (todayTimeInterval - createTimeInterval) > (persistDays * 24 * 3600);

            if (isFileSizeExceeded || isExpired) {
                [fileMgr removeItemAtPath:logPath error:nil];
                [fileMgr createFileAtPath:logPath contents:[NSData data] attributes:nil];
            }
        }
    }
    
    fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [fileHandle seekToEndOfFile];
    if (fileHandle != nil)
    {
        dup2([fileHandle fileDescriptor], STDERR_FILENO);
    }
    [fileHandle closeFile];
}

void redirectNSLog(NSString *suffix, NSInteger persistDays){
    NSString *logName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
    
    // do not redirect in test mode
    if (![[[NSBundle mainBundle] executablePath] hasPrefix:@"/Library"])
        return;
    
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    NSString *rootPath;
    if (getuid() == 0) {
        rootPath = @"/Library/Logs/Cleaner";
    } else {
        rootPath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Logs/Cleaner"];
    }
    BOOL isDir;
    if (![fileMgr fileExistsAtPath:rootPath isDirectory:&isDir] || !isDir) {
        [fileMgr createDirectoryAtPath:rootPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString *fileName = [NSString stringWithFormat:@"%@-%@.log", logName, suffix];
    
    
    NSString *logfilePath = [rootPath stringByAppendingPathComponent:fileName];
   
    NSLog(@"%s to %@", __FUNCTION__, logfilePath);
    // 较多使用QMCoreFunction时再引入
    //[MdlsToolsHelper redirectLogToFileAtPath:logfilePath forDays:persistDays maxSize:100];
    // clean log file
    redirectLogToFile(logfilePath, persistDays, 100);
}

void* bundleCopyCallBack()
{
    CFURLRef bundleURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)DEFAULT_APP_PATH, kCFURLPOSIXPathStyle, true);
    CFBundleRef mainBundle = CFBundleCreate(kCFAllocatorDefault, bundleURL);
    CFRelease(bundleURL);
    
    return mainBundle;
}

BOOL isAppRunningBundleId(NSString *bundelId){
    NSArray *runnings= [NSRunningApplication runningApplicationsWithBundleIdentifier:bundelId];
    NSLog(@"[TrashDel, running%@:%@", bundelId, runnings);
    return [runnings count] > 0;
}

static dispatch_source_t sAppWatchSource = nil;
static NSUInteger sAppWatchGeneration = 0;
static void startWatchingMainAppDeletion(void);

static BOOL isRelauncherRunning(void) {
    ProcessInfo_t *proc_info = NULL;
    BOOL running = NO;
    int count = CmcGetProcessInfo(McprocNone, 0, NO, &proc_info);
    if (count > 0 && proc_info != NULL) {
        for (int i = 0; i < count; i++) {
            if (strcmp(proc_info[i].pExeName, "cleaner_relauncher") == 0) {
                running = YES;
                break;
            }
        }
    }
    if (proc_info != NULL) {
        free(proc_info);
    }
    return running;
}

static void scheduleAppDeletionVerification(NSUInteger generation, NSUInteger retryCount) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != sAppWatchGeneration) {
            return;
        }
        // 更新期间 cleaner_relauncher 会短暂移动替换主应用，等待其完成再判定
        if (isRelauncherRunning() && retryCount < 30) {
            NSLog(@"CleanerDaemon defer uninstall check because cleaner_relauncher is active (retry=%lu)", (unsigned long)retryCount);
            scheduleAppDeletionVerification(generation, retryCount + 1);
            return;
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:DEFAULT_APP_PATH]) {
            NSLog(@"CleanerDaemon %@ still exists after change event, re-arming watcher", DEFAULT_APP_PATH);
            startWatchingMainAppDeletion();
            return;
        }
        NSLog(@"CleanerDaemon detected %@ removed, begin to uninstall", DEFAULT_APP_PATH);
        uninstallSub();
    });
}

static void startWatchingMainAppDeletion(void) {
    if (sAppWatchSource) {
        dispatch_source_cancel(sAppWatchSource);
        sAppWatchSource = nil;
    }
    int fd = open([DEFAULT_APP_PATH fileSystemRepresentation], O_EVTONLY);
    if (fd < 0) {
        NSLog(@"CleanerDaemon failed to open %@ for watching (errno=%d)", DEFAULT_APP_PATH, errno);
        if (![[NSFileManager defaultManager] fileExistsAtPath:DEFAULT_APP_PATH]) {
            sAppWatchGeneration++;
            scheduleAppDeletionVerification(sAppWatchGeneration, 0);
        }
        return;
    }
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,
                                                      (uintptr_t)fd,
                                                      DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
                                                      dispatch_get_main_queue());
    if (!source) {
        close(fd);
        return;
    }
    sAppWatchSource = source;
    dispatch_source_set_event_handler(source, ^{
        if (sAppWatchSource == source) {
            dispatch_source_cancel(source);
            sAppWatchSource = nil;
        }
        sAppWatchGeneration++;
        scheduleAppDeletionVerification(sAppWatchGeneration, 0);
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    dispatch_resume(source);
    NSLog(@"CleanerDaemon watching %@ deletion in-process", DEFAULT_APP_PATH);
}



int main(int argc, const char * argv[])
{

    @autoreleasepool
    {
        NSLog(@"%s args: ", __FUNCTION__);
        
        for(int i = 0; i < argc; i++) {
            NSLog(@"   %s", argv[i]);
        }

        // Security fix: socket 唤醒分支(reloadListenPlist/startup)已移除
        
        if (argc == 2 && strcmp(argv[1], kCopySelfToApplication) == 0) {
            redirectNSLog([NSString stringWithUTF8String:argv[1]], 30);
            setuid(0);
            copyFileIfNeed();
            return 0;
        }
        

        // 安装命令 - 命令参数 | 用户名 | 版本号 | 主进程ID
        if (argc == 5 && strcmp(argv[1], kInstallCmd_cstr) == 0)
        {
            // 安装流程，会先删旧再装新，删旧的时候不会删perference
            redirectNSLog([NSString stringWithUTF8String:argv[1]], 30);
            NSLog(@"[QMAgent] Ready to install for %s (ver: %s)", argv[2], argv[3]);
            NSLog(@" agent Path:%@", [[NSBundle mainBundle] bundlePath]);
            int nRet = InstallCastle(argv[2], argv[3], atoi(argv[4]));
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:kInstallFinishNotify
                                                                           object:[[NSNumber numberWithInt:nRet] stringValue]
                                                                         userInfo:nil
                                                                        options:NSNotificationPostToAllSessions];
            NSLog(@"[install] return");
            return nRet;
        }
        
        // 安装命令 - 命令参数 | 用户名 | 版本号 | 主进程ID
        if (argc == 6 && strcmp(argv[1], kRepairCmd_cstr) == 0)
        {
            // 安装流程，会先删旧再装新，删旧的时候不会删perference
            redirectNSLog([NSString stringWithUTF8String:argv[1]], 30);
            NSLog(@"[QMAgent] Ready to install for %s (ver: %s)", argv[2], argv[3]);
            NSLog(@" agent Path:%@", [[NSBundle mainBundle] bundlePath]);
            
            
            // 移动文件时先把卸载监听unload掉
            unloadPlistByLable(DAEMON_UNINSTALL_LAUNCHD_LABLE);
            unloadAgentPlistByLableForAllUser(DAEMON_UNINSTALL_LAUNCHD_LABLE);
            if (fileMoveTo(argv[5], (char *)[DEFAULT_APP_PATH UTF8String], MCCMD_MOVEFILE_MOVE) == -1)
            {
                NSLog(@"Update fail when replacing APP file");
                return -1;
            }
            
            int nRet = InstallCastle(argv[2], argv[3], atoi(argv[4]));
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:kInstallFinishNotify
                                                                           object:[[NSNumber numberWithInt:nRet] stringValue]
                                                                         userInfo:nil
                                                                        options:NSNotificationPostToAllSessions];
            NSLog(@"[install] return");
            return nRet;
        }
        
        //sleep(50);
        
        // 卸载
        if (argc == 2 && strcmp(argv[1], kUninstallCmd_cstr) == 0)
        {
            redirectNSLog([NSString stringWithUTF8String:argv[1]], 30);
            //DEFAULT_APP_PATH有变化就会触发kUninstallCmd_cstr，所以这里必须判断一下Cleaner.app在不在
            // 再确定要不要卸载。
            if (![[NSFileManager defaultManager] fileExistsAtPath:DEFAULT_APP_PATH]) {
                NSLog(@"%@ not exist, go to uninstall", DEFAULT_APP_PATH);
                uninstallSub();
            } else {
                NSLog(@"%@ exist, no need to uninstall", DEFAULT_APP_PATH);
            }
            return 0;
        }
        
        //重定向日志输出
        if (argc >= 2) {
            redirectNSLog([NSString stringWithUTF8String:argv[1]], 30);
        } else {
            redirectNSLog(nil, 7);
        }
        
        // 必须是要由系统Daemon加载
        if (argc != 2 || strcmp(argv[1], kLoadCmd_cstr) != 0)
        {
            NSLog(@"CleanerDaemon kLoadCmd_cstr error");
            return 0;
        }
       
        NSLog(@"CleanerDaemon main run");
        
        
        // daemon 保持常驻，不再检查 isNeedExitDaemon。
        // 原因：移除 socket 后，exit(0) 会导致 launchd 移除 job，
        // 后续客户端启动时 XPC 无法按需拉起 daemon。
        // daemon 内存占用极低，保持常驻等待 XPC 连接。
        // 退出逻辑由 clientExit() 负责（现在也改为不退出）。
        
        // 卸载自身(当Monitor的卸载机制出现异常,Agent下次启动时(比如开机时)卸载自身)
        if (![[NSFileManager defaultManager] fileExistsAtPath:DEFAULT_APP_PATH])
        {
            NSLog(@"CleanerDaemon DEFAULT_APP_PATH error， begin to uninstall");
            uninstallSub();
            return 0;
        }
        
        // 进程内监听主应用删除事件，替代独立 com.cleaner.uninstall.plist
        startWatchingMainAppDeletion();
        
        // 注册返回主bundle的回调
        CmcRegisterBundleCallBack(&bundleCopyCallBack);
                
        // 需要手动设置版本号
        NSString *curVersion = [[[NSBundle bundleWithPath:DEFAULT_APP_PATH] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
        curVersion = [curVersion stringByAppendingString:@".1"];
               
        NSOperationQueue *operQueue = [[NSOperationQueue alloc] init];
                
        NSXPCListener *listener = nil;
        LMDaemonListenerDelegate *delegate = nil;
   
        //11.3及以上系统暂时屏蔽隐私防护功能入口
        if (@available(macOS 11.3, *)) {
        } else {
            [OwlManageDaemon shareInstance];
        }
        
        //use xpc
        {
            NSLog(@"CleanerDaemon use xpc");
            delegate = [LMDaemonListenerDelegate new];
            // Set up the one NSXPCListener for this service. It will handle all incoming connections.
            listener = [[NSXPCListener alloc] initWithMachServiceName:DAEMON_APP_BUNDLEID];
            listener.delegate = delegate;
            // Resuming the serviceListener starts this service. This method does not return.
            [listener resume];
            NSLog(@"CleanerDaemon NSXPCListener resume");
        }
        
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}

