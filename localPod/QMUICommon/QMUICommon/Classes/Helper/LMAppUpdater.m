//
//  LMAppUpdater.m
//  QMUICommon
//
//  Modern GitHub Releases in-place auto updater for cleaner & LemonMonitor.
//

#import "LMAppUpdater.h"
#import <QMCoreFunction/LanguageHelper.h>
#import <Masonry/Masonry.h>
#import "LMAppThemeHelper.h"
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

NSString * const LMAppUpdateStateDidChangeNotification = @"LMAppUpdateStateDidChangeNotification";
static NSString * const kGitHubLatestReleaseAPI = @"https://api.github.com/repos/qg-hs/cleaner/releases/latest";
static NSString * const kLemonNewVersionKey = @"kLemonHasVersion";
static NSString * const kLemonNewVersionInfoKey = @"kLemonNewVersionInfo";

@interface LMAppUpdater () <NSURLSessionDownloadDelegate>

@property (nonatomic, assign, readwrite) BOOL hasUpdate;
@property (nonatomic, copy, readwrite, nullable) NSString *latestVersion;
@property (nonatomic, copy, readwrite, nullable) NSString *downloadURL;
@property (nonatomic, copy, readwrite, nullable) NSString *releaseNotes;
@property (nonatomic, assign, readwrite) BOOL isChecking;
@property (nonatomic, assign, readwrite) BOOL isDownloading;

@property (nonatomic, assign) NSTimeInterval lastCheckTimestamp;
@property (nonatomic, strong, nullable) NSTimer *periodicTimer;

// UI 控件
@property (nonatomic, strong, nullable) NSWindow *updateWindow;
@property (nonatomic, strong, nullable) NSImageView *appIconImageView;
@property (nonatomic, strong, nullable) NSTextField *titleLabel;
@property (nonatomic, strong, nullable) NSTextField *versionLabel;
@property (nonatomic, strong, nullable) NSScrollView *notesScrollView;
@property (nonatomic, strong, nullable) NSTextView *notesTextView;
@property (nonatomic, strong, nullable) NSProgressIndicator *progressBar;
@property (nonatomic, strong, nullable) NSTextField *statusLabel;
@property (nonatomic, strong, nullable) NSButton *primaryButton;
@property (nonatomic, strong, nullable) NSButton *cancelButton;

// 下载会话
@property (nonatomic, strong, nullable) NSURLSession *downloadSession;
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask *activeDownloadTask;
@property (nonatomic, assign) int64_t lastBytesSample;
@property (nonatomic, assign) NSTimeInterval lastTimeSample;
@property (nonatomic, assign) double currentSpeedBytesPerSec;
@property (nonatomic, copy, nullable) NSString *extractedAppTempPath;

@end

@implementation LMAppUpdater

+ (instancetype)sharedUpdater {
    static LMAppUpdater *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LMAppUpdater alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self restoreCachedUpdateState];
    }
    return self;
}

#pragma mark - Version & Path Resolution

- (NSString *)targetAppBundlePath {
    // 1. 若当前直接运行在 cleaner.app 下
    NSString *mainBundlePath = [[NSBundle mainBundle] bundlePath];
    if ([mainBundlePath.lastPathComponent isEqualToString:@"cleaner.app"]) {
        return mainBundlePath;
    }
    // 2. 若作为内嵌 Helper (如 LemonMonitor) 运行，向上追溯定位外层宿主 cleaner.app
    NSString *cursor = [mainBundlePath stringByDeletingLastPathComponent];
    while (cursor.length > 1 && ![cursor isEqualToString:@"/"]) {
        if ([cursor.lastPathComponent isEqualToString:@"cleaner.app"] && [[NSFileManager defaultManager] fileExistsAtPath:cursor]) {
            return cursor;
        }
        cursor = [cursor stringByDeletingLastPathComponent];
    }
    // 3. 生产标准安装路径优先级
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/cleaner.app"]) {
        return @"/Applications/cleaner.app";
    }
    return mainBundlePath;
}

