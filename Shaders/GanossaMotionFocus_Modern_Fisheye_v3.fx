/*
 * Ganossa Motion Focus - Modernized Edition with Motion Fisheye
 *
 * Original concept:
 *   Ganossa (mediehawk@gmail.com)
 * Original port credit:
 *   IDDQD
 *
 * Modernization goals:
 *   - Keep the original motion-following idea.
 *   - Remove the resolution-dependent 5184 normalization.
 *   - Replace the legacy ~192x108 analysis loop with a fixed 32x18 grid.
 *   - Make motion detection usable with HDR / wide luminance ranges.
 *   - Add temporal persistence and focus smoothing controls.
 *   - Add independent Fisheye deadzone and frame-rate-independent persistence.
 *   - Use a centered zoom transform instead of the legacy edge-correction formula.
 *   - Avoid discard-based partial rendering.
 *
 * Target:
 *   ReShade 6.x / current ReShade FX
 */

#include "ReShade.fxh"

// ============================================================================
// User controls
// ============================================================================

uniform bool mfDebug
<
    ui_label = "Debug overlay";
    ui_tooltip = "Show the detected motion center and the current analysis state.";
> = false;

uniform bool mfResetHistory
<
    ui_type = "button";
    ui_label = "Reset motion history";
    ui_tooltip = "Clear the temporal motion history. Useful after scene cuts or when enabling the effect mid-game.";
> = false;

uniform float mfFocusStrength
<
    ui_type = "slider";
    ui_label = "Focus strength";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_tooltip = "How strongly the camera follows the detected motion center.";
> = 1.0;

uniform float mfZoomStrength
<
    ui_type = "slider";
    ui_label = "Zoom strength";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_tooltip = "How strongly the image zooms toward the detected motion.";
> = 0.60;

uniform float mfMotionSensitivity
<
    ui_type = "slider";
    ui_label = "Motion sensitivity";
    ui_min = 0.25;
    ui_max = 4.0;
    ui_step = 0.05;
    ui_tooltip = "Amplifies frame-to-frame color changes before they are converted into motion intensity.";
> = 1.50;

uniform float mfMotionThreshold
<
    ui_type = "slider";
    ui_label = "Motion threshold";
    ui_min = 0.0;
    ui_max = 0.10;
    ui_step = 0.001;
    ui_tooltip = "Suppresses tiny frame-to-frame changes such as dithering and post-process noise.";
> = 0.010;

uniform float mfPersistence
<
    ui_type = "slider";
    ui_label = "Motion persistence";
    ui_min = 0.0;
    ui_max = 0.999;
    ui_step = 0.001;
    ui_tooltip = "How long detected motion remains in the temporal motion map.";
> = 0.960;

uniform float mfFocusSmoothing
<
    ui_type = "slider";
    ui_label = "Focus smoothing";
    ui_min = 0.01;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_tooltip = "Response speed of the tracked focus point. Higher values react faster.";
> = 0.25;

uniform float mfDeadzone
<
    ui_type = "slider";
    ui_label = "Focus deadzone";
    ui_min = 0.0;
    ui_max = 0.25;
    ui_step = 0.005;
    ui_tooltip = "Ignore small focus offsets around the screen center.";
> = 0.05;

uniform float mfMaxZoom
<
    ui_type = "slider";
    ui_label = "Maximum zoom";
    ui_min = 0.0;
    ui_max = 0.50;
    ui_step = 0.01;
    ui_tooltip = "Hard limit for zoom-in. 0.20 means the image can zoom in by at most 20 percent.";
> = 0.30;

uniform float mfMaxShift
<
    ui_type = "slider";
    ui_label = "Maximum focus shift";
    ui_min = 0.0;
    ui_max = 0.50;
    ui_step = 0.01;
    ui_tooltip = "Hard limit for camera translation caused by motion tracking.";
> = 0.30;

// Optional edge distortion. This is deliberately independent from the
// Motion Focus zoom: it only consumes the measured motion activity as its
// speed signal and applies a radial warp around the screen center.
uniform bool mfFisheyeEnable
<
    ui_type = "checkbox";
    ui_category = "Motion Fisheye";
    ui_category_closed = true;
    ui_category_toggle = true;
    ui_label = "Enable motion fisheye";
    ui_tooltip = "Enable an edge-only fisheye/barrel distortion driven by instantaneous image motion. It is independent from Motion Focus zoom.";
