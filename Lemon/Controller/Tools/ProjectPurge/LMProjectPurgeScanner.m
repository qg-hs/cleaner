//
//  LMProjectPurgeScanner.m
//  Lemon
//

#import "LMProjectPurgeScanner.h"
#include <fts.h>
#include <sys/stat.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdatomic.h>

static NSString * const kLMProjectPurgeDirsDefaultsKey = @"kLMProjectPurgeConfiguredDirs_v1";
static const int kLMMaxProjectScanDepth = 6;
static const uint64_t kLMMinArtifactSizeBytes = 64 * 1024; // 64 KB 以下空壳跳过

/// 使用 macOS 内核 getattrlistbulk 批量聚合目录物理分配块字节数（不跟随符号链接）
static uint64_t LMComputeDirectoryAllocatedSizeFast(const char *rootPath, atomic_bool *cancelFlag) {
    if (rootPath == NULL || (cancelFlag && atomic_load(cancelFlag))) {
        return 0;
    }

    uint64_t totalBytes = 0;
    NSMutableArray<NSString *> *dirStack = [[NSMutableArray alloc] initWithCapacity:64];
    NSString *initial = [NSString stringWithUTF8String:rootPath];
    if (!initial) {
        return 0;
    }
    [dirStack addObject:initial];

    struct attrlist attrList;
    memset(&attrList, 0, sizeof(attrList));
    attrList.bitmapcount = ATTR_BIT_MAP_COUNT;
    attrList.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_ERROR | ATTR_CMN_OBJTYPE;
    attrList.fileattr = ATTR_FILE_ALLOCSIZE;

    size_t bufSize = 64 * 1024;
    char *attrBuf = (char *)malloc(bufSize);
    if (attrBuf == NULL) {
        return 0;
    }

    while (dirStack.count > 0) {
        if (cancelFlag && atomic_load(cancelFlag)) {
            break;
        }
        @autoreleasepool {
            NSString *curDir = [dirStack lastObject];
            [dirStack removeLastObject];

            int fd = open([curDir fileSystemRepresentation], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (fd < 0) {
                continue;
            }

            while (1) {
                if (cancelFlag && atomic_load(cancelFlag)) {
                    break;
                }
                int retCount = getattrlistbulk(fd, &attrList, attrBuf, bufSize, 0);
                if (retCount <= 0) {
                    break;
                }
                char *entryPtr = attrBuf;
                int idx;
                for (idx = 0; idx < retCount; idx++) {
                    uint32_t entryLength = *(uint32_t *)entryPtr;
                    if (entryLength == 0) {
                        break;
                    }
                    char *fieldPtr = entryPtr + sizeof(uint32_t);
                    attribute_set_t returned = *(attribute_set_t *)fieldPtr;
                    fieldPtr += sizeof(attribute_set_t);

                    uint32_t errCode = 0;
                    if (returned.commonattr & ATTR_CMN_ERROR) {
                        errCode = *(uint32_t *)fieldPtr;
                        fieldPtr += sizeof(uint32_t);
                    }

                    const char *nameStr = NULL;
                    if (returned.commonattr & ATTR_CMN_NAME) {
                        attrreference_t nameRef = *(attrreference_t *)fieldPtr;
                        nameStr = fieldPtr + nameRef.attr_dataoffset;
                        fieldPtr += sizeof(attrreference_t);
                    }

                    fsobj_type_t objType = VNON;
                    if (returned.commonattr & ATTR_CMN_OBJTYPE) {
                        objType = *(fsobj_type_t *)fieldPtr;
                        fieldPtr += sizeof(fsobj_type_t);
                    }

                    off_t allocSize = 0;
                    if (returned.fileattr & ATTR_FILE_ALLOCSIZE) {
                        allocSize = *(off_t *)fieldPtr;
                        fieldPtr += sizeof(off_t);
                    }

                    if (errCode == 0 && nameStr != NULL) {
                        if (objType == VREG) {
                            if (allocSize > 0) {
                                totalBytes += (uint64_t)allocSize;
                            }
                        } else if (objType == VDIR) {
                            if (!(nameStr[0] == '.' && (nameStr[1] == '\0' || (nameStr[1] == '.' && nameStr[2] == '\0')))) {
                                NSString *childName = [NSString stringWithUTF8String:nameStr];
                                if (childName.length > 0) {
                                    [dirStack addObject:[curDir stringByAppendingPathComponent:childName]];
                                }
                            }
                        }
                    }

                    entryPtr += entryLength;
                }
            }
            close(fd);
        }
    }

    free(attrBuf);
    return totalBytes;
}

static BOOL LMFileExistsInDir(NSString *dirPath, NSArray<NSString *> *manifestNames) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger i;
    for (i = 0; i < manifestNames.count; i++) {
        NSString *candidate = [dirPath stringByAppendingPathComponent:manifestNames[i]];
        if ([fm fileExistsAtPath:candidate]) {
            return YES;
        }
    }
    return NO;
}

