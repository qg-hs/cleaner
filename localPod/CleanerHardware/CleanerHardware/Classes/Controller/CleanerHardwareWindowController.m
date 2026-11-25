//
//  CleanerHardwareWindowController.m
//  CleanerHardware
//
//  
//  Copyright © 2019 Tencent. All rights reserved.
//

#import "CleanerHardwareWindowController.h"
#import "CleanerHardwareViewController.h"

@interface CleanerHardwareWindowController ()<NSWindowDelegate>

@property (nonatomic, strong) CleanerHardwareViewController *hardViewController;

@end

@implementation CleanerHardwareWindowController

- (id)init
{
    self = [super initWithWindowNibName:NSStringFromClass(self.class)];
    
    return self;
}

-(void)awakeFromNib{
    [super awakeFromNib];
    [self.window setStyleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskTitled | NSFullSizeContentViewWindowMask];
    self.window.titlebarAppearsTransparent = YES;
    self.window.movableByWindowBackground = YES;
    self.window.delegate = self;
    [self.window setBackgroundColor:[NSColor whiteColor]];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    self.hardViewController = [[CleanerHardwareViewController alloc] init];
    [self.window.contentView addSubview:self.hardViewController.view];
}

-(void)windowWillClose:(NSNotification *)notification{
    [self.hardViewController stopTimer];
    [self.delegate windowWillDismiss:[self className]];
}

@end
