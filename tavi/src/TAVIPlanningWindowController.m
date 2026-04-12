#import "TAVIPlanningWindowController.h"

#import "TAVIMeasurementSession.h"
#import "TAVIProjectionPreviewView.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "DCMView.h"
#import "DCMPix.h"
#import "DicomImage.h"
#import "DicomSeries.h"
#import "DicomStudy.h"
#import "ROI.h"
#import "ViewerController.h"

static const NSInteger kTAVISampledOvalPoints = 64;

static NSTextField *TAVIMakeReadOnlyField(NSRect frame, NSFont *font) {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.editable = NO;
    field.selectable = YES;
    field.bordered = NO;
    field.drawsBackground = NO;
    field.font = font;
    field.lineBreakMode = NSLineBreakByWordWrapping;
    NSTextFieldCell *cell = (NSTextFieldCell *)field.cell;
    cell.wraps = YES;
    cell.usesSingleLineMode = NO;
    cell.scrollable = NO;
    return field;
}

static NSButton *TAVIMakeButton(NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bezelStyle = NSBezelStyleRounded;
    button.title = title;
    button.target = target;
    button.action = action;
    return button;
}

static NSString *TAVIDateString(NSDate *date) {
    if (date == nil) {
        return @"";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;
    return [formatter stringFromDate:date];
}

static NSString *TAVISanitizeFileComponent(NSString *value) {
    NSString *safe = value.length > 0 ? value : @"TAVI";
    NSCharacterSet *disallowed = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSArray<NSString *> *parts = [safe componentsSeparatedByCharactersInSet:disallowed];
    NSString *joined = [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@"-"];
    return joined.length > 0 ? joined : @"TAVI";
}

static NSString *TAVIFormatGeometrySummary(TAVIGeometryResult *geometry) {
    if (geometry == nil) {
        return @"Not captured";
    }
    return [NSString stringWithFormat:@"Perimeter %.1f mm, Area %.1f mm2, Min/Max %.1f / %.1f mm, EqD %.1f mm",
                                      geometry.perimeterMm,
                                      geometry.areaMm2,
                                      geometry.minimumDiameterMm,
                                      geometry.maximumDiameterMm,
                                      geometry.equivalentDiameterMm];
}

static NSString *TAVIFormatCalciumSummary(TAVICalciumResult *calcium) {
    if (calcium == nil) {
        return @"Not captured";
    }
    return [NSString stringWithFormat:@"HU %.0f -> %.1f mm2 hyperdense (%.1f%%)",
                                      calcium.thresholdHU,
                                      calcium.hyperdenseAreaMm2,
                                      calcium.fractionAboveThreshold * 100.0];
}

static TAVIVector3D TAVIPlaneNormalForPix(DCMPix *pix) {
    double orientation[9] = {0.0};
    [pix orientationDouble:orientation];
    TAVIVector3D row = TAVIVector3DMake(orientation[0], orientation[1], orientation[2]);
    TAVIVector3D column = TAVIVector3DMake(orientation[3], orientation[4], orientation[5]);
    TAVIVector3D normal = TAVIVector3DCross(row, column);
    if (TAVIVector3DIsZero(normal)) {
        normal = TAVIVector3DMake(orientation[6], orientation[7], orientation[8]);
    }
    return TAVIVector3DNormalize(normal);
}

static TAVIVector3D TAVIWorldPointFromPixelPoint(NSPoint pixelPoint, DCMPix *pix) {
    double orientation[9] = {0.0};
    double origin[3] = {0.0};
    [pix orientationDouble:orientation];
    [pix originDouble:origin];

    TAVIVector3D row = TAVIVector3DNormalize(TAVIVector3DMake(orientation[0], orientation[1], orientation[2]));
    TAVIVector3D column = TAVIVector3DNormalize(TAVIVector3DMake(orientation[3], orientation[4], orientation[5]));
    TAVIVector3D base = TAVIVector3DMake(origin[0], origin[1], origin[2]);

    TAVIVector3D world = TAVIVector3DAdd(base, TAVIVector3DScale(row, pixelPoint.x * pix.pixelSpacingX));
    world = TAVIVector3DAdd(world, TAVIVector3DScale(column, pixelPoint.y * pix.pixelSpacingY));
    return world;
}

static NSArray<NSValue *> *TAVIPixelPointsForContourROI(ROI *roi) {
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    if (roi.type == tOval) {
        NSRect rect = roi.rect;
        double cx = NSMidX(rect);
        double cy = NSMidY(rect);
        double rx = rect.size.width / 2.0;
        double ry = rect.size.height / 2.0;
        for (NSInteger idx = 0; idx < kTAVISampledOvalPoints; idx++) {
            double angle = ((double)idx / (double)kTAVISampledOvalPoints) * M_PI * 2.0;
            NSPoint point = NSMakePoint(cx + (cos(angle) * rx), cy + (sin(angle) * ry));
            [points addObject:[NSValue valueWithPoint:point]];
        }
        return points;
    }

    NSUInteger pointCount = roi.points.count;
    for (NSUInteger idx = 0; idx < pointCount; idx++) {
        [points addObject:[NSValue valueWithPoint:[roi pointAtIndex:idx]]];
    }

    if (points.count == 0 && !NSEqualRects(roi.rect, NSZeroRect)) {
        NSRect rect = roi.rect;
        [points addObject:[NSValue valueWithPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))]];
        [points addObject:[NSValue valueWithPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))]];
        [points addObject:[NSValue valueWithPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))]];
        [points addObject:[NSValue valueWithPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))]];
    }

    return points;
}

