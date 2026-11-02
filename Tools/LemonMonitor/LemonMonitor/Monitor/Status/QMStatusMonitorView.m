//
//  QMStatusMonitorView.m
//  LemonMonitor
//

//  Copyright (c) 2014年 Tencent. All rights reserved.
//

#import "QMStatusMonitorView.h"
#import "QMStatusCircleView.h"
#import "QMStatusTextField.h"
#import "QMNetworkSpeedFormatter.h"
#import <Masonry/Masonry.h>
#import <CoreFoundation/CFPreferences.h>
#import <CoreFoundation/CFBase.h>
#import <QMCoreFunction/NSTextField+Extension.h>
#import <QMCoreFunction/NSColor+Extension.h>
#import <QMCoreFunction/McCoreFunction.h>
#import <LemonHardware/MachineModel.h>
#import <QMUICommon/LMCommonHelper.h>

#import "QMDragEffectView.h"

// 状态栏全量采用等宽数字字体（tnum），彻底消除数字跳变引起的状态栏左右抖动
static NSFont *LMStatusMonoDigitFont(CGFloat size, NSFontWeight weight)
{
    return [NSFont monospacedDigitSystemFontOfSize:size weight:weight];
}

@interface QMStatusMonitorView ()
{
    NSMutableArray* mArrayForDarkModeAdaptiveViews;

}
// [NSColor controlTextColor] 的缓存，在必要的时候主动更新
@property (nonatomic, copy) NSColor *textColor;

@end


// 特别注意 Monitor上的字体颜色. 1. 要分暗黑主题和普通主题.
// 2.在外接其他显示器时, 非 Focus屏幕的字体颜色会自动变色.(10.14.4 之后出现) 如果是写死的颜色如 FFFFFF,不会自动变色, 如果是使用[NSColor controlTextColor] 会自动变色.
// 另外图片会自动变灰, 带固定颜色背景的 View 不会自动变色.


@implementation QMStatusMonitorView
@synthesize upSpeed;
@synthesize downSpeed;

- (QMEffectMode)effectMode
{
    return QMEffectStatusMode;
}

- (instancetype)initWithFrame:(NSRect)frameRect{
    self = [super initWithFrame:frameRect];
    if (self) {
//        logo = [[NSImageView alloc]initWithFrame:NSMakeRect(2, 3, 16, 16)];
//        [self addSubview:logo];
    }
        return self;
}
- (void)awakeFromNib
{
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain];
    id style = [dict objectForKey:@"AppleInterfaceStyle"];
    mDarkModeOn = ( style && [style isKindOfClass:[NSString class]] && NSOrderedSame == [style caseInsensitiveCompare:@"dark"] );
    
    NSLog(@"%s,mDarkModeOn=%d", __PRETTY_FUNCTION__, mDarkModeOn);
    
    mArrayForDarkModeAdaptiveViews = [[NSMutableArray alloc] init];
}

-(NSView*)getLogoContainerView:(NSSize*)size
{
    NSView* container = [[NSView alloc] init];
    NSImageView *logo1 = [[NSImageView alloc] init];
    logo1.image = [[NSBundle mainBundle] imageForResource:@"LOGO_16_black"];
    [logo1.image setTemplate:YES];
    logo1.imageScaling = NSImageScaleProportionallyUpOrDown;
    [container addSubview:logo1];
    [logo1 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(container);
        make.width.height.equalTo(@18);
    }];
    
    (*size).height = 22;
    (*size).width = 22;
    
    return container;
}

