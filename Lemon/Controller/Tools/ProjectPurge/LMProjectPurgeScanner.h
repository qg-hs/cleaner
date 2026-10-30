//
//  LMProjectPurgeScanner.h
//  Lemon
//

#import <Foundation/Foundation.h>
#import "LMProjectPurgeItem.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^LMProjectPurgeProgressBlock)(NSString *currentPath, NSUInteger discoveredCount);
typedef void (^LMProjectPurgeCompletionBlock)(NSArray<LMProjectPurgeItem *> *items, BOOL cancelled);

@interface LMProjectPurgeScanner : NSObject

+ (NSArray<NSString *> *)configuredScanDirectories;
+ (void)saveConfiguredScanDirectories:(NSArray<NSString *> *)directories;
+ (NSArray<NSString *> *)defaultScanDirectories;

- (void)startScanWithDirectories:(NSArray<NSString *> *)directories
                        progress:(nullable LMProjectPurgeProgressBlock)progressBlock
                      completion:(LMProjectPurgeCompletionBlock)completionBlock;

- (void)cancelScan;

@end

NS_ASSUME_NONNULL_END
