//
//  LMBigSpaceView.h
//  CleanerSpaceAnalyse
//
//  
//

#import <Cocoa/Cocoa.h>
#import "LMSpaceView.h"

@interface LMBigSpaceView : NSView <LMSpaceViewMoveDelegate>

@property(nonatomic, strong) NSPopover *tipPop;

@end

