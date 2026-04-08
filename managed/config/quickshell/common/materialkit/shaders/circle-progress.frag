#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float arcRadius;
    float strokeWidth;
    float renderProgress;
    vec4 strokeColorValue;
};

const float PI = 3.14159265358979323846;
const float TAU = 6.28318530717958647692;

float circleMask(vec2 point, vec2 center, float radius, float aa) {
    float dist = length(point - center) - radius;
    return 1.0 - smoothstep(0.0, aa, dist);
}

void main() {
    float clampedProgress = clamp(renderProgress, 0.0, 1.0);
    float halfStroke = max(strokeWidth * 0.5, 0.0);
    vec2 halfSize = itemSize * 0.5;
    vec2 point = qt_TexCoord0 * itemSize - halfSize;

    if (clampedProgress <= 0.0 || halfStroke <= 0.0 || arcRadius <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float radialDist = abs(length(point) - arcRadius) - halfStroke;
    float aa = max(fwidth(radialDist), 0.75);
    float ringMask = 1.0 - smoothstep(0.0, aa, radialDist);

    if (clampedProgress >= 0.9999) {
        fragColor = strokeColorValue * (ringMask * qt_Opacity);
        return;
    }

    float startAngle = -PI * 0.5;
    float sweep = clampedProgress * TAU;
    float angle = atan(point.y, point.x);
    float relativeAngle = mod(angle - startAngle + TAU, TAU);
    float arcMask = relativeAngle <= sweep ? ringMask : 0.0;

    vec2 startCenter = vec2(cos(startAngle), sin(startAngle)) * arcRadius;
    float endAngle = startAngle + sweep;
    vec2 endCenter = vec2(cos(endAngle), sin(endAngle)) * arcRadius;
    float startCapMask = circleMask(point, startCenter, halfStroke, aa);
    float endCapMask = circleMask(point, endCenter, halfStroke, aa);
    float mask = max(arcMask, max(startCapMask, endCapMask));

    fragColor = strokeColorValue * (mask * qt_Opacity);
}