/// 校验候选构建产物目录是否处于合法的项目上下文，并返回项目根目录与技术栈标签
static BOOL LMResolveProjectContext(NSString *artifactPath,
                                    NSString *artifactName,
                                    NSString **outProjectRoot,
                                    NSString **outEcosystemTag,
                                    LMProjectEcosystem *outEcosystem) {
    NSString *parentDir = [artifactPath stringByDeletingLastPathComponent];
    NSString *grandParentDir = [parentDir stringByDeletingLastPathComponent];

    NSArray<NSString *> *nodeManifests = @[@"package.json", @"pnpm-workspace.yaml", @"tsconfig.json", @"deno.json"];
    NSArray<NSString *> *rustManifests = @[@"Cargo.toml"];
    NSArray<NSString *> *goManifests = @[@"go.mod", @"go.work"];
    NSArray<NSString *> *pyManifests = @[@"pyproject.toml", @"requirements.txt", @"setup.py", @"Pipfile"];
    NSArray<NSString *> *jvmManifests = @[@"pom.xml", @"build.gradle", @"build.gradle.kts", @"settings.gradle", @"settings.gradle.kts", @"build.sbt"];
    NSArray<NSString *> *appleManifests = @[@"Podfile", @"Package.swift"];
    NSArray<NSString *> *cppZigPhpManifests = @[@"CMakeLists.txt", @"Makefile", @"meson.build", @"build.zig", @"composer.json", @"Gemfile"];

    // 1. Node / Frontend 专属目录
    if ([artifactName isEqualToString:@"node_modules"] ||
        [artifactName isEqualToString:@".next"] ||
        [artifactName isEqualToString:@".nuxt"] ||
        [artifactName isEqualToString:@".output"] ||
        [artifactName isEqualToString:@".turbo"] ||
        [artifactName isEqualToString:@".parcel-cache"] ||
        [artifactName isEqualToString:@".svelte-kit"] ||
        [artifactName isEqualToString:@".angular"] ||
        [artifactName isEqualToString:@".vite"]) {
        if (LMFileExistsInDir(parentDir, nodeManifests)) {
            *outProjectRoot = parentDir;
        } else if (LMFileExistsInDir(grandParentDir, nodeManifests)) {
            *outProjectRoot = grandParentDir;
        } else if ([artifactName isEqualToString:@"node_modules"]) {
            *outProjectRoot = parentDir;
        } else {
            return NO;
        }
        *outEcosystemTag = @"Node.js";
        *outEcosystem = LMProjectEcosystemNode;
        return YES;
    }

    // 2. Python 专属目录
    if ([artifactName isEqualToString:@".venv"] ||
        [artifactName isEqualToString:@"venv"] ||
        [artifactName isEqualToString:@"__pycache__"] ||
        [artifactName isEqualToString:@".pytest_cache"] ||
        [artifactName isEqualToString:@".mypy_cache"] ||
        [artifactName isEqualToString:@".ruff_cache"] ||
        [artifactName isEqualToString:@".tox"]) {
        if ([artifactName isEqualToString:@"venv"]) {
            // 校验 pyvenv.cfg 或 bin/python 避免误判普通名为 venv 的目录
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:[artifactPath stringByAppendingPathComponent:@"pyvenv.cfg"]] &&
                ![fm fileExistsAtPath:[artifactPath stringByAppendingPathComponent:@"bin/python"]]) {
                return NO;
            }
        }
        *outProjectRoot = LMFileExistsInDir(parentDir, pyManifests) ? parentDir :
                          (LMFileExistsInDir(grandParentDir, pyManifests) ? grandParentDir : parentDir);
        *outEcosystemTag = @"Python";
        *outEcosystem = LMProjectEcosystemPython;
        return YES;
    }

    // 3. Apple / Xcode / CocoaPods / SwiftPM
    if ([artifactName isEqualToString:@"DerivedData"]) {
        *outProjectRoot = parentDir;
        *outEcosystemTag = @"Xcode";
        *outEcosystem = LMProjectEcosystemAppleJVM;
        return YES;
    }
    if ([artifactName isEqualToString:@"Pods"]) {
        if (LMFileExistsInDir(parentDir, @[@"Podfile"])) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"CocoaPods";
            *outEcosystem = LMProjectEcosystemAppleJVM;
            return YES;
        }
        return NO;
    }
    if ([artifactName isEqualToString:@".build"]) {
        if (LMFileExistsInDir(parentDir, appleManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"SwiftPM";
            *outEcosystem = LMProjectEcosystemAppleJVM;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, @[@"CMakeLists.txt"])) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"CMake";
            *outEcosystem = LMProjectEcosystemOther;
            return YES;
        }
        return NO;
    }

    // 4. Rust / Maven / Scala -> target
    if ([artifactName isEqualToString:@"target"]) {
        if (LMFileExistsInDir(parentDir, rustManifests) || LMFileExistsInDir(grandParentDir, rustManifests)) {
            *outProjectRoot = LMFileExistsInDir(parentDir, rustManifests) ? parentDir : grandParentDir;
            *outEcosystemTag = @"Rust";
            *outEcosystem = LMProjectEcosystemRustGo;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, jvmManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Maven/JVM";
            *outEcosystem = LMProjectEcosystemAppleJVM;
            return YES;
        }
        return NO;
    }

    // 5. Gradle
    if ([artifactName isEqualToString:@".gradle"]) {
        if (LMFileExistsInDir(parentDir, jvmManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Gradle";
            *outEcosystem = LMProjectEcosystemAppleJVM;
            return YES;
        }
        return NO;
    }

    // 6. Zig
    if ([artifactName isEqualToString:@"zig-cache"] ||
        [artifactName isEqualToString:@".zig-cache"] ||
        [artifactName isEqualToString:@"zig-out"]) {
        if (LMFileExistsInDir(parentDir, @[@"build.zig"])) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Zig";
            *outEcosystem = LMProjectEcosystemOther;
            return YES;
        }
        return NO;
    }

    // 7. 通用名 build / dist / out / coverage / vendor（强制要求清单文件匹配，杜绝误删普通文件夹）
    if ([artifactName isEqualToString:@"build"] ||
        [artifactName isEqualToString:@"dist"] ||
        [artifactName isEqualToString:@"out"] ||
        [artifactName isEqualToString:@"coverage"]) {
        if (LMFileExistsInDir(parentDir, nodeManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Node.js";
            *outEcosystem = LMProjectEcosystemNode;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, jvmManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Gradle/JVM";
            *outEcosystem = LMProjectEcosystemAppleJVM;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, pyManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Python";
            *outEcosystem = LMProjectEcosystemPython;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, goManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Go";
            *outEcosystem = LMProjectEcosystemRustGo;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, cppZigPhpManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"C/C++";
            *outEcosystem = LMProjectEcosystemOther;
            return YES;
        }
        return NO;
    }

    if ([artifactName isEqualToString:@"vendor"]) {
        if (LMFileExistsInDir(parentDir, @[@"composer.json"])) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"PHP";
            *outEcosystem = LMProjectEcosystemOther;
            return YES;
        }
        if (LMFileExistsInDir(parentDir, goManifests)) {
            *outProjectRoot = parentDir;
            *outEcosystemTag = @"Go";
            *outEcosystem = LMProjectEcosystemRustGo;
            return YES;
        }
        return NO;
    }

    return NO;
}

