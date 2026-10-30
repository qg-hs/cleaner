//
//  QMCoreFunctionDef.h
//  Pods
//
//

#ifndef QMCoreFunctionDef_h
#define QMCoreFunctionDef_h

#ifdef APPSTORE_VERSION
#define kTXCProductId @"36664" // Lite和官网使用同一个，原Lite为52728
#else
#define kTXCProductId @"36664"
#endif

// 纯本地零联网：移除反馈外链及客户端/系统版本参数拼接
#define QMFeedbackURL (@"")

#endif /* QMCoreFunctionDef_h */