- (NSString *)currentInstalledVersion {
    NSBundle *targetBundle = [NSBundle bundleWithPath:[self targetAppBundlePath]];
    NSString *ver = [[targetBundle infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (ver.length == 0) {
        ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    }
    return [self normalizeVersionString:ver] ?: @"1.1.1";
}

- (NSString *)normalizeVersionString:(NSString *)rawVersion {
    if (![rawVersion isKindOfClass:[NSString class]] || rawVersion.length == 0) {
        return @"";
    }
    NSString *trimmed = [rawVersion stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmed hasPrefix:@"v"] || [trimmed hasPrefix:@"V"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    return trimmed;
}

- (BOOL)isVersion:(NSString *)remoteVersion newerThan:(NSString *)localVersion {
    NSString *cleanRemote = [self normalizeVersionString:remoteVersion];
    NSString *cleanLocal  = [self normalizeVersionString:localVersion];
    if (cleanRemote.length == 0 || cleanLocal.length == 0) {
        return NO;
    }
    return ([cleanRemote compare:cleanLocal options:NSNumericSearch] == NSOrderedDescending);
}

- (void)restoreCachedUpdateState {
    NSDictionary *cachedInfo = [[NSUserDefaults standardUserDefaults] objectForKey:kLemonNewVersionInfoKey];
    if ([cachedInfo isKindOfClass:[NSDictionary class]]) {
        NSString *cachedVer = cachedInfo[@"version"];
        NSString *cachedURL = cachedInfo[@"downloadURL"];
        if ([self isVersion:cachedVer newerThan:[self currentInstalledVersion]] &&
            [cachedURL isKindOfClass:[NSString class]] &&
            [cachedURL hasPrefix:@"https://github.com/qg-hs/cleaner/"]) {
            self.hasUpdate = YES;
            self.latestVersion = [self normalizeVersionString:cachedVer];
            self.downloadURL = cachedURL;
            self.releaseNotes = cachedInfo[@"body"];
            return;
        }
    }
    self.hasUpdate = NO;
    self.latestVersion = nil;
    self.downloadURL = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionInfoKey];
}

#pragma mark - Periodic Check

- (void)startPeriodicCheck {
    if (self.periodicTimer) {
        return;
    }
    [self checkForUpdatesWithManualTrigger:NO];
    self.periodicTimer = [NSTimer scheduledTimerWithTimeInterval:14400.0 // 4小时
                                                          target:self
                                                        selector:@selector(onPeriodicTimerFired:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)onPeriodicTimerFired:(NSTimer *)timer {
    [self checkForUpdatesWithManualTrigger:NO];
}

#pragma mark - Asset Matching

- (NSString *)selectBestAssetDownloadURLFromAssets:(NSArray *)assets {
    if (![assets isKindOfClass:[NSArray class]] || assets.count == 0) {
        return nil;
    }
#if defined(__arm64__) || defined(__aarch64__)
    NSString *preferredArchToken = @"arm64";
#else
    NSString *preferredArchToken = @"x86_64";
#endif
    NSString *archMatchURL = nil;
    NSString *universalMatchURL = nil;
    NSString *fallbackZipURL = nil;

    for (NSDictionary *asset in assets) {
        if (![asset isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *name = [asset[@"name"] lowercaseString];
        NSString *url  = asset[@"browser_download_url"];
        // 关键防护：自动就地替换必须下载 .zip 归档，严禁下载只读挂载卷 .dmg
        if (![name isKindOfClass:[NSString class]] || ![url isKindOfClass:[NSString class]] || ![name hasSuffix:@".zip"]) {
            continue;
        }
        if ([name containsString:preferredArchToken] && !archMatchURL) {
            archMatchURL = url;
        } else if ([name containsString:@"universal"] && !universalMatchURL) {
            universalMatchURL = url;
        } else if (!fallbackZipURL) {
            fallbackZipURL = url;
        }
    }
    return archMatchURL ?: (universalMatchURL ?: fallbackZipURL);
}

#pragma mark - Check For Updates

- (void)checkForUpdatesWithManualTrigger:(BOOL)isManual {
    if (self.isChecking || self.isDownloading) {
        if (isManual && self.updateWindow) {
            [NSApp activateIgnoringOtherApps:YES];
            [self.updateWindow makeKeyAndOrderFront:nil];
        }
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (!isManual && (now - self.lastCheckTimestamp < 300.0)) {
        return;
    }
    self.isChecking = YES;
    self.lastCheckTimestamp = now;

    if (isManual) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showCheckingStateUI];
        });
    }

    NSURL *url = [NSURL URLWithString:kGitHubLatestReleaseAPI];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:15.0];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"cleaner-macos-updater" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isChecking = NO;

        BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
        NSHTTPURLResponse *httpResp = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;

        if (error || !data || (httpResp && httpResp.statusCode != 200)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isManual) {
                    NSString *title = (httpResp && httpResp.statusCode == 404)
                        ? (isEnglish ? @"Already Up to Date" : @"当前已是最新版本")
                        : (isEnglish ? @"Update Check Failed" : @"检查更新失败");
                    NSString *detail = (httpResp && httpResp.statusCode == 404)
                        ? [NSString stringWithFormat:isEnglish ? @"Current version v%@ is the latest." : @"当前版本 v%@ 已是最新版本。", [strongSelf currentInstalledVersion]]
                        : [NSString stringWithFormat:isEnglish ? @"Unable to connect to GitHub (%@)." : @"无法连接 GitHub Releases 接口（%@）。", error.localizedDescription ?: @"HTTP Error"];
                    [strongSelf showMessageStateWithTitle:title subtitle:detail canUpdate:NO];
                }
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (isManual) {
                    [strongSelf showMessageStateWithTitle:isEnglish ? @"Check Failed" : @"检查更新失败"
                                                 subtitle:isEnglish ? @"Invalid response data." : @"服务器返回数据格式异常。"
                                                canUpdate:NO];
                }
            });
            return;
        }

        NSString *tagName = json[@"tag_name"];
        NSString *cleanRemoteVer = [strongSelf normalizeVersionString:tagName];
        NSString *localVer = [strongSelf currentInstalledVersion];
        NSString *matchedZipURL = [strongSelf selectBestAssetDownloadURLFromAssets:json[@"assets"]];
        NSString *releaseBody = [json[@"body"] isKindOfClass:[NSString class]] ? json[@"body"] : @"";

        BOOL newer = [strongSelf isVersion:cleanRemoteVer newerThan:localVer] && (matchedZipURL.length > 0);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (newer) {
                strongSelf.hasUpdate = YES;
                strongSelf.latestVersion = cleanRemoteVer;
                strongSelf.downloadURL = matchedZipURL;
                strongSelf.releaseNotes = releaseBody;

                NSDictionary *infoDict = @{
                    @"version": cleanRemoteVer,
                    @"downloadURL": matchedZipURL,
                    @"body": releaseBody
                };
                [[NSUserDefaults standardUserDefaults] setObject:cleanRemoteVer forKey:kLemonNewVersionKey];
                [[NSUserDefaults standardUserDefaults] setObject:infoDict forKey:kLemonNewVersionInfoKey];
                [[NSUserDefaults standardUserDefaults] synchronize];

                [[NSNotificationCenter defaultCenter] postNotificationName:LMAppUpdateStateDidChangeNotification object:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"LemonHasNewVersion" object:nil];

                if (isManual) {
                    [strongSelf showAvailableStateUIWithVersion:cleanRemoteVer notes:releaseBody];
                }
            } else {
                strongSelf.hasUpdate = NO;
                strongSelf.latestVersion = nil;
                strongSelf.downloadURL = nil;
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionKey];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionInfoKey];
                [[NSUserDefaults standardUserDefaults] synchronize];

                [[NSNotificationCenter defaultCenter] postNotificationName:LMAppUpdateStateDidChangeNotification object:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"LemonHasNewVersion" object:nil];

                if (isManual) {
                    [strongSelf showMessageStateWithTitle:isEnglish ? @"Already Up to Date" : @"当前已是最新版本"
                                                 subtitle:[NSString stringWithFormat:isEnglish ? @"cleaner v%@ is currently the newest version available." : @"cleaner v%@ 目前已是最新版本。", localVer]
                                                canUpdate:NO];
                }
            }
        });
    }];
    [task resume];
}

