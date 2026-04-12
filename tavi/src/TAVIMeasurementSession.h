#import <Foundation/Foundation.h>

#import "TAVIGeometry.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const TAVIStructureAnnulus;
FOUNDATION_EXPORT NSString * const TAVIStructureLeftOstium;
FOUNDATION_EXPORT NSString * const TAVIStructureRightOstium;
FOUNDATION_EXPORT NSString * const TAVIStructureSinus;
FOUNDATION_EXPORT NSString * const TAVIStructureSTJ;
FOUNDATION_EXPORT NSString * const TAVIStructureAscendingAorta;
FOUNDATION_EXPORT NSString * const TAVIStructureSinusPoints;
FOUNDATION_EXPORT NSString * const TAVIStructureLVOT;
FOUNDATION_EXPORT NSString * const TAVIStructureMembranousSeptum;

@interface TAVIContourSnapshot : NSObject <NSCopying>
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *seriesUID;
@property (nonatomic, copy) NSString *seriesDescription;
@property (nonatomic, copy) NSString *studyInstanceUID;
@property (nonatomic, copy) NSString *patientName;
@property (nonatomic, copy) NSString *patientID;
@property (nonatomic, copy) NSString *patientUID;
@property (nonatomic, copy) NSString *patientBirthDate;
@property (nonatomic, copy) NSArray<NSValue *> *pixelPoints;
@property (nonatomic, copy) NSArray<NSValue *> *worldPoints;
@property (nonatomic, copy) NSData *pixelValues;
@property (nonatomic) double pixelAreaMm2;
@property (nonatomic) short roiType;
@property (nonatomic) NSInteger sliceIndex;
@property (nonatomic) TAVIVector3D planeOrigin;
@property (nonatomic) TAVIVector3D planeNormal;
@end

@interface TAVIPointSnapshot : NSObject <NSCopying>
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *seriesUID;
@property (nonatomic, copy) NSString *seriesDescription;
@property (nonatomic, copy) NSString *studyInstanceUID;
@property (nonatomic, copy) NSString *patientName;
@property (nonatomic, copy) NSString *patientID;
@property (nonatomic, copy) NSString *patientUID;
@property (nonatomic, copy) NSString *patientBirthDate;
@property (nonatomic) NSPoint pixelPoint;
@property (nonatomic) NSInteger sliceIndex;
@property (nonatomic) short roiType;
@property (nonatomic) TAVIVector3D worldPoint;
@end

@interface TAVIReportRecord : NSObject
@property (nonatomic, copy) NSString *patientName;
@property (nonatomic, copy) NSString *patientID;
@property (nonatomic, copy) NSString *patientUID;
@property (nonatomic, copy) NSString *patientBirthDate;
@property (nonatomic, copy) NSString *studyInstanceUID;
@property (nonatomic, strong) NSDate *reportDate;
@property (nonatomic, strong, nullable) TAVIGeometryResult *annulusGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *assistedAnnulusGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *lvotGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *sinusGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *stjGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *ascendingAortaGeometry;
@property (nonatomic, strong, nullable) TAVICalciumResult *annulusCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *lvotCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *sinusCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *stjCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *ascendingAortaCalcium;
@property (nonatomic, strong, nullable) TAVIFluoroAngleResult *fluoroAngle;
@property (nonatomic, strong, nullable) TAVIProjectionConfirmationResult *projectionConfirmation;
@property (nonatomic, copy, nullable) NSString *annulusSeriesUID;
@property (nonatomic, copy, nullable) NSString *lvotSeriesUID;
@property (nonatomic, copy, nullable) NSString *sinusSeriesUID;
@property (nonatomic, copy, nullable) NSString *stjSeriesUID;
@property (nonatomic, copy, nullable) NSString *ascendingAortaSeriesUID;
@property (nonatomic, copy, nullable) NSString *leftOstiumSeriesUID;
@property (nonatomic, copy, nullable) NSString *rightOstiumSeriesUID;
@property (nonatomic, nullable) NSNumber *leftCoronaryHeightMm;
@property (nonatomic, nullable) NSNumber *rightCoronaryHeightMm;
@property (nonatomic, nullable) NSNumber *membranousSeptumLengthMm;
@property (nonatomic) NSInteger cuspCalcificationGrade;
@property (nonatomic) NSInteger annulusCalcificationGrade;
@property (nonatomic) double calciumThresholdHU;
@property (nonatomic) double horizontalAortaAngleDegrees;
@property (nonatomic) double virtualValveDiameterMm;
@property (nonatomic) BOOL usingAssistedAnnulusForPlanning;
@property (nonatomic, copy) NSString *notes;
- (NSString *)textReport;
- (NSString *)csvReport;
@end

