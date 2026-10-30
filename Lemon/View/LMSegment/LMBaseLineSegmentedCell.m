//
//  LMBaseLineSegmentedCell.m
//  Lemon
//

//  Copyright © 2019 Tencent. All rights reserved.
//

#import "LMBaseLineSegmentedCell.h"
#import <QMUICommon/NSFontHelper.h>
#import <QMUICommon/NSFont+LineHeight.h>
#import <QMUICommon/LMAppThemeHelper.h>
#import <QMCoreFunction/NSColor+Extension.h>


static CGFloat const kSelectedBarHeight = 2.5; // 选中底部胶囊条高度
static CGFloat const kSelectedBarWidth = 24.0; // 选中底部胶囊条宽度

@interface LMBaseLineSegmentedCell ()

@property(nonatomic, strong) NSDictionary* __redPointDict;

@end

@implementation LMBaseLineSegmentedCell

- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(NSView *)controlView{
    NSString *label = [self labelForSegment:segment];
    if (!label) {
        return;
    }

    BOOL isSelected = (segment == self.selectedSegment);
    NSColor *highlightedColor = [LMAppThemeHelper getTitleColor];
    NSColor *highlightedBaselineColor = [NSColor colorWithHex:0xFFAA09];
    NSColor *normalColor = [NSColor colorWithHex:0x94979B];
    NSColor *textColor = isSelected ? highlightedColor : normalColor;

    NSFont *textFont = isSelected
        ? [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium]
        : [NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular];

    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [paragraphStyle setAlignment:NSTextAlignmentCenter];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSForegroundColorAttributeName: textColor,
        NSFontAttributeName: textFont
    };

    NSRect labelBounds = [label boundingRectWithSize:frame.size
                                             options:NSStringDrawingUsesLineFragmentOrigin
                                          attributes:attributes];
    CGFloat drawHeight = ceil(labelBounds.size.height);
    CGFloat drawY = round(frame.origin.y + (frame.size.height - drawHeight) / 2.0 - 1.0);
    NSRect drawRect = NSMakeRect(frame.origin.x, drawY, frame.size.width, drawHeight);
    [label drawInRect:drawRect withAttributes:attributes];

    if (isSelected) {
        [self __saveSegmentSelectedState:label];
        CGFloat barWidth = MIN(kSelectedBarWidth, ceil(labelBounds.size.width));
        CGFloat barX = round(frame.origin.x + (frame.size.width - barWidth) / 2.0);
        CGFloat barY = [[NSGraphicsContext currentContext] isFlipped]
            ? (NSMaxY(frame) - kSelectedBarHeight)
            : NSMinY(frame);
        NSRect barRect = NSMakeRect(barX, barY, barWidth, kSelectedBarHeight);
        NSBezierPath *capsulePath = [NSBezierPath bezierPathWithRoundedRect:barRect
                                                                    xRadius:kSelectedBarHeight / 2.0
                                                                    yRadius:kSelectedBarHeight / 2.0];
        [highlightedBaselineColor setFill];
        [capsulePath fill];
    }

    // 未读红点指示器
    if ([self __needShowRedPoint:label]) {
        CGFloat dotSize = 6.0;
        CGFloat textRightX = round(frame.origin.x + (frame.size.width + labelBounds.size.width) / 2.0);
        CGFloat dotX = MIN(NSMaxX(frame) - dotSize - 2.0, textRightX + 2.0);
        CGFloat dotY = [[NSGraphicsContext currentContext] isFlipped]
            ? (drawY + 1.0)
            : (NSMaxY(drawRect) - dotSize - 1.0);
        NSBezierPath *dotPath = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX, dotY, dotSize, dotSize)];
        [[NSColor colorWithHex:0xFF4D4F] setFill];
        [dotPath fill];
    }
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSInteger count = self.segmentCount;
    if (count <= 0) {
        return;
    }
    CGFloat currentX = cellFrame.origin.x;
    NSInteger i;
    for (i = 0; i < count; i++) {
        CGFloat segWidth = [self widthForSegment:i];
        if (segWidth <= 0) {
            segWidth = cellFrame.size.width / count;
        }
        NSRect segFrame = NSMakeRect(currentX, cellFrame.origin.y, segWidth, cellFrame.size.height);
        [self drawSegment:i inFrame:segFrame withView:controlView];
        currentX += segWidth;
    }
}


- (void)updateCellRedPointInfo:(NSDictionary *)redPointDict {
    self.__redPointDict = redPointDict;
}

- (BOOL)__needShowRedPoint:(NSString *)title {
    if ([title isKindOfClass:NSString.class]) {
        NSString *key = self.__redPointDict[title];
        if (key && ![[NSUserDefaults standardUserDefaults] boolForKey:key]) {
            return YES;
        }
    }
    return NO;
}

- (void)__saveSegmentSelectedState:(NSString *)title {
    if ([title isKindOfClass:NSString.class]) {
        NSString *key = self.__redPointDict[title];
        if (key && ![[NSUserDefaults standardUserDefaults] boolForKey:key]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
        }
    }
}


@end