-(NSView*)getMemContainerView:(NSSize*)size
{
    NSView* containerMem = [[NSView alloc] init];
    
    
    NSTextField* memTextField = [NSTextField labelWithStringCompat:@"100%"];
    memTextField.font = LMStatusMonoDigitFont(11, NSFontWeightRegular);


    [containerMem addSubview:memTextField];
    [memTextField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerMem.mas_centerX);
        make.top.equalTo(containerMem.mas_top).offset(1);
    }];
    NSTextField* memTextField2 = [NSTextField labelWithStringCompat:@"MEM"];
    memTextField2.font = [NSFont systemFontOfSize:7];
    [containerMem addSubview:memTextField2];
    [memTextField2 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerMem.mas_centerX);
        make.bottom.equalTo(containerMem.mas_bottom);
    }];
    
    
    //    NSInteger textColor = mDarkModeOn ? 0xFFFFFF : 0x333333;
    //    memTextField.textColor = [NSColor colorWithHex:textColor alpha:1.0];
    //    memTextField2.textColor = [NSColor colorWithHex:textColor alpha:1.0];

    memTextField.textColor = [self getTextColor];
    memTextField2.textColor = [self getTextColor];

    (*size).height = 22;
    (*size).width = 30;
    mMemUsageField = memTextField;
    [self setRamUsed:self.ramUsed];
    [mArrayForDarkModeAdaptiveViews addObject:memTextField];
    [mArrayForDarkModeAdaptiveViews addObject:memTextField2];
    
    return containerMem;
}

-(NSView*)getDiskContainerView:(NSSize*)size
{
    NSView* containerDisk = [[NSView alloc] init];


    NSTextField* DiskTextField = [NSTextField labelWithStringCompat:@"0%"];
    DiskTextField.font = LMStatusMonoDigitFont(11, NSFontWeightRegular);
    [containerDisk addSubview:DiskTextField];
    [DiskTextField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerDisk.mas_centerX);
        make.top.equalTo(containerDisk.mas_top).offset(1);
    }];

    NSTextField* DiskTextField2 = [NSTextField labelWithStringCompat:@"SSD"];
    DiskTextField2.font = [NSFont systemFontOfSize:7];
    [containerDisk addSubview:DiskTextField2];
    [DiskTextField2 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerDisk.mas_centerX);
        make.bottom.equalTo(containerDisk.mas_bottom);
    }];
    
//    NSInteger textColor = mDarkModeOn ? 0xFFFFFF : 0x333333;
//    DiskTextField.textColor = [NSColor colorWithHex:textColor alpha:1.0];
//    DiskTextField2.textColor = [NSColor colorWithHex:textColor alpha:1.0];

    DiskTextField.textColor = [self getTextColor];
    DiskTextField2.textColor = [self getTextColor];
    
    (*size).height = 22;
    (*size).width = 30;
    mDiskUsageField = DiskTextField;
    [self setDiskUsed:self.diskUsed];
    [mArrayForDarkModeAdaptiveViews addObject:DiskTextField];
    [mArrayForDarkModeAdaptiveViews addObject:DiskTextField2];
    
    return containerDisk;
}

-(NSView*)getTmpContainerView:(NSSize*)size
{
    NSView* container = [[NSView alloc] init];
    
    
    NSTextField* mTextField = [NSTextField labelWithStringCompat:@"90C"];
    mTextField.font = LMStatusMonoDigitFont(11, NSFontWeightRegular);
    [container addSubview:mTextField];
    [mTextField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(container.mas_centerX);
        make.top.equalTo(container.mas_top).offset(1);
    }];
    
    NSTextField* mTextField2 = [NSTextField labelWithStringCompat:@"SEN"];
    mTextField2.font = [NSFont systemFontOfSize:7];
    [container addSubview:mTextField2];
    [mTextField2 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(container.mas_centerX);
        make.bottom.equalTo(container.mas_bottom);
    }];
    
//    NSInteger textColor = mDarkModeOn ? 0xFFFFFF : 0x333333;
//    mTextField.textColor = [NSColor colorWithHex:textColor alpha:1.0];
//    mTextField2.textColor = [NSColor colorWithHex:textColor alpha:1.0];
    mTextField.textColor = [self getTextColor];
    mTextField2.textColor = [self getTextColor];
    
    (*size).height = 22;
    (*size).width = 30;
    mCpuTempField = mTextField;
    [self setTemperatureValue:self.temperatureValue];
    [mArrayForDarkModeAdaptiveViews addObject:mTextField];
    [mArrayForDarkModeAdaptiveViews addObject:mTextField2];
    
    return container;
}


