//
//  MacthineModel.m
//  LemonHardware
//
//  
//  Copyright © 2019 Tencent. All rights reserved.
//

#import "MachineModel.h"
#import "BatteryModel.h"
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#include <sys/sysctl.h>

#ifndef APPSTORE_VERSION

#import "HardwareHeader.h"
#import <QMUICommon/SharedPrefrenceManager.h>
#endif

#ifndef APPSTORE_VERSION
#define kSIMachineAttributesPath    @"/System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/English.lproj/SIMachineAttributes.plist"
#define HARDWARE_PLIST @"hardware.plist"
#endif

@interface MachineModel()

#ifndef APPSTORE_VERSION
{
    NSDictionary * _machineAttributesDict;
}

#endif
@end

@implementation MachineModel

-(instancetype)init{
    self = [super init];
    if (self) {
        self.machineName=@"Unknown Mac";
        size_t len=0;
        sysctlbyname("hw.model", NULL, &len, NULL, 0);
        if (len) {
            NSMutableData *data=[NSMutableData dataWithLength:len];
            sysctlbyname("hw.model", [data mutableBytes], &len, NULL, 0);
            self.machineName=[NSString stringWithUTF8String:[data bytes]];
        }
    }
    
    return self;
}

#ifndef APPSTORE_VERSION
-(BOOL)getHardWareInfo{
    //    NSOperationQueue *machineInfoQueue = [[NSOperationQueue alloc] init];
    //    machineInfoQueue.maxConcurrentOperationCount = 2;
    
    //外部来开多线程
    [self getSystemVersion];
    [self getMachineInfo];
    NSString *yearString = [SharedPrefrenceManager getString:MAC_MODEL_DETAIL_INFO];
    if (yearString != nil) {
        self.yearString = yearString;
    }else{
        yearString = [self _macModelDetailInfo];
        if (yearString != nil) {
            yearString  = [yearString stringByReplacingOccurrencesOfString:@"(" withString:@""];
            yearString  = [yearString stringByReplacingOccurrencesOfString:@")" withString:@""];
            self.yearString = yearString;
            [SharedPrefrenceManager putString:self.yearString withKey:MAC_MODEL_DETAIL_INFO];
        }
    }
    self.isInit = YES;
    
    //    __weak MachineModel *weakSelf = self;
    //    NSBlockOperation *machineInfoOp = [NSBlockOperation blockOperationWithBlock:^{
    //        [weakSelf getMachineInfo];
    //    }];
    //
    ////    NSBlockOperation *thunderInfoOp = [NSBlockOperation blockOperationWithBlock:^{
    //////        [weakSelf getThunderInfo];
    ////        [weakSelf getSystemVersion];
    ////    }];
    //
    //    NSBlockOperation *yearStringOp = [NSBlockOperation blockOperationWithBlock:^{
    //        NSString *yearString = [SharedPrefrenceManager getString:MAC_MODEL_DETAIL_INFO];
    //        if (yearString != nil) {
    //            weakSelf.yearString = yearString;
    //        }else{
    //            weakSelf.yearString = [weakSelf _macModelDetailInfo];
    //            if (weakSelf != nil) {
    //                [SharedPrefrenceManager putString:weakSelf.yearString withKey:MAC_MODEL_DETAIL_INFO];
    //            }
    //        }
    //
    //    }];
    //    [yearStringOp setCompletionBlock:^{
    //        NSLog(@"%@ = %@", [weakSelf class], weakSelf);
    //    }];
    //
    //    [yearStringOp addDependency:machineInfoOp];
    ////    [yearStringOp addDependency:thunderInfoOp];
    //
    //    [machineInfoQueue addOperation:machineInfoOp];
    ////    [machineInfoQueue addOperation:thunderInfoOp];
    //    [machineInfoQueue addOperation:yearStringOp];
    
    
    return YES;
}

-(void)getSystemVersion{
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSString *sysVersion = [processInfo operatingSystemVersionString];
//    NSLog(@"sysVersion = %@", sysVersion);
    self.systemVersion = sysVersion;
//    NSLog(@"getSystemVersion = %@", sysVersion);
}

-(BOOL)getMachineInfo{
    // 优先通过 sysctlbyname + IORegistry (IODeviceTree) 原生内存直读，避免阻塞派生 system_profiler 子进程
    if ([self populateNativeMachineInfo]) {
        return YES;
    }
    [self writeToFile];
    [self readFromFile];
    return YES;
}

