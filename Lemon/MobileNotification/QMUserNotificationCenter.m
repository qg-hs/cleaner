//
//  QMUserNotificationCenter.m
//  LemonMonitor
//
//  Copyright (c) 2015年 Tencent. All rights reserved.
//

#import "QMUserNotificationCenter.h"
#import "NSUserNotification+QMExtensions.h"

NSString * const QMUserNotificationKey = @"_notification_key";
NSString * const QMUserNotificationActionIdKey = @"ACTION_ID";
#define kNotificationCategoryKey @"_category_key"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface QMBridgedUserNotification : NSUserNotification
@property (nonatomic, assign) NSUserNotificationActivationType bridgedActivationType;
@end

@implementation QMBridgedUserNotification
- (NSUserNotificationActivationType)activationType {
    return _bridgedActivationType;
}
@end

@interface QMUserNotificationCenter ()
@property (nonatomic, copy) void (^actionCallBack)(QMUNCNotificationAction action, NSString *notificationKey);
@property (nonatomic, strong) NSMutableDictionary<NSString *, UNNotificationCategory *> *registeredCategories API_AVAILABLE(macos(10.14));
@end

@implementation QMUserNotificationCenter

- (nullable UNUserNotificationCenter *)safeUNCenter API_AVAILABLE(macos(10.14)) {
    // 防止非 .app 宿主环境（如命令行单元测试）调用 currentNotificationCenter 抛出异常
    @try {
        if ([[NSBundle mainBundle] bundleIdentifier].length == 0) {
            return nil;
        }
        return [UNUserNotificationCenter currentNotificationCenter];
    } @catch (NSException *exception) {
        NSLog(@"[QMUserNotificationCenter] UNUserNotificationCenter unavailable: %@", exception.reason);
        return nil;
    }
}

- (id)init
{
    if (self = [super init])
    {
        if (@available(macOS 10.14, *)) {
            _registeredCategories = [[NSMutableDictionary alloc] init];
            UNUserNotificationCenter *unCenter = [self safeUNCenter];
            if (unCenter) {
                [unCenter setDelegate:self];
            } else {
                [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
            }
        } else {
            [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
        }
    }
    return self;
}

+ (instancetype)defaultUserNotificationCenter
{
    static QMUserNotificationCenter * notificationCenter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!notificationCenter)
            notificationCenter = [[QMUserNotificationCenter alloc] init];
    });
    return notificationCenter;
}

- (void)ensureUNAuthorizationAndDeliverRequest:(UNNotificationRequest *)request
                                      category:(UNNotificationCategory *)category
                                    categoryId:(NSString *)categoryId
                                  notification:(NSUserNotification *)notification
                                      userInfo:(NSDictionary *)dict
                                           key:(NSString *)key API_AVAILABLE(macos(10.14)) {
    UNUserNotificationCenter *unCenter = [self safeUNCenter];
    if (!unCenter) {
        return;
    }

    if (category && categoryId.length > 0) {
        @synchronized (self.registeredCategories) {
            self.registeredCategories[categoryId] = category;
            NSSet *categories = [NSSet setWithArray:self.registeredCategories.allValues];
            [unCenter setNotificationCategories:categories];
        }
    }

    __weak typeof(self) weakSelf = self;
    void (^enqueueBlock)(void) = ^{
        [unCenter addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            if (!error) {
                notification.userInfo = dict;
                [weakSelf presentedWhenAuthorizedWithNotification:notification key:key];
            }
        }];
    };

    [unCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            [unCenter requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                    completionHandler:^(BOOL granted, NSError * _Nullable error) {
                if (granted) {
                    enqueueBlock();
                }
            }];
        } else {
            enqueueBlock();
        }
    }];
}

