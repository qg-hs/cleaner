//
//  LoginItemManager.m
//  LemonGroup
//
//  
//  Copyright © 2020 Tencent. All rights reserved.
//


#import "QMLoginItemManager.h"
#import "QMBaseLoginItem.h"
#import <dlfcn.h>
#import "QMAppLoginItem.h"
#import <ServiceManagement/SMLoginItem.h>
#import <ServiceManagement/ServiceManagement.h>
#import "QMLocalAppHelper.h"
#import <AppKit/NSWorkspace.h>
#include <unistd.h>

// FinalShell.app 的bundle id
static NSString * const kFinalShellAppBundleId = @"st";

@interface QMLoginItemManager ()

/**
 launchd service 文件存放的目录
 */
@property NSArray *launchServiceFilePathArray;

/*
 Save login items
 */
@property NSMutableArray *loginItemArray;


typedef char (*SMLoginItemSetEnabledWithURL_ptr) ( void* ptr, char enabled);

@end

///Login Item Manager
@implementation QMLoginItemManager

+ (instancetype)shareInstance {
    static QMLoginItemManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[QMLoginItemManager alloc] init];
        [instance initData];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initData];
    }
    return self;
}

-(void)initData{
    self.launchServiceFilePathArray = @[@"/Library/LaunchDaemons",@"/Library/LaunchAgents",[@"~/Library/LaunchAgents" stringByExpandingTildeInPath]];
}


#pragma mark -- Launchctl & BTM Snapshot Helpers

