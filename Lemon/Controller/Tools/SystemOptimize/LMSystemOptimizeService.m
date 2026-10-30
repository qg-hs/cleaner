//
//  LMSystemOptimizeService.m
//  Lemon
//

#import "LMSystemOptimizeService.h"
#import "../Shared/LMModernToolBaseWindowController.h"
#import <Cocoa/Cocoa.h>
#import <QMCoreFunction/STPrivilegedTask.h>
#include <sqlite3.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/socket.h>
#include <sys/stat.h>

static int LMRunCommandSync(NSString *launchPath, NSArray<NSString *> *args, NSString **outStdout) {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:launchPath]) {
        return -1;
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = args ?: @[];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    @try {
        [task launch];
        NSData *outData = [[pipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        if (outStdout && outData.length > 0) {
            *outStdout = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
        }
        return task.terminationStatus;
    } @catch (NSException *ex) {
        return -1;
    }
}

static uint64_t LMDirectoryPhysicalBytes(NSString *dirPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *topAttr = [fm attributesOfItemAtPath:dirPath error:nil];
    if ([topAttr[NSFileType] isEqualToString:NSFileTypeRegular]) {
        return [topAttr[NSFileSize] unsignedLongLongValue];
    }
    uint64_t sum = 0;
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:dirPath];
    NSString *rel = nil;
    while ((rel = [en nextObject]) != nil) {
        NSDictionary *attrs = [en fileAttributes];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            sum += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return sum;
}

static BOOL LMContentHasActivePamTid(NSString *content) {
    if (content.length == 0) {
        return NO;
    }
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger i;
    for (i = 0; i < lines.count; i++) {
        NSString *trimmed = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) {
            continue;
        }
        if ([trimmed containsString:@"pam_tid.so"] && [trimmed hasPrefix:@"auth"]) {
            return YES;
        }
    }
    return NO;
}

@implementation LMSystemOptimizeService

+ (NSArray<LMSystemOptimizeTask *> *)defaultMaintenanceTasks {
    NSMutableArray<LMSystemOptimizeTask *> *list = [NSMutableArray arrayWithCapacity:5];

    LMSystemOptimizeTask *t1 = [[LMSystemOptimizeTask alloc] init];
    t1.taskType = LMSystemOptimizeTaskDNSFlush;
    t1.title = LMToolLocalized(@"刷新 DNS 缓存", @"Flush DNS Cache");
    t1.subtitle = LMToolLocalized(@"重置域名解析缓存，保护活跃 VPN 连接",
                                  @"Clear local DNS cache while preserving VPN");
    t1.requiresAdmin = NO;
    t1.isSelected = YES;
    [list addObject:t1];

    LMSystemOptimizeTask *t2 = [[LMSystemOptimizeTask alloc] init];
    t2.taskType = LMSystemOptimizeTaskQuickLookRebuild;
    t2.title = LMToolLocalized(@"重建预览缓存", @"Rebuild QuickLook");
    t2.subtitle = LMToolLocalized(@"修复访达缩略图白板与预览异常",
                                  @"Reset Finder thumbnail and QuickLook cache");
    t2.requiresAdmin = NO;
    t2.isSelected = YES;
    [list addObject:t2];

    LMSystemOptimizeTask *t3 = [[LMSystemOptimizeTask alloc] init];
    t3.taskType = LMSystemOptimizeTaskSQLiteVacuum;
    t3.title = LMToolLocalized(@"数据库碎片整理", @"Compact Databases");
    t3.subtitle = LMToolLocalized(@"无损紧缩离线应用的 SQLite 数据库",
                                  @"Vacuum closed Safari, Mail & Messages DBs");
    t3.requiresAdmin = NO;
    t3.isSelected = YES;
    [list addObject:t3];

    LMSystemOptimizeTask *t4 = [[LMSystemOptimizeTask alloc] init];
    t4.taskType = LMSystemOptimizeTaskSavedStateAndQuarantine;
    t4.title = LMToolLocalized(@"清理陈旧窗口状态", @"Clean Stale States");
    t4.subtitle = LMToolLocalized(@"移除超 30 天应用窗口快照与下载日志",
                                  @"Remove 30d+ Saved States & quarantine history");
    t4.requiresAdmin = NO;
    t4.isSelected = YES;
    [list addObject:t4];

    LMSystemOptimizeTask *t5 = [[LMSystemOptimizeTask alloc] init];
    t5.taskType = LMSystemOptimizeTaskBrokenPlistAudit;
    t5.title = LMToolLocalized(@"修复损坏偏好配置", @"Audit Broken Plists");
    t5.subtitle = LMToolLocalized(@"校验偏好设置并隔离损坏的 plist 文件",
                                  @"Quarantine corrupted preference plist files");
    t5.requiresAdmin = NO;
    t5.isSelected = YES;
    [list addObject:t5];

    return list;
}

+ (BOOL)hasActiveVPNTunnel {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || interfaces == NULL) {
        return NO;
    }
    BOOL vpnActive = NO;
    struct ifaddrs *cur = interfaces;
    while (cur != NULL) {
        if (cur->ifa_name != NULL && cur->ifa_addr != NULL) {
            unsigned int flags = cur->ifa_flags;
            if ((flags & IFF_UP) && (flags & IFF_RUNNING) && !(flags & IFF_LOOPBACK)) {
                // 真实 VPN 隧道接口携带 IPv4 (AF_INET) 地址，从而精准排除 macOS 系统常驻的仅含 fe80:: 的空 utun
                if (cur->ifa_addr->sa_family == AF_INET) {
                    if (strncmp(cur->ifa_name, "utun", 4) == 0 ||
                        strncmp(cur->ifa_name, "ppp", 3) == 0 ||
                        strncmp(cur->ifa_name, "ipsec", 5) == 0 ||
                        strncmp(cur->ifa_name, "tun", 3) == 0 ||
                        strncmp(cur->ifa_name, "tap", 3) == 0) {
                        vpnActive = YES;
                        break;
                    }
                }
            }
        }
        cur = cur->ifa_next;
    }
    freeifaddrs(interfaces);

    if (!vpnActive) {
        NSString *ncOut = nil;
        if (LMRunCommandSync(@"/usr/sbin/scutil", @[@"--nc", @"list"], &ncOut) == 0 && ncOut.length > 0) {
            if ([ncOut containsString:@"(Connected)"]) {
                vpnActive = YES;
            }
        }
    }
    return vpnActive;
}

