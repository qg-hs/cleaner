//
//  QMItemCreateHelper.m
//  LemonClener
//
//  Copyright © 2019年 Tencent. All rights reserved.
//
//  动态识别本地已安装第三方应用的缓存与日志路径并构建扫描子项
//

#import "QMItemCreateHelper.h"
#import "QMActionItem.h"
#import "LMAppSandboxHelper.h"
#import <QMCoreFunction/LanguageHelper.h>
#include <dirent.h>
#include <sys/stat.h>

typedef NS_ENUM(NSUInteger, CreateActionItemType) {
    CreateActionItemTypeCache,
    CreateActionItemTypeLogs,
    CreateActionItemTypeData,
};

@implementation QMItemCreateHelper

/// O(1) 短路式递归检测目录内是否存在至少一个非空有效文件（最大探测深度 3 层，忽略 .DS_Store 与 .localized）
static BOOL LMDirectoryHasNonEmptyFileRecursive(const char *dirPath, int depth) {
    if (dirPath == NULL || depth > 3) {
        return NO;
    }
    DIR *dir = opendir(dirPath);
    if (dir == NULL) {
        return NO;
    }
    BOOL found = NO;
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        const char *name = entry->d_name;
        if (strcmp(name, ".") == 0 ||
            strcmp(name, "..") == 0 ||
            strcmp(name, ".DS_Store") == 0 ||
            strcmp(name, ".localized") == 0) {
            continue;
        }
        char childPath[PATH_MAX];
        int written = snprintf(childPath, sizeof(childPath), "%s/%s", dirPath, name);
        if (written <= 0 || (size_t)written >= sizeof(childPath)) {
            continue;
        }
        struct stat st;
        if (lstat(childPath, &st) != 0) {
            continue;
        }
        if (S_ISREG(st.st_mode)) {
            if (st.st_size > 0) {
                found = YES;
                break;
            }
        } else if (S_ISDIR(st.st_mode)) {
            if (LMDirectoryHasNonEmptyFileRecursive(childPath, depth + 1)) {
                found = YES;
                break;
            }
        }
    }
    closedir(dir);
    return found;
}

+ (BOOL)hasCleanableFilesAtPath:(NSString *)rawPath {
    if (rawPath == nil || rawPath.length == 0) {
        return NO;
    }
    NSString *expandedPath = [rawPath stringByExpandingTildeInPath];
    // 若路径包含正则分组（如 CoreSimulator Volumes/(.+)/...），截取静态前缀目录进行存在性判断
    NSRange regexRange = [expandedPath rangeOfString:@"("];
    if (regexRange.location != NSNotFound) {
        NSString *prefix = [expandedPath substringToIndex:regexRange.location];
        expandedPath = [prefix stringByDeletingLastPathComponent];
    }
    if (expandedPath.length == 0) {
        return NO;
    }
    const char *cPath = [expandedPath fileSystemRepresentation];
    if (cPath == NULL) {
        return NO;
    }
    struct stat st;
    if (lstat(cPath, &st) != 0) {
        return NO;
    }
    if (S_ISREG(st.st_mode)) {
        return (st.st_size > 0);
    }
    if (S_ISDIR(st.st_mode)) {
        return LMDirectoryHasNonEmptyFileRecursive(cPath, 0);
    }
    return NO;
}