- (NSSet<NSString *> *)queryUserLaunchctlLoadedLabels {
    NSMutableSet<NSString *> *labels = [NSMutableSet set];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[@"list"];
    NSPipe *outPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = [NSPipe pipe];

    NSError *launchErr = nil;
    if (![task launchAndReturnError:&launchErr]) {
        return labels;
    }
    NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (data.length == 0) {
        return labels;
    }
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (line.length == 0 || [line hasPrefix:@"PID"]) {
            continue;
        }
        NSArray<NSString *> *cols = [line componentsSeparatedByString:@"\t"];
        NSString *label = cols.lastObject;
        if (cols.count >= 3 && label.length > 0) {
            [labels addObject:[label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
    }
    return labels;
}

- (void)parseBTMSnapshotRecord:(NSDictionary<NSString *, NSString *> *)rec
                      stateMap:(NSMutableDictionary<NSString *, NSNumber *> *)stateMap
                      mainApps:(NSMutableArray<NSDictionary<NSString *, NSString *> *> *)mainApps {
    if (rec.count == 0) {
        return;
    }
    NSString *typeStr = rec[@"Type"] ?: @"";
    NSString *dispStr = rec[@"Disposition"] ?: @"";
    NSString *rawId = rec[@"Identifier"] ?: @"";
    NSString *bundleId = rec[@"Bundle Identifier"] ?: @"";
    NSString *urlStr = rec[@"URL"] ?: @"";

    BOOL isEnabled = ([dispStr containsString:@"enabled"] &&
                      ![dispStr containsString:@"disabled"] &&
                      ![dispStr containsString:@"disallowed"]);

    // 剥离 BTM Identifier 前缀数字与点号，如 "4.net.tunnelblick.launcher" -> "net.tunnelblick.launcher"
    NSString *cleanId = rawId;
    NSRange dotRange = [rawId rangeOfString:@"."];
    if (dotRange.location != NSNotFound && dotRange.location <= 6) {
        NSString *prefix = [rawId substringToIndex:dotRange.location];
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([prefix rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            cleanId = [rawId substringFromIndex:dotRange.location + 1];
        }
    }

    if (cleanId.length > 0) {
        BOOL prev = [stateMap[cleanId] boolValue];
        stateMap[cleanId] = @(prev || isEnabled);
    }
    if (bundleId.length > 0) {
        BOOL prev = [stateMap[bundleId] boolValue];
        stateMap[bundleId] = @(prev || isEnabled);
    }

    // SMAppService.mainApp 注册的主应用登录项：Type 为 "app (0x2)" 且处于 enabled & allowed 状态
    if ([typeStr hasPrefix:@"app "] && isEnabled && urlStr.length > 0 && ![urlStr isEqualToString:@"(null)"]) {
        NSString *appPath = urlStr;
        if ([urlStr hasPrefix:@"file://"]) {
            NSURL *fileURL = [NSURL URLWithString:urlStr];
            if (fileURL.path.length > 0) {
                appPath = fileURL.path;
            }
        }
        if ([appPath hasPrefix:@"/"] &&
            [appPath hasSuffix:@".app"] &&
            ![appPath hasPrefix:@"/System/"] &&
            [[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
            NSString *resolvedBundleId = bundleId.length > 0 ? bundleId : cleanId;
            if (resolvedBundleId.length == 0) {
                resolvedBundleId = [[NSBundle bundleWithPath:appPath] bundleIdentifier] ?: @"";
            }
            if (resolvedBundleId.length > 0) {
                [mainApps addObject:@{
                    @"appPath": appPath,
                    @"bundleId": resolvedBundleId
                }];
            }
        }
    }
}

- (void)queryBTMSnapshotWithStateMap:(NSMutableDictionary<NSString *, NSNumber *> *)stateMap
                            mainApps:(NSMutableArray<NSDictionary<NSString *, NSString *> *> *)mainApps {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/sfltool"]) {
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sfltool"];
    task.arguments = @[@"dumpbtm"];
    NSPipe *outPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = [NSPipe pipe];

    __block NSData *outputData = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *launchErr = nil;
        if ([task launchAndReturnError:&launchErr]) {
            outputData = [[outPipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
        }
        dispatch_semaphore_signal(sema);
    });

    // 超时保护（上限 6 秒），避免后台服务异常阻塞
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC))) != 0) {
        if (task.isRunning) {
            [task terminate];
        }
        return;
    }
    if (outputData.length == 0) {
        return;
    }

    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    if (output.length == 0) {
        return;
    }

    long currentUid = (long)getuid();
    BOOL inValidUidSection = YES;
    NSMutableDictionary<NSString *, NSString *> *currentRec = nil;
    NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSString *rawLine in lines) {
        NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            continue;
        }
        if ([trimmed hasPrefix:@"Records for UID "]) {
            if (currentRec) {
                [self parseBTMSnapshotRecord:currentRec stateMap:stateMap mainApps:mainApps];
                currentRec = nil;
            }
            NSString *rest = [trimmed substringFromIndex:@"Records for UID ".length];
            long secUid = (long)[rest integerValue];
            inValidUidSection = (secUid == -2 || secUid == currentUid);
            continue;
        }
        if (!inValidUidSection) {
            continue;
        }
        // 新记录起始形如 "#1:"、"#28:"（注意排除 Embedded Item Identifiers 下的 "#1: 16.xxx"）
        if ([trimmed hasPrefix:@"#"] && [trimmed hasSuffix:@":"]) {
            if (currentRec) {
                [self parseBTMSnapshotRecord:currentRec stateMap:stateMap mainApps:mainApps];
            }
            currentRec = [NSMutableDictionary dictionary];
            continue;
        }
        if (!currentRec) {
            continue;
        }
        NSRange colonRange = [trimmed rangeOfString:@":"];
        if (colonRange.location != NSNotFound && colonRange.location > 0) {
            NSString *key = [trimmed substringToIndex:colonRange.location];
            if ([key hasPrefix:@"#"]) {
                continue;
            }
            NSString *val = [[trimmed substringFromIndex:colonRange.location + 1]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            currentRec[key] = val;
        }
    }
    if (currentRec && inValidUidSection) {
        [self parseBTMSnapshotRecord:currentRec stateMap:stateMap mainApps:mainApps];
    }
}