- (void)scheduleNotification:(NSUserNotification *)notification key:(NSString *)key
{
    if (!key || ![_delegateDict objectForKey:key])
        return;

    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            NSMutableDictionary *dict = [notification.userInfo mutableCopy];
            if (!dict) {
                dict = [[NSMutableDictionary alloc] init];
            }
            [dict setObject:key forKey:QMUserNotificationKey];

            NSString *reqId = notification.identifier.length > 0 ? notification.identifier : [[NSUUID UUID] UUIDString];
            NSString *categoryId = [NSString stringWithFormat:@"%@_%@", kNotificationCategoryKey, key];
            UNNotificationCategory *category = [self categoryWithUserNotification:notification identifier:categoryId];

            UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
            content.title = notification.title ?: @"";
            if (notification.subtitle.length > 0) {
                content.subtitle = notification.subtitle;
            }
            content.body = notification.informativeText ?: @"";
            content.categoryIdentifier = categoryId;
            content.userInfo = dict;

            UNNotificationTrigger *trigger = nil;
            if (notification.deliveryDate) {
                NSTimeInterval delay = [notification.deliveryDate timeIntervalSinceNow];
                if (delay > 0.5) {
                    trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delay repeats:NO];
                }
            }
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:reqId
                                                                                  content:content
                                                                                  trigger:trigger];
            [self ensureUNAuthorizationAndDeliverRequest:request
                                                category:category
                                              categoryId:categoryId
                                            notification:notification
                                                userInfo:dict
                                                     key:key];
            return;
        }
    }

    NSMutableDictionary * dict = [notification.userInfo mutableCopy];
    if (!dict)
        dict = [[NSMutableDictionary alloc] init];
    [dict setObject:key forKey:QMUserNotificationKey];
    notification.userInfo = dict;
    [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:notification];
}

- (void)deliverNotification:(NSUserNotification *)notification key:(NSString *)key
{
    if (@available(macOS 10.14, *)) {
        if (!key || ![_delegateDict objectForKey:key])
            return;

        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (!unCenter) {
            [self scheduleNotification:notification key:key];
            return;
        }

        NSMutableDictionary * dict = [notification.userInfo mutableCopy];
        if (!dict)
            dict = [[NSMutableDictionary alloc] init];
        [dict setObject:key forKey:QMUserNotificationKey];

        NSString *reqId = notification.identifier.length > 0 ? notification.identifier : [[NSUUID UUID] UUIDString];
        NSString *categoryId = [NSString stringWithFormat:@"%@_%@", kNotificationCategoryKey, key];
        UNNotificationCategory *category = [self categoryWithUserNotification:notification identifier:categoryId];

        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = notification.title ?: @"";
        if (notification.subtitle.length > 0) {
            content.subtitle = notification.subtitle;
        }
        content.body = notification.informativeText ?: @"";
        content.categoryIdentifier = categoryId;
        content.userInfo = dict;

        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:reqId
                                                                              content:content
                                                                              trigger:nil];
        [self ensureUNAuthorizationAndDeliverRequest:request
                                            category:category
                                          categoryId:categoryId
                                        notification:notification
                                            userInfo:dict
                                                 key:key];
    } else {
        [self scheduleNotification:notification key:key];
    }
}

- (void)presentedWhenAuthorizedWithNotification:(NSUserNotification *)notification key:(NSString *)key API_AVAILABLE(macos(10.14)) {
    UNUserNotificationCenter *unCenter = [self safeUNCenter];
    if (!unCenter) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [unCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized
            || settings.authorizationStatus == UNAuthorizationStatusProvisional) {
            if (key) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf notificationPresentedWithNotificationKey:key];
                    id obj = [strongSelf->_delegateDict objectForKey:key];
                    if ([obj respondsToSelector:@selector(userNotificationCenter:didDeliverNotification:)]) {
                        [obj userNotificationCenter:[NSUserNotificationCenter defaultUserNotificationCenter]
                             didDeliverNotification:notification];
                    }
                });
            }
        }
    }];
}

- (void)removeAllDeliveredNotifications {
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            [unCenter removeAllDeliveredNotifications];
            return;
        }
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
}

- (void)removeDeliveredNotificationWithIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            [unCenter removeDeliveredNotificationsWithIdentifiers:@[identifier]];
            return;
        }
    }
    NSUserNotification *targetNoti = nil;
    for (NSUserNotification *noti in [NSUserNotificationCenter defaultUserNotificationCenter].deliveredNotifications) {
        if ([noti.identifier isEqualToString:identifier]) {
            targetNoti = noti;
            break;
        }
    }
    if (targetNoti) {
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:targetNoti];
    }
}

- (void)removeScheduledNotificationWithIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) {
        return;
    }
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            [unCenter removePendingNotificationRequestsWithIdentifiers:@[identifier]];
            return;
        }
    }
    NSUserNotification *targetNoti = nil;
    for (NSUserNotification *noti in [NSUserNotificationCenter defaultUserNotificationCenter].scheduledNotifications) {
        if ([noti.identifier isEqualToString:identifier]) {
            targetNoti = noti;
            break;
        }
    }
    if (targetNoti) {
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeScheduledNotification:targetNoti];
    }
}

