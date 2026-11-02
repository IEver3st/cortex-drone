Pilot = {}
local P = Pilot
local C, D, U, H = Config, DroneDomain, DroneUtil, DroneHud
local DC = DroneClient
local PF = DroneProfile
local CI = Cinematic
local RESOURCE = GetCurrentResourceName()

local MODES = { normal = 'sport', sport = 'cine', cine = 'normal' }
local SPEED_MODES = { cine = true, normal = true, sport = true }
local LAST_MODE = 'cxdrone:lastMode'
local STUNGUN = joaat('WEAPON_STUNGUN')
local UNARMED = joaat('WEAPON_UNARMED')
local FUZZ = 'CAMERA_secuirity_FUZZ'
local SEE = 1 | 2 | 4 | 8 | 16
local BODIES = 2 | 4 | 8
local GROUND = 1 | 16
local SOLID = 1 | 2 | 16
local CLEAR = 0.15
local CAMERA = 1 | 2 | 4 | 16
local LEASH = math.max(0.3, C.signal.fadeStart + (1.0 - C.signal.fadeStart) * (0.85 - C.signal.obstructionPenalty))
local IDLE = { x = 0.0, y = 0.0, z = 0.0, yaw = 0.0, tilt = 0.0, lx = 0.0, ly = 0.0, any = false }
local DETACH = { leave = true, pilot = true, pilot_hit = true }
local GRAVITY = 9.81
local UP = vector3(0.0, 0.0, 1.0)
local IDENTITY = vector4(0.0, 0.0, 0.0, 1.0)
local LOOK_EASE = 10.0
local LENS_SPRING, TRICK_SPRING = 11.0, 9.0
local GRIP_FADE, FLARE_EASE, LEAN_SPRING, ROLL_SPRING, CRUISE_LEAN = 30.0, 0.8, 22.0, 15.0, 22.0
local AIR_LINEAR, AIR_SQUARE = 0.03, 0.002
local AIM_LIMIT, NOSE_SPRING, NOSE_SPEED = 90.0, 8.0, 0.4
local STILL = vector3(0.0, 0.0, 0.0)
local f = {}

local function reset()
    f = {
        cam = nil, view = 'gimbal', heading = 0.0, body = 0.0, gimbal = -10.0, zoom = 1.0, fov = C.camera.fov,
        vision = 'normal', light = false, mode = 'normal', boost = false, vel = vector3(0.0, 0.0, 0.0),
        pitch = 0.0, roll = 0.0, lock = nil, armed = false, armHeld = 0.0, fired = -100000,
        rth = nil, landing = false, motors = false, takeoff = nil, landTimer = 0.0,
        agl = 0.0, groundProbe = {}, losProbe = {}, rangeProbe = {}, aheadProbe = {}, aboveProbe = {}, clearProbe = {},
        range = nil, rangePoint = nil, acquiring = nil, braking = false, lightPitch = C.spotlight.traverse.max, chase = 1.0, tucked = false,
        quality = 1.0, bars = 5, obstructed = false, lostSince = nil,
        health = 0.0, pedHealth = 0, zone = nil, distance = 0.0,
        nextSlow = 0, nextHud = 0, nextPlace = 0, nextPresent = 0, sentTilt = nil, sentLight = nil,
        warned = {}, fuzz = 0.0, status = 'flying', statusUntil = 0, ending = nil,
        spin = 0.0, nextAnim = 0, legendUntil = 0, legendSig = nil, lowReturned = false, kb = IsUsingKeyboard(2),
        detached = nil, acro = nil, glide = nil, lens = nil, recover = nil, hardCam = false, input = {}, cine = nil, pendingLeave = false,
        pendingAcro = false, boostLatch = false,
    }
end
reset()

local function kind() return DC.session and DC.session.conf end

local function downed(ped) return IsEntityDead(ped) or GetEntityHealth(ped) <= 101 end

local function filming() return f.cine ~= nil and f.cine.self end

local function speeds()
    local conf = kind()
    local mode = (f.boost or f.glide) and 'sport' or f.mode
    return conf.speeds[mode]
end

local function acroRate() return DC.prefs.acroRates / 100.0 end
local function acroTilt() return DC.prefs.acroTilt end

local function remember(mode)
    SetResourceKvp(LAST_MODE, mode)
end

local function keyboard() return f.kb end
local function controls() return keyboard() and C.controls.keyboard or C.controls.pad end
local function pressed(name) return IsDisabledControlJustPressed(0, controls()[name]) end
local function held(name) return IsDisabledControlPressed(0, controls()[name]) end
local function released(name) return IsDisabledControlJustReleased(0, controls()[name]) end
local function axis(name) return GetDisabledControlNormal(0, controls()[name]) end

local function forward(heading)
    local h = math.rad(heading)
    return vector3(-math.sin(h), math.cos(h), 0.0), vector3(math.cos(h), math.sin(h), 0.0)
end

local function flat(v) return vector3(v.x, v.y, 0.0) end

local function approach(current, target, step)
    local delta = target - current
    local length = #delta
    if length <= step or length == 0.0 then return target end
    return current + delta * (step / length)
end

local function lerp(a, b, t) return a + (b - a) * math.min(1.0, t) end

local function present(now, force)
    if now < f.nextPresent then
        if force then f.sentLight = nil end
        return
    end
    local tilt = math.floor(f.lightPitch + 0.5)
    if not force and f.sentLight == f.light and f.sentTilt and math.abs(f.sentTilt - tilt) < 1 then return end
    f.nextPresent = now + 250
    f.sentLight, f.sentTilt = f.light, tilt
    TriggerServerEvent(RESOURCE .. ':presentation', { light = f.light, tilt = tilt })
end

