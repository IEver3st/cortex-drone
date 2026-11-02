DroneSwap = { active = false }
local S = DroneSwap
local C, D, U, R = Config, DroneDomain, DroneUtil, DroneRig
local DC = DroneClient
local RESOURCE = GetCurrentResourceName()
local MODEL = joaat(C.model)
local PACK = joaat('cxdrone_pack')
local EXTRA = 1
local HALF = 0.0176
local ZERO = vector3(0.0, 0.0, 0.0)
local SEAT = vector3(0.0, -0.0487, -0.0163)
local POP = vector3(0.0, -0.01, 0.006)
local SLID = vector3(0.0, -0.05, 0.024)
local ABOVE = vector3(0.0, -0.11, 0.05)
local OUT = { POP, SLID, ABOVE }
local IN = { ABOVE, SLID, ZERO }
local LEDS = { vector3(0.0, 0.0102, 0.0172), vector3(0.0, 0.0174, 0.0177), vector3(0.0, 0.0248, 0.0182), vector3(0.0, 0.032, 0.0186) }
local GLOW = { 70, 255, 140 }
local RIGHT, LEFT = 28422, 60309
local VIEW, FOCUS, FOV = vector3(0.16, -0.62, 0.30), vector3(0.0, -0.04, -0.02), 42.0
local LENS_GAP = 0.06
local LOOK = 25
local LOOK_MOUSE, LOOK_PAD = 10.0, 140.0
local PITCH = { 6.0, 80.0 }
local CLAMPS = { vector3(-0.0325, 0.0362, -0.0037), vector3(0.0325, 0.0362, -0.0037) }
local CLAMP_REACH = 0.011
local CLAMP_MIN = 0.018
local CLAMP_HIT = 1.7
local PAPER, INK = { 240, 240, 233 }, { 15, 16, 18 }
local CUE_TXD = 'cxdrone_cue'
local RINGS = { 0.025, 0.035, 0.05, 0.07, 0.1, 0.14, 0.2, 0.28 }
local RING_FILL, DOT_FILL = 0.72, 0.94
local STROKE = 0.0014
local PING_MS = 1700.0
local HOVER_RATE = 14.0
local HEAD = 31086
local CLEAR = 0.5
local BLEND_MS = 800
local BLOCKED = { 1, 2, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 45, 47, 58, 140, 141, 142, 143, 199, 200, 201, 205, 206, 257, 263, 264 }
local SQUEEZE_MS = 220.0
local DRAG = 0.07
local MAGNET, SNAP, UNSNAP = 0.14, 0.05, 0.08
local FOLLOW = 30.0
local SEAT_TIME = 0.42
local SEATED = 1.9
local GROUND = { 0.22, 0.6 }
local CARRY = 0.7
local SPACING = 0.11
local DROP_STEP = 0.03
local MARGIN = 0.06
local PAD_SPEED = 0.55
local SPRITE = { point = 1, open = 3, grab = 4 }
local STOP = setmetatable({}, { __tostring = function() return 'swap stopped' end })
local REPAIR_WAIT = 5000
local jobs, watching, standins, nets = {}, {}, {}, {}

CreateThread(function()
    local txd = CreateRuntimeTxd(CUE_TXD)
    for index = 1, #RINGS do CreateRuntimeTextureFromImage(txd, 'ring' .. index, ('assets/cue/ring%d.png'):format(index)) end
    CreateRuntimeTextureFromImage(txd, 'dot', 'assets/cue/dot.png')
end)

local function level(charge)
    return math.max(0, math.min(4, math.ceil((tonumber(charge) or 0) / 25.0 - 0.001)))
end

local function extra(drone, on)
    if not DoesExtraExist(drone, EXTRA) or IsVehicleExtraTurnedOn(drone, EXTRA) == on then return end
    local body, engine, tank = GetVehicleBodyHealth(drone), GetVehicleEngineHealth(drone), GetVehiclePetrolTankHealth(drone)
    SetVehicleExtra(drone, EXTRA, not on)
    SetVehicleBodyHealth(drone, body)
    SetVehicleEngineHealth(drone, engine)
    SetVehiclePetrolTankHealth(drone, tank)
end

local function pack(pos, rot, drone)
    if not HasModelLoaded(PACK) then return nil end
    local entity = CreateVehicle(PACK, pos.x, pos.y, pos.z, 0.0, false, false)
    if entity == 0 then return nil end
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetVehicleEngineOn(entity, false, true, true)
    SetVehicleDoorsLocked(entity, 2)
    if DoesExtraExist(entity, EXTRA) and not IsVehicleExtraTurnedOn(entity, EXTRA) then SetVehicleExtra(entity, EXTRA, false) end
    if drone and DoesEntityExist(drone) then
        SetVehicleColours(entity, GetVehicleColours(drone))
        SetVehicleExtraColours(entity, GetVehicleExtraColours(drone))
        SetVehicleDirtLevel(entity, GetVehicleDirtLevel(drone))
    end
    R.place(entity, pos, rot or R.IDENTITY)
    return entity
end

local function guard()
    if S.guarding then return end
    S.guarding = true
    CreateThread(function()
        while next(standins) do
            for drone, prop in pairs(standins) do
                if DC.stopped or not DoesEntityExist(drone) or not DoesEntityExist(prop) or IsVehicleExtraTurnedOn(drone, EXTRA) then
                    U.deleteEntity(prop)
                    standins[drone] = nil
                else
                    local pos, rot = R.pose(drone)
                    R.place(prop, R.compose(pos, rot, SEAT))
                end
            end
            Wait(0)
        end
        S.guarding = false
    end)
end

