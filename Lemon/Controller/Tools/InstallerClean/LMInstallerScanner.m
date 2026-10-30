//
//  LMInstallerScanner.m
//  Lemon
//

#import "LMInstallerScanner.h"
#include <fts.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdatomic.h>

static inline uint16_t LMReadLE16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline uint32_t LMReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/// O(1) I/O 零解压读取 ZIP 尾部中央目录（Central Directory），检测是否内嵌 macOS 安装载体 (.app / .pkg / .dmg)
static BOOL LMInspectZipForInstallerPayload(const char *zipPath,
                                            uint64_t fileSize,
                                            NSString **outPayloadFormat,
                                            NSString **outEmbeddedAppName) {
    if (zipPath == NULL || fileSize < 22) {
        return NO;
    }

    int fd = open(zipPath, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return NO;
    }

    size_t tailReadSize = (fileSize < 65557ULL) ? (size_t)fileSize : 65557;
    off_t tailOffset = (off_t)(fileSize - (uint64_t)tailReadSize);
    uint8_t *tailBuf = (uint8_t *)malloc(tailReadSize);
    if (tailBuf == NULL) {
        close(fd);
        return NO;
    }

    ssize_t got = pread(fd, tailBuf, tailReadSize, tailOffset);
    if (got < 22) {
        free(tailBuf);
        close(fd);
        return NO;
    }

    // 逆向搜索 EOCD 签名 0x06054b50
    ssize_t eocdPos = -1;
    ssize_t pos;
    for (pos = got - 22; pos >= 0; pos--) {
        if (tailBuf[pos] == 0x50 &&
            tailBuf[pos + 1] == 0x4b &&
            tailBuf[pos + 2] == 0x05 &&
            tailBuf[pos + 3] == 0x06) {
            eocdPos = pos;
            break;
        }
    }

    if (eocdPos < 0) {
        free(tailBuf);
        close(fd);
        return NO;
    }

    uint16_t totalEntries = LMReadLE16(tailBuf + eocdPos + 10);
    uint32_t cdSize = LMReadLE32(tailBuf + eocdPos + 12);
    uint32_t cdOffset = LMReadLE32(tailBuf + eocdPos + 16);
    free(tailBuf);

    // 过滤 ZIP64 超界或损坏头
    if (totalEntries == 0 || cdSize < 46 || cdOffset == 0xFFFFFFFFU || (uint64_t)cdOffset >= fileSize) {
        close(fd);
        return NO;
    }

    uint64_t avail = fileSize - (uint64_t)cdOffset;
    size_t readCDLen = (cdSize < avail) ? (size_t)cdSize : (size_t)avail;
    if (readCDLen > 512 * 1024) {
        readCDLen = 512 * 1024;
    }

    uint8_t *cdBuf = (uint8_t *)malloc(readCDLen);
    if (cdBuf == NULL) {
        close(fd);
        return NO;
    }

    ssize_t cdGot = pread(fd, cdBuf, readCDLen, (off_t)cdOffset);
    close(fd);

    if (cdGot < 46) {
        free(cdBuf);
        return NO;
    }

    BOOL isInstaller = NO;
    NSString *detectedFormat = nil;
    NSString *detectedApp = nil;

    size_t cursor = 0;
    NSUInteger inspected = 0;
    while (cursor + 46 <= (size_t)cdGot && inspected < 600) {
        if (!(cdBuf[cursor] == 0x50 &&
              cdBuf[cursor + 1] == 0x4b &&
              cdBuf[cursor + 2] == 0x01 &&
              cdBuf[cursor + 3] == 0x02)) {
            break;
        }

        uint16_t nameLen = LMReadLE16(cdBuf + cursor + 28);
        uint16_t extraLen = LMReadLE16(cdBuf + cursor + 30);
        uint16_t commentLen = LMReadLE16(cdBuf + cursor + 32);

        if (cursor + 46 + nameLen > (size_t)cdGot) {
            break;
        }

        if (nameLen > 0 && nameLen < 512) {
            NSString *entryName = [[NSString alloc] initWithBytes:(cdBuf + cursor + 46)
                                                           length:nameLen
                                                         encoding:NSUTF8StringEncoding];
            if (entryName != nil && ![entryName hasPrefix:@"__MACOSX/"]) {
                NSArray<NSString *> *parts = [entryName pathComponents];
                NSUInteger pIdx;
                for (pIdx = 0; pIdx < parts.count && pIdx < 3; pIdx++) {
                    NSString *comp = parts[pIdx];
                    NSString *lower = [comp lowercaseString];
                    if ([lower hasSuffix:@".app"]) {
                        isInstaller = YES;
                        detectedFormat = @"ZIP (.app)";
                        detectedApp = [comp stringByDeletingPathExtension];
                        break;
                    } else if ([lower hasSuffix:@".pkg"] || [lower hasSuffix:@".mpkg"]) {
                        isInstaller = YES;
                        detectedFormat = @"ZIP (.pkg)";
                        detectedApp = [comp stringByDeletingPathExtension];
                        break;
                    } else if ([lower hasSuffix:@".dmg"]) {
                        isInstaller = YES;
                        detectedFormat = @"ZIP (.dmg)";
                        detectedApp = [comp stringByDeletingPathExtension];
                        break;
                    }
                }
                if (isInstaller) {
                    break;
                }
            }
        }

        cursor += (46 + (size_t)nameLen + (size_t)extraLen + (size_t)commentLen);
        inspected++;
    }

    free(cdBuf);
    if (isInstaller) {
        if (outPayloadFormat) *outPayloadFormat = detectedFormat ?: @"ZIP";
        if (outEmbeddedAppName) *outEmbeddedAppName = detectedApp;
    }
    return isInstaller;
}