> = false;

uniform float mfFisheyeStrength
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Fisheye strength";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
    ui_tooltip = "Maximum distortion amount. Does not modify Motion Focus zoom.";
> = 0.55;

uniform float mfFisheyeSpeedCurve
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Fisheye speed response";
    ui_min = 0.50;
    ui_max = 3.0;
    ui_step = 0.05;
    ui_tooltip = "Response curve for motion speed. 1.0 is linear; higher values favor fast movement.";
> = 1.00;

uniform float mfFisheyeMotionGain
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Motion-to-fisheye gain";
    ui_min = 1.0;
    ui_max = 50.0;
    ui_step = 0.5;
    ui_tooltip = "Amplifies the measured instantaneous motion before converting it to distortion strength.";
> = 24.0;

uniform float mfFisheyePersistence
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Fisheye persistence";
    ui_min = 0.0;
    ui_max = 0.999;
    ui_step = 0.001;
    ui_tooltip = "How long the fisheye remains after motion stops. Higher values make the distortion fade out more gradually.";
> = 0.940;

uniform float mfFisheyeDeadzone
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Fisheye deadzone";
    ui_min = 0.0;
    ui_max = 0.50;
    ui_step = 0.005;
    ui_tooltip = "Ignore weak image motion below this level, preventing fisheye activation from tiny movement and temporal noise.";
> = 0.020;

uniform float mfFisheyeEdgeStart
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Fisheye edge start";
    ui_min = 0.0;
    ui_max = 0.85;
    ui_step = 0.01;
    ui_tooltip = "Radius at which the distortion begins. Higher values confine it closer to the edges.";
> = 0.25;

uniform float mfFisheyeAspect
<
    ui_type = "slider";
    ui_category = "Motion Fisheye";
    ui_label = "Fisheye aspect correction";
    ui_min = 0.50;
    ui_max = 1.50;
    ui_step = 0.01;
    ui_tooltip = "Fine-tunes aspect correction for ultrawide and unusual display ratios. 1.0 is the normal setting.";
> = 1.0;

// Runtime counters are hidden from the UI. Frame count avoids a false
// first-frame motion spike; frame time makes temporal behavior less dependent
// on the current FPS.
uniform int mfFrameCount <
    source = "framecount";
    hidden = true;
>;

uniform float mfFrameTime <
    source = "frametime";
    hidden = true;
>;

// ============================================================================
// Fixed analysis resolution
// ============================================================================
// 32x18 preserves the original 16:9 analysis ratio while replacing the
// resolution-dependent 192x108 sweep. The analysis pass now executes once
// on a 1x1 target and performs 576 samples per frame instead of ~20,736.
// Because the grid is fixed in normalized UV space, its behavior is consistent
// across 1080p, 1440p, 4K and ultrawide resolutions.

#define MF_HALF_WIDTH   (BUFFER_WIDTH / 2)
#define MF_HALF_HEIGHT  (BUFFER_HEIGHT / 2)

#define MF_ANALYSIS_X   32
#define MF_ANALYSIS_Y   18
#define MF_QUAD_X       (MF_ANALYSIS_X / 2)
#define MF_QUAD_Y       (MF_ANALYSIS_Y / 2)
#define MF_QUAD_SAMPLES (MF_QUAD_X * MF_QUAD_Y)
#define MF_TOTAL_SAMPLES (MF_ANALYSIS_X * MF_ANALYSIS_Y)

// ============================================================================
// Internal textures
// ============================================================================

// Current / previous half-resolution luminance + chroma activity. RG16F is
// enough for the comparison while keeping the history compact. Unlike the
// legacy RGBA8 storage, the half-float range also handles HDR values much better.
// the original RGBA8 history buffer.
texture2D Ganossa_MF_CurrentTex
{
    Width = MF_HALF_WIDTH;
    Height = MF_HALF_HEIGHT;
    Format = RG16F;
    MipLevels = 1;
};

