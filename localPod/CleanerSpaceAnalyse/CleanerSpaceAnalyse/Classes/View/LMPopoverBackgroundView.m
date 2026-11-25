//
//  MyPopoverBackgroundView.m
//  CleanerSpaceAnalyse
//
//  
//

#import "LMPopoverBackgroundView.h"

@implementation LMPopoverBackgroundView

-(void)drawRect:(NSRect)dirtyRect
{
    [[NSColor blackColor] set];
    NSRectFill(self.bounds);
}


@end
