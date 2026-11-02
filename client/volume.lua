DroneVolume = {}
local V = DroneVolume
local C = Config
local Volumetric = CortexVolumetric

local function settings() return C.spotlight.volumetric end

local function active()
    return settings().enabled and Volumetric ~= nil and Volumetric.playerEnabled()
end

local beam
local function get()
    if not beam then
        local cfg = settings()
        beam = Volumetric.new({
            txd = 'cxdrone_volume',
            discs = 40,
            maxBeams = 3,
            discAlpha = cfg.alpha,
            discFalloff = cfg.falloff,
            discNear = 0.1,
            coneScale = cfg.coneScale,
            sourceRadius = cfg.sourceRadius,
            openFade = cfg.openFade,
            contactSoftness = 0.6,
            phase = 0.5,
            glare = 120,
            inside = { behind = 1.0, margin = 0.3, soften = 0.5 },
            maxDrawDistance = cfg.maxDrawDistance,
            drawDistanceFrom = 'origin',
            traceFlags = 1 + 16,
            rayStart = 0.3,
            maxEndRadius = 10.0,
            paintEarly = active(),
        })
    end
    return beam
end

if Volumetric and settings().enabled then
    if active() then get() end
    Volumetric.onPlayerSetting(function(on)
        if on and active() then get() elseif not on and beam then beam:clear() end
    end)
end

local params = {}

function V.draw(entity, from, dir)
    if not active() then return false end
    local b = get()
    local dark = b:darkness(settings().dayFactor, false)
    if dark <= 0.0 then return false end
    local s = C.spotlight
    params.key, params.ignore = entity, entity
    params.ox, params.oy, params.oz = from.x, from.y, from.z
    params.dx, params.dy, params.dz = dir.x, dir.y, dir.z
    params.radius, params.length = s.radius, nil
    params.range = math.min(s.distance, settings().maxLength)
    params.r, params.g, params.b = s.colour[1], s.colour[2], s.colour[3]
    params.strength = dark
    return b:draw(params)
end
