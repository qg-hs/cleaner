//
//  LMInstallerScanner.h
//  Lemon
//

#import <Foundation/Foundation.h>
#import "LMInstallerItem.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^LMInstallerScanProgressBlock)(NSString *currentSource, NSUInteger foundCount);
typedef void (^LMInstallerScanCompletionBlock)(NSArray<LMInstallerItem *> *items, BOOL cancelled);

@interface LMInstallerScanner : NSObject

- (void)startScanWithProgress:(nullable LMInstallerScanProgressBlock)progressBlock
                   completion:(LMInstallerScanCompletionBlock)completionBlock;

- (void)cancelScan;

@end

NS_ASSUME_NONNULL_END