static NSString *LMFormatCacheBytesString(uint64_t bytes)
{
    if (bytes == 0) {
        return nil;
    }
    if (bytes >= 1024ULL * 1024ULL) {
        double mb = (double)bytes / (1024.0 * 1024.0);
        if (fabs(mb - round(mb)) < 0.05) {
            return [NSString stringWithFormat:@"%.0f MB", round(mb)];
        }
        return [NSString stringWithFormat:@"%.1f MB", mb];
    }
    return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
}

static NSString *LMCopyIODeviceTreeProductName(void)
{
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMasterPortDefault);
    if (!root) {
        return nil;
    }
    CFTypeRef prop = IORegistryEntrySearchCFProperty(root,
                                                     kIODeviceTreePlane,
                                                     CFSTR("product-name"),
                                                     kCFAllocatorDefault,
                                                     kIORegistryIterateRecursively);
    IOObjectRelease(root);
    if (!prop) {
        return nil;
    }
    NSString *result = nil;
    if (CFGetTypeID(prop) == CFDataGetTypeID()) {
        CFDataRef data = (CFDataRef)prop;
        const char *bytes = (const char *)CFDataGetBytePtr(data);
        CFIndex len = CFDataGetLength(data);
        if (bytes != NULL && len > 0) {
            size_t strLen = strnlen(bytes, (size_t)len);
            if (strLen > 0) {
                result = [[NSString alloc] initWithBytes:bytes length:strLen encoding:NSUTF8StringEncoding];
            }
        }
    } else if (CFGetTypeID(prop) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)prop copy];
    }
    CFRelease(prop);
    return result;
}

static NSString *LMDeriveMarketingMachineNameFromModelIdentifier(NSString *modelId)
{
    if (!modelId || modelId.length == 0) {
        return nil;
    }
    if ([modelId hasPrefix:@"MacBookPro"]) return @"MacBook Pro";
    if ([modelId hasPrefix:@"MacBookAir"]) return @"MacBook Air";
    if ([modelId hasPrefix:@"MacBook"]) return @"MacBook";
    if ([modelId hasPrefix:@"Macmini"]) return @"Mac mini";
    if ([modelId hasPrefix:@"iMacPro"]) return @"iMac Pro";
    if ([modelId hasPrefix:@"iMac"]) return @"iMac";
    if ([modelId hasPrefix:@"MacPro"]) return @"Mac Pro";
    if ([modelId hasPrefix:@"MacStudio"]) return @"Mac Studio";
    return nil;
}

