v2g vert(appdata_full v) {
	v2g o = (v2g)0;

    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2g, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	o.pos = UnityObjectToClipPos(v.vertex);
	o.uv0 = v.texcoord;
	o.uv1 = v.texcoord1;
	o.normal = v.normal;
	o.tangent = v.tangent;
	o.normalDir = UnityObjectToWorldNormal(v.normal);
	o.tangentDir = UnityObjectToWorldDir(v.tangent.xyz);
    half sign = v.tangent.w * unity_WorldTransformParams.w;
	o.bitangentDir = cross(o.normalDir, o.tangentDir) * sign;
	float4 objPos = mul(unity_ObjectToWorld, float4(0, 0, 0, 1));
	o.posWorld = mul(unity_ObjectToWorld, v.vertex);
	o.vertex = v.vertex;
	o.color = v.color;

	#if (UNITY_VERSION<600)
	TRANSFER_SHADOW(o);
	#else
	UNITY_TRANSFER_SHADOW(o, v.texcoord);
	#endif

	UNITY_TRANSFER_FOG(o, o.pos);
#if VERTEXLIGHT_ON
	o.vertexLight = VertexLightContribution(o.posWorld, o.normalDir);
#else
	o.vertexLight = 0;
#endif
	return o;
}

[maxvertexcount(6)]
void geom(triangle v2g IN[3], inout TriangleStream<VertexOutput> tristream)
{
	VertexOutput o = (VertexOutput)0;
	#if !NO_OUTLINE
	for (int i = 2; i >= 0; i--)
	{
		o.pos = UnityObjectToClipPos(IN[i].vertex + normalize(IN[i].normal) * (_outline_width * .01));
		o.uv0 = IN[i].uv0;
		o.uv1 = IN[i].uv1;
		o.posWorld = mul(unity_ObjectToWorld, IN[i].vertex);
		o.normalDir = UnityObjectToWorldNormal(IN[i].normal);
		o.tangentDir = IN[i].tangentDir;
		o.bitangentDir = IN[i].bitangentDir;
		o.is_outline = true;
		float _outline_width_var = _outline_width * .01; // Convert to cm
		// Scale outlines relative to the distance from the camera. Outlines close up look ugly in VR because
		// they can have holes, being shells. This is also why it is clamped to not make them bigger.
		// That looks good at a distance, but not perfect. 
		_outline_width_var *= min(distance(o.posWorld,_WorldSpaceCameraPos)*4, 1); 

		o.pos = UnityObjectToClipPos(IN[i].vertex + normalize(IN[i].normal) * _outline_width_var);

		// Pass-through the shadow coordinates if this pass has shadows.
		#if defined (SHADOWS_SCREEN) || ( defined (SHADOWS_DEPTH) && defined (SPOT) ) || defined (SHADOWS_CUBE) || (defined (UNITY_LIGHT_PROBE_PROXY_VOLUME) && UNITY_VERSION<600)
		o._ShadowCoord = IN[i]._ShadowCoord;
		#endif

		// Pass-through the fog coordinates if this pass has fog.
		#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
		o.fogCoord = IN[i].fogCoord;
		#endif

		// Pass-through the vertex light information.
		o.vertexLight = IN[i].vertexLight;
		o.color = fixed4( _outline_color.r, _outline_color.g, _outline_color.b, 1)*IN[i].color;

		UNITY_TRANSFER_INSTANCE_ID(IN[i], o);

		tristream.Append(o);
	}

	tristream.RestartStrip();
	#endif

	for (int ii = 0; ii < 3; ii++)
	{
		o.pos = UnityObjectToClipPos(IN[ii].vertex);
		o.uv0 = IN[ii].uv0;
		o.uv1 = IN[ii].uv1;
		o.posWorld = mul(unity_ObjectToWorld, IN[ii].vertex);
		o.normalDir = UnityObjectToWorldNormal(IN[ii].normal);
		o.tangentDir = IN[ii].tangentDir;
		o.bitangentDir = IN[ii].bitangentDir;
		o.posWorld = mul(unity_ObjectToWorld, IN[ii].vertex); 
		o.is_outline = false;

		// Pass-through the shadow coordinates if this pass has shadows.
		#if defined (SHADOWS_SCREEN) || ( defined (SHADOWS_DEPTH) && defined (SPOT) ) || defined (SHADOWS_CUBE) || (defined (UNITY_LIGHT_PROBE_PROXY_VOLUME) && UNITY_VERSION<600)
		o._ShadowCoord = IN[ii]._ShadowCoord;
		#endif

		// Pass-through the fog coordinates if this pass has fog.
		#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
		o.fogCoord = IN[ii].fogCoord;
		#endif

		// Pass-through the vertex light information.
		o.vertexLight = IN[ii].vertexLight;
		o.color = IN[ii].color;

		UNITY_TRANSFER_INSTANCE_ID(IN[i], o);

		tristream.Append(o);
	}

	tristream.RestartStrip();
}

