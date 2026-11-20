//
//  InstallAppHelper.m
//  LemonClener
//
//  Copyright © 2018年 Tencent. All rights reserved.
//

#import "InstallAppHelper.h"

@implementation InstallAppHelper

// 白名单：无标准位置垃圾或存在数据误删风险的应用
static NSArray<NSString *> *getWhiteAppList(void) {
    static NSArray<NSString *> *whiteAppLists = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        whiteAppLists = @[
            @"io.realm.realmbrowser",
            @"com.zennaware.cornerstone3.mas",
            @"com.sqlabs.sqlitemanager4"
        ];
    });
    return whiteAppLists;
}

/// 判断应用物理路径是否位于 macOS 系统只读核心卷（Safari 除外，需供“上网垃圾”模块匹配）
static BOOL LMIsReadOnlySystemApplication(NSURL *appURL, NSString *bundleIdentifier) {
    if ([bundleIdentifier isEqualToString:@"com.apple.Safari"]) {
        return NO;
    }
    NSURL *resolvedURL = [appURL URLByResolvingSymlinksInPath];
    NSString *resolvedPath = [resolvedURL path] ?: [appURL path];
    if (resolvedPath.length == 0) {
        return YES;
    }
    if ([resolvedPath hasPrefix:@"/System/Applications/"] ||
        [resolvedPath hasPrefix:@"/System/Library/"]) {
        return YES;
    }
    return NO;
}

/// 递归（最高 2 层）收集指定应用根目录下的全部 .app Bundle URL
static void LMCollectAppBundlesInDirectory(NSURL *rootDirURL, NSMutableArray<NSURL *> *outAppURLs) {
    if (rootDirURL == nil || outAppURLs == nil) {
        return;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fileManager fileExistsAtPath:[rootDirURL path] isDirectory:&isDir] || !isDir) {
        return;
    }

    NSError *error = nil;
    NSArray<NSURL *> *topLevelURLs = [fileManager contentsOfDirectoryAtURL:rootDirURL
                                                includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsPackageKey]
                                                                   options:NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsPackageDescendants
                                                                     error:&error];
    if (topLevelURLs.count == 0) {
        return;
    }

    for (NSURL *entryURL in topLevelURLs) {
        NSString *entryPath = [entryURL path];
        if (entryPath.length == 0) {
            continue;
        }
        if ([[[entryPath pathExtension] lowercaseString] isEqualToString:@"app"]) {
            [outAppURLs addObject:entryURL];
            continue;
        }
        BOOL subIsDir = NO;
        if ([fileManager fileExistsAtPath:entryPath isDirectory:&subIsDir] && subIsDir) {
            NSArray<NSURL *> *secondLevelURLs = [fileManager contentsOfDirectoryAtURL:entryURL
                                                           includingPropertiesForKeys:nil
                                                                              options:NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsPackageDescendants
                                                                                error:nil];
            for (NSURL *subURL in secondLevelURLs) {
                NSString *subPath = [subURL path];
                if (subPath.length > 0 && [[[subPath pathExtension] lowercaseString] isEqualToString:@"app"]) {
                    [outAppURLs addObject:subURL];
                }
            }
        }
    }
}

+ (NSMutableDictionary *)getInstallBundleIds {
    NSMutableDictionary *installBundleIdDic = [[NSMutableDictionary alloc] init];
    NSMutableArray<NSURL *> *appCandidateURLs = [[NSMutableArray alloc] init];

    @try {
        // 1. /Applications 全局应用目录
        NSArray<NSURL *> *localAppDirs = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationDirectory inDomains:NSLocalDomainMask];
        for (NSURL *dirURL in localAppDirs) {
            LMCollectAppBundlesInDirectory(dirURL, appCandidateURLs);
        }

        // 2. ~/Applications 用户级应用目录（JetBrains Toolbox / Chrome Apps / Homebrew Cask User 等）
        NSString *userAppsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications"];
        LMCollectAppBundlesInDirectory([NSURL fileURLWithPath:userAppsPath isDirectory:YES], appCandidateURLs);

        // 3. Setapp 订阅应用目录
        NSString *setappPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Setapp/Applications"];
        LMCollectAppBundlesInDirectory([NSURL fileURLWithPath:setappPath isDirectory:YES], appCandidateURLs);
    } @catch (NSException *exception) {
        NSLog(@"getInstallBundleIds collect exception = %@", exception);
    }

    NSString *selfBundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    NSArray<NSString *> *whiteAppList = getWhiteAppList();

    for (NSURL *appUrl in appCandidateURLs) {
        NSString *path = [appUrl path];
        if (path.length == 0 || ![[[path pathExtension] lowercaseString] isEqualToString:@"app"]) {
            continue;
        }

        NSBundle *appBundle = [NSBundle bundleWithURL:appUrl];
        NSString *appIdentifier = [appBundle bundleIdentifier];
        if (appIdentifier == nil || appIdentifier.length == 0) {
            NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Contents/Info.plist"]];
            appIdentifier = [plistDict objectForKey:@"CFBundleIdentifier"];
        }
        if (appIdentifier == nil || appIdentifier.length == 0) {
            continue;
        }

        // 过滤 macOS 系统只读卷内置组件
        if (LMIsReadOnlySystemApplication(appUrl, appIdentifier)) {
            continue;
        }

        // 过滤自身
        if ([appIdentifier isEqualToString:@"com.tencent.Lemon"] ||
            [appIdentifier isEqualToString:@"com.tencent.LemonLite"] ||
            (selfBundleId.length > 0 && [appIdentifier isEqualToString:selfBundleId])) {
            continue;
        }

        // 过滤微软 Office 套件防止许可证或配置丢失，保留 Edge 与 VS Code
        if (![appIdentifier containsString:@"com.microsoft.edgemac"] &&
            [appIdentifier containsString:@"com.microsoft"] &&
            ![appIdentifier isEqualToString:@"com.microsoft.VSCode"]) {
            continue;
        }

        // 过滤白名单软件
        if ([whiteAppList containsObject:appIdentifier]) {
            continue;
        }

        [installBundleIdDic setValue:path forKey:appIdentifier];
    }

    // 4. 第三方输入法目录 (/Library/Input Methods & ~/Library/Input Methods)
    NSArray<NSURL *> *inputUrls = [[NSFileManager defaultManager] URLsForDirectory:NSInputMethodsDirectory inDomains:NSLocalDomainMask | NSUserDomainMask];
    for (NSURL *inputDirURL in inputUrls) {
        @try {
            NSArray<NSURL *> *inputInstallArr = [[NSFileManager defaultManager]
                                                 contentsOfDirectoryAtURL:inputDirURL
                                                 includingPropertiesForKeys:nil
                                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                                 error:nil];
            for (NSURL *appUrl in inputInstallArr) {
                NSString *path = [appUrl path];
                if (path.length == 0 || ![[[path pathExtension] lowercaseString] isEqualToString:@"app"]) {
                    continue;
                }
                NSBundle *appBundle = [NSBundle bundleWithURL:appUrl];
                NSString *appIdentifier = [appBundle bundleIdentifier];
                if (appIdentifier.length == 0 || [appIdentifier hasPrefix:@"com.apple."]) {
                    continue;
                }
                [installBundleIdDic setValue:path forKey:appIdentifier];
            }
        } @catch (NSException *exception) {
            NSLog(@"getInstallBundleIds inputMethods exception = %@", exception);
        }
    }

    return installBundleIdDic;
}

@end