+ (void)executeTask:(LMSystemOptimizeTask *)task allowPrivilegedDNS:(BOOL)allowPrivDNS {
    task.reclaimedBytes = 0;

    switch (task.taskType) {
        case LMSystemOptimizeTaskDNSFlush: {
            if ([self hasActiveVPNTunnel] && !allowPrivDNS) {
                // 仅执行用户态目录解析缓存刷新，不向 mDNSResponder 发送信号，保护活跃 VPN 不断流
                int rc = LMRunCommandSync(@"/usr/bin/dscacheutil", @[@"-flushcache"], NULL);
                if (rc == 0) {
                    task.state = LMSystemOptimizeTaskStateSuccess;
                    task.resultText = LMToolLocalized(@"已刷新", @"Flushed");
                } else {
                    task.state = LMSystemOptimizeTaskStateFailed;
                    task.resultText = LMToolLocalized(@"失败", @"Failed");
                }
                return;
            }

            int rc1 = LMRunCommandSync(@"/usr/bin/dscacheutil", @[@"-flushcache"], NULL);
            if (allowPrivDNS) {
                STPrivilegedTask *priv = [[STPrivilegedTask alloc] initWithLaunchPath:@"/usr/bin/killall"
                                                                            arguments:@[@"-HUP", @"mDNSResponder"]];
                [priv launch];
                [priv waitUntilExit];
            }
            if (rc1 == 0) {
                task.state = LMSystemOptimizeTaskStateSuccess;
                task.resultText = LMToolLocalized(@"已刷新", @"Flushed");
            } else {
                task.state = LMSystemOptimizeTaskStateFailed;
                task.resultText = LMToolLocalized(@"失败", @"Failed");
            }
            break;
        }

        case LMSystemOptimizeTaskQuickLookRebuild: {
            int rc1 = LMRunCommandSync(@"/usr/bin/qlmanage", @[@"-r"], NULL);
            int rc2 = LMRunCommandSync(@"/usr/bin/qlmanage", @[@"-r", @"cache"], NULL);
            if (rc1 == 0 || rc2 == 0) {
                task.state = LMSystemOptimizeTaskStateSuccess;
                task.resultText = LMToolLocalized(@"已重建", @"Rebuilt");
            } else {
                task.state = LMSystemOptimizeTaskStateFailed;
                task.resultText = LMToolLocalized(@"失败", @"Failed");
            }
            break;
        }

        case LMSystemOptimizeTaskSQLiteVacuum: {
            NSMutableSet<NSString *> *runningBundles = [NSMutableSet set];
            NSArray<NSRunningApplication *> *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
            NSUInteger i;
            for (i = 0; i < runningApps.count; i++) {
                NSString *bid = runningApps[i].bundleIdentifier;
                if (bid.length > 0) {
                    [runningBundles addObject:bid];
                }
            }

            NSString *home = NSHomeDirectory();
            NSMutableArray<NSDictionary *> *dbTargets = [NSMutableArray array];
            [dbTargets addObject:@{ @"bundle": @"com.apple.Safari", @"path": [home stringByAppendingPathComponent:@"Library/Safari/History.db"] }];
            [dbTargets addObject:@{ @"bundle": @"com.apple.Safari", @"path": [home stringByAppendingPathComponent:@"Library/Safari/Favicon Cache/favicons.db"] }];
            [dbTargets addObject:@{ @"bundle": @"com.apple.MobileSMS", @"path": [home stringByAppendingPathComponent:@"Library/Messages/chat.db"] }];

            NSString *mailDir = [home stringByAppendingPathComponent:@"Library/Mail"];
            NSArray<NSString *> *mailVersions = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:mailDir error:nil];
            for (i = 0; i < mailVersions.count; i++) {
                NSString *vName = mailVersions[i];
                if ([vName hasPrefix:@"V"]) {
                    NSString *envIdx = [[mailDir stringByAppendingPathComponent:vName] stringByAppendingPathComponent:@"MailData/Envelope Index"];
                    [dbTargets addObject:@{ @"bundle": @"com.apple.mail", @"path": envIdx }];
                }
            }

            NSUInteger compactedCount = 0;
            NSUInteger skippedRunning = 0;
            uint64_t savedBytes = 0;

            for (i = 0; i < dbTargets.count; i++) {
                NSString *ownerBundle = dbTargets[i][@"bundle"];
                NSString *dbPath = dbTargets[i][@"path"];
                struct stat stBefore;
                if (stat([dbPath fileSystemRepresentation], &stBefore) != 0 || !S_ISREG(stBefore.st_mode)) {
                    continue;
                }
                if (stBefore.st_size < 128 * 1024) {
                    continue;
                }
                if ([runningBundles containsObject:ownerBundle]) {
                    skippedRunning++;
                    continue;
                }

                sqlite3 *db = NULL;
                int openRc = sqlite3_open_v2([dbPath fileSystemRepresentation], &db, SQLITE_OPEN_READWRITE, NULL);
                if (openRc == SQLITE_OK && db != NULL) {
                    sqlite3_busy_timeout(db, 400);
                    sqlite3_stmt *checkStmt = NULL;
                    BOOL isHealthy = NO;
                    if (sqlite3_prepare_v2(db, "PRAGMA quick_check(1);", -1, &checkStmt, NULL) == SQLITE_OK) {
                        if (sqlite3_step(checkStmt) == SQLITE_ROW) {
                            const unsigned char *txt = sqlite3_column_text(checkStmt, 0);
                            if (txt != NULL && strcmp((const char *)txt, "ok") == 0) {
                                isHealthy = YES;
                            }
                        }
                        sqlite3_finalize(checkStmt);
                    }
                    if (isHealthy) {
                        if (sqlite3_exec(db, "VACUUM;", NULL, NULL, NULL) == SQLITE_OK) {
                            compactedCount++;
                        }
                    }
                    sqlite3_close(db);

                    struct stat stAfter;
                    if (stat([dbPath fileSystemRepresentation], &stAfter) == 0 && stBefore.st_size > stAfter.st_size) {
                        savedBytes += (uint64_t)(stBefore.st_size - stAfter.st_size);
                    }
                } else if (db != NULL) {
                    sqlite3_close(db);
                }
            }

            task.reclaimedBytes = savedBytes;
            if (compactedCount > 0) {
                task.state = LMSystemOptimizeTaskStateSuccess;
                task.resultText = (savedBytes > 0)
                    ? [NSString stringWithFormat:LMToolLocalized(@"省 %@", @"Saved %@"), LMFormatByteCount(savedBytes)]
                    : LMToolLocalized(@"已整理", @"Compacted");
            } else if (skippedRunning > 0) {
                task.state = LMSystemOptimizeTaskStateSkipped;
                task.resultText = LMToolLocalized(@"运行中跳过", @"App Running");
            } else {
                task.state = LMSystemOptimizeTaskStateSuccess;
                task.resultText = LMToolLocalized(@"很干净", @"Clean");
            }
            break;
        }

        case LMSystemOptimizeTaskSavedStateAndQuarantine: {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *savedStateDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Saved Application State"];
            NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:savedStateDir error:nil];

            NSMutableSet<NSString *> *runningBundles = [NSMutableSet set];
            NSArray<NSRunningApplication *> *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
            NSUInteger i;
            for (i = 0; i < runningApps.count; i++) {
                if (runningApps[i].bundleIdentifier) {
                    [runningBundles addObject:runningApps[i].bundleIdentifier];
                }
            }

            NSDate *now = [NSDate date];
            uint64_t freed = 0;
            NSUInteger removedCount = 0;

            for (i = 0; i < entries.count; i++) {
                NSString *name = entries[i];
                if (![name hasSuffix:@".savedState"]) {
                    continue;
                }
                NSString *bundleGuess = [name substringToIndex:(name.length - @".savedState".length)];
                if ([runningBundles containsObject:bundleGuess]) {
                    continue;
                }
                NSString *full = [savedStateDir stringByAppendingPathComponent:name];
                NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
                if ([attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
                    continue;
                }
                NSDate *mtime = attrs[NSFileModificationDate];
                if (mtime && [now timeIntervalSinceDate:mtime] > 30.0 * 86400.0) {
                    uint64_t dirBytes = LMDirectoryPhysicalBytes(full);
                    if ([fm removeItemAtPath:full error:nil]) {
                        freed += dirBytes;
                        removedCount++;
                    }
                }
            }

            // 清理并紧缩 QuarantineEventsV2 下载隔离历史
            NSString *quarantineDB = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"];
            struct stat qBefore;
            if (stat([quarantineDB fileSystemRepresentation], &qBefore) == 0 && S_ISREG(qBefore.st_mode)) {
                sqlite3 *qdb = NULL;
                if (sqlite3_open_v2([quarantineDB fileSystemRepresentation], &qdb, SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK && qdb != NULL) {
                    sqlite3_busy_timeout(qdb, 400);
                    sqlite3_exec(qdb, "DELETE FROM LSQuarantineEvent; VACUUM;", NULL, NULL, NULL);
                    sqlite3_close(qdb);
                    struct stat qAfter;
                    if (stat([quarantineDB fileSystemRepresentation], &qAfter) == 0 && qBefore.st_size > qAfter.st_size) {
                        freed += (uint64_t)(qBefore.st_size - qAfter.st_size);
                    }
                } else if (qdb != NULL) {
                    sqlite3_close(qdb);
                }
            }

            task.reclaimedBytes = freed;
            task.state = LMSystemOptimizeTaskStateSuccess;
            task.resultText = (freed > 0)
                ? [NSString stringWithFormat:LMToolLocalized(@"释放 %@", @"Freed %@"), LMFormatByteCount(freed)]
                : LMToolLocalized(@"很干净", @"Clean");
            break;
        }

        case LMSystemOptimizeTaskBrokenPlistAudit: {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *prefsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
            NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:prefsDir error:nil];
            NSMutableArray<NSURL *> *brokenURLs = [NSMutableArray array];
            uint64_t brokenBytes = 0;

            NSUInteger i;
            for (i = 0; i < files.count; i++) {
                NSString *name = files[i];
                if (![[name pathExtension].lowercaseString isEqualToString:@"plist"] ||
                    [name hasPrefix:@"com.apple."] ||
                    [name hasSuffix:@".lockfile"]) {
                    continue;
                }
                NSString *full = [prefsDir stringByAppendingPathComponent:name];
                NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
                if (![attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
                    continue;
                }
                uint64_t fSize = [attrs[NSFileSize] unsignedLongLongValue];
                if (fSize == 0) {
                    continue; // 0 字节占位文件保留，仅处理损坏数据文件
                }
                NSData *data = [NSData dataWithContentsOfFile:full options:NSDataReadingMappedIfSafe error:nil];
                if (data.length > 0) {
                    NSError *plistErr = nil;
                    id plistObj = [NSPropertyListSerialization propertyListWithData:data
                                                                            options:NSPropertyListImmutable
                                                                             format:NULL
                                                                              error:&plistErr];
                    if (plistObj == nil && plistErr != nil) {
                        [brokenURLs addObject:[NSURL fileURLWithPath:full]];
                        brokenBytes += fSize;
                    }
                }
            }

            if (brokenURLs.count > 0) {
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                [[NSWorkspace sharedWorkspace] recycleURLs:brokenURLs completionHandler:^(NSDictionary<NSURL *,NSURL *> *newURLs, NSError *error) {
                    dispatch_semaphore_signal(sem);
                }];
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                task.reclaimedBytes = brokenBytes;
                task.state = LMSystemOptimizeTaskStateSuccess;
                task.resultText = [NSString stringWithFormat:LMToolLocalized(@"已隔离 %lu 项", @"Quarantined %lu"),
                                   (unsigned long)brokenURLs.count];
            } else {
                task.state = LMSystemOptimizeTaskStateSuccess;
                task.resultText = LMToolLocalized(@"很干净", @"Healthy");
            }
            break;
        }
    }
}