float4 frag(VertexOutput i, uint facing : SV_IsFrontFace) : SV_Target
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
	float3x3 tangentTransform = float3x3(i.tangentDir, i.bitangentDir, i.normalDir);

	float4 texcoords = TexCoords(i);

	SCSS_Input c = (SCSS_Input) 0;

    half3 normalTangent = NormalInTangentSpace(i.uv0, DetailMask(texcoords.xy));
    c.normal = normalize(i.tangentDir * normalTangent.x + i.bitangentDir * normalTangent.y + i.normalDir * normalTangent.z); 

	// Backface correction. If a polygon is facing away from the camera, it's lit incorrectly.
	// This will light it as though it is facing the camera (which it visually is), unless
	// it's part of an outline, in which case it's invalid and deleted. 
	facing = inMirror()? !facing : facing;
	c.normal.z *= facing? 1 : -1; 
	if (i.is_outline && !facing) discard;

	c.albedo = Albedo(texcoords);

	#if COLORED_OUTLINE
	if(i.is_outline) 
	{
		c.albedo = i.color.rgb; 
	}
	#else 
	c.albedo *= i.color.rgb;
	#endif

	c.alpha = Alpha(texcoords.xy);

	#if defined(_ALPHATEST_ON)
	// Switch between dithered alpha and sharp-edge alpha.
		if (_AlphaSharp  == 0) {
			float mask = (T(intensity(i.pos.xy + _SinTime.x%4)));
			c.alpha *= c.alpha;
			c.alpha = saturate(c.alpha + c.alpha * mask); 
			clip (c.alpha - _Cutoff);
		}
		if (_AlphaSharp  == 1) {
			c.alpha = ((c.alpha - _Cutoff) / max(fwidth(c.alpha), 0.0001) + 0.5);
			clip (c.alpha);
		}
	#endif

	#if !(defined(_ALPHATEST_ON) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON))
		c.alpha = 1.0;
	#endif

	// Lighting parameters
	SCSS_Light l = MainLight();
	#if defined(UNITY_PASS_FORWARDADD)
	l.dir = normalize(_WorldSpaceLightPos0.xyz - i.posWorld.xyz);
	#endif
	float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

	SCSS_LightParam d = (SCSS_LightParam) 0;
	d.halfDir = Unity_SafeNormalize (l.dir + viewDir);
	d.reflDir = reflect(-viewDir, c.normal); // Calculate reflection vector
	d.NdotL = saturate(dot(l.dir, c.normal)); // Calculate NdotL
	d.NdotV = saturate(dot(viewDir,  c.normal)); // Calculate NdotV
	d.LdotH = saturate(dot(l.dir, d.halfDir));
	d.NdotH = saturate(dot(c.normal, d.halfDir));
	d.rlPow4 = Pow4(float2(dot(d.reflDir, l.dir), 1 - d.NdotV));  

	c.tonemap = Tonemap(texcoords.xy, c.occlusion);

	// Specular variable setup
	if (_SpecularType != 0 )
	{
		half4 specGloss = SpecularGloss(texcoords);

		c.specColor = specGloss.rgb;
		c.smoothness = specGloss.a;

		// Because specular behaves poorly on backfaces, disable specular on outlines. 
		if(i.is_outline) 
		{
			c.specColor = 0;
			c.smoothness = 0;
		}

		// Specular energy converservation. From EnergyConservationBetweenDiffuseAndSpecular in UnityStandardUtils.cginc
		c.oneMinusReflectivity = 1 - SpecularStrength(c.specColor); 

		if (_UseMetallic == 1)
		{
			// From DiffuseAndSpecularFromMetallic
			c.oneMinusReflectivity = OneMinusReflectivityFromMetallic(c.specColor);
			c.specColor = lerp (unity_ColorSpaceDielectricSpec.rgb, c.albedo, c.specColor);
		}

		if (_UseEnergyConservation == 1)
		{
			c.albedo.xyz = c.albedo.xyz * (c.oneMinusReflectivity); 
		}

		if (_UseEnergyConservation == 1)
		{
			c.tonemap = c.tonemap * (c.oneMinusReflectivity); 
		}

		// Valve's geometic specular AA (to reduce shimmering edges)
	    float3 vNormalWsDdx = ddx(i.normalDir.xyz);
	    float3 vNormalWsDdy = ddy(i.normalDir.xyz);
	    float flGeometricRoughnessFactor = pow(saturate(max(dot(vNormalWsDdx.xyz, vNormalWsDdx.xyz), dot(vNormalWsDdy.xyz, vNormalWsDdy.xyz))), 0.333);
	    c.smoothness = min(c.smoothness, 1-flGeometricRoughnessFactor); // Ensure we don't double-count roughness if normal map encodes geometric roughness
	    	
	}

	// Lighting handling
	float3 finalColor = SCSS_ApplyLighting(c, d, i, viewDir, l, texcoords);

	#if defined(UNITY_PASS_FORWARDBASE)
	finalColor += Emission(texcoords.xy);
	finalColor += _CustomFresnelColor.xyz * (pow(d.rlPow4.y, rcp(_CustomFresnelColor.w+0.0001)));
	#endif

	float3 lightmap = float4(1.0,1.0,1.0,1.0);
	#if defined(LIGHTMAP_ON)
		lightmap = DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap, i.uv1 * unity_LightmapST.xy + unity_LightmapST.zw));
	#endif

	fixed4 finalRGBA = fixed4(finalColor * lightmap, c.alpha);
	UNITY_APPLY_FOG(i.fogCoord, finalRGBA);
	return finalRGBA;
}