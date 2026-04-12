#import <Foundation/Foundation.h>

#import "TAVIGeometry.h"

static void AssertClose(double actual, double expected, double tolerance, NSString *message) {
    if (fabs(actual - expected) > tolerance) {
        @throw [NSException exceptionWithName:@"AssertionFailure"
                                       reason:[NSString stringWithFormat:@"%@ (expected %.6f, got %.6f)", message, expected, actual]
                                     userInfo:nil];
    }
}

static void AssertTrue(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"AssertionFailure" reason:message userInfo:nil];
    }
}

static void AssertStringEqual(NSString *actual, NSString *expected, NSString *message) {
    if (![actual isEqualToString:expected]) {
        @throw [NSException exceptionWithName:@"AssertionFailure"
                                       reason:[NSString stringWithFormat:@"%@ (expected %@, got %@)", message, expected, actual]
                                     userInfo:nil];
    }
}

static NSArray<NSValue *> *SquarePoints(double sideLength) {
    return @[
        TAVIValueWithVector3D(TAVIVector3DMake(0.0, 0.0, 0.0)),
        TAVIValueWithVector3D(TAVIVector3DMake(sideLength, 0.0, 0.0)),
        TAVIValueWithVector3D(TAVIVector3DMake(sideLength, sideLength, 0.0)),
        TAVIValueWithVector3D(TAVIVector3DMake(0.0, sideLength, 0.0))
    ];
}

static NSArray<NSValue *> *EllipsePoints(double majorDiameter, double minorDiameter, NSUInteger count) {
    NSMutableArray<NSValue *> *points = [NSMutableArray arrayWithCapacity:count];
    double semiMajor = majorDiameter * 0.5;
    double semiMinor = minorDiameter * 0.5;
    for (NSUInteger idx = 0; idx < count; idx++) {
        double theta = ((double)idx / (double)count) * M_PI * 2.0;
        [points addObject:TAVIValueWithVector3D(TAVIVector3DMake(cos(theta) * semiMajor,
                                                                 sin(theta) * semiMinor,
                                                                 0.0))];
    }
    return points;
}

int main(void) {
    @autoreleasepool {
        TAVIGeometryResult *square = [TAVIGeometry geometryForWorldContour:SquarePoints(10.0)
                                                               planeNormal:TAVIVector3DMake(0.0, 0.0, 1.0)];
        AssertTrue(square != nil, @"Square geometry should exist");
        AssertClose(square.perimeterMm, 40.0, 0.0001, @"Square perimeter");
        AssertClose(square.areaMm2, 100.0, 0.0001, @"Square area");
        AssertClose(square.minimumDiameterMm, 10.0, 0.0001, @"Square minimum diameter");
        AssertClose(square.maximumDiameterMm, sqrt(200.0), 0.0001, @"Square maximum diameter");
        AssertClose(square.equivalentDiameterMm, 2.0 * sqrt(100.0 / M_PI), 0.0001, @"Square equivalent diameter");

        TAVIGeometryResult *assistedEllipse = [TAVIGeometry assistedAnnulusGeometryForWorldContour:EllipsePoints(24.0, 18.0, 96)
                                                                                        planeNormal:TAVIVector3DMake(0.0, 0.0, 1.0)];
        AssertTrue(assistedEllipse != nil, @"Assisted annulus fit should exist");
        AssertClose(assistedEllipse.maximumDiameterMm, 24.0, 0.3, @"Assisted annulus major diameter");
        AssertClose(assistedEllipse.minimumDiameterMm, 18.0, 0.3, @"Assisted annulus minor diameter");
        AssertClose(assistedEllipse.areaMm2, M_PI * 12.0 * 9.0, 2.0, @"Assisted annulus area");

        double distance = [TAVIGeometry distanceFromPoint:TAVIVector3DMake(4.0, 5.0, 15.0)
                                            toPlaneOrigin:TAVIVector3DMake(0.0, 0.0, 0.0)
                                                   normal:TAVIVector3DMake(0.0, 0.0, 1.0)];
        AssertClose(distance, 15.0, 0.0001, @"Plane distance");

        TAVIFluoroAngleResult *angle = [TAVIGeometry fluoroAngleForPlaneNormal:TAVIVector3DMake(1.0, 0.0, 1.0)];
        AssertTrue([angle.laoRaoLabel isEqualToString:@"LAO"], @"Expected LAO label");
        AssertTrue([angle.cranialCaudalLabel isEqualToString:@"CRANIAL"], @"Expected cranial label");
        AssertClose(angle.laoRaoDegrees, 90.0, 0.0001, @"Expected 90 degree LAO");
        AssertClose(angle.cranialCaudalDegrees, 45.0, 0.0001, @"Expected 45 degree cranial");

        NSArray<NSValue *> *sinusPoints = @[
            TAVIValueWithVector3D(TAVIVector3DMake(0.0, 0.0, 0.0)),
            TAVIValueWithVector3D(TAVIVector3DMake(10.0, 0.0, 0.0)),
            TAVIValueWithVector3D(TAVIVector3DMake(0.0, 10.0, 0.0))
        ];
        TAVIVector3D sinusNormal = [TAVIGeometry planeNormalForWorldPoints:sinusPoints];
        TAVIProjectionConfirmationResult *confirmation = [TAVIGeometry projectionConfirmationForReferenceNormal:TAVIVector3DMake(0.0, 0.0, 1.0)
                                                                                              confirmationNormal:sinusNormal];
        AssertTrue(confirmation != nil, @"Projection confirmation should exist");
        AssertClose(confirmation.normalDifferenceDegrees, 0.0, 0.0001, @"Projection confirmation delta");
        AssertStringEqual(confirmation.confirmationAngle.cranialCaudalLabel, @"CRANIAL", @"Confirmation cranial label");

        NSArray<NSValue *> *projected = [TAVIGeometry projectWorldPoints:@[
            TAVIValueWithVector3D(TAVIVector3DMake(1.0, 2.0, 0.0)),
            TAVIValueWithVector3D(TAVIVector3DMake(-1.0, -2.0, 0.0))
        ] planeOrigin:TAVIVector3DMake(0.0, 0.0, 0.0)
                                      planeNormal:TAVIVector3DMake(0.0, 0.0, 1.0)];
        AssertTrue(projected.count == 2, @"Projected points should round-trip");

        float pixelValues[] = {100.0f, 900.0f, 1200.0f, 850.0f, -50.0f};
        NSData *pixelData = [NSData dataWithBytes:pixelValues length:sizeof(pixelValues)];
        TAVICalciumResult *calcium = [TAVIGeometry calciumResultForPixelValues:pixelData pixelAreaMm2:2.0 thresholdHU:850.0];
        AssertTrue(calcium != nil, @"Calcium result should exist");
        AssertClose(calcium.totalAreaMm2, 10.0, 0.0001, @"Total area");
        AssertClose(calcium.hyperdenseAreaMm2, 6.0, 0.0001, @"Hyperdense area");
        AssertClose(calcium.fractionAboveThreshold, 0.6, 0.0001, @"Fraction above threshold");
        AssertClose(calcium.agatstonScore2D, 24.0, 0.0001, @"Agatston-like score");
        AssertTrue(calcium.samplesAboveThreshold == 3, @"Expected three samples above threshold");

        NSLog(@"All TAVI geometry tests passed.");
    }
    return 0;
}
