Autopilot = { gen = 0 }
local A = Autopilot
local C, D, U = Config, DroneDomain, DroneUtil
local DC = DroneClient
local RESOURCE = GetCurrentResourceName()

function A.probe(state, now, interval, from, to, flags, ignore, radius)
    if state.handle then
        local status, hit, coords, _, entity = GetShapeTestResult(state.handle)
        if status == 2 then
            state.handle = nil
            state.result = { hit = hit == 1 or hit == true, coords = coords, entity = entity }
            return state.result
        elseif status == 0 then
            state.handle = nil
        end
        return nil
    end
    if now >= (state.next or 0) then
        state.next = now + interval
        if radius then
            state.handle = StartShapeTestCapsule(from.x, from.y, from.z, to.x, to.y, to.z, radius, flags, ignore or 0, 7)
        else
            state.handle = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore or 0, 7)
        end
    end
end

A.footing = {}

local function footingKey(model) return ('cxdrone:footing:1:%d'):format(model) end

local boxes = {}

local ASSET_FEET = { [joaat('rcmavic')] = 0.078 }

local function restFor(model)
    local known = A.footing[model]
    if known == nil then
        known = ASSET_FEET[model]
        if not known then
            local stored = GetResourceKvpFloat(footingKey(model))
            known = stored > 0.0 and stored or false
        end
        A.footing[model] = known
    end
    if known then return known, true end
    local box = boxes[model]
    if not box then
        local low = GetModelDimensions(model)
        box = -low.z
        boxes[model] = box
    end
    return box, false
end

function A.rest(drone)
    return restFor(GetEntityModel(drone))
end

function A.restOf(model)
    return (restFor(model))
end

function A.ground(state, now, drone, pos)
    pos = pos or GetEntityCoords(drone)
    if state.drone ~= drone then state.drone, state.model = drone, GetEntityModel(drone) end
    local result = A.probe(state, now, 100, pos - vector3(0.0, 0.0, 0.05), pos - vector3(0.0, 0.0, 300.0), state.flags or (1 | 2 | 16), drone)
    if result then
        local z = result.hit and result.coords.z or (pos.z - 300.0)
        local found, water = GetWaterHeightNoWaves(pos.x, pos.y, pos.z)
        if found and water > z then z = water end
        state.z = z
    end
    if not state.z then return nil end
    return math.max(0.0, pos.z - restFor(state.model) - state.z)
end

function A.surface(drone, pos)
    local _, hit, coords = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z + 0.5, pos.x, pos.y, pos.z - 10.0, 1 | 2 | 16, drone, 7))
    if hit == 1 or hit == true then
        local wet, water = GetWaterHeightNoWaves(pos.x, pos.y, pos.z)
        if wet and water > coords.z then return water, true end
        return coords.z, false
    end
    local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.5, false)
    local wet, water = GetWaterHeightNoWaves(pos.x, pos.y, pos.z)
    if wet and (not found or water > z) then return water, true end
    return found and z or nil, false
end

local function grounded(drone)
    local s = DC.session
    return s and s.entity == drone and s.state == 'landed' and DoesEntityExist(drone)
end

local function calibrate(drone, ground, heading)
    if A.calibrating then return end
    A.calibrating = true
    CreateThread(function()
        local model = GetEntityModel(drone)
        FreezeEntityPosition(drone, false)
        SetVehicleGravity(drone, true)
        local last, steady, frames = GetEntityCoords(drone).z, 0, 0
        while frames < 150 and grounded(drone) do
            SetEntityRotation(drone, 0.0, 0.0, U.F(heading), 2, true)
            SetEntityVelocity(drone, 0.0, 0.0, -0.6)
            Wait(0)
            frames = frames + 1
            local z = GetEntityCoords(drone).z
            steady = math.abs(z - last) < 0.002 and steady + 1 or 0
            last = z
            if frames > 5 and steady >= 8 then break end
        end
        if grounded(drone) then
            SetEntityVelocity(drone, 0.0, 0.0, 0.0)
            SetEntityRotation(drone, 0.0, 0.0, U.F(heading), 2, true)
            FreezeEntityPosition(drone, true)
            local rest = GetEntityCoords(drone).z - ground
            local low = GetModelDimensions(model)
            if steady >= 8 and rest > 0.02 and rest <= -low.z + 0.05 then
                A.footing[model] = rest
                SetResourceKvpFloat(footingKey(model), rest)
                print(('[%s] calibrated landing height %.3f m (model box %.3f m)'):format(RESOURCE, rest, -low.z))
            end
        end
        A.calibrating = false
    end)
end

function A.settle(drone, heading)
    heading = heading or GetEntityHeading(drone)
    local pos = GetEntityCoords(drone)
    SetEntityRotation(drone, 0.0, 0.0, U.F(heading), 2, true)
    SetEntityVelocity(drone, 0.0, 0.0, 0.0)
    local ground, water = A.surface(drone, pos)
    if not ground then FreezeEntityPosition(drone, true); return end
    local rest, measured = A.rest(drone)
    SetEntityCoordsNoOffset(drone, pos.x, pos.y, U.F(ground + rest + 0.002), false, false, false)
    FreezeEntityPosition(drone, true)
    if not measured and not water then calibrate(drone, ground, heading) end
end

function A.home()
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    return vector3(at.x + fwd.x * 1.6, at.y + fwd.y * 1.6, at.z)
end

function A.descent(agl)
    if agl > 4.0 then return -3.0 end
    return -C.flight.landingSpeed
end

