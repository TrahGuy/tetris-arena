-- Block Arena — Lighting for an interior hall.
--
-- The single biggest reason the lobby read as "neon" was Bloom: intensity 0.95
-- at threshold 0.92 makes every mildly bright surface bleed light, which turns
-- accent trim into glow strips and flattens everything into the same haze.
-- Bloom is now low and high-threshold, so only genuinely emissive signage
-- blooms. Material and light do the rest of the work.
--
-- Lighting.Technology is NOT set here — it is not scriptable and cannot even be
-- read from the plugin context. Set it to ShadowMap by hand in Properties.

local Lighting = game:GetService("Lighting")

-- Night outside; the hall is lit by its own ceiling, so sun brightness barely
-- matters. Ambient is neutral grey, not violet — a colour cast on ambient tints
-- every concrete surface and reads as "everything is glowing".
Lighting.ClockTime = 0
Lighting.Brightness = 1.1
-- Low on purpose. The ceiling fixtures do the lighting; ambient only stops the
-- shadow side going black. Push it up and the hall flattens into an office.
Lighting.Ambient = Color3.fromRGB(26, 26, 31)
Lighting.OutdoorAmbient = Color3.fromRGB(22, 23, 30)
Lighting.EnvironmentDiffuseScale = 0.2
Lighting.EnvironmentSpecularScale = 0.4
Lighting.ExposureCompensation = 0
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.5
-- Indoors, so fog is pushed well past the far wall; it exists only for the city.
Lighting.FogColor = Color3.fromRGB(34, 36, 46)
Lighting.FogStart = 400
Lighting.FogEnd = 1200
Lighting.ColorShift_Top = Color3.fromRGB(24, 22, 34)
Lighting.ColorShift_Bottom = Color3.fromRGB(16, 18, 24)

local function ensure(class, name)
	local inst = Lighting:FindFirstChild(name)
	if inst and not inst:IsA(class) then inst:Destroy(); inst = nil end
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end

local sky = ensure("Sky", "Sky")
sky.CelestialBodiesShown = true
sky.StarCount = 3000
sky.SunAngularSize = 0
sky.MoonAngularSize = 0

-- Thin. It only has to give the city outside the glazing some depth; heavy haze
-- inside a lit hall just greys everything out.
local atmo = ensure("Atmosphere", "Atmosphere")
atmo.Density = 0.2
atmo.Offset = 0.2
atmo.Color = Color3.fromRGB(48, 48, 62)
atmo.Decay = Color3.fromRGB(72, 60, 104)
atmo.Glare = 0.1
atmo.Haze = 1.2

-- Was 0.95 / 0.92. Now only genuinely emissive signage crosses the threshold.
local bloom = ensure("BloomEffect", "Bloom")
bloom.Intensity = 0.38
bloom.Size = 20
bloom.Threshold = 1.05
bloom.Enabled = true

local dof = ensure("DepthOfFieldEffect", "DepthOfField")
dof.FarIntensity = 0.08
dof.FocusDistance = 60
dof.InFocusRadius = 220
dof.NearIntensity = 0
dof.Enabled = true

ensure("SunRaysEffect", "SunRays").Enabled = false

-- Slightly desaturated and near-neutral. The accents are strong enough on their
-- own; pushing saturation was making concrete look purple.
local grade = ensure("ColorCorrectionEffect", "Grade")
grade.Brightness = 0.008
grade.Contrast = 0.05
grade.Saturation = -0.04
grade.TintColor = Color3.fromRGB(250, 249, 252)
grade.Enabled = true

return "lighting: interior hall (set Technology = ShadowMap by hand)"
