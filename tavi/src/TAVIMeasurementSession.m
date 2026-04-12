#import "TAVIMeasurementSession.h"

NSString * const TAVIStructureAnnulus = @"annulus";
NSString * const TAVIStructureLeftOstium = @"left-ostium";
NSString * const TAVIStructureRightOstium = @"right-ostium";
NSString * const TAVIStructureSinus = @"sinus";
NSString * const TAVIStructureSTJ = @"stj";
NSString * const TAVIStructureAscendingAorta = @"ascending-aorta";
NSString * const TAVIStructureSinusPoints = @"sinus-points";
NSString * const TAVIStructureLVOT = @"lvot";
NSString * const TAVIStructureMembranousSeptum = @"membranous-septum";

static NSString *TAVISafeString(NSString *value) {
    return value.length > 0 ? value : @"";
}

static NSString *TAVIFormatOptionalDouble(NSNumber *value, NSString *suffix) {
    if (value == nil) {
        return @"";
    }
    return [NSString stringWithFormat:@"%.1f%@", value.doubleValue, suffix];
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
    return [NSString stringWithFormat:@"HU %.0f -> %.1f mm2 hyperdense (%.1f%% of ROI), Agatston-like %.1f",
                                      calcium.thresholdHU,
                                      calcium.hyperdenseAreaMm2,
                                      calcium.fractionAboveThreshold * 100.0,
                                      calcium.agatstonScore2D];
}

static NSString *TAVIFormatProjectionSummary(TAVIProjectionConfirmationResult *projectionConfirmation) {
    if (projectionConfirmation == nil) {
        return @"Optional 3-point sinus confirmation not captured";
    }
    return [projectionConfirmation summary];
}