#pragma mark -- App LoginItem
/**
获取LoginItem数据
获取应用中LoginItem数据
方法：结合应用包内 Contents/Library/LoginItems、Contents/Library/LaunchAgents|LaunchDaemons 与 macOS 13+ BTM 快照
*/
-(NSMutableArray *)getAppLoginItems{
    NSMutableArray *loginItemArray = [[NSMutableArray alloc]init];
    BOOL isMacOS13OrLater = NO;
    if (@available(macOS 13.0, *)) {
        isMacOS13OrLater = YES;
    }

    NSSet<NSString *> *loadedUserLabels = [self queryUserLaunchctlLoadedLabels];
    NSMutableDictionary<NSString *, NSNumber *> *btmStateMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *btmMainApps = [NSMutableArray array];
    if (isMacOS13OrLater) {
        [self queryBTMSnapshotWithStateMap:btmStateMap mainApps:btmMainApps];
    }

    NSMutableSet<NSString *> *recordedIdentifiers = [NSMutableSet set];
    NSMutableSet<NSString *> *appsWithEmbeddedItems = [NSMutableSet set];

    NSArray<QMLocalApp *> *appArray = [[QMLocalAppHelper shareInstance] getLocalAppData];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    for (QMLocalApp *localApp in appArray) {
        if (!localApp.bundlePath || [localApp.bundlePath hasPrefix:@"/System/"]) {
            continue;
        }
        if ([self needFilterLoginItem:localApp.bundleId]) {
            continue;
        }
        if ([self.delegate respondsToSelector:@selector(needFilterLoginItemBundleId:)]) {
            if ([self.delegate needFilterLoginItemBundleId:localApp.bundleId]) {
                continue;
            }
        }
        NSString *loginItemDirPath = [localApp.bundlePath stringByAppendingString:@"/Contents/Library/LoginItems"];
        BOOL isExist = [fileManager fileExistsAtPath:loginItemDirPath];
        if (isExist) {
            NSError *error = nil;
            NSArray *contentsArray = [fileManager contentsOfDirectoryAtPath:loginItemDirPath error:&error];
            for (NSString *path in contentsArray) {
                if ([path hasSuffix:@".app"]) {
                    NSString *loginItemAppPath = [loginItemDirPath stringByAppendingPathComponent:path];
                    QMAppLoginItem *loginItem = [[QMAppLoginItem alloc] initWithAppPath:localApp.bundlePath loginItemPath:loginItemAppPath loginItemType:LoginItemTypeAppItem];
                    if (!loginItem.loginItemBundleId || [recordedIdentifiers containsObject:loginItem.loginItemBundleId]) {
                        continue;
                    }
                    NSNumber *btmEnabled = btmStateMap[loginItem.loginItemBundleId];
                    if (isMacOS13OrLater && btmEnabled != nil) {
                        loginItem.isEnable = [btmEnabled boolValue];
                    } else {
                        loginItem.isEnable = ([loadedUserLabels containsObject:loginItem.loginItemBundleId] ||
                                              [self appLoginItemIsEnabledWithBundleId:loginItem.loginItemBundleId]);
                    }
                    loginItem.isManagedBySMAppService = isMacOS13OrLater;
                    if (loginItem.isEnable) {
                        loginItem.isDisabledByUser = NO;
                    }
                    [loginItemArray addObject:loginItem];
                    [recordedIdentifiers addObject:loginItem.loginItemBundleId];
                    [appsWithEmbeddedItems addObject:localApp.bundlePath];
                }
            }
        }

        // macOS 13+ SMAppService 支持包内嵌 Contents/Library/LaunchAgents 与 LaunchDaemons
        if (isMacOS13OrLater) {
            NSArray<NSString *> *embeddedSubDirs = @[@"/Contents/Library/LaunchAgents", @"/Contents/Library/LaunchDaemons"];
            for (NSString *subDir in embeddedSubDirs) {
                NSString *fullSubDir = [localApp.bundlePath stringByAppendingString:subDir];
                if (![fileManager fileExistsAtPath:fullSubDir]) {
                    continue;
                }
                NSArray<NSString *> *plistNames = [fileManager contentsOfDirectoryAtPath:fullSubDir error:NULL];
                for (NSString *plistName in plistNames) {
                    if (![plistName hasSuffix:@".plist"] || [self needFilterFile:plistName]) {
                        continue;
                    }
                    NSString *plistPath = [fullSubDir stringByAppendingPathComponent:plistName];
                    NSDictionary *plistDict = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                    if (![plistDict isKindOfClass:NSDictionary.class]) {
                        continue;
                    }
                    NSString *label = plistDict[LAUNCH_SERVICE_LABEL];
                    if (![label isKindOfClass:NSString.class] || label.length == 0 || [recordedIdentifiers containsObject:label]) {
                        continue;
                    }
                    QMAppLoginItem *embeddedServiceItem = [[QMAppLoginItem alloc] initWithAppPath:localApp.bundlePath
                                                                                    loginItemPath:plistPath
                                                                                    loginItemType:LoginItemTypeAppItem];
                    embeddedServiceItem.loginItemBundleId = label;
                    embeddedServiceItem.isManagedBySMAppService = YES;
                    NSNumber *btmEnabled = btmStateMap[label];
                    if (btmEnabled != nil) {
                        embeddedServiceItem.isEnable = [btmEnabled boolValue];
                    } else if ([subDir hasSuffix:@"LaunchDaemons"] &&
                               [self.delegate respondsToSelector:@selector(isEnableForLaunchServiceLabel:)]) {
                        embeddedServiceItem.isEnable = [self.delegate isEnableForLaunchServiceLabel:label];
                    } else {
                        embeddedServiceItem.isEnable = [loadedUserLabels containsObject:label];
                    }
                    if (embeddedServiceItem.isEnable) {
                        embeddedServiceItem.isDisabledByUser = NO;
                    }
                    [loginItemArray addObject:embeddedServiceItem];
                    [recordedIdentifiers addObject:label];
                    [appsWithEmbeddedItems addObject:localApp.bundlePath];
                }
            }
        }
    }

    // 补充通过 SMAppService.mainApp 注册且处于启用态的独立主应用登录项
    if (isMacOS13OrLater && btmMainApps.count > 0) {
        for (NSDictionary<NSString *, NSString *> *entry in btmMainApps) {
            NSString *appPath = entry[@"appPath"];
            NSString *bundleId = entry[@"bundleId"];
            if (!appPath || !bundleId) {
                continue;
            }
            if ([appsWithEmbeddedItems containsObject:appPath] || [recordedIdentifiers containsObject:bundleId]) {
                continue;
            }
            if ([self needFilterLoginItem:bundleId]) {
                continue;
            }
            if ([self.delegate respondsToSelector:@selector(needFilterLoginItemBundleId:)] &&
                [self.delegate needFilterLoginItemBundleId:bundleId]) {
                continue;
            }
            QMAppLoginItem *mainAppItem = [[QMAppLoginItem alloc] initWithAppPath:appPath
                                                                    loginItemPath:appPath
                                                                    loginItemType:LoginItemTypeAppItem];
            mainAppItem.loginItemBundleId = bundleId;
            mainAppItem.isEnable = YES;
            mainAppItem.isManagedBySMAppService = YES;
            mainAppItem.isDisabledByUser = NO;
            [loginItemArray addObject:mainAppItem];
            [recordedIdentifiers addObject:bundleId];
            [appsWithEmbeddedItems addObject:appPath];
        }
    }

    NSLog(@"%s, app loginItem Array count : %lu", __FUNCTION__, (unsigned long)loginItemArray.count);
    return loginItemArray;
}