local function refit(drone, prop)
    if not DoesExtraExist(drone, EXTRA) then return true end
    local body, engine, tank = GetVehicleBodyHealth(drone), GetVehicleEngineHealth(drone), GetVehiclePetrolTankHealth(drone)
    local health, main, tail = GetEntityHealth(drone), GetHeliMainRotorHealth(drone), GetHeliTailRotorHealth(drone)
    SetVehicleExtra(drone, EXTRA, false)
    SetVehicleFixed(drone)
    SetVehicleBodyHealth(drone, body)
    SetVehicleEngineHealth(drone, engine)
    SetVehiclePetrolTankHealth(drone, tank)
    SetEntityHealth(drone, health)
    SetHeliMainRotorHealth(drone, main)
    SetHeliTailRotorHealth(drone, tail)
    if IsVehicleExtraTurnedOn(drone, EXTRA) then
        if prop then U.deleteEntity(prop) end
        return true
    end
    print(('^3[%s] battery extra stayed off after refit (networked=%s control=%s frozen=%s body=%.0f)^0'):format(RESOURCE,
        tostring(NetworkGetEntityIsNetworked(drone)), tostring(NetworkHasControlOfEntity(drone)), tostring(IsEntityPositionFrozen(drone)), body))
    prop = prop or pack(GetEntityCoords(drone), nil, drone)
    if prop then
        standins[drone] = prop
        guard()
    end
    return false
end

local function sound(job, name)
    local entry = C.sounds[name]
    if not entry then return end
    if job.owner then PlaySoundFrontend(-1, entry.name, entry.set, true); return end
    local at = GetEntityCoords(job.drone)
    PlaySoundFromCoord(-1, entry.name, at.x, at.y, at.z, entry.set, false, 8.0, false)
end

local function seat(job, offset)
    local pos, rot = R.pose(job.drone)
    return R.compose(pos, rot, SEAT + offset)
end

local function along(path, p)
    local n = #path - 1
    p = math.max(0.0, math.min(n, p))
    local i = math.min(n, math.floor(p) + 1)
    return R.lerp(path[i], path[i + 1], p - (i - 1))
end