static NSString *TAVICSVEscape(NSString *value) {
    NSString *safe = TAVISafeString(value);
    NSString *escaped = [safe stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

static double TAVIRoundToHalfMillimeter(double value) {
    return round(value * 2.0) / 2.0;
}

@implementation TAVIContourSnapshot

- (id)copyWithZone:(NSZone *)zone {
    TAVIContourSnapshot *copy = [[[self class] allocWithZone:zone] init];
    copy.label = self.label;
    copy.seriesUID = self.seriesUID;
    copy.seriesDescription = self.seriesDescription;
    copy.studyInstanceUID = self.studyInstanceUID;
    copy.patientName = self.patientName;
    copy.patientID = self.patientID;
    copy.patientUID = self.patientUID;
    copy.patientBirthDate = self.patientBirthDate;
    copy.pixelPoints = self.pixelPoints;
    copy.worldPoints = self.worldPoints;
    copy.pixelValues = self.pixelValues;
    copy.pixelAreaMm2 = self.pixelAreaMm2;
    copy.roiType = self.roiType;
    copy.sliceIndex = self.sliceIndex;
    copy.planeOrigin = self.planeOrigin;
    copy.planeNormal = self.planeNormal;
    return copy;
}

@end

@implementation TAVIPointSnapshot

- (id)copyWithZone:(NSZone *)zone {
    TAVIPointSnapshot *copy = [[[self class] allocWithZone:zone] init];
    copy.label = self.label;
    copy.seriesUID = self.seriesUID;
    copy.seriesDescription = self.seriesDescription;
    copy.studyInstanceUID = self.studyInstanceUID;
    copy.patientName = self.patientName;
    copy.patientID = self.patientID;
    copy.patientUID = self.patientUID;
    copy.patientBirthDate = self.patientBirthDate;
    copy.pixelPoint = self.pixelPoint;
    copy.sliceIndex = self.sliceIndex;
    copy.roiType = self.roiType;
    copy.worldPoint = self.worldPoint;
    return copy;
}

@end

@implementation TAVIReportRecord

- (NSString *)textReport {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:@"TAVI Planning Report"];
    [lines addObject:@"===================="];
    [lines addObject:[NSString stringWithFormat:@"Report Date: %@", [formatter stringFromDate:self.reportDate ?: [NSDate date]]]];
    [lines addObject:[NSString stringWithFormat:@"Patient: %@", TAVISafeString(self.patientName)]];
    [lines addObject:[NSString stringWithFormat:@"Patient ID: %@", TAVISafeString(self.patientID)]];
    [lines addObject:[NSString stringWithFormat:@"Patient UID: %@", TAVISafeString(self.patientUID)]];
    [lines addObject:[NSString stringWithFormat:@"DOB: %@", TAVISafeString(self.patientBirthDate)]];
    [lines addObject:[NSString stringWithFormat:@"Study UID: %@", TAVISafeString(self.studyInstanceUID)]];
    [lines addObject:@""];

    [lines addObject:@"Annulus"];
    [lines addObject:[NSString stringWithFormat:@"Series UID: %@", TAVISafeString(self.annulusSeriesUID)]];
    [lines addObject:[NSString stringWithFormat:@"Captured contour: %@", TAVIFormatGeometrySummary(self.annulusGeometry)]];
    [lines addObject:[NSString stringWithFormat:@"Assisted ellipse fit: %@", TAVIFormatGeometrySummary(self.assistedAnnulusGeometry)]];
    [lines addObject:[NSString stringWithFormat:@"Planning source: %@", self.usingAssistedAnnulusForPlanning ? @"Assisted annulus fit" : @"Captured contour"]];
    [lines addObject:[NSString stringWithFormat:@"Horizontal aorta angle: %@", self.horizontalAortaAngleDegrees > 0.0 ? [NSString stringWithFormat:@"%.1f deg to axial reference", self.horizontalAortaAngleDegrees] : @"Not available"]];
    [lines addObject:[NSString stringWithFormat:@"Virtual valve overlay: %@", self.virtualValveDiameterMm > 0.0 ? [NSString stringWithFormat:@"%.1f mm", self.virtualValveDiameterMm] : @"Not configured"]];
    [lines addObject:[NSString stringWithFormat:@"Calcium assist: %@", TAVIFormatCalciumSummary(self.annulusCalcium)]];
    [lines addObject:[NSString stringWithFormat:@"Manual annulus calcification grade: %ld", (long)self.annulusCalcificationGrade]];
    [lines addObject:@""];

    [lines addObject:@"Coronary Heights"];
    [lines addObject:[NSString stringWithFormat:@"Left coronary height: %@", TAVIFormatOptionalDouble(self.leftCoronaryHeightMm, @" mm")]];
    [lines addObject:[NSString stringWithFormat:@"Right coronary height: %@", TAVIFormatOptionalDouble(self.rightCoronaryHeightMm, @" mm")]];
    [lines addObject:[NSString stringWithFormat:@"Left ostium series UID: %@", TAVISafeString(self.leftOstiumSeriesUID)]];
    [lines addObject:[NSString stringWithFormat:@"Right ostium series UID: %@", TAVISafeString(self.rightOstiumSeriesUID)]];
    [lines addObject:@""];

    [lines addObject:@"Root Measurements"];
    [lines addObject:[NSString stringWithFormat:@"LVOT (%@): %@", TAVISafeString(self.lvotSeriesUID), TAVIFormatGeometrySummary(self.lvotGeometry)]];
    [lines addObject:[NSString stringWithFormat:@"LVOT calcium: %@", TAVIFormatCalciumSummary(self.lvotCalcium)]];
    [lines addObject:[NSString stringWithFormat:@"Sinus (%@): %@", TAVISafeString(self.sinusSeriesUID), TAVIFormatGeometrySummary(self.sinusGeometry)]];
    [lines addObject:[NSString stringWithFormat:@"Sinus calcium: %@", TAVIFormatCalciumSummary(self.sinusCalcium)]];
    [lines addObject:[NSString stringWithFormat:@"STJ (%@): %@", TAVISafeString(self.stjSeriesUID), TAVIFormatGeometrySummary(self.stjGeometry)]];
    [lines addObject:[NSString stringWithFormat:@"STJ calcium: %@", TAVIFormatCalciumSummary(self.stjCalcium)]];
    [lines addObject:[NSString stringWithFormat:@"Ascending aorta (%@): %@", TAVISafeString(self.ascendingAortaSeriesUID), TAVIFormatGeometrySummary(self.ascendingAortaGeometry)]];
    [lines addObject:[NSString stringWithFormat:@"Ascending aorta calcium: %@", TAVIFormatCalciumSummary(self.ascendingAortaCalcium)]];
    [lines addObject:[NSString stringWithFormat:@"Membranous septum length: %@", TAVIFormatOptionalDouble(self.membranousSeptumLengthMm, @" mm")]];
    [lines addObject:@""];

    [lines addObject:@"Angle / Projection"];
    [lines addObject:[NSString stringWithFormat:@"Advisory annulus angle: %@", self.fluoroAngle ? [self.fluoroAngle advisorySummary] : @"Not available"]];
    [lines addObject:[NSString stringWithFormat:@"Sinus-point confirmation: %@", TAVIFormatProjectionSummary(self.projectionConfirmation)]];
    [lines addObject:@"Projection note: this is a lightweight planning preview, not vendor-validated simulated angio."];
    [lines addObject:@"Workflow note: the historical OsiriX TAVIReport workflow used 3 sinus points for projection-angle confirmation; this v1.2 plugin supports an optional 3-point confirmation step plus an annulus-based preview."];
    [lines addObject:@""];

    [lines addObject:@"Calcification"];
    [lines addObject:[NSString stringWithFormat:@"Manual cusp calcification grade: %ld", (long)self.cuspCalcificationGrade]];
    [lines addObject:[NSString stringWithFormat:@"Calcium threshold: %.0f HU", self.calciumThresholdHU]];
    [lines addObject:@""];

    [lines addObject:@"Notes"];
    [lines addObject:TAVISafeString(self.notes)];

    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)csvReport {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;

    NSArray<NSString *> *headers = @[
        @"report_date",
        @"patient_name",
        @"patient_id",
        @"patient_uid",
        @"patient_birth_date",
        @"study_instance_uid",
        @"annulus_series_uid",
        @"annulus_perimeter_mm",
        @"annulus_area_mm2",
        @"annulus_equivalent_diameter_mm",
        @"annulus_min_diameter_mm",
        @"annulus_max_diameter_mm",
        @"horizontal_aorta_angle_deg",
        @"virtual_valve_diameter_mm",
        @"assisted_annulus_perimeter_mm",
        @"assisted_annulus_area_mm2",
        @"assisted_annulus_min_diameter_mm",
        @"assisted_annulus_max_diameter_mm",
        @"using_assisted_annulus",
        @"lvot_series_uid",
        @"lvot_perimeter_mm",
        @"lvot_area_mm2",
        @"lvot_eq_diameter_mm",
        @"left_ostium_series_uid",
        @"right_ostium_series_uid",
        @"left_coronary_height_mm",
        @"right_coronary_height_mm",
        @"membranous_septum_length_mm",
        @"sinus_series_uid",
        @"sinus_perimeter_mm",
        @"sinus_area_mm2",
        @"sinus_eq_diameter_mm",
        @"stj_series_uid",
        @"stj_perimeter_mm",
        @"stj_area_mm2",
        @"stj_eq_diameter_mm",
        @"ascending_aorta_series_uid",
        @"ascending_aorta_perimeter_mm",
        @"ascending_aorta_area_mm2",
        @"ascending_aorta_eq_diameter_mm",
        @"annulus_hyperdense_area_mm2",
        @"annulus_agatston_2d",
        @"lvot_hyperdense_area_mm2",
        @"lvot_agatston_2d",
        @"sinus_hyperdense_area_mm2",
        @"sinus_agatston_2d",
        @"stj_hyperdense_area_mm2",
        @"stj_agatston_2d",
        @"ascending_aorta_hyperdense_area_mm2",
        @"ascending_aorta_agatston_2d",
        @"calcium_threshold_hu",
        @"manual_cusp_calcification_grade",
        @"manual_annulus_calcification_grade",
        @"annulus_fluoro_advisory",
        @"sinus_confirmation_summary",
        @"sinus_confirmation_delta_deg",
        @"notes"
    ];

    NSArray<NSString *> *values = @[
        TAVICSVEscape([formatter stringFromDate:self.reportDate ?: [NSDate date]]),
        TAVICSVEscape(self.patientName),
        TAVICSVEscape(self.patientID),
        TAVICSVEscape(self.patientUID),
        TAVICSVEscape(self.patientBirthDate),
        TAVICSVEscape(self.studyInstanceUID),
        TAVICSVEscape(self.annulusSeriesUID),
        TAVICSVEscape(self.annulusGeometry ? [NSString stringWithFormat:@"%.3f", self.annulusGeometry.perimeterMm] : @""),
        TAVICSVEscape(self.annulusGeometry ? [NSString stringWithFormat:@"%.3f", self.annulusGeometry.areaMm2] : @""),
        TAVICSVEscape(self.annulusGeometry ? [NSString stringWithFormat:@"%.3f", self.annulusGeometry.equivalentDiameterMm] : @""),
        TAVICSVEscape(self.annulusGeometry ? [NSString stringWithFormat:@"%.3f", self.annulusGeometry.minimumDiameterMm] : @""),
        TAVICSVEscape(self.annulusGeometry ? [NSString stringWithFormat:@"%.3f", self.annulusGeometry.maximumDiameterMm] : @""),
        TAVICSVEscape(self.horizontalAortaAngleDegrees > 0.0 ? [NSString stringWithFormat:@"%.3f", self.horizontalAortaAngleDegrees] : @""),
        TAVICSVEscape(self.virtualValveDiameterMm > 0.0 ? [NSString stringWithFormat:@"%.3f", self.virtualValveDiameterMm] : @""),
        TAVICSVEscape(self.assistedAnnulusGeometry ? [NSString stringWithFormat:@"%.3f", self.assistedAnnulusGeometry.perimeterMm] : @""),
        TAVICSVEscape(self.assistedAnnulusGeometry ? [NSString stringWithFormat:@"%.3f", self.assistedAnnulusGeometry.areaMm2] : @""),
        TAVICSVEscape(self.assistedAnnulusGeometry ? [NSString stringWithFormat:@"%.3f", self.assistedAnnulusGeometry.minimumDiameterMm] : @""),
        TAVICSVEscape(self.assistedAnnulusGeometry ? [NSString stringWithFormat:@"%.3f", self.assistedAnnulusGeometry.maximumDiameterMm] : @""),
        TAVICSVEscape(self.usingAssistedAnnulusForPlanning ? @"yes" : @"no"),
        TAVICSVEscape(self.lvotSeriesUID),
        TAVICSVEscape(self.lvotGeometry ? [NSString stringWithFormat:@"%.3f", self.lvotGeometry.perimeterMm] : @""),
        TAVICSVEscape(self.lvotGeometry ? [NSString stringWithFormat:@"%.3f", self.lvotGeometry.areaMm2] : @""),
        TAVICSVEscape(self.lvotGeometry ? [NSString stringWithFormat:@"%.3f", self.lvotGeometry.equivalentDiameterMm] : @""),
        TAVICSVEscape(self.leftOstiumSeriesUID),
        TAVICSVEscape(self.rightOstiumSeriesUID),
        TAVICSVEscape(self.leftCoronaryHeightMm ? [NSString stringWithFormat:@"%.3f", self.leftCoronaryHeightMm.doubleValue] : @""),
        TAVICSVEscape(self.rightCoronaryHeightMm ? [NSString stringWithFormat:@"%.3f", self.rightCoronaryHeightMm.doubleValue] : @""),
        TAVICSVEscape(self.membranousSeptumLengthMm ? [NSString stringWithFormat:@"%.3f", self.membranousSeptumLengthMm.doubleValue] : @""),
        TAVICSVEscape(self.sinusSeriesUID),
        TAVICSVEscape(self.sinusGeometry ? [NSString stringWithFormat:@"%.3f", self.sinusGeometry.perimeterMm] : @""),
        TAVICSVEscape(self.sinusGeometry ? [NSString stringWithFormat:@"%.3f", self.sinusGeometry.areaMm2] : @""),
        TAVICSVEscape(self.sinusGeometry ? [NSString stringWithFormat:@"%.3f", self.sinusGeometry.equivalentDiameterMm] : @""),
        TAVICSVEscape(self.stjSeriesUID),
        TAVICSVEscape(self.stjGeometry ? [NSString stringWithFormat:@"%.3f", self.stjGeometry.perimeterMm] : @""),
        TAVICSVEscape(self.stjGeometry ? [NSString stringWithFormat:@"%.3f", self.stjGeometry.areaMm2] : @""),
        TAVICSVEscape(self.stjGeometry ? [NSString stringWithFormat:@"%.3f", self.stjGeometry.equivalentDiameterMm] : @""),
        TAVICSVEscape(self.ascendingAortaSeriesUID),
        TAVICSVEscape(self.ascendingAortaGeometry ? [NSString stringWithFormat:@"%.3f", self.ascendingAortaGeometry.perimeterMm] : @""),
        TAVICSVEscape(self.ascendingAortaGeometry ? [NSString stringWithFormat:@"%.3f", self.ascendingAortaGeometry.areaMm2] : @""),
        TAVICSVEscape(self.ascendingAortaGeometry ? [NSString stringWithFormat:@"%.3f", self.ascendingAortaGeometry.equivalentDiameterMm] : @""),
        TAVICSVEscape(self.annulusCalcium ? [NSString stringWithFormat:@"%.3f", self.annulusCalcium.hyperdenseAreaMm2] : @""),
        TAVICSVEscape(self.annulusCalcium ? [NSString stringWithFormat:@"%.3f", self.annulusCalcium.agatstonScore2D] : @""),
        TAVICSVEscape(self.lvotCalcium ? [NSString stringWithFormat:@"%.3f", self.lvotCalcium.hyperdenseAreaMm2] : @""),
        TAVICSVEscape(self.lvotCalcium ? [NSString stringWithFormat:@"%.3f", self.lvotCalcium.agatstonScore2D] : @""),
        TAVICSVEscape(self.sinusCalcium ? [NSString stringWithFormat:@"%.3f", self.sinusCalcium.hyperdenseAreaMm2] : @""),
        TAVICSVEscape(self.sinusCalcium ? [NSString stringWithFormat:@"%.3f", self.sinusCalcium.agatstonScore2D] : @""),
        TAVICSVEscape(self.stjCalcium ? [NSString stringWithFormat:@"%.3f", self.stjCalcium.hyperdenseAreaMm2] : @""),
        TAVICSVEscape(self.stjCalcium ? [NSString stringWithFormat:@"%.3f", self.stjCalcium.agatstonScore2D] : @""),
        TAVICSVEscape(self.ascendingAortaCalcium ? [NSString stringWithFormat:@"%.3f", self.ascendingAortaCalcium.hyperdenseAreaMm2] : @""),
        TAVICSVEscape(self.ascendingAortaCalcium ? [NSString stringWithFormat:@"%.3f", self.ascendingAortaCalcium.agatstonScore2D] : @""),
        TAVICSVEscape([NSString stringWithFormat:@"%.0f", self.calciumThresholdHU]),
        TAVICSVEscape([NSString stringWithFormat:@"%ld", (long)self.cuspCalcificationGrade]),
        TAVICSVEscape([NSString stringWithFormat:@"%ld", (long)self.annulusCalcificationGrade]),
        TAVICSVEscape(self.fluoroAngle ? [self.fluoroAngle advisorySummary] : @""),
        TAVICSVEscape(self.projectionConfirmation ? [self.projectionConfirmation summary] : @""),
        TAVICSVEscape(self.projectionConfirmation ? [NSString stringWithFormat:@"%.3f", self.projectionConfirmation.normalDifferenceDegrees] : @""),
        TAVICSVEscape(self.notes)
    ];

    return [NSString stringWithFormat:@"%@\n%@", [headers componentsJoinedByString:@","], [values componentsJoinedByString:@","]];
}

@end

@implementation TAVIMeasurementSession

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _calciumThresholdHU = 850.0;
        _notes = @"";
        _sinusPointSnapshots = @[];
        _membranousSeptumPointSnapshots = @[];
    }
    return self;
}