#pragma mark - UI Construction

- (void)ensureUpdateWindow {
    if (self.updateWindow) {
        return;
    }
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    NSRect windowRect = NSMakeRect(0, 0, 480, 310);
    NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:windowRect
                                                styleMask:styleMask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    win.title = isEnglish ? @"cleaner Software Update" : @"cleaner 软件更新";
    win.level = NSFloatingWindowLevel;
    win.releasedWhenClosed = NO;
    win.backgroundColor = [LMAppThemeHelper getMainBgColor];

    NSView *content = win.contentView;

    // 1. 应用图标
    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 218, 64, 64)];
    NSImage *appIcon = [NSImage imageNamed:NSImageNameApplicationIcon] ?: [[NSBundle mainBundle] imageForResource:@"new_app_icon"];
    iconView.image = appIcon;
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [content addSubview:iconView];
    self.appIconImageView = iconView;

    // 2. 主标题
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(104, 252, 352, 26)];
    title.editable = NO;
    title.selectable = NO;
    title.bezeled = NO;
    title.drawsBackground = NO;
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    title.textColor = [LMAppThemeHelper getTitleColor];
    [content addSubview:title];
    self.titleLabel = title;

    // 3. 版本副标题
    NSTextField *ver = [[NSTextField alloc] initWithFrame:NSMakeRect(104, 226, 352, 20)];
    ver.editable = NO;
    ver.selectable = NO;
    ver.bezeled = NO;
    ver.drawsBackground = NO;
    ver.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    ver.textColor = [NSColor secondaryLabelColor];
    [content addSubview:ver];
    self.versionLabel = ver;

    // 4. 更新说明文本框（可滚动）
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 86, 432, 124)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSBezelBorder;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    textView.editable = NO;
    textView.selectable = YES;
    textView.font = [NSFont systemFontOfSize:12];
    textView.textColor = [LMAppThemeHelper getTitleColor];
    textView.backgroundColor = [NSColor controlBackgroundColor];
    scroll.documentView = textView;
    [content addSubview:scroll];
    self.notesScrollView = scroll;
    self.notesTextView = textView;

    // 5. 进度条
    NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 52, 432, 16)];
    bar.minValue = 0.0;
    bar.maxValue = 100.0;
    bar.doubleValue = 0.0;
    bar.indeterminate = NO;
    [content addSubview:bar];
    self.progressBar = bar;

    // 6. 状态说明
    NSTextField *status = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 26, 260, 20)];
    status.editable = NO;
    status.selectable = NO;
    status.bezeled = NO;
    status.drawsBackground = NO;
    status.font = [NSFont systemFontOfSize:11];
    status.textColor = [NSColor secondaryLabelColor];
    [content addSubview:status];
    self.statusLabel = status;

    // 7. 取消/稍后按钮
    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(290, 16, 80, 28)];
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.target = self;
    cancel.action = @selector(onCancelButtonClicked:);
    [content addSubview:cancel];
    self.cancelButton = cancel;

    // 8. 确认/更新按钮
    NSButton *action = [[NSButton alloc] initWithFrame:NSMakeRect(374, 16, 92, 28)];
    action.bezelStyle = NSBezelStyleRounded;
    action.keyEquivalent = @"\r";
    action.target = self;
    action.action = @selector(onActionButtonClicked:);
    [content addSubview:action];
    self.primaryButton = action;

    [win center];
    self.updateWindow = win;
}