- (BOOL)populateNativeMachineInfo
{
    // 1. CPU 品牌名称（Apple Silicon 与 Intel 均原生暴露 machdep.cpu.brand_string）
    char brandBuf[128] = {0};
    size_t brandLen = sizeof(brandBuf) - 1;
    if (sysctlbyname("machdep.cpu.brand_string", brandBuf, &brandLen, NULL, 0) == 0 && brandBuf[0] != '\0') {
        NSString *brand = [[NSString stringWithUTF8String:brandBuf]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        brand = [brand stringByReplacingOccurrencesOfString:@"(R)" withString:@""];
        brand = [brand stringByReplacingOccurrencesOfString:@"(TM)" withString:@""];
        while ([brand containsString:@"  "]) {
            brand = [brand stringByReplacingOccurrencesOfString:@"  " withString:@" "];
        }
        self.cpuName = brand;
    }
    if (!self.cpuName || self.cpuName.length == 0) {
        return NO;
    }

    // 2. 机型名称与年份规格：优先解析 IODeviceTree "product-name"（如 "MacBook Pro (16-inch, 2021)"）
    NSString *hwModelId = self.machineName;
    NSString *productDesc = LMCopyIODeviceTreeProductName();
    if (productDesc.length > 0) {
        NSRange parenStart = [productDesc rangeOfString:@"("];
        NSRange parenEnd = [productDesc rangeOfString:@")" options:NSBackwardsSearch];
        if (parenStart.location != NSNotFound && parenStart.location > 0) {
            self.machineName = [[productDesc substringToIndex:parenStart.location]
                                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (parenEnd.location != NSNotFound && parenEnd.location > parenStart.location + 1) {
                NSString *detail = [productDesc substringWithRange:NSMakeRange(parenStart.location + 1,
                                                                               parenEnd.location - parenStart.location - 1)];
                if (detail.length > 0 && self.yearString.length == 0) {
                    self.yearString = detail;
                    [SharedPrefrenceManager putString:detail withKey:MAC_MODEL_DETAIL_INFO];
                }
            }
        } else {
            self.machineName = productDesc;
        }
    } else {
        NSString *derivedName = LMDeriveMarketingMachineNameFromModelIdentifier(hwModelId);
        if (derivedName.length > 0) {
            self.machineName = derivedName;
        }
    }

    // 3. 物理核心数（支持 Apple Silicon 性能核 P + 能效核 E 异构拓扑展示）
    int physCores = 0;
    size_t intSize = sizeof(int);
    if (sysctlbyname("hw.physicalcpu", &physCores, &intSize, NULL, 0) == 0 && physCores > 0) {
        int perf0 = 0;
        int perf1 = 0;
        size_t p0Size = sizeof(int);
        size_t p1Size = sizeof(int);
        BOOL hasPerf0 = (sysctlbyname("hw.perflevel0.physicalcpu", &perf0, &p0Size, NULL, 0) == 0 && perf0 > 0);
        BOOL hasPerf1 = (sysctlbyname("hw.perflevel1.physicalcpu", &perf1, &p1Size, NULL, 0) == 0 && perf1 > 0);
        if (hasPerf0 && hasPerf1 && (perf0 + perf1 == physCores)) {
            self.cpuCores = [NSString stringWithFormat:@"%d (%dP + %dE)", physCores, perf0, perf1];
        } else {
            self.cpuCores = [NSString stringWithFormat:@"%d", physCores];
        }
    }

    // 4. 主频（Intel 原生暴露 hw.cpufrequency；Apple Silicon 异构动态调频不固定，保持 nil 以由 UI 自适应隐藏）
    uint64_t cpuFreqHz = 0;
    size_t freqSize = sizeof(cpuFreqHz);
    if (sysctlbyname("hw.cpufrequency", &cpuFreqHz, &freqSize, NULL, 0) == 0 && cpuFreqHz > 0) {
        self.cpuSpeed = [NSString stringWithFormat:@"%.2f GHz", (double)cpuFreqHz / 1e9];
    }

    // 5. L2 / L3 缓存
    uint64_t l2Bytes = 0;
    size_t l2Size = sizeof(l2Bytes);
    if (sysctlbyname("hw.l2cachesize", &l2Bytes, &l2Size, NULL, 0) == 0 && l2Bytes > 0) {
        self.L2Cache = LMFormatCacheBytesString(l2Bytes);
    }
    uint64_t l3Bytes = 0;
    size_t l3Size = sizeof(l3Bytes);
    if (sysctlbyname("hw.l3cachesize", &l3Bytes, &l3Size, NULL, 0) == 0 && l3Bytes > 0) {
        self.L3Cache = LMFormatCacheBytesString(l3Bytes);
    }

    return YES;
}

-(void)writeToFile{
    NSString *pathName = [self getHardWareInfoPathByName:HARDWARE_PLIST];
    
    NSString *tempPathName = [self getHardWareInfoTempPathByName:HARDWARE_PLIST];
    
    NSTask * task = [[NSTask alloc] init];
    // apply settings for task
    [task setLaunchPath: @"/bin/bash"];
    NSString *shellString = [NSString stringWithFormat:@"system_profiler SPHardwareDataType SPMemoryDataType SPDisplaysDataType -xml > \"%@\" && mv \"%@\" \"%@\"", tempPathName, tempPathName, pathName];
    [task setArguments: [NSArray arrayWithObjects:@"-c", shellString, nil]];
    
    @try
    {
        // set it off
        [task launch];
        
        // read data and convert NSArray
        [task waitUntilExit];
    }
    @catch(NSException *exception)
    {
    }
}

-(BOOL)readFromFile{
    NSString *fileName = [self getHardWareInfoPathByName:HARDWARE_PLIST];
    NSArray *hardwareArr = [[NSArray alloc] initWithContentsOfFile:fileName];
    if ([hardwareArr count] == 0) {
        return NO;
    }
    NSDictionary *hardwareDic = [hardwareArr objectAtIndex:0];
    if (hardwareDic == nil) {
        return NO;
    }
    if (![[hardwareDic allKeys] containsObject:@"_items"]) {
        return NO;
    }
    NSArray *_itemsArr = [hardwareDic objectForKey:@"_items"];
    if ([_itemsArr count] == 0) {
        return NO;
    }
    
    NSDictionary *hardwareInfoDic = [_itemsArr objectAtIndex:0];
    //拿机器名
    self.machineName = hardwareInfoDic[@"machine_name"];
    
    //拿处理器名
    if(hardwareInfoDic[@"cpu_type"] != nil){
        self.cpuName = hardwareInfoDic[@"cpu_type"];
    } else if (hardwareInfoDic[@"chip_type"] != nil) {
        self.cpuName = hardwareInfoDic[@"chip_type"];
    } else{
        self.cpuName = [self getCpuName];
    }
    
    //拿cpu速度
    self.cpuSpeed = hardwareInfoDic[@"current_processor_speed"];
    
    //拿核心数
    self.cpuCores = hardwareInfoDic[@"number_processors"];
    
    //拿二级缓存
    self.L2Cache = hardwareInfoDic[@"l2_cache_core"];
    
    //拿三级缓存
    self.L3Cache = hardwareInfoDic[@"l3_cache"];
    
    return YES;
}

#pragma mark-
#pragma mark cpu info

- (NSString *)getCpuName
{
    char cpumodel[128] = {0};
    size_t size = sizeof(cpumodel) - 1;
    if (sysctlbyname("machdep.cpu.brand_string", cpumodel, &size, NULL, 0))
    {
        cpumodel[0] = '\0';
    }
    NSString * cpuName = [[NSString stringWithUTF8String:cpumodel]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cpuName.length == 0) {
        return @"Apple Silicon";
    }
    if ([cpuName hasPrefix:@"Apple "]) {
        return cpuName;
    }
    cpuName = [cpuName stringByReplacingOccurrencesOfString:@"(R)" withString:@""];
    cpuName = [cpuName stringByReplacingOccurrencesOfString:@"(TM)" withString:@""];
    NSRange range = [cpuName rangeOfString:@"-"];
    if (range.length != 0)
    {
        return [cpuName substringToIndex:range.location];
    }
    return cpuName;
}

-(BOOL)getThunderInfo{
    NSString *shellString = @"system_profiler SPThunderboltDataType";
    NSString *retString = [QMShellExcuteHelper excuteCmd:shellString];
//    NSLog(@"retString = %@", retString);
    if ((retString == nil) || ([retString isEqualToString:@""])) {
        return NO;
    }
    if ([retString containsString:THUNDERBOLT]) {
        //通过range来拿数量
        self.thunderbolts = [self getSubstringCountBySubString:THUNDERBOLT withString:retString];
    }
    if ([retString containsString:PORT]) {
        //通过range来拿数量
        self.ports = [self getSubstringCountBySubString:PORT withString:retString];
    }
    
//    NSLog(@"getThunderInfo = %@", self);
    
    return YES;
}

-(NSInteger)getSubstringCountBySubString:(NSString *)subString withString:(NSString *)string{
    NSUInteger count = 0, length = [string length];
    @try{
        NSRange range = NSMakeRange(0, length);
        while(range.location != NSNotFound)
        {
            range = [string rangeOfString:subString options:0 range:range];
            if(range.location != NSNotFound)
            {
                range = NSMakeRange(range.location + range.length, length - (range.location + range.length));
                count++;
            }
        }
    }@catch(NSException *exception){
//        NSLog(@"getSubstringCountBySubString exception is = %@", exception);
    }
    
    
    return count;
}

- (NSString *)_macModelDetailInfo
{
    NSString * serial = getSerialNumber();
    
    // 获取信息
    NSString * macModel = getMacModelInfo(serial);
    if (macModel)
    {
        NSRange range = [macModel rangeOfString:@"("];
        if (range.length != 0 && range.location != 0)
        {
            macModel = [macModel substringFromIndex:range.location];
        }
        return macModel;
    }
    
    return nil;
    
    //    // 读取配置信息
    //    NSDictionary * attributesDict = [_machineAttributesDict objectForKey:self.machineName];
    //    if (attributesDict)
    //    {
    //        NSString * marketingModel = [[attributesDict objectForKey:@"_LOCALIZABLE_"] objectForKey:@"marketingModel"];
    //        return marketingModel;
    //    }
    //    // 如果没有配置
    //    NSDate * date = manufacureDate(serial);
    //    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    //    [format setDateFormat:@"yyyy/MMMM/"];
    //    NSString * str = [format stringFromDate:date];
    //
    //    NSDateFormatter *formatWeek = [[NSDateFormatter alloc] init];
    //    [formatWeek setDateFormat:@"F"];
    //    str = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"MachineModel__macModelDetailInfo_NSString_1", nil, [NSBundle bundleForClass:[self class]], @""), str, [formatWeek stringFromDate:date]];
    //
    //    macModel = [NSString stringWithFormat:@"(%@)", str];
    //    return macModel;
}

NSString * getSerialNumber()
{
    CFStringRef serialNumber = NULL;
    io_service_t    platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                                 IOServiceMatching("IOPlatformExpertDevice"));
    
    if (platformExpert) {
        CFTypeRef serialNumberAsCFString =
        IORegistryEntryCreateCFProperty(platformExpert,
                                        CFSTR(kIOPlatformSerialNumberKey),
                                        kCFAllocatorDefault, 0);
        if (serialNumberAsCFString) {
            serialNumber = serialNumberAsCFString;
        }
        
        IOObjectRelease(platformExpert);
    }
    
    return (__bridge_transfer NSString *)(serialNumber);
}

NSString * getMacModelInfo(NSString * serial)
{
    NSUInteger length = serial.length;
    if (10 < length && length  < 13)
    {
        // model key
        NSString * modelKey = [serial substringFromIndex:serial.length - (length == 11 ? 3 : 4)];
        if (!modelKey)
            return nil;
        NSArray * laungageArray = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
        NSString * languageKey = @"en";
        if (laungageArray.count > 0)
            languageKey = [laungageArray objectAtIndex:0];
        // local cache
        NSString * path = [@"~/library/preferences/com.apple.systemprofiler.plist" stringByStandardizingPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            NSDictionary * profilerDict = [NSDictionary dictionaryWithContentsOfFile:path];
            NSDictionary * namesDict = [profilerDict objectForKey:@"CPU Names"];
            if (namesDict && namesDict.count > 0)
            {
                for (NSString * key in namesDict.allKeys)
                {
                    if ([key hasPrefix:modelKey])
                    {
                        if ([key rangeOfString:languageKey].length != 0)
                            return [namesDict objectForKey:key];
                    }
                }
                // 合并语言
                NSRange range = [languageKey rangeOfString:@"-"];
                if (range.length != 0)
                {
                    languageKey = [languageKey substringToIndex:range.location];
                }
                for (NSString * key in namesDict.allKeys)
                {
                    if ([key hasPrefix:modelKey])
                    {
                        if ([key rangeOfString:languageKey].length != 0)
                            return [namesDict objectForKey:key];
                    }
                }
                
                return [[namesDict allValues] objectAtIndex:0];
            }
        }
        // 纯本地零联网：移除向 support-sp.apple.com 发送序列号特征的 HTTP 请求
        return nil;
    }
    return nil;
}

int indexOf(char *str1,char str2)
{
    size_t length = strlen(str1);
    for (int i = 0; i < length; i++)
    {
        if (str1[i] == str2)
            return i;
    }
    return -1;
}

NSDate * manufacureDate(NSString *serial)
{
    if (!serial)
        return nil;
    const char * serialChar = [serial UTF8String];
    size_t length = strlen(serialChar);
    if (10 < length && length  < 13)
    {
        int est_year = 0;
        int est_week = 0;
        if (length == 11)
        {
            char year = tolower(serialChar[2]);
            est_year = 2000 + indexOf("   3456789012", year);
            
            char week[3] = {0};
            strncpy(week,serialChar+3,2);
            est_week = atoi(week);
        }
        else
        {
            char * alpha_year = "cdfghjklmnpqrstvwxyz";
            char year = tolower(serialChar[3]);
            est_year = 2010 + (indexOf(alpha_year, year) / 2);
            int est_half = indexOf(alpha_year, year) % 2;
            
            char week= tolower(serialChar[4]);
            char * alpha_week = " 123456789cdfghjklmnpqrtvwxy";
            est_week = indexOf(alpha_week, week) + (est_half * 26);
        }
        NSDateComponents *comps = [[NSDateComponents alloc] init];
        [comps setYear:est_year];
        [comps setWeekOfYear:est_week];
        [comps setWeekday:0];
        NSCalendar * calendar = [NSCalendar currentCalendar];
        return [calendar dateFromComponents:comps];
    }
    return nil;
}

-(NSString *)description{
    return [NSString stringWithFormat:@"machineName = %@, yearString = %@, thunderbolts = %ld, ports = %ld, cpuName = %@, cpuSpeed = %@, cpuCores = %@, L2Cache = %@, L3Cache = %@", self.machineName, self.yearString, self.thunderbolts, self.ports, self.cpuName, self.cpuSpeed, self.cpuCores, self.L2Cache, self.L3Cache];
}

#endif

@end

// MacBook Pro https://support.apple.com/zh-cn/HT201300
NSString * const kMacBookPro_15_3 = @"Mac15,3";
NSString * const kMacBookPro_15_6 = @"Mac15,6";
NSString * const kMacBookPro_15_8 = @"Mac15,8";
NSString * const kMacBookPro_15_10 = @"Mac15,10";
NSString * const kMacBookPro_15_7 = @"Mac15,7";
NSString * const kMacBookPro_15_9 = @"Mac15,9";
NSString * const kMacBookPro_15_11 = @"Mac15,11";
NSString * const kMacBookPro_14_5 = @"Mac14,5";
NSString * const kMacBookPro_14_9 = @"Mac14,9";
NSString * const kMacBookPro_14_6 = @"Mac14,6";
NSString * const kMacBookPro_14_10 = @"Mac14,10";
NSString * const kMacBookPro_early_18_3 = @"MacBookPro18,3";
NSString * const kMacBookPro_early_18_4 = @"MacBookPro18,4";
NSString * const kMacBookPro_early_18_1 = @"MacBookPro18,1";
NSString * const kMacBookPro_early_18_2 = @"MacBookPro18,2";

// MacBook Air https://support.apple.com/zh-cn/102869
NSString * const kMacBookAir_15_13 = @"Mac15,13";
NSString * const kMacBookAir_15_12 = @"Mac15,12";
NSString * const kMacBookAir_14_15 = @"Mac14,15";
NSString * const kMacBookAir_14_2 = @"Mac14,2";

// 非刘海屏，但是model是Macxx,xx
NSString * const kMacBookPro_14_7 = @"Mac14,7";

@implementation MachineModel (LHScreen)

+ (BOOL)isLiquidScreen {
    if (@available(macOS 12.0, *)) {
        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (screens.count > 0) {
            for (NSScreen *screen in screens) {
                if (screen.safeAreaInsets.top > 0) {
                    return YES;
                }
            }
            return NO;
        }
    }
    static BOOL isLiquid = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isLiquid = [self __isLiquidScreen];
    });
    return isLiquid;
}

