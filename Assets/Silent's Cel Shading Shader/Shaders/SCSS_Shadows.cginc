#ifndef SCSS_SHADOWS_INCLUDED
#define SCSS_SHADOWS_INCLUDED

#pragma multi_compile_shadowcaster
#pragma fragmentoption ARB_precision_hint_fastest

#include "UnityCG.cginc"
#include "UnityShaderVariables.cginc"

#if (defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON))
    #define SCSS_USE_DITHER_MASK 1
#endif

// Need to output UVs in shadow caster, since we need to sample texture and do clip/dithering based on it
#if defined(_ALPHATEST_ON) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
    #define SCSS_USE_SHADOW_UVS 1
#endif

// Has a non-empty shadow caster output struct (it's an error to have empty structs on some platforms...)
#if !defined(V2F_SHADOW_CASTER_NOPOS_IS_EMPTY) || defined(SCSS_USE_SHADOW_UVS)
    #define SCSS_USE_SHADOW_OUTPUT_STRUCT 1
#endif

#ifdef UNITY_STEREO_INSTANCING_ENABLED
    #define SCSS_USE_STEREO_SHADOW_OUTPUT_STRUCT 1
#endif

#include "SCSS_Config.cginc"
#include "SCSS_Utils.cginc"
#include "SCSS_Input.cginc"
#include "SCSS_Attributes.cginc"
#include "SCSS_ForwardVertex.cginc"


#if defined(_SPECULAR)
/*
half SpecularSetup_ShadowGetOneMinusReflectivity(half2 uv)
{
    half3 specColor = _SpecColor.rgb;
    #ifdef _SPECGLOSSMAP
        specColor = tex2D(_SpecGlossMap, uv).rgb;
    #endif
    return (1 - SpecularStrength(specColor));
}
*/
#endif

float4 TexCoordsShadowCaster(float2 texcoords)
{
    float4 texcoord;
    texcoord.xy = TRANSFORM_TEX(texcoords, _MainTex);// Always source from uv0
    texcoord.xy = _PixelSampleMode? 
        sharpSample(_MainTex_TexelSize * _MainTex_ST.xyxy, texcoord.xy) : texcoord.xy;

    return texcoord;
}

// We have to do these dances of outputting SV_POSITION separately from the vertex shader,
// and inputting VPOS in the pixel shader, since they both map to "POSITION" semantic on
// some platforms, and then things don't go well.

void vertShadowCaster (VertexInputShadowCaster v
    , out float4 opos : SV_POSITION
    #ifdef SCSS_USE_SHADOW_OUTPUT_STRUCT
    , out VertexOutputShadowCaster o
    #endif
    #ifdef SCSS_USE_STEREO_SHADOW_OUTPUT_STRUCT
    , out VertexOutputStereoShadowCaster os
    #endif
)
{
    UNITY_SETUP_INSTANCE_ID(v);

    // Object-space vertex modifications go here.
    
    #ifdef SCSS_USE_STEREO_SHADOW_OUTPUT_STRUCT
        UNITY_TRANSFER_INSTANCE_ID(v, o);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(os);
    #endif

    TRANSFER_SHADOW_CASTER_NOPOS(o,opos)
    //TRANSFER_SHADOW_CASTER_NOPOS_LEGACY (o, opos)

    // Standard would apply texcoords here, but we need to apply them in fragment
    // due to pixel sampling mode options.

    // Simple inventory.
    float inventoryMask = getInventoryMask(v.uv0);

    // Apply the inventory mask.
    // Set the output variables based on the mask to completely remove it.
    // - Set the clip-space position to one that won't be rendered
    // - Set the vertex alpha to zero
    // - Disable outlines
    if (_UseInventory)
    {
        opos.z =     inventoryMask ? opos.z : 1e+9;
        //o.vertex =    inventoryMask ? o.vertex : 1e+9;
    }
    
    opos = ApplyNearVertexSquishing(opos);

    #if defined(SCSS_USE_SHADOW_UVS)
        o.tex = AnimateTexcoords(v.uv0);
    #endif
}

half4 fragShadowCaster (UNITY_POSITION(vpos)
#ifdef SCSS_USE_SHADOW_OUTPUT_STRUCT
    , VertexOutputShadowCaster i
#endif
) : SV_Target
{
    half alpha = Alpha(0);
    half3 albedo = 1;
    half oneMinusReflectivity = 0;
    #if defined(SCSS_USE_SHADOW_UVS)
        half4 texcoords = TexCoordsShadowCaster(i.tex);
        albedo = Albedo(texcoords);
        alpha = Alpha(texcoords);
    #endif // #if defined(SCSS_USE_SHADOW_UVS)

    #if defined(ALPHAFUNCTION)
    alphaFunction(alpha);
    #endif

    applyVanishing(alpha);

    #if defined(_SPECULAR)
    {
        half4 specGloss = SpecularGloss(texcoords, detailMask);

        if (_UseMetallic == 1)
        {
            // In Metallic mode, ignore the other colour channels. 
            specGloss = specGloss.r;
            oneMinusReflectivity = OneMinusReflectivityFromMetallic(specGloss);
        }
        else 
        {
            // Specular energy converservation. From EnergyConservationBetweenDiffuseAndSpecular in UnityStandardUtils.cginc
            oneMinusReflectivity = 1 - SpecularStrength(specGloss); 
        }
    }
    #endif
    // When premultiplied mode is set, this will multiply the diffuse by the alpha component,
    // allowing to handle transparency in physically correct way - only diffuse component gets affected by alpha
    PreMultiplyAlpha_local (albedo, alpha, oneMinusReflectivity, /*out*/ alpha);

    applyAlphaClip(alpha, _Cutoff, vpos.xy, _AlphaSharp);

    SHADOW_CASTER_FRAGMENT(i) 
}

#endif