- (void)applyMetadataFromContour:(TAVIContourSnapshot *)snapshot {
    if (snapshot == nil) {
        return;
    }
    self.patientName = snapshot.patientName ?: self.patientName;
    self.patientID = snapshot.patientID ?: self.patientID;
    self.patientUID = snapshot.patientUID ?: self.patientUID;
    self.patientBirthDate = snapshot.patientBirthDate ?: self.patientBirthDate;
    self.studyInstanceUID = snapshot.studyInstanceUID ?: self.studyInstanceUID;
}

- (void)applyMetadataFromPoint:(TAVIPointSnapshot *)snapshot {
    if (snapshot == nil) {
        return;
    }
    self.patientName = snapshot.patientName ?: self.patientName;
    self.patientID = snapshot.patientID ?: self.patientID;
    self.patientUID = snapshot.patientUID ?: self.patientUID;
    self.patientBirthDate = snapshot.patientBirthDate ?: self.patientBirthDate;
    self.studyInstanceUID = snapshot.studyInstanceUID ?: self.studyInstanceUID;
}

- (void)captureContourSnapshot:(TAVIContourSnapshot *)snapshot forIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:TAVIStructureAnnulus]) {
        self.annulusSnapshot = [snapshot copy];
    } else if ([identifier isEqualToString:TAVIStructureLVOT]) {
        self.lvotSnapshot = [snapshot copy];
    } else if ([identifier isEqualToString:TAVIStructureSinus]) {
        self.sinusSnapshot = [snapshot copy];
    } else if ([identifier isEqualToString:TAVIStructureSTJ]) {
        self.stjSnapshot = [snapshot copy];
    } else if ([identifier isEqualToString:TAVIStructureAscendingAorta]) {
        self.ascendingAortaSnapshot = [snapshot copy];
    }
    [self applyMetadataFromContour:snapshot];
    [self recompute];
}

