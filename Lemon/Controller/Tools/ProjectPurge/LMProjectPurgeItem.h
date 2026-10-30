//
//  LMProjectPurgeItem.h
//  Lemon
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LMProjectEcosystem) {
    LMProjectEcosystemAll = 0,
    LMProjectEcosystemNode = 1,
    LMProjectEcosystemRustGo = 2,
    LMProjectEcosystemPython = 3,
    LMProjectEcosystemAppleJVM = 4,
    LMProjectEcosystemOther = 5
};

@interface LMProjectPurgeItem : NSObject

@property (nonatomic, copy) NSString *artifactPath;
@property (nonatomic, copy) NSString *projectRootPath;
@property (nonatomic, copy) NSString *projectName;
@property (nonatomic, copy) NSString *artifactName;
@property (nonatomic, copy) NSString *ecosystemTag;
@property (nonatomic, assign) LMProjectEcosystem ecosystem;
@property (nonatomic, assign) uint64_t sizeInBytes;
@property (nonatomic, strong) NSDate *lastModifiedDate;
@property (nonatomic, assign) NSInteger daysSinceActive;
@property (nonatomic, assign) BOOL isRecent;
@property (nonatomic, assign) BOOL isSelected;

@end

NS_ASSUME_NONNULL_END