-(void)enableAppLoginItemWithBundleId: (NSString *)bundleId{
    NSString *plistFilePath = [self createPlistFileWithBundleId:bundleId];
    if (plistFilePath) {
        [self loadPlistFile:plistFilePath];
        [self removeFile:plistFilePath];
    }
}

-(void)disableAppLoginItemWithBundleId: (NSString *)bundleId{
    NSString *plistFilePath = [self createPlistFileWithBundleId:bundleId];
    if (plistFilePath) {
        [self unloadPlistFile:plistFilePath];
        [self removeFile:plistFilePath];
    }
}

- (void)removeFile:(NSString *)path {
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (error) {
        NSLog(@"%s,error: %@", __FUNCTION__, error);
    }
}

- (NSString *)createPlistFileWithBundleId:(NSString *)bundleId {
    NSString *appPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleId];
    NSLog(@"%s,bundleId: %@, login item path: %@", __FUNCTION__, bundleId, appPath);
    if (!appPath) {
        return nil;
    }
//    NSString *templatePath = [[NSBundle bundleForClass:self.class] pathForResource:@"loginItem_template" ofType:@"plist"];
    NSString *templatePath = [[NSBundle mainBundle] pathForResource:@"loginItem_template" ofType:@"plist"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:templatePath];
    if (!dict) {
        NSLog(@"dict is nil");
        return nil;
    }
    NSMutableArray *arguments = [dict objectForKey:@"ProgramArguments"];
    if (!arguments || arguments.count == 0) {
        return nil;
    }
    [arguments replaceObjectAtIndex:0 withObject:appPath];
    [dict setObject:arguments forKey:@"ProgramArguments"];
    [dict setObject:bundleId forKey:@"Label"];
    [dict setObject:appPath.stringByDeletingLastPathComponent forKey:@"WorkingDirectory"];
    
    NSString *directory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [[directory stringByAppendingPathComponent:bundleId] stringByAppendingPathExtension:@"plist"];
    BOOL result = [dict writeToFile:path atomically:YES];
    NSLog(@"result = %d",result);
    if (result) {
        return path;
    }
    return nil;
}

