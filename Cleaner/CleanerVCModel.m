//
//  CleanerVCModel.m
//  Cleaner
//

//  Copyright © 2021 Tencent. All rights reserved.
//

#import "CleanerVCModel.h"

@implementation CleanerVCModel

- (instancetype)init{
    self = [super init];
    if (self) {
        _toolConMap = [NSMutableDictionary dictionary];
    }
    return self;
}

+(CleanerVCModel *)shareInstance{
    static CleanerVCModel *shareInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[CleanerVCModel alloc] init];
    });
    
    return shareInstance;
}

@end