- (void)showCheckingStateUI {
    [self ensureUpdateWindow];
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    self.titleLabel.stringValue = isEnglish ? @"Checking for Updates..." : @"正在检查更新...";
    self.versionLabel.stringValue = [NSString stringWithFormat:isEnglish ? @"Current version: v%@" : @"当前安装版本：v%@", [self currentInstalledVersion]];
    self.notesScrollView.hidden = YES;
    self.progressBar.hidden = NO;
    self.progressBar.indeterminate = YES;
    [self.progressBar startAnimation:nil];
    self.statusLabel.stringValue = isEnglish ? @"Connecting to GitHub Releases..." : @"正在连接 GitHub Releases 获取最新版本...";
    self.cancelButton.hidden = YES;
    self.primaryButton.hidden = YES;

    [NSApp activateIgnoringOtherApps:YES];
    [self.updateWindow makeKeyAndOrderFront:nil];
}

- (void)showAvailableStateUIWithVersion:(NSString *)newVersion notes:(NSString *)notes {
    [self ensureUpdateWindow];
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    [self.progressBar stopAnimation:nil];
    self.progressBar.hidden = YES;

    self.titleLabel.stringValue = [NSString stringWithFormat:isEnglish ? @"New Version v%@ Available" : @"发现新版本 cleaner v%@", newVersion];
    self.versionLabel.stringValue = [NSString stringWithFormat:isEnglish ? @"Current version: v%@ (In-place update supported)" : @"当前版本：v%@（支持就地极速更新，无需手动安装）", [self currentInstalledVersion]];

    self.notesScrollView.hidden = NO;
    NSString *notesText = (notes.length > 0) ? notes : (isEnglish ? @"General bug fixes and performance improvements." : @"包含现代化 macOS 适配、性能优化与体验改进。");
    [self.notesTextView setString:notesText];

    self.statusLabel.stringValue = isEnglish ? @"Ready to download." : @"准备下载更新包。";
    self.cancelButton.hidden = NO;
    self.cancelButton.title = isEnglish ? @"Later" : @"稍后";
    self.primaryButton.hidden = NO;
    self.primaryButton.title = isEnglish ? @"Update Now" : @"立即更新";
    self.primaryButton.enabled = YES;

    [NSApp activateIgnoringOtherApps:YES];
    [self.updateWindow makeKeyAndOrderFront:nil];
}

