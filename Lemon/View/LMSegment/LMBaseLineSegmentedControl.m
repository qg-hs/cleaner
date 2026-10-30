//
//  LMBaseLineSegmentedControl.m
//  Lemon
//

//  Copyright © 2019 Tencent. All rights reserved.
//

#import "LMBaseLineSegmentedControl.h"
#import "LMBaseLineSegmentedCell.h"

@implementation LMBaseLineSegmentedControl

+ (Class)cellClass{
    return [LMBaseLineSegmentedCell class];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self.cell setBordered:NO];
        self.focusRingType = NSFocusRingTypeNone;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)wantsUpdateLayer {
    return NO;
}

- (void)addSubview:(NSView *)view {
    // 阻止 macOS 26 AppKit 内部注入 _NSCoreHostingView<AppKitSegmentedControl> 胶囊子视图
    [view setHidden:YES];
}

- (void)layout {
    [super layout];
    // 隐藏 macOS 11+ / macOS 26 NSSegmentedControl 内部生成的系统胶囊背景视图
    for (NSView *subview in self.subviews) {
        subview.hidden = YES;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    for (NSView *subview in self.subviews) {
        subview.hidden = YES;
    }
    if ([self.cell isKindOfClass:[LMBaseLineSegmentedCell class]]) {
        [(LMBaseLineSegmentedCell *)self.cell drawWithFrame:self.bounds inView:self];
    }
}

- (void)setSelectedSegment:(NSInteger)selectedSegment {
    [super setSelectedSegment:selectedSegment];
    [self setNeedsDisplay:YES];
}

- (NSRect)segmentFrameForIndex:(NSInteger)index {
    CGFloat totalWidth = self.bounds.size.width;
    NSInteger count = self.segmentCount;
    CGFloat segmentWidth = [self widthForSegment:index];
    if (segmentWidth <= 0 && count > 0) {
        segmentWidth = totalWidth / count;
    }
    CGFloat offsetX = 0;
    NSInteger i;
    for (i = 0; i < index; i++) {
        CGFloat w = [self widthForSegment:i];
        if (w <= 0 && count > 0) {
            w = totalWidth / count;
        }
        offsetX += w;
    }
    return NSMakeRect(offsetX, 0, segmentWidth, self.bounds.size.height);
}

- (void)mouseDown:(NSEvent *)event {
    // 获取点击位置
    NSPoint point = [event locationInWindow];
    // 转换为控件坐标系
    NSPoint transformedPoint = [self convertPoint:point fromView:nil];
    
    // 确定点击的分段
    NSInteger index;
    for (index = 0; index < self.segmentCount; index++) {
        NSRect segmentRect = [self segmentFrameForIndex:index];
        if (NSPointInRect(transformedPoint, segmentRect)) {
            // 设置选中分段
            self.selectedSegment = index;
            [self setNeedsDisplay:YES];
            // 触发点击事件
            [self sendAction:self.action to:self.target];
            break;
        }
    }
}

- (void)updateRedPointInfo:(NSDictionary *)redPointDict {
    LMBaseLineSegmentedCell * __cell = self.cell;
    [__cell updateCellRedPointInfo:redPointDict];
    [self setNeedsDisplay:YES];
}

@end