-(NSView*)getRpmContainerView:(NSSize*)size
{
    NSView* container = [[NSView alloc] init];
    
    NSTextField* mTextField = [NSTextField labelWithStringCompat:@"9999"];
    mTextField.font = LMStatusMonoDigitFont(11, NSFontWeightRegular);
    [container addSubview:mTextField];
    [mTextField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(container.mas_centerX);
        make.top.equalTo(container.mas_top).offset(1);
    }];
    
    NSTextField* mTextField2 = [NSTextField labelWithStringCompat:@"RPM"];
    mTextField2.font = [NSFont systemFontOfSize:7];
    [container addSubview:mTextField2];
    [mTextField2 mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(container.mas_centerX);
        make.bottom.equalTo(container.mas_bottom);
    }];
    
//    NSInteger textColor = mDarkModeOn ? 0xFFFFFF : 0x333333;
//    mTextField.textColor = [NSColor colorWithHex:textColor alpha:1.0];
//    mTextField2.textColor = [NSColor colorWithHex:textColor alpha:1.0];
    mTextField.textColor = [self getTextColor];
    mTextField2.textColor = [self getTextColor];
    
    (*size).height = 22;
    (*size).width = 30;
    mCpuFanSpeedField = mTextField;
    [self setFanSpeedValue:self.fanSpeedValue];
    [mArrayForDarkModeAdaptiveViews addObject:mTextField];
    [mArrayForDarkModeAdaptiveViews addObject:mTextField2];
    
    return container;
}

-(NSView*)getNetContainerView:(NSSize*)size
{
    // network container
    NSView* colNetContainerView = [[NSView alloc] init];
    
    
    NSImageView* upLoadSpeedIcon = [[NSImageView alloc] init];
    [colNetContainerView addSubview:upLoadSpeedIcon];
    [upLoadSpeedIcon setImage:[[NSBundle mainBundle] imageForResource:@"lemon_status_net_upload_white"]];
    [upLoadSpeedIcon.image setTemplate:YES];
    [upLoadSpeedIcon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(colNetContainerView.mas_left);
        make.top.mas_equalTo(colNetContainerView.mas_top).offset(2.5);
    }];
    
    NSTextField* upLoadSpeedText = [NSTextField labelWithStringCompat:@"0"];
    upLoadSpeedText.attributedStringValue = [self getAttrStringFromNetSpeed:0];
    upLoadSpeedText.font = LMStatusMonoDigitFont(9, NSFontWeightRegular);
    [colNetContainerView addSubview:upLoadSpeedText];
    [upLoadSpeedText mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(upLoadSpeedIcon.mas_right);
        make.centerY.equalTo(upLoadSpeedIcon);
        //        make.top.mas_equalTo(colNetContainerView.mas_top).offset(16);
    }];
    
    NSImageView* downLoadSpeedIcon = [[NSImageView alloc] init];
    [colNetContainerView addSubview:downLoadSpeedIcon];
    [downLoadSpeedIcon setImage:[[NSBundle mainBundle]  imageForResource:@"lemon_status_net_download_white"]];
    [downLoadSpeedIcon.image setTemplate:YES];
    [downLoadSpeedIcon mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(colNetContainerView.mas_left);
        make.bottom.mas_equalTo(colNetContainerView.mas_bottom).offset(-2);
    }];
    
    NSTextField* downLoadSpeedText = [NSTextField labelWithStringCompat:@"0"];
    downLoadSpeedText.attributedStringValue = [self getAttrStringFromNetSpeed:0];
    downLoadSpeedText.font = LMStatusMonoDigitFont(9, NSFontWeightRegular);
    [colNetContainerView addSubview:downLoadSpeedText];
    [downLoadSpeedText mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(downLoadSpeedIcon.mas_right);
        make.bottom.mas_equalTo(downLoadSpeedIcon.mas_bottom).offset(1);
    }];
    

