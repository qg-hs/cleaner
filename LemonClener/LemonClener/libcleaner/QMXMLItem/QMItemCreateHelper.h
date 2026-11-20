//
//  QMItemCreateHelper.h
//  LemonClener
//
//  Copyright © 2019年 Tencent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "QMCategoryItem.h"

@interface QMItemCreateHelper : NSObject

// 创建一个模拟的 soft QMCategorySubItem 规则
+ (QMCategorySubItem *)createSoftAdaptCategorySubItemWithId:(NSString *)subCateId
                                                DisplayName:(NSString *)appDisplayName
                                                 searchNane:(NSString *)appSearchName
                                                   bundleId:(NSString *)bundleId
                                                    appPath:(NSString *)appPath;

// 通过已安装列表来动态创建本地应用扫描规则
+ (void)createAllSoftAdaptCategorySubItemWithInstallArr:(NSDictionary *)installBundleIdDic
                                        curCategoryItem:(QMCategoryItem *)categoryItem;

// 校验指定路径是否存在实际可清理文件（忽略 .DS_Store 与空目录骨架）
+ (BOOL)hasCleanableFilesAtPath:(NSString *)rawPath;

// 校验某个扫描子项下是否存在至少一个非空可清理路径
+ (BOOL)subItemHasAnyCleanablePath:(QMCategorySubItem *)subItem;

// 判断是否有中文
+ (BOOL)isIncludeChineseInString:(NSString *)str;

@end