- (void)loadPlistFile:(NSString *)filePath {
    NSString *cmd = [NSString stringWithFormat:@"launchctl load -w %@",filePath];
    BOOL ret = system([cmd UTF8String]);
    NSLog(@"%s, ret = %d", __FUNCTION__ ,ret);
}

- (void)unloadPlistFile:(NSString *)filePath {
    NSString *cmd = [NSString stringWithFormat:@"launchctl unload -w %@",filePath];
    BOOL ret = system([cmd UTF8String]);
    NSLog(@"%s, ret = %d", __FUNCTION__ ,ret);
}


#pragma mark -- system login item
/**
 获取系统偏好设置中登录项数据
 方法：采用系统提供的API: LSSharedFileListCreate
 */
-(NSMutableArray *)getSystemLoginItems{
    self.loginItemArray = [[NSMutableArray alloc]init];
    UInt32 seedValue;
    CFURLRef thePath = NULL;
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems == NULL) {
        return self.loginItemArray;
    }
    CFArrayRef loginItemsArray = LSSharedFileListCopySnapshot(loginItems, &seedValue);
    if (loginItemsArray != NULL) {
        for (id item in (__bridge NSArray *)loginItemsArray) {
            LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
            if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &thePath, NULL) == noErr && thePath != NULL) {
                NSString *filePath = [(__bridge NSURL *)thePath path];
                if (filePath.length > 0) {
                    QMBaseLoginItem *loginItem = [[QMBaseLoginItem alloc] initWithAppPath:filePath];
                    loginItem.loginItemType = LoginItemTypeSystemItem;
                    loginItem.isEnable = YES;
                    loginItem.isDisabledByUser = NO; // 上次关闭失败，或者该服务会做对抗，例如ioa
                    [self.loginItemArray addObject:loginItem];
                }
                CFRelease(thePath);
                thePath = NULL;
            }
        }
        CFRelease(loginItemsArray);
    }
    CFRelease(loginItems);
    NSLog(@"%s, system loginItem Array count : %lu", __FUNCTION__, (unsigned long)self.loginItemArray.count);
    return self.loginItemArray;
}

