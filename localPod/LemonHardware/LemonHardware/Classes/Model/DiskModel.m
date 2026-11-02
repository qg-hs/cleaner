//
//  DiskModel.m
//  LemonHardware
//
//  
//  Copyright © 2019 Tencent. All rights reserved.
//

#import "DiskModel.h"

#define DISK_PLIST @"disk.plist"

@implementation DiskZoneModel

-(NSString *)description{
    return [NSString stringWithFormat:@"diskName = %@, maxSize= %lld, leftSize = %lld, isMaindisk = %d", self.diskName, self.maxSize, self.leftSize, self.isMainDisk];
}

@end

@implementation DiskModel

-(instancetype)init{
    self = [super init];
    if (self) {
        self.diskZoneArr = [[NSMutableArray alloc] init];
    }
    
    return self;
}

-(BOOL)getHardWareInfo{
    [self.diskZoneArr removeAllObjects];
    // 优先通过内核 FileSystem Resource Keys 原生直读，避免每 30 秒 fork system_profiler 子进程与磁盘写入
    if (![self populateFromNativeMountedVolumes]) {
        [self writeInfoToToFile];
        [self readFromFile];
    }
    self.isInit = YES;
    
    return YES;
}

-(long long)getAllUsableBytesForURL:(NSURL *)targetURL {
    NSURL *fileURL = targetURL ?: [NSURL fileURLWithPath:NSHomeDirectory()];
    [fileURL removeAllCachedResourceValues];
    NSError *error = nil;
    NSArray<NSURLResourceKey> *keys = @[
        NSURLVolumeAvailableCapacityForImportantUsageKey,
        NSURLVolumeAvailableCapacityKey
    ];
    NSDictionary *results = [fileURL resourceValuesForKeys:keys error:&error];
    if (!results) {
        return 0;
    }
    long long importantBytes = [[results objectForKey:NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue];
    if (importantBytes > 0) {
        return importantBytes;
    }
    return [[results objectForKey:NSURLVolumeAvailableCapacityKey] longLongValue];
}

-(long long)getAllUsableBytes{
    return [self getAllUsableBytesForURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
}

-(BOOL)populateFromNativeMountedVolumes {
    NSArray<NSURLResourceKey> *keys = @[
        NSURLVolumeLocalizedNameKey,
        NSURLVolumeNameKey,
        NSURLVolumeTotalCapacityKey,
        NSURLVolumeAvailableCapacityForImportantUsageKey,
        NSURLVolumeAvailableCapacityKey,
        NSURLVolumeIsReadOnlyKey,
        NSURLVolumeIsLocalKey,
        NSURLVolumeIsInternalKey
    ];
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:keys
                                                                                                     options:NSVolumeEnumerationSkipHiddenVolumes];
    if (urls.count == 0) {
        return NO;
    }

    BOOL addedMainDisk = NO;
    long long mainContainerSize = 0;

    for (NSURL *volURL in urls) {
        [volURL removeAllCachedResourceValues];
        NSDictionary<NSURLResourceKey, id> *vals = [volURL resourceValuesForKeys:keys error:nil];
        if (!vals) {
            continue;
        }
        if (vals[NSURLVolumeIsLocalKey] && ![vals[NSURLVolumeIsLocalKey] boolValue]) {
            continue;
        }
        NSString *mountPath = [volURL path] ?: @"";
        BOOL isRootMount = [mountPath isEqualToString:@"/"];
        BOOL isDataMount = [mountPath isEqualToString:@"/System/Volumes/Data"];
        BOOL isReadOnly = [vals[NSURLVolumeIsReadOnlyKey] boolValue];

        // macOS 11+ SSV 根卷 "/" 为只读快照，但代表用户主磁盘名称（如 Macintosh HD），需保留并聚合 Data 卷真实可用容量
        if (isReadOnly && !isRootMount) {
            continue;
        }
        if ([mountPath hasPrefix:@"/System/Volumes/"] && !isDataMount) {
            continue;
        }

        NSString *volName = vals[NSURLVolumeLocalizedNameKey] ?: vals[NSURLVolumeNameKey] ?: [mountPath lastPathComponent];
        if ([volName isEqualToString:@"Recovery"] || [volName isEqualToString:@"Preboot"] || [volName isEqualToString:@"VM"] || [volName isEqualToString:@"Update"]) {
            continue;
        }

        long long totalBytes = [vals[NSURLVolumeTotalCapacityKey] longLongValue];
        if (totalBytes <= 0) {
            continue;
        }

        if (isRootMount || isDataMount) {
            if (addedMainDisk) {
                continue;
            }
            DiskZoneModel *mainZone = [[DiskZoneModel alloc] init];
            if (isDataMount) {
                NSURL *rootURL = [NSURL fileURLWithPath:@"/"];
                NSDictionary *rootVals = [rootURL resourceValuesForKeys:@[NSURLVolumeLocalizedNameKey, NSURLVolumeNameKey] error:nil];
                volName = rootVals[NSURLVolumeLocalizedNameKey] ?: rootVals[NSURLVolumeNameKey] ?: volName;
            }
            mainZone.diskName = volName ?: @"Macintosh HD";
            mainZone.maxSize = totalBytes;
            long long usable = [self getAllUsableBytes];
            if (usable <= 0) {
                usable = [self getAllUsableBytesForURL:volURL];
            }
            mainZone.leftSize = (usable > totalBytes) ? totalBytes : usable;
            mainZone.isMainDisk = YES;
            [self.diskZoneArr insertObject:mainZone atIndex:0];
            addedMainDisk = YES;
            mainContainerSize = totalBytes;
            continue;
        }

        // 过滤挂载在 /Volumes 下的磁盘映像（DMG）只读或虚拟卷以及同 APFS 主容器重复影射卷
        BOOL isInternal = vals[NSURLVolumeIsInternalKey] ? [vals[NSURLVolumeIsInternalKey] boolValue] : NO;
        if (isInternal && mainContainerSize > 0 && totalBytes == mainContainerSize && [mountPath hasPrefix:@"/Volumes/"]) {
            NSString *symDest = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:mountPath error:nil];
            if ([symDest isEqualToString:@"/"]) {
                continue;
            }
        }

        long long leftBytes = [self getAllUsableBytesForURL:volURL];
        if (leftBytes > totalBytes) {
            leftBytes = totalBytes;
        }
        DiskZoneModel *zoneModel = [[DiskZoneModel alloc] init];
        zoneModel.diskName = volName ?: @"Disk";
        zoneModel.maxSize = totalBytes;
        zoneModel.leftSize = leftBytes;
        zoneModel.isMainDisk = NO;
        [self.diskZoneArr addObject:zoneModel];
    }

    return self.diskZoneArr.count > 0;
}