#pragma mark - .DS_Store Suppression

+ (BOOL)isNetworkDSStoreSuppressed {
    NSString *outStr = nil;
    if (LMRunCommandSync(@"/usr/bin/defaults", @[@"read", @"com.apple.desktopservices", @"DSDontWriteNetworkStores"], &outStr) == 0) {
        NSString *trim = [outStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return ([trim isEqualToString:@"1"] || [[trim lowercaseString] isEqualToString:@"true"]);
    }
    return NO;
}

+ (BOOL)isUSBDSStoreSuppressed {
    NSString *outStr = nil;
    if (LMRunCommandSync(@"/usr/bin/defaults", @[@"read", @"com.apple.desktopservices", @"DSDontWriteUSBStores"], &outStr) == 0) {
        NSString *trim = [outStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return ([trim isEqualToString:@"1"] || [[trim lowercaseString] isEqualToString:@"true"]);
    }
    return NO;
}

+ (BOOL)setSuppressNetworkDSStore:(BOOL)suppressNet suppressUSBDSStore:(BOOL)suppressUSB {
    int rc1 = LMRunCommandSync(@"/usr/bin/defaults",
                               @[@"write", @"com.apple.desktopservices", @"DSDontWriteNetworkStores", @"-bool", suppressNet ? @"TRUE" : @"FALSE"],
                               NULL);
    int rc2 = LMRunCommandSync(@"/usr/bin/defaults",
                               @[@"write", @"com.apple.desktopservices", @"DSDontWriteUSBStores", @"-bool", suppressUSB ? @"TRUE" : @"FALSE"],
                               NULL);
    return (rc1 == 0 && rc2 == 0);
}

#pragma mark - Terminal sudo Touch ID (pam_tid.so)

+ (BOOL)isTouchIDPamModuleAvailable {
    NSFileManager *fm = [NSFileManager defaultManager];
    return ([fm fileExistsAtPath:@"/usr/lib/pam/pam_tid.so.2"] ||
            [fm fileExistsAtPath:@"/usr/lib/pam/pam_tid.so"]);
}

+ (BOOL)isSudoTouchIDEnabled {
    NSString *sudoLocal = [NSString stringWithContentsOfFile:@"/etc/pam.d/sudo_local" encoding:NSUTF8StringEncoding error:nil];
    if (LMContentHasActivePamTid(sudoLocal)) {
        return YES;
    }
    NSString *sudoMain = [NSString stringWithContentsOfFile:@"/etc/pam.d/sudo" encoding:NSUTF8StringEncoding error:nil];
    return LMContentHasActivePamTid(sudoMain);
}

+ (BOOL)setSudoTouchIDEnabled:(BOOL)enabled errorMessage:(NSString **)outError {
    if (![self isTouchIDPamModuleAvailable]) {
        if (outError) {
            *outError = LMToolLocalized(@"当前系统未检测到 pam_tid.so 模块，无法配置 Touch ID",
                                        @"pam_tid.so is not available on this macOS system");
        }
        return NO;
    }

    NSOperatingSystemVersion osVer = [[NSProcessInfo processInfo] operatingSystemVersion];
    BOOL useSudoLocal = (osVer.majorVersion >= 14 || [[NSFileManager defaultManager] fileExistsAtPath:@"/etc/pam.d/sudo_local.template"]);
    NSString *targetPamPath = useSudoLocal ? @"/etc/pam.d/sudo_local" : @"/etc/pam.d/sudo";
    NSString *pamTidLine = @"auth       sufficient     pam_tid.so";

    NSString *existingContent = [NSString stringWithContentsOfFile:targetPamPath encoding:NSUTF8StringEncoding error:nil];
    if (existingContent == nil && useSudoLocal) {
        existingContent = [NSString stringWithContentsOfFile:@"/etc/pam.d/sudo_local.template" encoding:NSUTF8StringEncoding error:nil];
        if (existingContent == nil) {
            existingContent = @"# sudo_local: local config file which survives system update and is included for sudo\n";
        }
    }
    if (existingContent == nil) {
        if (outError) {
            *outError = LMToolLocalized(@"无法读取 /etc/pam.d/sudo 配置文件", @"Unable to read PAM configuration");
        }
        return NO;
    }

    NSMutableArray<NSString *> *newLines = [NSMutableArray array];
    NSArray<NSString *> *oldLines = [existingContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    BOOL inserted = NO;

    NSUInteger i;
    for (i = 0; i < oldLines.count; i++) {
        NSString *line = oldLines[i];
        NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        if ([trim containsString:@"pam_tid.so"]) {
            if (enabled) {
                if (!inserted) {
                    [newLines addObject:pamTidLine];
                    inserted = YES;
                }
            } else {
                // 禁用时如果是模板注释则保留注释，否则移除活动行
                if ([trim hasPrefix:@"#"]) {
                    [newLines addObject:line];
                }
            }
            continue;
        }

        // 若启用且尚未插入，在首条非注释规则前插入 pam_tid.so
        if (enabled && !inserted && trim.length > 0 && ![trim hasPrefix:@"#"]) {
            [newLines addObject:pamTidLine];
            inserted = YES;
        }
        [newLines addObject:line];
    }

    if (enabled && !inserted) {
        [newLines addObject:pamTidLine];
    }

    // 去除末尾多余空行并保证单一换行结尾
    while (newLines.count > 0 && [newLines.lastObject length] == 0) {
        [newLines removeLastObject];
    }
    NSString *finalText = [[newLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];

    // 写入当前用户专属安全临时文件 (0600)，随后通过 /usr/bin/install 原子赋权 (0444 root:wheel) 安装至 /etc/pam.d/
    NSString *stagingName = [NSString stringWithFormat:@"cleaner_pam_%@.tmp", [[NSUUID UUID] UUIDString]];
    NSString *stagingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:stagingName];
    NSError *writeErr = nil;
    if (![finalText writeToFile:stagingPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr]) {
        if (outError) {
            *outError = writeErr.localizedDescription ?: @"Failed to stage PAM config";
        }
        return NO;
    }
    chmod([stagingPath fileSystemRepresentation], S_IRUSR | S_IWUSR);

    STPrivilegedTask *privTask = [[STPrivilegedTask alloc] initWithLaunchPath:@"/usr/bin/install"
                                                                    arguments:@[@"-m", @"0444", @"-o", @"root", @"-g", @"wheel", stagingPath, targetPamPath]];
    int launchErr = [privTask launch];
    if (launchErr == 0) {
        [privTask waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:stagingPath error:nil];

    if (launchErr != 0 || [privTask terminationStatus] != 0) {
        if (outError) {
            *outError = LMToolLocalized(@"管理员授权取消或写入 PAM 失败", @"Administrator authorization cancelled or install failed");
        }
        return NO;
    }

    BOOL actualState = [self isSudoTouchIDEnabled];
    return (actualState == enabled);
}

@end