/// 剥离 Homebrew 缓存文件名的 64 位 SHA256-- 前缀
static NSString *LMCleanInstallerDisplayName(NSString *rawFileName) {
    if (rawFileName.length > 66) {
        NSRange sepRange = [rawFileName rangeOfString:@"--"];
        if (sepRange.location == 64) {
            BOOL allHex = YES;
            NSUInteger i;
            for (i = 0; i < 64; i++) {
                unichar c = [rawFileName characterAtIndex:i];
                BOOL isHex = ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'));
                if (!isHex) {
                    allHex = NO;
                    break;
                }
            }
            if (allHex) {
                return [rawFileName substringFromIndex:66];
            }
        }
    }
    return rawFileName;
}

/// 归一化软件名以便与 /Applications 已安装应用交叉比对
static NSString *LMNormalizeAppIdentifierToken(NSString *rawName) {
    if (rawName.length == 0) {
        return @"";
    }
    NSString *base = [[rawName stringByDeletingPathExtension] lowercaseString];
    // 截断常见版本号与架构后缀（如 -1.2.3, _arm64, -universal, -macos）
    NSArray<NSString *> *cutMarkers = @[@"-macos", @"_macos", @"-darwin", @"-arm64", @"_arm64", @"-aarch64", @"-x86_64", @"-universal", @"_universal"];
    NSUInteger i;
    for (i = 0; i < cutMarkers.count; i++) {
        NSRange r = [base rangeOfString:cutMarkers[i]];
        if (r.location != NSNotFound && r.location >= 2) {
            base = [base substringToIndex:r.location];
        }
    }
    NSMutableString *lettersOnly = [NSMutableString stringWithCapacity:base.length];
    for (i = 0; i < base.length; i++) {
        unichar c = [base characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c > 0x007F) {
            if (c >= '0' && c <= '9' && lettersOnly.length >= 3) {
                // 遇到应用名后的版本号数字即停止，保留如 iina / cleanmymacx / orbstack 等主体词
                break;
            }
            [lettersOnly appendFormat:@"%C", c];
        }
    }
    return lettersOnly;
}

