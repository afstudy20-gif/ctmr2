#import <Foundation/Foundation.h>

#import "TAVITypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface TAVIGeometryResult : NSObject <NSCopying>
@property (nonatomic) double perimeterMm;
@property (nonatomic) double areaMm2;
@property (nonatomic) double equivalentDiameterMm;
@property (nonatomic) double minimumDiameterMm;
@property (nonatomic) double maximumDiameterMm;
@property (nonatomic) TAVIVector3D centroid;
@property (nonatomic) TAVIVector3D planeNormal;
@property (nonatomic) TAVIVector3D majorAxisDirection;
@property (nonatomic) TAVIVector3D minorAxisDirection;
@end

@interface TAVICalciumResult : NSObject <NSCopying>
@property (nonatomic) double thresholdHU;
@property (nonatomic) double totalAreaMm2;
@property (nonatomic) double hyperdenseAreaMm2;
@property (nonatomic) double fractionAboveThreshold;
@property (nonatomic) double agatstonScore2D;
@property (nonatomic) NSUInteger totalSamples;
@property (nonatomic) NSUInteger samplesAboveThreshold;
@end

@interface TAVIFluoroAngleResult : NSObject <NSCopying>
@property (nonatomic) double laoRaoDegrees;
@property (nonatomic) double cranialCaudalDegrees;
@property (nonatomic, copy) NSString *laoRaoLabel;
@property (nonatomic, copy) NSString *cranialCaudalLabel;
@property (nonatomic) TAVIVector3D planeNormal;
- (NSString *)advisorySummary;
@end

@interface TAVIProjectionConfirmationResult : NSObject <NSCopying>
@property (nonatomic) TAVIVector3D confirmationNormal;
@property (nonatomic, strong) TAVIFluoroAngleResult *confirmationAngle;
@property (nonatomic) double normalDifferenceDegrees;
@property (nonatomic) double laoRaoDifferenceDegrees;
@property (nonatomic) double cranialCaudalDifferenceDegrees;
- (NSString *)summary;
@end

@interface TAVIGeometry : NSObject
+ (nullable TAVIGeometryResult *)geometryForWorldContour:(NSArray<NSValue *> *)worldPoints
                                            planeNormal:(TAVIVector3D)planeNormal;
+ (nullable TAVIGeometryResult *)assistedAnnulusGeometryForWorldContour:(NSArray<NSValue *> *)worldPoints
                                                           planeNormal:(TAVIVector3D)planeNormal;
+ (double)distanceFromPoint:(TAVIVector3D)point
              toPlaneOrigin:(TAVIVector3D)origin
                     normal:(TAVIVector3D)normal;
+ (TAVIFluoroAngleResult *)fluoroAngleForPlaneNormal:(TAVIVector3D)planeNormal;
+ (nullable TAVIProjectionConfirmationResult *)projectionConfirmationForReferenceNormal:(TAVIVector3D)referenceNormal
                                                                     confirmationNormal:(TAVIVector3D)confirmationNormal;
+ (TAVICalciumResult *)calciumResultForPixelValues:(NSData *)pixelValues
                                       pixelAreaMm2:(double)pixelAreaMm2
                                        thresholdHU:(double)thresholdHU;
+ (TAVIVector3D)planeNormalForWorldPoints:(NSArray<NSValue *> *)worldPoints;
+ (double)angleBetweenVector:(TAVIVector3D)lhs andVector:(TAVIVector3D)rhs;
+ (TAVIPoint2D)projectWorldPoint:(TAVIVector3D)worldPoint
                      planeOrigin:(TAVIVector3D)planeOrigin
                      planeNormal:(TAVIVector3D)planeNormal;
+ (NSArray<NSValue *> *)projectWorldPoints:(NSArray<NSValue *> *)worldPoints
                               planeOrigin:(TAVIVector3D)planeOrigin
                               planeNormal:(TAVIVector3D)planeNormal;
@end

NS_ASSUME_NONNULL_END
