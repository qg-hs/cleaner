//
//  LMSystemOptimizeService.h
//  Lemon
//

#import <Foundation/Foundation.h>
#import "LMSystemOptimizeTask.h"

NS_ASSUME_NONNULL_BEGIN

@interface LMSystemOptimizeService : NSObject

+ (NSArray<LMSystemOptimizeTask *> *)defaultMaintenanceTasks;

/// VPN 活跃隧道探测（过滤系统内置空 fe80:: utun 接口，仅在真实 IPv4 隧道连接时返回 YES）
+ (BOOL)hasActiveVPNTunnel;

/// 执行单项维护任务（需在后台队列调用）
+ (void)executeTask:(LMSystemOptimizeTask *)task allowPrivilegedDNS:(BOOL)allowPrivDNS;

/// 外接 USB 与 SMB/NFS 网络卷禁写 .DS_Store 状态
+ (BOOL)isNetworkDSStoreSuppressed;
+ (BOOL)isUSBDSStoreSuppressed;
+ (BOOL)setSuppressNetworkDSStore:(BOOL)suppressNet suppressUSBDSStore:(BOOL)suppressUSB;

/// 终端 sudo Touch ID 免密认证开关
+ (BOOL)isTouchIDPamModuleAvailable;
+ (BOOL)isSudoTouchIDEnabled;
+ (BOOL)setSudoTouchIDEnabled:(BOOL)enabled errorMessage:(NSString * _Nullable * _Nullable)outError;

@end

NS_ASSUME_NONNULL_END