static NSPoint TAVIPixelPointForPointROI(ROI *roi) {
    if (roi.points.count > 0) {
        return [roi pointAtIndex:0];
    }
    NSRect rect = roi.rect;
    return NSMakePoint(NSMidX(rect), NSMidY(rect));
}

static BOOL TAVIPointInPolygon(NSPoint point, NSArray<NSValue *> *polygon) {
    BOOL inside = NO;
    NSUInteger count = polygon.count;
    if (count < 3) {
        return NO;
    }

    for (NSUInteger i = 0, j = count - 1; i < count; j = i++) {
        NSPoint pi = polygon[i].pointValue;
        NSPoint pj = polygon[j].pointValue;
        BOOL intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < ((pj.x - pi.x) * (point.y - pi.y) / MAX((pj.y - pi.y), DBL_EPSILON)) + pi.x);
        if (intersects) {
            inside = !inside;
        }
    }
    return inside;
}

static BOOL TAVIPointInEllipse(NSPoint point, NSRect rect) {
    double rx = rect.size.width / 2.0;
    double ry = rect.size.height / 2.0;
    if (rx <= DBL_EPSILON || ry <= DBL_EPSILON) {
        return NO;
    }
    double dx = (point.x - NSMidX(rect)) / rx;
    double dy = (point.y - NSMidY(rect)) / ry;
    return ((dx * dx) + (dy * dy)) <= 1.0;
}

static NSData *TAVIPixelValuesInsideROI(ROI *roi, NSArray<NSValue *> *pixelPoints, DCMPix *pix, double *pixelAreaMm2) {
    if (pixelAreaMm2 != NULL) {
        *pixelAreaMm2 = pix.pixelSpacingX * pix.pixelSpacingY;
    }

    float *image = pix.fImage;
    if (image == NULL || pixelPoints.count < 3) {
        return [NSData data];
    }

    long width = pix.pwidth;
    long height = pix.pheight;
    if (width <= 0 || height <= 0) {
        return [NSData data];
    }

    double minX = DBL_MAX;
    double minY = DBL_MAX;
    double maxX = -DBL_MAX;
    double maxY = -DBL_MAX;
    for (NSValue *value in pixelPoints) {
        NSPoint point = value.pointValue;
        minX = MIN(minX, point.x);
        minY = MIN(minY, point.y);
        maxX = MAX(maxX, point.x);
        maxY = MAX(maxY, point.y);
    }

    NSInteger startX = MAX(0, (NSInteger)floor(minX));
    NSInteger startY = MAX(0, (NSInteger)floor(minY));
    NSInteger endX = MIN((NSInteger)width - 1, (NSInteger)ceil(maxX));
    NSInteger endY = MIN((NSInteger)height - 1, (NSInteger)ceil(maxY));

    NSMutableData *samples = [NSMutableData data];
    for (NSInteger y = startY; y <= endY; y++) {
        for (NSInteger x = startX; x <= endX; x++) {
            NSPoint samplePoint = NSMakePoint((double)x + 0.5, (double)y + 0.5);
            BOOL isInside = roi.type == tOval
                ? TAVIPointInEllipse(samplePoint, roi.rect)
                : TAVIPointInPolygon(samplePoint, pixelPoints);
            if (!isInside) {
                continue;
            }

            float value = image[(y * width) + x];
            [samples appendBytes:&value length:sizeof(float)];
        }
    }

    return samples;
}

static DicomImage *TAVIImageForViewerAndROI(ViewerController *viewer, ROI *roi) {
    NSMutableArray *files = [viewer fileList];
    if (files.count == 0) {
        return nil;
    }

    DCMView *imageView = [viewer imageView];
    NSInteger currentIndex = imageView != nil ? imageView.curImage : -1;
    if (currentIndex >= 0 && currentIndex < (NSInteger)files.count) {
        DicomImage *currentImage = files[(NSUInteger)currentIndex];
        if (roi.pix.imageObjectID == nil || [currentImage.objectID isEqual:roi.pix.imageObjectID]) {
            return currentImage;
        }
    }

    if (roi.pix.imageObjectID != nil) {
        for (DicomImage *image in files) {
            if ([image.objectID isEqual:roi.pix.imageObjectID]) {
                return image;
            }
        }
    }

    return files.firstObject;
}

static void TAVIPopulateMetadataFromImage(id snapshot, DicomImage *image) {
    DicomSeries *series = image.series;
    DicomStudy *study = series.study;
    [snapshot setSeriesUID:series.seriesDICOMUID ?: series.seriesInstanceUID ?: @""];
    [snapshot setSeriesDescription:series.seriesDescription ?: series.name ?: @""];
    [snapshot setStudyInstanceUID:study.studyInstanceUID ?: @""];
    [snapshot setPatientName:study.name ?: @""];
    [snapshot setPatientID:study.patientID ?: @""];
    [snapshot setPatientUID:study.patientUID ?: @""];
    [snapshot setPatientBirthDate:TAVIDateString(study.dateOfBirth)];
}

