#import "TAVITypes.h"

NSValue *TAVIValueWithVector3D(TAVIVector3D vector) {
    return [NSValue valueWithBytes:&vector objCType:@encode(TAVIVector3D)];
}

TAVIVector3D TAVIVector3DFromValue(NSValue *value) {
    TAVIVector3D vector = TAVIVector3DMake(0.0, 0.0, 0.0);
    if (value != nil) {
        [value getValue:&vector];
    }
    return vector;
}

NSString *TAVIStringFromVector3D(TAVIVector3D vector) {
    return [NSString stringWithFormat:@"(%.3f, %.3f, %.3f)", vector.x, vector.y, vector.z];
}

NSValue *TAVIValueWithPoint2D(TAVIPoint2D point) {
    return [NSValue valueWithBytes:&point objCType:@encode(TAVIPoint2D)];
}

TAVIPoint2D TAVIPoint2DFromValue(NSValue *value) {
    TAVIPoint2D point = TAVIPoint2DMake(0.0, 0.0);
    if (value != nil) {
        [value getValue:&point];
    }
    return point;
}