//判断LoginItem是否启用
- (BOOL)appLoginItemIsEnabledWithBundleId:(NSString*)bundleId {
    if (!bundleId) {
        return NO;
    }
    CFDictionaryRef dict = SMJobCopyDictionary(kSMDomainUserLaunchd, (__bridge CFStringRef)bundleId);
//    NSLog(@"%s, dict = %@",__FUNCTION__, dict);
    if (dict == NULL) {
        return NO;
    }
    CFRelease(dict);
    return YES;
}

-(void)addSystemLoginItemWithAppPath: (NSString *)appPath{
    NSLog(@"%s, app path: %@", __FUNCTION__, appPath);
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    //url为app所在的目录
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
    LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemLast, NULL, NULL, url, NULL, NULL);
    CFRelease(item);
    CFRelease(loginItems);
}

-(void)removeSystemLoginItemWithAppPath: (NSString *)appPath{
    [self reverseSharedFileList];
    NSLog(@"%s, app path: %@", __FUNCTION__, appPath);
    UInt32 seedValue;
    CFURLRef thePath;
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    CFArrayRef loginItemsArray = LSSharedFileListCopySnapshot(loginItems, &seedValue);
    for (id item in (__bridge NSArray *)loginItemsArray) {
        LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
        OSStatus status = LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &thePath, NULL);
        if (status == noErr) {
            //appPath目录为要取消开机启动app的路径
            if ([[(__bridge NSURL *)thePath path] hasPrefix:appPath]) {
                OSStatus status = LSSharedFileListItemRemove(loginItems, itemRef); // Deleting the item
                NSLog(@"%s, remove login item path: %@, result is: %d",__FUNCTION__, appPath,status);
                break;
            }
            CFRelease(thePath);
        } else {
            NSLog(@"%s, resolve item error: %d", __FUNCTION__, status);
        }
    }
    CFRelease(loginItemsArray);
    CFRelease(loginItems);
    [self reverseSharedFileList];
}

- (void)reverseSharedFileList {
    UInt32 seedValue;
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    CFArrayRef loginItemsArray = LSSharedFileListCopySnapshot(loginItems, &seedValue);
    NSArray *array = (__bridge NSArray *)loginItemsArray;
    NSLog(@"%s, shared list file count: %lu", __FUNCTION__, (unsigned long)array.count);
    CFRelease(loginItemsArray);
    CFRelease(loginItems);
}


#pragma mark -- Launch service
/**
 获取Launch plist数据
 */