static NSDate *LMResolveProjectLastActiveDate(NSString *projectRoot, NSString *artifactPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDate *latest = nil;
    NSArray<NSString *> *probes = @[
        artifactPath,
        projectRoot,
        [projectRoot stringByAppendingPathComponent:@".git/index"],
        [projectRoot stringByAppendingPathComponent:@"package.json"],
        [projectRoot stringByAppendingPathComponent:@"Cargo.toml"],
        [projectRoot stringByAppendingPathComponent:@"go.mod"],
        [projectRoot stringByAppendingPathComponent:@"pyproject.toml"],
        [projectRoot stringByAppendingPathComponent:@"build.gradle"],
        [projectRoot stringByAppendingPathComponent:@"pom.xml"]
    ];
    NSUInteger i;
    for (i = 0; i < probes.count; i++) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:probes[i] error:nil];
        NSDate *mDate = attrs[NSFileModificationDate];
        if (mDate && (latest == nil || [mDate compare:latest] == NSOrderedDescending)) {
            latest = mDate;
        }
    }
    return latest ?: [NSDate distantPast];
}

@interface LMProjectPurgeScanner () {
    atomic_bool _cancelled;
}
@end

@implementation LMProjectPurgeScanner

+ (NSArray<NSString *> *)defaultScanDirectories {
    NSString *home = NSHomeDirectory();
    NSArray<NSString *> *candidates = @[
        @"Projects", @"Code", @"Workspace", @"Developer",
        @"Github", @"GitHub", @"repos", @"dev", @"work",
        @"Documents", @"Desktop"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *valid = [NSMutableArray array];
    NSMutableSet<NSString *> *seenRealPaths = [NSMutableSet set];
    NSUInteger i;
    for (i = 0; i < candidates.count; i++) {
        NSString *full = [home stringByAppendingPathComponent:candidates[i]];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            NSString *resolved = [full stringByResolvingSymlinksInPath];
            if (resolved.length > 0 && ![seenRealPaths containsObject:resolved]) {
                [seenRealPaths addObject:resolved];
                [valid addObject:resolved];
            }
        }
    }
    return valid;
}