function A.returnStep(rth, drone, pos, agl, dt)
    local home = A.home()
    local dx, dy = home.x - pos.x, home.y - pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 2.5 then
        rth.descending = false
        local cruise = dist > 20.0 and math.max(pos.z, home.z - 1.0 + C.flight.returnAltitude) or pos.z
        local dir = vector3(dx / dist, dy / dist, 0.0)
        rth.ahead = rth.ahead or {}
        local probe = A.probe(rth.ahead, U.now(), 200, pos, pos + dir * 10.0, 1 | 16, drone)
        if probe then rth.blocked = probe.hit end
        if rth.blocked then cruise = pos.z + 6.0 end
        if rth.roof then cruise = math.min(cruise, pos.z) end
        local vz = D.clamp((cruise - pos.z) * 0.8, -4.0, 5.0)
        local speed = math.min(C.flight.returnSpeed, dist * 0.6 + 0.5)
        if rth.blocked or (dist > 20.0 and pos.z < cruise - 3.0) then speed = 0.0 end
        return vector3(dir.x * speed, dir.y * speed, vz), U.heading(dx, dy), false
    end
    rth.descending = true
    if agl < 0.4 then return vector3(0.0, 0.0, 0.0), nil, true end
    return vector3(dx * 0.8, dy * 0.8, A.descent(agl)), nil, false
end

local function approach(current, target, step)
    local delta = target - current
    local length = #delta
    if length <= step or length == 0.0 then return target end
    return current + delta * (step / length)
end

function A.unattended(action, heading)
    local s = DC.session
    if not s or not DoesEntityExist(s.entity) then return end
    local drone = s.entity
    A.gen = A.gen + 1
    local gen = A.gen
    A.action, A.actionGen = action, gen
    FreezeEntityPosition(drone, false)
    SetVehicleEngineOn(drone, true, true, true)
    SetVehicleGravity(drone, false)
    CreateThread(function()
        local state, ground, above = { forced = true, reason = 'leave' }, {}, {}
        local vel = vector3(0.0, 0.0, 0.0)
        local last = U.now()
        while gen == A.gen and DC.session == s and not DC.piloting and DoesEntityExist(drone) and s.state == 'unattended' do
            local now = U.now()
            local dt = D.clamp((now - last) / 1000.0, 0.001, 0.1)
            last = now
            if not NetworkHasControlOfEntity(drone) then NetworkRequestControlOfEntity(drone) end
            local agl = A.ground(ground, now, drone) or 5.0
            local pos = GetEntityCoords(drone)
            local tv, wanted, landed
            if action == 'return' then
                local over = A.probe(above, now, 200, pos, pos + vector3(0.0, 0.0, 2.5), 1 | 16, drone)
                if over then state.roof = over.hit end
                tv, wanted, landed = A.returnStep(state, drone, pos, agl, dt)
            else
                tv, landed = vector3(0.0, 0.0, A.descent(agl)), agl < 0.4
            end
            if landed then
                SetVehicleEngineOn(drone, false, true, true)
                SetHeliBladesSpeed(drone, 0.0)
                SetVehicleGravity(drone, true)
                s.state = 'landed'
                A.settle(drone, heading)
                TriggerServerEvent(RESOURCE .. ':leave', { state = 'landed' })
                break
            end
            vel = approach(vel, tv, 8.0 * dt)
            if wanted then heading = heading + U.angleDelta(heading, wanted) * math.min(1.0, dt * 2.5) end
            SetEntityRotation(drone, 0.0, 0.0, U.F(heading), 2, true)
            SetEntityVelocity(drone, U.F(vel.x), U.F(vel.y), U.F(vel.z))
            Wait(0)
        end
    end)
end

local function cut(drone)
    FreezeEntityPosition(drone, false)
    SetVehicleKeepEngineOnWhenAbandoned(drone, false)
    SetVehicleEngineOn(drone, false, true, true)
    SetHeliBladesSpeed(drone, 0.0)
    SetVehicleGravity(drone, true)
end

local function wreck(s)
    s.state = 'crashed'
    local result = U.call('crash', { reason = 'impact' })
    if DC.session ~= s or (result and result.ok and result.data and result.data.destroyed) then return end
    U.notify('notify.crashed', 'info')
end

function A.fall(drone)
    local s = DC.session
    if not s or not DoesEntityExist(drone) then return end
    A.gen = A.gen + 1
    local gen = A.gen
    s.descending = true
    CreateThread(function()
        local powered, vel, still, since, last = true, GetEntityVelocity(drone), 0.0, nil, U.now()
        while gen == A.gen and DC.session == s and not DC.piloting and DoesEntityExist(drone) and s.state == 'unattended' do
            local now = U.now()
            local dt = D.clamp((now - last) / 1000.0, 0.001, 0.1)
            last = now
            if not NetworkHasControlOfEntity(drone) then
                NetworkRequestControlOfEntity(drone)
            else
                if powered then
                    powered, since = false, now
                    cut(drone)
                end
                local measured = GetEntityVelocity(drone)
                if HasEntityCollidedWithAnything(drone) and #(vel - measured) > C.flight.crashSpeed then wreck(s); break end
                vel = measured
                still = #measured < 0.3 and still + dt or 0.0
                if still > 1.0 or now - since > 10000 then
                    FreezeEntityPosition(drone, true)
                    s.state = 'landed'
                    TriggerServerEvent(RESOURCE .. ':leave', { state = 'landed' })
                    break
                end
            end
            Wait(0)
        end
    end)
end

function A.cancel() A.gen = A.gen + 1 end

function A.active() return A.actionGen == A.gen and A.action or nil end