- (void)addDelegate:(id<NSUserNotificationCenterDelegate>)delegate forKey:(NSString *)key
{
    if (!delegate || !key)
        return;
    if (!_delegateDict) _delegateDict = [[NSMutableDictionary alloc] init];
    [_delegateDict setObject:delegate forKey:key];
}

- (void)removeAllScheduledNotification
{
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            [unCenter removeAllPendingNotificationRequests];
            [unCenter removeAllDeliveredNotifications];
            return;
        }
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
}

- (void)removeScheduledNotificationWithKey:(NSString *)key flagsBlock:(BOOL (^)(NSDictionary * userInfo))sender
{
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *center = [self safeUNCenter];
        if (center) {
            __weak typeof(center) weakCenter = center;
            [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
                NSMutableArray<NSString *> *identifiers = [NSMutableArray<NSString *> array];
                for (UNNotification *notification in notifications)
                {
                    NSDictionary *userInfo = notification.request.content.userInfo;
                    if (!userInfo)
                        continue;
                    NSString *userKey = [userInfo objectForKey:QMUserNotificationKey];
                    if (!userKey)
                        continue;
                    if ([userKey isEqualToString:key])
                    {
                        if (!sender || sender(userInfo))
                            [identifiers addObject:notification.request.identifier];
                    }
                }
                if (identifiers.count > 0) {
                    [weakCenter removeDeliveredNotificationsWithIdentifiers:identifiers];
                }
            }];
            return;
        }
    }

    NSUserNotificationCenter * center = [NSUserNotificationCenter defaultUserNotificationCenter];
    NSArray * array = [[center deliveredNotifications] copy];
    for (NSUserNotification * notification in array)
    {
        NSDictionary *userInfo = [notification userInfo];
        if (!userInfo)
            continue;
        NSString * userKey = [userInfo objectForKey:QMUserNotificationKey];
        if (!userKey)
            continue;
        if ([userKey isEqualToString:key])
        {
            if (!sender || sender(userInfo))
                [center removeDeliveredNotification:notification];
        }
    }
}


