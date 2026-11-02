//
//  LMAppUpdater.h
//  QMUICommon
//
//  Modern GitHub Releases in-place auto updater for cleaner & LemonMonitor.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const LMAppUpdateStateDidChangeNotification;

@interface LMAppUpdater : NSObject

@property (nonatomic, assign, readonly) BOOL hasUpdate;
@property (nonatomic, copy, readonly, nullable) NSString *latestVersion;
@property (nonatomic, copy, readonly, nullable) NSString *downloadURL;
@property (nonatomic, copy, readonly, nullable) NSString *releaseNotes;
@property (nonatomic, assign, readonly) BOOL isChecking;
@property (nonatomic, assign, readonly) BOOL isDownloading;

+ (instancetype)sharedUpdater;

/// 启动每 4 小时一次的后台低优先级定时检测
- (void)startPeriodicCheck;

/// 检查是否有新版本（isManual=YES 会弹出 UI 提示进度与结果）
- (void)checkForUpdatesWithManualTrigger:(BOOL)isManual;

/// 开始下载最新版本并执行脱机自动替换重启
- (void)startUpdate;
- (void)startHotUpdate;

/// 解析当前目标主程序 cleaner.app 所在路径（优先 /Applications/cleaner.app）
- (NSString *)targetAppBundlePath;

/// 当前已安装的主程序版本
- (NSString *)currentInstalledVersion;

@end

NS_ASSUME_NONNULL_END