static TAVIContourSnapshot *TAVIMakeContourSnapshot(ROI *roi, ViewerController *viewer, NSString *label, NSError **error) {
    if (roi.pix == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"TAVIPlanning"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected ROI is not attached to a loaded image."}];
        }
        return nil;
    }

    NSArray<NSValue *> *pixelPoints = TAVIPixelPointsForContourROI(roi);
    if (pixelPoints.count < 3) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"TAVIPlanning"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected contour ROI does not contain enough points."}];
        }
        return nil;
    }

    NSMutableArray<NSValue *> *worldPoints = [NSMutableArray arrayWithCapacity:pixelPoints.count];
    for (NSValue *value in pixelPoints) {
        [worldPoints addObject:TAVIValueWithVector3D(TAVIWorldPointFromPixelPoint(value.pointValue, roi.pix))];
    }

    double pixelAreaMm2 = 0.0;
    NSData *pixelValues = TAVIPixelValuesInsideROI(roi, pixelPoints, roi.pix, &pixelAreaMm2);

    TAVIContourSnapshot *snapshot = [[TAVIContourSnapshot alloc] init];
    snapshot.label = label;
    snapshot.pixelPoints = pixelPoints;
    snapshot.worldPoints = worldPoints;
    snapshot.pixelValues = pixelValues;
    snapshot.pixelAreaMm2 = pixelAreaMm2;
    snapshot.roiType = roi.type;
    snapshot.sliceIndex = viewer.imageView.curImage;
    snapshot.planeNormal = TAVIPlaneNormalForPix(roi.pix);
    snapshot.planeOrigin = TAVIVector3DFromValue(worldPoints.firstObject);

    DicomImage *image = TAVIImageForViewerAndROI(viewer, roi);
    if (image != nil) {
        TAVIPopulateMetadataFromImage(snapshot, image);
    }
    return snapshot;
}

static TAVIPointSnapshot *TAVIMakePointSnapshot(ROI *roi, ViewerController *viewer, NSString *label, NSError **error) {
    if (roi.pix == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"TAVIPlanning"
                                         code:1010
                                     userInfo:@{NSLocalizedDescriptionKey: @"The selected point ROI is not attached to a loaded image."}];
        }
        return nil;
    }

    NSPoint pixelPoint = TAVIPixelPointForPointROI(roi);
    TAVIPointSnapshot *snapshot = [[TAVIPointSnapshot alloc] init];
    snapshot.label = label;
    snapshot.pixelPoint = pixelPoint;
    snapshot.sliceIndex = viewer.imageView.curImage;
    snapshot.roiType = roi.type;
    snapshot.worldPoint = TAVIWorldPointFromPixelPoint(pixelPoint, roi.pix);

    DicomImage *image = TAVIImageForViewerAndROI(viewer, roi);
    if (image != nil) {
        TAVIPopulateMetadataFromImage(snapshot, image);
    }
    return snapshot;
}

@interface TAVIPlanningWindowController () <NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate>

@property (nonatomic, weak) ViewerController *viewer;
@property (nonatomic, strong) TAVIMeasurementSession *session;

@property (nonatomic, strong) NSTextField *datasetStatusField;
@property (nonatomic, strong) NSTextField *workflowField;
@property (nonatomic, strong) NSTextField *captureStatusField;
@property (nonatomic, strong) NSTextField *annulusField;
@property (nonatomic, strong) NSTextField *assistedAnnulusField;
@property (nonatomic, strong) NSTextField *lvotField;
@property (nonatomic, strong) NSTextField *membranousSeptumField;
@property (nonatomic, strong) NSTextField *coronaryField;
@property (nonatomic, strong) NSTextField *sinusField;
@property (nonatomic, strong) NSTextField *stjField;
@property (nonatomic, strong) NSTextField *ascendingAortaField;
@property (nonatomic, strong) NSTextField *angleField;
@property (nonatomic, strong) NSTextField *confirmationField;
@property (nonatomic, strong) NSTextField *calciumField;
@property (nonatomic, strong) NSTextField *exportStatusField;
@property (nonatomic, strong) NSTextField *thresholdField;
@property (nonatomic, strong) NSTextField *virtualValveField;
@property (nonatomic, strong) NSPopUpButton *cuspPopup;
@property (nonatomic, strong) NSPopUpButton *annulusPopup;
@property (nonatomic, strong) NSButton *assistAnnulusButton;
@property (nonatomic, strong) NSTextView *notesTextView;
@property (nonatomic, strong) NSTextView *reportTextView;
@property (nonatomic, strong) TAVIProjectionPreviewView *previewView;

@end

@implementation TAVIPlanningWindowController