//    NSInteger textColor = mDarkModeOn ? 0xFFFFFF : 0x333333;
//    upLoadSpeedText.textColor = [NSColor colorWithHex:textColor alpha:1.0];
//    downLoadSpeedText.textColor = [NSColor colorWithHex:textColor alpha:1.0];
    upLoadSpeedText.textColor = [self getTextColor];
    downLoadSpeedText.textColor = [self getTextColor];
    
    (*size).height = 22;
    (*size).width = 40;
    mDownSpeedField = downLoadSpeedText;
    mUpSpeedField = upLoadSpeedText;
//    mUpLoadSpeedMeasurement = upLoadSpeedMeasurement;
//    mDownLoadSpeedMeasurement = downLoadSpeedMeasurement;
    [self setDownSpeed:self.downSpeed];
    [self setUpSpeed:self.upSpeed];
    [mArrayForDarkModeAdaptiveViews addObject:upLoadSpeedText];
    [mArrayForDarkModeAdaptiveViews addObject:downLoadSpeedText];
    
    return colNetContainerView;
}

- (NSView *)getCpuUsageContainerView:(NSSize *)size {
    NSView *containerView = [[NSView alloc] init];
    NSTextField *cpuValueText = [NSTextField labelWithStringCompat:@"%"];
    cpuValueText.font = LMStatusMonoDigitFont(11, NSFontWeightRegular);
    [containerView addSubview:cpuValueText];
    [cpuValueText mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerView);
        make.top.equalTo(containerView).offset(1);
    }];
    NSTextField *cpuLabel = [NSTextField labelWithStringCompat:@"CPU"];
    cpuLabel.font = [NSFont systemFontOfSize:7];
    [containerView addSubview:cpuLabel];
    [cpuLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerView);
        make.bottom.equalTo(containerView);
    }];
    cpuLabel.textColor = [self getTextColor];
    cpuValueText.textColor = [self getTextColor];
    (*size).height = 22;
    (*size).width = 30;
    mCpuUsageField = cpuValueText;
    [self setCpuUsed:self.cpuUsed];
    [mArrayForDarkModeAdaptiveViews addObject:cpuValueText];
    [mArrayForDarkModeAdaptiveViews addObject:cpuLabel];
    return containerView;
}

- (NSView *)getGpuUsageContainerView:(NSSize *)size {
    NSView *containerView = [[NSView alloc] init];
    NSTextField *gpuValueText = [NSTextField labelWithStringCompat:@"%"];
    gpuValueText.font = LMStatusMonoDigitFont(11, NSFontWeightRegular);
    [containerView addSubview:gpuValueText];
    [gpuValueText mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerView);
        make.top.equalTo(containerView).offset(1);
    }];
    NSTextField *gpuLabel = [NSTextField labelWithStringCompat:@"GPU"];
    gpuLabel.font = [NSFont systemFontOfSize:7];
    [containerView addSubview:gpuLabel];
    [gpuLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(containerView);
        make.bottom.equalTo(containerView);
    }];
    gpuLabel.textColor = [self getTextColor];
    gpuValueText.textColor = [self getTextColor];
    (*size).height = 22;
    (*size).width = 30;
    mGpuUsageField = gpuValueText;
    [self setGpuUsed:self.gpuUsed];
    [mArrayForDarkModeAdaptiveViews addObject:gpuValueText];
    [mArrayForDarkModeAdaptiveViews addObject:gpuLabel];
    return containerView;
}

