//
//  LGBaseLoginItem.h
//  LemonGroup
//
//  
//  Copyright © 2020 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef enum{
    LoginItemTypeSystemItem = 0,
    LoginItemTypeAppItem,
    LoginItemTypeService,
}LoginItemType;

/*
 base login item
 */
@interface QMBaseLoginItem : NSObject {
@protected
    NSString *_uid;
}

///app path
@property NSString *appPath;

///app name
@property NSString *appName;

///login item type
@property LoginItemType loginItemType;

///login item is enabled
@property BOOL isEnable;

/// macOS 13+ 由 SMAppService / BTM 托管（需跳转系统设置->登录项进行授权变更）
@property (nonatomic, assign) BOOL isManagedBySMAppService;

- (instancetype)initWithAppPath: (NSString *)appPath;

- (instancetype)initWithAppPath: (NSString *)appPath loginItemType: (LoginItemType)type;

- (void)disableLoginItem;

- (void)enableLoginItem;

- (void)openSystemLoginItemsSettings;

/// 被用户禁用
@property (nonatomic) BOOL isDisabledByUser;
/// 唯一标识
@property (nonatomic, copy, readonly) NSString *uid;
@property (nonatomic, copy, readonly) NSString *cacheKey;
@property (nonatomic, strong, readonly) NSMutableDictionary *cacheDict;

@end

NS_ASSUME_NONNULL_END