- (instancetype)initWithViewer:(ViewerController *)viewer {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1240, 960)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self != nil) {
        _viewer = viewer;
        _session = [[TAVIMeasurementSession alloc] init];
        [self buildWindow];
        [self refreshUIWithStatus:@"Ready to capture TAVI landmarks, assisted annulus fit, and projection preview inputs."];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(viewerWindowWillClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:viewer.window];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)presentWindow {
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildWindow {
    self.window.title = @"TAVI Planning";
    self.window.delegate = self;
    self.window.minSize = NSMakeSize(1180, 900);

    NSView *contentView = self.window.contentView;
    NSFont *bodyFont = [NSFont systemFontOfSize:12.0];
    NSFont *sectionFont = [NSFont boldSystemFontOfSize:13.0];

    NSView *leftPanel = [[NSView alloc] initWithFrame:NSMakeRect(20, 20, 540, 900)];
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(580, 20, 640, 900)];
    leftPanel.autoresizingMask = NSViewHeightSizable;
    rightPanel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:leftPanel];
    [contentView addSubview:rightPanel];

    NSBox *datasetBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 710, 540, 190)];
    datasetBox.title = @"Dataset Status";
    datasetBox.contentViewMargins = NSMakeSize(12, 12);
    [leftPanel addSubview:datasetBox];
    self.datasetStatusField = TAVIMakeReadOnlyField(NSMakeRect(10, 92, 508, 62), bodyFont);
    self.workflowField = TAVIMakeReadOnlyField(NSMakeRect(10, 10, 508, 78), [NSFont userFixedPitchFontOfSize:11.0]);
    [datasetBox.contentView addSubview:self.datasetStatusField];
    [datasetBox.contentView addSubview:self.workflowField];

    NSBox *captureBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 430, 540, 270)];
    captureBox.title = @"Landmark Capture";
    captureBox.contentViewMargins = NSMakeSize(12, 12);
    [leftPanel addSubview:captureBox];

    CGFloat buttonWidth = 242.0;
    CGFloat buttonHeight = 28.0;
    NSArray<NSArray<NSString *> *> *captureButtons = @[
        @[@"Capture Ascending Aorta ROI", NSStringFromSelector(@selector(captureAscendingAorta:)), @"10", @"190"],
        @[@"Capture STJ ROI", NSStringFromSelector(@selector(captureSTJ:)), @"268", @"190"],
        @[@"Capture Sinus ROI", NSStringFromSelector(@selector(captureSinus:)), @"10", @"152"],
        @[@"Capture LVOT ROI", NSStringFromSelector(@selector(captureLVOT:)), @"268", @"152"],
        @[@"Capture Annulus Contour", NSStringFromSelector(@selector(captureAnnulus:)), @"10", @"114"],
        @[@"Capture 3 Sinus Points", NSStringFromSelector(@selector(captureSinusPoints:)), @"268", @"114"],
        @[@"Capture Septum Points", NSStringFromSelector(@selector(captureMembranousSeptum:)), @"10", @"76"],
        @[@"Capture Left Ostium Point", NSStringFromSelector(@selector(captureLeftOstium:)), @"268", @"76"],
        @[@"Capture Right Ostium Point", NSStringFromSelector(@selector(captureRightOstium:)), @"10", @"38"]
    ];
    for (NSArray<NSString *> *item in captureButtons) {
        SEL action = NSSelectorFromString(item[1]);
        CGFloat x = item[2].doubleValue;
        CGFloat y = item[3].doubleValue;
        [captureBox.contentView addSubview:TAVIMakeButton(item[0], NSMakeRect(x, y, buttonWidth, buttonHeight), self, action)];
    }

    self.assistAnnulusButton = TAVIMakeButton(@"Use Assisted Annulus", NSMakeRect(268, 38, buttonWidth, buttonHeight), self, @selector(toggleAssistedAnnulus:));
    [captureBox.contentView addSubview:self.assistAnnulusButton];
    [captureBox.contentView addSubview:TAVIMakeButton(@"Recompute", NSMakeRect(10, 2, 100, 28), self, @selector(recompute:))];
    self.captureStatusField = TAVIMakeReadOnlyField(NSMakeRect(122, 0, 388, 32), bodyFont);
    [captureBox.contentView addSubview:self.captureStatusField];

    NSBox *measurementsBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 120, 540, 300)];
    measurementsBox.title = @"Root Measurements";
    measurementsBox.contentViewMargins = NSMakeSize(12, 12);
    [leftPanel addSubview:measurementsBox];

    NSArray<NSString *> *titles = @[
        @"Annulus",
        @"Assisted Annulus",
        @"LVOT",
        @"Membranous Septum",
        @"Coronary Heights",
        @"Sinus of Valsalva",
        @"Sinotubular Junction",
        @"Ascending Aorta"
    ];
    NSArray<NSTextField *> *fields = @[
        self.annulusField = TAVIMakeReadOnlyField(NSMakeRect(175, 236, 335, 30), bodyFont),
        self.assistedAnnulusField = TAVIMakeReadOnlyField(NSMakeRect(175, 204, 335, 30), bodyFont),
        self.lvotField = TAVIMakeReadOnlyField(NSMakeRect(175, 172, 335, 30), bodyFont),
        self.membranousSeptumField = TAVIMakeReadOnlyField(NSMakeRect(175, 140, 335, 24), bodyFont),
        self.coronaryField = TAVIMakeReadOnlyField(NSMakeRect(175, 108, 335, 24), bodyFont),
        self.sinusField = TAVIMakeReadOnlyField(NSMakeRect(175, 76, 335, 24), bodyFont),
        self.stjField = TAVIMakeReadOnlyField(NSMakeRect(175, 44, 335, 24), bodyFont),
        self.ascendingAortaField = TAVIMakeReadOnlyField(NSMakeRect(175, 12, 335, 24), bodyFont)
    ];
    for (NSUInteger idx = 0; idx < titles.count; idx++) {
        NSTextField *label = TAVIMakeReadOnlyField(NSMakeRect(10, 236 - ((CGFloat)idx * 32.0), 155, 22), sectionFont);
        label.stringValue = titles[idx];
        [measurementsBox.contentView addSubview:label];
        [measurementsBox.contentView addSubview:fields[idx]];
    }

    NSBox *angleBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 540, 110)];
    angleBox.title = @"Angle And Calcium";
    angleBox.contentViewMargins = NSMakeSize(12, 12);
    [leftPanel addSubview:angleBox];

    NSTextField *thresholdLabel = TAVIMakeReadOnlyField(NSMakeRect(10, 62, 140, 22), sectionFont);
    thresholdLabel.stringValue = @"Calcium Threshold (HU)";
    [angleBox.contentView addSubview:thresholdLabel];
    self.thresholdField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 58, 70, 24)];
    self.thresholdField.delegate = self;
    self.thresholdField.target = self;
    self.thresholdField.action = @selector(thresholdChanged:);
    self.thresholdField.stringValue = @"850";
    [angleBox.contentView addSubview:self.thresholdField];

    NSTextField *virtualValveLabel = TAVIMakeReadOnlyField(NSMakeRect(240, 62, 120, 22), sectionFont);
    virtualValveLabel.stringValue = @"Virtual Valve (mm)";
    [angleBox.contentView addSubview:virtualValveLabel];
    self.virtualValveField = [[NSTextField alloc] initWithFrame:NSMakeRect(365, 58, 70, 24)];
    self.virtualValveField.delegate = self;
    self.virtualValveField.target = self;
    self.virtualValveField.action = @selector(virtualValveChanged:);
    [angleBox.contentView addSubview:self.virtualValveField];

    NSTextField *cuspLabel = TAVIMakeReadOnlyField(NSMakeRect(10, 34, 95, 22), sectionFont);
    cuspLabel.stringValue = @"Cusp Grade";
    [angleBox.contentView addSubview:cuspLabel];
    self.cuspPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 30, 70, 24)];
    [self.cuspPopup addItemsWithTitles:@[@"0", @"1", @"2", @"3"]];
    self.cuspPopup.target = self;
    self.cuspPopup.action = @selector(calcificationChanged:);
    [angleBox.contentView addSubview:self.cuspPopup];

    NSTextField *annulusLabel = TAVIMakeReadOnlyField(NSMakeRect(240, 34, 110, 22), sectionFont);
    annulusLabel.stringValue = @"Annulus Grade";
    [angleBox.contentView addSubview:annulusLabel];
    self.annulusPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(365, 30, 70, 24)];
    [self.annulusPopup addItemsWithTitles:@[@"0", @"1", @"2", @"3"]];
    self.annulusPopup.target = self;
    self.annulusPopup.action = @selector(calcificationChanged:);
    [angleBox.contentView addSubview:self.annulusPopup];

    self.angleField = TAVIMakeReadOnlyField(NSMakeRect(10, 8, 520, 20), bodyFont);
    self.confirmationField = TAVIMakeReadOnlyField(NSMakeRect(440, 56, 90, 22), bodyFont);
    self.calciumField = TAVIMakeReadOnlyField(NSMakeRect(440, 28, 90, 22), bodyFont);
    [angleBox.contentView addSubview:self.angleField];
    [angleBox.contentView addSubview:self.confirmationField];
    [angleBox.contentView addSubview:self.calciumField];

    NSBox *previewBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 640, 640, 260)];
    previewBox.title = @"Projection Preview";
    previewBox.contentViewMargins = NSMakeSize(12, 12);
    [rightPanel addSubview:previewBox];
    self.previewView = [[TAVIProjectionPreviewView alloc] initWithFrame:NSMakeRect(10, 10, 610, 220)];
    self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [previewBox.contentView addSubview:self.previewView];

    NSBox *notesBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 490, 640, 140)];
    notesBox.title = @"Notes";
    notesBox.contentViewMargins = NSMakeSize(12, 12);
    [rightPanel addSubview:notesBox];
    NSScrollView *notesScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 610, 92)];
    notesScrollView.borderType = NSBezelBorder;
    notesScrollView.hasVerticalScroller = YES;
    self.notesTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 610, 92)];
    self.notesTextView.delegate = self;
    notesScrollView.documentView = self.notesTextView;
    [notesBox.contentView addSubview:notesScrollView];

    NSBox *reportBox = [[NSBox alloc] initWithFrame:NSMakeRect(0, 70, 640, 410)];
    reportBox.title = @"Report Preview";
    reportBox.contentViewMargins = NSMakeSize(12, 12);
    [rightPanel addSubview:reportBox];
    NSScrollView *reportScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 610, 370)];
    reportScrollView.borderType = NSBezelBorder;
    reportScrollView.hasVerticalScroller = YES;
    self.reportTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 610, 370)];
    self.reportTextView.editable = NO;
    self.reportTextView.font = [NSFont userFixedPitchFontOfSize:12.0];
    reportScrollView.documentView = self.reportTextView;
    [reportBox.contentView addSubview:reportScrollView];

    [rightPanel addSubview:TAVIMakeButton(@"Export CSV", NSMakeRect(0, 20, 120, 30), self, @selector(exportCSV:))];
    [rightPanel addSubview:TAVIMakeButton(@"Export Text", NSMakeRect(130, 20, 120, 30), self, @selector(exportText:))];
    self.exportStatusField = TAVIMakeReadOnlyField(NSMakeRect(265, 22, 360, 24), bodyFont);
    [rightPanel addSubview:self.exportStatusField];
}

