//
//  LMAppSlimScanner.m
//  Lemon
//

#import "LMAppSlimScanner.h"
#import "../Shared/LMModernToolBaseWindowController.h"
#import <Cocoa/Cocoa.h>
#import <QMCoreFunction/STPrivilegedTask.h>
#include <mach-o/fat.h>
#include <mach/machine.h>
#include <libkern/OSByteOrder.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <sys/clonefile.h>
#include <fts.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdatomic.h>

static int LMSlimRunToolSync(NSString *launchPath, NSArray<NSString *> *args) {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:launchPath]) {
        return -1;
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = args ?: @[];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    @try {
        [task launch];
        [task waitUntilExit];
        return task.terminationStatus;
    } @catch (NSException *ex) {
        return -1;
    }
}

/// O(1) pread 直接解析 Mach-O Fat Header，必须同时包含 hostCPU 与 stripCPU 才返回可回收切片大小
static uint64_t LMInspectUniversalMachOSavings(const char *filePath,
                                               cpu_type_t hostCPU,
                                               cpu_type_t stripCPU) {
    int fd = open(filePath, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return 0;
    }
    uint8_t buf[512];
    ssize_t n = pread(fd, buf, sizeof(buf), 0);
    close(fd);
    if (n < (ssize_t)sizeof(struct fat_header)) {
        return 0;
    }

    uint32_t rawMagic = *(const uint32_t *)buf;
    BOOL hasHost = NO;
    BOOL hasStrip = NO;
    uint64_t stripBytes = 0;

    if (rawMagic == FAT_MAGIC || rawMagic == FAT_CIGAM) {
        BOOL swap = (rawMagic == FAT_CIGAM);
        const struct fat_header *fh = (const struct fat_header *)buf;
        uint32_t nArch = swap ? OSSwapInt32(fh->nfat_arch) : fh->nfat_arch;
        if (nArch < 2 || nArch > 12) {
            return 0;
        }
        size_t needed = sizeof(struct fat_header) + (size_t)nArch * sizeof(struct fat_arch);
        if ((size_t)n < needed) {
            return 0;
        }
        const struct fat_arch *archs = (const struct fat_arch *)(buf + sizeof(struct fat_header));
        uint32_t i;
        for (i = 0; i < nArch; i++) {
            cpu_type_t ctype = (cpu_type_t)(swap ? OSSwapInt32((uint32_t)archs[i].cputype) : (uint32_t)archs[i].cputype);
            uint32_t sliceSize = swap ? OSSwapInt32(archs[i].size) : archs[i].size;
            if (ctype == hostCPU) {
                hasHost = YES;
            } else if (ctype == stripCPU) {
                hasStrip = YES;
                stripBytes += (uint64_t)sliceSize;
            }
        }
    } else if (rawMagic == FAT_MAGIC_64 || rawMagic == FAT_CIGAM_64) {
        BOOL swap = (rawMagic == FAT_CIGAM_64);
        const struct fat_header *fh = (const struct fat_header *)buf;
        uint32_t nArch = swap ? OSSwapInt32(fh->nfat_arch) : fh->nfat_arch;
        if (nArch < 2 || nArch > 12) {
            return 0;
        }
        size_t needed = sizeof(struct fat_header) + (size_t)nArch * sizeof(struct fat_arch_64);
        if ((size_t)n < needed) {
            return 0;
        }
        const struct fat_arch_64 *archs = (const struct fat_arch_64 *)(buf + sizeof(struct fat_header));
        uint32_t i;
        for (i = 0; i < nArch; i++) {
            cpu_type_t ctype = (cpu_type_t)(swap ? OSSwapInt32((uint32_t)archs[i].cputype) : (uint32_t)archs[i].cputype);
            uint64_t sliceSize = swap ? OSSwapInt64(archs[i].size) : archs[i].size;
            if (ctype == hostCPU) {
                hasHost = YES;
            } else if (ctype == stripCPU) {
                hasStrip = YES;
                stripBytes += sliceSize;
            }
        }
    }

    return (hasHost && hasStrip) ? stripBytes : 0;
}

/// 读取用户在 Finder 中勾选了「使用 Rosetta 打开」的应用 BundleID 集合
static NSSet<NSString *> *LMRosettaPreferredBundleIDs(void) {
    NSString *lsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:lsPath];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return [NSSet set];
    }
    NSDictionary *archMap = dict[@"LSArchitecturesForX86_64"];
    if (![archMap isKindOfClass:[NSDictionary class]]) {
        return [NSSet set];
    }
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSString *bid in archMap.allKeys) {
        id val = archMap[bid];
        if ([val isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)val;
            if ([arr containsObject:@"x86_64"]) {
                [set addObject:bid];
            }
        }
    }
    return set;
}