texture2D Ganossa_MF_PreviousTex
{
    Width = MF_HALF_WIDTH;
    Height = MF_HALF_HEIGHT;
    Format = RG16F;
    MipLevels = 1;
};

// Temporal motion map. One channel is sufficient.
texture2D Ganossa_MF_MotionTex
{
    Width = MF_HALF_WIDTH;
    Height = MF_HALF_HEIGHT;
    Format = RG16F;
    MipLevels = 1;
};

texture2D Ganossa_MF_PreviousMotionTex
{
    Width = MF_HALF_WIDTH;
    Height = MF_HALF_HEIGHT;
    Format = R16F;
    MipLevels = 1;
};

// 1x1 state: xy = normalized focus offset [-0.5, 0.5],
// z = average motion activity, w = quadrant contrast.
texture2D Ganossa_MF_StateTex
{
    Width = 1;
    Height = 1;
    Format = RGBA16F;
    MipLevels = 1;
};

texture2D Ganossa_MF_PreviousStateTex
{
    Width = 1;
    Height = 1;
    Format = RGBA16F;
    MipLevels = 1;
};

// Explicit samplers make filtering/address behavior independent of defaults.
sampler2D Ganossa_MF_CurrentColor
{
    Texture = Ganossa_MF_CurrentTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
};

sampler2D Ganossa_MF_PreviousColor
{
    Texture = Ganossa_MF_PreviousTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
};

sampler2D Ganossa_MF_MotionColor
{
    Texture = Ganossa_MF_MotionTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
};

sampler2D Ganossa_MF_PreviousMotionColor
{
    Texture = Ganossa_MF_PreviousMotionTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = POINT;
};

sampler2D Ganossa_MF_StateColor
{
    Texture = Ganossa_MF_StateTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
};

sampler2D Ganossa_MF_PreviousStateColor
{
    Texture = Ganossa_MF_PreviousStateTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
};

// 1x1 instantaneous motion energy used only by the optional fisheye.
// It is generated together with the main analysis state using MRT.
texture2D Ganossa_MF_FisheyeSpeedTex
{
    Width = 1;
    Height = 1;
    Format = R16F;
    MipLevels = 1;
};

texture2D Ganossa_MF_PreviousFisheyeSpeedTex
{
    Width = 1;
    Height = 1;
    Format = R16F;
    MipLevels = 1;
};

sampler2D Ganossa_MF_FisheyeSpeedColor
{
    Texture = Ganossa_MF_FisheyeSpeedTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
};

sampler2D Ganossa_MF_PreviousFisheyeSpeedColor
{
    Texture = Ganossa_MF_PreviousFisheyeSpeedTex;
    AddressU = CLAMP;
    AddressV = CLAMP;
    MagFilter = POINT;
    MinFilter = POINT;
    MipFilter = POINT;
};

// ============================================================================
// Helper
// ============================================================================

float2 MF_GetColorFeatures(float3 color)
{
    float luma = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
    float chroma = max(color.r, max(color.g, color.b)) -
                   min(color.r, min(color.g, color.b));
    return float2(luma, chroma);
}

// ============================================================================
// Pass 1: downsample current frame to half resolution
// ============================================================================

float4 PS_MotionFocusCapture(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float2 features = MF_GetColorFeatures(color);
    return float4(features, 0.0f, 0.0f);
}

// ============================================================================
// Pass 2: build temporally persistent motion map
// ============================================================================