- (void)viewerWindowWillClose:(NSNotification *)notification {
    [self close];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (self.onWindowClose != nil) {
        self.onWindowClose();
    }
}

- (BOOL)validateDatasetAndShowAlert {
    if (self.viewer == nil) {
        [self showAlertWithMessage:@"No active Horos viewer is attached to the plugin window."];
        return NO;
    }

    BOOL volumic = [self.viewer isDataVolumicIn4D:NO checkEverythingLoaded:YES tryToCorrect:NO];
    if (!volumic) {
        [self showAlertWithMessage:@"The active series is not volumic. Open a volumic series or MPR aligned to the target plane and try again."];
        return NO;
    }
    return YES;
}

- (NSArray<ROI *> *)validatedSelectedROIsForAllowedTypes:(NSArray<NSNumber *> *)allowedTypes requiredCount:(NSUInteger)requiredCount {
    NSMutableArray *selected = [self.viewer selectedROIs];
    if (selected.count != requiredCount) {
        NSString *message = requiredCount == 1
            ? @"Select exactly one ROI in Horos before capturing."
            : [NSString stringWithFormat:@"Select exactly %lu point ROIs in Horos before capturing this step.", (unsigned long)requiredCount];
        [self showAlertWithMessage:message];
        return nil;
    }

    for (ROI *roi in selected) {
        if (![allowedTypes containsObject:@(roi.type)]) {
            [self showAlertWithMessage:@"The selected ROI type is not valid for this capture action."];
            return nil;
        }
    }
    return selected;
}

