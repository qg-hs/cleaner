//
//  CleanerVCModel.h
//  Cleaner
//

//  Copyright © 2021 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CleanerVCModel : NSObject

@property (nonatomic, strong) NSMutableDictionary *toolConMap;
+(CleanerVCModel *)shareInstance;

@end

NS_ASSUME_NONNULL_END
