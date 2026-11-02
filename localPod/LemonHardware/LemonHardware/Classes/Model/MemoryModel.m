//
//  MemoryModel.m
//  LemonHardware
//
//  
//  Copyright © 2019 Tencent. All rights reserved.
//

#import "MemoryModel.h"
#include <sys/sysctl.h>

#define MEM_PLIST @"mem.plist"

@implementation MemBankModel

-(NSString *)description{
    return [NSString stringWithFormat:@"memBankType = %@, memSize = %@, memSpeed = %@, memStatus = %@", self.memBankType, self.memSize, self.memSpeed, self.memStatus];
}

@end

@implementation MemoryModel

-(instancetype)init{
    self = [super init];
    if (self) {
        self.memBankArr = [[NSMutableArray alloc] init];
    }
    
    return self;
}

-(BOOL)getHardWareInfo{
    [self.memBankArr removeAllObjects];
#ifdef __arm64__
    // Apple Silicon 采用 SoC 统一内存架构，无独立 DIMM 插槽，直接通过 sysctl hw.memsize 原生读取
    uint64_t memBytes = 0;
    size_t memLen = sizeof(memBytes);
    if (sysctlbyname("hw.memsize", &memBytes, &memLen, NULL, 0) == 0 && memBytes > 0) {
        double gb = (double)memBytes / (1024.0 * 1024.0 * 1024.0);
        MemBankModel *bankModel = [[MemBankModel alloc] init];
        bankModel.memSize = [NSString stringWithFormat:@"%.0f GB", round(gb)];
        [self.memBankArr addObject:bankModel];
        self.isInit = YES;
        return YES;
    }
#endif
    [self writeToFile];
    [self readFromFile];
    self.isInit = YES;
    
    return YES;
}

-(void)writeToFile{
    NSString *pathName = [self getHardWareInfoPathByName:MEM_PLIST];
    NSString *tempPathName = [self getHardWareInfoTempPathByName:MEM_PLIST];
    
    NSString *shellString = [NSString stringWithFormat:@"system_profiler SPMemoryDataType -xml > \"%@\" && mv \"%@\" \"%@\"", tempPathName, tempPathName, pathName];
    @try{
        [QMShellExcuteHelper excuteCmd:shellString];
    }
    @catch(NSException *exception){
        NSLog(@"exception = %@", exception);
    }
}

-(BOOL)readFromFile{
    NSString *fileName = [self getHardWareInfoPathByName:MEM_PLIST];
    NSArray *memArr = [[NSArray alloc] initWithContentsOfFile:fileName];
    if ([memArr count] == 0) {
        return NO;
    }
    NSDictionary *memDic = [memArr objectAtIndex:0];
    if (memDic == nil) {
        return NO;
    }
    NSArray *_itemsArr0 =memDic[@"_items"];
    if ([_itemsArr0 count] == 0) {
        return NO;
    }
    NSDictionary *itemDic = [_itemsArr0 objectAtIndex:0];
    if (itemDic == nil) {
        return NO;
    }
    NSArray *_itemsArr1 = [itemDic objectForKey:@"_items"];
    if ([_itemsArr1 count] == 0) {
        //适配 AppleM1 新机器，只显示有内存大小：16GB
        NSString *memSize = itemDic[@"SPMemoryDataType"];
        if (memSize) {
            MemBankModel *bankModel = [[MemBankModel alloc] init];
            bankModel.memSize = memSize;
            [self.memBankArr addObject:bankModel];
            return YES;
        } else {
            return NO;
        }
    }
    for (NSDictionary *memBankDic in _itemsArr1) {
        NSString *dimmType = memBankDic[@"dimm_type"];
        if([dimmType isEqualToString:@"empty"]){
            continue;
        }
        MemBankModel *bankModel = [[MemBankModel alloc] init];
        bankModel.memBankType = memBankDic[@"dimm_type"];
        bankModel.memSize = memBankDic[@"dimm_size"];
        bankModel.memSpeed = memBankDic[@"dimm_speed"];
        bankModel.memStatus = memBankDic[@"dimm_status"];
        [self.memBankArr addObject:bankModel];
    }
    
    return YES;
}

-(NSString *)description{
    return [NSString stringWithFormat:@"memBankArr = %@", self.memBankArr];
}

@end