- (void)captureContourForIdentifier:(NSString *)identifier roiName:(NSString *)roiName displayTitle:(NSString *)displayTitle {
    if (![self validateDatasetAndShowAlert]) {
        return;
    }

    ROI *roi = [[self validatedSelectedROIsForAllowedTypes:@[@(tCPolygon), @(tPencil), @(tOval)] requiredCount:1] firstObject];
    if (roi == nil) {
        return;
    }

    NSError *error = nil;
    TAVIContourSnapshot *snapshot = TAVIMakeContourSnapshot(roi, self.viewer, displayTitle, &error);
    if (snapshot == nil) {
        [self showAlertWithMessage:error.localizedDescription ?: @"Unable to capture the selected contour ROI."];
        return;
    }

    roi.name = roiName;
    [self.viewer needsDisplayUpdate];
    [self.session captureContourSnapshot:snapshot forIdentifier:identifier];
    [self refreshUIWithStatus:[NSString stringWithFormat:@"Captured %@ from series %@.", displayTitle, snapshot.seriesUID]];
}

- (void)capturePointForIdentifier:(NSString *)identifier roiName:(NSString *)roiName displayTitle:(NSString *)displayTitle {
    if (![self validateDatasetAndShowAlert]) {
        return;
    }

    ROI *roi = [[self validatedSelectedROIsForAllowedTypes:@[@(t2DPoint), @(t3Dpoint)] requiredCount:1] firstObject];
    if (roi == nil) {
        return;
    }

    NSError *error = nil;
    TAVIPointSnapshot *snapshot = TAVIMakePointSnapshot(roi, self.viewer, displayTitle, &error);
    if (snapshot == nil) {
        [self showAlertWithMessage:error.localizedDescription ?: @"Unable to capture the selected point ROI."];
        return;
    }

    roi.name = roiName;
    [self.viewer needsDisplayUpdate];
    [self.session capturePointSnapshot:snapshot forIdentifier:identifier];
    [self refreshUIWithStatus:[NSString stringWithFormat:@"Captured %@ from series %@.", displayTitle, snapshot.seriesUID]];
}

- (void)captureAnnulus:(id)sender {
    [self captureContourForIdentifier:TAVIStructureAnnulus roiName:@"TAVI_Annulus" displayTitle:@"Annulus"];
}

- (void)captureLVOT:(id)sender {
    [self captureContourForIdentifier:TAVIStructureLVOT roiName:@"TAVI_LVOT" displayTitle:@"LVOT"];
}

- (void)captureLeftOstium:(id)sender {
    [self capturePointForIdentifier:TAVIStructureLeftOstium roiName:@"TAVI_LeftOstium" displayTitle:@"Left Ostium"];
}

- (void)captureRightOstium:(id)sender {
    [self capturePointForIdentifier:TAVIStructureRightOstium roiName:@"TAVI_RightOstium" displayTitle:@"Right Ostium"];
}

- (void)captureSinus:(id)sender {
    [self captureContourForIdentifier:TAVIStructureSinus roiName:@"TAVI_Sinus" displayTitle:@"Sinus"];
}

- (void)captureSTJ:(id)sender {
    [self captureContourForIdentifier:TAVIStructureSTJ roiName:@"TAVI_STJ" displayTitle:@"STJ"];
}

- (void)captureAscendingAorta:(id)sender {
    [self captureContourForIdentifier:TAVIStructureAscendingAorta roiName:@"TAVI_AscAo" displayTitle:@"Ascending Aorta"];
}

- (void)captureSinusPoints:(id)sender {
    if (![self validateDatasetAndShowAlert]) {
        return;
    }

    NSArray<ROI *> *rois = [self validatedSelectedROIsForAllowedTypes:@[@(t2DPoint), @(t3Dpoint)] requiredCount:3];
    if (rois == nil) {
        return;
    }

    NSMutableArray<TAVIPointSnapshot *> *snapshots = [NSMutableArray arrayWithCapacity:rois.count];
    for (NSUInteger idx = 0; idx < rois.count; idx++) {
        ROI *roi = rois[idx];
        NSError *error = nil;
        NSString *label = [NSString stringWithFormat:@"Sinus Point %lu", (unsigned long)(idx + 1)];
        TAVIPointSnapshot *snapshot = TAVIMakePointSnapshot(roi, self.viewer, label, &error);
        if (snapshot == nil) {
            [self showAlertWithMessage:error.localizedDescription ?: @"Unable to capture the selected sinus point ROI."];
            return;
        }
        roi.name = [NSString stringWithFormat:@"TAVI_SinusPoint_%lu", (unsigned long)(idx + 1)];
        [snapshots addObject:snapshot];
    }

    [self.viewer needsDisplayUpdate];
    [self.session capturePointSnapshots:snapshots forIdentifier:TAVIStructureSinusPoints];
    [self refreshUIWithStatus:@"Captured three sinus points for projection-angle confirmation."];
}