float4 PS_MotionFocusMotion(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD) : SV_Target
{
    float2 currentFeatures = tex2D(Ganossa_MF_CurrentColor, texcoord).rg;
    float2 previousFeatures = tex2D(Ganossa_MF_PreviousColor, texcoord).rg;

    float2 featureDelta = abs(currentFeatures - previousFeatures);

    // Normalize the frame-to-frame signal toward a 60 Hz reference. Without
    // this, the same camera movement produces noticeably different per-frame
    // deltas at 30 FPS and 120+ FPS. This also makes the fisheye speed driver
    // much more consistent across frame rates.
    float frameScale = 16.6667f / max(0.25f, mfFrameTime);
    frameScale = clamp(frameScale, 0.25f, 4.0f);

    // Luminance drives the detector; a smaller chroma contribution preserves
    // useful sensitivity to color motion without making small hue shifts dominate.
    float weightedDelta = (featureDelta.x + featureDelta.y * 0.25f) * frameScale;
    float motion = 1.0f - exp(-weightedDelta * mfMotionSensitivity);

    motion = saturate((motion - mfMotionThreshold) /
                      max(0.0001f, 1.0f - mfMotionThreshold));

    float previousMotion = tex2D(Ganossa_MF_PreviousMotionColor, texcoord).r;

    // Convert the user persistence value into a frame-rate-independent decay.
    float dt60 = clamp(mfFrameTime * 0.060f, 0.25f, 4.0f);
    float framePersistence = pow(saturate(mfPersistence), dt60);

    // Keep strong motion immediately, while allowing weaker motion to decay.
    float persistentMotion = max(motion, previousMotion * framePersistence);

    // Do not treat the very first frame after startup as a full-screen change.
    if (mfFrameCount <= 1 || mfResetHistory)
        persistentMotion = 0.0f;

    // R = temporally persistent motion for Motion Focus.
    // G = instantaneous motion for the independent Fisheye speed driver.
    return float4(persistentMotion, motion, 0.0f, 0.0f);
}

// ============================================================================
// Pass 3: reduce the motion map to 1x1 Motion Focus state + fisheye speed
// ============================================================================

void PS_MotionFocusAnalyze(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD,
    out float4 stateR : SV_Target0,
    out float4 fisheyeSpeedR : SV_Target1)
{
    float4 quadrants = 0.0f;
    float totalMotion = 0.0f;
    float totalInstantMotion = 0.0f;
    float2 weightedCenter = 0.0f;

    [loop]
    for (int y = 0; y < MF_ANALYSIS_Y; ++y)
    {
        [loop]
        for (int x = 0; x < MF_ANALYSIS_X; ++x)
        {
            float2 analysisUV =
                (float2(x, y) + 0.5f) /
                float2((float)MF_ANALYSIS_X, (float)MF_ANALYSIS_Y);

            float2 motionData = tex2D(Ganossa_MF_MotionColor, analysisUV).rg;
            float motion = motionData.x;

            totalMotion += motion;
            totalInstantMotion += motionData.y;
            weightedCenter += analysisUV * motion;

            if (x < MF_QUAD_X && y < MF_QUAD_Y)
                quadrants.x += motion;
            else if (x >= MF_QUAD_X && y < MF_QUAD_Y)
                quadrants.y += motion;
            else if (x < MF_QUAD_X && y >= MF_QUAD_Y)
                quadrants.z += motion;
            else
                quadrants.w += motion;
        }
    }

    quadrants /= (float)MF_QUAD_SAMPLES;

    float activity = saturate(totalMotion / (float)MF_TOTAL_SAMPLES);

    float2 focusOffset = 0.0f;
    if (totalMotion > 0.00001f)
        focusOffset = weightedCenter / totalMotion - 0.5f;

    float usableRange = max(0.0001f, 0.5f - mfDeadzone);
    float2 focusSign = sign(focusOffset);
    float2 focusMagnitude = max(abs(focusOffset) - mfDeadzone, 0.0f);
    focusOffset = focusSign * saturate(focusMagnitude / usableRange) * 0.5f;

    float strongestQuadrant = max(
        quadrants.x,
        max(quadrants.y, max(quadrants.z, quadrants.w)));

    float otherAverage =
        (quadrants.x + quadrants.y + quadrants.z + quadrants.w - strongestQuadrant) / 3.0f;

    float contrast = saturate(
        (strongestQuadrant - otherAverage) /
        max(0.0001f, strongestQuadrant));

    float4 rawState = float4(focusOffset, activity, contrast);
    float4 previousState = tex2D(Ganossa_MF_PreviousStateColor, float2(0.5f, 0.5f));

    float dt60 = clamp(mfFrameTime * 0.060f, 0.25f, 4.0f);
    float response = 1.0f - pow(1.0f - saturate(mfFocusSmoothing), dt60);

    float4 state = rawState;
    if (mfFrameCount > 1 && !mfResetHistory)
        state = lerp(previousState, rawState, response);

    stateR = state;

    // Fisheye has its own motion signal. Apply a deadzone first so that tiny
    // changes do not start the effect, then retain the remaining signal in a
    // separate 1x1 temporal history so the distortion fades instead of snapping
    // to zero when movement stops. This does not modify Motion Focus state.
    float instantActivity = saturate(totalInstantMotion / (float)MF_TOTAL_SAMPLES);
    float fisheyeInput = saturate(
        (instantActivity - mfFisheyeDeadzone) /
        max(0.0001f, 1.0f - mfFisheyeDeadzone));

    float previousFisheye =
        tex2D(Ganossa_MF_PreviousFisheyeSpeedColor, float2(0.5f, 0.5f)).r;

    float dt60Fisheye = clamp(mfFrameTime * 0.060f, 0.25f, 4.0f);
    float fisheyePersistence =
        pow(saturate(mfFisheyePersistence), dt60Fisheye);

    float persistentFisheye =
        max(fisheyeInput, previousFisheye * fisheyePersistence);

    if (mfFrameCount <= 1 || mfResetHistory)
        persistentFisheye = 0.0f;

    fisheyeSpeedR = float4(persistentFisheye, 0.0f, 0.0f, 0.0f);
}