- (void)capturePointSnapshot:(TAVIPointSnapshot *)snapshot forIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:TAVIStructureLeftOstium]) {
        self.leftOstiumSnapshot = [snapshot copy];
    } else if ([identifier isEqualToString:TAVIStructureRightOstium]) {
        self.rightOstiumSnapshot = [snapshot copy];
    }
    [self applyMetadataFromPoint:snapshot];
    [self recompute];
}

- (void)capturePointSnapshots:(NSArray<TAVIPointSnapshot *> *)snapshots forIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:TAVIStructureSinusPoints]) {
        NSMutableArray<TAVIPointSnapshot *> *copies = [NSMutableArray arrayWithCapacity:snapshots.count];
        for (TAVIPointSnapshot *snapshot in snapshots) {
            [copies addObject:[snapshot copy]];
        }
        self.sinusPointSnapshots = copies;
        if (self.sinusPointSnapshots.count > 0) {
            [self applyMetadataFromPoint:self.sinusPointSnapshots.firstObject];
        }
        [self recompute];
    } else if ([identifier isEqualToString:TAVIStructureMembranousSeptum]) {
        NSMutableArray<TAVIPointSnapshot *> *copies = [NSMutableArray arrayWithCapacity:snapshots.count];
        for (TAVIPointSnapshot *snapshot in snapshots) {
            [copies addObject:[snapshot copy]];
        }
        self.membranousSeptumPointSnapshots = copies;
        if (self.membranousSeptumPointSnapshots.count > 0) {
            [self applyMetadataFromPoint:self.membranousSeptumPointSnapshots.firstObject];
        }
        [self recompute];
    }
}