#pragma mark - NSUserNotificationCenterDelegate (Legacy Fallback)

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
    NSDictionary *userInfo = [notification userInfo];
    if (!userInfo)
    {
        return;
    }
    NSString * key = [userInfo objectForKey:QMUserNotificationKey];
    if (key)
    {
        [self notificationPresentedWithNotificationKey:key];
        id obj = [_delegateDict objectForKey:key];
        if ([obj respondsToSelector:@selector(userNotificationCenter:didDeliverNotification:)])
            [obj userNotificationCenter:center didDeliverNotification:notification];
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    NSDictionary *userInfo = [notification userInfo];
    if (!userInfo)
    {
        return;
    }
    NSString * key = [userInfo objectForKey:QMUserNotificationKey];
    if (notification.activationType == NSUserNotificationActivationTypeContentsClicked) {
        [self notificationContentClickedWithNotificationKey:key];
    } else if (notification.activationType == NSUserNotificationActivationTypeActionButtonClicked) {
        [self notificationButtonClickedWithNotificationKey:key];
    } else if (notification.activationType == NSUserNotificationActivationTypeNone) {
        [self notificationDismissedWithNotificationKey:key];
    }
    if (key)
    {
        id obj = [_delegateDict objectForKey:key];
        if ([obj respondsToSelector:@selector(userNotificationCenter:didActivateNotification:)])
            [obj userNotificationCenter:center didActivateNotification:notification];
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDismissAlert:(NSUserNotification *)notification{
    NSDictionary *userInfo = [notification userInfo];
    if (!userInfo)
    {
        return;
    }
    NSString * key = [userInfo objectForKey:QMUserNotificationKey];
    if (key)
    {
        id obj = [_delegateDict objectForKey:key];
        if ([obj respondsToSelector:@selector(userNotificationCenter:didDismissAlert:)])
            [obj userNotificationCenter:center didDismissAlert:notification];
    }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}


#pragma mark - UNUserNotification Actions & Delegate

- (UNNotificationCategory *)categoryWithUserNotification:(NSUserNotification *)notification
                                              identifier:(NSString *)categoryIdentifier API_AVAILABLE(macos(10.14)) {
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    if (notification.hasActionButton && notification.actionButtonTitle.length > 0) {
        UNNotificationAction *action = [UNNotificationAction
                                        actionWithIdentifier:UNNotificationActionButtonDidBlock
                                        title:notification.actionButtonTitle
                                        options:UNNotificationActionOptionForeground];
        [actions addObject:action];
    }
    if (notification.otherButtonTitle.length > 0) {
        UNNotificationAction *action = [UNNotificationAction
                                        actionWithIdentifier:UNNotificationActionOtherButtonDidBlock
                                        title:notification.otherButtonTitle
                                        options:UNNotificationActionOptionNone];
        [actions addObject:action];
    }
    for (QMUserNotificationAction *__action in notification.qm_actions) {
        UNNotificationAction *action = [UNNotificationAction
                                        actionWithIdentifier:__action.actionIdentifier
                                        title:__action.title
                                        options:__action.options];
        [actions addObject:action];
    }

    return [UNNotificationCategory categoryWithIdentifier:(categoryIdentifier ?: kNotificationCategoryKey)
                                                  actions:actions.copy
                                        intentIdentifiers:@[]
                                                  options:UNNotificationCategoryOptionCustomDismissAction];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler API_AVAILABLE(macos(10.14)) {
    // 应用处于前台时同样允许系统横幅与通知中心列表展示
    if (completionHandler) {
        if (@available(macOS 11.0, *)) {
            completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
        } else {
            completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
        }
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void(^)(void))completionHandler API_AVAILABLE(macos(10.14)) {
    NSString *key = [response.notification.request.content.userInfo objectForKey:QMUserNotificationKey];
    NSUserNotificationActivationType bridgedType = NSUserNotificationActivationTypeActionButtonClicked;
    if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        bridgedType = NSUserNotificationActivationTypeContentsClicked;
        [self notificationContentClickedWithNotificationKey:key];
    } else if ([response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
        bridgedType = NSUserNotificationActivationTypeNone;
        [self notificationDismissedWithNotificationKey:key];
    } else {
        bridgedType = NSUserNotificationActivationTypeActionButtonClicked;
        [self notificationButtonClickedWithNotificationKey:key];
    }

    if (key) {
        id obj = [_delegateDict objectForKey:key];

        QMBridgedUserNotification *notification = [[QMBridgedUserNotification alloc] init];
        notification.title = response.notification.request.content.title;
        notification.informativeText = response.notification.request.content.body;
        notification.identifier = response.notification.request.identifier;
        notification.bridgedActivationType = bridgedType;

        NSMutableDictionary *dict = [response.notification.request.content.userInfo mutableCopy];
        if (!dict) {
            dict = [[NSMutableDictionary alloc] init];
        }
        if (response.actionIdentifier) {
            [dict setObject:response.actionIdentifier forKey:QMUserNotificationActionIdKey];
        }
        notification.userInfo = dict;

        if ([response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
            if ([obj respondsToSelector:@selector(userNotificationCenter:didDismissAlert:)]) {
                [obj userNotificationCenter:[NSUserNotificationCenter defaultUserNotificationCenter]
                            didDismissAlert:notification];
            }
        }
        if ([obj respondsToSelector:@selector(userNotificationCenter:didActivateNotification:)]) {
            [obj userNotificationCenter:[NSUserNotificationCenter defaultUserNotificationCenter]
                didActivateNotification:notification];
        }
    }

    if (completionHandler) {
        completionHandler();
    }
}

#pragma mark - private

- (void)notificationPresentedWithNotificationKey:(NSString *)key {
    if (self.actionCallBack) {
        self.actionCallBack(QMUNCNotificationActionShown, key?:@"");
    }
}

- (void)notificationContentClickedWithNotificationKey:(NSString *)key {
    if (self.actionCallBack) {
        self.actionCallBack(QMUNCNotificationActionContentClicked, key?:@"");
    }
}

- (void)notificationButtonClickedWithNotificationKey:(NSString *)key {
    if (self.actionCallBack) {
        self.actionCallBack(QMUNCNotificationActionButtonClicked, key?:@"");
    }
}

- (void)notificationDismissedWithNotificationKey:(NSString *)key {
    if (self.actionCallBack) {
        self.actionCallBack(QMUNCNotificationActionDismissed, key?:@"");
    }
}

- (void)addNotificationActionCallBack:(void (^)(QMUNCNotificationAction, NSString *))callBack {
    self.actionCallBack = callBack;
}

@end

#pragma clang diagnostic pop
