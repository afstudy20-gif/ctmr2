#import <Foundation/Foundation.h>
#import <float.h>
#import <math.h>

typedef struct {
    double x;
    double y;
    double z;
} TAVIVector3D;

typedef struct {
    double x;
    double y;
} TAVIPoint2D;

static inline TAVIVector3D TAVIVector3DMake(double x, double y, double z) {
    TAVIVector3D vector;
    vector.x = x;
    vector.y = y;
    vector.z = z;
    return vector;
}

static inline TAVIPoint2D TAVIPoint2DMake(double x, double y) {
    TAVIPoint2D point;
    point.x = x;
    point.y = y;
    return point;
}

static inline TAVIVector3D TAVIVector3DAdd(TAVIVector3D a, TAVIVector3D b) {
    return TAVIVector3DMake(a.x + b.x, a.y + b.y, a.z + b.z);
}

static inline TAVIVector3D TAVIVector3DSubtract(TAVIVector3D a, TAVIVector3D b) {
    return TAVIVector3DMake(a.x - b.x, a.y - b.y, a.z - b.z);
}

static inline TAVIVector3D TAVIVector3DScale(TAVIVector3D vector, double scale) {
    return TAVIVector3DMake(vector.x * scale, vector.y * scale, vector.z * scale);
}

static inline double TAVIVector3DDot(TAVIVector3D a, TAVIVector3D b) {
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z);
}

static inline TAVIVector3D TAVIVector3DCross(TAVIVector3D a, TAVIVector3D b) {
    return TAVIVector3DMake((a.y * b.z) - (a.z * b.y),
                            (a.z * b.x) - (a.x * b.z),
                            (a.x * b.y) - (a.y * b.x));
}

static inline double TAVIVector3DLength(TAVIVector3D vector) {
    return sqrt(TAVIVector3DDot(vector, vector));
}

static inline TAVIVector3D TAVIVector3DNormalize(TAVIVector3D vector) {
    double length = TAVIVector3DLength(vector);
    if (length <= DBL_EPSILON) {
        return TAVIVector3DMake(0.0, 0.0, 0.0);
    }
    return TAVIVector3DScale(vector, 1.0 / length);
}

static inline BOOL TAVIVector3DIsZero(TAVIVector3D vector) {
    return fabs(vector.x) <= DBL_EPSILON &&
           fabs(vector.y) <= DBL_EPSILON &&
           fabs(vector.z) <= DBL_EPSILON;
}

FOUNDATION_EXPORT NSValue *TAVIValueWithVector3D(TAVIVector3D vector);
FOUNDATION_EXPORT TAVIVector3D TAVIVector3DFromValue(NSValue *value);
FOUNDATION_EXPORT NSString *TAVIStringFromVector3D(TAVIVector3D vector);
FOUNDATION_EXPORT NSValue *TAVIValueWithPoint2D(TAVIPoint2D point);
FOUNDATION_EXPORT TAVIPoint2D TAVIPoint2DFromValue(NSValue *value);
