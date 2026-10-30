//
//  LMInstallerItem.h
//  Lemon
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LMInstallerSourceGroup) {
    LMInstallerSourceGroupAll = 0,
    LMInstallerSourceGroupLocal = 1,    // Downloads / Desktop / Documents / Drop Box
    LMInstallerSourceGroupHomebrew = 2, // Homebrew Caches
    LMInstallerSourceGroupApps = 3      // iCloud / Mail / Telegram
};

@interface LMInstallerItem : NSObject

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *sourceTag;
@property (nonatomic, assign) LMInstallerSourceGroup sourceGroup;
@property (nonatomic, copy) NSString *formatTag;
@property (nonatomic, copy, nullable) NSString *detectedAppName;
@property (nonatomic, assign) BOOL isAppAlreadyInstalled;
@property (nonatomic, assign) uint64_t sizeInBytes;
@property (nonatomic, strong) NSDate *modifiedDate;
@property (nonatomic, strong, nullable) NSImage *fileIcon;
@property (nonatomic, assign) BOOL isSelected;

@end

NS_ASSUME_NONNULL_END