#pragma mark - private

+ (BOOL)__isLiquidScreen {
    BOOL isLiquid = NO;
    MachineModel *model = [[MachineModel alloc] init];
    NSString *machineName = model.machineName ? : @"Unknown Mac";
    NSArray *list = @[
        kMacBookPro_15_3,
        kMacBookPro_15_6,
        kMacBookPro_15_8,
        kMacBookPro_15_10,
        kMacBookPro_15_7,
        kMacBookPro_15_9,
        kMacBookPro_15_11,
        kMacBookPro_14_5,
        kMacBookPro_14_9,
        kMacBookPro_14_6,
        kMacBookPro_14_10,
        kMacBookPro_early_18_3,
        kMacBookPro_early_18_4,
        kMacBookPro_early_18_1,
        kMacBookPro_early_18_2,
        kMacBookAir_15_13,
        kMacBookAir_15_12,
        kMacBookAir_14_15,
        kMacBookAir_14_2
    ];
    if ([list containsObject:machineName]) {
        isLiquid = YES;
    } else if ([machineName containsString:@"iMac"]) {
        isLiquid = NO;
    } else if ([machineName containsString:@"Macmini"]) {
        isLiquid = NO;
    } else if ([machineName containsString:@"MacPro"]) {
        isLiquid = NO;
    } else if ([machineName containsString:@"MacBookAir"]) {
        isLiquid = NO;
    } else if ([machineName containsString:@"MacBookPro"]) {
        isLiquid = NO;
    } else if ([machineName isEqualToString:kMacBookPro_14_7]) {
        isLiquid = NO;
    } else if ([self __assertRegex:@"Mac(\\d{1,2}),(\\d{1,2})" matchStr:machineName]) {
        // 有电池则是笔记本，否则为iMac、Mac Mini、Mac Pro、Mac studio
        BatteryModel *batteryModel = [[BatteryModel alloc] init];
        isLiquid = [batteryModel isExistBattery];
    } else {
        isLiquid = NO;
    }
    return isLiquid;
}

// 正则比较
+ (BOOL)__assertRegex:(NSString*)regexString matchStr:(NSString *)str
{
    NSPredicate *regex = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", regexString];
    return [regex evaluateWithObject:str];
}

@end