@interface LMAppSlimScanner () {
    atomic_bool _cancelled;
}
@end

@implementation LMAppSlimScanner

+ (BOOL)isAppleSiliconHost {
    int arm64Cap = 0;
    size_t len = sizeof(arm64Cap);
    if (sysctlbyname("hw.optional.arm64", &arm64Cap, &len, NULL, 0) == 0 && arm64Cap == 1) {
        return YES;
    }
    return NO;
}

+ (NSString *)nativeKeepArchitectureName {
    return [self isAppleSiliconHost] ? @"arm64" : @"x86_64";
}

+ (NSString *)removableArchitectureName {
    return [self isAppleSiliconHost] ? @"x86_64" : @"arm64";
}

- (void)cancelScan {
    atomic_store(&_cancelled, true);
}

- (void)startScanWithProgress:(LMAppSlimScanProgressBlock)progressBlock
                   completion:(LMAppSlimScanCompletionBlock)completionBlock {
    atomic_store(&_cancelled, false);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL isAS = [LMAppSlimScanner isAppleSiliconHost];
        cpu_type_t hostCPU = isAS ? CPU_TYPE_ARM64 : CPU_TYPE_X86_64;
        cpu_type_t stripCPU = isAS ? CPU_TYPE_X86_64 : CPU_TYPE_ARM64;
        NSString *stripArchStr = [LMAppSlimScanner removableArchitectureName];

        NSSet<NSString *> *rosettaBundles = isAS ? LMRosettaPreferredBundleIDs() : [NSSet set];
        NSString *selfBundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

        NSMutableSet<NSString *> *runningAppPaths = [NSMutableSet set];
        NSMutableSet<NSString *> *runningBundleIDs = [NSMutableSet set];
        NSArray<NSRunningApplication *> *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
        NSUInteger rIdx;
        for (rIdx = 0; rIdx < runningApps.count; rIdx++) {
            NSURL *bURL = runningApps[rIdx].bundleURL;
            if (bURL.path.length > 0) {
                [runningAppPaths addObject:[bURL.path stringByResolvingSymlinksInPath]];
            }
            if (runningApps[rIdx].bundleIdentifier.length > 0) {
                [runningBundleIDs addObject:runningApps[rIdx].bundleIdentifier];
            }
        }

        NSArray<NSString *> *appRoots = @[
            @"/Applications",
            [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"]
        ];

        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray<NSString *> *candidateApps = [NSMutableArray array];
        NSMutableSet<NSString *> *seenAppPaths = [NSMutableSet set];

        NSUInteger dIdx;
        for (dIdx = 0; dIdx < appRoots.count; dIdx++) {
            NSString *dir = appRoots[dIdx];
            NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:dir error:nil];
            NSUInteger eIdx;
            for (eIdx = 0; eIdx < entries.count; eIdx++) {
                NSString *name = entries[eIdx];
                if (![[name pathExtension].lowercaseString isEqualToString:@"app"]) {
                    continue;
                }
                NSString *full = [[dir stringByAppendingPathComponent:name] stringByResolvingSymlinksInPath];
                if (full.length > 0 && ![full hasPrefix:@"/System/"] && ![seenAppPaths containsObject:full]) {
                    [seenAppPaths addObject:full];
                    [candidateApps addObject:full];
                }
            }
        }

        NSMutableArray<LMAppSlimItem *> *results = [NSMutableArray array];
        NSUInteger aIdx;
        for (aIdx = 0; aIdx < candidateApps.count; aIdx++) {
            if (atomic_load(&self->_cancelled)) {
                break;
            }
            @autoreleasepool {
                NSString *appPath = candidateApps[aIdx];
                NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
                NSDictionary *info = appBundle.infoDictionary;
                NSString *bundleID = info[(NSString *)kCFBundleIdentifierKey] ?: @"";

                // 6 重安全豁免过滤
                if (bundleID.length == 0 ||
                    [bundleID hasPrefix:@"com.apple."] ||
                    [bundleID isEqualToString:selfBundleID] ||
                    [rosettaBundles containsObject:bundleID]) {
                    continue;
                }

                // 跳过 Mac App Store 应用 (_MASReceipt)
                NSString *masReceipt = [appPath stringByAppendingPathComponent:@"Contents/_MASReceipt/receipt"];
                if ([fm fileExistsAtPath:masReceipt]) {
                    continue;
                }

                NSString *displayName = [fm displayNameAtPath:appPath];
                if ([displayName hasSuffix:@".app"]) {
                    displayName = [displayName stringByDeletingPathExtension];
                }

                if (progressBlock && (aIdx % 4 == 0)) {
                    NSUInteger cnt = results.count;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progressBlock(displayName, cnt);
                    });
                }

                // 遍历 Contents 内部所有文件，统计总大小并定位所有双架构 Mach-O
                NSString *contentsDir = [appPath stringByAppendingPathComponent:@"Contents"];
                if (![fm fileExistsAtPath:contentsDir]) {
                    continue;
                }

                uint64_t totalBytes = 0;
                uint64_t savingsBytes = 0;
                NSMutableArray<NSString *> *relFatPaths = [NSMutableArray array];

                char *cPaths[2] = { strdup([contentsDir fileSystemRepresentation]), NULL };
                FTS *ftsp = fts_open(cPaths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
                if (ftsp != NULL) {
                    FTSENT *ent = NULL;
                    NSString *appPrefix = [appPath hasSuffix:@"/"] ? appPath : [appPath stringByAppendingString:@"/"];
                    while ((ent = fts_read(ftsp)) != NULL) {
                        if (atomic_load(&self->_cancelled)) {
                            break;
                        }
                        if (ent->fts_info != FTS_F || ent->fts_statp == NULL) {
                            continue;
                        }
                        uint64_t fSize = (uint64_t)ent->fts_statp->st_size;
                        totalBytes += fSize;

                        if (fSize < 4096) {
                            continue;
                        }

                        // 仅探测可执行权限文件或动态库 (.dylib / .so)
                        BOOL isExec = ((ent->fts_statp->st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0);
                        if (!isExec) {
                            const char *dot = strrchr(ent->fts_name, '.');
                            if (dot == NULL || (strcmp(dot, ".dylib") != 0 && strcmp(dot, ".so") != 0)) {
                                continue;
                            }
                        }

                        uint64_t sliceSave = LMInspectUniversalMachOSavings(ent->fts_path, hostCPU, stripCPU);
                        if (sliceSave > 0) {
                            NSString *fullMachO = [NSString stringWithUTF8String:ent->fts_path];
                            if ([fullMachO hasPrefix:appPrefix]) {
                                NSString *relPath = [fullMachO substringFromIndex:appPrefix.length];
                                if (relPath.length > 0) {
                                    [relFatPaths addObject:relPath];
                                    savingsBytes += sliceSave;
                                }
                            }
                        }
                    }
                    fts_close(ftsp);
                }
                free(cPaths[0]);

                // 仅展示可节省 >= 1 MB 的 Universal 应用
                if (savingsBytes >= 1024 * 1024 && relFatPaths.count > 0) {
                    LMAppSlimItem *item = [[LMAppSlimItem alloc] init];
                    item.appPath = appPath;
                    item.appName = displayName ?: [appPath lastPathComponent];
                    item.bundleIdentifier = bundleID;
                    item.versionString = info[@"CFBundleShortVersionString"] ?: (info[(NSString *)kCFBundleVersionKey] ?: @"");
                    item.totalAppBytes = totalBytes;
                    item.estimatedSavingsBytes = savingsBytes;
                    item.relativeFatBinaryPaths = [relFatPaths copy];
                    item.removableArchName = stripArchStr;
                    item.isRunning = ([runningAppPaths containsObject:appPath] || [runningBundleIDs containsObject:bundleID]);
                    item.isSelected = !item.isRunning;
                    [results addObject:item];
                }
            }
        }

        if (atomic_load(&self->_cancelled)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(@[], YES);
            });
            return;
        }

        [results sortUsingComparator:^NSComparisonResult(LMAppSlimItem *a, LMAppSlimItem *b) {
            if (a.estimatedSavingsBytes > b.estimatedSavingsBytes) return NSOrderedAscending;
            if (a.estimatedSavingsBytes < b.estimatedSavingsBytes) return NSOrderedDescending;
            return [a.appName localizedCaseInsensitiveCompare:b.appName];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSWorkspace *ws = [NSWorkspace sharedWorkspace];
            NSUInteger i;
            for (i = 0; i < results.count; i++) {
                results[i].appIcon = [ws iconForFile:results[i].appPath];
            }
            completionBlock([results copy], NO);
        });
    });
}

