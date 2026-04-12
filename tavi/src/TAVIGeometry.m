#import "TAVIGeometry.h"

#include <string.h>

static const double kTAVIGeometryEpsilon = 1.0e-9;

typedef struct {
    double x;
    double y;
} TAVIInternalPoint2D;

typedef struct {
    TAVIVector3D basisU;
    TAVIVector3D basisV;
    TAVIVector3D normal;
} TAVIPlaneBasis;

typedef struct {
    double area;
    double perimeter;
    double minimumDiameter;
    double maximumDiameter;
    TAVIVector3D centroid;
    TAVIVector3D normal;
    TAVIVector3D majorAxisDirection;
    TAVIVector3D minorAxisDirection;
} TAVIGeometryComputation;

@implementation TAVIGeometryResult

- (id)copyWithZone:(NSZone *)zone {
    TAVIGeometryResult *copy = [[[self class] allocWithZone:zone] init];
    copy.perimeterMm = self.perimeterMm;
    copy.areaMm2 = self.areaMm2;
    copy.equivalentDiameterMm = self.equivalentDiameterMm;
    copy.minimumDiameterMm = self.minimumDiameterMm;
    copy.maximumDiameterMm = self.maximumDiameterMm;
    copy.centroid = self.centroid;
    copy.planeNormal = self.planeNormal;
    copy.majorAxisDirection = self.majorAxisDirection;
    copy.minorAxisDirection = self.minorAxisDirection;
    return copy;
}

@end

@implementation TAVICalciumResult

- (id)copyWithZone:(NSZone *)zone {
    TAVICalciumResult *copy = [[[self class] allocWithZone:zone] init];
    copy.thresholdHU = self.thresholdHU;
    copy.totalAreaMm2 = self.totalAreaMm2;
    copy.hyperdenseAreaMm2 = self.hyperdenseAreaMm2;
    copy.fractionAboveThreshold = self.fractionAboveThreshold;
    copy.agatstonScore2D = self.agatstonScore2D;
    copy.totalSamples = self.totalSamples;
    copy.samplesAboveThreshold = self.samplesAboveThreshold;
    return copy;
}

@end

@implementation TAVIFluoroAngleResult

- (id)copyWithZone:(NSZone *)zone {
    TAVIFluoroAngleResult *copy = [[[self class] allocWithZone:zone] init];
    copy.laoRaoDegrees = self.laoRaoDegrees;
    copy.cranialCaudalDegrees = self.cranialCaudalDegrees;
    copy.laoRaoLabel = self.laoRaoLabel;
    copy.cranialCaudalLabel = self.cranialCaudalLabel;
    copy.planeNormal = self.planeNormal;
    return copy;
}

- (NSString *)advisorySummary {
    return [NSString stringWithFormat:@"%@ %.1f / %@ %.1f (normal %@)",
                                      self.laoRaoLabel,
                                      self.laoRaoDegrees,
                                      self.cranialCaudalLabel,
                                      self.cranialCaudalDegrees,
                                      TAVIStringFromVector3D(self.planeNormal)];
}

@end

@implementation TAVIProjectionConfirmationResult

- (id)copyWithZone:(NSZone *)zone {
    TAVIProjectionConfirmationResult *copy = [[[self class] allocWithZone:zone] init];
    copy.confirmationNormal = self.confirmationNormal;
    copy.confirmationAngle = [self.confirmationAngle copy];
    copy.normalDifferenceDegrees = self.normalDifferenceDegrees;
    copy.laoRaoDifferenceDegrees = self.laoRaoDifferenceDegrees;
    copy.cranialCaudalDifferenceDegrees = self.cranialCaudalDifferenceDegrees;
    return copy;
}

- (NSString *)summary {
    return [NSString stringWithFormat:@"%@, delta %.1f deg (LAO/RAO %.1f, cran/caud %.1f)",
                                      [self.confirmationAngle advisorySummary],
                                      self.normalDifferenceDegrees,
                                      self.laoRaoDifferenceDegrees,
                                      self.cranialCaudalDifferenceDegrees];
}

@end

