//
//  LMAppSlimItem.h
//  Lemon
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LMAppSlimItem : NSObject

@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *versionString;
@property (nonatomic, strong, nullable) NSImage *appIcon;
@property (nonatomic, assign) uint64_t totalAppBytes;
@property (nonatomic, assign) uint64_t estimatedSavingsBytes;
@property (nonatomic, copy) NSArray<NSString *> *relativeFatBinaryPaths;
@property (nonatomic, copy) NSString *removableArchName;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL isSelected;

@end

NS_ASSUME_NONNULL_END