- (NSArray *)getLaunchServiceItems {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray *launchServiceItemArray = [[NSMutableArray alloc]init];
    // 一次性快照当前用户态 launchctl 已加载服务集合，避免逐个 plist 派生 grep 子进程（O(N) 降为 O(1)）
    NSSet<NSString *> *loadedUserLabels = [self queryUserLaunchctlLoadedLabels];
    for (NSString *directoryPath in self.launchServiceFilePathArray) {
        NSArray *fileNames = [fileManager contentsOfDirectoryAtPath:directoryPath error:NULL];
        for (NSString *fileName in fileNames) {
            if ([self needFilterFile:fileName]) {
                continue;
            }
            if ([self.delegate respondsToSelector:@selector(needFilterLaunchServiceFile:)]) {
                if ([self.delegate needFilterLaunchServiceFile:fileName]) {
                    continue;
                }
            }
            NSString *filePath = [directoryPath stringByAppendingPathComponent:fileName];
            NSDictionary *dict = [[NSDictionary alloc] initWithContentsOfFile:filePath];
            // 保护。防止用户修改了plist文件的key类型。
            if (![dict isKindOfClass:NSDictionary.class] || dict.count == 0) {
                continue;
            }
            NSString *label = dict[LAUNCH_SERVICE_LABEL];
            if (![label isKindOfClass:NSString.class] || label.length == 0) {
                continue;
            }
            QMAppLaunchItem *launchItem = [[QMAppLaunchItem alloc] initWithLaunchFilePath:filePath itemType:LoginItemTypeService];
            launchItem.label = label;
            if (launchItem.domainType == LaunchServiceDomainTypeUser) {
                launchItem.isEnable = [loadedUserLabels containsObject:label];
            } else {
                launchItem.isEnable = [self serviceIsEnabledWithItem:launchItem];
            }
            if (launchItem.isEnable) {
                launchItem.isDisabledByUser = NO; // 上次关闭失败，或者该服务会做对抗，例如ioa
            }
//            NSLog(@"%s, launch login itme filePath : %@",__FUNCTION__, filePath);
            //将launch plist文件与App进行匹配；
            //1. 先通过bundleId进行匹配，如果plist文件名包含bundleId,则匹配成功
            //2. 分析plist文件，与其中包含的App进行匹配
            QMLocalApp *localApp = [self getAppInfoWithFileName:fileName];
            if (localApp) {
                launchItem.appName = localApp.appName;
                launchItem.appPath = localApp.bundlePath;
            } else if(dict) {
                NSArray *array = dict[LAUNCH_SERVICE_PROGRAM_ARGUMENTS];
                if (![array isKindOfClass:NSArray.class] || array.count == 0) {
                    continue;
                }
                NSString *programPath = array[0];
                if (![programPath isKindOfClass:NSString.class] || programPath.length == 0) {
                    continue;
                }
                //判断是否包含app
                if (([programPath containsString:@".app/"] || [programPath hasSuffix:@"app"])) {
                    NSRange range = [programPath rangeOfString:@".app"];
                    if (range.location != NSNotFound) {
                        NSUInteger index = range.location + 4;
                        NSString *appPath = [programPath substringToIndex:index];
                        launchItem.appPath = appPath;
                        launchItem.appName = [appPath lastPathComponent];
                    }
                }
            }
            [launchServiceItemArray addObject:launchItem];
        }
        
    }
    NSLog(@"%s, launchItemArray count : %lu",__FUNCTION__, (unsigned long)launchServiceItemArray.count);
    return launchServiceItemArray;
}

- (BOOL)needFilterFile:(NSString *)fileName {
    fileName = [fileName lowercaseString];
    if ([fileName containsString:@"com.tencent.lemon."]) {
        return YES;
    }
    if ([fileName containsString:@"com.tencent.lemonmonitor"]) {
        return YES;
    }
    if ([fileName containsString:@"com.teamviewer"]) {
        return YES;
    }
    if ([fileName containsString:@"com.xk72.charles"]) {
        return YES;
    }
    if ([fileName containsString:@"com.cisco.anyconnect"]) {
        return YES;
    }
    return NO;
}

- (BOOL)needFilterLoginItem:(NSString *)bundleId {
    if ([bundleId isEqualToString:@"com.tencent.Lemon"]) {
        return YES;
    }
    if ([bundleId isEqualToString:@"com.tencent.LemonMonitor"]) {
        return YES;
    }
    return NO;
}

- (QMLocalApp *)getAppInfoWithFileName:(NSString *)fileName {
    NSArray <QMLocalApp *>* localAppData = [[QMLocalAppHelper shareInstance] getLocalAppData];
    for (QMLocalApp *localApp in localAppData) {
        if (!localApp.bundleId || [localApp.bundleId isEqualToString:@""]) {
//            NSLog(@"%s, app bundle is nil, the app path is: %@", __FUNCTION__, localApp.bundlePath);
            continue;
        }
        fileName = [fileName lowercaseString];
        NSString *tempString = [localApp.bundleId lowercaseString];
       
        if ([self isSpecialApp:localApp]) {
            if ([self isSpecialThatFileName:fileName belongsToApp:localApp]) {
                return localApp;
            }
        } else {
            // 去掉后缀
            NSString *fileNameWithoutExtension = [fileName stringByDeletingPathExtension];
            if ([fileNameWithoutExtension containsString:tempString]) {
                return localApp;
            }
        }
    }
    return nil;
}

