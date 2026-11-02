//
//  cleaner_relauncher.m
//  cleaner
//
//  Standalone native helper program for atomic in-place app replacement and auto-relaunch.
//  Zero dependencies, decoupled POSIX lifecycle.
//

#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>
#include <sys/xattr.h>
#include <stdlib.h>

static void LogUpdate(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/cleaner_updater.log"];
    NSString *entry = [NSString stringWithFormat:@"[%@] [relauncher:%d] %@\n", [NSDate date], getpid(), msg];
    
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
    NSLog(@"%@", msg);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        pid_t callerPid = 0;
        NSString *srcApp = nil;
        NSString *dstApp = nil;
        NSString *relaunchApp = nil;
        BOOL relaunchMonitor = NO;

        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--pid") == 0 && i + 1 < argc) {
                callerPid = (pid_t)atoi(argv[++i]);
            } else if (strcmp(argv[i], "--src") == 0 && i + 1 < argc) {
                srcApp = [NSString stringWithUTF8String:argv[++i]];
            } else if (strcmp(argv[i], "--dst") == 0 && i + 1 < argc) {
                dstApp = [NSString stringWithUTF8String:argv[++i]];
            } else if (strcmp(argv[i], "--relaunch") == 0 && i + 1 < argc) {
                relaunchApp = [NSString stringWithUTF8String:argv[++i]];
            } else if (strcmp(argv[i], "--relaunch-monitor") == 0) {
                relaunchMonitor = YES;
            }
        }

        if (srcApp.length == 0 || dstApp.length == 0) {
            LogUpdate(@"Error: Missing mandatory arguments --src or --dst.");
            return 1;
        }
        if (relaunchApp.length == 0) {
            relaunchApp = dstApp;
        }

        // 1. 完全脱离父进程会话组，防止父进程退出时级联终止
        setsid();
        signal(SIGHUP, SIG_IGN);

        LogUpdate(@"Starting in-place update: callerPid=%d src=%@ dst=%@ relaunch=%@ relaunchMonitor=%d",
                  callerPid, srcApp, dstApp, relaunchApp, relaunchMonitor);

        // 2. 等待调用方主进程退出（最多等待 5 秒）
        if (callerPid > 0) {
            int retries = 0;
            while (retries < 50 && kill(callerPid, 0) == 0) {
                usleep(100000); // 100ms
                retries++;
            }
            if (kill(callerPid, 0) == 0) {
                LogUpdate(@"Caller process %d did not terminate within 5s, forcing SIGKILL", callerPid);
                kill(callerPid, SIGKILL);
                usleep(200000);
            }
        }

        // 3. 清理残留的相关常驻进程（LemonMonitor / cleaner），释放文件句柄
        system("/usr/bin/killall -9 LemonMonitor cleaner 2>/dev/null || true");
        usleep(300000); // 等待 300ms 确保内核释放文件锁

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:srcApp]) {
            LogUpdate(@"Error: Extracted source app does not exist at %@", srcApp);
            return 2;
        }

        // 4. 原子重命名替换与失败回滚保护
        NSString *backupPath = [dstApp stringByAppendingFormat:@".old.%u", (unsigned int)time(NULL)];
        BOOL hasExisting = [fm fileExistsAtPath:dstApp];

        if (hasExisting) {
            NSError *backupErr = nil;
            if (![fm moveItemAtPath:dstApp toPath:backupPath error:&backupErr]) {
                LogUpdate(@"Warning: Could not move dst to backup (%@), attempting direct removal", backupErr);
                [fm removeItemAtPath:dstApp error:nil];
            } else {
                LogUpdate(@"Moved existing app to backup %@", backupPath);
            }
        }

        NSError *installErr = nil;
        BOOL installSuccess = [fm moveItemAtPath:srcApp toPath:dstApp error:&installErr];
        if (!installSuccess) {
            LogUpdate(@"Atomic move failed (%@), trying fallback with /usr/bin/ditto", installErr);
            NSString *dittoCmd = [NSString stringWithFormat:@"/usr/bin/ditto \"%@\" \"%@\"", srcApp, dstApp];
            if (system([dittoCmd UTF8String]) == 0) {
                installSuccess = YES;
                LogUpdate(@"Fallback ditto succeeded.");
            }
        }

        // 若因受保护目录无写入权限导致失败，尝试使用 AppleScript 调起系统管理员提权覆盖
        if (!installSuccess) {
            LogUpdate(@"User privileges failed to replace app, requesting administrator privileges via osascript...");
            NSString *adminScript = [NSString stringWithFormat:
                @"do shell script \"/bin/rm -rf '%@' && /usr/bin/ditto '%@' '%@'\" with administrator privileges",
                dstApp, srcApp, dstApp];
            NSAppleScript *as = [[NSAppleScript alloc] initWithSource:adminScript];
            NSDictionary *asErr = nil;
            NSAppleEventDescriptor *result = [as executeAndReturnError:&asErr];
            if (result && !asErr) {
                installSuccess = YES;
                LogUpdate(@"Privileged installation succeeded.");
            } else {
                LogUpdate(@"Privileged installation failed: %@", asErr);
            }
        }

        // 若最终替换失败，执行回滚
        if (!installSuccess) {
            LogUpdate(@"Fatal: Installation failed! Rolling back from backup...");
            if ([fm fileExistsAtPath:backupPath]) {
                [fm moveItemAtPath:backupPath toPath:dstApp error:nil];
            }
            return 3;
        }

        // 替换成功，静默清理备份
        if ([fm fileExistsAtPath:backupPath]) {
            [fm removeItemAtPath:backupPath error:nil];
        }

        // 5. 递归清除 Gatekeeper 隔离属性与设置执行权限
        NSString *xattrCmd = [NSString stringWithFormat:@"/usr/bin/xattr -dr com.apple.quarantine \"%@\" 2>/dev/null || true", dstApp];
        system([xattrCmd UTF8String]);
        NSString *chmodCmd = [NSString stringWithFormat:@"/bin/chmod -R a+rX \"%@\" 2>/dev/null || true", dstApp];
        system([chmodCmd UTF8String]);

        // 6. 重启启动新版应用程序
        LogUpdate(@"Launching updated application: %@", relaunchApp);
        NSString *openAppCmd = [NSString stringWithFormat:@"/usr/bin/open -n \"%@\"", relaunchApp];
        system([openAppCmd UTF8String]);

        // 7. 若原本在运行状态栏监控，重新唤醒内置 LemonMonitor
        if (relaunchMonitor) {
            NSString *monitorAppPath = [dstApp stringByAppendingPathComponent:@"Contents/Library/LoginItems/LemonMonitor.app"];
            if ([fm fileExistsAtPath:monitorAppPath]) {
                LogUpdate(@"Relaunching status bar monitor: %@", monitorAppPath);
                NSString *openMonitorCmd = [NSString stringWithFormat:@"/usr/bin/open -a \"%@\" --args 1 2>/dev/null || true", monitorAppPath];
                system([openMonitorCmd UTF8String]);
            }
        }

        // 8. 清理临时解包目录
        NSString *tempRoot = [srcApp stringByDeletingLastPathComponent];
        if ([tempRoot containsString:@"cleaner_update_"] || [tempRoot containsString:@"cleaner_hotupdate_"]) {
            [fm removeItemAtPath:tempRoot error:nil];
        }

        LogUpdate(@"cleaner_relauncher update process finished successfully.");
        return 0;
    }
}
