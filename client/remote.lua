DroneRemote = { known = {} }
local R = DroneRemote
local C, D, U = Config, DroneDomain, DroneUtil
local DC = DroneClient
local MODEL = joaat(C.model)
local known = R.known
local lit = {}
local tilts = {}
local litGen = 0
local AIRBORNE = { flying = true, unattended = true }

local function plain(value)
    if type(value) ~= 'table' then return nil end
    return {
        owner = tonumber(value.owner) or 0, kind = type(value.kind) == 'string' and value.kind or '',
        light = value.light == true, tilt = D.finite(value.tilt) and value.tilt or C.spotlight.traverse.max,
        state = type(value.state) == 'string' and value.state or 'landed',
    }
end

local MAX_LIGHTS, MAX_SHADOWS = 6, 2
local nearest = {}

local function closer(a, b) return a.dist < b.dist end

local function drawLights()
    litGen = litGen + 1
    local gen = litGen
    CreateThread(function()
        local s = C.spotlight
        local r, g, b = U.I(s.colour[1]), U.I(s.colour[2]), U.I(s.colour[3])
        local slew = s.slew
        while gen == litGen and next(lit) do
            local own = DC.session and DC.session.entity
            local flown = DC.piloting and own
            local origin
            local count = 0
            for entity in pairs(lit) do
                if entity ~= flown then
                    if not DoesEntityExist(entity) or GetEntityModel(entity) ~= MODEL then
                        known[entity], lit[entity], tilts[entity] = nil, nil, nil
                    else
                        origin = origin or GetFinalRenderedCamCoord()
                        local from = U.lampPosition(entity)
                        local dist = #(from - origin)
                        if dist < 250.0 then
                            count = count + 1
                            local slot = nearest[count] or {}
                            nearest[count] = slot
                            slot.entity, slot.from, slot.dist = entity, from, dist
                        end
                    end
                end
            end
            for i = #nearest, count + 1, -1 do nearest[i] = nil end
            if count > 1 then table.sort(nearest, closer) end
            local dt = count > 0 and GetFrameTime() or 0.0
            local reach = slew * dt
            local ease = math.min(1.0, dt * 5.0)
            for index = 1, math.min(count, MAX_LIGHTS) do
                local slot = nearest[index]
                local entity, from = slot.entity, slot.from
                local tilt, heading
                if entity == own then tilt, heading = Pilot.beam() end
                if not tilt then
                    local info = known[entity]
                    local want = info and info.tilt or s.traverse.max
                    tilt = tilts[entity] or want
                    tilt = tilt + D.clamp((want - tilt) * ease, -reach, reach)
                    heading = GetEntityHeading(entity)
                end
                tilts[entity] = tilt
                local dir = U.rotationToDirection(tilt, heading)
                if index <= MAX_SHADOWS then
                    DrawSpotLightWithShadow(from.x, from.y, from.z, dir.x, dir.y, dir.z, r, g, b,
                        U.F(s.distance), U.F(s.brightness), U.F(s.hardness), U.F(s.radius), U.F(s.falloff), 20 + index)
                else
                    DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, r, g, b,
                        U.F(s.distance), U.F(s.brightness), U.F(s.hardness), U.F(s.radius), U.F(s.falloff))
                end
                DroneVolume.draw(entity, from, dir)
            end
            Wait(0)
        end
    end)
end

local spinning = false

local function spinRotors()
    if spinning then return end
    spinning = true
    CreateThread(function()
        while not DC.stopped and next(known) do
            local own = DC.session and (DC.piloting or Pilot.launching()) and DC.session.entity
            local origin = GetFinalRenderedCamCoord()
            local speed = U.F(C.rotors.hover)
            local near = false
            for entity in pairs(known) do
                if entity ~= own and DoesEntityExist(entity) and GetIsVehicleEngineRunning(entity)
                    and #(GetEntityCoords(entity) - origin) < 200.0 then
                    SetHeliBladesSpeed(entity, speed)
                    near = true
                end
            end
            Wait(near and 0 or 500)
        end
        spinning = false
    end)