- (BOOL)isSpecialApp:(QMLocalApp *)app {
    // 特例app， bundle id 是 “st”
    return [app.bundleId isEqualToString:kFinalShellAppBundleId];
}

- (BOOL)isSpecialThatFileName:(NSString *)fileName belongsToApp:(QMLocalApp *)app {
    // 特例app用更严格的判断
    if ([app.bundleId isEqualToString:kFinalShellAppBundleId]) {
        NSString *customBundleId = [kFinalShellAppBundleId stringByAppendingString:@"."];
        if ([fileName hasPrefix:customBundleId]) {
            return YES;
        }
    }
    return NO;
}

//判断后台服务是否启用
-(BOOL)serviceIsEnabledWithItem: (QMAppLaunchItem *)item{
    NSString *cmd = @"";
    __block NSString *cmdResult = @"";
     BOOL isEnable = NO;
    switch (item.domainType) {
        case LaunchServiceDomainTypeSystem:
//            cmd = [NSString stringWithFormat:@"sudo launchctl list | grep %@", item.label];
            isEnable = [self.delegate isEnableForLaunchServiceLabel:item.label];
            break;
        case LaunchServiceDomainTypeUser:
            cmd = [NSString stringWithFormat:@"launchctl list | grep %@", item.label];
            cmdResult = [self.delegate exeCommonCmd:cmd];
            break;
        default:
            break;
    }
    if(cmdResult && ![cmdResult isEqualToString:@""]){
        isEnable = YES;
    }
    return isEnable;
}

-(void)disableLaunchItem:(QMAppLaunchItem *)item{
    NSLog(@"%s, launch file path: %@", __FUNCTION__, item.filePath);
    switch (item.domainType) {
        case LaunchServiceDomainTypeSystem:
//            cmd = [NSString stringWithFormat: @"sudo launchctl disable system/%@;sudo launchctl unload %@",item.label, item.filePath];
            [self.delegate disableSystemLaunchItemWithFilePath:item.filePath label:item.label];
            break;
        case LaunchServiceDomainTypeUser: {
            NSString *cmd = [NSString stringWithFormat: @"launchctl disable gui/$UID/%@;launchctl unload %@", item.label, item.filePath];
             int result = system([cmd UTF8String]);
             NSLog(@"%s, disable user launchctl item: %@, result: %d ", __FUNCTION__, item.label, result);

        }
            break;
        default:
            break;
    }

}

-(void)enableLaunchItem:(QMAppLaunchItem *)item{
    NSLog(@"%s, launch file path: %@", __FUNCTION__, item.filePath);
    NSString *cmd = @"";
//    cmd = @"sudo launchctl enable system/com.adobe.fpsaud&&sudo launchctl load /Library/LaunchDaemons/com.adobe.fpsaud.plist";
    switch (item.domainType) {
        case LaunchServiceDomainTypeSystem:
//            cmd = [NSString stringWithFormat: @"sudo launchctl enable system/%@&&sudo launchctl load %@",item.label, item.filePath];
            [self.delegate enabelSystemLaunchItemWithFilePath:item.filePath label:item.label];
            break;
        case LaunchServiceDomainTypeUser:
            cmd = [NSString stringWithFormat: @"launchctl enable gui/$UID/%@&&launchctl load %@", item.label, item.filePath];
            int result = system([cmd UTF8String]);
            NSLog(@"%s, enable user launchctl item: %@, result: %d ", __FUNCTION__, item.label, result);
            break;
        default:
            break;
    }
}


@end