- (TAVIGeometryResult *)activeAnnulusGeometry {
    if (self.useAssistedAnnulusForPlanning && self.assistedAnnulusGeometry != nil) {
        return self.assistedAnnulusGeometry;
    }
    return self.annulusGeometry;
}

- (TAVIFluoroAngleResult *)preferredProjectionAngle {
    return self.projectionConfirmation.confirmationAngle ?: self.fluoroAngle;
}

- (void)recompute {
    self.annulusGeometry = self.annulusSnapshot ? [TAVIGeometry geometryForWorldContour:self.annulusSnapshot.worldPoints planeNormal:self.annulusSnapshot.planeNormal] : nil;
    self.assistedAnnulusGeometry = self.annulusSnapshot ? [TAVIGeometry assistedAnnulusGeometryForWorldContour:self.annulusSnapshot.worldPoints planeNormal:self.annulusSnapshot.planeNormal] : nil;
    self.lvotGeometry = self.lvotSnapshot ? [TAVIGeometry geometryForWorldContour:self.lvotSnapshot.worldPoints planeNormal:self.lvotSnapshot.planeNormal] : nil;
    self.sinusGeometry = self.sinusSnapshot ? [TAVIGeometry geometryForWorldContour:self.sinusSnapshot.worldPoints planeNormal:self.sinusSnapshot.planeNormal] : nil;
    self.stjGeometry = self.stjSnapshot ? [TAVIGeometry geometryForWorldContour:self.stjSnapshot.worldPoints planeNormal:self.stjSnapshot.planeNormal] : nil;
    self.ascendingAortaGeometry = self.ascendingAortaSnapshot ? [TAVIGeometry geometryForWorldContour:self.ascendingAortaSnapshot.worldPoints planeNormal:self.ascendingAortaSnapshot.planeNormal] : nil;

    self.annulusCalcium = self.annulusSnapshot ? [TAVIGeometry calciumResultForPixelValues:self.annulusSnapshot.pixelValues pixelAreaMm2:self.annulusSnapshot.pixelAreaMm2 thresholdHU:self.calciumThresholdHU] : nil;
    self.lvotCalcium = self.lvotSnapshot ? [TAVIGeometry calciumResultForPixelValues:self.lvotSnapshot.pixelValues pixelAreaMm2:self.lvotSnapshot.pixelAreaMm2 thresholdHU:self.calciumThresholdHU] : nil;
    self.sinusCalcium = self.sinusSnapshot ? [TAVIGeometry calciumResultForPixelValues:self.sinusSnapshot.pixelValues pixelAreaMm2:self.sinusSnapshot.pixelAreaMm2 thresholdHU:self.calciumThresholdHU] : nil;
    self.stjCalcium = self.stjSnapshot ? [TAVIGeometry calciumResultForPixelValues:self.stjSnapshot.pixelValues pixelAreaMm2:self.stjSnapshot.pixelAreaMm2 thresholdHU:self.calciumThresholdHU] : nil;
    self.ascendingAortaCalcium = self.ascendingAortaSnapshot ? [TAVIGeometry calciumResultForPixelValues:self.ascendingAortaSnapshot.pixelValues pixelAreaMm2:self.ascendingAortaSnapshot.pixelAreaMm2 thresholdHU:self.calciumThresholdHU] : nil;

    TAVIGeometryResult *planningAnnulus = [self activeAnnulusGeometry];
    self.fluoroAngle = planningAnnulus ? [TAVIGeometry fluoroAngleForPlaneNormal:planningAnnulus.planeNormal] : nil;
    self.horizontalAortaAngleDegrees = 0.0;
    if (planningAnnulus != nil) {
        double rawAngle = [TAVIGeometry angleBetweenVector:planningAnnulus.planeNormal andVector:TAVIVector3DMake(0.0, 0.0, 1.0)];
        self.horizontalAortaAngleDegrees = rawAngle > 90.0 ? 180.0 - rawAngle : rawAngle;
        if (!self.hasManualVirtualValveDiameter) {
            self.virtualValveDiameterMm = TAVIRoundToHalfMillimeter(planningAnnulus.equivalentDiameterMm);
        }
    }

    self.leftCoronaryHeightMm = nil;
    self.rightCoronaryHeightMm = nil;
    self.membranousSeptumLengthMm = nil;
    if (planningAnnulus != nil && self.leftOstiumSnapshot != nil) {
        double distance = fabs([TAVIGeometry distanceFromPoint:self.leftOstiumSnapshot.worldPoint
                                                 toPlaneOrigin:planningAnnulus.centroid
                                                        normal:planningAnnulus.planeNormal]);
        self.leftCoronaryHeightMm = @(distance);
    }
    if (planningAnnulus != nil && self.rightOstiumSnapshot != nil) {
        double distance = fabs([TAVIGeometry distanceFromPoint:self.rightOstiumSnapshot.worldPoint
                                                 toPlaneOrigin:planningAnnulus.centroid
                                                        normal:planningAnnulus.planeNormal]);
        self.rightCoronaryHeightMm = @(distance);
    }
    if (self.membranousSeptumPointSnapshots.count >= 2) {
        TAVIVector3D first = self.membranousSeptumPointSnapshots[0].worldPoint;
        TAVIVector3D second = self.membranousSeptumPointSnapshots[1].worldPoint;
        self.membranousSeptumLengthMm = @(TAVIVector3DLength(TAVIVector3DSubtract(second, first)));
    }

    self.projectionConfirmation = nil;
    if (planningAnnulus != nil && self.sinusPointSnapshots.count >= 3) {
        NSMutableArray<NSValue *> *worldPoints = [NSMutableArray arrayWithCapacity:self.sinusPointSnapshots.count];
        for (TAVIPointSnapshot *snapshot in self.sinusPointSnapshots) {
            [worldPoints addObject:TAVIValueWithVector3D(snapshot.worldPoint)];
        }
        TAVIVector3D confirmationNormal = [TAVIGeometry planeNormalForWorldPoints:worldPoints];
        self.projectionConfirmation = [TAVIGeometry projectionConfirmationForReferenceNormal:planningAnnulus.planeNormal
                                                                          confirmationNormal:confirmationNormal];
    }
}