- (void)_bindCompactField:(NSTextField *)valueField forItemFlag:(long)flag {
    switch (flag) {
        case STATUS_TYPE_CPU:
            mCpuUsageField = valueField;
            [self setCpuUsed:self.cpuUsed];
            break;
        case STATUS_TYPE_GPU:
            mGpuUsageField = valueField;
            [self setGpuUsed:self.gpuUsed];
            break;
        case STATUS_TYPE_MEM:
            mMemUsageField = valueField;
            [self setRamUsed:self.ramUsed];
            break;
        case STATUS_TYPE_DISK:
            mDiskUsageField = valueField;
            [self setDiskUsed:self.diskUsed];
            break;
        case STATUS_TYPE_TEP:
            mCpuTempField = valueField;
            [self setTemperatureValue:self.temperatureValue];
            break;
        case STATUS_TYPE_FAN:
            mCpuFanSpeedField = valueField;
            [self setFanSpeedValue:self.fanSpeedValue];
            break;
        default:
            break;
    }
}

- (NSString *)_shortTitleForItemFlag:(long)flag {
    switch (flag) {
        case STATUS_TYPE_CPU:  return @"CPU";
        case STATUS_TYPE_GPU:  return @"GPU";
        case STATUS_TYPE_MEM:  return @"MEM";
        case STATUS_TYPE_DISK: return @"SSD";
        case STATUS_TYPE_TEP:  return @"SEN";
        case STATUS_TYPE_FAN:  return @"RPM";
        default:               return @"";
    }
}

- (NSView *)_singleMetricViewForFlag:(long)flag size:(NSSize *)size {
    switch (flag) {
        case STATUS_TYPE_CPU:  return [self getCpuUsageContainerView:size];
        case STATUS_TYPE_GPU:  return [self getGpuUsageContainerView:size];
        case STATUS_TYPE_MEM:  return [self getMemContainerView:size];
        case STATUS_TYPE_DISK: return [self getDiskContainerView:size];
        case STATUS_TYPE_TEP:  return [self getTmpContainerView:size];
        case STATUS_TYPE_FAN:  return [self getRpmContainerView:size];
        default:               return [self getLogoContainerView:size];
    }
}

// 刘海屏紧凑双行堆叠列：上下两行各渲染一项 "标签 + 等宽数值"，列宽压缩约 45%
- (NSView *)getCompactPairContainerTopFlag:(long)topFlag bottomFlag:(long)bottomFlag size:(NSSize *)size {
    NSView *container = [[NSView alloc] init];
    NSColor *txtColor = [self getTextColor];

    NSTextField *topTitle = [NSTextField labelWithStringCompat:[self _shortTitleForItemFlag:topFlag]];
    topTitle.font = [NSFont systemFontOfSize:7.5 weight:NSFontWeightMedium];
    topTitle.textColor = txtColor;
    [container addSubview:topTitle];

    NSTextField *topVal = [NSTextField labelWithStringCompat:@"0%"];
    topVal.font = LMStatusMonoDigitFont(8.5, NSFontWeightRegular);
    topVal.alignment = NSTextAlignmentRight;
    topVal.textColor = txtColor;
    [container addSubview:topVal];

    NSTextField *botTitle = [NSTextField labelWithStringCompat:[self _shortTitleForItemFlag:bottomFlag]];
    botTitle.font = [NSFont systemFontOfSize:7.5 weight:NSFontWeightMedium];
    botTitle.textColor = txtColor;
    [container addSubview:botTitle];

    NSTextField *botVal = [NSTextField labelWithStringCompat:@"0%"];
    botVal.font = LMStatusMonoDigitFont(8.5, NSFontWeightRegular);
    botVal.alignment = NSTextAlignmentRight;
    botVal.textColor = txtColor;
    [container addSubview:botVal];

    [topVal mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(container);
        make.top.equalTo(container).offset(1);
    }];
    [topTitle mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(container);
        make.centerY.equalTo(topVal);
    }];
    [botVal mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(container);
        make.bottom.equalTo(container).offset(-1);
    }];
    [botTitle mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(container);
        make.centerY.equalTo(botVal);
    }];

    [mArrayForDarkModeAdaptiveViews addObject:topTitle];
    [mArrayForDarkModeAdaptiveViews addObject:topVal];
    [mArrayForDarkModeAdaptiveViews addObject:botTitle];
    [mArrayForDarkModeAdaptiveViews addObject:botVal];

    [self _bindCompactField:topVal forItemFlag:topFlag];
    [self _bindCompactField:botVal forItemFlag:bottomFlag];

    BOOL hasRpm = (topFlag == STATUS_TYPE_FAN || bottomFlag == STATUS_TYPE_FAN);
    (*size).height = 22;
    (*size).width = hasRpm ? 48 : 44;
    return container;
}