+ (BOOL)subItemHasAnyCleanablePath:(QMCategorySubItem *)subItem {
    if (subItem == nil || subItem.m_actionItemArray.count == 0) {
        return NO;
    }
    NSString *sysTempCPath = [[NSTemporaryDirectory() stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"C"];
    for (QMActionItem *actionItem in subItem.m_actionItemArray) {
        for (QMActionPathItem *pathItem in actionItem.pathItemArray) {
            if ([pathItem.type isEqualToString:@"abs"]) {
                if ([self hasCleanableFilesAtPath:pathItem.value]) {
                    return YES;
                }
            } else if ([pathItem.type isEqualToString:@"special"] &&
                       [pathItem.value isEqualToString:@"SystemTempDir"] &&
                       pathItem.value1.length > 0) {
                NSString *candidate = [sysTempCPath stringByAppendingPathComponent:pathItem.value1];
                if ([self hasCleanableFilesAtPath:candidate]) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

/// 属于“上网垃圾”独立分类的浏览器 Bundle ID 集合，在“应用垃圾”中跳过以避免重复
static NSSet<NSString *> *LMBrowserBundleIdBlacklist(void) {
    static NSSet<NSString *> *browserSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        browserSet = [NSSet setWithArray:@[
            @"com.apple.Safari",
            @"com.google.Chrome",
            @"com.google.Chrome.canary",
            @"com.operasoftware.Opera",
            @"org.mozilla.firefox",
            @"com.tencent.QQBrowser",
            @"com.quark.desktop",
            @"com.microsoft.edgemac",
            @"company.thebrowser.Browser",
            @"com.brave.Browser"
        ]];
    });
    return browserSet;
}

/// 归集本地未在 XML 特化规则中声明的第三方应用，仅挂载磁盘上实际存在缓存或日志的应用
+ (void)createAllSoftAdaptCategorySubItemWithInstallArr:(NSDictionary *)installBundleIdDic
                                        curCategoryItem:(QMCategoryItem *)categoryItem {
    if (installBundleIdDic == nil || installBundleIdDic.count == 0 || categoryItem == nil) {
        return;
    }

    NSSet<NSString *> *browserBlacklist = LMBrowserBundleIdBlacklist();

    // 预读四大顶层目录快照，将后续每个应用的目录匹配降为内存级 O(K) 查找
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *homeDir = NSHomeDirectory();
    NSString *cachesRoot = [homeDir stringByAppendingPathComponent:@"Library/Caches"];
    NSString *containersRoot = [homeDir stringByAppendingPathComponent:@"Library/Containers"];
    NSString *appSupportRoot = [homeDir stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *logsRoot = [homeDir stringByAppendingPathComponent:@"Library/Logs"];

    NSArray<NSString *> *cachesEntries = [fm contentsOfDirectoryAtPath:cachesRoot error:nil] ?: @[];
    NSArray<NSString *> *containersEntries = [fm contentsOfDirectoryAtPath:containersRoot error:nil] ?: @[];
    NSSet<NSString *> *appSupportSet = [NSSet setWithArray:([fm contentsOfDirectoryAtPath:appSupportRoot error:nil] ?: @[])];
    NSSet<NSString *> *logsSet = [NSSet setWithArray:([fm contentsOfDirectoryAtPath:logsRoot error:nil] ?: @[])];

    NSArray<NSString *> *sortedBundleIds = [[installBundleIdDic allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<QMCategorySubItem *> *dynamicItems = [[NSMutableArray alloc] init];

    for (NSString *bundleId in sortedBundleIds) {
        if (bundleId.length == 0) {
            continue;
        }
        // 严格屏蔽所有 com.apple.* 系统原生组件，防止系统自带应用被误扫
        if ([bundleId hasPrefix:@"com.apple."] || [bundleId containsString:@"com.apple."]) {
            continue;
        }
        // 屏蔽已归入“上网垃圾”的浏览器应用
        if ([browserBlacklist containsObject:bundleId]) {
            continue;
        }

        NSString *appPath = [installBundleIdDic objectForKey:bundleId];
        if (![appPath isKindOfClass:[NSString class]] || appPath.length == 0) {
            continue;
        }

        QMCategorySubItem *subCateItem = [self createDynamicSubItemForBundleId:bundleId
                                                                       appPath:appPath
                                                                    cachesRoot:cachesRoot
                                                                 cachesEntries:cachesEntries
                                                                containersRoot:containersRoot
                                                             containersEntries:containersEntries
                                                                appSupportRoot:appSupportRoot
                                                                 appSupportSet:appSupportSet
                                                                      logsRoot:logsRoot
                                                                       logsSet:logsSet];
        if (subCateItem != nil) {
            [dynamicItems addObject:subCateItem];
        }
    }

    // 按应用展示名称排序后挂载至分类
    [dynamicItems sortUsingComparator:^NSComparisonResult(QMCategorySubItem *a, QMCategorySubItem *b) {
        return [a.title localizedStandardCompare:b.title];
    }];

    for (QMCategorySubItem *subItem in dynamicItems) {
        [categoryItem addSubCategoryItem:subItem];
    }
}

+ (QMCategorySubItem *)createDynamicSubItemForBundleId:(NSString *)bundleId
                                               appPath:(NSString *)appPath
                                            cachesRoot:(NSString *)cachesRoot
                                         cachesEntries:(NSArray<NSString *> *)cachesEntries
                                        containersRoot:(NSString *)containersRoot
                                     containersEntries:(NSArray<NSString *> *)containersEntries
                                        appSupportRoot:(NSString *)appSupportRoot
                                         appSupportSet:(NSSet<NSString *> *)appSupportSet
                                              logsRoot:(NSString *)logsRoot
                                               logsSet:(NSSet<NSString *> *)logsSet {
    NSBundle *appBundle = [NSBundle bundleWithPath:appPath];
    NSDictionary *infoDict = [appBundle infoDictionary];
    if (infoDict == nil) {
        infoDict = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
    }
    NSDictionary *localizedInfoDict = [appBundle localizedInfoDictionary];

    NSString *folderBaseName = [[[appPath lastPathComponent] stringByDeletingPathExtension] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *appSearchName = infoDict[(NSString *)kCFBundleNameKey];
    if (![appSearchName isKindOfClass:[NSString class]] || appSearchName.length == 0) {
        appSearchName = infoDict[@"CFBundleDisplayName"];
    }
    if (![appSearchName isKindOfClass:[NSString class]] || appSearchName.length == 0) {
        appSearchName = folderBaseName;
    }

    NSString *appDisplayName = localizedInfoDict[@"CFBundleDisplayName"];
    if (![appDisplayName isKindOfClass:[NSString class]] || appDisplayName.length == 0) {
        appDisplayName = localizedInfoDict[(NSString *)kCFBundleNameKey];
    }
    if (![appDisplayName isKindOfClass:[NSString class]] || appDisplayName.length == 0) {
        NSString *finderDisplayName = [[[NSFileManager defaultManager] displayNameAtPath:appPath] stringByDeletingPathExtension];
        if (finderDisplayName.length > 0) {
            appDisplayName = finderDisplayName;
        }
    }
    if (![appDisplayName isKindOfClass:[NSString class]] || appDisplayName.length == 0) {
        appDisplayName = appSearchName;
    }
    if (appDisplayName.length == 0) {
        return nil;
    }

    // 1. 探测该应用在本地真实存在且非空的缓存路径集合
    NSMutableOrderedSet<NSString *> *validCachePaths = [[NSMutableOrderedSet alloc] init];
    NSString *bundlePrefixDot = [bundleId stringByAppendingString:@"."];

    for (NSString *entry in cachesEntries) {
        if ([entry isEqualToString:bundleId] ||
            [entry hasPrefix:bundlePrefixDot] ||
            (appSearchName.length >= 3 && [entry caseInsensitiveCompare:appSearchName] == NSOrderedSame)) {
            NSString *fullPath = [cachesRoot stringByAppendingPathComponent:entry];
            if ([self hasCleanableFilesAtPath:fullPath]) {
                [validCachePaths addObject:fullPath];
            }
        }
    }

    // 沙盒容器 Caches（支持标准 <bundleId> 与 <TeamID>.<bundleId>）
    NSString *dotBundleSuffix = [@"." stringByAppendingString:bundleId];
    NSMutableArray<NSString *> *matchedContainers = [[NSMutableArray alloc] init];
    for (NSString *containerEntry in containersEntries) {
        if ([containerEntry isEqualToString:bundleId] || [containerEntry hasSuffix:dotBundleSuffix]) {
            [matchedContainers addObject:containerEntry];
            NSString *containerCachePath = [[containersRoot stringByAppendingPathComponent:containerEntry] stringByAppendingPathComponent:@"Data/Library/Caches"];
            if ([self hasCleanableFilesAtPath:containerCachePath]) {
                [validCachePaths addObject:containerCachePath];
            }
        }
    }

    // Electron / Chromium / CEF 架构在 ~/Library/Application Support/<App>/ 下的安全缓存子目录
    static NSArray<NSString *> *safeAppSupportCacheSubdirs = nil;
    static dispatch_once_t cacheSubdirsToken;
    dispatch_once(&cacheSubdirsToken, ^{
        safeAppSupportCacheSubdirs = @[
            @"Cache",
            @"Code Cache",
            @"GPUCache",
            @"CachedData",
            @"CachedExtensionVSIXs",
            @"DawnCache",
            @"GraphiteDawnCache",
            @"ShaderCache",
            @"Service Worker/CacheStorage",
            @"Service Worker/ScriptCache"
        ];
    });

    NSMutableOrderedSet<NSString *> *appSupportCandidates = [[NSMutableOrderedSet alloc] init];
    if ([appSupportSet containsObject:bundleId]) {
        [appSupportCandidates addObject:bundleId];
    }
    if (appSearchName.length > 0 && [appSupportSet containsObject:appSearchName]) {
        [appSupportCandidates addObject:appSearchName];
    }
    if (folderBaseName.length > 0 && [appSupportSet containsObject:folderBaseName]) {
        [appSupportCandidates addObject:folderBaseName];
    }
    if (appDisplayName.length > 0 && [appSupportSet containsObject:appDisplayName]) {
        [appSupportCandidates addObject:appDisplayName];
    }

    for (NSString *supportDirName in appSupportCandidates) {
        NSString *supportBase = [appSupportRoot stringByAppendingPathComponent:supportDirName];
        for (NSString *subCacheRel in safeAppSupportCacheSubdirs) {
            NSString *fullSubCachePath = [supportBase stringByAppendingPathComponent:subCacheRel];
            if ([self hasCleanableFilesAtPath:fullSubCachePath]) {
                [validCachePaths addObject:fullSubCachePath];
            }
        }
    }

    // 系统临时缓存目录 /var/folders/.../C/<bundleId>
    NSString *sysTempCPath = [[[NSTemporaryDirectory() stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"C"] stringByAppendingPathComponent:bundleId];
    if ([self hasCleanableFilesAtPath:sysTempCPath]) {
        [validCachePaths addObject:sysTempCPath];
    }

    // 2. 探测该应用在本地真实存在且非空的日志路径集合
    NSMutableOrderedSet<NSString *> *validLogPaths = [[NSMutableOrderedSet alloc] init];
    NSMutableOrderedSet<NSString *> *logCandidateNames = [[NSMutableOrderedSet alloc] initWithObjects:bundleId, nil];
    if (appSearchName.length > 0) {
        [logCandidateNames addObject:appSearchName];
    }
    if (folderBaseName.length > 0) {
        [logCandidateNames addObject:folderBaseName];
    }
    if (appDisplayName.length > 0) {
        [logCandidateNames addObject:appDisplayName];
    }

    for (NSString *logName in logCandidateNames) {
        if ([logsSet containsObject:logName]) {
            NSString *fullLogPath = [logsRoot stringByAppendingPathComponent:logName];
            if ([self hasCleanableFilesAtPath:fullLogPath]) {
                [validLogPaths addObject:fullLogPath];
            }
        }
    }

    for (NSString *containerEntry in matchedContainers) {
        NSString *containerLogPath = [[containersRoot stringByAppendingPathComponent:containerEntry] stringByAppendingPathComponent:@"Data/Library/Logs"];
        if ([self hasCleanableFilesAtPath:containerLogPath]) {
            [validLogPaths addObject:containerLogPath];
        }
    }

    static NSArray<NSString *> *safeAppSupportLogSubdirs = nil;
    static dispatch_once_t logSubdirsToken;
    dispatch_once(&logSubdirsToken, ^{
        safeAppSupportLogSubdirs = @[
            @"logs",
            @"Logs",
            @"Crashpad/completed"
        ];
    });

    for (NSString *supportDirName in appSupportCandidates) {
        NSString *supportBase = [appSupportRoot stringByAppendingPathComponent:supportDirName];
        for (NSString *subLogRel in safeAppSupportLogSubdirs) {
            NSString *fullSubLogPath = [supportBase stringByAppendingPathComponent:subLogRel];
            if ([self hasCleanableFilesAtPath:fullSubLogPath]) {
                [validLogPaths addObject:fullSubLogPath];
            }
        }
    }

    // 若该本地应用既无非空缓存目录，也无非空日志目录，直接跳过，不在界面产生 0 B 噪音项
    if (validCachePaths.count == 0 && validLogPaths.count == 0) {
        return nil;
    }

    BOOL isChinese = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeChinese);
    QMCategorySubItem *subItem = [[QMCategorySubItem alloc] init];
    subItem.subCategoryID = bundleId;
    subItem.bundleId = bundleId;
    subItem.title = appDisplayName;
    subItem.tips = isChinese
        ? [NSString stringWithFormat:@"清理 %@ 运行产生的缓存及日志文件", appDisplayName]
        : [NSString stringWithFormat:@"Clean caches and logs generated by %@", appDisplayName];
    subItem.fastMode = YES;
    subItem.showAction = YES;
    subItem.recommend = YES;
    subItem.isCautious = YES;
    subItem.defaultState = 1;

    if ([bundleId isEqualToString:@"com.google.android.studio"] ||
        [bundleId hasPrefix:@"com.jetbrains."] ||
        [bundleId containsString:@"com.bohemiancoding.sketch"]) {
        subItem.recommend = NO;
        subItem.isCautious = NO;
        subItem.fastMode = NO;
    }

    if (validCachePaths.count > 0) {
        QMActionItem *cacheActionItem = [[QMActionItem alloc] init];
        cacheActionItem.actionID = [NSString stringWithFormat:@"%@_cache", bundleId];
        cacheActionItem.type = QMActionFileType;
        cacheActionItem.bundleID = bundleId;
        cacheActionItem.appPath = appPath;
        cacheActionItem.recommend = subItem.recommend;
        cacheActionItem.state = subItem.recommend ? NSControlStateValueOn : NSControlStateValueOff;
        cacheActionItem.title = isChinese
            ? [NSString stringWithFormat:@"%@ 缓存", appDisplayName]
            : [NSString stringWithFormat:@"%@ Caches", appDisplayName];

        for (NSString *cacheDir in validCachePaths) {
            QMActionPathItem *pathItem = [self createPathItemWithType:@"abs" path:cacheDir bundleId:bundleId];
            [cacheActionItem addActionPathItem:pathItem];
        }
        [subItem addActionItem:cacheActionItem];
    }

    if (validLogPaths.count > 0) {
        QMActionItem *logActionItem = [[QMActionItem alloc] init];
        logActionItem.actionID = [NSString stringWithFormat:@"%@_logs", bundleId];
        logActionItem.type = QMActionFileType;
        logActionItem.bundleID = bundleId;
        logActionItem.appPath = appPath;
        logActionItem.recommend = YES;
        logActionItem.state = NSControlStateValueOn;
        logActionItem.title = isChinese
            ? [NSString stringWithFormat:@"%@ 日志", appDisplayName]
            : [NSString stringWithFormat:@"%@ Logs", appDisplayName];

        for (NSString *logDir in validLogPaths) {
            QMActionPathItem *pathItem = [self createPathItemWithType:@"abs" path:logDir bundleId:bundleId];
            [logActionItem addActionPathItem:pathItem];
        }
        [subItem addActionItem:logActionItem];
    }

    return subItem;
}

+ (QMCategorySubItem *)createSoftAdaptCategorySubItemWithId:(NSString *)subCateId
                                                DisplayName:(NSString *)appDisplayName
                                                 searchNane:(NSString *)appSearchName
                                                   bundleId:(NSString *)bundleId
                                                    appPath:(NSString *)appPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *homeDir = NSHomeDirectory();
    NSString *cachesRoot = [homeDir stringByAppendingPathComponent:@"Library/Caches"];
    NSString *containersRoot = [homeDir stringByAppendingPathComponent:@"Library/Containers"];
    NSString *appSupportRoot = [homeDir stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *logsRoot = [homeDir stringByAppendingPathComponent:@"Library/Logs"];

    NSArray<NSString *> *cachesEntries = [fm contentsOfDirectoryAtPath:cachesRoot error:nil] ?: @[];
    NSArray<NSString *> *containersEntries = [fm contentsOfDirectoryAtPath:containersRoot error:nil] ?: @[];
    NSSet<NSString *> *appSupportSet = [NSSet setWithArray:([fm contentsOfDirectoryAtPath:appSupportRoot error:nil] ?: @[])];
    NSSet<NSString *> *logsSet = [NSSet setWithArray:([fm contentsOfDirectoryAtPath:logsRoot error:nil] ?: @[])];

    return [self createDynamicSubItemForBundleId:(bundleId ?: subCateId)
                                         appPath:appPath
                                      cachesRoot:cachesRoot
                                   cachesEntries:cachesEntries
                                  containersRoot:containersRoot
                               containersEntries:containersEntries
                                  appSupportRoot:appSupportRoot
                                   appSupportSet:appSupportSet
                                        logsRoot:logsRoot
                                         logsSet:logsSet];
}

+ (QMActionPathItem *)createPathItemWithType:(NSString *)type
                                        path:(NSString *)path
                                    bundleId:(NSString *)bundleId {
    QMActionPathItem *pathItem = [[QMActionPathItem alloc] init];
    pathItem.type = type;
    pathItem.value = path;
    pathItem.level = 1;
    if (![type isEqualToString:@"abs"]) {
        pathItem.value1 = bundleId;
    }
    return pathItem;
}

+ (BOOL)isIncludeChineseInString:(NSString *)str {
    for (int i = 0; i < str.length; i++) {
        unichar ch = [str characterAtIndex:i];
        if (0x4E00 <= ch && ch <= 0x9FA5) {
            return YES;
        }
    }
    return NO;
}

@end