// ============================================================================
// Optional motion-driven fisheye
// ============================================================================

float2 MF_ApplyMotionFisheye(float2 uv, float motionSpeed)
{
    if (!mfFisheyeEnable || mfFisheyeStrength <= 0.0f)
        return uv;

    // The motion signal has already had its deadzone and temporal persistence
    // applied in the 1x1 analysis pass. Convert it to a perceptual speed signal
    // before applying the user response curve.
    float speedSignal = 1.0f - exp(-motionSpeed * mfFisheyeMotionGain);
    float speed = pow(saturate(speedSignal), mfFisheyeSpeedCurve);

    if (speed <= 0.00001f)
        return uv;

    float screenAspect = (float)BUFFER_WIDTH / max(1.0f, (float)BUFFER_HEIGHT);
    float aspectScale = (screenAspect / 1.7777778f) * mfFisheyeAspect;

    float2 p = uv - 0.5f;
    p.x *= aspectScale;

    float radius = length(p);
    if (radius <= 0.000001f)
        return uv;

    float maxRadius = length(float2(0.5f * aspectScale, 0.5f));
    float radiusNorm = saturate(radius / max(0.0001f, maxRadius));

    float edge = smoothstep(mfFisheyeEdgeStart, 1.0f, radiusNorm);
    edge = edge * edge;

    float amount = saturate(mfFisheyeStrength * speed * edge);

    // Inverse radial barrel/fisheye warp. The mapping moves the source sample
    // inward near the outer image while leaving the center essentially intact.
    float radial = radiusNorm * radiusNorm;
    float warp = 1.0f - amount * (0.85f + 0.15f * radial) * radial;
    float2 warped = p * warp;

    warped.x /= max(0.0001f, aspectScale);
    return saturate(warped + 0.5f);
}

// ============================================================================
// Pass 4: apply centered zoom + motion-following translation
// ============================================================================

