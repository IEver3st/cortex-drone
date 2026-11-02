DroneClient = { session = nil, piloting = false, stopped = false }
local U = {}
DroneUtil = U
local RESOURCE = GetCurrentResourceName()

function U.F(value) return (tonumber(value) or 0) + 0.0 end
function U.I(value) return math.floor((tonumber(value) or 0) + 0.5) end

function U.now() return GetGameTimer() end

function U.lampPosition(entity) return GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.075, -0.065) end

function U.loadModel(model, timeout)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = U.now() + (timeout or 5000)
    while not HasModelLoaded(hash) do
        if U.now() > deadline then return nil end
        Wait(0)
    end
    return hash
end

function U.deleteEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return true end
    if IsEntityAttached(entity) then DetachEntity(entity, false, false) end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
    return not DoesEntityExist(entity)
end

function U.hardenDrone(entity)
    SetVehicleEngineCanDegrade(entity, false)
    SetDisableVehicleEngineFires(entity, true)
    SetDisableVehiclePetrolTankFires(entity, true)
    SetDisableVehiclePetrolTankDamage(entity, true)
    SetVehicleCanLeakOil(entity, false)
    SetVehicleCanLeakPetrol(entity, false)
    SetVehicleDirtLevel(entity, 0.0)
    WashDecalsFromVehicle(entity, 1.0)
end

function U.foldEngineDamage(entity)
    local engine = GetVehicleEngineHealth(entity)
    if engine >= 1000.0 then return end
    local body = GetVehicleBodyHealth(entity)
    if body > 0.0 then SetVehicleBodyHealth(entity, U.F(math.max(0.0, body - (1000.0 - engine)))) end
    SetVehicleEngineHealth(entity, 1000.0)
end

function U.underWorld(entity)
    local pos = GetEntityCoords(entity)
    local found, ground = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 100.0, false)
    if not found or ground <= pos.z + 0.5 then return nil end
    local handle = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z, pos.x, pos.y, pos.z - 300.0, 1, entity, 7)
    local _, hit = GetShapeTestResult(handle)
    if hit == 1 or hit == true then return nil end
    return ground
end

function U.lift(entity, ground, rest)
    local pos = GetEntityCoords(entity)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityRotation(entity, 0.0, 0.0, U.F(GetEntityHeading(entity)), 2, true)
    SetEntityCoordsNoOffset(entity, pos.x, pos.y, U.F(ground + rest + 0.002), false, false, false)
end

function U.loadAnim(dict, timeout)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local deadline = U.now() + (timeout or 3000)
    while not HasAnimDictLoaded(dict) do
        if U.now() > deadline then return false end
        Wait(0)
    end
    return true
end

function U.sound(name)
    local sound = Config.sounds[name]
    if not sound then return end
    PlaySoundFrontend(-1, sound.name, sound.set, true)
end

function U.hud(visible)
    if not Config.hideHud then return end
    TriggerEvent(RESOURCE .. ':hud', visible)
    if GetResourceState('cortex-hud') ~= 'started' then return end
    pcall(function()
        if visible then exports['cortex-hud']:showHud(RESOURCE) else exports['cortex-hud']:hideHud(RESOURCE) end
    end)
end

function U.notify(key, kind, vars)
    if lib and lib.notify then lib.notify({ description = L(key, vars), type = kind or 'error' }) end
end

RegisterNetEvent(RESOURCE .. ':notify', function(key, kind, vars)
    if type(key) ~= 'string' or #key > 64 then return end
    U.notify(key, type(kind) == 'string' and kind or 'error', type(vars) == 'table' and vars or nil)
end)

RegisterNetEvent(RESOURCE .. ':operator', function(text)
    if type(text) == 'string' then print(('[%s] %s'):format(RESOURCE, text:sub(1, 4000))) end
end)

function U.call(name, payload)
    local ok, result = pcall(function() return lib.callback.await(RESOURCE .. ':' .. name, false, payload or {}) end)
    if not ok or type(result) ~= 'table' then return nil end
    return result
end

function U.accent()
    local ok, data = pcall(function() return exports['cortex-lib']:getPresentation() end)
    local value = ok and type(data) == 'table' and type(data.profile) == 'table' and data.profile.accent
    if type(value) ~= 'string' or not value:match('^#%x%x%x%x%x%x$') then value = '#8fcbbf' end
    return tonumber(value:sub(2, 3), 16), tonumber(value:sub(4, 5), 16), tonumber(value:sub(6, 7), 16)