- (BOOL)hasRequiredCaptures {
    return self.annulusSnapshot != nil && self.leftOstiumSnapshot != nil && self.rightOstiumSnapshot != nil;
}

- (NSString *)captureCompletenessSummary {
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    if (self.annulusSnapshot == nil) {
        [missing addObject:@"annulus"];
    }
    if (self.leftOstiumSnapshot == nil) {
        [missing addObject:@"left ostium"];
    }
    if (self.rightOstiumSnapshot == nil) {
        [missing addObject:@"right ostium"];
    }
    if (missing.count == 0) {
        return @"Required captures complete";
    }
    return [NSString stringWithFormat:@"Missing required captures: %@", [missing componentsJoinedByString:@", "]];
}

- (NSString *)nextRecommendedStepSummary {
    if (self.ascendingAortaSnapshot == nil) {
        return @"Step 1: capture ascending aorta on a perpendicular MPR plane.";
    }
    if (self.stjSnapshot == nil) {
        return @"Step 2: capture the sino-tubular junction on the next perpendicular plane.";
    }
    if (self.sinusSnapshot == nil) {
        return @"Step 3: capture the sinus of Valsalva contour before annulus planning.";
    }
    if (self.annulusSnapshot == nil) {
        return @"Step 4: capture the annulus contour. This unlocks assisted annulus fitting and advisory angle guidance.";
    }
    if (self.lvotSnapshot == nil) {
        return @"Optional Step 4a: capture the LVOT contour for additional root sizing.";
    }
    if (self.sinusPointSnapshots.count < 3) {
        return @"Optional Step 4b: capture three sinus points to confirm the projection-angle preview, or continue to coronary ostia.";
    }
    if (self.membranousSeptumPointSnapshots.count < 2) {
        return @"Optional Step 4c: capture two membranous septum points if you want the brochure-style septum length measurement.";
    }
    if (self.leftOstiumSnapshot == nil) {
        return @"Step 5: capture the left coronary ostium point.";
    }
    if (self.rightOstiumSnapshot == nil) {
        return @"Step 6: capture the right coronary ostium point.";
    }
    return @"Core workflow complete. Review the assisted annulus, preview angle, calcium assist, and export the report.";
}