end

local function setLit(entity, on)
    local was = next(lit) ~= nil
    lit[entity] = on or nil
    if on and not was then drawLights() end
end

AddStateBagChangeHandler('cxDrone', nil, function(bagName, _, value)
    local info = plain(value)
    local entity = GetEntityFromStateBagName(bagName)
    for _ = 1, 60 do
        if entity ~= 0 then break end
        Wait(0)
        entity = GetEntityFromStateBagName(bagName)
    end
    if entity == 0 then return end
    if not info then
        known[entity], lit[entity], tilts[entity] = nil, nil, nil
        return
    end
    if GetEntityModel(entity) ~= MODEL then return end
    if not known[entity] then U.hardenDrone(entity) end
    known[entity] = info
    setLit(entity, info.light and AIRBORNE[info.state] == true)
    spinRotors()
    if info.state == 'destroyed' then
        SetVehicleEngineOn(entity, false, true, true)
    end
end)

CreateThread(function()
    while not DC.stopped do
        Wait(5000)
        for entity in pairs(known) do
            if not DoesEntityExist(entity) then known[entity], lit[entity], tilts[entity] = nil, nil, nil end
        end
    end
end)

local tablets = {}
local MAX_TABLETS = 16

local function removeTablet(id)
    local entry = tablets[id]
    tablets[id] = nil
    if entry and entry.prop and DoesEntityExist(entry.prop) then
        DetachEntity(entry.prop, false, true)
        DeleteEntity(entry.prop)
    end
end

local function spawnTablet(id, ped)
    local prop = C.pilot.prop
    if not prop then return end
    local hash = U.loadModel(prop.model, 2000)
    if not hash or not DoesEntityExist(ped) then return end
    local at = GetEntityCoords(ped)
    local object = CreateObject(hash, at.x, at.y, at.z + 0.2, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(object, false, false)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, prop.bone), U.F(prop.offset.x), U.F(prop.offset.y), U.F(prop.offset.z),
        U.F(prop.rotation.x), U.F(prop.rotation.y), U.F(prop.rotation.z), true, true, false, false, 2, true)
    tablets[id] = { ped = ped, prop = object }
end

local pilots = {}
local tabletGen = 0

local function watchTablets()
    tabletGen = tabletGen + 1
    local gen = tabletGen
    CreateThread(function()
        while gen == tabletGen and not DC.stopped and (next(pilots) or next(tablets)) do
            local origin = GetEntityCoords(PlayerPedId())
            local seen, count = {}, 0
            for id in pairs(pilots) do
                local player = GetPlayerFromServerId(id)
                local ped = player ~= -1 and GetPlayerPed(player) or 0
                if ped ~= 0 and DoesEntityExist(ped) and count < MAX_TABLETS and #(GetEntityCoords(ped) - origin) <= 80.0 then
                    seen[id], count = true, count + 1
                    local entry = tablets[id]
                    if not entry or entry.ped ~= ped or not DoesEntityExist(entry.prop) then
                        removeTablet(id)
                        spawnTablet(id, ped)
                    end
                end
            end
            for id in pairs(tablets) do if not seen[id] then removeTablet(id) end end
            Wait(500)
        end
    end)
end

AddStateBagChangeHandler('cxDronePilot', nil, function(bagName, _, value)
    if not C.pilot.othersSeeTablet or not C.pilot.prop then return end
    local id = tonumber(bagName:match('^player:(%d+)$'))
    if not id or id == GetPlayerServerId(PlayerId()) then return end
    local was = next(pilots) ~= nil or next(tablets) ~= nil
    pilots[id] = value == true or nil
    if not pilots[id] then removeTablet(id) end
    if not was and next(pilots) then watchTablets() end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    litGen = litGen + 1
    for id in pairs(tablets) do removeTablet(id) end
end)