+ (NSArray<NSString *> *)configuredScanDirectories {
    NSArray<NSString *> *saved = [[NSUserDefaults standardUserDefaults] stringArrayForKey:kLMProjectPurgeDirsDefaultsKey];
    if (saved != nil && saved.count > 0) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray<NSString *> *existing = [NSMutableArray array];
        NSUInteger i;
        for (i = 0; i < saved.count; i++) {
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:saved[i] isDirectory:&isDir] && isDir) {
                [existing addObject:saved[i]];
            }
        }
        if (existing.count > 0) {
            return existing;
        }
    }
    return [self defaultScanDirectories];
}

+ (void)saveConfiguredScanDirectories:(NSArray<NSString *> *)directories {
    if (directories == nil || directories.count == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLMProjectPurgeDirsDefaultsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:directories forKey:kLMProjectPurgeDirsDefaultsKey];
    }
}

/// 去除存在父子包含关系的重复扫描根目录，保证不重复扫描同一子树
+ (NSArray<NSString *> *)_deduplicateRootPaths:(NSArray<NSString *> *)rawDirs {
    NSMutableArray<NSString *> *resolved = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger i;
    for (i = 0; i < rawDirs.count; i++) {
        NSString *p = [[rawDirs[i] stringByExpandingTildeInPath] stringByResolvingSymlinksInPath];
        BOOL isDir = NO;
        if (p.length > 0 && [fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
            if (![resolved containsObject:p]) {
                [resolved addObject:p];
            }
        }
    }
    [resolved sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if (a.length < b.length) return NSOrderedAscending;
        if (a.length > b.length) return NSOrderedDescending;
        return [a compare:b];
    }];

    NSMutableArray<NSString *> *filtered = [NSMutableArray array];
    for (i = 0; i < resolved.count; i++) {
        NSString *candidate = resolved[i];
        BOOL covered = NO;
        NSUInteger j;
        for (j = 0; j < filtered.count; j++) {
            NSString *parent = [filtered[j] hasSuffix:@"/"] ? filtered[j] : [filtered[j] stringByAppendingString:@"/"];
            if ([candidate hasPrefix:parent]) {
                covered = YES;
                break;
            }
        }
        if (!covered) {
            [filtered addObject:candidate];
        }
    }
    return filtered;
}

