#import "TAVIProjectionPreviewView.h"

#import "TAVIMeasurementSession.h"

static NSArray<NSValue *> *TAVIEllipseWorldPoints(TAVIGeometryResult *geometry, NSUInteger count) {
    if (geometry == nil || count < 8 || TAVIVector3DIsZero(geometry.majorAxisDirection) || TAVIVector3DIsZero(geometry.minorAxisDirection)) {
        return @[];
    }

    double semiMajor = geometry.maximumDiameterMm * 0.5;
    double semiMinor = geometry.minimumDiameterMm * 0.5;
    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger idx = 0; idx < count; idx++) {
        double theta = ((double)idx / (double)count) * M_PI * 2.0;
        TAVIVector3D point = geometry.centroid;
        point = TAVIVector3DAdd(point, TAVIVector3DScale(geometry.majorAxisDirection, cos(theta) * semiMajor));
        point = TAVIVector3DAdd(point, TAVIVector3DScale(geometry.minorAxisDirection, sin(theta) * semiMinor));
        [points addObject:TAVIValueWithVector3D(point)];
    }
    return points;
}

static NSArray<NSValue *> *TAVICircleWorldPoints(TAVIGeometryResult *geometry, double diameterMm, NSUInteger count) {
    if (geometry == nil || diameterMm <= 0.0 || count < 8 || TAVIVector3DIsZero(geometry.majorAxisDirection) || TAVIVector3DIsZero(geometry.minorAxisDirection)) {
        return @[];
    }

    double radius = diameterMm * 0.5;
    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger idx = 0; idx < count; idx++) {
        double theta = ((double)idx / (double)count) * M_PI * 2.0;
        TAVIVector3D point = geometry.centroid;
        point = TAVIVector3DAdd(point, TAVIVector3DScale(geometry.majorAxisDirection, cos(theta) * radius));
        point = TAVIVector3DAdd(point, TAVIVector3DScale(geometry.minorAxisDirection, sin(theta) * radius));
        [points addObject:TAVIValueWithVector3D(point)];
    }
    return points;
}

static void TAVIExpandBoundsWithProjectedPoints(NSRect *bounds, NSArray<NSValue *> *projectedPoints) {
    for (NSValue *value in projectedPoints) {
        TAVIPoint2D point = TAVIPoint2DFromValue(value);
        if (NSIsEmptyRect(*bounds)) {
            *bounds = NSMakeRect(point.x, point.y, 0.0, 0.0);
        } else {
            *bounds = NSUnionRect(*bounds, NSMakeRect(point.x, point.y, 0.0, 0.0));
        }
    }
}

static NSPoint TAVIConvertProjectedPointToView(TAVIPoint2D point, NSRect dataBounds, NSRect drawingRect, CGFloat scale) {
    double centeredX = point.x - NSMidX(dataBounds);
    double centeredY = point.y - NSMidY(dataBounds);
    return NSMakePoint(NSMidX(drawingRect) + centeredX * scale, NSMidY(drawingRect) - centeredY * scale);
}

static void TAVIDrawProjectedPath(NSArray<NSValue *> *projectedPoints,
                                  NSRect dataBounds,
                                  NSRect drawingRect,
                                  CGFloat scale,
                                  NSColor *strokeColor,
                                  CGFloat lineWidth,
                                  NSArray<NSNumber *> *dashPattern) {
    if (projectedPoints.count < 2) {
        return;
    }

    NSBezierPath *path = [NSBezierPath bezierPath];
    TAVIPoint2D firstPoint2D = TAVIPoint2DFromValue(projectedPoints.firstObject);
    [path moveToPoint:TAVIConvertProjectedPointToView(firstPoint2D, dataBounds, drawingRect, scale)];
    for (NSUInteger idx = 1; idx < projectedPoints.count; idx++) {
        TAVIPoint2D point2D = TAVIPoint2DFromValue(projectedPoints[idx]);
        [path lineToPoint:TAVIConvertProjectedPointToView(point2D, dataBounds, drawingRect, scale)];
    }
    [path closePath];
    path.lineWidth = lineWidth;
    if (dashPattern.count > 0) {
        CGFloat pattern[dashPattern.count];
        for (NSUInteger idx = 0; idx < dashPattern.count; idx++) {
            pattern[idx] = dashPattern[idx].doubleValue;
        }
        [path setLineDash:pattern count:dashPattern.count phase:0.0];
    }
    [strokeColor setStroke];
    [path stroke];
}