local function legendRows()
    local conf = kind()
    local pad = not keyboard()
    local key = pad and {
        move = 'LS', look = 'RS', climb = 'RT LT', mode = 'R3', zoom = 'D-PAD', vision = 'RB', light = 'D-PAD',
        lock = 'X', payload = 'Y', view = 'BACK', home = 'D-PAD', leave = 'B', boost = 'A', acro = 'LB', throttle = 'RT LT', cinematic = 'L3',
    } or {
        move = 'W A S D', look = L('key.mouse'), climb = 'SPACE CTRL', mode = 'C', zoom = L('key.wheel'), vision = 'Q', light = 'F',
        lock = 'LMB', payload = 'RMB', view = 'V', home = 'Z', leave = 'BACKSPACE', boost = 'SHIFT', acro = 'X', throttle = 'SPACE CTRL', cinematic = 'H',
    }
    local c = f.cine
    if c and c.self then
        return { { label = L('legend.filmStop'), value = key.acro }, { label = L('legend.leave'), value = key.leave } }
    end
    if c then
        local shot = f.lock and c.shot and c.shot.name
        local rows = {}
        if shot == 'follow' then
            rows[1] = { label = L('legend.distanceSwing'), value = key.move }
            rows[2] = { label = L('legend.height'), value = key.climb }
        elseif shot == 'orbit' then
            rows[1] = { label = L('legend.radiusSpeed'), value = key.move }
            rows[2] = { label = L('legend.height'), value = key.climb }
        elseif shot and CI.auto[shot] then
            rows[1] = { label = L('legend.stopShot'), value = key.move }
        else
            rows[1] = { label = L('legend.move'), value = key.move }
            rows[2] = { label = L('legend.climb'), value = key.climb }
        end
        rows[#rows + 1] = { label = L(f.lock and 'legend.frame' or 'legend.pan'), value = key.look }
        rows[#rows + 1] = { label = L('legend.zoom'), value = key.zoom }
        rows[#rows + 1] = { label = L('legend.mode'), value = key.mode }
        if conf.features.track then
            rows[#rows + 1] = { label = L(f.lock and 'legend.release' or 'legend.subject'), value = key.lock }
            rows[#rows + 1] = { label = L('legend.shot'), value = key.payload }
            if C.cinematic.filmMe then rows[#rows + 1] = { label = L('legend.filmMe'), value = key.acro } end
        end
        rows[#rows + 1] = { label = L('legend.cinematicOff'), value = key.cinematic }
        rows[#rows + 1] = { label = L('legend.leave'), value = key.leave }
        return rows
    end
    local racing = DC.session and DC.session.race
    if f.acro or f.glide then
        local rows = f.glide and {
            { label = L('legend.move'), value = key.move },
            { label = L('legend.climb'), value = key.climb },
        } or {
            { label = L('legend.pitchRoll'), value = key.move },
            { label = L(f.view == 'chase' and 'legend.yaw' or 'legend.pitchYaw'), value = key.look },
            { label = L('legend.throttle'), value = key.throttle },
        }
        if f.glide and f.view ~= 'chase' then
            rows[#rows + 1] = { label = L('legend.flip'), value = key.boost .. ' + ' .. key.move }
            rows[#rows + 1] = { label = L('legend.loop'), value = key.look .. ' + ' .. (pad and 'LS' or 'W') }
        end
        if racing then
            rows[#rows + 1] = { label = L('legend.view'), value = key.view }
            rows[#rows + 1] = { label = L('legend.respawn'), value = key.home }
            rows[#rows + 1] = { label = L('legend.leave'), value = key.leave }
            return rows
        end
        rows[#rows + 1] = { label = L(f.glide and 'legend.normal' or 'legend.stabilise'), value = key.acro }
        if conf.payload then
            local label = conf.payload.kind == 'taser' and 'legend.taser' or (f.armed and 'legend.detonate' or 'legend.arm')
            rows[#rows + 1] = { label = L(label), value = key.payload }
        end
        rows[#rows + 1] = { label = L('legend.view'), value = key.view }
        rows[#rows + 1] = { label = L('legend.home'), value = key.home }
        rows[#rows + 1] = { label = L('legend.leave'), value = key.leave }
        return rows
    end
    local rows = {
        { label = L('legend.move'), value = key.move },
        { label = L('legend.climb'), value = key.climb },
        { label = L('legend.mode'), value = key.mode },
        { label = L('legend.boost'), value = key.boost },
        { label = L('legend.zoom'), value = key.zoom },
    }
    if conf.acro then rows[#rows + 1] = { label = L(f.pendingAcro and 'legend.normal' or 'legend.acro'), value = key.acro } end
    if conf.features.cinematic then rows[#rows + 1] = { label = L('legend.cinematic'), value = key.cinematic } end
    if conf.features.night or conf.features.thermal then rows[#rows + 1] = { label = L('legend.vision'), value = key.vision } end
    if conf.features.spotlight then rows[#rows + 1] = { label = L('legend.light'), value = key.light } end
    if conf.features.track then
        local label = 'legend.lock'
        if f.lock then label = (f.lock.point or f.lock.follow or f.lock.hiddenSince or not conf.features.follow) and 'legend.release' or 'legend.follow' end
        rows[#rows + 1] = { label = L(label), value = key.lock }
        if f.lock and f.lock.point then rows[#rows + 1] = { label = L('legend.orbit'), value = pad and 'LS' or 'A D' } end
    end
    if conf.payload and not racing then
        local label = conf.payload.kind == 'taser' and 'legend.taser' or (f.armed and 'legend.detonate' or 'legend.arm')
        rows[#rows + 1] = { label = L(label), value = key.payload }
    end
    rows[#rows + 1] = { label = L('legend.view'), value = key.view }
    rows[#rows + 1] = { label = L(f.rth and 'legend.cancel' or 'legend.home'), value = key.home }
    rows[#rows + 1] = { label = L('legend.leave'), value = key.leave }
    return rows
end

local function updateLegend(now)
    local policy = DC.prefs.legend
    if policy == 'off' or ((policy ~= 'always' or f.cine) and now >= f.legendUntil) or not (lib and lib.showHelp) then
        if f.legendSig and lib and lib.hideHelp then pcall(lib.hideHelp) end
        f.legendSig = nil
        return
    end
    local rows = legendRows()
    local parts = {}
    for i, row in ipairs(rows) do parts[i] = row.label .. ':' .. row.value end
    local sig = table.concat(parts, '|')
    if sig == f.legendSig then return end
    local called, accepted = pcall(lib.showHelp, rows, { compact = true })
    if called and accepted ~= false then f.legendSig = sig end
end

local legendPx = tonumber(LocalPlayer.state.cortexHelpLegend) or 0

AddStateBagChangeHandler('cortexHelpLegend', nil, function(bagName, _, value)
    local serverId = GetPlayerServerId(PlayerId())
    if serverId <= 0 or bagName ~= ('player:%d'):format(serverId) then return end
    legendPx = tonumber(value) or 0
end)

local function hideLegend()
    if f.legendSig and lib and lib.hideHelp then pcall(lib.hideHelp) end
    f.legendSig = nil
end

local tablets = {}
local tabletWatch = false

local function deleteTablet(object)
    tablets[object] = nil
    if DoesEntityExist(object) then
        DetachEntity(object, false, true)
        SetEntityAsMissionEntity(object, true, true)
        DeleteEntity(object)
    end
end

local function removeTablet()
    for object in pairs(tablets) do deleteTablet(object) end
end

local function watchTablets()
    if tabletWatch then return end
    tabletWatch = true
    CreateThread(function()
        while next(tablets) and not DC.stopped do
            Wait(250)
            local ped, now = PlayerPedId(), U.now()
            for object, attachedAt in pairs(tablets) do
                local stray = not DoesEntityExist(object) or not IsEntityAttachedToEntity(object, ped)
                    or IsEntityDead(ped) or (not DC.piloting and now - attachedAt > 1000)
                if stray then deleteTablet(object) end
            end
        end
        tabletWatch = false
        if DC.stopped then removeTablet() end
    end)
end

local function attachTablet(ped)
    local prop = C.pilot.prop
    if not prop then return end
    removeTablet()
    local hash = U.loadModel(prop.model, 2000)
    if not hash then return end
    local at = GetEntityCoords(ped)
    local object = CreateObject(hash, at.x, at.y, at.z + 0.2, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(object, false, false)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, prop.bone), U.F(prop.offset.x), U.F(prop.offset.y), U.F(prop.offset.z),
        U.F(prop.rotation.x), U.F(prop.rotation.y), U.F(prop.rotation.z), true, true, false, false, 2, true)
    tablets[object] = U.now()
    watchTablets()
end

local function playPilotAnim(ped)
    local anim = C.pilot.anim
    if IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then return end
    if not HasAnimDictLoaded(anim.dict) and not U.loadAnim(anim.dict, 1000) then return end
    TaskPlayAnim(ped, anim.dict, anim.name, 4.0, -4.0, -1, anim.flag or 49, 0.0, false, false, false)
end

local function applyVision()
    SetNightvision(f.vision == 'night')
    SetSeethrough(f.vision == 'thermal')
end

local function applyView(drone)
    if f.cam then DetachCam(f.cam) end
    f.camAt, f.camPitch = nil, nil
end

local function gimbalOffset()
    local o = C.camera.offset
    if f.glide then return U.qrot(f.glide.q, vector3(o.x, o.y, o.z)) end
    local fwd, right = forward(f.body)
    return right * o.x + fwd * o.y + vector3(0.0, 0.0, o.z)
end

local function lensPosition(drone)
    return GetEntityCoords(drone) + gimbalOffset()
end

local function lightDirection()
    return U.rotationToDirection(f.lightPitch, f.body)
end

local function aimLight(dt)
    local traverse = C.spotlight.traverse
    local want = D.clamp(f.gimbal, traverse.min, traverse.max)
    local reach = C.spotlight.slew * dt
    f.lightPitch = f.lightPitch + D.clamp(want - f.lightPitch, -reach, reach)
end

local function lit() return f.light and f.motors end

local function attachCam(drone, offset)
    if f.camAt and #(f.camAt - offset) < 0.0005 then return end
    f.camAt = offset
    AttachCamToEntity(f.cam, drone, U.F(offset.x), U.F(offset.y), U.F(offset.z), false)
end

local function aimCam(pitch, heading)
    if f.camPitch and math.abs(f.camPitch - pitch) < 0.001 and math.abs(f.camHeading - heading) < 0.001 then return end
    f.camPitch, f.camHeading = pitch, heading
    SetCamRot(f.cam, U.F(pitch), 0.0, U.F(heading), 2)
end

local function setFuzz(amount)
    amount = D.clamp(amount, 0.0, 1.0)
    if math.abs(amount - f.fuzz) < 0.02 and not (amount == 0.0 and f.fuzz > 0.0) then return end
    if amount <= 0.0 then
        ClearTimecycleModifier()
    else
        if f.fuzz <= 0.0 then SetTimecycleModifier(FUZZ) end
        SetTimecycleModifierStrength(U.F(amount))
    end
    f.fuzz = amount
end

local function park(drone)
    Autopilot.settle(drone)
end

local function motorsOn(drone, on)
    if on then FreezeEntityPosition(drone, false) end
    f.motors = on
    f.spin = on and C.rotors.idle or 0.0
    SetVehicleKeepEngineOnWhenAbandoned(drone, on)
    SetVehicleEngineOn(drone, on, true, true)
    SetHeliBladesSpeed(drone, U.F(f.spin))
    SetVehicleGravity(drone, not on)
end

local function spinRotors(dt, drone)
    if not f.motors then return end
    local r = C.rotors
    local target = r.idle
    local a = f.acro or f.glide
    if a then
        local load = a.thrust / GRAVITY
        if load <= 1.0 then
            target = r.idle + (r.hover - r.idle) * load
        else
            target = r.hover + (r.full - r.hover) * D.clamp((load - 1.0) / math.max(C.acro.thrust - 1.0, 0.01), 0.0, 1.0)
        end
    elseif not (f.takeoff and U.now() - f.takeoff.at < 1000) then
        local sp = speeds()
        local load = #flat(f.vel) / math.max(sp.horizontal, 0.1) + math.max(f.vel.z, 0.0) / math.max(sp.vertical, 0.1)
        target = r.hover + (r.full - r.hover) * D.clamp(load, 0.0, 1.0)
    end
    f.spin = lerp(f.spin, target, math.min(1.0, dt * 3.0))
    SetHeliBladesSpeed(drone, U.F(f.spin))
end

local function land(drone)
    if f.acro or f.recover or f.glide then SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0) end
    f.acro, f.recover, f.glide = nil, nil, nil
    f.pitch, f.roll = 0.0, 0.0
    motorsOn(drone, false)
    DC.session.state = 'landed'
    park(drone)
    f.vel = vector3(0.0, 0.0, 0.0)
    f.rth, f.landing, f.takeoff, f.landTimer = nil, false, nil, 0.0
    f.status = 'landed'
end
P.land = land

local function cineToast(kind)
    if f.cine then f.cine.toast, f.cine.toastUntil = kind, U.now() + 2500 end
end

local function syncLook()
    if f.cine then f.cine.yaw, f.cine.tilt = f.heading, f.gimbal end
end

local function vitals(ped)
    return GetEntityHealth(ped) + GetPedArmour(ped)
end

local function pilotStance(ped)
    SetCurrentPedWeapon(ped, UNARMED, true)
    SetPedCanSwitchWeapon(ped, false)
    playPilotAnim(ped)
    attachTablet(ped)
    f.pedHealth = vitals(ped)
    f.nextAnim = U.now() + 600
    TriggerServerEvent(RESOURCE .. ':pilot', { on = true, flying = f.motors })
end

local function stopSelf()
    local c = f.cine
    if not c or not c.self then return end
    c.self = false
    if f.lock and f.lock.self then f.lock = nil end
    c.shot = nil
    syncLook()
    f.legendSig = nil
    f.legendUntil = math.max(f.legendUntil, U.now() + 8000)
    cineToast('off')
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) or IsPedSwimming(ped) or downed(ped) then
        f.pendingLeave = true
        return
    end
    pilotStance(ped)
end

local function releaseLock()
    local own = f.lock and f.lock.self
    f.lock = nil
    f.legendSig = nil
    if f.cine then
        f.cine.shot = nil
        syncLook()
        if own then stopSelf() end
    end
end

local function cameraDirection()
    if f.acro then return f.acro.look end
    local g = f.glide
    if g and g.cam then return U.qrot(g.cam, vector3(0.0, 1.0, 0.0)) end
    if f.lens and f.lens.cam then return U.qrot(f.lens.cam, vector3(0.0, 1.0, 0.0)) end
    return U.rotationToDirection(f.gimbal, f.heading)
end

local function related(target, entity)
    if not entity or entity == 0 then return false end
    if entity == target then return true end
    local targetType, entityType = GetEntityType(target), GetEntityType(entity)
    if targetType == 1 and entityType == 2 then return GetVehiclePedIsIn(target, false) == entity end
    if targetType == 2 and entityType == 1 then return GetVehiclePedIsIn(entity, false) == target end
    if targetType == 1 and entityType == 1 then
        local vehicle = GetVehiclePedIsIn(target, false)
        return vehicle ~= 0 and vehicle == GetVehiclePedIsIn(entity, false)
    end
    return false
end

local function sighted(target, from, point, result)
    if not result.hit then return true end
    return related(target, result.entity) or #(result.coords - from) >= #(point - from) - 0.1
end

local function aimPoint(entity)
    local at = GetEntityCoords(entity)
    if GetEntityType(entity) == 1 then at = at + vector3(0.0, 0.0, 0.3) end
    return at
end

local function lookup(lock)
    local conf = kind()
    if not conf.features.lookup or not NetworkGetEntityIsNetworked(lock.entity) then return end
    local netId = NetworkGetNetworkIdFromEntity(lock.entity)
    CreateThread(function()
        local result = U.call('lookup', { netId = netId })
        if f.lock ~= lock or not result or not result.ok or type(result.data) ~= 'table' then return end
        lock.info = result.data
    end)
end

local function lockOn(entity, now)
    local low, high = GetModelDimensions(GetEntityModel(entity))
    local lock = { entity = entity, follow = false, since = now, info = nil, see = { {}, {} }, clear = { true, true }, hiddenSince = nil,
        low = low, high = high, top = high.z * 0.8, colour = { U.accent() } }
    lock.seen, lock.seenVel, lock.seenAt = aimPoint(entity), GetEntityVelocity(entity), now
    f.lock = lock
    f.rth = f.rth and f.rth.forced and f.rth or nil
    lookup(lock)
    f.legendSig = nil
    if f.cine then
        f.cine.shot, f.cine.fx, f.cine.fy = { name = 'track' }, 0.0, 0.0
        cineToast('shot')
    end
    U.sound('toggle')
end

local function lockPoint(point, drone, now)
    local orbit = flat(GetEntityCoords(drone) - point)
    f.lock = { point = point, follow = false, since = now, hiddenSince = nil, radius = #orbit,
        low = vector3(-0.6, -0.6, 0.0), high = vector3(0.6, 0.6, 0.5), colour = { U.accent() } }
    f.rth = f.rth and f.rth.forced and f.rth or nil
    f.legendSig = nil
    if f.cine then
        f.cine.shot, f.cine.fx, f.cine.fy = { name = 'track' }, 0.0, 0.0
        cineToast('shot')
    end
    U.sound('toggle')
end

local function aimGround(job)
    job.stage, job.probe, job.radius, job.from, job.to = 'ground', {}, nil, job.aimFrom, job.aimTo
end

local function stepAcquire(now, drone)
    local job = f.acquiring
    if not job then return end
    if now - job.started > 1000 then f.acquiring = nil; U.sound('toggle'); return end
    local flags = job.stage == 'pick' and BODIES or (job.stage == 'ground' and GROUND or SEE)
    local result = Autopilot.probe(job.probe, now, 0, job.from, job.to, flags, drone, job.radius)
    if not result then return end
    if job.stage == 'pick' then
        local entity = result.hit and result.entity or 0
        local entityType = entity ~= 0 and GetEntityType(entity) or 0
        if (entityType ~= 1 and entityType ~= 2) or entity == PlayerPedId() or entity == drone then aimGround(job); return end
        local from = GetEntityCoords(drone)
        job.stage, job.entity, job.probe, job.radius = 'confirm', entity, {}, nil
        job.from, job.to = from, aimPoint(entity)
        return
    end
    if job.stage == 'confirm' then
        if DoesEntityExist(job.entity) and sighted(job.entity, job.from, job.to, result) then
            f.acquiring = nil
            lockOn(job.entity, now)
        else
            aimGround(job)
        end
        return
    end
    f.acquiring = nil
    if result.hit then lockPoint(result.coords, drone, now) else U.sound('toggle') end
end

local function pressLock(drone)
    local conf = kind()
    if not conf.features.track or f.acquiring then return end
    if not f.lock then
        local from = lensPosition(drone)
        local to = from + cameraDirection() * conf.range
        local aimTo = from + cameraDirection() * (conf.range * 0.95)
        f.acquiring = { stage = 'pick', started = U.now(), probe = {}, from = from, to = to, aimFrom = from, aimTo = aimTo, radius = 0.6 }
        return
    elseif not f.cine and not f.lock.point and not f.lock.follow and conf.features.follow and not f.lock.hiddenSince then
        f.lock.follow = true
        f.lock.offset = GetEntityCoords(drone) - GetEntityCoords(f.lock.entity)
    else
        releaseLock()
        cineToast('shot')
    end
    f.legendSig = nil
    U.sound('toggle')
end

local function hideGrace() return f.cine and C.cinematic.hideGrace or C.track.hideGrace end

local function setSubject(lock, entity)
    if lock.entity == entity then return end
    local low, high = GetModelDimensions(GetEntityModel(entity))
    lock.entity, lock.low, lock.high, lock.top = entity, low, high, high.z * 0.8
    lock.see, lock.clear = { {}, {} }, { true, true }
end

local function ownSubject(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    return vehicle ~= 0 and vehicle or ped
end

local function stepLock(now, drone, conf)
    local lock = f.lock
    if not lock then return end
    if lock.self then setSubject(lock, ownSubject(PlayerPedId())) end
    local origin = GetEntityCoords(drone)
    if lock.point then
        if #(lock.point - origin) > conf.range then
            releaseLock()
            U.notify('notify.lockLost', 'info')
        end
        return
    end
    local entity = lock.entity
    if not DoesEntityExist(entity) or #(GetEntityCoords(entity) - origin) > conf.range then
        releaseLock()
        U.notify('notify.lockLost', 'info')
        return
    end
    local centre = GetEntityCoords(entity)
    local top = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, lock.top)
    for i, point in ipairs({ centre, top }) do
        local result = Autopilot.probe(lock.see[i], now, 150, origin, point, SEE, drone)
        if result then lock.clear[i] = sighted(entity, origin, point, result) end
    end
    if lock.clear[1] or lock.clear[2] then
        lock.hiddenSince = nil
        lock.seen, lock.seenVel, lock.seenAt = aimPoint(entity), GetEntityVelocity(entity), now
        return
    end
    lock.hiddenSince = lock.hiddenSince or now
    if not lock.self and now - lock.hiddenSince > hideGrace() * 1000 then
        releaseLock()
        U.notify('notify.lockLost', 'info')
    end
end

local function lockAim(now)
    local lock = f.lock
    if lock.point then return lock.point end
    if not lock.hiddenSince then return aimPoint(lock.entity) end
    local elapsed = math.min((now - lock.seenAt) / 1000.0, hideGrace())
    return lock.seen + lock.seenVel * elapsed
end

local function startReturn(forced, reason)
    if f.rth and f.rth.forced and not forced then return end
    f.rth = { forced = forced, reason = reason }
    f.landing = false
    if f.lock and f.lock.follow then releaseLock() end
    if f.cine then
        if f.cine.self then
            releaseLock()
        elseif f.lock and f.cine.shot and f.cine.shot.name ~= 'track' then
            f.cine.shot = { name = 'track' }
            cineToast('shot')
        end
    end
    f.legendSig = nil
end
P.startReturn = startReturn

local function acroLook(q, tilt)
    local t = math.rad(tilt)
    return U.qrot(q, vector3(0.0, math.cos(t), math.sin(t)))
end

local function enterAcro(drone)
    local q = U.quaternion(drone)
    f.acro = { q = q, thrust = GRAVITY, sx = 0.0, sy = 0.0, kick = vector3(0.0, 0.0, 0.0), chase = f.heading, look = acroLook(q, acroTilt()), gimbal = f.gimbal }
    f.recover, f.boost, f.landing, f.rth, f.braking, f.acquiring = nil, false, false, nil, false, nil
    f.range, f.rangePoint = nil, nil
    if f.lock then releaseLock() end
    f.legendSig = nil
    f.legendUntil = math.max(f.legendUntil, U.now() + 10000)
end

local function exitAcro(drone)
    if not f.acro then return end
    local a = f.acro
    f.recover = { q = a.q, tilt = acroTilt(), ends = U.now() + 1500 }
    f.acro = nil
    if f.view == 'chase' then f.heading = a.chase % 360.0 end
    f.pitch, f.roll, f.body, f.gimbal = 0.0, 0.0, f.heading, a.gimbal
    SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0)
    f.legendSig = nil
    f.legendUntil = math.max(f.legendUntil, U.now() + 10000)
end

local function spring(x, rate, goal, dt, w)
    local gap = x - goal
    local c = rate + w * gap
    local e = math.exp(-w * dt)
    return goal + (gap + c * dt) * e, (rate - w * c * dt) * e
end

local function lookPitch(g)
    local excess = g.view - D.clamp(g.view, -AIM_LIMIT, AIM_LIMIT)
    local past, gain = math.abs(excess), C.acro.lookFlip - 1.0
    local pitch = past + gain * (past < LOOK_EASE and past * past / (2.0 * LOOK_EASE) or past - LOOK_EASE * 0.5)
    return excess < 0.0 and -pitch or pitch
end

local function setLookPitch(g, pitch)
    if pitch == 0.0 then
        g.view = D.clamp(g.view, -AIM_LIMIT, AIM_LIMIT)
        return
    end
    local p, flip = math.abs(pitch), C.acro.lookFlip
    local bend = (flip - 1.0) / (2.0 * LOOK_EASE)
    local past
    if p >= LOOK_EASE * (1.0 + flip) * 0.5 then
        past = (p + (flip - 1.0) * LOOK_EASE * 0.5) / flip
    elseif math.abs(bend) < 1e-6 then
        past = p
    else
        past = (math.sqrt(math.max(0.0, 1.0 + 4.0 * bend * p)) - 1.0) / (2.0 * bend)
    end
    g.view = pitch > 0.0 and AIM_LIMIT + past or -AIM_LIMIT - past
end

local function glideAim(g)
    return D.clamp(g.view, -AIM_LIMIT, AIM_LIMIT)
end

local function glideLook(g, tilt, now)
    local cam = C.camera
    if f.view == 'chase' then
        if lookPitch(g) == 0.0 then g.view = D.clamp(g.view + tilt, cam.gimbalMin, cam.gimbalMax) end
        return
    end
    local probe = f.lookProbe
    if not probe then
        probe = { since = now, frames = 0, zero = 0, up = 0.0, down = 0.0, settle = 0, breaks = 0, folds = 0, peak = 0.0 }
        f.lookProbe = probe
    end
    probe.frames = probe.frames + 1
    if tilt == 0.0 then probe.zero = probe.zero + 1 elseif tilt > 0.0 then probe.up = probe.up + tilt else probe.down = probe.down - tilt end
    if math.abs(tilt) > 6.0 * GetFrameTime() then g.looked, g.lookRate, g.unwind, g.level = now, 0.0, false, nil end
    local level = lookPitch(g) == 0.0
    local view = g.view + tilt
    local edge = D.clamp(view, -AIM_LIMIT, AIM_LIMIT)
    if level and view ~= edge then
        local detent = C.acro.loopDetent
        g.press = (g.press or 0.0) + (view - edge)
        if math.abs(g.press) < detent then
            view = edge
        else
            view = edge + g.press - (g.press > 0.0 and detent or -detent)
            g.press = 0.0
            probe.breaks = probe.breaks + 1
        end
        probe.peak = math.max(probe.peak, math.abs(g.press))
    elseif level and (g.press or 0.0) * tilt < 0.0 then
        local left = math.abs(g.press) - math.abs(tilt)
        g.press = left > 0.0 and (g.press > 0.0 and left or -left) or 0.0
    end
    g.view = view
    if f.agl < 1.0 and level then g.view = glideAim(g) end
    local pitch = lookPitch(g)
    if math.abs(pitch) >= 360.0 then
        setLookPitch(g, pitch > 0.0 and pitch - 360.0 or pitch + 360.0)
        pitch = lookPitch(g)
    end
    local total = glideAim(g) + pitch
    if pitch ~= 0.0 and math.abs(total) >= 360.0 - C.acro.levelBand then
        local goal = total > 0.0 and 360.0 or -360.0
        g.nose, g.view, g.press = g.nose + pitch - goal, total - goal, 0.0
        g.lookRate, g.unwind, g.level = 0.0, false, nil
        probe.folds = probe.folds + 1
    end
    if now - probe.since >= 100 then
        local aim, look = glideAim(g), lookPitch(g)
        if C.debug and (math.abs(aim) >= 80.0 or look ~= 0.0 or probe.breaks > 0 or probe.folds > 0) then
            print(('[cortex-drone] lookprobe t=%d f=%d zero=%d up=%.1f down=%.1f peak=%.1f press=%.1f aim=%.1f look=%.1f settle=%d unwind=%s breaks=%d folds=%d heading=%.0f'):format(
                now, probe.frames, probe.zero, probe.up, probe.down, probe.peak, g.press or 0.0, aim, look, probe.settle, tostring(g.unwind), probe.breaks, probe.folds, f.heading))
        end
        f.lookProbe = nil
    end
end

local function settleLook(g, dt)
    if f.lookProbe then f.lookProbe.settle = f.lookProbe.settle + 1 end
    g.press = 0.0
    local pitch = lookPitch(g)
    if not g.unwind then
        if pitch == 0.0 then
            g.lookRate = 0.0
            return
        end
        g.unwind, g.level = true, math.abs(pitch) >= 20.0
    end
    local total = g.level and glideAim(g) + pitch or pitch
    local goal = math.abs(total) > 180.0 and (total > 0.0 and 360.0 or -360.0) or 0.0
    local nextTotal, rate = spring(total, g.lookRate, goal, dt, TRICK_SPRING)
    if math.abs(goal - nextTotal) < 0.05 or (nextTotal - goal) * (total - goal) < 0.0 then
        if g.level then g.nose, g.view = g.nose + pitch - goal, 0.0 else setLookPitch(g, 0.0) end
        g.lookRate, g.unwind, g.level = 0.0, false, nil
        return
    end
    g.lookRate = rate
    if not g.level then
        setLookPitch(g, nextTotal)
    elseif nextTotal > AIM_LIMIT then
        setLookPitch(g, nextTotal - AIM_LIMIT)
    elseif nextTotal < -AIM_LIMIT then
        setLookPitch(g, nextTotal + AIM_LIMIT)
    else
        g.view = nextTotal
    end
end

local function settleTurn(q, spin, dt)
    if q.w < 0.0 then q = vector4(-q.x, -q.y, -q.z, -q.w) end
    local s = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
    local scale = s > 1e-9 and math.deg(2.0 * math.atan(s, q.w)) / s or 0.0
    if s * scale < 0.05 and #spin < 1.0 then return IDENTITY, STILL end
    local x, vx = spring(q.x * scale, spin.x, 0.0, dt, TRICK_SPRING)
    local y, vy = spring(q.y * scale, spin.y, 0.0, dt, TRICK_SPRING)
    local z, vz = spring(q.z * scale, spin.z, 0.0, dt, TRICK_SPRING)
    return U.qturn(vector3(math.rad(x), math.rad(y), math.rad(z))), vector3(vx, vy, vz)
end

local function enterGlide(drone)
    local lens = f.lens or { pitch = 0.0, pitchRate = 0.0, roll = 0.0, rollRate = 0.0 }
    f.lens = nil
    f.glide = { q = U.quaternion(drone), pitch = f.pitch, roll = f.roll, pitchRate = 0.0, rollRate = 0.0, bank = 0.0, rate = 0.0, ease = 0.0, turn = IDENTITY, spin = STILL, lookRate = 0.0, unwind = false,
        nose = 0.0, noseRate = 0.0, view = f.gimbal, looked = 0, heading = f.heading, thrust = GRAVITY, cam = nil, dev = nil,
        lensPitch = lens.pitch, lensPitchRate = lens.pitchRate, lensRoll = lens.roll, lensRollRate = lens.rollRate }
    f.recover, f.boost, f.landing, f.rth, f.braking, f.acquiring = nil, false, false, nil, false, nil
    if f.lock then releaseLock() end
    f.legendSig = nil
    f.legendUntil = math.max(f.legendUntil, U.now() + 10000)
end

local function exitGlide(drone)
    local g = f.glide
    if not g then return end
    f.glide = nil
    SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0)
    f.body = f.heading
    local mount = f.gimbal
    f.gimbal = D.clamp(glideAim(g), C.camera.gimbalMin, C.camera.gimbalMax)
    if math.abs(lookPitch(g)) > 2.0 or U.qangle(g.turn, IDENTITY) > 2.0 or math.abs(g.nose) > 2.0 then
        f.recover = { q = g.q, tilt = mount, ends = U.now() + 1500 }
        f.pitch, f.roll = 0.0, 0.0
    else
        f.lens = { pitch = g.lensPitch, pitchRate = g.lensPitchRate, roll = g.lensRoll, rollRate = g.lensRollRate }
    end
    f.legendSig = nil
    f.legendUntil = math.max(f.legendUntil, U.now() + 10000)
end

local function startAcro(drone, conf)
    if not conf.acro or not f.motors or f.takeoff or f.lostSince or (f.rth and f.rth.forced) or DC.session.battery <= 0.0 then return false end
    if DC.prefs.acroControls == 'manual' then enterAcro(drone) else enterGlide(drone) end
    return true
end

local function grounded()
    return not f.motors or f.takeoff ~= nil
end

local function toggleAcro(drone, conf)
    if f.acro or f.glide or f.pendingAcro then
        if f.acro then exitAcro(drone) elseif f.glide then exitGlide(drone) end
        f.pendingAcro = false
        remember(f.mode)
    elseif conf.acro and grounded() and DC.session.state ~= 'crashed' and DC.session.battery > 0.0 then
        f.pendingAcro = true
        remember('acro')
    elseif startAcro(drone, conf) then
        remember('acro')
    else
        return
    end
    f.legendSig = nil
    U.sound('toggle')
end

local function settlePendingAcro(drone, conf)
    if not f.pendingAcro or grounded() then return end
    f.pendingAcro = false
    f.legendSig = nil
    if f.rth or f.landing then return end
    startAcro(drone, conf)
end

local function applyStartMode(conf)
    local want = DC.prefs.startMode
    if want == 'last' then want = GetResourceKvpString(LAST_MODE) end
    if want == 'acro' then
        f.mode, f.pendingAcro = 'normal', conf.acro == true
    else
        f.mode = SPEED_MODES[want] and want or 'normal'
    end
end

local function holdRaceAcro(drone)
    if f.acro or f.glide then return end
    if DC.prefs.acroControls == 'manual' then enterAcro(drone) else enterGlide(drone) end
end

local function subjectVel(dt)
    local c, lock = f.cine, f.lock
    if lock.point then return STILL end
    local raw = lock.hiddenSince and lock.seenVel or GetEntityVelocity(lock.entity)
    if c.velOf ~= lock then
        c.velOf, c.vel = lock, raw
    else
        c.vel = c.vel + (raw - c.vel) * (1.0 - math.exp(-dt / 0.25))
    end
    return c.vel
end

local function cineSubject(now)
    local c, lock, subject = f.cine, f.lock, f.cine.subject
    if lock.point then
        subject.at, subject.vel, subject.heading, subject.vehicle = lock.point, STILL, f.heading, false
    else
        local entity = lock.entity
        subject.at = lockAim(now)
        subject.vel = c.velOf == lock and c.vel or (lock.hiddenSince and lock.seenVel or GetEntityVelocity(entity))
        subject.heading = GetEntityHeading(entity)
        subject.vehicle = GetEntityType(entity) == 2
    end
    return subject
end

local function shoot(name, drone, now)
    local c = f.cine
    c.shot = CI.begin(name, cineSubject(now), GetEntityCoords(drone), c.shot)
    f.legendSig = nil
    cineToast('shot')
end

local function nextShot(drone, now)
    local c = f.cine
    if not f.lock or not c.shot then cineToast('need'); U.sound('toggle'); return end
    shoot(CI.next(c.shot.name), drone, now)
    U.sound('toggle')
end

local function startSelf(drone, now)
    local c = f.cine
    local conf = kind()
    if not C.cinematic.filmMe or not conf.features.track or not f.motors or f.takeoff or f.lostSince or f.rth or f.landing or f.agl < 0.4 then
        U.sound('toggle')
        return
    end
    local ped = PlayerPedId()
    local lock = { self = true, follow = false, since = now, hiddenSince = nil, colour = { U.accent() } }
    setSubject(lock, ownSubject(ped))
    lock.seen, lock.seenVel, lock.seenAt = aimPoint(lock.entity), GetEntityVelocity(lock.entity), now
    f.acquiring = nil
    f.lock = lock
    c.self, c.fx, c.fy = true, 0.0, 0.0
    local keep = c.shot and c.shot.name ~= 'track' and c.shot.name or 'follow'
    c.shot = nil
    shoot(keep, drone, now)
    f.boost = false
    StopAnimTask(ped, C.pilot.anim.dict, C.pilot.anim.name, 2.0)
    removeTablet()
    SetPedCanSwitchWeapon(ped, true)
    TriggerServerEvent(RESOURCE .. ':pilot', { on = false, flying = true })
    f.legendUntil = now + 8000
    U.sound('toggle')
end

local function keepFollow(c, drone)
    local lock = f.lock
    if not lock or not lock.entity or lock.self or not (c.shot and c.shot.name == 'follow') or not kind().features.follow
        or not DoesEntityExist(lock.entity) then return end
    lock.follow = true
    lock.offset = GetEntityCoords(drone) - GetEntityCoords(lock.entity)
end

local function endCinematic(drone)
    local c = f.cine
    if not c then return end
    if c.self then releaseLock() end
    keepFollow(c, drone)
    f.cine = nil
    if c.speed and f.mode == c.speed then f.mode = c.mode end
    f.legendSig = nil
end

local function toggleCinematic(drone, conf, now)
    if f.cine then
        endCinematic(drone)
        f.legendUntil = math.max(f.legendUntil, now + 10000)
        U.sound('toggle')
        return
    end
    if not conf.features.cinematic or f.falling or f.ending then return end
    if f.acro then exitAcro(drone) elseif f.glide then exitGlide(drone) end
    f.pendingAcro = false
    local speed = C.cinematic.speedMode or nil
    f.cine = { mode = f.mode, speed = speed, shot = nil, self = false, fx = 0.0, fy = 0.0, yaw = f.heading, tilt = f.gimbal,
        tv = f.vel, subject = {}, toast = nil, toastUntil = 0 }
    if speed then f.mode = speed end
    f.boost = false
    if f.lock then
        local follow = f.lock.follow
        f.lock.follow = false
        if follow then shoot('follow', drone, now) else f.cine.shot = { name = 'track' } end
    end
    cineToast('on')
    f.legendSig = nil
    f.legendUntil = now + 8000
    U.sound('toggle')
end

local function fireTaser(drone)
    local conf = kind()
    local payload = conf.payload
    if U.now() - f.fired < payload.cooldown * 1000 or DC.session.payload <= 0 then U.sound('toggle'); return end
    local origin = GetOffsetFromEntityInWorldCoords(drone, 0.0, 0.2, -0.15)
    local target
    if f.lock and f.lock.entity and DoesEntityExist(f.lock.entity) then
        if f.lock.hiddenSince then U.sound('toggle'); return end
        target = aimPoint(f.lock.entity)
    else
        local from = lensPosition(drone)
        local to = from + cameraDirection() * (payload.range + 10.0)
        local _, hit, coords = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, SEE, drone, 7))
        target = (hit == 1 or hit == true) and coords or to
    end
    if #(target - origin) > payload.range then U.notify('notify.taserRange', 'info'); return end
    f.fired = U.now()
    CreateThread(function()
        local result = U.call('payload', {})
        if not result or not result.ok then f.fired = -100000; return end
        if DC.session then
            DC.session.payload = result.data and result.data.left or math.max(0, DC.session.payload - 1)
            local level = result.data and result.data.battery
            DC.session.battery = math.max(0.0, D.finite(level) and math.min(level, DC.session.battery) or DC.session.battery - C.battery.taserShot)
        end
        RequestWeaponAsset(STUNGUN, 31, 0)
        local deadline = U.now() + 1000
        while not HasWeaponAssetLoaded(STUNGUN) and U.now() < deadline do Wait(0) end
        if not DoesEntityExist(drone) then return end
        local from = GetOffsetFromEntityInWorldCoords(drone, 0.0, 0.2, -0.15)
        ShootSingleBulletBetweenCoordsIgnoreEntity(from.x, from.y, from.z, target.x, target.y, target.z, 1, true, STUNGUN,
            PlayerPedId(), true, false, -1.0, drone, false)
    end)
end

local function detonate(drone)
    if f.ending then return end
    f.ending = 'detonating'
    local conf = kind()
    local at = GetEntityCoords(drone)
    CreateThread(function()
        local result = U.call('payload', {})
        if not result or not result.ok or not (result.data and result.data.detonate) then
            f.ending = nil
            f.armed = false
            U.notify('notify.payloadFailed')
            return
        end
        local payload = conf.payload
        if DoesEntityExist(drone) then at = GetEntityCoords(drone) end
        AddOwnedExplosion(PlayerPedId(), at.x, at.y, at.z, payload.explosion, U.F(payload.scale), true, false, 1.0)
        U.deleteEntity(drone)
        P.stop('detonated')
        DC.session = nil
    end)
end

local function crash(drone, reason)
    if f.ending then return end
    if DC.session and DC.session.race then
        f.ending = 'crashed'
        f.acro, f.glide, f.recover, f.lock, f.rth = nil, nil, nil, nil, nil
        SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0)
        motorsOn(drone, false)
        FreezeEntityPosition(drone, true)
        f.status = 'crashed'
        present(U.now(), true)
        U.sound('lost')
        TriggerEvent('cortex-drone:raceCrashed', reason)
        return
    end
    local conf = kind()
    if conf.payload and conf.payload.kind == 'explosive' and f.armed then detonate(drone); return end
    f.ending = 'crashed'
    DC.session.state = 'crashed'
    if f.acro then f.acro.thrust = 0.0 end
    if f.glide then SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0) end
    f.glide = nil
    motorsOn(drone, false)
    f.light, f.lock, f.rth = false, nil, nil
    f.status = 'crashed'
    present(U.now(), true)
    U.sound('lost')
    local session = DC.session
    local shown = U.now() + 1600
    CreateThread(function()
        Wait(1600)
        if DC.session and DC.session ~= session then return end
        P.stop('crashed')
    end)
    CreateThread(function()
        local result = U.call('crash', { reason = reason })
        local left = shown - U.now()
        if left > 0 then Wait(left) end
        if DC.session ~= session or (result and result.ok and result.data and result.data.destroyed) then return end
        U.notify('notify.crashed', 'info')
    end)
end

local function warningFor(now, conf, cine)
    local s = DC.session
    if f.status == 'crashed' then return 'crashed', 'critical' end
    if f.lostSince then return 'signal_lost', 'critical' end
    if s.battery <= 0.0 then return 'battery_empty', 'critical' end
    if s.battery < 12.0 then return 'battery_critical', 'critical' end
    if f.zone then return 'no_fly', 'caution' end
    if not cine then
        if f.lock and f.lock.hiddenSince then return 'target_hidden', 'caution' end
        if f.braking then return 'obstacle', 'caution' end
        if f.agl >= conf.maxAltitude - 0.5 then return 'altitude_limit', 'caution' end
        if not s.race then
            if f.bars <= 2 and f.quality > 0.0 then return 'signal_weak', 'caution' end
            if f.obstructed then return 'link_obstructed', 'caution' end
            if s.battery <= C.battery.returnAt + 10.0 then return 'battery_low', 'caution' end
            if f.distance > conf.range * 0.9 then return 'range_limit', 'caution' end
        end
    end
    if f.rth then return 'returning', 'caution' end
    if f.landing then return 'landing', 'caution' end
end

local function warn(code, now)
    if not code then return end
    local seen = f.warned[code]
    f.warned[code] = now
    if type(seen) == 'number' and now - seen < 5000 then return end
    if code == 'signal_lost' or code == 'crashed' then U.sound('lost')
    elseif code ~= 'returning' and code ~= 'landing' then U.sound('warning') end
end

local function targetInfo(lock, origin)
    if lock.point then return { kind = 'object', title = L('lock.point'), hidden = false, range = #(lock.point - origin) } end
    local entity = lock.entity
    if lock.hiddenSince and lock.card then
        local card = {}
        for key, value in pairs(lock.card) do card[key] = value end
        card.hidden, card.range = true, #(lock.seen - origin)
        return card
    end
    local info = lock.info or {}
    local range = #(GetEntityCoords(entity) - origin)
    if GetEntityType(entity) == 2 then
        if not lock.label then
            local name = GetDisplayNameFromVehicleModel(GetEntityModel(entity))
            local label = GetLabelText(name)
            lock.label = label == 'NULL' and name or label
            lock.plate = (GetVehicleNumberPlateText(entity) or ''):gsub('^%s+', ''):gsub('%s+$', '')
        end
        lock.card = { kind = 'vehicle', title = lock.label, plate = lock.plate, owner = info.owner, speed = GetEntitySpeed(entity) }
    elseif GetEntityType(entity) == 1 then
        lock.card = { kind = 'person', title = info.name or L('ui.person'), detail = info.job, speed = GetEntitySpeed(entity) }
    else
        lock.card = { kind = 'object', title = L('ui.object') }
    end
    local card = {}
    for key, value in pairs(lock.card) do card[key] = value end
    card.hidden, card.range = false, range
    return card
end

local power = { usage = {}, cruise = {} }

function power.accessories(flags)
    flags.spotlight, flags.thermal, flags.night, flags.track = lit(), f.vision == 'thermal', f.vision == 'night', f.lock ~= nil
    return flags
end

local function drainFlags()
    local usage = power.usage
    local a = f.acro or f.glide
    if a then
        usage.mode, usage.load, usage.hover, usage.boost = 'acro', a.thrust / GRAVITY, nil, nil
    else
        local hspeed = #flat(f.vel)
        usage.mode, usage.load = f.mode, nil
        usage.hover, usage.boost = hspeed < 0.5 and math.abs(f.vel.z) < 0.3, f.boost
    end
    usage.motors = f.motors
    return power.accessories(usage)
end

function power.cruiseFlags()
    power.cruise.mode = f.mode
    return power.accessories(power.cruise)
end

local function placeAt(pos)
    local street = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    local road = street ~= 0 and GetStreetNameFromHashKey(street) or ''
    local area = GetLabelText(GetNameOfZone(pos.x, pos.y, pos.z))
    if area == 'NULL' then area = '' end
    if road == '' and area == '' then return nil end
    return { street = road, area = area }
end

local function homeTrip(pos, home)
    local dx, dy = home.x - pos.x, home.y - pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local cruise = dist > 20.0 and math.max(pos.z, home.z - 1.0 + C.flight.returnAltitude) or pos.z
    local drop = math.max(0.0, cruise - home.z + 1.0)
    local final = math.min(drop, 4.0)
    local travel = dist > 2.5 and dist / C.flight.returnSpeed + 1.5 or 0.0
    return (cruise - pos.z) / 5.0 + travel + (drop - final) / 3.0 + final / C.flight.landingSpeed
end

local function hudState(now, conf, drone, pos)
    local s = DC.session
    local fwdSpeed = #flat(f.vel)
    local draw = D.drainPerSecond(conf, drainFlags(), s.capacity)
    local home = Autopilot.home()
    local dx, dy = home.x - pos.x, home.y - pos.y
    if now >= f.nextPlace then f.nextPlace, f.place = now + 1000, placeAt(pos) end
    local trip = f.motors and (dx * dx + dy * dy) > 6.25 and homeTrip(pos, home) or nil
    local status = f.status
    if f.status ~= 'crashed' and f.status ~= 'starting' and f.status ~= 'landed' then
        if f.lostSince then status = 'lost'
        elseif f.rth then status = f.rth.descending and 'landing' or 'returning'
        elseif f.landing then status = 'landing'
        elseif f.lock then status = f.lock.follow and 'following' or 'tracking'
        else status = 'flying' end
    end
    local payload
    if conf.payload and not s.race then
        local ready = conf.payload.kind == 'explosive' or (now - f.fired >= conf.payload.cooldown * 1000 and s.payload > 0)
        payload = { kind = conf.payload.kind, count = s.payload, ready = ready, armed = f.armed }
    end
    local c = f.cine
    local code, severity = warningFor(now, conf, c ~= nil)
    warn(code, now)
    local target = f.lock and (f.lock.point or DoesEntityExist(f.lock.entity)) and targetInfo(f.lock, pos) or nil
    local cine = c and {
        shot = f.lock and c.shot and c.shot.name or 'free', self = c.self, frame = DC.prefs.cineFrame,
        toast = now < c.toastUntil and c.toast or nil,
    } or nil
    return {
        mode = (f.acro or f.glide or f.pendingAcro) and 'acro' or f.mode, boost = f.boost, status = status, battery = s.battery,
        throttle = f.acro and math.floor(f.acro.thrust / (C.acro.thrust * GRAVITY) * 100.0 + 0.5) or nil,
        remaining = f.motors and s.battery / math.max(draw, 0.0001) or s.battery / D.drainPerSecond(conf, { mode = 'normal' }, s.capacity),
        signal = f.bars, heading = U.compass(f.heading),
        home = (dx * dx + dy * dy) > 9.0 and U.compass(U.heading(dx, dy)) or nil,
        altitude = f.agl, distance = f.distance, hspeed = fwdSpeed, vspeed = f.vel.z,
        gimbal = f.glide and D.clamp(glideAim(f.glide), C.camera.gimbalMin, C.camera.gimbalMax) or f.gimbal, zoom = f.zoom, vision = f.vision, view = f.view, light = f.light, lightPitch = f.lightPitch,
        range = (not f.lock and f.view == 'gimbal') and f.range or nil,
        trip = trip, reserve = trip and s.battery - trip * D.drainPerSecond(conf, power.cruiseFlags(), s.capacity) or nil,
        ahead = f.clearance, place = f.place,
        lock = f.lock and (f.lock.follow and 'following' or 'tracking') or nil,
        target = target, payload = payload,
        warning = code and { code = code, severity = severity } or nil,
        cine = cine,
    }
end

local function drawBracket(lock)
    local entity, low, high = lock.entity, lock.low, lock.high
    local minX, minY, maxX, maxY = 2.0, 2.0, -1.0, -1.0
    local seen = false
    for i = 0, 7 do
        local x = (i & 1) == 0 and low.x or high.x
        local y = (i & 2) == 0 and low.y or high.y
        local z = (i & 4) == 0 and low.z or high.z
        local world = lock.point and (lock.point + vector3(x, y, z)) or GetOffsetFromEntityInWorldCoords(entity, x, y, z)
        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)
        if onScreen then
            seen = true
            minX, minY = math.min(minX, sx), math.min(minY, sy)
            maxX, maxY = math.max(maxX, sx), math.max(maxY, sy)
        end
    end
    if not seen then return end
    local w, h = GetActiveScreenResolution()
    local u = 1.0 / 1080.0
    local ty, tx = 3.0 * u, 3.0 * u * (h / w)
    local pad = 8.0 * u
    minX, maxX = minX - pad * (h / w), maxX + pad * (h / w)
    minY, maxY = minY - pad, maxY + pad
    local lx = math.min((maxX - minX) * 0.3, 28.0 * u * (h / w))
    local ly = math.min((maxY - minY) * 0.3, 28.0 * u)
    local r, g, b = U.I(lock.colour[1]), U.I(lock.colour[2]), U.I(lock.colour[3])
    for _, corner in ipairs({ { minX, minY, 1, 1 }, { maxX, minY, -1, 1 }, { minX, maxY, 1, -1 }, { maxX, maxY, -1, -1 } }) do
        local cx, cy, sx, sy = corner[1], corner[2], corner[3], corner[4]
        DrawRect(U.F(cx + sx * lx * 0.5), U.F(cy), U.F(lx), U.F(ty), r, g, b, 235)
        DrawRect(U.F(cx), U.F(cy + sy * ly * 0.5), U.F(tx), U.F(ly), r, g, b, 235)
    end
end

local function drawSpotlight(drone)
    local s = C.spotlight
    local from = U.lampPosition(drone)
    local dir = lightDirection()
    DrawSpotLightWithShadow(from.x, from.y, from.z, dir.x, dir.y, dir.z, U.I(s.colour[1]), U.I(s.colour[2]), U.I(s.colour[3]),
        U.F(s.distance), U.F(s.brightness), U.F(s.hardness), U.F(s.radius), U.F(s.falloff), 7)
    if f.vision ~= 'thermal' then DroneVolume.draw(drone, from, dir) end
end

local function readInput(dt)
    local kb = keyboard()
    local x = GetDisabledControlNormal(0, 30)
    local y = -GetDisabledControlNormal(0, 31)
    local z
    if kb then
        z = (held('up') and 1.0 or 0.0) - (held('down') and 1.0 or 0.0)
    else
        z = axis('up') - axis('down')
    end
    local lx, ly = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
    local sens = DC.prefs.sensitivity / 100.0
    local fovFactor = f.fov / C.camera.fov
    local yaw, tilt
    if kb then
        yaw = -lx * 8.0 * sens * fovFactor
        tilt = -ly * 8.0 * sens * fovFactor
    else
        yaw = -lx * speeds().yaw * dt * fovFactor
        tilt = -ly * 70.0 * dt * fovFactor
    end
    if DC.prefs.invert then tilt = -tilt end
    local mag = math.sqrt(x * x + y * y)
    if mag > 1.0 then x, y = x / mag, y / mag end
    local input = f.input
    input.x, input.y, input.z, input.yaw, input.tilt, input.lx, input.ly = x, y, z, yaw, tilt, lx, ly
    input.any = mag > 0.15 or math.abs(z) > 0.15
    return input
end

local function handleButtons(now, dt, drone, conf)
    local s = DC.session
    local racing = s and s.race
    if filming() then
        if pressed('acro') then releaseLock(); U.sound('toggle') end
        return
    end
    if racing and pressed('home') then crash(drone, 'reset'); return end
    if not racing and pressed('cinematic') then toggleCinematic(drone, conf, now) end
    if not racing and pressed('mode') then
        if f.acro then exitAcro(drone) elseif f.glide then exitGlide(drone) elseif not f.pendingAcro then f.mode = MODES[f.mode] or 'normal' end
        f.pendingAcro = false
        f.legendSig = nil
        if not f.cine then remember(f.mode) end
        U.sound('toggle')
    end
    if f.cine then
        if pressed('acro') then startSelf(drone, now) end
    elseif not racing and pressed('acro') then
        toggleAcro(drone, conf)
    end
    local boostable = not (f.acro or f.glide or f.cine) and f.mode ~= 'sport'
    if DC.prefs.boost == 'toggle' then
        if not boostable then f.boostLatch = false elseif pressed('boost') then f.boostLatch = not f.boostLatch end
        f.boost = f.boostLatch
    else
        f.boostLatch = false
        f.boost = boostable and held('boost')
    end
    if pressed('vision') then
        local order = { 'normal' }
        if conf.features.night then order[#order + 1] = 'night' end
        if conf.features.thermal then order[#order + 1] = 'thermal' end
        local index = 1
        for i, value in ipairs(order) do if value == f.vision then index = i end end
        f.vision = order[index % #order + 1]
        applyVision()
        U.sound('toggle')
    end
    if conf.features.spotlight and pressed('spotlight') then
        f.light = not f.light
        DC.session.light = f.light
        present(now, true)
        U.sound('toggle')
    end
    if pressed('view') then
        f.view = f.view == 'gimbal' and 'chase' or 'gimbal'
        applyView(drone)
        U.sound('toggle')
    end
    if not racing and f.motors and not f.lostSince and pressed('home') then
        if f.rth and not f.rth.forced then f.rth = nil; f.legendSig = nil else startReturn(false, 'pilot') end
        U.sound('toggle')
    end
    if not racing and f.motors and not (f.acro or f.glide) and pressed('lock') then pressLock(drone) end
    if f.cine then
        if pressed('payload') then nextShot(drone, now) end
    elseif conf.payload and f.motors and not racing then
        if conf.payload.kind == 'taser' then
            if pressed('payload') then fireTaser(drone) end
        elseif f.armed then
            if pressed('payload') then detonate(drone) end
        else
            if held('payload') then
                f.armHeld = f.armHeld + dt
                if f.armHeld >= conf.payload.armSeconds then
                    f.armed, f.armHeld, f.legendSig = true, 0.0, nil
                    U.sound('warning')
                end
            else
                f.armHeld = 0.0
            end
        end
    end
    local kb = keyboard()
    local zoomStep = 0.0
    if kb then
        if IsDisabledControlJustPressed(0, 241) then zoomStep = zoomStep + 1.0 end
        if IsDisabledControlJustPressed(0, 242) then zoomStep = zoomStep - 1.0 end
    end
    if zoomStep ~= 0.0 then f.zoom = f.zoom * (zoomStep > 0 and 1.18 or 1 / 1.18) end
    if held('zoomIn') then f.zoom = f.zoom * (1.0 + 1.6 * dt) end
    if held('zoomOut') then f.zoom = f.zoom / (1.0 + 1.6 * dt) end
    f.zoom = D.clamp(f.zoom, 1.0, conf.zoomMax)
end

local function flightTarget(dt, input, drone, pos, conf)
    local sp = speeds()
    local fwd, right = forward(f.heading)
    local tv = (fwd * input.y + right * input.x) * sp.horizontal + vector3(0.0, 0.0, input.z * sp.vertical)

    if f.lock and f.lock.follow and not f.lock.hiddenSince and DoesEntityExist(f.lock.entity) then
        local lock = f.lock
        lock.offset = lock.offset + (fwd * input.y + right * input.x) * sp.horizontal * dt + vector3(0.0, 0.0, input.z * sp.vertical * dt)
        local home = GetEntityCoords(PlayerPedId())
        local want = GetEntityCoords(lock.entity) + lock.offset
        local leash = want - home
        local limit = conf.range * LEASH
        local leashed = #leash > limit
        if leashed then want = home + leash * (limit / #leash) end
        local follow = (want - pos) * 1.4 + (leashed and vector3(0.0, 0.0, 0.0) or GetEntityVelocity(lock.entity))
        local cap = conf.speeds.sport.horizontal * 1.3
        if #follow > cap then follow = follow * (cap / #follow) end
        tv = follow
    end

    local c = f.cine
    local shot = c and f.lock and c.shot
    if shot and shot.name ~= 'track' then
        if CI.auto[shot.name] and input.any then
            c.shot = { name = 'track' }
            f.legendSig = nil
            cineToast('shot')
        else
            local now = U.now()
            local done
            tv, done = CI.step(shot, cineSubject(now), pos, input, dt, sp, f.lock.hiddenSince ~= nil, f.agl >= conf.maxAltitude - 1.0)
            if f.agl < 1.5 and tv.z < 0.0 then tv = vector3(tv.x, tv.y, math.max(0.0, (1.0 - f.agl) * 2.0)) end
            if done then shoot(c.self and 'follow' or 'track', drone, now) end
        end
    end

    if not c and f.lock and f.lock.point then
        local lock = f.lock
        local rel = flat(pos - lock.point)
        local r = #rel
        local out = r > 0.05 and rel / r or -forward(f.heading)
        local tangent = vector3(-out.y, out.x, 0.0)
        lock.radius = math.max(math.min(lock.radius, C.track.orbitMinRadius), lock.radius - input.y * sp.horizontal * dt)
        local orbit = math.min(sp.horizontal, math.sqrt(sp.accel * 0.8 * math.max(r, 1.0)))
        local hold = D.clamp((lock.radius - r) * 1.5, -sp.horizontal, sp.horizontal)
        local glide = tangent * (input.x * orbit) + out * hold
        if #glide > sp.horizontal then glide = glide * (sp.horizontal / #glide) end
        tv = glide + vector3(0.0, 0.0, input.z * sp.vertical)
    end

    if f.rth then
        if input.any and not f.rth.forced then
            f.rth = nil
            f.legendSig = nil
        else
            local rv, heading, landed = Autopilot.returnStep(f.rth, drone, pos, f.agl, dt)
            if landed then land(drone); return vector3(0.0, 0.0, 0.0) end
            tv = rv
            if heading and not f.lock then f.heading = f.heading + U.angleDelta(f.heading, heading) * math.min(1.0, dt * 2.5) end
        end
    elseif f.landing then
        tv = vector3(tv.x * 0.3, tv.y * 0.3, Autopilot.descent(f.agl))
        if f.agl < 0.4 then land(drone); return vector3(0.0, 0.0, 0.0) end
    end

    if f.zone and not conf.ignoreNoFly then
        local out = vector3(pos.x - f.zone.x, pos.y - f.zone.y, 0.0)
        local length = #out
        if length > 0.01 then
            out = out / length
            local inward = tv.x * out.x + tv.y * out.y
            if inward < 0.0 then tv = tv - out * inward end
            tv = tv + out * 6.0
        end
    end
    if f.agl >= conf.maxAltitude and tv.z > 0.0 then tv = vector3(tv.x, tv.y, f.agl > conf.maxAltitude + 2.0 and -1.0 or 0.0) end
    return tv
end

local function brake(tv, dir, result, pos, reach, decel)
    if not result or not result.hit then return tv, false end
    local gap = (result.coords - pos).x * dir.x + (result.coords - pos).y * dir.y + (result.coords - pos).z * dir.z
    if gap <= 0.0 or gap > reach then return tv, false end
    local room = gap - C.sensing.radius - C.sensing.margin
    local allowed = room > 0.0 and math.sqrt(2.0 * decel * room) or room * 2.0
    local along = tv.x * dir.x + tv.y * dir.y + tv.z * dir.z
    if along <= allowed then return tv, false end
    return tv - dir * (along - allowed), true
end

local function sense(now, tv, drone, pos, conf)
    f.braking = false
    if not conf.sensing then return tv end
    local s = C.sensing
    local sp = speeds()
    local decel = sp.accel * 1.6
    local h = flat(tv)
    if #h < 0.05 then h = flat(f.vel) end
    local speed = #h
    if speed > 0.05 then
        local dir = h / speed
        local reach = s.margin + s.radius + speed * s.lookahead + speed * speed / (2.0 * decel)
        local result = Autopilot.probe(f.aheadProbe, now, 50, pos, pos + dir * reach, SOLID, drone, s.radius)
        if result then f.ahead = result end
        local braked
        tv, braked = brake(tv, dir, f.ahead, pos, reach, decel)
        f.braking = braked
    else
        f.ahead = nil
    end
    if tv.z > 0.3 then
        local up = vector3(0.0, 0.0, 1.0)
        local reach = s.margin + s.radius + tv.z * s.lookahead + tv.z * tv.z / (2.0 * sp.accel * 1.4)
        local result = Autopilot.probe(f.aboveProbe, now, 50, pos, pos + up * reach, SOLID, drone, s.radius)
        if result then f.above = result end
        local braked
        tv, braked = brake(tv, up, f.above, pos, reach, sp.accel * 1.4)
        f.braking = f.braking or braked
    else
        f.above = nil
    end
    return tv
end

function power.out(now)
    if f.light then
        f.light = false
        DC.session.light = false
        present(now, true)
    end
    if f.vision ~= 'normal' then
        f.vision = 'normal'
        applyVision()
    end
    if f.lock then releaseLock() end
end

local function drainBattery(now, dt, conf)
    local s = DC.session
    if s.race then return end
    if s.battery <= 0.0 then power.out(now); return end
    local rate = D.drainPerSecond(conf, drainFlags(), s.capacity)
    if rate <= 0.0 then return end
    s.battery = math.max(0.0, s.battery - rate * dt)
    if s.battery <= 0.0 then power.out(now) end
end

local function blankAdopt()
    return { hit = 0, hitGain = 0.0, engine = 0, engineGain = 0.0, rejected = 0, rejectedGain = 0.0, top = 0.0 }
end

local function tally(a, kind, gain)
    a[kind], a[kind .. 'Gain'], a.top = a[kind] + 1, a[kind .. 'Gain'] + gain, math.max(a.top, gain)
end

local function note(kind, measured)
    local gain = #measured - #f.vel
    f.adopt, f.adoptTotal = f.adopt or blankAdopt(), f.adoptTotal or blankAdopt()
    tally(f.adopt, kind, gain)
    tally(f.adoptTotal, kind, gain)
end

local function collide(drone, conf)
    if not HasEntityCollidedWithAnything(drone) then return 0.0, false end
    local measured = GetEntityVelocity(drone)
    local impact = #(f.vel - measured)
    local threshold = (conf.payload and conf.payload.kind == 'explosive' and f.armed) and conf.payload.impactSpeed or C.flight.crashSpeed
    if impact > threshold then crash(drone, 'impact'); return 1.0, true end
    note('hit', measured)
    f.vel = measured
    return impact / threshold, false
end

local function expo(value)
    local e = DC.prefs.acroExpo / 100.0
    return value * (1.0 - e) + value * value * value * e
end

local function ramp(current, want, dt)
    local time = C.acro.keyRamp
    if time <= 0.0 then return want end
    local step = dt / time
    if math.abs(want) < math.abs(current) or want * current < 0.0 then step = step * 3.0 end
    return current + D.clamp(want - current, -step, step)
end

local function nearest(current, heading)
    local flipped = (heading + 180.0) % 360.0
    return math.abs(U.angleDelta(current, heading)) <= math.abs(U.angleDelta(current, flipped)) and heading or flipped
end

local function chaseHeading(a, q)
    local right = U.qrot(q, vector3(1.0, 0.0, 0.0))
    local fwd = U.qrot(q, vector3(0.0, 1.0, 0.0))
    if fwd.x * fwd.x + fwd.y * fwd.y < 0.0025 then return a.chase end
    if right.x * fwd.y - right.y * fwd.x >= 0.0 then return U.heading(fwd.x, fwd.y) end
    return nearest(a.chase, U.heading(fwd.x, fwd.y))
end

local function contact(drone, conf)
    local hit, crashed = collide(drone, conf)
    if crashed then return hit, true end
    if hit == 0.0 then
        local measured = GetEntityVelocity(drone)
        if #(measured - f.vel) > 1.5 then
            if #measured < #f.vel then
                note('engine', measured)
                f.vel = measured
            else
                note('rejected', measured)
            end
        end
    end
    return hit, false
end

local function bound(v, pos, conf, dt)
    if f.zone and not conf.ignoreNoFly then
        local out = vector3(pos.x - f.zone.x, pos.y - f.zone.y, 0.0)
        local length = #out
        if length > 0.01 then
            out = out / length
            local inward = v.x * out.x + v.y * out.y
            if inward < 0.0 then v = v - out * inward end
            v = v + out * (12.0 * dt)
        end
    end
    if f.agl >= conf.maxAltitude and v.z > 0.0 then v = vector3(v.x, v.y, f.agl > conf.maxAltitude + 2.0 and -1.0 or 0.0) end
    if #v > 80.0 then v = v * (80.0 / #v) end
    return v
end

local function touchdown(drone, input, v, dt, after)
    if DC.session.race then return false end
    if f.agl < 0.4 and input.z < -0.5 and #v < 1.0 then
        f.landTimer = f.landTimer + dt
        if f.landTimer > after then land(drone); return true end
    else
        f.landTimer = 0.0
    end
    return false
end

local function flyAcro(dt, drone, conf, input, pos)
    local a, A = f.acro, C.acro
    local hit, crashed = contact(drone, conf)
    if crashed then return true end
    if hit > 0.12 and A.tumble > 0.0 then
        local spin = math.rad(A.tumble)
        a.kick = a.kick + vector3(math.random() * 2.0 - 1.0, math.random() * 2.0 - 1.0, (math.random() * 2.0 - 1.0) * 0.4) * (spin * hit)
        if #a.kick > spin * 1.5 then a.kick = a.kick * (spin * 1.5 / #a.kick) end
    end

    local sx, sy = input.x, input.y
    if keyboard() then sx, sy = ramp(a.sx, input.x, dt), ramp(a.sy, input.y, dt) end
    a.sx, a.sy = sx, sy
    local look, turn, stickPitch, stickYaw = 0.0, 0.0, 0.0, 0.0
    if keyboard() then
        local scale = DC.prefs.sensitivity / 100.0 * A.mouse * 8.0 * f.fov / C.camera.fov
        look, turn = -input.ly * scale, -input.lx * scale
    else
        stickPitch, stickYaw = -input.ly, -input.lx
    end
    if DC.prefs.invert then look, stickPitch = -look, -stickPitch end
    if f.view == 'chase' then look, stickPitch = 0.0, 0.0 end
    local rate = acroRate()
    local pitchRate = expo(D.clamp(stickPitch - sy, -1.0, 1.0)) * A.pitchRate * rate
    local rollRate = expo(D.clamp(sx, -1.0, 1.0)) * A.rollRate * rate
    local yawRate = expo(D.clamp(stickYaw, -1.0, 1.0)) * A.yawRate * rate
    local turnBy = vector3(math.rad(pitchRate * dt + look), math.rad(rollRate * dt), math.rad(yawRate * dt + turn)) + a.kick * dt
    a.kick = a.kick * math.exp(-dt * 5.0)
    a.q = U.qnorm(U.qmul(a.q, U.qturn(turnBy)))
    local q = a.q

    local top = A.thrust * GRAVITY
    local z = D.clamp(input.z, -1.0, 1.0)
    local want = z >= 0.0 and GRAVITY + z * (top - GRAVITY) or GRAVITY * (1.0 + z)
    a.thrust = a.thrust + (want - a.thrust) * math.min(1.0, dt * 12.0)

    local v = f.vel
    local drag = GRAVITY * math.sqrt(A.thrust * A.thrust - 1.0) / (A.topSpeed * A.topSpeed)
    v = bound(v + (U.qrot(q, UP) * a.thrust - UP * GRAVITY - v * (#v * drag + 0.05)) * dt, pos, conf, dt)
    f.vel = v
    if touchdown(drone, input, v, dt, 0.6) then return false end

    SetEntityQuaternion(drone, U.F(q.x), U.F(q.y), U.F(q.z), U.F(q.w))
    SetEntityVelocity(drone, U.F(v.x), U.F(v.y), U.F(v.z))
    local spin = U.qrot(q, turnBy) * (1.0 / dt)
    if #spin > 25.0 then spin = spin * (25.0 / #spin) end
    SetEntityAngularVelocity(drone, U.F(spin.x), U.F(spin.y), U.F(spin.z))

    a.look = acroLook(q, acroTilt())
    if a.look.x * a.look.x + a.look.y * a.look.y > 0.0025 then f.heading = U.heading(a.look.x, a.look.y) end
    f.body = f.heading
    a.chase = a.chase + U.angleDelta(a.chase, chaseHeading(a, q)) * math.min(1.0, dt * 2.5)
    return false
end

local function glideLean(g, dt, ax, ay, limit, weight)
    local pitch, roll = -math.deg(math.atan(ay, GRAVITY)), math.deg(math.atan(ax, GRAVITY))
    local size = math.sqrt(pitch * pitch + roll * roll)
    if size > limit then pitch, roll = pitch * limit / size, roll * limit / size end
    g.pitch, g.pitchRate = spring(g.pitch, g.pitchRate, g.pitch + (pitch - g.pitch) * weight, dt, LEAN_SPRING)
    g.roll, g.rollRate = spring(g.roll, g.rollRate, g.roll + (roll - g.roll) * weight, dt, ROLL_SPRING)
end

local function glideFrame(g, pitch, roll, look)
    local lean = U.qmul(U.qturn(vector3(math.rad(pitch), 0.0, 0.0)), U.qturn(vector3(0.0, math.rad(roll), 0.0)))
    return U.qmul(U.qmul(U.qyaw(f.heading), lean), U.qmul(U.qturn(vector3(math.rad(look), 0.0, 0.0)), g.turn))
end

local function flyGlide(now, dt, drone, conf, input, pos)
    local g, A = f.glide, C.acro
    local _, crashed = contact(drone, conf)
    if crashed then return true end

    local mx, my, fx, fy = input.x, input.y, 0.0, 0.0
    local dev = g.dev
    if dev and now < dev.ends then
        mx, my, fx, fy = dev.x, dev.y, dev.fx, dev.fy
        f.heading = (f.heading + dev.yaw * dt) % 360.0
        if dev.look ~= 0.0 then glideLook(g, dev.look * dt, now) end
    elseif f.view ~= 'chase' and held('boost') then
        mx, my, fx, fy = 0.0, 0.0, -input.y, input.x
    end
    if f.view == 'chase' or (f.agl < 1.0 and #g.spin < 1.0 and U.qangle(g.turn, IDENTITY) < 1.0) then fx, fy = 0.0, 0.0 end
    if fx ~= 0.0 or fy ~= 0.0 then
        local flipRate = A.flipRate * acroRate()
        local want = vector3(fx, fy, 0.0) * flipRate
        local gap = want - g.spin
        local step = keyboard() and A.keyRamp > 0.0 and flipRate / A.keyRamp * dt or math.huge
        g.spin = #gap > step and g.spin + gap * (step / #gap) or want
        g.turn = U.qnorm(U.qmul(g.turn, U.qturn(g.spin * math.rad(dt))))
    else
        g.turn, g.spin = settleTurn(g.turn, g.spin, dt)
    end
    if now - g.looked > A.lookRest * 1000.0 then settleLook(g, dt) end
    local look = lookPitch(g)
    local chase = f.view == 'chase'
    if chase and look == 0.0 then g.view = D.clamp(g.view, C.camera.gimbalMin, C.camera.gimbalMax) end
    local aim = glideAim(g)
    local steep, band = math.abs(aim), A.levelBand
    local slope = (chase or steep <= band) and 0.0 or math.rad((steep < band * 2.0 and (steep - band) * 2.0 or steep) * (aim < 0.0 and -1.0 or 1.0))
    if not chase and look ~= 0.0 then slope = math.rad(aim + look) end

    local swing = math.rad(U.angleDelta(g.heading, f.heading))
    g.heading = f.heading
    local fwd, right = forward(f.heading)
    local speed = #f.vel
    local fade = math.max(0.0, 1.0 - (U.qangle(g.turn, IDENTITY) + math.abs(look)) / GRIP_FADE)
    local cruiseAir = (A.authority * GRAVITY * math.tan(math.rad(math.min(CRUISE_LEAN, A.tilt * 0.6))) / A.cruise - AIR_LINEAR) / A.cruise
    local drag = f.vel * (AIR_LINEAR + (AIR_SQUARE + (cruiseAir - AIR_SQUARE) * fade) * speed)
    local k = 1.0 + (A.authority - 1.0) * fade
    local tricking = fx ~= 0.0 or fy ~= 0.0 or math.abs(look) > 10.0 or U.qangle(g.turn, IDENTITY) > 0.01
    local carve = tricking and 0.0 or swing * A.carve
    if carve ~= 0.0 then
        local c, s = math.cos(carve), math.sin(carve)
        f.vel = vector3(f.vel.x * c - f.vel.y * s, f.vel.x * s + f.vel.y * c, f.vel.z)
    end
    local level = my * math.cos(slope)
    local line = vector3(fwd.x * level, fwd.y * level, my * math.sin(slope)) * A.cruise
    local side = right * (mx * A.cruise)
    local ask = line + side
    local size = #ask
    if keyboard() and A.keyEase > 0.0 and size > 0.05 * A.cruise then
        local dir = ask / size
        local along = D.clamp(f.vel.x * dir.x + f.vel.y * dir.y + f.vel.z * dir.z, 0.0, A.cruise)
        local creep = math.min(A.creep, A.cruise)
        local span = math.max(A.cruise - creep, 0.001)
        g.ease = math.min(1.0, math.max(g.ease, math.sqrt(math.max(0.0, along - creep) / span)) + dt / A.keyEase)
        local cap = creep + span * g.ease * g.ease
        if size > cap then line, side = line * (cap / size), side * (cap / size) end
    else
        g.ease = 0.0
    end
    local throttle = input.z > 0.0 and math.min(input.z, 1.0) * A.climb or math.max(input.z, -1.0) * A.descent
    local brake = math.min(A.pullOut, 0.85 * (A.thrust - 1.0) * GRAVITY)
    local room = math.sqrt(2.0 * brake * math.max(f.agl + f.vel.z * 0.1 - A.floor, 0.0))
    local settle = throttle < 0.0 and math.min(-throttle, 0.5 + f.agl * 0.8) or 0.0
    local low = math.max(-A.cruise, -math.max(room, settle))
    local want = line.z + throttle
    local fit = D.clamp(want, low, A.climb)
    if fit ~= want and line.z ~= 0.0 then line = line * D.clamp((fit - throttle) / line.z, 0.0, 1.0) end
    ask = line + side
    local aimFlat = (fx ~= 0.0 or fy ~= 0.0) and flat(f.vel) or vector3(ask.x, ask.y, 0.0)
    local pull = (aimFlat - flat(f.vel)) * ((1.0 - math.exp(-A.response * dt)) / dt) + flat(drag)
    local steer = math.abs(mx) > 0.05 or math.abs(my) > 0.05
    local flare = A.tilt * A.brake * math.min(1.0, #flat(f.vel) / (A.cruise * FLARE_EASE))
    glideLean(g, dt, (pull.x * right.x + pull.y * right.y) / k, (pull.x * fwd.x + pull.y * fwd.y) / k, steer and A.tilt or flare, fade)
    if not tricking then
        g.rate = g.rate + (D.clamp(carve / dt, -12.0, 12.0) - g.rate) * (1.0 - math.exp(-dt * 20.0))
        local bank = -math.deg(math.atan(#flat(f.vel) * g.rate, k * GRAVITY))
        g.bank = g.bank + (bank - g.bank) * (1.0 - math.exp(-dt * 12.0))
    end

    local climb = D.clamp(ask.z + throttle, low, A.climb)
    local rise = (climb - f.vel.z) * ((1.0 - math.exp(-A.response * dt)) / dt)
    if rise > 0.0 then
        rise = math.min(rise, (A.thrust - 1.0) * GRAVITY)
    else
        rise = math.max(rise, -(f.vel.z > 0.0 and GRAVITY or A.diveAccel))
    end

    local up = U.qrot(glideFrame(g, g.pitch, g.roll, look), UP)
    local lift = GRAVITY + rise + drag.z
    local full = math.cos(math.rad(math.min(A.tilt + 5.0, 75.0)))
    local hold = D.clamp((up.z - 0.2) / (full - 0.2), 0.0, 1.0)
    local power = D.clamp((up.z + 0.25) / 0.3, 0.0, 1.0)
    local want = D.clamp(lift / math.max(up.z, 0.05), 0.0, A.thrust * GRAVITY) * power + GRAVITY * 0.15 * (1.0 - power)
    g.thrust = g.thrust + (want - g.thrust) * math.min(1.0, dt * 12.0)
    local assist = A.float * math.max(0.0, math.min(lift, GRAVITY + drag.z + math.max(0.0, -f.vel.z) * A.response) - g.thrust * up.z) * (1.0 - hold)
    local push = up * g.thrust
    push = vector3(push.x * k, push.y * k, push.z)
    local grip = A.grip * fade
    local gap = pull - flat(push)
    local gapSize = #gap
    if gapSize > grip then gap = gap * (grip / gapSize) end
    local accel = push + gap + UP * (assist - GRAVITY) - drag
    accel = vector3(accel.x, accel.y, accel.z + (rise - accel.z) * fade)
    local v = bound(f.vel + accel * dt, pos, conf, dt)
    f.vel = v
    if touchdown(drone, input, v, dt, 0.5) then return false end

    local diving = not chase and not tricking and my > 0.0 and slope < 0.0
    local reach = D.clamp((#v - 1.0) / (A.cruise * NOSE_SPEED), 0.0, 1.0)
    local path = math.deg(math.atan(v.z, math.max(#flat(v), 0.01)))
    local noseGoal = diving and math.min(path, 0.0) * A.nose * reach * math.min(my, 1.0) or 0.0
    g.nose, g.noseRate = spring(g.nose, g.noseRate, noseGoal, dt, NOSE_SPRING)
    if not chase then
        local mount = D.clamp(g.nose, aim - C.camera.gimbalMax, aim - C.camera.gimbalMin)
        if mount ~= g.nose then g.nose, g.noseRate = mount, 0.0 end
    end
    f.gimbal = chase and aim or aim - g.nose

    local roll = D.clamp(g.roll + g.bank, -A.tilt - 10.0, A.tilt + 10.0)
    local q = glideFrame(g, g.pitch, roll, look + g.nose)
    SetEntityQuaternion(drone, U.F(q.x), U.F(q.y), U.F(q.z), U.F(q.w))
    SetEntityVelocity(drone, U.F(v.x), U.F(v.y), U.F(v.z))
    local spin = U.qspin(g.q, q, dt)
    if #spin > 25.0 then spin = spin * (25.0 / #spin) end
    SetEntityAngularVelocity(drone, U.F(spin.x), U.F(spin.y), U.F(spin.z))
    g.q = q
    local lensShare = chase and 1.0 or D.clamp(2.0 - steep / math.max(band, 0.001), 0.0, 1.0)
    g.lensPitch, g.lensPitchRate = spring(g.lensPitch, g.lensPitchRate, g.pitch * A.viewPitch * lensShare, dt, LENS_SPRING)
    g.lensRoll, g.lensRollRate = spring(g.lensRoll, g.lensRollRate, roll, dt, LENS_SPRING)
    local mounted = U.qmul(glideFrame(g, g.lensPitch, 0.0, look + g.nose), U.qturn(vector3(math.rad(f.gimbal), 0.0, 0.0)))
    g.cam = U.qmul(mounted, U.qturn(vector3(0.0, math.rad(g.lensRoll), 0.0)))
    f.pitch, f.roll, f.body = g.pitch, roll, f.heading
    return false
end

local function deadstick(drone)
    local a = f.acro
    if a then
        if f.view == 'chase' then f.heading = a.chase % 360.0 end
        f.gimbal = a.gimbal
    end
    if f.glide then SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0) end
    f.acro, f.recover, f.acquiring, f.glide = nil, nil, nil, nil
    releaseLock()
    motorsOn(drone, false)
    f.vel = GetEntityVelocity(drone)
    f.rth, f.landing, f.takeoff, f.landTimer, f.boost, f.braking = nil, false, nil, 0.0, false, false
    f.falling = { since = U.now(), still = 0.0 }
    U.sound('lost')
end

local function fall(now, dt, drone, conf)
    local _, crashed = collide(drone, conf)
    if crashed then return end
    local measured = GetEntityVelocity(drone)
    f.vel = measured
    local drop = f.falling
    drop.still = #measured < 0.3 and drop.still + dt or 0.0
    if drop.still > 1.0 or now - drop.since > 10000 then
        f.falling = nil
        f.vel = vector3(0.0, 0.0, 0.0)
        FreezeEntityPosition(drone, true)
        f.status = 'landed'
    end
end

local function fly(now, dt, drone, conf, input)
    local s = DC.session
    local pos = f.posAt == now and f.pos or GetEntityCoords(drone)
    PF.on('cxdrone:fly.ground')
    f.groundProbe.flags = s.race and 1 or nil
    local ground = Autopilot.ground(f.groundProbe, now, drone, pos)
    PF.off()
    if ground then f.agl = ground end
    if s.battery <= 0.0 and f.motors then
        if f.agl < 0.4 and not f.acro then land(drone) else deadstick(drone) end
    end
    if f.falling then fall(now, dt, drone, conf); return end
    if (f.acro or f.glide) and (f.rth or f.landing or f.lostSince or not f.motors) then exitAcro(drone); exitGlide(drone) end
    if s.race and f.motors and not f.takeoff then holdRaceAcro(drone) else settlePendingAcro(drone, conf) end

    PF.on('cxdrone:fly.lock')
    stepLock(now, drone, conf)
    PF.off()
    local c = f.cine
    if f.lock then
        local aim, rate = lockAim(now), 6.0
        if c then
            rate = C.cinematic.aim
            aim = aim + (subjectVel(dt) - f.vel) * (1.0 / rate)
        end
        local d = aim - (pos + gimbalOffset())
        local horizontal = math.sqrt(d.x * d.x + d.y * d.y)
        local wantYaw = U.heading(d.x, d.y)
        local wantPitch = math.deg(math.atan(d.z, math.max(horizontal, 0.01)))
        if c then
            local reach = C.cinematic.framing
            c.fx = D.clamp(c.fx + input.yaw, -reach.yaw, reach.yaw)
            c.fy = D.clamp(c.fy + input.tilt, -reach.pitch, reach.pitch)
            wantYaw, wantPitch = wantYaw + c.fx, wantPitch + c.fy
        end
        f.heading = f.heading + U.angleDelta(f.heading, wantYaw) * math.min(1.0, dt * rate)
        f.gimbal = lerp(f.gimbal, D.clamp(wantPitch, C.camera.gimbalMin, C.camera.gimbalMax), dt * rate)
    elseif c and s.battery > 0.0 then
        local rate = C.cinematic.look
        if f.rth then c.yaw, c.tilt = f.heading, f.gimbal end
        c.yaw = (c.yaw + input.yaw) % 360.0
        c.tilt = D.clamp(c.tilt + input.tilt, C.camera.gimbalMin, C.camera.gimbalMax)
        f.heading = (f.heading + U.angleDelta(f.heading, c.yaw) * math.min(1.0, dt * rate)) % 360.0
        f.gimbal = lerp(f.gimbal, c.tilt, dt * rate)
    elseif not f.acro and s.battery > 0.0 then
        f.heading = (f.heading + input.yaw) % 360.0
        if f.glide then
            glideLook(f.glide, input.tilt, now)
        else
            f.gimbal = D.clamp(f.gimbal + input.tilt, C.camera.gimbalMin, C.camera.gimbalMax)
        end
    end

    if f.lostSince and not (f.rth and f.rth.forced) and not f.landing then input = IDLE end

    if not f.motors then
        if s.state ~= 'crashed' and input.z > 0.5 and s.battery > 0.0 then
            f.takeoff = { at = now }
            motorsOn(drone, true)
            f.status = 'starting'
            s.state = 'flying'
            TriggerServerEvent(RESOURCE .. ':pilot', { on = true, flying = true })
            U.sound('start')
        end
    elseif f.takeoff then
        local elapsed = now - f.takeoff.at
        if elapsed < 1000 then
            f.vel = vector3(0.0, 0.0, 0.0)
        elseif f.agl < C.flight.takeoffHeight and elapsed < 5000 then
            f.status = 'flying'
            f.vel = vector3(0.0, 0.0, 1.6)
        else
            f.takeoff = nil
        end
    elseif f.acro then
        PF.on('cxdrone:fly.acro')
        local crashed = flyAcro(dt, drone, conf, input, pos)
        PF.off()
        if crashed then return end
    elseif f.glide then
        PF.on('cxdrone:fly.glide')
        local crashed = flyGlide(now, dt, drone, conf, input, pos)
        PF.off()
        if crashed then return end
    else
        PF.on('cxdrone:fly.collide')
        local _, crashed = collide(drone, conf)
        PF.off()
        if crashed then return end
        PF.on('cxdrone:fly.target')
        local tv = flightTarget(dt, input, drone, pos, conf)
        PF.off()
        if f.motors then
            local accel = speeds().accel
            if c then
                if f.rth or f.landing then
                    c.tv = tv
                else
                    local shooting = f.lock and c.shot and c.shot.name ~= 'track'
                    local ease = math.max(shooting and C.cinematic.ease * 0.4 or C.cinematic.ease, 0.01)
                    c.tv = c.tv + (tv - c.tv) * (1.0 - math.exp(-dt / ease))
                    tv = c.tv
                    if shooting then accel = math.max(accel, C.cinematic.accel) end
                end
            end
            PF.on('cxdrone:fly.sense')
            tv = sense(now, tv, drone, pos, conf)
            PF.off()
            local horizontal = approach(flat(f.vel), flat(tv), (#flat(tv) < #flat(f.vel) and accel * 1.6 or accel) * dt)
            local vertical = f.vel.z + D.clamp(tv.z - f.vel.z, -accel * 1.4 * dt, accel * 1.4 * dt)
            f.vel = vector3(horizontal.x, horizontal.y, vertical)
            if f.agl < 0.4 and input.z < -0.5 and #horizontal < 1.0 and not f.rth then
                f.landTimer = f.landTimer + dt
                if f.landTimer > 0.5 then land(drone) end
            else
                f.landTimer = 0.0
            end
        end
    end

    aimLight(dt)

    PF.on('cxdrone:fly.pose')
    if f.motors and not (f.acro or f.glide) then
        f.body = f.body + U.angleDelta(f.body, f.heading) * math.min(1.0, dt * 8.0)
        local r = f.recover
        if r then
            local level = U.qyaw(f.body)
            local k = 1.0 - math.exp(-dt * 6.0)
            r.q = U.qslerp(r.q, level, k)
            r.tilt = r.tilt + (f.gimbal - r.tilt) * k
            if now >= r.ends or (U.qangle(r.q, level) < 2.0 and math.abs(f.gimbal - r.tilt) < 1.0) then
                f.recover = nil
                SetEntityRotation(drone, 0.0, 0.0, U.F(f.body), 2, true)
            else
                SetEntityQuaternion(drone, U.F(r.q.x), U.F(r.q.y), U.F(r.q.z), U.F(r.q.w))
            end
        else
            local sp = speeds()
            local fwd, right = forward(f.heading)
            local along = (f.vel.x * fwd.x + f.vel.y * fwd.y) / sp.horizontal
            local side = (f.vel.x * right.x + f.vel.y * right.y) / sp.horizontal
            local t = now / 1000.0
            f.pitch = lerp(f.pitch, -D.clamp(along, -1.0, 1.0) * sp.tilt + math.sin(t * 1.7) * 0.4, dt * 5.0)
            f.roll = lerp(f.roll, D.clamp(side, -1.0, 1.0) * sp.tilt + math.sin(t * 1.3) * 0.4, dt * 5.0)
            SetEntityRotation(drone, U.F(f.pitch), U.F(f.roll), U.F(f.body), 2, true)
        end
        SetEntityVelocity(drone, U.F(f.vel.x), U.F(f.vel.y), U.F(f.vel.z))
    end
    PF.off()
    drainBattery(now, dt, conf)
end

local function step(now, dt, drone, conf)
    PF.on('cxdrone:input')
    local input = filming() and IDLE or readInput(dt)
    handleButtons(now, dt, drone, conf)
    PF.off()
    if f.ending then return end
    PF.on('cxdrone:acquire')
    stepAcquire(now, drone)
    PF.off()
    PF.on('cxdrone:fly')
    fly(now, dt, drone, conf, input)
    PF.off()
end

local function link(now, drone, conf)
    local s = DC.session
    local ped = PlayerPedId()
    local pos = GetEntityCoords(drone)

    if IsEntityInWater(drone) and GetEntitySubmergedLevel(drone) > 0.3 then crash(drone, 'water'); return end
    if IsEntityDead(drone) or GetVehicleEngineHealth(drone) <= 0.0 then crash(drone, 'destroyed'); return end
    U.foldEngineDamage(drone)
    local body, engine = GetVehicleBodyHealth(drone), GetVehicleEngineHealth(drone)
    if body <= 0.0 then crash(drone, 'destroyed'); return end
    f.health = body + engine

    if f.motors and not GetIsVehicleEngineRunning(drone) then SetVehicleEngineOn(drone, true, true, true) end
    if f.motors and IsEntityPositionFrozen(drone) then FreezeEntityPosition(drone, false) end

    if not NetworkHasControlOfEntity(drone) then
        NetworkRequestControlOfEntity(drone)
        f.noControl = f.noControl or now
        if now - f.noControl > 2500 then return 'control' end
    else
        f.noControl = nil
    end

    f.distance = #(pos - GetEntityCoords(ped))
    if f.distance < 4.0 then SetEntityNoCollisionEntity(drone, ped, true) end
    f.zone = (not conf.ignoreNoFly and not s.race) and D.noFly(pos.x, pos.y) or nil

    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local los = Autopilot.probe(f.losProbe, now, 500, head, pos, 1 | 16, ped)
    if los then f.obstructed = los.hit and #(los.coords - pos) > 1.5 end
    f.quality = s.race and 1.0 or D.signal(f.distance, conf.range, f.obstructed)
    f.bars = D.bars(f.quality)
    if f.quality <= 0.0 then
        f.lostSince = f.lostSince or now
        if now - f.lostSince > C.signal.lostGraceSeconds * 1000 and f.motors and not f.lostActed then
            f.lostActed = true
            return 'lost'
        end
    elseif f.quality > 0.15 then
        if f.lostSince and f.rth and f.rth.reason == 'signal' then f.rth.forced = false end
        f.lostSince, f.lostActed = nil, false
    end

    if s.battery > C.battery.returnAt then f.lowReturned = false end
    if f.motors and s.battery <= C.battery.returnAt and not f.lowReturned and s.battery > 0.0 then
        f.lowReturned = true
        return 'battery'
    end
end

local function slow(now, drone, conf)
    local event = link(now, drone, conf)
    if f.ending then return end
    if event == 'control' then P.stop('control'); U.notify('notify.control'); return end
    if event == 'lost' then
        local action = C.signal.onLost
        if action == 'hover' then P.stop('lost'); U.notify('notify.lost'); return
        elseif action == 'land' then
            if filming() then releaseLock() end
            f.landing, f.rth = true, nil
        else startReturn(true, 'signal') end
    elseif event == 'battery' then
        startReturn(false, 'battery')
    end

    local ped = PlayerPedId()
    local pedHealth = vitals(ped)
    if filming() then
        if downed(ped) then P.stop('pilot'); return end
        if not f.motors then releaseLock() end
        f.pedHealth = pedHealth
        setFuzz(f.lostSince and 0.9 or (f.quality < 0.5 and (0.5 - f.quality) * 1.4 or 0.0))
        return
    end
    if downed(ped) or IsPedInAnyVehicle(ped, true) or IsPedSwimming(ped) then P.stop('pilot'); return end
    if (IsPedRagdoll(ped) or (C.flight.pilotHitDropsLink and not (DC.session and DC.session.race) and pedHealth < f.pedHealth)) then
        P.stop('pilot_hit')
        U.notify('notify.pilotHit')
        return
    end
    f.pedHealth = pedHealth
    if now >= f.nextAnim then playPilotAnim(ped); f.nextAnim = now + 600 end
    setFuzz(f.lostSince and 0.9 or (f.quality < 0.5 and (0.5 - f.quality) * 1.4 or 0.0))
end

local function rangefind(now, drone)
    if f.lock or f.acro or f.cine then f.range, f.rangePoint = nil, nil; return end
    local from = f.pos + gimbalOffset()
    local result = Autopilot.probe(f.rangeProbe, now, 200, from, from + cameraDirection() * 1000.0, SEE, drone)
    if not result then return end
    if result.hit then
        f.range, f.rangePoint = #(result.coords - from), result.coords
    else
        f.range, f.rangePoint = nil, nil
    end
end

local function clearance(now, drone)
    local speed = #f.vel
    if not f.motors or f.falling or #flat(f.vel) < 1.0 then f.clearance = nil; return end
    local radius = C.sensing.radius
    local reach = D.clamp(speed * 2.5, 8.0, 80.0)
    local result = Autopilot.probe(f.clearProbe, now, 100, f.pos, f.pos + f.vel / speed * reach, SEE, drone, radius)
    if not result then return end
    if result.hit then
        f.clearance, f.clearanceAt = math.max(0.0, #(result.coords - f.pos) - radius), now
    elseif not f.clearanceAt or now - f.clearanceAt > 300 then
        f.clearance = nil
    end
end

local function guarded(drone, from, dir, length)
    local guard = f.camGuard
    if not guard then
        guard = {}
        f.camGuard = guard
    end
    if guard.handle then
        local status, hit = GetShapeTestResult(guard.handle)
        if status ~= 1 then guard.handle = nil end
        if status == 2 then
            guard.clear = not (hit == 1 or hit == true)
            guard.at, guard.dir, guard.reach = guard.sentAt, guard.sentDir, guard.sentReach
        end
    end
    local speed = #f.vel
    if not guard.handle then
        local lead = 0.05 + speed * 0.1
        local reach = lead + length + 1.0 + speed * 0.1
        local start = from - dir * lead
        local tip = start + dir * reach
        guard.handle = StartShapeTestLosProbe(start.x, start.y, start.z, tip.x, tip.y, tip.z, CAMERA, drone, 7)
        guard.sentAt, guard.sentDir, guard.sentReach = start, dir, reach
    end
    if not (guard.clear and guard.at) then return false end
    local shift = from - guard.at
    local along = shift.x * guard.dir.x + shift.y * guard.dir.y + shift.z * guard.dir.z
    local aside = #(shift - guard.dir * along)
    local aligned = dir.x * guard.dir.x + dir.y * guard.dir.y + dir.z * guard.dir.z
    return aside < 0.02 + speed * 0.025 and aligned > 0.998 and along >= 0.0 and along + length <= guard.reach
end

local function blocked(drone, from, to)
    PF.on('cxdrone:camera.probe')
    local ray = to - from
    local length = #ray
    if length < 0.001 or guarded(drone, from, ray / length, length) then
        PF.off()
        return nil
    end
    PF.on('cxdrone:camera.sync')
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, CAMERA, drone, 7)
    local _, hit, coords = GetShapeTestResult(handle)
    PF.off()
    PF.off()
    if hit == 1 or hit == true then return #(coords - from) end
end

local function easeLens(dt)
    local l = f.lens
    l.pitch, l.pitchRate = spring(l.pitch, l.pitchRate, 0.0, dt, LENS_SPRING)
    l.roll, l.rollRate = spring(l.roll, l.rollRate, 0.0, dt, LENS_SPRING)
    if math.abs(l.pitch) + math.abs(l.roll) < 0.05 and math.abs(l.pitchRate) + math.abs(l.rollRate) < 0.05 then
        f.lens = nil
        aimCam(f.gimbal, f.heading)
        return
    end
    local lean = U.qmul(U.qturn(vector3(math.rad(l.pitch), 0.0, 0.0)), U.qturn(vector3(0.0, math.rad(l.roll), 0.0)))
    l.cam = U.qmul(U.qmul(U.qyaw(f.heading), lean), U.qturn(vector3(math.rad(f.gimbal), 0.0, 0.0)))
    local pitch, roll, yaw = U.euler(l.cam)
    f.camPitch = nil
    SetCamRot(f.cam, U.F(pitch), U.F(roll), U.F(yaw), 2)
end

local function camera(dt, drone, pos)
    if not f.cam then return end
    f.fov = lerp(f.fov, C.camera.fov / f.zoom, dt * (f.cine and C.cinematic.zoom or 8.0))
    if not f.camFov or math.abs(f.camFov - f.fov) >= 0.001 then
        f.camFov = f.fov
        SetCamFov(f.cam, U.F(f.fov))
    end
    local centre = pos or GetEntityCoords(drone)
    f.tucked = false
    local pose = f.acro and f.acro.q or (f.recover and f.recover.q)
    local tilt = f.acro and acroTilt() or (f.recover and f.recover.tilt)
    local hard = pose ~= nil and f.view == 'gimbal'
    if hard or f.view ~= 'gimbal' then f.lens = nil end
    if hard ~= f.hardCam then
        DetachCam(f.cam)
        f.hardCam = hard
        f.camAt, f.camPitch = nil, nil
    end
    if hard then
        local o = C.camera.offset
        local reach = U.qrot(pose, vector3(o.x, o.y, o.z)) + acroLook(pose, tilt) * CLEAR
        local length = #reach
        local hit = length > 0.001 and blocked(drone, centre, centre + reach)
        local scale = 1.0
        if hit then
            scale = math.max(0.0, hit - CLEAR) / length
            f.tucked = true
        end
        HardAttachCamToEntity(f.cam, drone, U.F(tilt), 0.0, 0.0, U.F(o.x * scale), U.F(o.y * scale), U.F(o.z * scale), true)
    elseif f.view == 'gimbal' then
        local g = f.glide
        local offset = gimbalOffset()
        local reach = offset + cameraDirection() * CLEAR
        local length = #reach
        local hit = length > 0.001 and blocked(drone, centre, centre + reach)
        if hit then
            offset = reach * (math.max(0.0, hit - CLEAR) / length)
            f.tucked = true
        end
        attachCam(drone, offset)
        if g and g.cam then
            local pitch, roll, yaw = U.euler(g.cam)
            f.camPitch = nil
            SetCamRot(f.cam, U.F(pitch), U.F(roll), U.F(yaw), 2)
        elseif f.lens then
            easeLens(dt)
        else
            aimCam(f.gimbal, f.heading)
        end
    else
        local heading = f.acro and f.acro.chase or f.heading
        local fwd = forward(heading)
        local chase = C.camera.chase
        local full = vector3(0.0, 0.0, chase.height) - fwd * chase.distance
        local length = #full
        local hit = blocked(drone, centre, centre + full * ((length + 0.3) / length))
        local room = hit and math.max(0.0, hit - 0.3) / length or 1.0
        f.chase = room < f.chase and room or lerp(f.chase, room, dt * 2.0)
        local at = full * f.chase
        f.tucked = length * f.chase < 0.6
        attachCam(drone, at)
        local look = fwd * 4.0 + vector3(0.0, 0.0, math.sin(math.rad(f.acro and -8.0 or f.gimbal)) * 4.0)
        local d = look - at
        local pitch = math.deg(math.atan(d.z, math.sqrt(d.x * d.x + d.y * d.y)))
        aimCam(pitch, heading)
    end
end

local function blankTrace(now, pos, vel)
    return { since = now, frames = 0, maxDt = 0.0, col = 0, verr = 0.0, verrMax = 0.0, drift = 0.0, driftMax = 0.0, pos = pos, vel = vel,
        qfwd = nil, qdrift = 0.0, qcam = nil }
end

local function traceFrame(now, dt, drone)
    local t = f.trace or blankTrace(now)
    f.trace = t
    local pos, vel = GetEntityCoords(drone), GetEntityVelocity(drone)
    if t.pos and f.motors then
        local e = #(vel - t.vel)
        local d = #(pos - (t.pos + t.vel * dt))
        t.verr, t.verrMax = t.verr + e, math.max(t.verrMax, e)
        t.drift, t.driftMax = t.drift + d, math.max(t.driftMax, d)
    end
    t.frames, t.maxDt = t.frames + 1, math.max(t.maxDt, dt)
    if HasEntityCollidedWithAnything(drone) then t.col = t.col + 1 end
    if f.acro then
        local fwd = GetEntityForwardVector(drone)
        local mine = U.qrot(f.acro.q, vector3(0.0, 1.0, 0.0))
        t.qfwd = math.min(t.qfwd or 1.0, fwd.x * mine.x + fwd.y * mine.y + fwd.z * mine.z)
        t.qdrift = math.max(t.qdrift, U.qangle(U.quaternion(drone), f.acro.q))
        if f.hardCam then
            local rot = GetFinalRenderedCamRot(2)
            local seen = U.rotationToDirection(rot.x, rot.z)
            local look = f.acro.look
            t.qcam = math.min(t.qcam or 1.0, seen.x * look.x + seen.y * look.y + seen.z * look.z)
        end
    end
    if now - t.since < 1000 then return end
    local n = math.max(t.frames, 1)
    local acro = f.acro and ('acro thr=%.1fg qfwd=%.3f qdrift=%.1f qcam=%s'):format(f.acro.thrust / GRAVITY, t.qfwd or 1.0, t.qdrift,
        t.qcam and ('%.3f'):format(t.qcam) or '-') or (f.glide and ('acro=glide lean=%.0f/%.0f bank=%.0f look=%.0f turn=%.0f spin=%.0f thr=%.1fg gimbal=%.0f'):format(
        f.glide.pitch, f.glide.roll, f.glide.bank, lookPitch(f.glide), U.qangle(f.glide.turn, IDENTITY), #f.glide.spin, f.glide.thrust / GRAVITY, f.gimbal)) or 'acro=off'
    local a = f.adopt or blankAdopt()
    f.adopt = nil
    print(('[%s] trace fps=%d maxdt=%dms col=%d verr=%.2f/%.2f drift=%.3f/%.3f ctrl=%s owner=%s motors=%s spd=%.1f view=%s adopt hit=%d/%+.1f engine=%d/%+.1f rejected=%d/%+.1f top=%.1f %s'):format(
        RESOURCE, t.frames, math.floor(t.maxDt * 1000), t.col, t.verr / n, t.verrMax, t.drift / n, t.driftMax,
        tostring(NetworkHasControlOfEntity(drone)), tostring(NetworkGetEntityOwner(drone) == PlayerId()), tostring(f.motors), #f.vel, f.view,
        a.hit, a.hitGain, a.engine, a.engineGain, a.rejected, a.rejectedGain, a.top, acro))
    f.trace = blankTrace(now, t.pos, t.vel)
end

local function loop()
    while DC.piloting do
        local now = U.now()
        local dt = D.clamp(GetFrameTime(), 0.001, 0.1)
        local s = DC.session
        local drone = s and s.entity
        if not drone or not DoesEntityExist(drone) then P.stop('gone'); break end
        local conf = s.conf
        f.pos, f.posAt = GetEntityCoords(drone), now
        PF.on('cxdrone:frame')
        PF.on('cxdrone:controls')
        f.kb = IsUsingKeyboard(2)

        if filming() or f.pendingLeave then
            local keys, pad = C.controls.keyboard, C.controls.pad
            DisableControlAction(0, keys.acro, true)
            DisableControlAction(0, pad.acro, true)
            DisableControlAction(0, keys.leave, true)
            DisableControlAction(0, pad.leave, true)
            local ped = PlayerPedId()
            SetEntityNoCollisionEntity(drone, ped, true)
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 then SetEntityNoCollisionEntity(drone, vehicle, true) end
        else
            DisableAllControlActions(0)
            EnableControlAction(0, 199, true)
            EnableControlAction(0, 200, true)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 249, true)
        end
        HideHudAndRadarThisFrame()
        PF.off()

        local left = false
        if not f.ending then
            if C.debug then traceFrame(now, dt, drone) end
            if f.raceHold then FreezeEntityPosition(drone, true) else step(now, dt, drone, conf) end
            if C.debug and f.trace then f.trace.pos, f.trace.vel = GetEntityCoords(drone), f.vel end
            if DC.piloting and not f.ending and now >= f.nextSlow then
                f.nextSlow = now + 250
                PF.on('cxdrone:slow')
                slow(now, drone, conf)
                PF.off()
            end
            left = (pressed('leave') or f.pendingLeave) and DC.piloting and not f.ending and not f.falling
        end
        if left or not DC.piloting then
            PF.off()
            if left then P.stop('leave') end
            break
        end

        PF.on('cxdrone:rotors')
        spinRotors(dt, drone)
        PF.off()
        PF.on('cxdrone:camera')
        camera(dt, drone, f.pos)
        if f.tucked then SetEntityLocallyInvisible(drone) end
        PF.off()
        PF.on('cxdrone:rangefind')
        if not f.ending then rangefind(now, drone) end
        PF.off()
        PF.on('cxdrone:clearance')
        if not f.ending then clearance(now, drone) end
        PF.off()
        if lit() then
            PF.on('cxdrone:spotlight')
            drawSpotlight(drone)
            PF.off()
        end
        if f.lock and not f.lock.hiddenSince and (f.lock.point or DoesEntityExist(f.lock.entity))
            and (not f.cine or (not f.lock.self and now - f.lock.since < 1200)) then
            PF.on('cxdrone:bracket')
            drawBracket(f.lock)
            PF.off()
        end
        present(now, false)

        if now >= f.nextHud then
            f.nextHud = now + 100
            if f.status == 'starting' and not f.takeoff then f.status = 'flying' end
            if s.state ~= 'crashed' then s.state = (f.motors or f.falling) and 'flying' or 'landed' end
            PF.on('cxdrone:hud.build')
            local state = hudState(now, conf, drone, GetEntityCoords(drone))
            PF.off()
            PF.on('cxdrone:hud.send')
            H.state(state)
            PF.off()
            PF.on('cxdrone:legend')
            updateLegend(now)
            H.legend(f.legendSig and legendPx or 0)
            PF.off()
        end
        PF.off()
        Wait(0)
    end
end

local function launch(drone, ped)
    local at = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local found, ground = GetGroundZFor_3dCoord(at.x, at.y, at.z + 0.5, false)
    local height = (found and ground or at.z - 1.0) + C.flight.launchHeight
    local chest = GetPedBoneCoords(ped, 24818, 0.0, 0.0, 0.0)
    local fwd, right = forward(heading)
    local spot, facing, best = nil, heading, -1.0
    for _, dir in ipairs({ fwd, right, -right, -fwd }) do
        local want = vector3(at.x, at.y, height) + dir * 1.2
        local handle = StartExpensiveSynchronousShapeTestLosProbe(chest.x, chest.y, chest.z, want.x, want.y, want.z, SOLID, drone, 7)
        local _, hit, coords = GetShapeTestResult(handle)
        local clear = not (hit == 1 or hit == true)
        local room = clear and 1.2 or #(coords - chest) - 0.45
        if room > best then
            best = room
            local toward = (want - chest) / #(want - chest)
            local near = chest + toward * D.clamp(room, 0.35, 1.2)
            spot, facing = vector3(near.x, near.y, height), U.heading(dir.x, dir.y)
        end
        if clear then break end
    end
    SetEntityNoCollisionEntity(drone, ped, true)
    SetEntityCoordsNoOffset(drone, spot.x, spot.y, spot.z, false, false, false)
    SetEntityRotation(drone, 0.0, 0.0, U.F(facing), 2, true)
    SetEntityVelocity(drone, 0.0, 0.0, 0.0)
    motorsOn(drone, true)
    f.spin = C.rotors.hover
    SetHeliBladesSpeed(drone, U.F(f.spin))
    return facing
end

local ignoreCamCollision = SetGameplayCamIgnoreEntityCollisionThisUpdate
    or function(entity) return Citizen.InvokeNative(0x2AED6301F67007D5, entity) end

local function canToss(ped)
    return IsPedOnFoot(ped) and not IsEntityDead(ped) and not IsPedRagdoll(ped) and not IsPedFalling(ped)
        and not IsPedSwimming(ped) and not IsPedClimbing(ped) and not IsPedInCover(ped, false)
end

local function holdStill()
    DisableAllControlActions(0)
    for _, control in ipairs({ 1, 2, 199, 200, 245, 249 }) do EnableControlAction(0, control, true) end
end

local function handPoint(ped, heading)
    local hold = C.launch.hold
    local hand = GetPedBoneCoords(ped, hold.bone, 0.0, 0.0, 0.0)
    return hand + forward(heading) * hold.forward + UP * hold.up
end

local function preloadPilot()
    U.loadAnim(C.pilot.anim.dict, 1000)
    if C.pilot.prop then
        local hash = U.loadModel(C.pilot.prop.model, 2000)
        if hash then SetModelAsNoLongerNeeded(hash) end
    end
end

local tossing = false

local function toss(s, drone, ped)
    local conf = C.launch
    local anim = conf.anim
    if not conf.enabled or not canToss(ped) then return nil end
    if not HasAnimDictLoaded(anim.dict) and not U.loadAnim(anim.dict, 1500) then return nil end
    preloadPilot()
    local heading = GetEntityHeading(ped)
    SetCurrentPedWeapon(ped, UNARMED, true)
    ClearPedTasks(ped)
    SetEntityNoCollisionEntity(drone, ped, true)
    FreezeEntityPosition(drone, true)
    SetEntityVisible(drone, false, false)
    TaskPlayAnim(ped, anim.dict, anim.name, 4.0, -2.0, -1, anim.flag, 0.0, false, false, false)
    local startBy = U.now() + 1000
    local last, lastAt, velocity, released = nil, 0, vector3(0.0, 0.0, 0.0), false
    while not released do
        Wait(0)
        holdStill()
        if DC.stopped or DC.session ~= s or not DoesEntityExist(drone) or not canToss(ped) then break end
        SetEntityNoCollisionEntity(drone, ped, true)
        ignoreCamCollision(drone)
        if IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then
            local phase = GetEntityAnimCurrentTime(ped, anim.dict, anim.name)
            if phase >= conf.grab then
                local now = U.now()
                heading = GetEntityHeading(ped)
                local point = handPoint(ped, heading)
                if last and now > lastAt then
                    local dt = (now - lastAt) / 1000.0
                    velocity = velocity + ((point - last) / dt - velocity) * (1.0 - math.exp(-dt / 0.03))
                end
                last, lastAt = point, now
                SetEntityCoordsNoOffset(drone, point.x, point.y, point.z, false, false, false)
                SetEntityRotation(drone, 0.0, 0.0, U.F(heading), 2, true)
                if not IsEntityVisible(drone) then SetEntityVisible(drone, true, false) end
                released = phase >= conf.release
            end
        elseif U.now() > startBy then
            break
        end
    end
    if not released then StopAnimTask(ped, anim.dict, anim.name, 2.0) end
    RemoveAnimDict(anim.dict)
    if not DoesEntityExist(drone) then return nil end
    SetEntityVisible(drone, true, false)
    if not released then return nil end
    local fwd = forward(heading)
    local outward = velocity.x * fwd.x + velocity.y * fwd.y
    if outward < conf.push then velocity = velocity + fwd * (conf.push - outward) end
    velocity = vector3(velocity.x, velocity.y, math.max(velocity.z, conf.lift))
    local speed = #velocity
    if speed > conf.maxSpeed then velocity = velocity * (conf.maxSpeed / speed) end
    motorsOn(drone, true)
    f.spin = 0.0
    SetHeliBladesSpeed(drone, 0.0)
    SetEntityVelocity(drone, U.F(velocity.x), U.F(velocity.y), U.F(velocity.z))
    f.vel = velocity
    return heading
end

local LIMBS = { { 45509, 61163 }, { 61163, 18905 }, { 18905, 60309 }, { 40269, 28252 }, { 28252, 57005 }, { 57005, 28422 }, { 31086, 24818 } }

local function apart(p, a, b)
    local ab, ap = b - a, p - a
    local span = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
    local t = span > 0.0001 and D.clamp((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / span, 0.0, 1.0) or 0.0
    return #(p - (a + ab * t))
end

local function clearOf(drone, ped)
    local low, high = GetModelDimensions(GetEntityModel(drone))
    local reach = math.sqrt(math.max(-low.x, high.x) ^ 2 + math.max(-low.y, high.y) ^ 2) + C.launch.clearance
    local at = GetEntityCoords(drone)
    for _, limb in ipairs(LIMBS) do
        if apart(at, GetPedBoneCoords(ped, limb[1], 0.0, 0.0, 0.0), GetPedBoneCoords(ped, limb[2], 0.0, 0.0, 0.0)) < reach then return false end
    end
    return true
end

local function watchToss(s, drone, ped, conf)
    local started = U.now()
    local watch, limit = math.floor(C.launch.watch * 1000), math.floor(C.launch.watch * 1000) + 1500
    local clear, spun = false, false
    while not DC.stopped and DC.session == s and DoesEntityExist(drone) and f.motors do
        local elapsed = U.now() - started
        if elapsed >= limit or (clear and elapsed >= watch) then break end
        Wait(0)
        holdStill()
        SetEntityNoCollisionEntity(drone, ped, true)
        ignoreCamCollision(drone)
        local dt = D.clamp(GetFrameTime(), 0.001, 0.1)
        clear = clearOf(drone, ped)
        if clear then
            if not spun then spun, f.spin = true, C.rotors.hover end
            fly(U.now(), dt, drone, conf, IDLE)
            spinRotors(dt, drone)
        else
            f.vel = f.vel * math.exp(-dt * 1.5)
            SetHeliBladesSpeed(drone, 0.0)
            SetEntityVelocity(drone, U.F(f.vel.x), U.F(f.vel.y), U.F(f.vel.z))
        end
    end
    if not clear and not DC.stopped and DC.session == s and DoesEntityExist(drone) and f.motors then
        motorsOn(drone, false)
        f.vel = GetEntityVelocity(drone)
        f.falling = { since = U.now(), still = 0.0 }
    end
end

local function leaving(s, hold)
    TriggerServerEvent(RESOURCE .. ':leave', { state = s.state, hold = hold, light = f.light, tilt = math.floor(f.lightPitch + 0.5) })
end

local function hover(s, drone)
    f.vel = vector3(0.0, 0.0, 0.0)
    SetEntityVelocity(drone, 0.0, 0.0, 0.0)
    SetEntityRotation(drone, 0.0, 0.0, U.F(f.body), 2, true)
    FreezeEntityPosition(drone, true)
    s.state = 'unattended'
    leaving(s, true)
end

local function undock(s, drone, action)
    f.detached = nil
    releaseLock()
    if not f.motors then
        if f.falling and s.state ~= 'crashed' then
            s.state = 'unattended'
            leaving(s, false)
            Autopilot.fall(drone)
        else
            leaving(s, false)
        end
        return
    end
    if action == 'hover' then hover(s, drone) else Autopilot.unattended(action, f.body) end
end

local function away(now, s, drone, conf)
    local event = link(now, drone, conf)
    if f.ending or not f.detached then return end
    if event == 'control' then undock(s, drone, 'hover')
    elseif event == 'lost' then U.notify('notify.trackingLost', 'info'); undock(s, drone, C.signal.onLost)
    elseif event == 'battery' then undock(s, drone, 'return')
    elseif downed(PlayerPedId()) then undock(s, drone, 'hover') end
end

local function track(s, drone)
    Autopilot.cancel()
    local gen = Autopilot.gen
    f.detached, f.boost, f.tracked = gen, false, drone
    CreateThread(function()
        while f.detached == gen and Autopilot.gen == gen and DC.session == s and not DC.piloting and not DC.stopped
            and not f.ending and DoesEntityExist(drone) do
            local now = U.now()
            fly(now, D.clamp(GetFrameTime(), 0.001, 0.1), drone, s.conf, IDLE)
            if f.detached ~= gen or f.ending then break end
            if not f.lock or not f.motors then undock(s, drone, C.flight.leave); break end
            if now >= f.nextSlow then
                f.nextSlow = now + 250
                away(now, s, drone, s.conf)
            end
            present(now, false)
            Wait(0)
        end
        if f.detached == gen then f.detached, f.lock = nil, nil end
    end)
end

function P.start()
    local s = DC.session
    if DC.piloting or tossing or not s or not DoesEntityExist(s.entity) then return false end
    local drone = s.entity
    local kept = f.detached and f.tracked == drone and f.lock and not f.ending and {
        lock = f.lock, vel = f.vel, heading = f.heading, body = f.body, gimbal = f.gimbal, lightPitch = f.lightPitch, pitch = f.pitch,
        roll = f.roll, mode = f.mode, zoom = f.zoom, vision = f.vision, rth = f.rth, landing = f.landing, lowReturned = f.lowReturned,
        warned = f.warned, agl = f.agl, groundProbe = f.groundProbe, distance = f.distance,
    } or nil
    f.detached = nil
    local resumed = not kept and s.state == 'unattended' and Autopilot.active() or nil
    if not U.control(drone, 2000) then
        if kept then track(s, drone) end
        U.notify('notify.control')
        return false
    end
    SetNetworkIdCanMigrate(s.netId, false)
    Autopilot.cancel()
    s.descending = false
    reset()
    local conf = s.conf
    f.heading = GetEntityHeading(drone)
    f.agl = math.max(0.0, GetEntityHeightAboveGround(drone))
    f.body = f.heading
    f.view = DC.prefs.view == 'chase' and 'chase' or 'gimbal'
    f.light = s.light == true
    FreezeEntityPosition(drone, false)
    SetEntityDynamic(drone, true)
    U.hardenDrone(drone)
    if s.fresh then
        s.fresh = false
        SetVehicleBodyHealth(drone, U.F(conf.health))
        SetVehicleEngineHealth(drone, 1000.0)
        SetVehiclePetrolTankHealth(drone, 1000.0)
    end
    U.foldEngineDamage(drone)
    SetVehicleDoorsLocked(drone, 2)
    local ped = PlayerPedId()
    local tossed = nil
    if s.launch then
        s.launch = false
        tossing = true
        local ok, heading = pcall(toss, s, drone, ped)
        tossed = ok and heading or nil
        if not ok then
            print(('[%s] launch toss failed: %s'):format(RESOURCE, heading))
            if DoesEntityExist(drone) then SetEntityVisible(drone, true, false) end
        end
        if DC.session ~= s or not DoesEntityExist(drone) then tossing = false; return false end
        f.heading = tossed or launch(drone, ped)
        f.body = f.heading
        s.state = 'flying'
        if tossed then
            local watched, failure = pcall(watchToss, s, drone, ped, conf)
            if not watched then print(('[%s] launch watch failed: %s'):format(RESOURCE, failure)) end
        end
        tossing = false
        if DC.session ~= s or not DoesEntityExist(drone) then return false end
    elseif s.state == 'flying' or s.state == 'unattended' then
        motorsOn(drone, true)
        s.state = 'flying'
    else
        motorsOn(drone, false)
        if s.state ~= 'crashed' then park(drone) end
        f.status = 'landed'
    end
    f.health = GetVehicleBodyHealth(drone) + GetVehicleEngineHealth(drone)
    f.lightPitch = D.clamp(f.gimbal, C.spotlight.traverse.min, C.spotlight.traverse.max)
    if kept then
        for key, value in pairs(kept) do f[key] = value end
        f.spin = C.rotors.hover
    elseif resumed == 'return' and f.motors then
        f.rth = { forced = false, reason = 'pilot' }
    elseif resumed == 'land' and f.motors then
        f.landing = true
    end
    if not kept and not s.race then applyStartMode(conf) end

    f.pedHealth = vitals(ped)
    SetCurrentPedWeapon(ped, UNARMED, true)
    SetPedCanSwitchWeapon(ped, false)
    if not tossed then ClearPedTasks(ped) end
    playPilotAnim(ped)
    attachTablet(ped)

    f.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(f.cam, U.F(f.fov))
    SetCamNearClip(f.cam, 0.05)
    applyView(drone)
    camera(0.016, drone)
    RenderScriptCams(true, true, 450, true, true)
    SetFocusEntity(drone)
    applyVision()

    U.hud(false)
    DC.piloting = true
    f.legendUntil = U.now() + 20000
    local text = Locale.prefixed('ui.')
    for key, value in pairs(Locale.prefixed('warning.')) do text[key] = value end
    H.open({
        text = text, units = DC.prefs.units, safezone = GetSafeZoneSize(),
        type = { label = conf.label, zoomMax = conf.zoomMax, features = conf.features, payload = (conf.payload and not s.race) and conf.payload.kind or false,
            light = conf.features.spotlight and { min = C.spotlight.traverse.min, max = C.spotlight.traverse.max } or false,
            range = s.race and 0 or conf.range, fade = C.signal.fadeStart },
    })
    TriggerServerEvent(RESOURCE .. ':pilot', { on = true, flying = f.motors })
    present(U.now(), true)
    U.sound('start')
    CreateThread(loop)
    return true
end

function P.devState()
    local s = DC.session
    local drone = s and s.entity
    local g = f.glide
    local live = drone and DoesEntityExist(drone)
    local rot = live and GetEntityRotation(drone, 2)
    local spin = live and GetEntityRotationVelocity(drone)
    local cam = f.cam and GetFinalRenderedCamRot(2)
    return {
        piloting = DC.piloting == true, state = s and s.state or false, kind = s and s.kind or false, motors = f.motors == true,
        acro = (f.acro and 'manual') or (g and 'glide') or false, controls = DC.prefs.acroControls, mode = f.mode, view = f.view,
        gimbal = f.gimbal, heading = f.heading, agl = f.agl, speed = #f.vel, recover = f.recover ~= nil,
        lean = g and { g.pitch, g.roll, g.bank } or false, look = g and lookPitch(g) or 0.0, aim = g and glideAim(g) or false, nose = g and g.nose or false,
        lens = (g and { g.lensPitch, g.lensRoll }) or (f.lens and { f.lens.pitch, f.lens.roll }) or false, turnRate = g and math.deg(g.rate) or 0.0, spin = g and #g.spin or 0.0,
        turn = g and U.qangle(g.turn, IDENTITY) or 0.0, thrust = g and g.thrust / GRAVITY or false,
        rotation = rot and { rot.x, rot.y, rot.z } or false, spin = spin and { spin.x, spin.y, spin.z } or false,
        camera = cam and { cam.x, cam.y, cam.z } or false, adopt = f.adoptTotal or false,
    }
end

function P.devAcro()
    local s = DC.session
    if not DC.piloting or not s or not DoesEntityExist(s.entity) then return P.devState() end
    toggleAcro(s.entity, kind())
    return P.devState()
end

function P.devGlide(input)
    local g = f.glide
    if g then
        g.dev = { x = input.x or 0.0, y = input.y or 0.0, fx = input.fx or 0.0, fy = input.fy or 0.0, yaw = input.yaw or 0.0,
            look = input.look or 0.0, ends = U.now() + (input.time or 1.0) * 1000.0 }
    end
    return P.devState()
end

function P.devPose(x, y, z, heading, gimbal)
    local s = DC.session
    if not DC.piloting or not s or not DoesEntityExist(s.entity) then return P.devState() end
    local drone = s.entity
    SetEntityCoordsNoOffset(drone, U.F(x), U.F(y), U.F(z), false, false, false)
    SetEntityRotation(drone, 0.0, 0.0, U.F(heading), 2, true)
    SetEntityVelocity(drone, 0.0, 0.0, 0.0)
    f.vel, f.heading, f.body, f.pitch, f.roll = vector3(0.0, 0.0, 0.0), U.F(heading), U.F(heading), 0.0, 0.0
    if gimbal then f.gimbal = U.F(gimbal) end
    return P.devState()
end

function P.stop(reason)
    if not DC.piloting or (reason == 'leave' and f.falling) then return end
    DC.piloting = false
    local s = DC.session
    local drone = s and s.entity
    pcall(H.close)
    pcall(hideLegend)
    pcall(U.hud, true)
    if f.cam then
        pcall(RenderScriptCams, false, reason ~= 'stopped', 350, true, true)
        pcall(DestroyCam, f.cam, false)
        f.cam = nil
    end
    pcall(ClearFocus)
    pcall(SetNightvision, false)
    pcall(SetSeethrough, false)
    pcall(ClearTimecycleModifier)
    f.fuzz = 0.0
    local ped = PlayerPedId()
    pcall(removeTablet)
    pcall(StopAnimTask, ped, C.pilot.anim.dict, C.pilot.anim.name, 2.0)
    pcall(SetPedCanSwitchWeapon, ped, true)
    pcall(RemoveAnimDict, C.pilot.anim.dict)
    f.acquiring = nil
    local c = f.cine
    f.cine, f.pendingLeave = nil, false
    if c then
        if f.lock and f.lock.self then f.lock = nil end
        if s and drone and DoesEntityExist(drone) then keepFollow(c, drone) end
        if c.speed and f.mode == c.speed then f.mode = c.mode end
    end
    if f.acro then f.gimbal = f.acro.gimbal end
    if f.motors and (f.acro or f.recover or f.glide) and drone and DoesEntityExist(drone) then
        pcall(SetEntityAngularVelocity, drone, 0.0, 0.0, 0.0)
        pcall(SetEntityRotation, drone, 0.0, 0.0, U.F(f.body), 2, true)
    end
    f.acro, f.recover, f.glide, f.hardCam = nil, nil, nil, false
    if s then s.light = f.light end
    local tracking = f.lock and f.motors and not f.ending and DETACH[reason] and f.agl >= 0.4 and s and s.state ~= 'crashed'
        and drone and DoesEntityExist(drone) and not downed(ped)
    if not tracking then f.lock = nil end

    if reason == 'stopped' or not s or not drone or not DoesEntityExist(drone) then return end
    if tracking then
        s.state = 'unattended'
        leaving(s, false)
        track(s, drone)
        return
    end
    if f.falling and s.state ~= 'crashed' then
        s.state = 'unattended'
        leaving(s, false)
        Autopilot.fall(drone)
        return
    end
    if s.state ~= 'crashed' and f.motors then
        local action = C.flight.leave
        if reason == 'lost' then action = 'hover'
        elseif reason ~= 'control' and f.rth then action = 'return'
        elseif reason ~= 'control' and f.landing then action = 'land' end
        if f.agl < 0.4 then
            land(drone)
        elseif action == 'hover' then
            hover(s, drone)
            return
        else
            s.state = 'unattended'
            Autopilot.unattended(action, f.body)
        end
    end
    leaving(s, false)
end

function P.motors() return f.motors end
function P.launching() return tossing end
function P.tracking() return f.detached ~= nil end
function P.beam() if f.detached then return f.lightPitch, f.body end end

function P.raceHold(on)
    local s = DC.session
    if not on then
        if f.raceHold and s and DoesEntityExist(s.entity) and f.motors then FreezeEntityPosition(s.entity, false) end
        f.raceHold = nil
        return true
    end
    if not s or not s.race or not DC.piloting then return false end
    f.raceHold = true
    return true
end

function P.raceRespawn(x, y, z, h)
    local s = DC.session
    if not s or not s.race or not DC.piloting or not DoesEntityExist(s.entity) then return false end
    local drone = s.entity
    if not NetworkHasControlOfEntity(drone) then NetworkRequestControlOfEntity(drone) end
    f.acro, f.glide, f.recover, f.takeoff, f.landing, f.rth = nil, nil, nil, nil, false, nil
    f.falling, f.lock, f.lens, f.landTimer, f.boost, f.braking, f.lostSince, f.lostActed = nil, nil, nil, 0.0, false, false, nil, false
    SetVehicleFixed(drone)
    SetVehicleDeformationFixed(drone)
    SetEntityHealth(drone, 1000)
    SetHeliMainRotorHealth(drone, 1000.0)
    SetHeliTailRotorHealth(drone, 1000.0)
    SetVehicleUndriveable(drone, false)
    U.hardenDrone(drone)
    SetEntityCoordsNoOffset(drone, U.F(x), U.F(y), U.F(z), false, false, false)
    SetEntityRotation(drone, 0.0, 0.0, U.F(h), 2, true)
    SetEntityVelocity(drone, 0.0, 0.0, 0.0)
    SetEntityAngularVelocity(drone, 0.0, 0.0, 0.0)
    SetVehicleBodyHealth(drone, U.F(s.conf.health))
    SetVehicleEngineHealth(drone, 1000.0)
    SetVehiclePetrolTankHealth(drone, 1000.0)
    f.vel, f.heading, f.body, f.pitch, f.roll = vector3(0.0, 0.0, 0.0), U.F(h), U.F(h), 0.0, 0.0
    f.health = GetVehicleBodyHealth(drone) + GetVehicleEngineHealth(drone)
    f.ending, f.status = nil, 'flying'
    s.state = 'flying'
    motorsOn(drone, true)
    holdRaceAcro(drone)
    present(U.now(), true)
    CreateThread(function() U.call('respawn', {}) end)
    return true
end

function P.raceGo()
    local s = DC.session
    f.raceHold = nil
    if not s or not s.race or not DC.piloting or not DoesEntityExist(s.entity) or f.ending then return false end
    local drone = s.entity
    f.takeoff, f.landing, f.rth, f.falling, f.landTimer = nil, false, nil, nil, 0.0
    if not f.motors then
        motorsOn(drone, true)
        TriggerServerEvent(RESOURCE .. ':pilot', { on = true, flying = true })
        U.sound('start')
    end
    FreezeEntityPosition(drone, false)
    s.state, f.status = 'flying', 'flying'
    holdRaceAcro(drone)
    present(U.now(), true)
    return true
end