float4 PS_MotionFocusDisplay(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD) : SV_Target
{
    float4 state = tex2D(Ganossa_MF_StateColor, float2(0.5f, 0.5f));

    float2 focusOffset = state.xy;
    float activity = saturate(state.z);
    float contrast = saturate(state.w);

    // Both effects strengthen with actual motion, but focus translation is
    // additionally gated by quadrant contrast so global motion does not cause
    // a large arbitrary pan.
    float focusAmount =
        activity * pow(contrast, 1.5f) * mfFocusStrength;

    float zoomAmount =
        activity * (0.35f + 0.65f * contrast) * mfZoomStrength;

    zoomAmount = min(zoomAmount, mfMaxZoom);

    float2 focusShift = focusOffset * (2.0f * mfMaxShift) * focusAmount;

    // Zoom around the screen center, then move the sample position toward the
    // detected motion. Positive focusOffset means the image itself shifts in
    // the opposite direction, keeping the moving subject closer to center.
    float2 sampleCoord =
        (texcoord - 0.5f) * (1.0f - zoomAmount) +
        0.5f + focusShift;

    sampleCoord = saturate(sampleCoord);

    if (mfDebug)
    {
        float2 center = float2(0.5f, 0.5f);
        float2 target = saturate(0.5f + focusOffset);

        // Center crosshair.
        if ((abs(texcoord.x - center.x) < 0.0015f &&
             abs(texcoord.y - center.y) < 0.012f) ||
            (abs(texcoord.y - center.y) < 0.0015f &&
             abs(texcoord.x - center.x) < 0.012f))
            return float4(0.0f, 1.0f, 0.0f, 1.0f);

        // Detected motion center.
        if ((abs(texcoord.x - target.x) < 0.0020f &&
             abs(texcoord.y - target.y) < 0.015f) ||
            (abs(texcoord.y - target.y) < 0.0020f &&
             abs(texcoord.x - target.x) < 0.015f))
            return float4(1.0f, 0.0f, 0.0f, 1.0f);

        // Small activity bar in the upper-left corner.
        if (texcoord.y > 0.01f && texcoord.y < 0.02f &&
            texcoord.x < activity * 0.25f)
            return float4(1.0f, 1.0f, 0.0f, 1.0f);
    }

    // The fisheye is intentionally evaluated after Motion Focus. This means
    // it does not multiply, replace or otherwise alter mfZoomStrength. It is
    // simply an additional motion-reactive lens pass folded into the same
    // fullscreen shader for zero extra render-target traffic.
    float fisheyeSpeed = tex2D(Ganossa_MF_FisheyeSpeedColor, float2(0.5f, 0.5f)).r;
    sampleCoord = MF_ApplyMotionFisheye(sampleCoord, fisheyeSpeed);

    return tex2D(ReShade::BackBuffer, sampleCoord);
}

// ============================================================================
// Pass 5: store current frame and motion map for the next frame
// ============================================================================

void PS_MotionFocusStoreHistory(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD,
    out float4 previousFrame : SV_Target0,
    out float4 previousMotion : SV_Target1)
{
    previousFrame = tex2D(Ganossa_MF_CurrentColor, texcoord);
    previousMotion = tex2D(Ganossa_MF_MotionColor, texcoord);
}

// ============================================================================
// Pass 6: store the persistent fisheye strength for the next frame
// ============================================================================

float4 PS_MotionFocusStoreFisheyeSpeed(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(Ganossa_MF_FisheyeSpeedColor, float2(0.5f, 0.5f));
}

// ============================================================================
// Pass 7: store the 1x1 tracking state for the next frame
// ============================================================================

float4 PS_MotionFocusStoreState(
    float4 vpos : SV_Position,
    float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(Ganossa_MF_StateColor, float2(0.5f, 0.5f));
}

// ============================================================================
// Technique
// ============================================================================

technique GanossaMotionFocusModernFisheye
<
    ui_label = "Ganossa Motion Focus (Modern + Fisheye)";
    ui_tooltip = "Modernized, resolution-independent Motion Focus with an optional motion-driven fisheye edge distortion.";
>
{
    pass MotionFocusCapturePass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusCapture;
        RenderTarget = Ganossa_MF_CurrentTex;
        ClearRenderTargets = false;
    }

    pass MotionFocusMotionPass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusMotion;
        RenderTarget = Ganossa_MF_MotionTex;
        ClearRenderTargets = false;
    }

    pass MotionFocusAnalyzePass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusAnalyze;
        RenderTarget0 = Ganossa_MF_StateTex;
        RenderTarget1 = Ganossa_MF_FisheyeSpeedTex;
        ClearRenderTargets = true;
    }

    pass MotionFocusDisplayPass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusDisplay;
    }

    pass MotionFocusStoreHistoryPass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusStoreHistory;
        RenderTarget0 = Ganossa_MF_PreviousTex;
        RenderTarget1 = Ganossa_MF_PreviousMotionTex;
        ClearRenderTargets = false;
    }

    pass MotionFocusStoreFisheyeSpeedPass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusStoreFisheyeSpeed;
        RenderTarget = Ganossa_MF_PreviousFisheyeSpeedTex;
        ClearRenderTargets = false;
    }

    pass MotionFocusStoreStatePass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_MotionFocusStoreState;
        RenderTarget = Ganossa_MF_PreviousStateTex;
        ClearRenderTargets = false;
    }
}