- (void)showMessageStateWithTitle:(NSString *)title subtitle:(NSString *)subtitle canUpdate:(BOOL)canUpdate {
    [self ensureUpdateWindow];
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    [self.progressBar stopAnimation:nil];
    self.progressBar.hidden = YES;
    self.notesScrollView.hidden = YES;

    self.titleLabel.stringValue = title;
    self.versionLabel.stringValue = subtitle;
    self.statusLabel.stringValue = @"";
    self.cancelButton.hidden = YES;
    self.primaryButton.hidden = NO;
    self.primaryButton.title = isEnglish ? @"OK" : @"好";
    self.primaryButton.enabled = YES;

    [NSApp activateIgnoringOtherApps:YES];
    [self.updateWindow makeKeyAndOrderFront:nil];
}

#pragma mark - Button Actions

- (void)onCancelButtonClicked:(id)sender {
    if (self.isDownloading) {
        [self.activeDownloadTask cancel];
        self.activeDownloadTask = nil;
        self.isDownloading = NO;
    }
    [self.updateWindow orderOut:nil];
}

- (void)onActionButtonClicked:(id)sender {
    if (self.extractedAppTempPath.length > 0) {
        // 更新包已就绪，立即触发脱机重启安装
        [self executeRelaunchAndApplyUpdate];
        return;
    }
    if (self.hasUpdate && self.downloadURL.length > 0) {
        [self startUpdate];
        return;
    }
    [self.updateWindow orderOut:nil];
}

#pragma mark - Download & Install Pipeline