- (void)captureMembranousSeptum:(id)sender {
    if (![self validateDatasetAndShowAlert]) {
        return;
    }

    NSArray<ROI *> *rois = [self validatedSelectedROIsForAllowedTypes:@[@(t2DPoint), @(t3Dpoint)] requiredCount:2];
    if (rois == nil) {
        return;
    }

    NSMutableArray<TAVIPointSnapshot *> *snapshots = [NSMutableArray arrayWithCapacity:rois.count];
    for (NSUInteger idx = 0; idx < rois.count; idx++) {
        ROI *roi = rois[idx];
        NSError *error = nil;
        NSString *label = [NSString stringWithFormat:@"Membranous Septum %lu", (unsigned long)(idx + 1)];
        TAVIPointSnapshot *snapshot = TAVIMakePointSnapshot(roi, self.viewer, label, &error);
        if (snapshot == nil) {
            [self showAlertWithMessage:error.localizedDescription ?: @"Unable to capture the selected membranous septum point ROI."];
            return;
        }
        roi.name = [NSString stringWithFormat:@"TAVI_MembranousSeptum_%lu", (unsigned long)(idx + 1)];
        [snapshots addObject:snapshot];
    }

    [self.viewer needsDisplayUpdate];
    [self.session capturePointSnapshots:snapshots forIdentifier:TAVIStructureMembranousSeptum];
    [self refreshUIWithStatus:@"Captured two membranous septum points for length measurement."];
}

- (void)toggleAssistedAnnulus:(id)sender {
    if (self.session.assistedAnnulusGeometry == nil) {
        [self showAlertWithMessage:@"Capture the annulus contour first. The plugin computes the assisted annulus fit from that contour."];
        return;
    }

    self.session.useAssistedAnnulusForPlanning = !self.session.useAssistedAnnulusForPlanning;
    [self.session recompute];
    [self refreshUIWithStatus:self.session.useAssistedAnnulusForPlanning
        ? @"Switched planning measurements and preview to the assisted annulus fit."
        : @"Switched planning measurements and preview back to the captured annulus contour."];
}

- (void)recompute:(id)sender {
    [self.session recompute];
    [self refreshUIWithStatus:@"Recomputed measurements using the current threshold, planning source, and captured snapshots."];
}

- (void)thresholdChanged:(id)sender {
    double threshold = self.thresholdField.doubleValue;
    if (threshold <= 0.0) {
        threshold = 850.0;
        self.thresholdField.stringValue = @"850";
    }
    self.session.calciumThresholdHU = threshold;
    [self.session recompute];
    [self refreshUIWithStatus:[NSString stringWithFormat:@"Updated calcium threshold to %.0f HU.", threshold]];
}

- (void)virtualValveChanged:(id)sender {
    double diameter = self.virtualValveField.doubleValue;
    if (diameter <= 0.0) {
        self.session.hasManualVirtualValveDiameter = NO;
    } else {
        self.session.virtualValveDiameterMm = diameter;
        self.session.hasManualVirtualValveDiameter = YES;
    }
    [self.session recompute];
    [self refreshUIWithStatus:self.session.hasManualVirtualValveDiameter
        ? [NSString stringWithFormat:@"Updated virtual valve overlay to %.1f mm.", self.session.virtualValveDiameterMm]
        : @"Reset virtual valve overlay to the annulus-derived suggestion."];
}

- (void)calcificationChanged:(id)sender {
    self.session.cuspCalcificationGrade = self.cuspPopup.indexOfSelectedItem;
    self.session.annulusCalcificationGrade = self.annulusPopup.indexOfSelectedItem;
    [self refreshUIWithStatus:@"Updated manual calcification grades."];
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.notesTextView) {
        self.session.notes = self.notesTextView.string ?: @"";
        [self refreshReportPreview];
    }
}

- (void)exportCSV:(id)sender {
    TAVIReportRecord *record = [self.session reportRecord];
    [self exportReportNamedSuffix:@"tavi-report" extension:@"csv" contents:[record csvReport]];
}

- (void)exportText:(id)sender {
    TAVIReportRecord *record = [self.session reportRecord];
    [self exportReportNamedSuffix:@"tavi-report" extension:@"txt" contents:[record textReport]];
}

- (void)exportReportNamedSuffix:(NSString *)suffix extension:(NSString *)extension contents:(NSString *)contents {
    TAVIReportRecord *record = [self.session reportRecord];
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = [extension isEqualToString:@"csv"] ? @[UTTypeCommaSeparatedText] : @[UTTypePlainText];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[extension];
#pragma clang diagnostic pop
    }
    NSString *filename = [NSString stringWithFormat:@"%@-%@.%@", TAVISanitizeFileComponent(record.patientName), suffix, extension];
    panel.nameFieldStringValue = filename;
    if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSError *error = nil;
    BOOL success = [contents writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        [self showAlertWithMessage:error.localizedDescription ?: @"Failed to write the export file."];
        return;
    }

    self.exportStatusField.stringValue = [NSString stringWithFormat:@"Saved %@", panel.URL.lastPathComponent];
}

