-- Block Arena — Lighting.
--
-- Tuned so surfaces actually catch light. The first pass was a true midnight
-- (Brightness 0.75, Ambient 10/6/18) and everything that was not emissive
-- rendered pure black, which made a 300x300 lobby read as an empty void. The
-- neon still carries the look; ambient just has to lift the carbon and glass
-- enough to see that they are there.
--
-- Lighting.Technology is NOT set here — it is not scriptable and cannot even be
-- read from the plugin context. Set it to ShadowMap by hand in Properties.

local Lighting = game:GetService("Lighting")

Lighting.ClockTime = 0
Lighting.Brightness = 1.7
Lighting.Ambient = Color3.fromRGB(30, 28, 40)
Lighting.OutdoorAmbient = Color3.fromRGB(40, 37, 54)
Lighting.EnvironmentDiffuseScale = 0.45
Lighting.EnvironmentSpecularScale = 0.5
Lighting.ExposureCompensation = 0.05
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.4
Lighting.FogColor = Color3.fromRGB(26, 20, 40)
Lighting.FogStart = 120
Lighting.FogEnd = 480
Lighting.ColorShift_Top = Color3.fromRGB(38, 18, 66)
Lighting.ColorShift_Bottom = Color3.fromRGB(0, 34, 52)

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
sky.StarCount = 6000
sky.SunAngularSize = 0
sky.MoonAngularSize = 0

-- Haze carries the sky. With the stock skybox at midnight everything above the
-- horizon renders flat black, so the haze band is the only thing separating
-- "night" from "nothing" — hence the lifted Colour and the wide Offset.
local atmo = ensure("Atmosphere", "Atmosphere")
atmo.Density = 0.36
atmo.Offset = 0.3
atmo.Color = Color3.fromRGB(54, 44, 80)
atmo.Decay = Color3.fromRGB(112, 54, 152)
atmo.Glare = 0.45
atmo.Haze = 2.9

-- Threshold raised with the brightness, or the whole scene blooms.
local bloom = ensure("BloomEffect", "Bloom")
bloom.Intensity = 0.95
bloom.Size = 36
bloom.Threshold = 0.92
bloom.Enabled = true

local dof = ensure("DepthOfFieldEffect", "DepthOfField")
dof.FarIntensity = 0.15
dof.FocusDistance = 40
dof.InFocusRadius = 140
dof.NearIntensity = 0
dof.Enabled = true

ensure("SunRaysEffect", "SunRays").Enabled = false

-- Contrast pulled back from 0.22: it was crushing the shadow end to black.
local grade = ensure("ColorCorrectionEffect", "Grade")
grade.Brightness = 0.012
grade.Contrast = 0.1
grade.Saturation = 0.14
grade.TintColor = Color3.fromRGB(240, 236, 255)
grade.Enabled = true

return "lighting configured (set Technology = ShadowMap by hand)"