end

function U.control(entity, timeout)
    if NetworkHasControlOfEntity(entity) then return true end
    local deadline = U.now() + (timeout or 2000)
    while not NetworkHasControlOfEntity(entity) do
        if U.now() > deadline or not DoesEntityExist(entity) then return false end
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return true
end

function U.entity(netId, timeout)
    local deadline = U.now() + (timeout or 5000)
    while not NetworkDoesEntityExistWithNetworkId(netId) do
        if U.now() > deadline then return 0 end
        Wait(0)
    end
    local entity = NetToVeh(netId)
    deadline = U.now() + 1000
    while entity == 0 or not DoesEntityExist(entity) do
        if U.now() > deadline then return 0 end
        Wait(0)
        entity = NetToVeh(netId)
    end
    return entity
end

function U.heading(dx, dy)
    return (math.deg(math.atan(-dx, dy)) + 360.0) % 360.0
end

function U.compass(gtaHeading)
    return (360.0 - gtaHeading) % 360.0
end

function U.angleDelta(from, to)
    return (to - from + 540.0) % 360.0 - 180.0
end

function U.rotationToDirection(pitch, heading)
    local p, h = math.rad(pitch), math.rad(heading)
    return vector3(-math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), math.sin(p))
end

local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

function U.qnorm(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-9 then return vector4(0.0, 0.0, 0.0, 1.0) end
    return vector4(q.x / n, q.y / n, q.z / n, q.w / n)
end

function U.qmul(a, b)
    return vector4(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
end

function U.qturn(v)
    local angle = #v
    if angle < 1e-9 then return U.qnorm(vector4(v.x * 0.5, v.y * 0.5, v.z * 0.5, 1.0)) end
    local s = math.sin(angle * 0.5) / angle
    return vector4(v.x * s, v.y * s, v.z * s, math.cos(angle * 0.5))
end

function U.qrot(q, v)
    local u = vector3(q.x, q.y, q.z)
    local t = cross(u, v) * 2.0
    return v + t * q.w + cross(u, t)
end

function U.qyaw(heading)
    local h = math.rad(heading) * 0.5
    return vector4(0.0, 0.0, math.sin(h), math.cos(h))
end

local function qdot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w end

function U.qangle(a, b)
    return math.deg(2.0 * math.acos(math.min(1.0, math.abs(qdot(a, b)))))
end

function U.qslerp(a, b, t)
    local d = qdot(a, b)
    if d < 0.0 then b, d = vector4(-b.x, -b.y, -b.z, -b.w), -d end
    if d > 0.9995 then
        return U.qnorm(vector4(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t))
    end
    local theta = math.acos(d)
    local s = math.sin(theta)
    local wa, wb = math.sin((1.0 - t) * theta) / s, math.sin(t * theta) / s
    return vector4(a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb, a.w * wa + b.w * wb)
end

function U.euler(q)
    local fwd = U.qrot(q, vector3(0.0, 1.0, 0.0))
    local right = U.qrot(q, vector3(1.0, 0.0, 0.0))
    local up = U.qrot(q, vector3(0.0, 0.0, 1.0))
    local pitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, fwd.z))))
    if fwd.x * fwd.x + fwd.y * fwd.y < 1e-8 then return pitch, 0.0, math.deg(math.atan(right.y, right.x)) end
    return pitch, math.deg(math.atan(-right.z, up.z)), math.deg(math.atan(-fwd.x, fwd.y))
end

function U.qspin(from, to, dt)
    local d = U.qmul(to, vector4(-from.x, -from.y, -from.z, from.w))
    if d.w < 0.0 then d = vector4(-d.x, -d.y, -d.z, -d.w) end
    local s = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    if s < 1e-9 then return vector3(0.0, 0.0, 0.0) end
    return vector3(d.x, d.y, d.z) * (2.0 * math.atan(s, d.w) / s / dt)
end

function U.quaternion(entity)
    local x, y, z, w = GetEntityQuaternion(entity)
    return U.qnorm(vector4(x, y, z, w))
end

function U.playOnce(dict, name, duration, flag)
    if not U.loadAnim(dict) then return end
    TaskPlayAnim(PlayerPedId(), dict, name, 8.0, -8.0, duration or -1, flag or 0, 0.0, false, false, false)
    RemoveAnimDict(dict)
end