+ (BOOL)slimApplicationItem:(LMAppSlimItem *)item
        moveOriginalToTrash:(BOOL)moveToTrash
             reclaimedBytes:(uint64_t *)outReclaimed
               errorMessage:(NSString **)outError {
    if (outReclaimed) {
        *outReclaimed = 0;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (item == nil || item.appPath.length == 0 || ![fm fileExistsAtPath:item.appPath]) {
        if (outError) *outError = LMToolLocalized(@"目标应用不存在", @"Target application does not exist");
        return NO;
    }

    // 实时复核目标应用是否正在运行
    NSArray<NSRunningApplication *> *running = [[NSWorkspace sharedWorkspace] runningApplications];
    NSUInteger rIdx;
    for (rIdx = 0; rIdx < running.count; rIdx++) {
        NSRunningApplication *ra = running[rIdx];
        if ((item.bundleIdentifier.length > 0 && [ra.bundleIdentifier isEqualToString:item.bundleIdentifier]) ||
            (ra.bundleURL.path.length > 0 && [[ra.bundleURL.path stringByResolvingSymlinksInPath] isEqualToString:item.appPath])) {
            if (outError) {
                *outError = [NSString stringWithFormat:LMToolLocalized(@"%@ 正在运行，请先退出后再瘦身", @"%@ is currently running"), item.appName];
            }
            return NO;
        }
    }

    // 1. 在当前用户缓存目录创建独立事务暂存区，优先使用 APFS clonefile CoW 零空间克隆
    NSString *stageRoot = [NSHomeDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"Library/Caches/com.lemon.cleaner.slim_%@", [[NSUUID UUID] UUIDString]]];
    if (![fm createDirectoryAtPath:stageRoot withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (outError) *outError = LMToolLocalized(@"无法创建临时瘦身工作区", @"Failed to create staging directory");
        return NO;
    }

    NSString *stagedAppPath = [stageRoot stringByAppendingPathComponent:[item.appPath lastPathComponent]];
    int cloneRc = clonefile([item.appPath fileSystemRepresentation], [stagedAppPath fileSystemRepresentation], 0);
    if (cloneRc != 0) {
        NSError *cpErr = nil;
        if (![fm copyItemAtPath:item.appPath toPath:stagedAppPath error:&cpErr]) {
            [fm removeItemAtPath:stageRoot error:nil];
            if (outError) *outError = cpErr.localizedDescription ?: @"Copy to staging failed";
            return NO;
        }
    }

    // 确保克隆体归属当前用户可写，以便 lipo 与 codesign 修改二进制文件
    LMSlimRunToolSync(@"/bin/chmod", @[@"-R", @"u+w", stagedAppPath]);

    // 2. 在克隆体上逐个执行 lipo -remove 剥离冗余架构
    NSString *archToRemove = item.removableArchName ?: [self removableArchitectureName];
    uint64_t actualSaved = 0;
    BOOL lipoFailed = NO;

    NSUInteger bIdx;
    for (bIdx = 0; bIdx < item.relativeFatBinaryPaths.count; bIdx++) {
        NSString *relPath = item.relativeFatBinaryPaths[bIdx];
        NSString *targetBin = [stagedAppPath stringByAppendingPathComponent:relPath];
        struct stat stBefore;
        if (stat([targetBin fileSystemRepresentation], &stBefore) != 0 || !S_ISREG(stBefore.st_mode)) {
            continue;
        }

        mode_t origMode = stBefore.st_mode & 07777;
        chmod([targetBin fileSystemRepresentation], origMode | S_IWUSR);

        NSString *tmpOutBin = [targetBin stringByAppendingString:@".cleaner_slim"];
        int lipoRc = LMSlimRunToolSync(@"/usr/bin/lipo", @[@"-remove", archToRemove, targetBin, @"-output", tmpOutBin]);
        if (lipoRc != 0 || ![fm fileExistsAtPath:tmpOutBin]) {
            [fm removeItemAtPath:tmpOutBin error:nil];
            lipoFailed = YES;
            break;
        }

        struct stat stAfter;
        if (stat([tmpOutBin fileSystemRepresentation], &stAfter) == 0 && stAfter.st_size > 0 && stBefore.st_size > stAfter.st_size) {
            chmod([tmpOutBin fileSystemRepresentation], origMode);
            if (rename([tmpOutBin fileSystemRepresentation], [targetBin fileSystemRepresentation]) == 0) {
                actualSaved += (uint64_t)(stBefore.st_size - stAfter.st_size);
            } else {
                [fm removeItemAtPath:tmpOutBin error:nil];
                lipoFailed = YES;
                break;
            }
        } else {
            [fm removeItemAtPath:tmpOutBin error:nil];
        }
    }

    if (lipoFailed || actualSaved == 0) {
        [fm removeItemAtPath:stageRoot error:nil];
        if (outError) *outError = LMToolLocalized(@"剥离冗余架构切片失败，原应用未做任何修改", @"lipo architecture stripping failed; original app untouched");
        return NO;
    }

    // 3. 清除隔离属性并执行本地 Ad-hoc 深度重签与完整性校验
    LMSlimRunToolSync(@"/usr/bin/xattr", @[@"-cr", stagedAppPath]);
    int signRc = LMSlimRunToolSync(@"/usr/bin/codesign", @[@"--force", @"--deep", @"--sign", @"-", stagedAppPath]);
    int verifyRc = (signRc == 0) ? LMSlimRunToolSync(@"/usr/bin/codesign", @[@"--verify", @"--deep", stagedAppPath]) : -1;
    if (signRc != 0 || verifyRc != 0) {
        [fm removeItemAtPath:stageRoot error:nil];
        if (outError) *outError = LMToolLocalized(@"重签名校验未通过，已自动回滚并保留原应用", @"Code signature verification failed; safely aborted");
        return NO;
    }

    // 4. 替换原应用（优先当前用户权限操作；若 /Applications 受 root 权限保护则走 STPrivilegedTask）
    NSString *parentDir = [item.appPath stringByDeletingLastPathComponent];
    BOOL userWritable = ([fm isWritableFileAtPath:parentDir] && [fm isWritableFileAtPath:item.appPath]);
    BOOL swapSucceeded = NO;

    if (userWritable) {
        if (moveToTrash) {
            __block BOOL trashed = NO;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            [[NSWorkspace sharedWorkspace] recycleURLs:@[[NSURL fileURLWithPath:item.appPath]]
                                     completionHandler:^(NSDictionary<NSURL *,NSURL *> *newURLs, NSError *error) {
                trashed = (newURLs.count > 0 || ![fm fileExistsAtPath:item.appPath]);
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            if (trashed) {
                swapSucceeded = [fm moveItemAtPath:stagedAppPath toPath:item.appPath error:nil];
            }
        } else {
            if ([fm removeItemAtPath:item.appPath error:nil]) {
                swapSucceeded = [fm moveItemAtPath:stagedAppPath toPath:item.appPath error:nil];
            }
        }
    }

    if (!swapSucceeded) {
        // 特权替换通道（当应用在 /Applications 下属 root:wheel 时）
        if (moveToTrash) {
            NSString *trashDest = [[NSHomeDirectory() stringByAppendingPathComponent:@".Trash"]
                                   stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_backup_%d.app",
                                                                   [[item.appPath lastPathComponent] stringByDeletingPathExtension],
                                                                   (int)[[NSDate date] timeIntervalSince1970]]];
            STPrivilegedTask *mvTrash = [[STPrivilegedTask alloc] initWithLaunchPath:@"/bin/mv"
                                                                           arguments:@[item.appPath, trashDest]];
            if ([mvTrash launch] == 0) {
                [mvTrash waitUntilExit];
            }
        } else {
            STPrivilegedTask *rmOrig = [[STPrivilegedTask alloc] initWithLaunchPath:@"/bin/rm"
                                                                          arguments:@[@"-rf", item.appPath]];
            if ([rmOrig launch] == 0) {
                [rmOrig waitUntilExit];
            }
        }

        if (![fm fileExistsAtPath:item.appPath]) {
            STPrivilegedTask *mvNew = [[STPrivilegedTask alloc] initWithLaunchPath:@"/bin/mv"
                                                                         arguments:@[stagedAppPath, item.appPath]];
            if ([mvNew launch] == 0) {
                [mvNew waitUntilExit];
                swapSucceeded = ([mvNew terminationStatus] == 0 && [fm fileExistsAtPath:item.appPath]);
            }
        }
    }

    [fm removeItemAtPath:stageRoot error:nil];

    if (!swapSucceeded) {
        if (outError) *outError = LMToolLocalized(@"替换应用目录权限不足或取消授权", @"Permission denied while replacing application bundle");
        return NO;
    }

    if (outReclaimed) {
        *outReclaimed = actualSaved;
    }
    return YES;
}

@end