- (NSColor *)getTextColor {
    if (!_textColor) {
        [self updateTextColor];
    }
    return _textColor;
}

- (void)updateTextColor {
    self.textColor = [NSColor controlTextColor];
}

- (void)updateAllTextColors {
    [self updateTextColor];
    NSColor *currentTextColor = [self getTextColor];
    for (NSTextField *textField in self->mArrayForDarkModeAdaptiveViews) {
        textField.textColor = currentTextColor;
        [textField setNeedsDisplay:YES];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [self updateAllTextColors];
    }
}

- (void)updateTrackingAreas
{
    NSArray *trackingAreas = [self trackingAreas];
    for (NSTrackingArea *area in trackingAreas)
    {
        [self removeTrackingArea:area];
    }
    NSRect bounds = self.bounds;
    bounds.size.height += 1;
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:bounds options:NSTrackingMouseEnteredAndExited|NSTrackingMouseMoved|NSTrackingActiveAlways
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}


- (void)setRamUsed:(double)value
{
    [super setRamUsed:value];
    mMemUsageField.stringValue = [NSString stringWithFormat:@"%d%%",(int)round(value*100)];
//    [super setRamUsed:value];
//
//    ramPieView.progress = value;
//    ramFieldView.progress = value;
}



-(void)setDiskUsed:(double)value {
    [super setDiskUsed:value];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->mDiskUsageField.stringValue = [NSString stringWithFormat:@"%d%%",(int)round(value*100)];
    });
}

- (void)setCpuUsed:(double)cpuUsed {
    [super setCpuUsed:cpuUsed];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->mCpuUsageField.stringValue = [NSString stringWithFormat:@"%d%%",(int)round(cpuUsed*100)];
    });
}

- (void)setGpuUsed:(double)gpuUsed {
    [super setGpuUsed:gpuUsed];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->mGpuUsageField.stringValue = [NSString stringWithFormat:@"%d%%",(int)round(gpuUsed*100)];
    });
}

-(NSAttributedString*)getAttrStringFromNetSpeed:(float)value
{
    const float oneMB = 1024;
    float _value = 0;
    NSString * formatStr = nil;
    if (value > 1000)
    {
        _value = value / oneMB;
        formatStr = @" M/s";
    }
    else
    {
        _value = value;
        formatStr = @" K/s";
    }
    NSFont *numFont = LMStatusMonoDigitFont(9, NSFontWeightRegular);
    NSFont *unitFont = LMStatusMonoDigitFont(8, NSFontWeightRegular);
    NSString *str = (_value > 100)
        ? [NSString stringWithFormat:@"%d%@", (int)_value, formatStr]
        : [NSString stringWithFormat:@"%.1f%@", _value, formatStr];
    NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:str];
    [attributeString addAttribute:NSFontAttributeName value:numFont range:NSMakeRange(0, str.length)];
    [attributeString addAttribute:NSFontAttributeName value:unitFont range:NSMakeRange(str.length - 3, 3)];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    [attributeString addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0, str.length)];
    return attributeString;
}

- (void)setUpSpeed:(float)value
{
    [super setUpSpeed:value];
    mUpSpeedField.attributedStringValue = [self getAttrStringFromNetSpeed:value/1000.f];
}