- (void)startUpdate {
    if (self.isDownloading) {
        [self.updateWindow makeKeyAndOrderFront:nil];
        return;
    }
    if (self.downloadURL.length == 0) {
        [self checkForUpdatesWithManualTrigger:YES];
        return;
    }

    NSURL *url = [NSURL URLWithString:self.downloadURL];
    if (!url) return;

    self.isDownloading = YES;
    self.lastBytesSample = 0;
    self.lastTimeSample = [NSDate timeIntervalSinceReferenceDate];
    self.currentSpeedBytesPerSec = 0.0;

    [self ensureUpdateWindow];
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    self.titleLabel.stringValue = [NSString stringWithFormat:isEnglish ? @"Downloading v%@..." : @"正在下载新版本 v%@...", self.latestVersion ?: @""];
    self.versionLabel.stringValue = isEnglish ? @"Application will exit and relaunch automatically upon completion." : @"下载完成后将自动退出应用、完成替换并重新启动。";
    self.notesScrollView.hidden = YES;
    self.progressBar.hidden = NO;
    self.progressBar.indeterminate = NO;
    self.progressBar.doubleValue = 0.0;
    self.statusLabel.stringValue = isEnglish ? @"Connecting to download server..." : @"正在建立下载连接...";
    self.cancelButton.hidden = NO;
    self.cancelButton.title = isEnglish ? @"Cancel" : @"取消";
    self.primaryButton.hidden = NO;
    self.primaryButton.title = isEnglish ? @"Downloading..." : @"下载中...";
    self.primaryButton.enabled = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.downloadSession = [NSURLSession sessionWithConfiguration:config
                                                         delegate:self
                                                    delegateQueue:[NSOperationQueue mainQueue]];
    self.activeDownloadTask = [self.downloadSession downloadTaskWithURL:url];
    [self.activeDownloadTask resume];
}

- (void)startHotUpdate {
    [self startUpdate];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval dt = now - self.lastTimeSample;
    if (dt >= 0.5) {
        int64_t dBytes = totalBytesWritten - self.lastBytesSample;
        self.currentSpeedBytesPerSec = (double)dBytes / dt;
        self.lastBytesSample = totalBytesWritten;
        self.lastTimeSample = now;
    }

    NSString *speedStr = @"";
    if (self.currentSpeedBytesPerSec > 1024 * 1024) {
        speedStr = [NSString stringWithFormat:@"%.1f MB/s", self.currentSpeedBytesPerSec / (1024.0 * 1024.0)];
    } else if (self.currentSpeedBytesPerSec > 1024) {
        speedStr = [NSString stringWithFormat:@"%.0f KB/s", self.currentSpeedBytesPerSec / 1024.0];
    }

    if (totalBytesExpectedToWrite > 0) {
        double pct = (double)totalBytesWritten * 100.0 / (double)totalBytesExpectedToWrite;
        self.progressBar.indeterminate = NO;
        self.progressBar.doubleValue = pct;
        double mbWritten = (double)totalBytesWritten / (1024.0 * 1024.0);
        double mbTotal   = (double)totalBytesExpectedToWrite / (1024.0 * 1024.0);
        self.statusLabel.stringValue = [NSString stringWithFormat:
            isEnglish ? @"%.1f MB / %.1f MB (%.0f%%) - %@" : @"%.1f MB / %.1f MB (%.0f%%) · %@",
            mbWritten, mbTotal, pct, speedStr];
    } else {
        self.progressBar.indeterminate = YES;
        [self.progressBar startAnimation:nil];
        double mbWritten = (double)totalBytesWritten / (1024.0 * 1024.0);
        self.statusLabel.stringValue = [NSString stringWithFormat:
            isEnglish ? @"%.1f MB downloaded - %@" : @"已下载 %.1f MB · %@", mbWritten, speedStr];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
    NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"cleaner_update_%d", getpid()]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:tempRoot error:nil];
    [fm createDirectoryAtPath:tempRoot withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *zipPath = [tempRoot stringByAppendingPathComponent:@"cleaner-update.zip"];
    NSError *moveErr = nil;
    if (![fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:zipPath] error:&moveErr]) {
        self.isDownloading = NO;
        [self showMessageStateWithTitle:isEnglish ? @"Update Failed" : @"更新失败"
                               subtitle:isEnglish ? @"Failed to save update package." : @"无法保存下载文件。"
                              canUpdate:NO];
        return;
    }

    self.titleLabel.stringValue = isEnglish ? @"Extracting and Verifying..." : @"正在解压并校验安装包...";
    self.progressBar.indeterminate = YES;
    [self.progressBar startAnimation:nil];
    self.statusLabel.stringValue = isEnglish ? @"Checking integrity and signatures..." : @"正在校验代码签名与架构完整性...";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *extractDir = [tempRoot stringByAppendingPathComponent:@"extracted"];
        [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];

        // 1. 调用 ditto 解压 zip 归档
        NSTask *unzipTask = [[NSTask alloc] init];
        unzipTask.launchPath = @"/usr/bin/ditto";
        unzipTask.arguments = @[@"-x", @"-k", zipPath, extractDir];
        [unzipTask launch];
        [unzipTask waitUntilExit];

        NSString *extractedApp = [extractDir stringByAppendingPathComponent:@"cleaner.app"];
        NSString *extractedExec = [extractedApp stringByAppendingPathComponent:@"Contents/MacOS/cleaner"];

        if (unzipTask.terminationStatus != 0 || ![fm isExecutableFileAtPath:extractedExec]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isDownloading = NO;
                [self showMessageStateWithTitle:isEnglish ? @"Verification Failed" : @"安装包校验失败"
                                       subtitle:isEnglish ? @"Invalid cleaner.app found in download package." : @"解压产物中未检测到合法的 cleaner.app。"
                                      canUpdate:NO];
            });
            return;
        }

        self.extractedAppTempPath = extractedApp;

        // 2. 准备执行无感接管重启
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progressBar stopAnimation:nil];
            self.progressBar.hidden = YES;
            self.titleLabel.stringValue = isEnglish ? @"Update Ready" : @"新版本已就绪";
            self.versionLabel.stringValue = isEnglish ? @"Restarting application to apply updates..." : @"应用即将自动退出并重新启动完成更新...";
            self.statusLabel.stringValue = isEnglish ? @"Restarting in 2 seconds..." : @"2 秒后自动重启...";
            self.primaryButton.title = isEnglish ? @"Restart Now" : @"立即重启";
            self.primaryButton.enabled = YES;
            self.cancelButton.hidden = YES;

            // 倒计时 2 秒自动执行重启
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.extractedAppTempPath.length > 0) {
                    [self executeRelaunchAndApplyUpdate];
                }
            });
        });
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error && error.code != NSURLErrorCancelled) {
        self.isDownloading = NO;
        BOOL isEnglish = ([LanguageHelper getCurrentSystemLanguageType] == SystemLanguageTypeEnglish);
        [self showMessageStateWithTitle:isEnglish ? @"Download Failed" : @"下载失败"
                               subtitle:error.localizedDescription ?: (isEnglish ? @"Network disconnected." : @"网络连接中断，请稍后重试。")
                              canUpdate:NO];
    }
}