-(void)writeInfoToToFile{
    NSString *pathName = [self getHardWareInfoPathByName:DISK_PLIST];
    NSString *tempPathName = [self getHardWareInfoTempPathByName:DISK_PLIST];
    
    // 先输出到临时文件，再原子性覆盖目标文件.确保多线程下文件安全
    // mv 读取线程安全​​：其他线程要么看到旧文件，要么看到新文件，不会读到损坏的中间状态。
    NSString *shellString = [NSString stringWithFormat:@"system_profiler SPStorageDataType -xml > \"%@\" && mv \"%@\" \"%@\"", tempPathName, tempPathName, pathName];
    @try{
        [QMShellExcuteHelper excuteCmd:shellString];
    }
    @catch(NSException *exception){
        NSLog(@"exception = %@", exception);
    }
}

-(BOOL)readFromFile{
    NSString *fileName = [self getHardWareInfoPathByName:DISK_PLIST];
    
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:fileName options:0 error:&error];
    if (!data) {
        NSLog(@"Failed to read file: %@, error: %@", fileName, error);
        return NO;
    }
    
    // 使用NSPropertyListSerialization解析
    id propertyList = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (!propertyList) {
        NSLog(@"Failed to parse plist: %@", error);
        return NO;
    }
    
    // 检查解析结果是否为数组
    if (![propertyList isKindOfClass:[NSArray class]]) {
        NSLog(@"Plist root is not an array");
        return NO;
    }
    NSArray *diskArr = (NSArray *)propertyList;
    if ([diskArr count] == 0) {
        NSLog(@"Empty diskArr");
        return NO;
    }

    NSDictionary *diskDic = [diskArr objectAtIndex:0];
    if (diskDic == nil) {
        NSLog(@"%s, diskDic is nil", __FUNCTION__);
        return NO;
    }
    NSArray *_items = [diskDic objectForKey:@"_items"];
    if([_items count] == 0){
        NSLog(@"%s, _items is nil", __FUNCTION__);
        return NO;
    }
    
    for (NSDictionary *itemDic in _items) {
        NSString *mountPoint = [itemDic objectForKey:@"mount_point"];
        if ([itemDic[@"writable"] isEqualToString:@"no"]) {
            continue;
        }
        NSDictionary *physDic = [itemDic objectForKey:@"physical_drive"];
        NSString *diskName = [physDic objectForKey:@"device_name"];
        if ([diskName isEqualToString:@"Disk Image"] || [diskName isEqualToString:@"Recovery"]) {
            continue;
        }
        DiskZoneModel *zoneModel = [[DiskZoneModel alloc] init];
        zoneModel.diskName = [itemDic objectForKey:@"_name"];
        zoneModel.maxSize = [[itemDic objectForKey:@"size_in_bytes"] longLongValue];
        zoneModel.leftSize = [[itemDic objectForKey:@"free_space_in_bytes"] longLongValue];
        zoneModel.isMainDisk = NO;
        if ([mountPoint isEqualToString:@"/"] || [mountPoint isEqualToString:@"/System/Volumes/Data"]) {
            long long newLeftSize = [self getAllUsableBytes];
            if (newLeftSize > 0) {
                zoneModel.leftSize = newLeftSize;
            }
            zoneModel.isMainDisk = YES;
        }
        
        [self.diskZoneArr addObject:zoneModel];
    }
    
//    NSLog(@"diskmodel = %@", self);
    
    return YES;
}

-(NSString *)description{
    return [NSString stringWithFormat:@"diskZoneArr arr =[%@]", self.diskZoneArr];
}

@end