- (void)refreshUIWithStatus:(NSString *)status {
    NSString *patientLine = self.session.patientName.length > 0
        ? [NSString stringWithFormat:@"Patient %@ (%@)", self.session.patientName, self.session.patientID ?: @""]
        : @"No patient metadata captured yet";
    NSString *studyLine = self.session.studyInstanceUID.length > 0
        ? [NSString stringWithFormat:@"Study UID %@", self.session.studyInstanceUID]
        : @"Study UID not captured yet";
    BOOL volumic = self.viewer != nil ? [self.viewer isDataVolumicIn4D:NO checkEverythingLoaded:NO tryToCorrect:NO] : NO;

    self.datasetStatusField.stringValue = [NSString stringWithFormat:@"%@\n%@\nViewer volumic: %@\nNext recommended step: %@",
                                           patientLine,
                                           studyLine,
                                           volumic ? @"Yes" : @"No",
                                           [self.session nextRecommendedStepSummary]];
    self.workflowField.stringValue = [self.session workflowChecklistSummary];
    self.captureStatusField.stringValue = [NSString stringWithFormat:@"%@\n%@",
                                           [self.session captureCompletenessSummary],
                                           status ?: @""];

    self.annulusField.stringValue = self.session.annulusGeometry
        ? [NSString stringWithFormat:@"%@\nCalcium: %@", TAVIFormatGeometrySummary(self.session.annulusGeometry), TAVIFormatCalciumSummary(self.session.annulusCalcium)]
        : @"Not captured";
    self.assistedAnnulusField.stringValue = [self.session assistedAnnulusSummary];
    self.lvotField.stringValue = self.session.lvotGeometry
        ? [NSString stringWithFormat:@"%@\nCalcium: %@", TAVIFormatGeometrySummary(self.session.lvotGeometry), TAVIFormatCalciumSummary(self.session.lvotCalcium)]
        : @"Optional capture not present";
    self.membranousSeptumField.stringValue = self.session.membranousSeptumLengthMm
        ? [NSString stringWithFormat:@"%.1f mm", self.session.membranousSeptumLengthMm.doubleValue]
        : @"Optional 2-point capture not present";
    self.coronaryField.stringValue = [NSString stringWithFormat:@"Left %@ | Right %@",
                                      self.session.leftCoronaryHeightMm ? [NSString stringWithFormat:@"%.1f mm", self.session.leftCoronaryHeightMm.doubleValue] : @"-",
                                      self.session.rightCoronaryHeightMm ? [NSString stringWithFormat:@"%.1f mm", self.session.rightCoronaryHeightMm.doubleValue] : @"-"];
    self.sinusField.stringValue = self.session.sinusGeometry
        ? [NSString stringWithFormat:@"%@\nCalcium: %@", TAVIFormatGeometrySummary(self.session.sinusGeometry), TAVIFormatCalciumSummary(self.session.sinusCalcium)]
        : @"Optional capture not present";
    self.stjField.stringValue = self.session.stjGeometry
        ? [NSString stringWithFormat:@"%@\nCalcium: %@", TAVIFormatGeometrySummary(self.session.stjGeometry), TAVIFormatCalciumSummary(self.session.stjCalcium)]
        : @"Optional capture not present";
    self.ascendingAortaField.stringValue = self.session.ascendingAortaGeometry
        ? [NSString stringWithFormat:@"%@\nCalcium: %@", TAVIFormatGeometrySummary(self.session.ascendingAortaGeometry), TAVIFormatCalciumSummary(self.session.ascendingAortaCalcium)]
        : @"Optional capture not present";

    self.angleField.stringValue = self.session.fluoroAngle
        ? [NSString stringWithFormat:@"Angle %@ | horizontal aorta %.1f deg | valve %.1f mm",
                                      [self.session.fluoroAngle advisorySummary],
                                      self.session.horizontalAortaAngleDegrees,
                                      self.session.virtualValveDiameterMm]
        : @"Advisory annulus angle: capture annulus to compute.";
    self.confirmationField.stringValue = self.session.projectionConfirmation ? @"3-point OK" : @"3-point opt";
    self.calciumField.stringValue = [NSString stringWithFormat:@"Annulus Ag %.1f",
                                     self.session.annulusCalcium ? self.session.annulusCalcium.agatstonScore2D : 0.0];
    self.virtualValveField.stringValue = self.session.virtualValveDiameterMm > 0.0
        ? [NSString stringWithFormat:@"%.1f", self.session.virtualValveDiameterMm]
        : @"";
    self.calciumField.toolTip = [NSString stringWithFormat:@"Threshold %.0f HU, cusp grade %ld, annulus grade %ld",
                                     self.session.calciumThresholdHU,
                                     (long)self.session.cuspCalcificationGrade,
                                     (long)self.session.annulusCalcificationGrade];
    self.assistAnnulusButton.title = self.session.useAssistedAnnulusForPlanning && self.session.assistedAnnulusGeometry
        ? @"Use Captured Annulus"
        : @"Use Assisted Annulus";

    [self.previewView refreshWithSession:self.session];
    [self refreshReportPreview];
}

- (void)refreshReportPreview {
    TAVIReportRecord *record = [self.session reportRecord];
    self.reportTextView.string = [record textReport];
}

- (void)showAlertWithMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"TAVI Planning";
    alert.informativeText = message ?: @"An unknown error occurred.";
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end
