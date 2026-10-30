//
//  LMModernToolBaseWindowController.h
//  Lemon
//

#import <Cocoa/Cocoa.h>
#import <QMUICommon/QMBaseWindowController.h>
#import <QMUICommon/LMCheckboxButton.h>
#import <QMUICommon/LMRectangleButton.h>
#import <QMUICommon/LMBorderButton.h>
#import <QMUICommon/COSwitch.h>

NS_ASSUME_NONNULL_BEGIN

/// 根据当前应用语言设置返回简中或英文文案
NSString *LMToolLocalized(NSString *zhText, NSString *enText);

/// 字节数格式化为人类可读字符串（B / KB / MB / GB）
NSString *LMFormatByteCount(uint64_t bytes);

typedef NS_ENUM(NSInteger, LMToolPillTone) {
    LMToolPillToneMint = 0,    // #04D999 / alpha 0.14
    LMToolPillToneBlue = 1,    // #1A83F7 / alpha 0.13
    LMToolPillToneAmber = 2,   // #FF9A00 / alpha 0.14
    LMToolPillToneNeutral = 3, // #94979B / alpha 0.14
};

/// 原生 Lemon 圆角胶囊状态标签（20pt 高，cornerRadius = 10，对齐开机启动项管理样式）
@interface LMToolPillBadgeView : NSView
@property (nonatomic, strong, readonly) NSTextField *textLabel;
- (void)configureWithText:(NSString *)text tone:(LMToolPillTone)tone;
@end

/// 支持悬浮反馈的表格单元格协议
@protocol LMToolHoverCellProtocol <NSObject>
@optional
- (void)updateHoverState:(BOOL)isHovered;
@end

/// 全宽悬浮高亮行视图（复刻开机启动项管理 / 垃圾扫描列表悬浮态）
@interface LMToolHoverRowView : NSTableRowView
@property (nonatomic, assign, readonly) BOOL isRowHovered;
@end

/// 支持点击整行空白区域触发勾选、双击在访达中显示的轻量表格
@interface LMToolClickableTableView : NSTableView
@property (nonatomic, copy, nullable) void (^onRowBodyClicked)(NSInteger row);
@property (nonatomic, copy, nullable) void (^onRowDoubleClicked)(NSInteger row);
@end

/// 极简文字筛选栏（无灰色分段框，选中态底部 2pt 翠绿指示条，复刻大文件清理筛选栏）
@interface LMToolFilterBarView : NSView
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) void (^onSelectTab)(NSInteger index);
- (instancetype)initWithTitles:(NSArray<NSString *> *)titles;
@end

/// 扫描加载态（LMBigLoadingView）与空结果态统一覆盖层
@interface LMToolStatusOverlayView : NSView
- (void)showLoadingWithTitle:(NSString *)title;
- (void)showEmptyWithTitle:(NSString *)title;
- (void)dismissOverlay;
@end

@interface LMModernToolBaseWindowController : QMBaseWindowController <NSWindowDelegate>

@property (nonatomic, strong, readonly) NSView *rootContainerView;
@property (nonatomic, strong, readonly) NSView *headerBarView;
@property (nonatomic, strong, readonly) NSTextField *headerTitleLabel;
@property (nonatomic, strong, readonly) NSView *headerRightContainer;
@property (nonatomic, strong, readonly) NSView *headerDividerView;
@property (nonatomic, strong, readonly) NSView *bodyContentView;

- (instancetype)initWithToolTitle:(NSString *)title
                       windowSize:(NSSize)windowSize;

/// 兼容旧签名（自动忽略冗余副标题与左侧大图标，保持原生极简居中标题栏）
- (instancetype)initWithToolTitle:(NSString *)title
                         subtitle:(nullable NSString *)subtitle
                         iconName:(nullable NSString *)iconName
                       windowSize:(NSSize)windowSize;

/// 子类重写以构建界面
- (void)setupToolContentView;

/// 子类重写以在关闭窗口时终止异步任务
- (void)toolWindowWillClose;

#pragma mark - 原生 Lemon UI 控件工厂

+ (NSTextField *)labelWithText:(NSString *)text
                          font:(NSFont *)font
                         color:(NSColor *)color;

+ (LMCheckboxButton *)checkboxWithMixed:(BOOL)allowsMixed
                                 target:(nullable id)target
                                 action:(nullable SEL)action;

+ (LMRectangleButton *)primaryButtonWithTitle:(NSString *)title
                                       target:(nullable id)target
                                       action:(nullable SEL)action;

+ (LMBorderButton *)ghostButtonWithTitle:(NSString *)title
                                fontSize:(int)fontSize
                                  target:(nullable id)target
                                  action:(nullable SEL)action;

+ (NSButton *)finderHoverButtonWithTarget:(nullable id)target
                                   action:(nullable SEL)action;

+ (NSSearchField *)searchFieldWithPlaceholder:(NSString *)placeholder
                                       target:(nullable id)target
                                       action:(nullable SEL)action;

+ (NSButton *)sortableColumnButtonWithTitle:(NSString *)title
                                  alignment:(NSTextAlignment)alignment
                                     target:(nullable id)target
                                     action:(nullable SEL)action;

+ (void)styleSortableColumnButton:(NSButton *)button
                            title:(NSString *)title
                           active:(BOOL)active
                        ascending:(BOOL)ascending
                        alignment:(NSTextAlignment)alignment;

+ (NSScrollView *)cleanTableScrollViewWithTable:(LMToolClickableTableView * _Nullable * _Nonnull)outTable
                                       delegate:(id<NSTableViewDelegate, NSTableViewDataSource>)delegate
                                      rowHeight:(CGFloat)rowHeight;

+ (NSAttributedString *)summaryAttributedWithPrefix:(NSString *)prefix
                                          highlight:(NSString *)highlight
                                             suffix:(nullable NSString *)suffix
                                     highlightColor:(NSColor *)highlightColor;

@end

NS_ASSUME_NONNULL_END
