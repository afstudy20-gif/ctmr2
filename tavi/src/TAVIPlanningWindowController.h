#import <Cocoa/Cocoa.h>

@class ViewerController;

NS_ASSUME_NONNULL_BEGIN

@interface TAVIPlanningWindowController : NSWindowController

@property (nonatomic, copy, nullable) void (^onWindowClose)(void);

- (instancetype)initWithViewer:(ViewerController *)viewer;
- (void)presentWindow;

@end

NS_ASSUME_NONNULL_END
