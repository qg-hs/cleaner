//
//  QMUserNotificationCenter.m
//  LemonMonitor
//
//  Copyright (c) 2015年 Tencent. All rights reserved.
//

#import "QMUserNotificationCenter.h"

#define kNotificationKey @"_notification_key"
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, UNNotificationCategory *> *registeredCategories API_AVAILABLE(macos(10.14));
@end

@implementation QMUserNotificationCenter

- (nullable UNUserNotificationCenter *)safeUNCenter API_AVAILABLE(macos(10.14)) {
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

- (void)scheduleNotification:(NSUserNotification *)notification key:(NSString *)key
{
    if (!key || ![_delegateDict objectForKey:key])
        return;

    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            [self deliverNotification:notification key:key];
            return;
        }
    }

    NSMutableDictionary * dict = [notification.userInfo mutableCopy];
    if (!dict)
        dict = [[NSMutableDictionary alloc] init];
    [dict setObject:key forKey:kNotificationKey];
    notification.userInfo = dict;
    [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:notification];
}

- (void)addDelegate:(id<NSUserNotificationCenterDelegate>)delegate forKey:(NSString *)key
{
    if (!delegate || !key)
        return;
    if ([[_delegateDict allKeys] containsObject:delegate])
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
                    NSString *userKey = [userInfo objectForKey:kNotificationKey];
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
        NSString * userKey = [userInfo objectForKey:kNotificationKey];
        if (!userKey)
            continue;
        if ([userKey isEqualToString:key])
        {
            if (!sender || sender(userInfo))
                [center removeDeliveredNotification:notification];
        }
    }
}

- (void)deliverNotification:(NSUserNotification *)notification key:(NSString *)key
{
    if (@available(macOS 10.14, *)) {
        if (!key || ![_delegateDict objectForKey:key])
            return;

        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (!unCenter) {
            return;
        }

        NSMutableDictionary *dict = [notification.userInfo mutableCopy];
        if (!dict)
            dict = [[NSMutableDictionary alloc] init];
        [dict setObject:key forKey:kNotificationKey];

        NSString *reqId = notification.identifier.length > 0 ? notification.identifier : [[NSUUID UUID] UUIDString];
        NSString *categoryId = [NSString stringWithFormat:@"%@_%@", kNotificationCategoryKey, key];

        NSMutableArray *actions = [[NSMutableArray alloc] init];
        if (notification.hasActionButton && notification.actionButtonTitle.length > 0) {
            UNNotificationAction *action = [UNNotificationAction
                                            actionWithIdentifier:UNNotificationActionDidBlock
                                            title:notification.actionButtonTitle
                                            options:UNNotificationActionOptionForeground];
            [actions addObject:action];
        }
        if (notification.otherButtonTitle.length > 0) {
            UNNotificationAction *action = [UNNotificationAction
                                            actionWithIdentifier:@"UNNotificationActionOther"
                                            title:notification.otherButtonTitle
                                            options:UNNotificationActionOptionNone];
            [actions addObject:action];
        }

        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:categoryId
                                                                                  actions:actions
                                                                        intentIdentifiers:@[]
                                                                                  options:UNNotificationCategoryOptionCustomDismissAction];

        @synchronized (self.registeredCategories) {
            self.registeredCategories[categoryId] = category;
            NSSet *categories = [NSSet setWithArray:self.registeredCategories.allValues];
            [unCenter setNotificationCategories:categories];
        }

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
        [unCenter addNotificationRequest:request withCompletionHandler:nil];
    }
}

- (void)removeAllDeliveredNotifications
{
    if (@available(macOS 10.14, *)) {
        UNUserNotificationCenter *unCenter = [self safeUNCenter];
        if (unCenter) {
            [unCenter removeAllDeliveredNotifications];
            return;
        }
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
}

#pragma mark - NSUserNotificationCenterDelegate (Legacy Fallback)

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
    NSDictionary *userInfo = [notification userInfo];
    if (!userInfo)
    {
        return;
    }
    NSString * key = [userInfo objectForKey:kNotificationKey];
    if (key)
    {
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
    NSString * key = [userInfo objectForKey:kNotificationKey];
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
    NSString * key = [userInfo objectForKey:kNotificationKey];
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

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler API_AVAILABLE(macos(10.14)) {
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
    NSString *key = [response.notification.request.content.userInfo objectForKey:kNotificationKey];
    NSUserNotificationActivationType bridgedType = NSUserNotificationActivationTypeActionButtonClicked;
    if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        bridgedType = NSUserNotificationActivationTypeContentsClicked;
    } else if ([response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
        bridgedType = NSUserNotificationActivationTypeNone;
    } else {
        bridgedType = NSUserNotificationActivationTypeActionButtonClicked;
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
            [dict setObject:response.actionIdentifier forKey:@"ACTION_ID"];
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

@end

#pragma clang diagnostic pop
