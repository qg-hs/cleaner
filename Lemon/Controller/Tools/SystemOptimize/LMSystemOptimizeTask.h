//
//  LMSystemOptimizeTask.h
//  Lemon
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LMSystemOptimizeTaskType) {
    LMSystemOptimizeTaskDNSFlush = 0,
    LMSystemOptimizeTaskQuickLookRebuild = 1,
    LMSystemOptimizeTaskSQLiteVacuum = 2,
    LMSystemOptimizeTaskSavedStateAndQuarantine = 3,
    LMSystemOptimizeTaskBrokenPlistAudit = 4
};

typedef NS_ENUM(NSInteger, LMSystemOptimizeTaskState) {
    LMSystemOptimizeTaskStateIdle = 0,
    LMSystemOptimizeTaskStateRunning = 1,
    LMSystemOptimizeTaskStateSuccess = 2,
    LMSystemOptimizeTaskStateSkipped = 3,
    LMSystemOptimizeTaskStateFailed = 4
};

@interface LMSystemOptimizeTask : NSObject

@property (nonatomic, assign) LMSystemOptimizeTaskType taskType;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, assign) BOOL requiresAdmin;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) LMSystemOptimizeTaskState state;
@property (nonatomic, copy, nullable) NSString *resultText;
@property (nonatomic, assign) uint64_t reclaimedBytes;

@end

NS_ASSUME_NONNULL_END