- (NSString *)workflowChecklistSummary {
    NSArray<NSString *> *lines = @[
        [NSString stringWithFormat:@"[%@] 1 Ascending aorta", self.ascendingAortaSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 2 STJ", self.stjSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 3 Sinus contour", self.sinusSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 4 Annulus contour", self.annulusSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 4a LVOT contour", self.lvotSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 4b Sinus-point confirmation", self.sinusPointSnapshots.count >= 3 ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 4c Membranous septum", self.membranousSeptumPointSnapshots.count >= 2 ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 5 Left ostium", self.leftOstiumSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"[%@] 6 Right ostium", self.rightOstiumSnapshot ? @"x" : @" "],
        [NSString stringWithFormat:@"Planning source: %@", self.useAssistedAnnulusForPlanning && self.assistedAnnulusGeometry ? @"Assisted annulus fit" : @"Captured annulus contour"]
    ];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)assistedAnnulusSummary {
    if (self.assistedAnnulusGeometry == nil) {
        return @"Capture annulus to compute assisted ellipse fit";
    }
    return [NSString stringWithFormat:@"%@%@",
                                      TAVIFormatGeometrySummary(self.assistedAnnulusGeometry),
                                      self.useAssistedAnnulusForPlanning ? @" [active for planning]" : @""];
}

- (NSString *)projectionConfirmationSummary {
    return TAVIFormatProjectionSummary(self.projectionConfirmation);
}

- (TAVIReportRecord *)reportRecord {
    TAVIReportRecord *record = [[TAVIReportRecord alloc] init];
    record.patientName = TAVISafeString(self.patientName);
    record.patientID = TAVISafeString(self.patientID);
    record.patientUID = TAVISafeString(self.patientUID);
    record.patientBirthDate = TAVISafeString(self.patientBirthDate);
    record.studyInstanceUID = TAVISafeString(self.studyInstanceUID);
    record.reportDate = [NSDate date];
    record.annulusGeometry = self.annulusGeometry;
    record.assistedAnnulusGeometry = self.assistedAnnulusGeometry;
    record.lvotGeometry = self.lvotGeometry;
    record.sinusGeometry = self.sinusGeometry;
    record.stjGeometry = self.stjGeometry;
    record.ascendingAortaGeometry = self.ascendingAortaGeometry;
    record.annulusCalcium = self.annulusCalcium;
    record.lvotCalcium = self.lvotCalcium;
    record.sinusCalcium = self.sinusCalcium;
    record.stjCalcium = self.stjCalcium;
    record.ascendingAortaCalcium = self.ascendingAortaCalcium;
    record.fluoroAngle = self.fluoroAngle;
    record.projectionConfirmation = self.projectionConfirmation;
    record.annulusSeriesUID = self.annulusSnapshot.seriesUID;
    record.lvotSeriesUID = self.lvotSnapshot.seriesUID;
    record.sinusSeriesUID = self.sinusSnapshot.seriesUID;
    record.stjSeriesUID = self.stjSnapshot.seriesUID;
    record.ascendingAortaSeriesUID = self.ascendingAortaSnapshot.seriesUID;
    record.leftOstiumSeriesUID = self.leftOstiumSnapshot.seriesUID;
    record.rightOstiumSeriesUID = self.rightOstiumSnapshot.seriesUID;
    record.leftCoronaryHeightMm = self.leftCoronaryHeightMm;
    record.rightCoronaryHeightMm = self.rightCoronaryHeightMm;
    record.membranousSeptumLengthMm = self.membranousSeptumLengthMm;
    record.cuspCalcificationGrade = self.cuspCalcificationGrade;
    record.annulusCalcificationGrade = self.annulusCalcificationGrade;
    record.calciumThresholdHU = self.calciumThresholdHU;
    record.horizontalAortaAngleDegrees = self.horizontalAortaAngleDegrees;
    record.virtualValveDiameterMm = self.virtualValveDiameterMm;
    record.usingAssistedAnnulusForPlanning = self.useAssistedAnnulusForPlanning && self.assistedAnnulusGeometry != nil;
    record.notes = self.notes ?: @"";
    return record;
}

@end