- (void)setDownSpeed:(float)value
{
    [super setDownSpeed:value];
    mDownSpeedField.attributedStringValue = [self getAttrStringFromNetSpeed:value/1000.f];
}

-(void)setTemperatureValue:(double)value
{
    [super setTemperatureValue:value];
    if (value < 10.0) {
        mCpuTempField.stringValue = @"--°C";
    } else {
        mCpuTempField.stringValue = [NSString stringWithFormat:@"%d°C", (int)round(value)];
    }
}

-(void)setFanSpeedValue:(float)value
{
    [super setFanSpeedValue:value];
    mCpuFanSpeedField.stringValue = [NSString stringWithFormat:@"%d", (int)round(value)];
}

- (void)setStatusType:(long)type
{
    NSLog(@"%s, type=%lx", __PRETTY_FUNCTION__, type);
    
    // remove all subview
    while (self.subviews.count > 0) {
        NSView* subview = (NSView*)self.subviews.firstObject;
        [subview removeFromSuperview];
    }
    
    [mArrayForDarkModeAdaptiveViews removeAllObjects];
    
    BOOL hasPhysicalFan = LMDeviceHasPhysicalFan();
    long scalarOrder[6] = {
        STATUS_TYPE_CPU,
        STATUS_TYPE_GPU,
        STATUS_TYPE_MEM,
        STATUS_TYPE_DISK,
        STATUS_TYPE_TEP,
        STATUS_TYPE_FAN
    };
    long enabledScalars[6] = {0};
    int scalarCount = 0;
    int idx;
    for (idx = 0; idx < 6; idx++) {
        long flag = scalarOrder[idx];
        if (flag == STATUS_TYPE_FAN && !hasPhysicalFan) {
            continue; // 无风扇机型自动跳过顶栏 0 RPM 占位
        }
        if (type & flag) {
            enabledScalars[scalarCount++] = flag;
        }
    }

    int totalVisibleItems = scalarCount + ((type & STATUS_TYPE_LOGO) ? 1 : 0) + ((type & STATUS_TYPE_NET) ? 1 : 0);
    BOOL isCompact = NO;
    if (type & STATUS_TYPE_COMPACT_SET) {
        isCompact = ((type & STATUS_TYPE_COMPACT) != 0);
    } else {
        // 刘海屏且勾选指标 >= 4 项时默认自动启用紧凑双行布局，避免被系统刘海区域裁剪
        isCompact = ([MachineModel isLiquidScreen] && totalVisibleItems >= 4);
    }

    NSMutableArray* containerArray = [[NSMutableArray alloc] init];
    NSMutableArray* containerSize = [[NSMutableArray alloc] init];
    self.statusNum = 0;
    NSSize size;
    BOOL showOne = NO;

    if (type & STATUS_TYPE_LOGO) {
        NSView* containerLogo = [self getLogoContainerView:&size];
        [containerArray addObject:containerLogo];
        [containerSize addObject:[NSValue valueWithSize:size]];
        showOne = YES;
    }

    if (isCompact && scalarCount >= 2) {
        int sIdx = 0;
        while (sIdx + 1 < scalarCount) {
            NSView *pairView = [self getCompactPairContainerTopFlag:enabledScalars[sIdx]
                                                         bottomFlag:enabledScalars[sIdx + 1]
                                                               size:&size];
            [containerArray addObject:pairView];
            [containerSize addObject:[NSValue valueWithSize:size]];
            showOne = YES;
            sIdx += 2;
        }
        if (sIdx < scalarCount) {
            NSView *oddView = [self _singleMetricViewForFlag:enabledScalars[sIdx] size:&size];
            [containerArray addObject:oddView];
            [containerSize addObject:[NSValue valueWithSize:size]];
            showOne = YES;
        }
    } else {
        int sIdx;
        for (sIdx = 0; sIdx < scalarCount; sIdx++) {
            NSView *metricView = [self _singleMetricViewForFlag:enabledScalars[sIdx] size:&size];
            [containerArray addObject:metricView];
            [containerSize addObject:[NSValue valueWithSize:size]];
            showOne = YES;
        }
    }

    if (type & STATUS_TYPE_NET) {
        NSView* containerNet = [self getNetContainerView:&size];
        [containerArray addObject:containerNet];
        [containerSize addObject:[NSValue valueWithSize:size]];
        showOne = YES;
    }

    self.statusNum = totalVisibleItems;
    if (!showOne) {
        NSView* containerLogo = [self getLogoContainerView:&size];
        [containerArray addObject:containerLogo];
        [containerSize addObject:[NSValue valueWithSize:size]];
    }

    CGFloat dividerPad = isCompact ? 2.5 : 3.0;
    int i;
    for (i = 0; i < (int)containerArray.count; i++)
    {
        NSView* container  = [containerArray objectAtIndex:i];
        NSNumber* width = [NSNumber numberWithFloat:[[containerSize objectAtIndex:i] sizeValue].width];
        NSNumber* height = [NSNumber numberWithFloat:[[containerSize objectAtIndex:i] sizeValue].height];
        
        if (i == 0)
        {
            [self addSubview:container];
            [container mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerY.equalTo(self.mas_centerY);
                if (containerArray.count == 1)
                {
                    make.left.equalTo(self.mas_left).offset(2);
                    make.right.equalTo(self.mas_right).offset(-2);
                }
                else
                {
                    make.left.equalTo(self.mas_left).offset(0);
                }
                make.height.equalTo(height);
                make.width.equalTo(width);
            }];
        }
        else if (i == (int)containerArray.count - 1)
        {
            NSView* containerPre = [containerArray objectAtIndex:i-1];
            NSImageView *dividerIcon = [self getDividerImageView];
            [self addSubview:dividerIcon];
            [dividerIcon mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.equalTo(containerPre.mas_right).offset(dividerPad);
                make.centerY.equalTo(self.mas_centerY);
                make.width.equalTo(@1);
                make.height.equalTo(@16);
            }];
            
            [self addSubview:container];
            [container mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerY.equalTo(self.mas_centerY);
                make.left.equalTo(dividerIcon.mas_right).offset(dividerPad);
                make.right.equalTo(self.mas_right);
                make.height.equalTo(height);
                make.width.mas_equalTo(width.intValue + 2);
            }];
        }
        else
        {
            NSView* containerPre = [containerArray objectAtIndex:i-1];
            NSImageView *dividerIcon = [self getDividerImageView];
            [self addSubview:dividerIcon];

            [dividerIcon mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.equalTo(containerPre.mas_right).offset(dividerPad);
                make.centerY.equalTo(self.mas_centerY);
                make.width.equalTo(@1);
                make.height.equalTo(@16);
            }];
            
            [self addSubview:container];
            [container mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerY.equalTo(self.mas_centerY);
                make.left.equalTo(dividerIcon.mas_right).offset(dividerPad);
                make.height.equalTo(height);
                make.width.equalTo(width);
            }];
        }
    }
}

- (NSImageView *)getDividerImageView {
    NSImageView *imageView = [[NSImageView alloc] init];
    imageView.image = [NSImage imageNamed:@"status_divider"];
    [imageView.image setTemplate:YES];
    return imageView;
}

-(void)onDarkModeChange
{
    if ([LMCommonHelper isMacOS11]) {
        return;
    }
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain];
    id style = [dict objectForKey:@"AppleInterfaceStyle"];
    mDarkModeOn = ( style && [style isKindOfClass:[NSString class]] && NSOrderedSame == [style caseInsensitiveCompare:@"dark"] );
    
    NSLog(@"%s,mDarkModeOn=%d", __PRETTY_FUNCTION__, mDarkModeOn);
    
    // 使用统一的颜色更新方法
    [self updateAllTextColors];
}

@end