@interface TAVIMeasurementSession : NSObject
@property (nonatomic) double calciumThresholdHU;
@property (nonatomic) NSInteger cuspCalcificationGrade;
@property (nonatomic) NSInteger annulusCalcificationGrade;
@property (nonatomic) BOOL useAssistedAnnulusForPlanning;
@property (nonatomic, copy) NSString *notes;

@property (nonatomic, copy, nullable) NSString *patientName;
@property (nonatomic, copy, nullable) NSString *patientID;
@property (nonatomic, copy, nullable) NSString *patientUID;
@property (nonatomic, copy, nullable) NSString *patientBirthDate;
@property (nonatomic, copy, nullable) NSString *studyInstanceUID;

@property (nonatomic, strong, nullable) TAVIContourSnapshot *annulusSnapshot;
@property (nonatomic, strong, nullable) TAVIPointSnapshot *leftOstiumSnapshot;
@property (nonatomic, strong, nullable) TAVIPointSnapshot *rightOstiumSnapshot;
@property (nonatomic, strong, nullable) TAVIContourSnapshot *sinusSnapshot;
@property (nonatomic, strong, nullable) TAVIContourSnapshot *stjSnapshot;
@property (nonatomic, strong, nullable) TAVIContourSnapshot *ascendingAortaSnapshot;
@property (nonatomic, strong, nullable) TAVIContourSnapshot *lvotSnapshot;
@property (nonatomic, copy) NSArray<TAVIPointSnapshot *> *sinusPointSnapshots;
@property (nonatomic, copy) NSArray<TAVIPointSnapshot *> *membranousSeptumPointSnapshots;

@property (nonatomic, strong, nullable) TAVIGeometryResult *annulusGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *assistedAnnulusGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *lvotGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *sinusGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *stjGeometry;
@property (nonatomic, strong, nullable) TAVIGeometryResult *ascendingAortaGeometry;
@property (nonatomic, strong, nullable) TAVICalciumResult *annulusCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *lvotCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *sinusCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *stjCalcium;
@property (nonatomic, strong, nullable) TAVICalciumResult *ascendingAortaCalcium;
@property (nonatomic, strong, nullable) TAVIFluoroAngleResult *fluoroAngle;
@property (nonatomic, strong, nullable) TAVIProjectionConfirmationResult *projectionConfirmation;
@property (nonatomic, nullable) NSNumber *leftCoronaryHeightMm;
@property (nonatomic, nullable) NSNumber *rightCoronaryHeightMm;
@property (nonatomic, nullable) NSNumber *membranousSeptumLengthMm;
@property (nonatomic) double horizontalAortaAngleDegrees;
@property (nonatomic) double virtualValveDiameterMm;
@property (nonatomic) BOOL hasManualVirtualValveDiameter;

- (void)captureContourSnapshot:(TAVIContourSnapshot *)snapshot forIdentifier:(NSString *)identifier;
- (void)capturePointSnapshot:(TAVIPointSnapshot *)snapshot forIdentifier:(NSString *)identifier;
- (void)capturePointSnapshots:(NSArray<TAVIPointSnapshot *> *)snapshots forIdentifier:(NSString *)identifier;
- (void)recompute;
- (BOOL)hasRequiredCaptures;
- (NSString *)captureCompletenessSummary;
- (NSString *)nextRecommendedStepSummary;
- (NSString *)workflowChecklistSummary;
- (NSString *)assistedAnnulusSummary;
- (NSString *)projectionConfirmationSummary;
- (nullable TAVIGeometryResult *)activeAnnulusGeometry;
- (nullable TAVIFluoroAngleResult *)preferredProjectionAngle;
- (TAVIReportRecord *)reportRecord;
@end

NS_ASSUME_NONNULL_END