local function lights(job)
    local show = job.show
    if not show then return end
    local t = U.now() - show.start
    if t > show.length then job.show = nil; return end
    local count = show.count
    if show.fill then count = math.min(count, t // 110 + 1) end
    local pos, rot = seat(job, ZERO)
    for i = 1, count do
        if not (show.blink and i == count and (t // 250) % 2 == 1) then
            local at = pos + U.qrot(rot, LEDS[i])
            DrawMarker(28, at.x, at.y, at.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0016, 0.0016, 0.0016, GLOW[1], GLOW[2], GLOW[3], 235,
                false, false, 2, false, nil, nil, false)
            DrawLightWithRange(at.x, at.y, at.z + 0.006, GLOW[1], GLOW[2], GLOW[3], 0.06, 1.2)
        end
    end
end

local function segment(c, a, b)
    local ab = b - a
    local length = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
    local t = length > 0.0 and math.max(0.0, math.min(1.0, ((c.x - a.x) * ab.x + (c.y - a.y) * ab.y + (c.z - a.z) * ab.z) / length)) or 0.0
    return #(c - (a + ab * t))
end

local function veil(job)
    local ped = job.ped
    local feet = GetEntityCoords(ped) - vector3(0.0, 0.0, 1.0)
    local top = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0) + vector3(0.0, 0.0, 0.15)
    if segment(GetFinalRenderedCamCoord(), feet, top) >= CLEAR then return end
    SetEntityLocallyInvisible(ped)
    for _, object in ipairs(job.attached) do
        if DoesEntityExist(object) then SetEntityLocallyInvisible(object) end
    end
end

local function shield(at, want, drone)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(at.x, at.y, at.z, want.x, want.y, want.z, 1 | 2 | 16, drone, 7)
    local _, hit, coords = GetShapeTestResult(probe)
    if hit == 1 or hit == true then
        local back = at - coords
        local length = #back
        if length > LENS_GAP * 2.0 then return coords + back * (LENS_GAP / length) end
    end
    return want
end

local function look(job)
    local o = job.orbit
    job.looking = o ~= nil and not job.leaving and IsDisabledControlPressed(0, LOOK)
    if not job.looking then return end
    local mouse = IsUsingKeyboard(0)
    local k = mouse and LOOK_MOUSE or LOOK_PAD * math.min(GetFrameTime(), 0.05)
    local dx = mouse and GetDisabledControlUnboundNormal(0, 1) or GetDisabledControlNormal(0, 1)
    local dy = mouse and GetDisabledControlUnboundNormal(0, 2) or GetDisabledControlNormal(0, 2)
    if dx == 0.0 and dy == 0.0 then return end
    o.yaw = (o.yaw - dx * k) % 360.0
    o.pitch = math.max(PITCH[1], math.min(PITCH[2], o.pitch + dy * k))
    local at = seat(job, FOCUS)
    local p, h = math.rad(o.pitch), math.rad(o.yaw)
    local from = shield(at, at + vector3(math.cos(h) * math.cos(p), math.sin(h) * math.cos(p), math.sin(p)) * o.reach, job.drone)
    SetCamCoord(job.cam, from.x, from.y, from.z)
    PointCamAtCoord(job.cam, at.x, at.y, at.z)
end

local function frame(job, latched)
    local ped = job.ped
    if job.owner then
        for _, control in ipairs(BLOCKED) do DisableControlAction(0, control, true) end
        DisableControlAction(0, job.cancel, true)
        if job.cam then look(job) else job.looking = false end
        if job.attached and (job.cam or U.now() < job.veilUntil) then veil(job) end
        if IsDisabledControlJustPressed(0, job.cancel) then job.stop = job.stop or 'cancel' end
        if IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, true) or IsEntityInWater(ped)
            or (job.origin and #(GetEntityCoords(ped) - job.origin) > 1.2) then
            job.stop = job.stop or 'interrupted'
        end
    elseif not DoesEntityExist(ped) then
        job.stop = job.stop or 'gone'
    end
    if DC.stopped then job.stop = job.stop or 'stopped' end
    if not DoesEntityExist(job.drone) then job.stop = job.stop or 'gone' end
    if job.stop and not latched then error(STOP, 0) end
    SetEntityNoCollisionEntity(ped, job.drone, true)
    SetHeliBladesSpeed(job.drone, 0.0)
    lights(job)
end

local function hold(job, seconds, fn)
    local start, length = U.now(), math.max(1.0, seconds * 1000.0)
    while true do
        local t = math.min(1.0, (U.now() - start) / length)
        if fn then fn(t) end
        frame(job)
        if t >= 1.0 then return end
        Wait(0)
    end
end

local function await(job, stages)
    while not stages[job.remote] do
        frame(job)
        Wait(0)
    end
end

local function anim(job, which, flag)
    local a = C.swap.anim[which]
    local length = job.lengths[which]
    if job.owner and length > 0.0 then
        TaskPlayAnim(job.ped, a.dict, a.name, 4.0, -4.0, -1, flag, 0.0, false, false, false)
    end
    return length > 0.0 and length or 1.5
end

local function hand(job, bone, ahead)
    local pos = GetPedBoneCoords(job.ped, bone, 0.0, 0.0, 0.0)
    local yaw = U.qyaw(GetEntityHeading(job.ped))
    return pos + U.qrot(yaw, ahead), yaw
end

local function spot(job, side)
    local yaw = U.qyaw(job.heading)
    local at = job.home + U.qrot(yaw, vector3(side * 0.3, -0.12, 0.0))
    local ground = R.ground(at.x, at.y, job.floor + 0.3, job.drone) or job.floor
    return vector3(at.x, at.y, ground + HALF), U.qnorm(U.qmul(yaw, U.qyaw(side * -16.0)))
end

local function attachments(ped)
    local list = {}
    for _, object in ipairs(GetGamePool('CObject')) do
        if IsEntityAttachedToEntity(object, ped) then list[#list + 1] = object end
    end
    return list
end

local function lens(job)
    local at = seat(job, FOCUS)
    local want = job.home + U.qrot(U.qyaw(job.heading), VIEW)
    local offset = want - at
    local reach = #offset
    job.orbit = { yaw = math.deg(math.atan(offset.y, offset.x)), pitch = math.deg(math.asin(offset.z / reach)), reach = reach }
    return shield(at, want, job.drone), at
end

local function carry(job, prop, fromPos, fromRot, toPos, toRot, seconds, lift)
    local via = (fromPos + toPos) * 0.5 + vector3(0.0, 0.0, lift)
    hold(job, seconds, function(t)
        local e = R.ease(t)
        R.place(prop, R.curve(fromPos, via, toPos, e), U.qslerp(fromRot, toRot, e))
    end)
end

local function slide(job, prop, from, to, seconds)
    hold(job, seconds, function(t)
        local pos, rot = seat(job, R.lerp(from, to, R.ease(t)))
        R.place(prop, pos, rot)
    end)
end

local function screen(pos)
    local on, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    return on, x, y
end

local function visible(pos)
    local on, x, y = screen(pos)
    return on and x >= MARGIN and x <= 1.0 - MARGIN and y >= MARGIN and y <= 1.0 - MARGIN
end

local function ray(x, y)
    local origin, rot, fov = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2), GetFinalRenderedCamFov()
    local forward = U.rotationToDirection(rot.x, rot.z)
    local yaw = math.rad(rot.z)
    local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
    local up = vector3(right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x)
    local t = math.tan(math.rad(fov) * 0.5)
    return origin, forward + right * ((x * 2.0 - 1.0) * t * GetAspectRatio(false)) + up * ((1.0 - y * 2.0) * t)
end

local function input(job)
    local i = job.input
    local keyboard = IsUsingKeyboard(0)
    i.pad, i.looking = not keyboard, job.looking == true
    if i.looking and i.x then
        i.dx, i.dy, i.settle = 0.0, 0.0, true
    else
        local x, y
        if keyboard then
            x, y = GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
        else
            local dt = math.min(GetFrameTime(), 0.05) * PAD_SPEED
            x = math.max(0.0, math.min(1.0, (i.x or 0.5) + (GetDisabledControlNormal(0, 1) + GetDisabledControlNormal(0, 30)) * dt))
            y = math.max(0.0, math.min(1.0, (i.y or 0.5) + (GetDisabledControlNormal(0, 2) + GetDisabledControlNormal(0, 31)) * dt))
        end
        if i.settle then
            i.dx, i.dy, i.settle = 0.0, 0.0, false
        else
            i.dx, i.dy = x - (i.x or x), y - (i.y or y)
        end
        i.x, i.y = x, y
    end
    local held = IsDisabledControlPressed(0, 24) or IsDisabledControlPressed(0, 237) or (not keyboard and IsDisabledControlPressed(0, 201))
    i.pressed, i.released, i.held = held and not i.held, not held and i.held == true, held
    return i
end

local cursorStyle = SetMouseCursorStyle or SetMouseCursorSprite

local function pointer(i, sprite)
    if not sprite or i.looking then return end
    if not i.pad then
        SetMouseCursorActiveThisFrame()
        cursorStyle(sprite)
        return
    end
    local aspect = GetAspectRatio(false)
    local grabbing = sprite == SPRITE.grab
    DrawRect(i.x, i.y, 0.018 / aspect, 0.018, 12, 14, 16, 200)
    DrawRect(i.x, i.y, 0.011 / aspect, 0.011, grabbing and GLOW[1] or 236, grabbing and GLOW[2] or 238, grabbing and GLOW[3] or 240, 255)
end

local function over(i, pos)
    local on, x, y = screen(pos)
    if not on then return false end
    local _, ex, ey = screen(pos + vector3(0.0, 0.0, 0.05))
    local aspect = GetAspectRatio(false)
    local r = math.max(0.035, math.sqrt(((ex - x) * aspect) ^ 2 + (ey - y) ^ 2))
    local dx, dy = (i.x - x) * aspect, i.y - y
    local gap = dx * dx + dy * dy
    return gap <= r * r, gap
end

local function grip(i, pos)
    local _, x, y = screen(pos)
    return { x = i.x - x, y = i.y - y }
end

local function marker(at)
    local on, x, y = screen(at)
    if not on then return nil end
    local _, ex, ey = screen(at + vector3(0.0, 0.0, CLAMP_REACH))
    return { x = x, y = y, r = math.max(CLAMP_MIN, math.sqrt(((ex - x) * GetAspectRatio(false)) ^ 2 + (ey - y) ^ 2)) }
end

local function clampTargets(pos, rot)
    local eye = GetFinalRenderedCamCoord()
    local aspect = GetAspectRatio(false)
    local shown, fallback = {}, nil
    for _, offset in ipairs(CLAMPS) do
        local at = pos + U.qrot(rot, offset)
        local on, x, y = screen(at)
        if on then
            local normal = U.qrot(rot, vector3(offset.x > 0.0 and 1.0 or -1.0, 0.0, 0.0))
            local to = eye - at
            local _, ex, ey = screen(at + vector3(0.0, 0.0, CLAMP_REACH))
            local target = { x = x, y = y, r = math.max(CLAMP_MIN, math.sqrt(((ex - x) * aspect) ^ 2 + (ey - y) ^ 2)),
                facing = normal.x * to.x + normal.y * to.y + normal.z * to.z }
            if target.facing > 0.0 then shown[#shown + 1] = target end
            if not fallback or target.facing > fallback.facing then fallback = target end
        end
    end
    if #shown == 0 and fallback then shown[1] = fallback end
    return shown
end

local function onClamp(i, target)
    local reach = target.r * CLAMP_HIT
    local dx, dy = (i.x - target.x) * GetAspectRatio(false), i.y - target.y
    return dx * dx + dy * dy <= reach * reach
end

local function ring(x, y, diameter, stroke, colour, alpha, aspect)
    if alpha <= 0 or diameter <= 0.0 then return end
    local want, pick, best = stroke / diameter, 1, math.huge
    for index, ratio in ipairs(RINGS) do
        local miss = math.abs(math.log(ratio / want))
        if miss < best then pick, best = index, miss end
    end
    local size = diameter / RING_FILL
    DrawSprite(CUE_TXD, 'ring' .. pick, x, y, size / aspect, size, 0.0, colour[1], colour[2], colour[3], math.floor(alpha))
end

local function dot(x, y, diameter, colour, alpha, aspect)
    if alpha <= 0 or diameter <= 0.0 then return end
    local size = diameter / DOT_FILL
    DrawSprite(CUE_TXD, 'dot', x, y, size / aspect, size, 0.0, colour[1], colour[2], colour[3], math.floor(alpha))
end

local function cue(target, mix, k, accent)
    local aspect = GetAspectRatio(false)
    local x, y, base = target.x, target.y, target.r * 1.25
    local fade = 1.0 - k
    local colour = {}
    for n = 1, 3 do colour[n] = math.floor(PAPER[n] + (accent[n] - PAPER[n]) * mix) end
    if mix < 1.0 and k <= 0.0 then
        for n = 0, 1 do
            local t = (U.now() / PING_MS + n * 0.5) % 1.0
            local d = base * (0.25 + 1.3 * (1.0 - (1.0 - t) ^ 3))
            local a = 242.0 * (1.0 - t) * (1.0 - mix)
            ring(x, y, d, STROKE * 2.6, INK, a * 0.3, aspect)
            ring(x, y, d, STROKE, PAPER, a, aspect)
        end
    end
    if mix > 0.0 then
        local d = base * (1.0 - 0.8 * k)
        local a = 255.0 * mix * math.max(0.0, 1.0 - k * 1.25)
        ring(x, y, d, STROKE * 2.6, INK, a * 0.35, aspect)
        ring(x, y, d, STROKE, accent, a, aspect)
    end
    local d = target.r * 0.31 * (1.0 + 0.25 * mix) * (1.0 - 0.7 * k)
    dot(x, y, d + 0.002, INK, 150.0 * fade, aspect)
    dot(x, y, d, colour, 255.0 * fade, aspect)
end

local function aim(job, i, height)
    local origin, dir = ray(i.x - job.grip.x, i.y - job.grip.y)
    if dir.z > -0.0001 then return nil end
    local t = (height - origin.z) / dir.z
    if t <= 0.0 then return nil end
    local at = origin + dir * t
    local flat = vector3(at.x - job.home.x, at.y - job.home.y, 0.0)
    if #flat > CARRY then flat = flat * (CARRY / #flat) end
    return vector3(job.home.x + flat.x, job.home.y + flat.y, height)
end

local function drop(job, prop, avoid)
    local pos, rot = GetEntityCoords(prop), U.quaternion(prop)
    local flat = vector3(pos.x - job.home.x, pos.y - job.home.y, 0.0)
    if #flat < 0.001 then flat = U.qrot(U.qyaw(job.heading), vector3(1.0, 0.0, 0.0)) end
    local dir = flat / #flat
    local reach = math.max(GROUND[1], math.min(GROUND[2], #flat))
    local to
    while true do
        local at = vector3(job.home.x, job.home.y, 0.0) + dir * reach
        if avoid then
            local gap = vector3(at.x - avoid.x, at.y - avoid.y, 0.0)
            if #gap < SPACING then
                local away = #gap > 0.001 and gap / #gap or U.qrot(U.qyaw(job.heading), vector3(1.0, 0.0, 0.0))
                at = at + away * (SPACING - #gap)
            end
        end
        local ground = R.ground(at.x, at.y, job.floor + 0.3, job.drone) or job.floor
        to = vector3(at.x, at.y, ground + HALF)
        if reach <= GROUND[1] or visible(to) then break end
        reach = math.max(GROUND[1], reach - DROP_STEP)
    end
    local toRot = U.qyaw(GetEntityHeading(prop))
    carry(job, prop, pos, rot, to, toRot, 0.22, 0.01)
    return to, toRot
end

local function legend(on, keyboard)
    if not (lib and lib.showHelp) then return end
    if on then
        pcall(lib.showHelp, { { label = L('legend.stopSwap'), value = keyboard and 'BACKSPACE' or 'B' } }, { compact = true })
    else
        pcall(lib.hideHelp)
    end
end

local HINTS = {
    clamp = { { 'legend.pressClamps', 'grab' }, { 'legend.lookAround', 'look' }, { 'legend.stopSwap', 'stop' } },
    out = { { 'legend.dragOut', 'grab' }, { 'legend.lookAround', 'look' }, { 'legend.stopSwap', 'stop' } },
    set = { { 'legend.setDown', 'grab' }, { 'legend.lookAround', 'look' }, { 'legend.stopSwap', 'stop' } },
    pick = { { 'legend.pickNew', 'grab' }, { 'legend.lookAround', 'look' }, { 'legend.stopSwap', 'stop' } },
    seat = { { 'legend.slideIn', 'grab' }, { 'legend.lookAround', 'look' }, { 'legend.stopSwap', 'stop' } },
    lock = { { 'legend.clickIn', 'grab' }, { 'legend.lookAround', 'look' }, { 'legend.stopSwap', 'stop' } },
}

local function keyLabel(kind, pad)
    if kind == 'grab' then return pad and 'RT' or L('key.mouse') end
    if kind == 'look' then return pad and 'LT' or 'RMB' end
    return pad and 'B' or 'BACKSPACE'
end

local function hint(job, name)
    local pad = job.input.pad == true
    if not job.owner or (job.hint == name and job.hintPad == pad) or not (lib and lib.showHelp) then return end
    job.hint, job.hintPad = name, pad
    local rows = {}
    for _, row in ipairs(HINTS[name]) do rows[#rows + 1] = { label = L(row[1]), value = keyLabel(row[2], pad) } end
    pcall(lib.showHelp, rows, { compact = true })
end

local function stage(job, name)
    job.stage = name
    if job.owner then TriggerServerEvent(RESOURCE .. ':swapstage', { stage = name }) end
end

local function unseat(job, old)
    if job.unseated then return end
    job.unseated = true
    SetEntityVisible(old, true, false)
    extra(job.drone, false)
end

local function pullOut(job, old)
    local mode, p, squeeze, pressed, popped, chained, mix = 'clamp', 0.0, 0.0, false, false, false, 0.0
    local accent = { U.accent() }
    job.stage = 'release'
    while true do
        local i = input(job)
        local sprite
        if i.released then chained = false end
        if mode == 'clamp' then
            if pressed and not popped then
                squeeze = math.min(1.0, squeeze + GetFrameTime() * 1000.0 / SQUEEZE_MS)
                if squeeze >= 1.0 then popped = true; sound(job, 'release') end
            end
            local pos, rot = seat(job, R.lerp(ZERO, POP, R.ease(squeeze)))
            R.place(old, pos, rot)
            if not pressed then
                local targets, hovering = clampTargets(pos, rot), false
                for _, target in ipairs(targets) do hovering = hovering or onClamp(i, target) end
                mix = mix + ((hovering and 1.0 or 0.0) - mix) * math.min(1.0, GetFrameTime() * HOVER_RATE)
                for _, target in ipairs(targets) do cue(target, mix, 0.0, accent) end
                job.cues = targets
                sprite = hovering and SPRITE.open or SPRITE.point
                if hovering and i.pressed then
                    pressed, chained = true, true
                    unseat(job, old)
                    sound(job, 'latch')
                end
            elseif not popped then
                for _, target in ipairs(clampTargets(pos, rot)) do cue(target, 1.0, R.ease(squeeze), accent) end
                sprite = SPRITE.open
            else
                job.cues = nil
                local hovering = over(i, pos)
                sprite = hovering and SPRITE.open or SPRITE.point
                if (hovering and i.pressed) or (chained and i.held) then mode = 'pull' end
            end
            hint(job, popped and 'out' or 'clamp')
        elseif mode == 'pull' or mode == 'rest' then
            if mode == 'pull' then
                p = math.max(0.0, math.min(2.0, p + i.dy / DRAG))
                sprite = SPRITE.grab
                if i.released then
                    if p < 1.0 then
                        slide(job, old, along(OUT, p), POP, 0.12)
                        mode, p = 'clamp', 0.0
                    else
                        mode = 'rest'
                    end
                elseif p >= 2.0 then
                    local pos = seat(job, ABOVE)
                    job.grip = grip(i, pos)
                    mode = 'carry'
                end
            else
                local pos = seat(job, along(OUT, p))
                local hovering = over(i, pos)
                sprite = hovering and SPRITE.open or SPRITE.point
                if hovering and i.pressed then mode = 'pull' end
            end
            if mode == 'pull' or mode == 'rest' then R.place(old, seat(job, along(OUT, p))) end
            hint(job, 'out')
        end
        if mode == 'carry' then
            sprite = SPRITE.grab
            local _, rot = seat(job, ABOVE)
            local at = aim(job, i, job.carry)
            if at then R.place(old, at, rot) end
            hint(job, 'set')
            if i.released then
                job.oldPos, job.oldRot = drop(job, old, job.freshPos)
                return
            end
        end
        pointer(i, sprite)
        frame(job)
        Wait(0)
    end
end

local function seatIn(job, fresh, fromPos, fromRot, p)
    hold(job, 0.1 + SEAT_TIME * (2.0 - p) / 2.0, function(t)
        local railPos, railRot = seat(job, along(IN, p + (2.0 - p) * R.ease(t)))
        local blend = R.ease(math.min(1.0, t * 3.0))
        R.place(fresh, R.lerp(fromPos, railPos, blend), U.qslerp(fromRot, railRot, blend))
    end)
    R.place(fresh, seat(job, ZERO))
end

local function slotIn(job, fresh)
    local mode, p, locked, mix = 'ground', 0.0, false, 0.0
    local accent = { U.accent() }
    local curPos, curRot = job.freshPos, job.freshRot
    while true do
        local i = input(job)
        local sprite
        local dt = math.min(GetFrameTime(), 0.05)
        local abovePos, aboveRot = seat(job, ABOVE)
        if mode == 'ground' then
            local hovering = over(i, job.freshPos)
            sprite = hovering and SPRITE.open or SPRITE.point
            if hovering and i.pressed then
                job.grip = grip(i, job.freshPos)
                curPos, curRot = job.freshPos, job.freshRot
                mode, p, locked, mix = 'carry', 0.0, false, 0.0
            end
            hint(job, 'pick')
        else
            sprite = SPRITE.grab
            local at = aim(job, i, job.carry)
            local wantPos, wantRot = curPos, curRot
            local near = false
            if at then
                local reach = #(at.xy - abovePos.xy)
                if locked and p <= 0.0 and reach > UNSNAP then
                    locked = false
                elseif not locked and reach < SNAP then
                    locked, p = true, 0.0
                    sound(job, 'toggle')
                end
                near = reach < MAGNET
                if locked then
                    p = math.max(0.0, math.min(2.0, p - i.dy / DRAG))
                    wantPos, wantRot = seat(job, along(IN, p))
                else
                    local pull = R.ease(math.max(0.0, math.min(1.0, (MAGNET - reach) / (MAGNET - SNAP))))
                    wantPos = R.lerp(at, abovePos, pull * 0.8)
                    wantRot = U.qslerp(job.freshRot, aboveRot, R.ease(1.0 - math.min(1.0, reach / 0.35)))
                end
            end
            local follow = 1.0 - math.exp(-dt * FOLLOW)
            curPos, curRot = R.lerp(curPos, wantPos, follow), U.qslerp(curRot, wantRot, follow)
            R.place(fresh, curPos, curRot)
            mix = mix + ((near and 1.0 or 0.0) - mix) * math.min(1.0, dt * HOVER_RATE)
            if not locked then
                local target = marker(seat(job, ZERO))
                if target then cue(target, mix, 0.0, accent) end
            end
            if locked and (p >= SEATED or i.released) then
                seatIn(job, fresh, curPos, curRot, p)
                return
            elseif i.released then
                job.freshPos, job.freshRot = drop(job, fresh, job.oldPos)
                mode = 'ground'
            end
            hint(job, locked and 'lock' or 'seat')
        end
        pointer(i, sprite)
        frame(job)
        Wait(0)
    end
end

local function commit(job)
    local answer
    CreateThread(function() answer = U.call('spare', { item = job.item, slot = job.slot }) or false end)
    local deadline = U.now() + 15000
    while answer == nil do
        if U.now() > deadline then answer = false end
        frame(job, true)
        Wait(0)
    end
    if not answer or not answer.ok then
        job.failed = answer or nil
        job.stop = 'failed'
        error(STOP, 0)
    end
    job.committed = answer.data or {}
    local data = job.committed
    if DC.session and data.kind == DC.session.kind then
        DC.session.battery = D.finite(data.charge) and data.charge or 100.0
        DC.session.capacity = D.finite(data.capacity) and data.capacity or 1.0
    end
    if job.stop then error(STOP, 0) end
end

local function releaseOld(job, rightPos, rightRot)
    local seatPos, seatRot = seat(job, ZERO)
    local old = pack(seatPos, seatRot, job.drone)
    if not old then job.stop = 'model'; error(STOP, 0) end
    job.props.old = old
    if job.owner then
        SetEntityVisible(old, false, false)
        pullOut(job, old)
        stage(job, 'out')
        return old
    end
    unseat(job, old)
    await(job, { out = true, ['in'] = true })
    sound(job, 'release')
    slide(job, old, ZERO, POP, 0.15)
    hold(job, 0.15)
    slide(job, old, POP, SLID, 0.6)
    local pos, rot = seat(job, SLID)
    carry(job, old, pos, rot, rightPos, rightRot, 1.1, 0.14)
    job.oldPos, job.oldRot = rightPos, rightRot
    return old
end

local function insertFresh(job, fresh)
    if job.owner then
        slotIn(job, fresh)
    else
        await(job, { ['in'] = true })
        local pos, rot = seat(job, ABOVE)
        carry(job, fresh, job.freshPos, job.freshRot, pos, rot, 1.1, 0.12)
        slide(job, fresh, ABOVE, SLID, 0.35)
        slide(job, fresh, SLID, ZERO, 0.45)
    end
    sound(job, 'latch')
    if job.owner then
        job.hint = nil
        legend(true, not job.input.pad)
        commit(job)
        stage(job, 'in')
    end
    job.props.fresh = nil
    refit(job.drone, fresh)
    job.unseated, job.repaired = false, true
end

local function perform(job)
    local ped = job.ped
    local fresh = pack(GetEntityCoords(ped), job.yaw, job.drone)
    if not fresh then job.stop = 'model'; error(STOP, 0) end
    job.props.fresh = fresh
    local leftPos, leftRot = spot(job, -1.0)
    local rightPos, rightRot = spot(job, 1.0)
    job.freshPos, job.freshRot = leftPos, leftRot

    job.stage = 'enter'
    local length = anim(job, 'enter', 2)
    hold(job, length, function(t)
        local k = R.ease(R.span(t, 0.45, 0.9))
        if job.bench then
            local from, yaw = hand(job, RIGHT, vector3(0.0, 0.12, -0.03))
            R.place(job.drone, R.lerp(from, job.home, k), U.qslerp(yaw, job.yaw, k))
        end
        local from, yaw = hand(job, LEFT, vector3(0.0, 0.04, 0.0))
        R.place(fresh, R.lerp(from, leftPos, k), U.qslerp(yaw, leftRot, k))
    end)
    anim(job, 'base', 1)
    job.carry = (seat(job, ABOVE)).z
    if job.owner and C.swap.camera then
        local from, at = lens(job)
        job.cam = R.camera(from, at, FOV, BLEND_MS)
        job.attached, job.veilUntil = attachments(ped), 0
    end

    job.stage = 'inspect'
    hold(job, 0.5)
    sound(job, 'led')
    job.show = { start = U.now(), length = 2400, count = level(job.charge), blink = (job.charge or 0) < 12.5 }
    hold(job, 2.6)

    local old = releaseOld(job, rightPos, rightRot)
    hold(job, 0.25)

    job.stage = 'insert'
    insertFresh(job, fresh)

    job.stage = 'lights'
    hold(job, 0.5)
    sound(job, 'led')
    job.show = { start = U.now(), length = 2600, count = math.max(1, level(job.fresh)), fill = true }
    hold(job, 2.8)

    job.leaving = true
    job.stage = 'exit'
    if job.cam then R.release(job.cam, BLEND_MS); job.cam = nil end
    job.veilUntil = U.now() + BLEND_MS
    local home, homeRot = GetEntityCoords(job.drone), U.quaternion(job.drone)
    local oldPos, oldRot = job.oldPos or rightPos, job.oldRot or rightRot
    length = anim(job, 'exit', 0)
    hold(job, length, function(t)
        local k = R.ease(R.span(t, 0.1, 0.5))
        if job.bench then
            local to, yaw = hand(job, RIGHT, vector3(0.0, 0.12, -0.03))
            R.place(job.drone, R.lerp(home, to, k), U.qslerp(homeRot, yaw, k))
        end
        local to, yaw = hand(job, LEFT, vector3(0.0, 0.04, 0.0))
        R.place(old, R.lerp(oldPos, to, k), U.qslerp(oldRot, yaw, k))
    end)
end

local function cleanup(job)
    if job.clean then return end
    job.clean = true
    if job.cam then R.release(job.cam, job.stop and 0 or BLEND_MS); job.cam = nil end
    jobs[job] = nil
    if S.job == job then S.job = nil end
    for _, prop in pairs(job.props) do U.deleteEntity(prop) end
    job.props = {}
    if job.bench then
        U.deleteEntity(job.drone)
    elseif job.unseated and job.drone and DoesEntityExist(job.drone) then
        if job.stop == 'stopped' then
            if NetworkHasControlOfEntity(job.drone) then extra(job.drone, true) end
        else
            if job.owner then U.control(job.drone, 500) end
            refit(job.drone)
            job.repaired = true
        end
    end
    local a = C.swap.anim
    for _, which in ipairs({ 'enter', 'base', 'exit' }) do
        if job.owner then StopAnimTask(job.ped, a[which].dict, a[which].name, 2.0) end
        RemoveAnimDict(a[which].dict)
    end
    SetModelAsNoLongerNeeded(PACK)
end

local function run(job)
    jobs[job] = true
    if job.owner then S.job = job end
    local done, err = pcall(perform, job)
    if not done and err ~= STOP then print(('^1[%s] battery swap failed: %s^0'):format(RESOURCE, tostring(err))) end
    cleanup(job)
    return done
end

local function prepare(job)
    local a = C.swap.anim
    job.lengths = {}
    for _, which in ipairs({ 'enter', 'base', 'exit' }) do
        job.lengths[which] = U.loadAnim(a[which].dict, 3000) and GetAnimDuration(a[which].dict, a[which].name) or 0.0
    end
    return U.loadModel(PACK, 5000) ~= nil and U.loadModel(MODEL, 5000) ~= nil
end

local function place(job, ped)
    local origin = GetEntityCoords(ped)
    job.heading = GetEntityHeading(ped)
    job.yaw = U.qyaw(job.heading)
    local ahead = origin + U.qrot(job.yaw, vector3(0.0, C.swap.kneel, 0.0))
    local below = R.ground(origin.x, origin.y, origin.z - 0.5, ped)
    local ground = R.ground(ahead.x, ahead.y, origin.z - 0.5, ped)
    if not below or not ground or math.abs(ground - below) > 0.4 then return false end
    local probe = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, ahead.x, ahead.y, ground + 0.25, 1 | 16, ped, 7)
    local _, hit = GetShapeTestResult(probe)
    if hit == 1 or hit == true then return false end
    job.floor = ground
    job.home = vector3(ahead.x, ahead.y, ground + Autopilot.restOf(MODEL))
    return true
end

local function bench(job, kind)
    local drone = CreateVehicle(MODEL, job.home.x, job.home.y, job.home.z - 5.0, job.heading, false, false)
    if drone == 0 then return false end
    SetEntityCollision(drone, false, false)
    FreezeEntityPosition(drone, true)
    SetEntityInvincible(drone, true)
    SetVehicleColours(drone, kind.colours[1], kind.colours[2])
    SetVehicleEngineOn(drone, false, true, true)
    SetVehicleDoorsLocked(drone, 2)
    SetVehicleNumberPlateText(drone, 'DRONE')
    extra(drone, true)
    R.place(drone, job.home, job.yaw)
    job.drone, job.bench = drone, true
    return true
end

local function landed(job, drone)
    local pos = GetEntityCoords(drone)
    job.drone, job.bench = drone, false
    job.heading = GetEntityHeading(drone)
    job.yaw = U.qyaw(job.heading)
    job.home = pos
    local rest = Autopilot.rest(drone)
    job.floor = R.ground(pos.x, pos.y, pos.z, drone) or (pos.z - rest)
end

local function approach(job)
    local yaw = U.qyaw(job.heading)
    local target = job.home + U.qrot(yaw, vector3(0.0, -C.swap.kneel, 0.0))
    TaskGoStraightToCoord(job.ped, target.x, target.y, target.z, 1.0, 5000, job.heading, 0.05)
    local deadline = U.now() + 5000
    while U.now() < deadline do
        frame(job)
        local at = GetEntityCoords(job.ped)
        if #(at.xy - target.xy) < 0.2 and math.abs(U.angleDelta(GetEntityHeading(job.ped), job.heading)) < 20.0 then break end
        Wait(0)
    end
    ClearPedTasks(job.ped)
    SetEntityHeading(job.ped, job.heading)
end

local function attempt(item, slot, ped)
    local result = U.call('swap', { item = item, slot = slot })
    if not result or not result.ok then DC.failure(result); return nil end
    local data = result.data or {}
    local kind = D.type(data.kind)
    local job = { ped = ped, owner = true, item = item, slot = data.slot or slot, charge = data.charge, fresh = tonumber(data.fresh) or 100,
        props = {}, input = {}, cancel = C.controls.keyboard.leave }
    S.pending = job
    local ok, problem = kind and prepare(job), 'notify.unavailable'
    if ok and data.net then
        local drone = U.entity(data.net, 2000)
        ok, problem = drone ~= 0 and U.control(drone, 1500), 'notify.control'
        if ok then landed(job, drone) end
    elseif ok then
        ok, problem = place(job, ped), 'notify.swapRoom'
        if ok then ok, problem = bench(job, kind), 'notify.unavailable' end
    end
    if not ok then job.problem = problem; return job end
    if not DoesExtraExist(job.drone, EXTRA) then job.instant = true; return job end
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    S.held = not LocalPlayer.state.invBusy
    if S.held then LocalPlayer.state:set('invBusy', true, false) end
    S.legend = true
    legend(true, IsUsingKeyboard(0))
    if not job.bench and not pcall(approach, job) then
        ClearPedTasks(ped)
        return job
    end
    job.origin = GetEntityCoords(ped)
    TriggerServerEvent(RESOURCE .. ':swapshow')
    run(job)
    return job
end

function S.start(item, slot)
    if S.active then return true end
    if not C.swap.enabled or not IsModelInCdimage(PACK) then return false end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) or IsEntityInWater(ped) or IsPedRagdoll(ped) or IsPedFalling(ped) then return false end
    S.active = true
    CreateThread(function()
        local done, job = pcall(attempt, item, slot, ped)
        if not done then
            print(('^1[%s] battery swap failed: %s^0'):format(RESOURCE, tostring(job)))
            job = S.pending
        end
        S.pending = nil
        if job then pcall(cleanup, job) end
        if S.legend then legend(false); S.legend = false end
        if S.held then LocalPlayer.state:set('invBusy', false, false); S.held = false end
        TriggerServerEvent(RESOURCE .. ':swapend')
        S.active = false
        if not job then return end
        if job.committed then
            DC.charged(job.committed)
        elseif job.instant then
            DC.instant(item, slot)
        elseif job.problem then
            U.notify(job.problem)
        elseif job.stop == 'failed' then
            DC.failure(job.failed)
        elseif job.stop == 'cancel' or job.stop == 'interrupted' then
            U.notify('notify.swapStopped', 'info')
        elseif not done then
            U.notify('notify.unavailable')
        end
    end)
    return true
end

local function observe(id, info)
    local player = GetPlayerFromServerId(id)
    local ped = player ~= -1 and GetPlayerPed(player) or 0
    if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())) > 40.0 then return end
    local kind = D.type(info.kind)
    if not kind then return end
    local job = { ped = ped, owner = false, token = info.token, remote = info.stage, charge = tonumber(info.charge) or 0,
        fresh = tonumber(info.fresh) or 100, props = {}, input = {} }
    watching[id] = job
    local ready = prepare(job) and type(Player(id).state.cxDroneSwap) == 'table'
    if ready and info.net then
        local drone = U.entity(info.net, 1500)
        ready = drone ~= 0
        if ready then landed(job, drone) end
    elseif ready then
        ready = place(job, ped) and bench(job, kind)
    end
    if ready and not job.stop and DoesExtraExist(job.drone, EXTRA) then
        run(job)
    else
        cleanup(job)
    end
    if watching[id] == job then watching[id] = nil end
end

function S.devState()
    local job = S.job
    if not job or not DoesEntityExist(job.drone) then return { active = S.active } end
    local pos, rot = R.pose(job.drone)
    local inverse = vector4(-rot.x, -rot.y, -rot.z, rot.w)
    local function relative(at) local v = U.qrot(inverse, at - pos); return { x = v.x, y = v.y, z = v.z } end
    local state = { active = S.active, stage = job.stage, hint = job.hint, bench = job.bench, fresh = job.fresh, charge = job.charge,
        unseated = job.unseated == true, cues = job.cues, pointer = job.input and { x = job.input.x, y = job.input.y, pad = job.input.pad },
        drone = { x = pos.x, y = pos.y, z = pos.z, heading = GetEntityHeading(job.drone) },
        ped = relative(GetEntityCoords(job.ped)), right = relative(GetPedBoneCoords(job.ped, RIGHT, 0.0, 0.0, 0.0)),
        left = relative(GetPedBoneCoords(job.ped, LEFT, 0.0, 0.0, 0.0)), extra = IsVehicleExtraTurnedOn(job.drone, EXTRA), props = {} }
    for name, prop in pairs(job.props) do
        if DoesEntityExist(prop) then state.props[name] = relative(GetEntityCoords(prop)) end
    end
    return state
end

local function repairAfter(id, current, net)
    CreateThread(function()
        local deadline = U.now() + REPAIR_WAIT
        while current and watching[id] == current and U.now() < deadline do Wait(50) end
        if (current and current.repaired) or DC.stopped or not NetworkDoesEntityExistWithNetworkId(net) then return end
        local drone = NetworkGetEntityFromNetworkId(net)
        if drone ~= 0 and DoesEntityExist(drone) and DoesExtraExist(drone, EXTRA) then refit(drone) end
    end)
end

AddStateBagChangeHandler('cxDroneSwap', nil, function(bagName, _, value)
    local id = tonumber(bagName:match('^player:(%d+)$'))
    if not id or id == GetPlayerServerId(PlayerId()) then return end
    local current = watching[id]
    if current and type(value) == 'table' and value.token ~= nil and value.token == current.token then
        current.remote = value.stage
        return
    end
    if current and not current.leaving then current.stop = 'ended' end
    local net = nets[id]
    nets[id] = type(value) == 'table' and tonumber(value.net) or nil
    if net and type(value) ~= 'table' then repairAfter(id, current, net) end
    if type(value) == 'table' and type(value.kind) == 'string' then
        CreateThread(function() observe(id, value) end)
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= RESOURCE then return end
    for job in pairs(jobs) do
        job.stop = 'stopped'
        pcall(cleanup, job)
    end
    for drone, prop in pairs(standins) do U.deleteEntity(prop); standins[drone] = nil end
    if S.legend then legend(false) end
    if S.held then LocalPlayer.state:set('invBusy', false, false) end
end)
