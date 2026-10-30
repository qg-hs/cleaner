//
//  LMAppSlimScanner.h
//  Lemon
//

#import <Foundation/Foundation.h>
#import "LMAppSlimItem.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^LMAppSlimScanProgressBlock)(NSString *currentAppName, NSUInteger foundCount);
typedef void (^LMAppSlimScanCompletionBlock)(NSArray<LMAppSlimItem *> *items, BOOL cancelled);

@interface LMAppSlimScanner : NSObject

/// 当前物理机器是否为 Apple Silicon (arm64)
+ (BOOL)isAppleSiliconHost;

/// 本机原生保留架构名 ("arm64" 或 "x86_64")
+ (NSString *)nativeKeepArchitectureName;

/// 待剥离冗余架构名 ("x86_64" 或 "arm64")
+ (NSString *)removableArchitectureName;

- (void)startScanWithProgress:(nullable LMAppSlimScanProgressBlock)progressBlock
                   completion:(LMAppSlimScanCompletionBlock)completionBlock;

- (void)cancelScan;

/// 对单个应用执行事务型安全架构瘦身（CoW 副本剥离 -> Ad-hoc 重签校验 -> 原包进废纸篓或移除 -> 原子替换）
+ (BOOL)slimApplicationItem:(LMAppSlimItem *)item
        moveOriginalToTrash:(BOOL)moveToTrash
             reclaimedBytes:(uint64_t * _Nullable)outReclaimed
               errorMessage:(NSString * _Nullable * _Nullable)outError;

@end

NS_ASSUME_NONNULL_END