static NSSet<NSString *> *LMCollectInstalledAppNormalizedTokens(void) {
    NSMutableSet<NSString *> *tokens = [NSMutableSet set];
    NSArray<NSString *> *appDirs = @[@"/Applications", [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger d;
    for (d = 0; d < appDirs.count; d++) {
        NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:appDirs[d] error:nil];
        NSUInteger i;
        for (i = 0; i < contents.count; i++) {
            NSString *entry = contents[i];
            if ([[entry pathExtension].lowercaseString isEqualToString:@"app"]) {
                NSString *tok = LMNormalizeAppIdentifierToken(entry);
                if (tok.length >= 3) {
                    [tokens addObject:tok];
                }
            }
        }
    }
    return tokens;
}

@interface LMInstallerScanner () {
    atomic_bool _cancelled;
}
@end

@implementation LMInstallerScanner

- (void)cancelScan {
    atomic_store(&_cancelled, true);
}

- (void)startScanWithProgress:(LMInstallerScanProgressBlock)progressBlock
                   completion:(LMInstallerScanCompletionBlock)completionBlock {
    atomic_store(&_cancelled, false);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *home = NSHomeDirectory();
        NSArray<NSDictionary *> *sources = @[
            @{ @"path": [home stringByAppendingPathComponent:@"Downloads"], @"tag": @"Downloads", @"group": @(LMInstallerSourceGroupLocal) },
            @{ @"path": [home stringByAppendingPathComponent:@"Desktop"], @"tag": @"Desktop", @"group": @(LMInstallerSourceGroupLocal) },
            @{ @"path": [home stringByAppendingPathComponent:@"Documents"], @"tag": @"Documents", @"group": @(LMInstallerSourceGroupLocal) },
            @{ @"path": [home stringByAppendingPathComponent:@"Public/Drop Box"], @"tag": @"Drop Box", @"group": @(LMInstallerSourceGroupLocal) },
            @{ @"path": [home stringByAppendingPathComponent:@"Library/Caches/Homebrew/downloads"], @"tag": @"Homebrew", @"group": @(LMInstallerSourceGroupHomebrew) },
            @{ @"path": [home stringByAppendingPathComponent:@"Library/Caches/Homebrew"], @"tag": @"Homebrew", @"group": @(LMInstallerSourceGroupHomebrew) },
            @{ @"path": [home stringByAppendingPathComponent:@"Library/Mobile Documents/com~apple~CloudDocs/Downloads"], @"tag": @"iCloud", @"group": @(LMInstallerSourceGroupApps) },
            @{ @"path": [home stringByAppendingPathComponent:@"Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], @"tag": @"Mail", @"group": @(LMInstallerSourceGroupApps) },
            @{ @"path": [home stringByAppendingPathComponent:@"Library/Application Support/Telegram Desktop"], @"tag": @"Telegram", @"group": @(LMInstallerSourceGroupApps) }
        ];

        NSSet<NSString *> *directExts = [NSSet setWithArray:@[@"dmg", @"pkg", @"mpkg", @"iso", @"xip"]];
        NSSet<NSString *> *installedAppTokens = LMCollectInstalledAppNormalizedTokens();

        NSMutableArray<LMInstallerItem *> *foundItems = [NSMutableArray array];
        NSMutableSet<NSString *> *seenInodes = [NSMutableSet set];
        NSFileManager *fm = [NSFileManager defaultManager];

        NSUInteger sIdx;
        for (sIdx = 0; sIdx < sources.count; sIdx++) {
            if (atomic_load(&self->_cancelled)) {
                break;
            }
            NSDictionary *src = sources[sIdx];
            NSString *rootPath = src[@"path"];
            NSString *sourceTag = src[@"tag"];
            LMInstallerSourceGroup group = (LMInstallerSourceGroup)[src[@"group"] integerValue];

            BOOL isDir = NO;
            if (![fm fileExistsAtPath:rootPath isDirectory:&isDir] || !isDir) {
                continue;
            }

            if (progressBlock) {
                NSUInteger countSnapshot = foundItems.count;
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressBlock(sourceTag, countSnapshot);
                });
            }

            char *cPaths[2] = { strdup([rootPath fileSystemRepresentation]), NULL };
            FTS *ftsp = fts_open(cPaths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
            if (ftsp != NULL) {
                FTSENT *entry = NULL;
                while ((entry = fts_read(ftsp)) != NULL) {
                    if (atomic_load(&self->_cancelled)) {
                        break;
                    }
                    if (entry->fts_level > 2) {
                        if (entry->fts_info == FTS_D) {
                            fts_set(ftsp, entry, FTS_SKIP);
                        }
                        continue;
                    }
                    if (entry->fts_info == FTS_D && entry->fts_level > 0) {
                        NSString *dName = [NSString stringWithUTF8String:entry->fts_name];
                        if ([dName hasSuffix:@".app"] || [dName hasSuffix:@".pkg"] || [dName hasSuffix:@".mpkg"]) {
                            // 目录形态的 .pkg / .mpkg 安装包
                            NSString *lowerExt = [[dName pathExtension] lowercaseString];
                            if ([lowerExt isEqualToString:@"pkg"] || [lowerExt isEqualToString:@"mpkg"]) {
                                fts_set(ftsp, entry, FTS_SKIP);
                                NSString *pkgPath = [NSString stringWithUTF8String:entry->fts_path];
                                if (pkgPath != nil && entry->fts_statp != NULL) {
                                    NSString *inodeKey = [NSString stringWithFormat:@"%d:%llu",
                                                          (int)entry->fts_statp->st_dev,
                                                          (unsigned long long)entry->fts_statp->st_ino];
                                    if (![seenInodes containsObject:inodeKey]) {
                                        [seenInodes addObject:inodeKey];
                                        // 统计包目录大小
                                        uint64_t pkgBytes = 0;
                                        NSDirectoryEnumerator *en = [fm enumeratorAtPath:pkgPath];
                                        NSString *sub = nil;
                                        while ((sub = [en nextObject]) != nil) {
                                            NSDictionary *at = [en fileAttributes];
                                            if ([at[NSFileType] isEqualToString:NSFileTypeRegular]) {
                                                pkgBytes += [at[NSFileSize] unsignedLongLongValue];
                                            }
                                        }
                                        if (pkgBytes > 0) {
                                            LMInstallerItem *item = [[LMInstallerItem alloc] init];
                                            item.filePath = pkgPath;
                                            item.displayName = LMCleanInstallerDisplayName(dName);
                                            item.sourceTag = sourceTag;
                                            item.sourceGroup = group;
                                            item.formatTag = [lowerExt uppercaseString];
                                            item.sizeInBytes = pkgBytes;
                                            item.modifiedDate = [NSDate dateWithTimeIntervalSince1970:entry->fts_statp->st_mtimespec.tv_sec];
                                            NSString *norm = LMNormalizeAppIdentifierToken(item.displayName);
                                            item.isAppAlreadyInstalled = (norm.length >= 3 && [installedAppTokens containsObject:norm]);
                                            item.isSelected = YES;
                                            [foundItems addObject:item];
                                        }
                                    }
                                }
                                continue;
                            }
                            fts_set(ftsp, entry, FTS_SKIP);
                            continue;
                        }
                        if ([dName hasPrefix:@"."]) {
                            fts_set(ftsp, entry, FTS_SKIP);
                            continue;
                        }
                    }

                    // 仅处理普通文件（跳过 Homebrew 顶层指向 downloads/ 的符号链接，避免误删软链本体而遗留大文件）
                    if (entry->fts_info != FTS_F || entry->fts_statp == NULL) {
                        continue;
                    }

                    uint64_t fSize = (uint64_t)entry->fts_statp->st_size;
                    if (fSize < 32 * 1024) {
                        continue; // 过滤 <32KB 的校验文件或损坏残片
                    }

                    NSString *fName = [NSString stringWithUTF8String:entry->fts_name];
                    if (fName.length == 0 || [fName hasPrefix:@"."] || [fName hasSuffix:@".incomplete"] || [fName hasSuffix:@".crdownload"] || [fName hasSuffix:@".download"]) {
                        continue;
                    }

                    NSString *ext = [[fName pathExtension] lowercaseString];
                    if (ext.length == 0) {
                        continue;
                    }

                    BOOL matched = NO;
                    NSString *formatBadge = nil;
                    NSString *embeddedApp = nil;

                    if ([directExts containsObject:ext]) {
                        matched = YES;
                        formatBadge = [ext uppercaseString];
                    } else if ([ext isEqualToString:@"zip"]) {
                        matched = LMInspectZipForInstallerPayload(entry->fts_path, fSize, &formatBadge, &embeddedApp);
                    }

                    if (!matched) {
                        continue;
                    }

                    NSString *inodeKey = [NSString stringWithFormat:@"%d:%llu",
                                          (int)entry->fts_statp->st_dev,
                                          (unsigned long long)entry->fts_statp->st_ino];
                    if ([seenInodes containsObject:inodeKey]) {
                        continue;
                    }
                    [seenInodes addObject:inodeKey];

                    NSString *fullFilePath = [NSString stringWithUTF8String:entry->fts_path];
                    if (fullFilePath.length == 0) {
                        continue;
                    }

                    LMInstallerItem *item = [[LMInstallerItem alloc] init];
                    item.filePath = fullFilePath;
                    item.displayName = LMCleanInstallerDisplayName(fName);
                    item.sourceTag = sourceTag;
                    item.sourceGroup = group;
                    item.formatTag = formatBadge ?: [ext uppercaseString];
                    item.detectedAppName = embeddedApp;
                    item.sizeInBytes = fSize;
                    item.modifiedDate = [NSDate dateWithTimeIntervalSince1970:entry->fts_statp->st_mtimespec.tv_sec];

                    NSString *probeName = (embeddedApp.length > 0) ? embeddedApp : item.displayName;
                    NSString *normToken = LMNormalizeAppIdentifierToken(probeName);
                    item.isAppAlreadyInstalled = (normToken.length >= 3 && [installedAppTokens containsObject:normToken]);
                    item.isSelected = YES;

                    [foundItems addObject:item];
                }
                fts_close(ftsp);
            }
            free(cPaths[0]);
        }

        if (atomic_load(&self->_cancelled)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(@[], YES);
            });
            return;
        }

        [foundItems sortUsingComparator:^NSComparisonResult(LMInstallerItem *a, LMInstallerItem *b) {
            if (a.sizeInBytes > b.sizeInBytes) return NSOrderedAscending;
            if (a.sizeInBytes < b.sizeInBytes) return NSOrderedDescending;
            return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSWorkspace *ws = [NSWorkspace sharedWorkspace];
            NSUInteger i;
            for (i = 0; i < foundItems.count; i++) {
                LMInstallerItem *it = foundItems[i];
                it.fileIcon = [ws iconForFile:it.filePath];
            }
            completionBlock([foundItems copy], NO);
        });
    });
}

@end