#pragma mark - Execution & Relaunch

- (NSString *)locateOrSynthesizeRelauncher {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 1. 尝试主包 Resources 目录
    NSString *bundleRelauncher = [[NSBundle mainBundle] pathForResource:@"cleaner_relauncher" ofType:nil];
    if (bundleRelauncher && [fm isExecutableFileAtPath:bundleRelauncher]) {
        return bundleRelauncher;
    }
    // 2. 尝试宿主 cleaner.app Resources 目录
    NSString *targetApp = [self targetAppBundlePath];
    NSString *outerRelauncher = [targetApp stringByAppendingPathComponent:@"Contents/Resources/cleaner_relauncher"];
    if ([fm isExecutableFileAtPath:outerRelauncher]) {
        return outerRelauncher;
    }
    // 3. 尝试新解压包内的 cleaner_relauncher
    if (self.extractedAppTempPath.length > 0) {
        NSString *newRelauncher = [self.extractedAppTempPath stringByAppendingPathComponent:@"Contents/Resources/cleaner_relauncher"];
        if ([fm isExecutableFileAtPath:newRelauncher]) {
            return newRelauncher;
        }
    }
    return nil;
}

- (void)executeRelaunchAndApplyUpdate {
    if (self.extractedAppTempPath.length == 0) {
        return;
    }

    NSString *relauncherPath = [self locateOrSynthesizeRelauncher];
    NSString *targetAppPath  = [self targetAppBundlePath];
    NSString *extractedApp   = self.extractedAppTempPath;

    // 清理缓存标记
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLemonNewVersionInfoKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 检测当前是否有 LemonMonitor 运行
    BOOL isMonitorRunning = NO;
    for (NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([app.bundleIdentifier isEqualToString:@"com.tencent.LemonMonitor"]) {
            isMonitorRunning = YES;
            break;
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"cleaner_relaunch_%d", getpid()]];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tempRelauncher = [tempDir stringByAppendingPathComponent:@"cleaner_relauncher"];

    if (relauncherPath.length > 0 && [fm fileExistsAtPath:relauncherPath]) {
        // 关键步骤：复制 cleaner_relauncher 到 /tmp 目录执行，避免目标包原地覆盖时造成自身二进制被锁死
        [fm copyItemAtPath:relauncherPath toPath:tempRelauncher error:nil];
        chmod([tempRelauncher fileSystemRepresentation], 0755);

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        [args addObject:@"--pid"];
        [args addObject:[NSString stringWithFormat:@"%d", getpid()]];
        [args addObject:@"--src"];
        [args addObject:extractedApp];
        [args addObject:@"--dst"];
        [args addObject:targetAppPath];
        [args addObject:@"--relaunch"];
        [args addObject:targetAppPath];
        if (isMonitorRunning) {
            [args addObject:@"--relaunch-monitor"];
        }

        // 使用 posix_spawn + POSIX_SPAWN_SETSID 完全脱离当前宿主会话组
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);

        int argc = (int)args.count + 1;
        char **argv = (char **)malloc(sizeof(char *) * (argc + 1));
        argv[0] = strdup([tempRelauncher fileSystemRepresentation]);
        for (int i = 0; i < args.count; i++) {
            argv[i + 1] = strdup([args[i] UTF8String]);
        }
        argv[argc] = NULL;

        pid_t childPid = 0;
        int spawnStatus = posix_spawn(&childPid, [tempRelauncher fileSystemRepresentation], NULL, &attr, argv, environ);

        for (int i = 0; i < argc; i++) {
            free(argv[i]);
        }
        free(argv);
        posix_spawnattr_destroy(&attr);

        if (spawnStatus == 0) {
            // 守护进程已拉起，立即彻底退出当前应用
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSApplication sharedApplication] terminate:nil];
            });
            return;
        }
    }

    // 终极安全保底：若找不到预编译 relauncher 二进制，使用脱机 shell 脚本完成相同原子替换
    NSString *fallbackScript = [tempDir stringByAppendingPathComponent:@"relaunch_fallback.sh"];
    NSString *scriptContent = [NSString stringWithFormat:
        @"#!/bin/sh\n"
        @"sleep 0.8\n"
        @"killall -9 LemonMonitor cleaner 2>/dev/null || true\n"
        @"sleep 0.4\n"
        @"rm -rf \"%@\"\n"
        @"/usr/bin/ditto \"%@\" \"%@\"\n"
        @"/usr/bin/xattr -dr com.apple.quarantine \"%@\" 2>/dev/null || true\n"
        @"/bin/chmod -R a+rX \"%@\" 2>/dev/null || true\n"
        @"/usr/bin/open -n \"%@\"\n"
        @"if [ \"%d\" -eq 1 ] && [ -d \"%@/Contents/Library/LoginItems/LemonMonitor.app\" ]; then\n"
        @"  /usr/bin/open -a \"%@/Contents/Library/LoginItems/LemonMonitor.app\" --args 1 2>/dev/null || true\n"
        @"fi\n"
        @"rm -rf \"%@\"\n",
        targetAppPath,
        extractedApp, targetAppPath,
        targetAppPath,
        targetAppPath,
        targetAppPath,
        isMonitorRunning ? 1 : 0,
        targetAppPath,
        targetAppPath,
        tempDir];

    [scriptContent writeToFile:fallbackScript atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([fallbackScript fileSystemRepresentation], 0755);

    NSString *launchCmd = [NSString stringWithFormat:@"nohup /bin/sh \"%@\" >/dev/null 2>&1 &", fallbackScript];
    system([launchCmd UTF8String]);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSApplication sharedApplication] terminate:nil];
    });
}

@end