static double TAVICross2D(TAVIInternalPoint2D origin, TAVIInternalPoint2D a, TAVIInternalPoint2D b) {
    return ((a.x - origin.x) * (b.y - origin.y)) - ((a.y - origin.y) * (b.x - origin.x));
}

static double TAVIDistance2D(TAVIInternalPoint2D a, TAVIInternalPoint2D b) {
    double dx = a.x - b.x;
    double dy = a.y - b.y;
    return sqrt((dx * dx) + (dy * dy));
}

static NSComparisonResult TAVIComparePoint2D(TAVIInternalPoint2D a, TAVIInternalPoint2D b) {
    if (fabs(a.x - b.x) > kTAVIGeometryEpsilon) {
        return a.x < b.x ? NSOrderedAscending : NSOrderedDescending;
    }
    if (fabs(a.y - b.y) > kTAVIGeometryEpsilon) {
        return a.y < b.y ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

static TAVIInternalPoint2D TAVIInternalPoint2DFromValue(NSValue *value) {
    TAVIPoint2D point = TAVIPoint2DFromValue(value);
    TAVIInternalPoint2D internalPoint = {point.x, point.y};
    return internalPoint;
}

static NSArray<NSValue *> *TAVISanitizedWorldPoints(NSArray<NSValue *> *worldPoints) {
    NSMutableArray<NSValue *> *sanitized = [worldPoints mutableCopy];
    if (sanitized.count > 3) {
        TAVIVector3D first = TAVIVector3DFromValue(sanitized.firstObject);
        TAVIVector3D last = TAVIVector3DFromValue(sanitized.lastObject);
        if (TAVIVector3DLength(TAVIVector3DSubtract(first, last)) < 1.0e-6) {
            [sanitized removeLastObject];
        }
    }
    return sanitized;
}

static TAVIVector3D TAVIFallbackNormalForWorldPoints(NSArray<NSValue *> *worldPoints) {
    if (worldPoints.count < 3) {
        return TAVIVector3DMake(0.0, 0.0, 1.0);
    }

    TAVIVector3D origin = TAVIVector3DFromValue(worldPoints[0]);
    for (NSUInteger idx = 1; idx + 1 < worldPoints.count; idx++) {
        TAVIVector3D a = TAVIVector3DSubtract(TAVIVector3DFromValue(worldPoints[idx]), origin);
        TAVIVector3D b = TAVIVector3DSubtract(TAVIVector3DFromValue(worldPoints[idx + 1]), origin);
        TAVIVector3D cross = TAVIVector3DCross(a, b);
        if (!TAVIVector3DIsZero(cross)) {
            return TAVIVector3DNormalize(cross);
        }
    }
    return TAVIVector3DMake(0.0, 0.0, 1.0);
}

static TAVIPlaneBasis TAVIPlaneBasisMake(TAVIVector3D planeNormal) {
    TAVIPlaneBasis basis;
    basis.normal = TAVIVector3DNormalize(planeNormal);
    if (TAVIVector3DIsZero(basis.normal)) {
        basis.normal = TAVIVector3DMake(0.0, 0.0, 1.0);
    }

    TAVIVector3D helper = fabs(basis.normal.z) < 0.9 ? TAVIVector3DMake(0.0, 0.0, 1.0) : TAVIVector3DMake(0.0, 1.0, 0.0);
    basis.basisU = TAVIVector3DNormalize(TAVIVector3DCross(helper, basis.normal));
    if (TAVIVector3DIsZero(basis.basisU)) {
        basis.basisU = TAVIVector3DNormalize(TAVIVector3DCross(TAVIVector3DMake(1.0, 0.0, 0.0), basis.normal));
    }
    basis.basisV = TAVIVector3DNormalize(TAVIVector3DCross(basis.normal, basis.basisU));
    return basis;
}

static TAVIPoint2D TAVIProjectWorldPointWithBasis(TAVIVector3D worldPoint,
                                                  TAVIVector3D planeOrigin,
                                                  TAVIPlaneBasis basis) {
    TAVIVector3D delta = TAVIVector3DSubtract(worldPoint, planeOrigin);
    return TAVIPoint2DMake(TAVIVector3DDot(delta, basis.basisU), TAVIVector3DDot(delta, basis.basisV));
}

static NSArray<NSValue *> *TAVIProjectWorldPointsWithBasis(NSArray<NSValue *> *worldPoints,
                                                           TAVIVector3D planeOrigin,
                                                           TAVIPlaneBasis basis) {
    NSMutableArray<NSValue *> *projected = [NSMutableArray arrayWithCapacity:worldPoints.count];
    for (NSValue *value in worldPoints) {
        [projected addObject:TAVIValueWithPoint2D(TAVIProjectWorldPointWithBasis(TAVIVector3DFromValue(value), planeOrigin, basis))];
    }
    return projected;
}

static NSArray<NSValue *> *TAVIConvexHull(NSArray<NSValue *> *points) {
    if (points.count <= 3) {
        return points;
    }

    NSArray<NSValue *> *sorted = [points sortedArrayUsingComparator:^NSComparisonResult(NSValue *lhs, NSValue *rhs) {
        return TAVIComparePoint2D(TAVIInternalPoint2DFromValue(lhs), TAVIInternalPoint2DFromValue(rhs));
    }];

    NSMutableArray<NSValue *> *lower = [NSMutableArray array];
    for (NSValue *value in sorted) {
        while (lower.count >= 2) {
            TAVIPoint2D a2 = TAVIPoint2DFromValue(lower[lower.count - 2]);
            TAVIPoint2D b2 = TAVIPoint2DFromValue(lower[lower.count - 1]);
            TAVIPoint2D c2 = TAVIPoint2DFromValue(value);
            TAVIInternalPoint2D a = {a2.x, a2.y};
            TAVIInternalPoint2D b = {b2.x, b2.y};
            TAVIInternalPoint2D c = {c2.x, c2.y};
            if (TAVICross2D(a, b, c) > 0.0) {
                break;
            }
            [lower removeLastObject];
        }
        [lower addObject:value];
    }

    NSMutableArray<NSValue *> *upper = [NSMutableArray array];
    for (NSValue *value in [sorted reverseObjectEnumerator]) {
        while (upper.count >= 2) {
            TAVIPoint2D a2 = TAVIPoint2DFromValue(upper[upper.count - 2]);
            TAVIPoint2D b2 = TAVIPoint2DFromValue(upper[upper.count - 1]);
            TAVIPoint2D c2 = TAVIPoint2DFromValue(value);
            TAVIInternalPoint2D a = {a2.x, a2.y};
            TAVIInternalPoint2D b = {b2.x, b2.y};
            TAVIInternalPoint2D c = {c2.x, c2.y};
            if (TAVICross2D(a, b, c) > 0.0) {
                break;
            }
            [upper removeLastObject];
        }
        [upper addObject:value];
    }

    [lower removeLastObject];
    [upper removeLastObject];

    NSMutableArray<NSValue *> *hull = [NSMutableArray arrayWithArray:lower];
    [hull addObjectsFromArray:upper];
    return hull;
}

static BOOL TAVICalculatePrincipalAxes(NSArray<NSValue *> *projectedPoints,
                                       TAVIPlaneBasis basis,
                                       TAVIVector3D *majorAxisDirection,
                                       TAVIVector3D *minorAxisDirection,
                                       double *axisRatio) {
    if (projectedPoints.count < 2) {
        return NO;
    }

    double meanX = 0.0;
    double meanY = 0.0;
    for (NSValue *value in projectedPoints) {
        TAVIPoint2D point = TAVIPoint2DFromValue(value);
        meanX += point.x;
        meanY += point.y;
    }
    meanX /= (double)projectedPoints.count;
    meanY /= (double)projectedPoints.count;

    double sxx = 0.0;
    double syy = 0.0;
    double sxy = 0.0;
    for (NSValue *value in projectedPoints) {
        TAVIPoint2D point = TAVIPoint2DFromValue(value);
        double dx = point.x - meanX;
        double dy = point.y - meanY;
        sxx += dx * dx;
        syy += dy * dy;
        sxy += dx * dy;
    }
    sxx /= (double)projectedPoints.count;
    syy /= (double)projectedPoints.count;
    sxy /= (double)projectedPoints.count;

    double trace = sxx + syy;
    double determinantTerm = sqrt(MAX(0.0, ((sxx - syy) * (sxx - syy)) + (4.0 * sxy * sxy)));
    double lambda1 = MAX(0.0, (trace + determinantTerm) * 0.5);
    double lambda2 = MAX(0.0, (trace - determinantTerm) * 0.5);

    double vx = 1.0;
    double vy = 0.0;
    if (fabs(sxy) > kTAVIGeometryEpsilon || fabs(lambda1 - sxx) > kTAVIGeometryEpsilon) {
        vx = sxy;
        vy = lambda1 - sxx;
        double length = hypot(vx, vy);
        if (length > kTAVIGeometryEpsilon) {
            vx /= length;
            vy /= length;
        } else {
            vx = 1.0;
            vy = 0.0;
        }
    }

    TAVIVector3D majorWorld = TAVIVector3DNormalize(TAVIVector3DAdd(TAVIVector3DScale(basis.basisU, vx),
                                                                    TAVIVector3DScale(basis.basisV, vy)));
    TAVIVector3D minorWorld = TAVIVector3DNormalize(TAVIVector3DCross(basis.normal, majorWorld));
    if (TAVIVector3DIsZero(minorWorld)) {
        minorWorld = basis.basisV;
    }

    if (majorAxisDirection != NULL) {
        *majorAxisDirection = majorWorld;
    }
    if (minorAxisDirection != NULL) {
        *minorAxisDirection = minorWorld;
    }
    if (axisRatio != NULL) {
        if (lambda2 <= kTAVIGeometryEpsilon) {
            *axisRatio = 1.0;
        } else {
            *axisRatio = MAX(1.0, sqrt(lambda1 / lambda2));
        }
    }
    return YES;
}

static TAVIGeometryComputation TAVICalculateContourGeometry(NSArray<NSValue *> *worldPoints, TAVIVector3D planeNormal) {
    TAVIGeometryComputation computation;
    memset(&computation, 0, sizeof(computation));

    NSArray<NSValue *> *sanitized = TAVISanitizedWorldPoints(worldPoints);
    computation.normal = TAVIVector3DNormalize(planeNormal);
    if (TAVIVector3DIsZero(computation.normal)) {
        computation.normal = TAVIFallbackNormalForWorldPoints(sanitized);
    }

    for (NSValue *value in sanitized) {
        computation.centroid = TAVIVector3DAdd(computation.centroid, TAVIVector3DFromValue(value));
    }
    computation.centroid = sanitized.count > 0 ? TAVIVector3DScale(computation.centroid, 1.0 / (double)sanitized.count) : TAVIVector3DMake(0.0, 0.0, 0.0);

    TAVIPlaneBasis basis = TAVIPlaneBasisMake(computation.normal);
    NSArray<NSValue *> *projected = TAVIProjectWorldPointsWithBasis(sanitized, computation.centroid, basis);

    for (NSUInteger idx = 0; idx < projected.count; idx++) {
        TAVIPoint2D currentPoint = TAVIPoint2DFromValue(projected[idx]);
        TAVIPoint2D nextPoint = TAVIPoint2DFromValue(projected[(idx + 1) % projected.count]);
        TAVIInternalPoint2D current = {currentPoint.x, currentPoint.y};
        TAVIInternalPoint2D next = {nextPoint.x, nextPoint.y};
        computation.perimeter += TAVIDistance2D(current, next);
        computation.area += ((current.x * next.y) - (next.x * current.y));
    }
    computation.area = fabs(computation.area) * 0.5;

    NSArray<NSValue *> *hull = TAVIConvexHull(projected);
    for (NSUInteger i = 0; i < hull.count; i++) {
        TAVIPoint2D aPoint = TAVIPoint2DFromValue(hull[i]);
        TAVIInternalPoint2D a = {aPoint.x, aPoint.y};
        for (NSUInteger j = i + 1; j < hull.count; j++) {
            TAVIPoint2D bPoint = TAVIPoint2DFromValue(hull[j]);
            TAVIInternalPoint2D b = {bPoint.x, bPoint.y};
            computation.maximumDiameter = MAX(computation.maximumDiameter, TAVIDistance2D(a, b));
        }
    }

    computation.minimumDiameter = DBL_MAX;
    if (hull.count >= 2) {
        for (NSUInteger idx = 0; idx < hull.count; idx++) {
            TAVIPoint2D aPoint = TAVIPoint2DFromValue(hull[idx]);
            TAVIPoint2D bPoint = TAVIPoint2DFromValue(hull[(idx + 1) % hull.count]);
            TAVIInternalPoint2D a = {aPoint.x, aPoint.y};
            TAVIInternalPoint2D b = {bPoint.x, bPoint.y};
            double edgeLength = TAVIDistance2D(a, b);
            if (edgeLength <= kTAVIGeometryEpsilon) {
                continue;
            }

            double nx = -(b.y - a.y) / edgeLength;
            double ny = (b.x - a.x) / edgeLength;
            double minProjection = DBL_MAX;
            double maxProjection = -DBL_MAX;

            for (NSValue *value in hull) {
                TAVIPoint2D point2D = TAVIPoint2DFromValue(value);
                double projection = (point2D.x * nx) + (point2D.y * ny);
                minProjection = MIN(minProjection, projection);
                maxProjection = MAX(maxProjection, projection);
            }
            computation.minimumDiameter = MIN(computation.minimumDiameter, maxProjection - minProjection);
        }
    }
    if (computation.minimumDiameter == DBL_MAX) {
        computation.minimumDiameter = 0.0;
    }

    TAVICalculatePrincipalAxes(projected, basis, &computation.majorAxisDirection, &computation.minorAxisDirection, NULL);
    return computation;
}

static TAVIGeometryResult *TAVIGeometryResultFromComputation(TAVIGeometryComputation computation) {
    TAVIGeometryResult *result = [[TAVIGeometryResult alloc] init];
    result.perimeterMm = computation.perimeter;
    result.areaMm2 = computation.area;
    result.equivalentDiameterMm = computation.area > 0.0 ? (2.0 * sqrt(computation.area / M_PI)) : 0.0;
    result.minimumDiameterMm = computation.minimumDiameter;
    result.maximumDiameterMm = computation.maximumDiameter;
    result.centroid = computation.centroid;
    result.planeNormal = computation.normal;
    result.majorAxisDirection = computation.majorAxisDirection;
    result.minorAxisDirection = computation.minorAxisDirection;
    return result;
}

@implementation TAVIGeometry

+ (TAVIGeometryResult *)geometryForWorldContour:(NSArray<NSValue *> *)worldPoints
                                    planeNormal:(TAVIVector3D)planeNormal {
    if (worldPoints.count < 3) {
        return nil;
    }

    TAVIGeometryComputation computation = TAVICalculateContourGeometry(worldPoints, planeNormal);
    if (computation.area <= 0.0) {
        return nil;
    }
    return TAVIGeometryResultFromComputation(computation);
}

+ (TAVIGeometryResult *)assistedAnnulusGeometryForWorldContour:(NSArray<NSValue *> *)worldPoints
                                                   planeNormal:(TAVIVector3D)planeNormal {
    if (worldPoints.count < 3) {
        return nil;
    }

    NSArray<NSValue *> *sanitized = TAVISanitizedWorldPoints(worldPoints);
    TAVIVector3D normal = TAVIVector3DNormalize(planeNormal);
    if (TAVIVector3DIsZero(normal)) {
        normal = TAVIFallbackNormalForWorldPoints(sanitized);
    }

    TAVIVector3D centroid = TAVIVector3DMake(0.0, 0.0, 0.0);
    for (NSValue *value in sanitized) {
        centroid = TAVIVector3DAdd(centroid, TAVIVector3DFromValue(value));
    }
    centroid = TAVIVector3DScale(centroid, 1.0 / (double)sanitized.count);

    TAVIPlaneBasis basis = TAVIPlaneBasisMake(normal);
    NSArray<NSValue *> *projected = TAVIProjectWorldPointsWithBasis(sanitized, centroid, basis);
    if (projected.count < 3) {
        return nil;
    }

    double area = 0.0;
    for (NSUInteger idx = 0; idx < projected.count; idx++) {
        TAVIPoint2D current = TAVIPoint2DFromValue(projected[idx]);
        TAVIPoint2D next = TAVIPoint2DFromValue(projected[(idx + 1) % projected.count]);
        area += (current.x * next.y) - (next.x * current.y);
    }
    area = fabs(area) * 0.5;
    if (area <= 0.0) {
        return nil;
    }

    TAVIVector3D majorAxisDirection = basis.basisU;
    TAVIVector3D minorAxisDirection = basis.basisV;
    double axisRatio = 1.0;
    TAVICalculatePrincipalAxes(projected, basis, &majorAxisDirection, &minorAxisDirection, &axisRatio);
    axisRatio = MAX(axisRatio, 1.0);

    double majorDiameter = 2.0 * sqrt((area * axisRatio) / M_PI);
    double minorDiameter = 2.0 * sqrt(area / (M_PI * axisRatio));
    double semiMajor = majorDiameter * 0.5;
    double semiMinor = minorDiameter * 0.5;
    double h = pow(semiMajor - semiMinor, 2.0) / pow(semiMajor + semiMinor, 2.0);
    double perimeter = M_PI * (semiMajor + semiMinor) * (1.0 + (3.0 * h) / (10.0 + sqrt(MAX(0.0, 4.0 - (3.0 * h)))));

    TAVIGeometryResult *result = [[TAVIGeometryResult alloc] init];
    result.perimeterMm = perimeter;
    result.areaMm2 = area;
    result.equivalentDiameterMm = 2.0 * sqrt(area / M_PI);
    result.minimumDiameterMm = minorDiameter;
    result.maximumDiameterMm = majorDiameter;
    result.centroid = centroid;
    result.planeNormal = normal;
    result.majorAxisDirection = majorAxisDirection;
    result.minorAxisDirection = minorAxisDirection;
    return result;
}

+ (double)distanceFromPoint:(TAVIVector3D)point
              toPlaneOrigin:(TAVIVector3D)origin
                     normal:(TAVIVector3D)normal {
    TAVIVector3D normalizedNormal = TAVIVector3DNormalize(normal);
    if (TAVIVector3DIsZero(normalizedNormal)) {
        return 0.0;
    }
    return TAVIVector3DDot(TAVIVector3DSubtract(point, origin), normalizedNormal);
}

+ (TAVIFluoroAngleResult *)fluoroAngleForPlaneNormal:(TAVIVector3D)planeNormal {
    TAVIVector3D normal = TAVIVector3DNormalize(planeNormal);
    if (TAVIVector3DIsZero(normal)) {
        normal = TAVIVector3DMake(0.0, 1.0, 0.0);
    }

    double laoRao = atan2(normal.x, normal.y) * 180.0 / M_PI;
    double cranialCaudal = atan2(normal.z, hypot(normal.x, normal.y)) * 180.0 / M_PI;

    TAVIFluoroAngleResult *result = [[TAVIFluoroAngleResult alloc] init];
    result.laoRaoLabel = laoRao >= 0.0 ? @"LAO" : @"RAO";
    result.cranialCaudalLabel = cranialCaudal >= 0.0 ? @"CRANIAL" : @"CAUDAL";
    result.laoRaoDegrees = fabs(laoRao);
    result.cranialCaudalDegrees = fabs(cranialCaudal);
    result.planeNormal = normal;
    return result;
}

+ (TAVIProjectionConfirmationResult *)projectionConfirmationForReferenceNormal:(TAVIVector3D)referenceNormal
                                                            confirmationNormal:(TAVIVector3D)confirmationNormal {
    TAVIVector3D normalizedReference = TAVIVector3DNormalize(referenceNormal);
    TAVIVector3D normalizedConfirmation = TAVIVector3DNormalize(confirmationNormal);
    if (TAVIVector3DIsZero(normalizedReference) || TAVIVector3DIsZero(normalizedConfirmation)) {
        return nil;
    }

    TAVIVector3D invertedConfirmation = TAVIVector3DScale(normalizedConfirmation, -1.0);
    if ([self angleBetweenVector:normalizedReference andVector:invertedConfirmation] <
        [self angleBetweenVector:normalizedReference andVector:normalizedConfirmation]) {
        normalizedConfirmation = invertedConfirmation;
    }

    TAVIFluoroAngleResult *referenceAngle = [self fluoroAngleForPlaneNormal:normalizedReference];
    TAVIFluoroAngleResult *confirmationAngle = [self fluoroAngleForPlaneNormal:normalizedConfirmation];

    TAVIProjectionConfirmationResult *result = [[TAVIProjectionConfirmationResult alloc] init];
    result.confirmationNormal = normalizedConfirmation;
    result.confirmationAngle = confirmationAngle;
    result.normalDifferenceDegrees = [self angleBetweenVector:normalizedReference andVector:normalizedConfirmation];
    result.laoRaoDifferenceDegrees = fabs(referenceAngle.laoRaoDegrees - confirmationAngle.laoRaoDegrees);
    result.cranialCaudalDifferenceDegrees = fabs(referenceAngle.cranialCaudalDegrees - confirmationAngle.cranialCaudalDegrees);
    return result;
}

+ (TAVICalciumResult *)calciumResultForPixelValues:(NSData *)pixelValues
                                       pixelAreaMm2:(double)pixelAreaMm2
                                        thresholdHU:(double)thresholdHU {
    TAVICalciumResult *result = [[TAVICalciumResult alloc] init];
    result.thresholdHU = thresholdHU;
    result.totalSamples = pixelValues.length / sizeof(float);
    result.totalAreaMm2 = (double)result.totalSamples * pixelAreaMm2;

    NSUInteger samplesAbove = 0;
    const float *values = pixelValues.bytes;
    for (NSUInteger idx = 0; idx < result.totalSamples; idx++) {
        double value = (double)values[idx];
        if (value >= thresholdHU) {
            samplesAbove++;
        }
        if (value >= 130.0) {
            double densityFactor = 0.0;
            if (value >= 400.0) {
                densityFactor = 4.0;
            } else if (value >= 300.0) {
                densityFactor = 3.0;
            } else if (value >= 200.0) {
                densityFactor = 2.0;
            } else {
                densityFactor = 1.0;
            }
            result.agatstonScore2D += pixelAreaMm2 * densityFactor;
        }
    }

    result.samplesAboveThreshold = samplesAbove;
    result.hyperdenseAreaMm2 = (double)samplesAbove * pixelAreaMm2;
    result.fractionAboveThreshold = result.totalSamples > 0
        ? (double)samplesAbove / (double)result.totalSamples
        : 0.0;
    return result;
}

+ (TAVIVector3D)planeNormalForWorldPoints:(NSArray<NSValue *> *)worldPoints {
    return TAVIFallbackNormalForWorldPoints(TAVISanitizedWorldPoints(worldPoints));
}

+ (double)angleBetweenVector:(TAVIVector3D)lhs andVector:(TAVIVector3D)rhs {
    TAVIVector3D normalizedLhs = TAVIVector3DNormalize(lhs);
    TAVIVector3D normalizedRhs = TAVIVector3DNormalize(rhs);
    if (TAVIVector3DIsZero(normalizedLhs) || TAVIVector3DIsZero(normalizedRhs)) {
        return 0.0;
    }

    double clampedDot = MAX(-1.0, MIN(1.0, TAVIVector3DDot(normalizedLhs, normalizedRhs)));
    return acos(clampedDot) * 180.0 / M_PI;
}

+ (TAVIPoint2D)projectWorldPoint:(TAVIVector3D)worldPoint
                      planeOrigin:(TAVIVector3D)planeOrigin
                      planeNormal:(TAVIVector3D)planeNormal {
    TAVIPlaneBasis basis = TAVIPlaneBasisMake(planeNormal);
    return TAVIProjectWorldPointWithBasis(worldPoint, planeOrigin, basis);
}

+ (NSArray<NSValue *> *)projectWorldPoints:(NSArray<NSValue *> *)worldPoints
                               planeOrigin:(TAVIVector3D)planeOrigin
                               planeNormal:(TAVIVector3D)planeNormal {
    TAVIPlaneBasis basis = TAVIPlaneBasisMake(planeNormal);
    return TAVIProjectWorldPointsWithBasis(worldPoints, planeOrigin, basis);
}

@end
