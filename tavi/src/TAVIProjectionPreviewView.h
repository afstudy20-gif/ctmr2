#import <Cocoa/Cocoa.h>

@class TAVIMeasurementSession;

NS_ASSUME_NONNULL_BEGIN

@interface TAVIProjectionPreviewView : NSView

- (void)refreshWithSession:(nullable TAVIMeasurementSession *)session;

@end

NS_ASSUME_NONNULL_END