static void TAVIDrawProjectedMarker(TAVIPoint2D point,
                                    NSString *label,
                                    NSColor *fillColor,
                                    NSRect dataBounds,
                                    NSRect drawingRect,
                                    CGFloat scale) {
    NSPoint drawPoint = TAVIConvertProjectedPointToView(point, dataBounds, drawingRect, scale);
    NSRect markerRect = NSMakeRect(drawPoint.x - 4.0, drawPoint.y - 4.0, 8.0, 8.0);
    NSBezierPath *marker = [NSBezierPath bezierPathWithOvalInRect:markerRect];
    [fillColor setFill];
    [marker fill];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: fillColor
    };
    [label drawAtPoint:NSMakePoint(drawPoint.x + 6.0, drawPoint.y + 2.0) withAttributes:attributes];
}

@interface TAVIProjectionPreviewView ()

@property (nonatomic, strong, nullable) TAVIMeasurementSession *session;

@end

@implementation TAVIProjectionPreviewView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        self.wantsLayer = YES;
    }
    return self;
}

- (void)refreshWithSession:(TAVIMeasurementSession *)session {
    self.session = session;
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor colorWithSRGBRed:0.97 green:0.98 blue:0.99 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.0, 1.0) xRadius:10.0 yRadius:10.0];
    border.lineWidth = 1.0;
    [[NSColor colorWithWhite:0.86 alpha:1.0] setStroke];
    [border stroke];

    NSDictionary<NSAttributedStringKey, id> *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.15 alpha:1.0]
    };
    NSDictionary<NSAttributedStringKey, id> *captionAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.35 alpha:1.0]
    };

    [@"Projection Preview" drawAtPoint:NSMakePoint(14.0, NSMaxY(self.bounds) - 22.0) withAttributes:titleAttributes];

    if (self.session == nil || self.session.annulusSnapshot == nil) {
        [@"Capture annulus to render the lightweight angio-style preview." drawAtPoint:NSMakePoint(14.0, NSMidY(self.bounds)) withAttributes:captionAttributes];
        return;
    }

    TAVIGeometryResult *activeAnnulus = [self.session activeAnnulusGeometry] ?: self.session.annulusGeometry;
    TAVIVector3D planeOrigin = activeAnnulus ? activeAnnulus.centroid : self.session.annulusGeometry.centroid;
    TAVIVector3D planeNormal = self.session.projectionConfirmation ? self.session.projectionConfirmation.confirmationNormal : activeAnnulus.planeNormal;

    NSArray<NSValue *> *annulusProjected = [TAVIGeometry projectWorldPoints:self.session.annulusSnapshot.worldPoints
                                                                 planeOrigin:planeOrigin
                                                                 planeNormal:planeNormal];
    NSArray<NSValue *> *assistedProjected = self.session.assistedAnnulusGeometry
        ? [TAVIGeometry projectWorldPoints:TAVIEllipseWorldPoints(self.session.assistedAnnulusGeometry, 80)
                               planeOrigin:planeOrigin
                               planeNormal:planeNormal]
        : @[];
    NSArray<NSValue *> *sinusProjected = self.session.sinusSnapshot
        ? [TAVIGeometry projectWorldPoints:self.session.sinusSnapshot.worldPoints planeOrigin:planeOrigin planeNormal:planeNormal]
        : @[];
    NSArray<NSValue *> *lvotProjected = self.session.lvotSnapshot
        ? [TAVIGeometry projectWorldPoints:self.session.lvotSnapshot.worldPoints planeOrigin:planeOrigin planeNormal:planeNormal]
        : @[];
    NSArray<NSValue *> *stjProjected = self.session.stjSnapshot
        ? [TAVIGeometry projectWorldPoints:self.session.stjSnapshot.worldPoints planeOrigin:planeOrigin planeNormal:planeNormal]
        : @[];
    NSArray<NSValue *> *ascendingProjected = self.session.ascendingAortaSnapshot
        ? [TAVIGeometry projectWorldPoints:self.session.ascendingAortaSnapshot.worldPoints planeOrigin:planeOrigin planeNormal:planeNormal]
        : @[];
    NSArray<NSValue *> *virtualValveProjected = self.session.virtualValveDiameterMm > 0.0
        ? [TAVIGeometry projectWorldPoints:TAVICircleWorldPoints(activeAnnulus, self.session.virtualValveDiameterMm, 80)
                               planeOrigin:planeOrigin
                               planeNormal:planeNormal]
        : @[];

    NSMutableArray<NSValue *> *pointMarkers = [NSMutableArray array];
    NSMutableArray<NSString *> *pointLabels = [NSMutableArray array];
    if (self.session.leftOstiumSnapshot != nil) {
        [pointMarkers addObject:TAVIValueWithPoint2D([TAVIGeometry projectWorldPoint:self.session.leftOstiumSnapshot.worldPoint
                                                                          planeOrigin:planeOrigin
                                                                          planeNormal:planeNormal])];
        [pointLabels addObject:@"L"];
    }
    if (self.session.rightOstiumSnapshot != nil) {
        [pointMarkers addObject:TAVIValueWithPoint2D([TAVIGeometry projectWorldPoint:self.session.rightOstiumSnapshot.worldPoint
                                                                          planeOrigin:planeOrigin
                                                                          planeNormal:planeNormal])];
        [pointLabels addObject:@"R"];
    }

    NSMutableArray<NSValue *> *sinusPointMarkers = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < self.session.sinusPointSnapshots.count; idx++) {
        TAVIPointSnapshot *snapshot = self.session.sinusPointSnapshots[idx];
        [sinusPointMarkers addObject:TAVIValueWithPoint2D([TAVIGeometry projectWorldPoint:snapshot.worldPoint
                                                                               planeOrigin:planeOrigin
                                                                               planeNormal:planeNormal])];
    }

    NSMutableArray<NSValue *> *membranousSeptumMarkers = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < self.session.membranousSeptumPointSnapshots.count; idx++) {
        TAVIPointSnapshot *snapshot = self.session.membranousSeptumPointSnapshots[idx];
        [membranousSeptumMarkers addObject:TAVIValueWithPoint2D([TAVIGeometry projectWorldPoint:snapshot.worldPoint
                                                                                      planeOrigin:planeOrigin
                                                                                      planeNormal:planeNormal])];
    }

    NSRect dataBounds = NSZeroRect;
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, annulusProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, assistedProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, sinusProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, lvotProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, stjProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, ascendingProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, virtualValveProjected);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, pointMarkers);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, sinusPointMarkers);
    TAVIExpandBoundsWithProjectedPoints(&dataBounds, membranousSeptumMarkers);

    if (NSIsEmptyRect(dataBounds)) {
        dataBounds = NSMakeRect(-10.0, -10.0, 20.0, 20.0);
    }
    if (dataBounds.size.width < 1.0) {
        dataBounds.size.width = 1.0;
    }
    if (dataBounds.size.height < 1.0) {
        dataBounds.size.height = 1.0;
    }

    NSRect drawingRect = NSInsetRect(self.bounds, 16.0, 18.0);
    drawingRect.size.height -= 36.0;
    CGFloat scale = MIN(drawingRect.size.width / MAX(dataBounds.size.width, 1.0),
                        drawingRect.size.height / MAX(dataBounds.size.height, 1.0)) * 0.85;

    NSBezierPath *crosshair = [NSBezierPath bezierPath];
    [crosshair moveToPoint:NSMakePoint(NSMidX(drawingRect), NSMinY(drawingRect))];
    [crosshair lineToPoint:NSMakePoint(NSMidX(drawingRect), NSMaxY(drawingRect))];
    [crosshair moveToPoint:NSMakePoint(NSMinX(drawingRect), NSMidY(drawingRect))];
    [crosshair lineToPoint:NSMakePoint(NSMaxX(drawingRect), NSMidY(drawingRect))];
    CGFloat dashes[2] = {4.0, 4.0};
    [crosshair setLineDash:dashes count:2 phase:0.0];
    crosshair.lineWidth = 1.0;
    [[NSColor colorWithWhite:0.88 alpha:1.0] setStroke];
    [crosshair stroke];

    TAVIDrawProjectedPath(ascendingProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.58 green:0.69 blue:0.84 alpha:1.0], 1.6, @[@4.0, @3.0]);
    TAVIDrawProjectedPath(stjProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.42 green:0.62 blue:0.78 alpha:1.0], 1.8, @[@5.0, @3.0]);
    TAVIDrawProjectedPath(sinusProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.16 green:0.55 blue:0.70 alpha:1.0], 2.0, @[]);
    TAVIDrawProjectedPath(lvotProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.35 green:0.47 blue:0.74 alpha:1.0], 1.8, @[@6.0, @3.0]);
    TAVIDrawProjectedPath(annulusProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.82 green:0.28 blue:0.20 alpha:1.0], 2.4, @[]);
    TAVIDrawProjectedPath(assistedProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.95 green:0.62 blue:0.18 alpha:1.0], 2.0, @[@7.0, @4.0]);
    TAVIDrawProjectedPath(virtualValveProjected, dataBounds, drawingRect, scale, [NSColor colorWithSRGBRed:0.18 green:0.25 blue:0.35 alpha:1.0], 1.8, @[@2.0, @3.0]);

    for (NSUInteger idx = 0; idx < pointMarkers.count; idx++) {
        TAVIDrawProjectedMarker(TAVIPoint2DFromValue(pointMarkers[idx]),
                                pointLabels[idx],
                                [NSColor colorWithSRGBRed:0.12 green:0.37 blue:0.67 alpha:1.0],
                                dataBounds,
                                drawingRect,
                                scale);
    }

    for (NSUInteger idx = 0; idx < sinusPointMarkers.count; idx++) {
        TAVIPoint2D point = TAVIPoint2DFromValue(sinusPointMarkers[idx]);
        NSPoint drawPoint = TAVIConvertProjectedPointToView(point, dataBounds, drawingRect, scale);
        NSBezierPath *diamond = [NSBezierPath bezierPath];
        [diamond moveToPoint:NSMakePoint(drawPoint.x, drawPoint.y + 5.0)];
        [diamond lineToPoint:NSMakePoint(drawPoint.x + 5.0, drawPoint.y)];
        [diamond lineToPoint:NSMakePoint(drawPoint.x, drawPoint.y - 5.0)];
        [diamond lineToPoint:NSMakePoint(drawPoint.x - 5.0, drawPoint.y)];
        [diamond closePath];
        [[NSColor colorWithSRGBRed:0.35 green:0.52 blue:0.16 alpha:1.0] setFill];
        [diamond fill];
    }

    if (membranousSeptumMarkers.count == 2) {
        TAVIPoint2D first = TAVIPoint2DFromValue(membranousSeptumMarkers[0]);
        TAVIPoint2D second = TAVIPoint2DFromValue(membranousSeptumMarkers[1]);
        NSBezierPath *septumPath = [NSBezierPath bezierPath];
        [septumPath moveToPoint:TAVIConvertProjectedPointToView(first, dataBounds, drawingRect, scale)];
        [septumPath lineToPoint:TAVIConvertProjectedPointToView(second, dataBounds, drawingRect, scale)];
        septumPath.lineWidth = 2.0;
        [[NSColor colorWithSRGBRed:0.58 green:0.36 blue:0.18 alpha:1.0] setStroke];
        [septumPath stroke];
    }

    NSString *caption = self.session.projectionConfirmation
        ? [NSString stringWithFormat:@"Preview uses sinus-point confirmation: %@. Virtual valve %.1f mm. Horizontal angle %.1f deg.",
                                      [self.session.projectionConfirmation summary],
                                      self.session.virtualValveDiameterMm,
                                      self.session.horizontalAortaAngleDegrees]
        : [NSString stringWithFormat:@"Preview uses annulus-derived advisory angle: %@. Virtual valve %.1f mm. Horizontal angle %.1f deg.",
                                      [[self.session preferredProjectionAngle] advisorySummary],
                                      self.session.virtualValveDiameterMm,
                                      self.session.horizontalAortaAngleDegrees];
    [caption drawInRect:NSMakeRect(14.0, 10.0, self.bounds.size.width - 28.0, 28.0) withAttributes:captionAttributes];
}

@end