- (void)cancelScan {
    atomic_store(&_cancelled, true);
}

- (void)startScanWithDirectories:(NSArray<NSString *> *)directories
                        progress:(LMProjectPurgeProgressBlock)progressBlock
                      completion:(LMProjectPurgeCompletionBlock)completionBlock {
    atomic_store(&_cancelled, false);
    NSArray<NSString *> *roots = [LMProjectPurgeScanner _deduplicateRootPaths:directories];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (roots.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(@[], NO);
            });
            return;
        }

        NSSet<NSString *> *skipDirNames = [NSSet setWithArray:@[
            @"Library", @".Trash", @"Applications", @"Pictures", @"Movies", @"Music",
            @".git", @".hg", @".svn", @".idea", @".vscode"
        ]];

        NSSet<NSString *> *targetArtifactNames = [NSSet setWithArray:@[
            @"node_modules", @".next", @".nuxt", @".output", @".turbo", @".parcel-cache",
            @".svelte-kit", @".angular", @".vite",
            @".venv", @"venv", @"__pycache__", @".pytest_cache", @".mypy_cache", @".ruff_cache", @".tox",
            @"DerivedData", @"Pods", @".build",
            @"target", @".gradle",
            @"zig-cache", @".zig-cache", @"zig-out",
            @"build", @"dist", @"out", @"coverage", @"vendor"
        ]];

        // 阶段一：fts_open 剪枝遍历定位候选产物目录（时间复杂度 O(V_project_skeleton)）
        NSMutableArray<LMProjectPurgeItem *> *candidates = [NSMutableArray array];
        char **cPaths = (char **)calloc(roots.count + 1, sizeof(char *));
        NSUInteger rIdx;
        for (rIdx = 0; rIdx < roots.count; rIdx++) {
            cPaths[rIdx] = strdup([roots[rIdx] fileSystemRepresentation]);
        }
        cPaths[roots.count] = NULL;

        FTS *ftsp = fts_open(cPaths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
        if (ftsp != NULL) {
            FTSENT *entry = NULL;
            NSUInteger stepCounter = 0;
            while ((entry = fts_read(ftsp)) != NULL) {
                if (atomic_load(&self->_cancelled)) {
                    break;
                }
                if (entry->fts_info != FTS_D) {
                    continue;
                }
                if (entry->fts_level == 0) {
                    continue;
                }
                if (entry->fts_level > kLMMaxProjectScanDepth) {
                    fts_set(ftsp, entry, FTS_SKIP);
                    continue;
                }

                NSString *dirName = [NSString stringWithUTF8String:entry->fts_name];
                if (dirName.length == 0) {
                    continue;
                }

                if ([skipDirNames containsObject:dirName] || [dirName hasSuffix:@".app"]) {
                    fts_set(ftsp, entry, FTS_SKIP);
                    continue;
                }

                stepCounter++;
                if (progressBlock && (stepCounter % 45 == 0)) {
                    NSString *curPath = [NSString stringWithUTF8String:entry->fts_path];
                    NSUInteger foundSoFar = candidates.count;
                    if (curPath) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            progressBlock(curPath, foundSoFar);
                        });
                    }
                }

                if ([targetArtifactNames containsObject:dirName]) {
                    NSString *fullPath = [NSString stringWithUTF8String:entry->fts_path];
                    if (fullPath.length > 0) {
                        NSString *projRoot = nil;
                        NSString *ecoTag = nil;
                        LMProjectEcosystem eco = LMProjectEcosystemOther;
                        if (LMResolveProjectContext(fullPath, dirName, &projRoot, &ecoTag, &eco)) {
                            // 命中构建产物，立即阻断向该产物内部（如百万文件的 node_modules）递归
                            fts_set(ftsp, entry, FTS_SKIP);

                            LMProjectPurgeItem *item = [[LMProjectPurgeItem alloc] init];
                            item.artifactPath = fullPath;
                            item.artifactName = dirName;
                            item.projectRootPath = projRoot ?: [fullPath stringByDeletingLastPathComponent];
                            item.projectName = [item.projectRootPath lastPathComponent];
                            item.ecosystemTag = ecoTag ?: @"Other";
                            item.ecosystem = eco;
                            [candidates addObject:item];
                        }
                    }
                }
            }
            fts_close(ftsp);
        }

        for (rIdx = 0; rIdx < roots.count; rIdx++) {
            free(cPaths[rIdx]);
        }
        free(cPaths);

        if (atomic_load(&self->_cancelled)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(@[], YES);
            });
            return;
        }

        // 阶段二：受控 8 路并发 getattrlistbulk 统计真实物理分配块大小与最近活跃时间
        NSMutableArray<LMProjectPurgeItem *> *sizedResults = [NSMutableArray arrayWithCapacity:candidates.count];
        NSLock *resultLock = [[NSLock alloc] init];
        dispatch_semaphore_t concurrencySem = dispatch_semaphore_create(8);
        dispatch_group_t sizeGroup = dispatch_group_create();
        NSDate *now = [NSDate date];

        NSUInteger cIdx;
        for (cIdx = 0; cIdx < candidates.count; cIdx++) {
            if (atomic_load(&self->_cancelled)) {
                break;
            }
            LMProjectPurgeItem *candidate = candidates[cIdx];
            dispatch_semaphore_wait(concurrencySem, DISPATCH_TIME_FOREVER);
            dispatch_group_async(sizeGroup, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool {
                    if (!atomic_load(&self->_cancelled)) {
                        if (progressBlock) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                progressBlock(candidate.artifactPath, candidates.count);
                            });
                        }
                        uint64_t bytes = LMComputeDirectoryAllocatedSizeFast([candidate.artifactPath fileSystemRepresentation], &self->_cancelled);
                        if (!atomic_load(&self->_cancelled) && bytes >= kLMMinArtifactSizeBytes) {
                            candidate.sizeInBytes = bytes;
                            NSDate *activeDate = LMResolveProjectLastActiveDate(candidate.projectRootPath, candidate.artifactPath);
                            candidate.lastModifiedDate = activeDate;
                            NSTimeInterval ageSec = [now timeIntervalSinceDate:activeDate];
                            NSInteger days = (ageSec > 0) ? (NSInteger)(ageSec / 86400.0) : 0;
                            candidate.daysSinceActive = days;
                            candidate.isRecent = (days < 7);
                            candidate.isSelected = !candidate.isRecent;

                            [resultLock lock];
                            [sizedResults addObject:candidate];
                            [resultLock unlock];
                        }
                    }
                    dispatch_semaphore_signal(concurrencySem);
                }
            });
        }

        dispatch_group_wait(sizeGroup, DISPATCH_TIME_FOREVER);

        if (atomic_load(&self->_cancelled)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(@[], YES);
            });
            return;
        }

        // 按占用体积降序排列
        [sizedResults sortUsingComparator:^NSComparisonResult(LMProjectPurgeItem *a, LMProjectPurgeItem *b) {
            if (a.sizeInBytes > b.sizeInBytes) return NSOrderedAscending;
            if (a.sizeInBytes < b.sizeInBytes) return NSOrderedDescending;
            return [a.projectName localizedCaseInsensitiveCompare:b.projectName];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock([sizedResults copy], NO);
        });
    });
}

@end
