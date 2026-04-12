#import <Cocoa/Cocoa.h>

#import "PluginFilter.h"
#import "TAVIPlanningWindowController.h"

@class ViewerController;

@interface TAVIWindowRegistry : NSObject
@property (nonatomic, strong) NSMapTable<ViewerController *, TAVIPlanningWindowController *> *windowsByViewer;
+ (instancetype)sharedRegistry;
- (void)presentWindowForViewer:(ViewerController *)viewer;
- (void)closeAllWindows;
@end

@implementation TAVIWindowRegistry

+ (instancetype)sharedRegistry {
    static TAVIWindowRegistry *registry = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [[TAVIWindowRegistry alloc] init];
        registry.windowsByViewer = [NSMapTable weakToStrongObjectsMapTable];
    });
    return registry;
}

- (void)presentWindowForViewer:(ViewerController *)viewer {
    if (viewer == nil) {
        return;
    }

    TAVIPlanningWindowController *controller = [self.windowsByViewer objectForKey:viewer];
    if (controller == nil) {
        controller = [[TAVIPlanningWindowController alloc] initWithViewer:viewer];
        __weak typeof(self) weakSelf = self;
        __weak ViewerController *weakViewer = viewer;
        controller.onWindowClose = ^{
            [weakSelf.windowsByViewer removeObjectForKey:weakViewer];
        };
        [self.windowsByViewer setObject:controller forKey:viewer];
    }
    [controller presentWindow];
}

- (void)closeAllWindows {
    for (TAVIPlanningWindowController *controller in self.windowsByViewer.objectEnumerator) {
        [controller close];
    }
    [self.windowsByViewer removeAllObjects];
}

@end

@interface TAVIMeasurementPlugin : PluginFilter
@end

@implementation TAVIMeasurementPlugin

- (void)initPlugin {
    [TAVIWindowRegistry sharedRegistry];
}

- (void)willUnload {
    [[TAVIWindowRegistry sharedRegistry] closeAllWindows];
}

- (long)filterImage:(NSString *)menuName {
    if (viewerController == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"TAVI Planning";
        alert.informativeText = @"No active Horos viewer is available.";
        [alert runModal];
        return 0;
    }

    [[TAVIWindowRegistry sharedRegistry] presentWindowForViewer:viewerController];
    return 0;
}

- (BOOL)isCertifiedForMedicalImaging {
    return NO;
}

@end
