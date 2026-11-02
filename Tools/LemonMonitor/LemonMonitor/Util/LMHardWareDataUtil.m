//
//  LMHardWareDataUtil.m
//  LemonMonitor
//

//  Copyright © 2019 Tencent. All rights reserved.
//

#import "LMHardWareDataUtil.h"
#import <LemonStat/McDiskInfo.h>

@implementation LMHardWareDataUtil

+(void)calculateDiskUsageInfoWithMainDiskName: (NSString *)mainDiskName volumeArray: (NSArray *) volumnesArray freeBytes: (uint64_t *)freeBytes totalBytes: (uint64_t *)totalBytes{
    uint64_t mainDiskTotalBytes = 0;
    uint64_t mainDiskFreeBytes = 0;
    if (mainDiskName == nil) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (int i=0; i<volumnesArray.count; i++)
        {
            McVolumeInfo *volumnInfo = volumnesArray[i];
            if (![volumnInfo.devName isEqualToString:@"Disk Image"]&& ![volumnInfo.volName isEqualToString:@"Recovery"] && volumnInfo.writeble) {
                //TODO: realPath返回 “/” 说明该磁盘是mainDisk, 为什么?
                NSString *realPath = [fileManager destinationOfSymbolicLinkAtPath:volumnInfo.volPath error:nil];
                if ((realPath != nil) && [realPath isEqualToString:@"/"]) {
                    mainDiskName = volumnInfo.volName;
                    mainDiskTotalBytes = volumnInfo.totalBytes;
                    mainDiskFreeBytes = volumnInfo.freeBytes;
                    break;
                }
                
            }
        }
    }
    for (int i=0; i<volumnesArray.count; i++)
    {
        McVolumeInfo *volumeInfo = volumnesArray[i];
        
        if (volumeInfo.networkDevice) {
            continue;
        }
        if ([volumeInfo.volName isEqualToString:mainDiskName] && volumeInfo.internalDevice) {
            // 使用 64 位精确字节数校准 APFS 主磁盘可用空间（消除原 float 24bit 尾数精度截断）
            uint64_t usableBytes = [self getAllUsableBytes];
            if (usableBytes > 0) {
                volumeInfo.freeBytes = usableBytes;
            }
        }
        //如果不是Disk Image，并且磁盘可写，不是Recovery; Recovery:用于恢复系统、修复磁盘用的一个可启动应用
        if (![volumeInfo.volName isEqualToString:@"Disk Image"] && ![volumeInfo.volName isEqualToString:@"Recovery"] && volumeInfo.writeble) {
            // APFS 同容器多卷共享同一 totalBytes，避免重复累加主容器容量
            if (![volumeInfo.volName isEqualToString:mainDiskName] &&
                ((volumeInfo.totalBytes == mainDiskTotalBytes && volumeInfo.internalDevice) ||
                 (volumeInfo.totalBytes == mainDiskTotalBytes && volumeInfo.freeBytes == mainDiskFreeBytes))) {
                continue;
            }
            *freeBytes += volumeInfo.freeBytes;
            *totalBytes += volumeInfo.totalBytes;
        }
    }
    
}

+(uint64_t)getAllUsableBytes{
    NSError *error = nil;
    NSURL *fileURL = [[NSURL alloc] initFileURLWithPath:NSHomeDirectory()];
    [fileURL removeAllCachedResourceValues];
    NSDictionary *results = [fileURL resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeAvailableCapacityKey] error:&error];
    if (!results) {
        NSLog(@"Error retrieving resource keys: %@", error);
        return 0;
    }
    long long importantVal = [[results objectForKey:NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue];
    if (importantVal > 0) {
        return (uint64_t)importantVal;
    }
    long long availVal = [[results objectForKey:NSURLVolumeAvailableCapacityKey] longLongValue];
    return availVal > 0 ? (uint64_t)availVal : 0;
}
@end
