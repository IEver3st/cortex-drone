local C, D, B = Config, DroneDomain, Bridge
local RESOURCE = GetCurrentResourceName()
local MODEL = joaat(C.model)
local BEAT_TIMEOUT_MS = 10000
local DEAD_GRACE_MS = 5000
local RATES = { deploy = 1500, beat = 800, presentation = 200, payload = 400, lookup = 900, crash = 500, pickup = 800, leave = 300, session = 1000, pilot = 200, spare = 1500, swap = 1500, swapshow = 300, swapstage = 200, swapend = 300, respawn = 300 }

DroneServer = { sessions = {} }
local S = DroneServer
local sessions = S.sessions
local rates, abandon, pending, chosen, swaps = {}, {}, {}, {}, {}
local races = {}
local SWAP_TIMEOUT_MS = 180000
local CHARGE_REFRESH_MS = 30000

local function ok(data) return { ok = true, data = data } end
local function fail(code) return { ok = false, error = { code = code } } end
S.ok, S.fail = ok, fail

local function now() return GetGameTimer() end

local function limited(src, name)
    local key, at = src .. ':' .. name, now()
    local last = rates[key]
    if last and at - last >= 0 and at - last < (RATES[name] or 300) then return true end
    rates[key] = at
    return false
end

local function callback(name, fn)
    lib.callback.register(RESOURCE .. ':' .. name, function(src, data)
        if limited(src, name) then return fail('RATE_LIMITED') end
        if type(data) ~= 'table' then data = {} end
        local success, result = pcall(fn, src, data)
        if not success then
            print(('^1[%s] %s failed: %s^0'):format(RESOURCE, name, tostring(result)))
            return fail('UNAVAILABLE')
        end
        return result or fail('UNAVAILABLE')
    end)
end
S.callback = callback

local function event(name, fn)
    RegisterNetEvent(RESOURCE .. ':' .. name, function(data)
        local src = source
        if limited(src, name) then return end
        if type(data) ~= 'table' then data = {} end
        local success, err = pcall(fn, src, data)
        if not success then print(('^1[%s] %s failed: %s^0'):format(RESOURCE, name, tostring(err))) end
    end)
end

local function alive(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity)
end

local function distance(a, b)
    return #(GetEntityCoords(a) - GetEntityCoords(b))
end

local pilots = {}

local function setPilot(src, on)
    local value = on == true and C.pilot.othersSeeTablet == true
    if pilots[src] == value then return end
    pilots[src] = value
    Player(src).state:set('cxDronePilot', value, true)
end

local function presentation(session)
    if not alive(session.entity) then return end
    local signature = ('%s|%s|%d|%s'):format(session.kind, tostring(session.light), session.tilt or 0, session.state)
    if session.sent == signature then return end
    session.sent = signature
    Entity(session.entity).state:set('cxDrone', {
        owner = session.src, kind = session.kind, light = session.light == true, tilt = session.tilt or 0,
        state = session.state,
    }, true)
end

local function deleteEntity(entity)
    if alive(entity) then DeleteEntity(entity) end
end

function S.finish(src, reason)
    local session = sessions[src]
    if not session then return end
    sessions[src] = nil
    abandon[src] = nil
    pcall(deleteEntity, session.entity)
    if session.cell then pcall(DroneBattery.store, session.cell, session.battery, true) end
    if GetPlayerName(tostring(src)) then
        pcall(setPilot, src, false)
        TriggerClientEvent(RESOURCE .. ':ended', src, reason)
    end
end

local function carrying(src, kind)
    if not B.itemsRequired() then return true end
    local amount = B.count(src, kind.item)
    if amount == nil then return nil end
    return amount > 0
end

local function fleet(src, owner, only)
    local list, failed = {}, false
    for key, kind in pairs(C.types) do
        if not only or only == key then
            if not B.itemsRequired() then
                list[#list + 1] = { kind = key, cell = DroneBattery.key(owner, key) }
            else
                local found = B.drones(src, kind.item)
                if not found then failed = true end
                for _, entry in ipairs(found or {}) do
                    local fallback = entry.item and DroneBattery.newId(entry.item)
                    local id = entry.metadata[B.ID] or B.tag(src, kind.item, entry.slot, fallback or DroneBattery.newId()) or fallback
                    list[#list + 1] = { kind = key, id = id, slot = entry.slot, cell = DroneBattery.key(owner, key, id) }
                end
            end
        end
    end
    for _, drone in ipairs(list) do drone.charge = DroneBattery.charge(drone.cell) end
    return list, failed
end

local function choose(src, owner, kindKey, wanted)
    local slot = wanted and wanted.kind == kindKey and now() - wanted.at < 15000 and wanted.slot or nil
    local list, failed = fleet(src, owner, kindKey)
    if failed then return nil end
    local best
    for _, drone in ipairs(list) do
        if slot and drone.slot == slot then return drone end
        if not best or drone.charge > best.charge then best = drone end
    end
    if best then return best end
    local cell = DroneBattery.key(owner, kindKey)
    return { kind = kindKey, cell = cell, charge = DroneBattery.charge(cell) }
end

local function held(src, session)
    local kind = D.type(session.kind)
    if not session.id or not B.itemsRequired() then return carrying(src, kind) end
    local list = B.drones(src, kind.item)
    if not list then return nil end
    for _, entry in ipairs(list) do
        if B.identity(entry) == session.id then
            if not entry.metadata[B.ID] then B.tag(src, kind.item, entry.slot, session.id) end
            return true
        end
    end
    return false
end

local function spawn(src, ped, kindKey, kind, at)
    local origin = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local radians = math.rad(heading)
    local x, y, z = origin.x - math.sin(radians) * 1.2, origin.y + math.cos(radians) * 1.2, origin.z
    if at then x, y, z, heading = at.x, at.y, at.z, at.w end
    local entity = CreateVehicleServerSetter(MODEL, 'plane', x, y, z, heading)
    local deadline = now() + 3000
    while not alive(entity) do
        if now() > deadline then return nil end
        Wait(0)
    end
    FreezeEntityPosition(entity, true)
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    SetVehicleDoorsLocked(entity, 2)
    SetVehicleColours(entity, kind.colours[1], kind.colours[2])
    SetVehicleNumberPlateText(entity, 'DRONE')
    return entity
end

local function summary(session)
    return {
        netId = NetworkGetNetworkIdFromEntity(session.entity), kind = session.kind, battery = session.battery, capacity = session.capacity,
        payload = session.payload, state = session.state, light = session.light, race = session.race ~= nil,
    }
end

local function begin(src, kindKey)
    local kind = D.type(kindKey)
    if not kind then return fail('INVALID_REQUEST') end
    local wanted = chosen[src]
    chosen[src] = nil
    local ped, data = B.actor(src)
    if not ped then return fail('UNAVAILABLE') end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return fail('ON_FOOT') end

    local session = sessions[src]
    if session then
        if not alive(session.entity) then
            S.finish(src, 'gone')
        elseif session.state == 'crashed' then
            local marked = abandon[src]
            if marked and now() - marked < 15000 then
                abandon[src] = nil
                S.finish(src, 'abandoned')
                return fail('ABANDONED')
            end
            abandon[src] = now()
            local at = GetEntityCoords(session.entity)
            return { ok = false, error = { code = 'DOWN', at = { x = at.x, y = at.y, z = at.z } } }
        elseif session.kind ~= kindKey then
            return fail('OTHER_DRONE')
        elseif not session.race and distance(ped, session.entity) > kind.range then
            return fail('TOO_FAR')
        else
            session.beat = now()
            FreezeEntityPosition(session.entity, false)
            local result = summary(session)
            result.reconnect = true
            return ok(result)
        end
    end

    if not B.allowed(src, kind.access, data) then return fail('DENIED') end
    local race = races[src]
    if race then
        if race.kind ~= kindKey then return fail('OTHER_DRONE') end
        local owner = B.identifier(src)
        if not owner then return fail('UNAVAILABLE') end
        local entity = spawn(src, ped, kindKey, kind, race.spawn)
        if not entity then return fail('SPAWN_FAILED') end
        if sessions[src] or not B.actor(src) or races[src] ~= race then deleteEntity(entity); return fail('UNAVAILABLE') end
        session = {
            src = src, owner = owner, kind = kindKey, entity = entity, battery = 100.0, capacity = 1.0, beat = now(), started = now(),
            state = 'landed', light = false, tilt = math.floor(C.spotlight.traverse.max), far = 0, payload = 0, fired = 0, race = race.race,
        }
        sessions[src] = session
        presentation(session)
        DroneAudit.log('deploys', 'Race drone deployed', { Player = DroneAudit.actor(src), Type = kind.label, Race = race.race })
        return ok(summary(session))
    end
    local at = GetEntityCoords(ped)
    if not kind.ignoreNoFly and D.noFly(at.x, at.y) then return fail('NO_FLY') end
    local carried = carrying(src, kind)
    if carried == nil then return fail('INVENTORY') end
    if not carried then return fail('NO_ITEM') end
    local owner = B.identifier(src)
    if not owner then return fail('UNAVAILABLE') end
    local drone = choose(src, owner, kindKey, wanted)
    if not drone then return fail('INVENTORY') end
    local battery = drone.charge
    if battery < C.battery.minimumToLaunch then return fail('BATTERY_LOW') end

    local entity = spawn(src, ped, kindKey, kind)
    if not entity then return fail('SPAWN_FAILED') end
    if sessions[src] or not B.actor(src) then deleteEntity(entity); return fail('UNAVAILABLE') end

    session = {
        src = src, owner = owner, kind = kindKey, id = drone.id, cell = drone.cell, entity = entity, battery = battery,
        capacity = DroneBattery.capacity(drone.cell),
        beat = now(), started = now(),
        state = 'landed', light = kind.features.spotlight == true and C.spotlight.onAtLaunch == true, tilt = math.floor(C.spotlight.traverse.max), far = 0,
        payload = kind.payload and kind.payload.kind == 'taser' and kind.payload.count or (kind.payload and 1 or 0),
        fired = 0,
    }
    sessions[src] = session
    presentation(session)
    DroneBattery.store(drone.cell, battery, true)
    DroneAudit.log('deploys', 'Drone deployed', { Player = DroneAudit.actor(src), Type = kind.label, Battery = ('%d%%'):format(math.floor(battery)) })
    return ok(summary(session))
end
S.begin = begin
S.fleet = fleet

callback('deploy', function(src, data)
    if pending[src] then return fail('RATE_LIMITED') end
    pending[src] = true
    local success, result = pcall(begin, src, data.kind)
    pending[src] = nil
    if not success then error(result) end
    return result
end)

callback('session', function(src)
    local session = sessions[src]
    if not session or not alive(session.entity) then return ok(nil) end
    return ok(summary(session))
end)

local STATES = { flying = true, unattended = true, landed = true, crashed = true }

callback('beat', function(src, data)
    local session = sessions[src]
    if not session then return fail('ENDED') end
    if not alive(session.entity) then S.finish(src, 'gone'); return fail('ENDED') end
    local kind = D.type(session.kind)
    local at = now()
    local elapsed = (at - session.beat) / 1000.0
    session.beat = at
    if session.race then
        if session.state ~= 'crashed' and STATES[data.state] and data.state ~= 'crashed' then session.state = data.state end
        if data.piloting ~= true then setPilot(src, false) end
        presentation(session)
        return ok({ battery = session.battery })
    end

    if session.state ~= 'crashed' and STATES[data.state] and data.state ~= 'crashed' then session.state = data.state end
    if session.state == 'flying' or session.state == 'unattended' then
        local floor = session.battery - D.minimumDrainPerSecond(kind, session.capacity, session.light) * math.min(elapsed, 15.0)
        local claim = D.finite(data.battery) and data.battery or floor
        if session.charged then claim, session.charged = floor, nil end
        session.battery = D.clamp(math.min(floor, claim), 0.0, 100.0)
    elseif session.state == 'landed' and data.piloting == true and D.finite(data.battery) then
        if session.charged then session.charged = nil
        else session.battery = D.clamp(math.min(session.battery, data.battery), 0.0, 100.0) end
    end
    DroneBattery.store(session.cell, session.battery)

    local ped = GetPlayerPed(src)
    if ped ~= 0 and session.state ~= 'crashed' and distance(ped, session.entity) > kind.range * 1.5 + 25.0 then
        session.far = session.far + 1
        if session.far >= 3 then S.finish(src, 'too_far'); return fail('ENDED') end
    else
        session.far = 0
    end

    if held(src, session) == false then S.finish(src, 'no_item'); return fail('ENDED') end
    if data.piloting ~= true then setPilot(src, false) end
    presentation(session)
    return ok({ battery = session.battery })
end)

local function present(session, data)
    if session.state == 'crashed' then return end
    local kind = D.type(session.kind)
    local traverse = C.spotlight.traverse
    if type(data.light) == 'boolean' then session.light = data.light and kind.features.spotlight == true end
    session.tilt = D.finite(data.tilt) and math.floor(D.clamp(data.tilt, traverse.min, traverse.max) + 0.5) or session.tilt
end

event('presentation', function(src, data)
    local session = sessions[src]
    if not session then return end
    present(session, data)
    presentation(session)
end)

event('pilot', function(src, data)
    local session = sessions[src]
    setPilot(src, session ~= nil and data.on == true)
    if session and data.flying == true and session.state ~= 'crashed' and alive(session.entity) then
        FreezeEntityPosition(session.entity, false)
        session.state = 'flying'
        presentation(session)
    end
end)

callback('payload', function(src, data)
    local session = sessions[src]
    if not session or session.state ~= 'flying' then return fail('NOT_FLYING') end
    if not alive(session.entity) then return fail('NOT_FLYING') end
    if session.race then return fail('NO_PAYLOAD') end
    local kind = D.type(session.kind)
    local payload = kind.payload
    if not payload then return fail('NO_PAYLOAD') end
    if session.payload <= 0 then return fail('EMPTY') end
    if payload.kind == 'taser' then
        if now() - session.fired < payload.cooldown * 1000 then return fail('COOLDOWN') end
        session.fired = now()
        session.payload = session.payload - 1
        session.battery = math.max(0.0, session.battery - C.battery.taserShot)
        DroneAudit.log('payloads', 'Drone taser fired', { Player = DroneAudit.actor(src), Left = session.payload })
        return ok({ left = session.payload, battery = session.battery })
    end
    if B.itemsRequired() and not B.removeDrone(src, kind.item, session.id) then return fail('NO_ITEM') end
    session.payload = 0
    local at = GetEntityCoords(session.entity)
    DroneAudit.log('payloads', 'Drone detonated', { Player = DroneAudit.actor(src), At = ('%.1f %.1f %.1f'):format(at.x, at.y, at.z) })
    local entity = session.entity
    sessions[src] = nil
    setPilot(src, false)
    if session.id then DroneBattery.drop(session.cell) else DroneBattery.store(session.cell, session.battery, true) end
    SetTimeout(1500, function() deleteEntity(entity) end)
    return ok({ detonate = true })
end)

local function destroyed(entity)
    local health = GetEntityHealth(entity)
    local body = GetVehicleBodyHealth(entity)
    local engine = GetVehicleEngineHealth(entity)
    return (health ~= nil and health <= 0) or (body ~= nil and body <= 0.0) or (engine ~= nil and engine <= 0.0)
end

local function destroy(src, session)
    local kind = D.type(session.kind)
    if C.pickup.loseItemWhenDestroyed and B.itemsRequired() and B.removeDrone(src, kind.item, session.id) and session.id then
        DroneBattery.drop(session.cell)
        session.cell = nil
    end
    local at = GetEntityCoords(session.entity)
    DroneAudit.log('destroyed', 'Drone destroyed', { Player = DroneAudit.actor(src), Type = kind.label, At = ('%.1f %.1f %.1f'):format(at.x, at.y, at.z) })
    S.finish(src, 'destroyed')
end

callback('crash', function(src, data)
    local session = sessions[src]
    if not session then return fail('ENDED') end
    if not alive(session.entity) then S.finish(src, 'gone'); return fail('ENDED') end
    session.state = 'crashed'
    session.light = false
    presentation(session)
    if session.race then return ok({ destroyed = false }) end
    for _ = 1, 10 do
        if destroyed(session.entity) then
            destroy(src, session)
            return ok({ destroyed = true })
        end
        Wait(100)
        if sessions[src] ~= session then return fail('ENDED') end
        if not alive(session.entity) then S.finish(src, 'gone'); return fail('ENDED') end
    end
    return ok({ destroyed = false })
end)

callback('respawn', function(src)
    local session = sessions[src]
    if not session or not session.race then return fail('ENDED') end
    if not alive(session.entity) then S.finish(src, 'gone'); return fail('ENDED') end
    session.state = 'flying'
    presentation(session)
    return ok({})
end)

event('leave', function(src, data)
    local session = sessions[src]
    if not session then return end
    setPilot(src, false)
    if session.state ~= 'crashed' and (data.state == 'unattended' or data.state == 'landed') then session.state = data.state end
    if data.hold == true and session.state == 'unattended' and alive(session.entity) then FreezeEntityPosition(session.entity, true) end
    present(session, data)
    presentation(session)
end)

local function sessionOf(entity)
    for src, session in pairs(sessions) do
        if session.entity == entity then return src, session end
    end
end

callback('pickup', function(src, data)
    local netId = D.integer(data.netId, 1, 65535)
    if not netId then return fail('INVALID_REQUEST') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not alive(entity) or GetEntityModel(entity) ~= MODEL then return fail('GONE') end
    local ped, data_ = B.actor(src)
    if not ped then return fail('UNAVAILABLE') end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return fail('ON_FOOT') end
    if distance(ped, entity) > C.pickup.distance + 1.0 then return fail('TOO_FAR') end
    if #GetEntityVelocity(entity) > 1.5 then return fail('MOVING') end
    local ownerSrc, session = sessionOf(entity)
    if not session then return fail('GONE') end
    if session.state == 'flying' or session.race then return fail('MOVING') end
    local kind = D.type(session.kind)

    if ownerSrc == src then
        S.finish(src, 'stowed')
        return ok({ stowed = true })
    end

    if not C.pickup.othersCanSeize then return fail('NOT_YOURS') end
    if not B.framework() or not B.allowed(src, C.pickup.seize, data_) then return fail('NOT_YOURS') end
    local taken = false
    local metadata = session.id and { [B.ID] = session.id } or nil
    if B.itemsRequired() and B.removeDrone(ownerSrc, kind.item, session.id) then
        if not B.add(src, kind.item, 1, metadata) then
            B.add(ownerSrc, kind.item, 1, metadata)
            return fail('FULL')
        end
        taken = true
    end
    DroneAudit.log('seized', 'Drone seized', { By = DroneAudit.actor(src), Owner = DroneAudit.actor(ownerSrc), Type = kind.label, Item = tostring(taken) })
    S.finish(ownerSrc, 'seized')
    return ok({ seized = true, item = taken })
end)

local Pack = DroneBattery.pack
local STAGES = { out = true, ['in'] = true }

local function packOf(data)
    local spare = type(data.item) == 'string' and data.item
    return spare, spare and C.battery.packs[spare]
end

local function slotOf(data)
    return D.integer(data.slot, 1, 1000) and data.slot or nil
end

local function choosePack(src, spare, slot)
    if not B.itemsRequired() then return { charge = 100.0, metadata = {} } end
    local list = Pack.list(src, spare)
    if not list then return nil, 'INVENTORY' end
    local best
    for _, entry in ipairs(list) do
        if slot and entry.slot == slot then return entry end
        if not best or entry.charge > best.charge then best = entry end
    end
    if not best then return nil, 'NO_ITEM' end
    return best
end

local function level(found, session)
    if session then return session.battery end
    return DroneBattery.charge(found.cell)
end

local function target(src, pack, fresh)
    local session = sessions[src]
    if session and (session.state ~= 'landed' or session.race) then return nil, nil, 'FLYING' end
    local owner = B.identifier(src)
    if not owner then return nil, nil, 'UNAVAILABLE' end
    local found
    if session then found = { kind = session.kind, cell = session.cell, charge = session.battery }
    else
        for _, drone in ipairs(fleet(src, owner)) do
            if not found or drone.charge < found.charge
                or (drone.charge == found.charge and DroneBattery.capacity(drone.cell) < DroneBattery.capacity(found.cell)) then
                found = drone
            end
        end
    end
    if not found then return nil, nil, 'NO_DRONE' end
    local capacity = DroneBattery.capacity(found.cell)
    if found.charge >= 99.5 and fresh >= 99.5 and math.abs(capacity - pack.capacity) < 0.001 then return nil, nil, 'FULL_CHARGE' end
    if fresh * pack.capacity <= found.charge * capacity + 0.5 then return nil, nil, 'WEAKER_PACK' end
    return found, session
end

local function fit(src, spare, pack, found, session, slot)
    local fresh, returned = 100.0, nil
    if B.itemsRequired() then
        local entry, code = choosePack(src, spare, slot)
        if not entry then return fail(code) end
        fresh = entry.charge
        if not B.remove(src, spare, 1, entry.slot) then return fail('NO_ITEM') end
        local old = level(found, session)
        local oldItem = Pack.item(DroneBattery.capacity(found.cell))
        if oldItem then
            if not B.add(src, oldItem, 1, Pack.metadata(old, C.battery.packs[oldItem].capacity)) then
                B.add(src, spare, 1, next(entry.metadata) and entry.metadata or nil)
                return fail('FULL')
            end
            returned = { item = oldItem, charge = math.floor(old) }
        end
    end
    DroneBattery.fitPack(found.cell, pack.capacity, fresh)
    if session then session.battery, session.capacity, session.charged = fresh, pack.capacity, true end
    return ok({ kind = found.kind, capacity = pack.capacity, charge = fresh, returned = returned })
end

local function owns(src, cell)
    local owner = B.identifier(src)
    if not owner then return false end
    for _, drone in ipairs(fleet(src, owner)) do
        if drone.cell == cell then return true end
    end
    return false
end

local function showSwap(src, swap)
    Player(src).state:set('cxDroneSwap', {
        token = swap.token, kind = swap.kind, charge = math.floor(swap.charge + 0.5), fresh = math.floor(swap.fresh + 0.5),
        net = swap.net or false, stage = swap.stage,
    }, true)
end

local function clearSwap(src)
    if not swaps[src] then return end
    local shown = swaps[src].shown
    swaps[src] = nil
    if shown and GetPlayerName(tostring(src)) then Player(src).state:set('cxDroneSwap', nil, true) end
end

callback('swap', function(src, data)
    local spare, pack = packOf(data)
    if not pack then return fail('INVALID_REQUEST') end
    clearSwap(src)
    if not B.actor(src) then return fail('UNAVAILABLE') end
    local entry, problem = choosePack(src, spare, slotOf(data))
    if not entry then return fail(problem) end
    local found, session, code = target(src, pack, entry.charge)
    if not found then return fail(code) end
    local net
    if session then
        local ped = GetPlayerPed(src)
        if ped == 0 or not alive(session.entity) or distance(ped, session.entity) > C.swap.reach + 1.0 then return fail('WALK_TO_DRONE') end
        net = NetworkGetNetworkIdFromEntity(session.entity)
    end
    local at = now()
    swaps[src] = { item = spare, slot = entry.slot, kind = found.kind, cell = found.cell, charge = found.charge, fresh = entry.charge,
        session = session, net = net, at = at, token = at, stage = 'start' }
    return ok({ kind = found.kind, charge = found.charge, fresh = entry.charge, capacity = pack.capacity, net = net, slot = entry.slot })
end)

event('swapshow', function(src)
    local swap = swaps[src]
    if not swap or swap.shown then return end
    swap.shown = true
    showSwap(src, swap)
end)

event('swapstage', function(src, data)
    local swap = swaps[src]
    if not swap or not swap.shown or not STAGES[data.stage] or swap.stage == data.stage then return end
    swap.stage, swap.at = data.stage, now()
    showSwap(src, swap)
end)

event('swapend', function(src) clearSwap(src) end)

callback('packs', function(src)
    local required = B.itemsRequired()
    local list = {}
    for item, pack in pairs(C.battery.packs) do
        if required then
            local found = Pack.list(src, item)
            if not found then return fail('INVENTORY') end
            local best
            for _, entry in ipairs(found) do
                pcall(Pack.refresh, src, item, entry)
                if not best or entry.charge > best.charge then best = entry end
            end
            if best then list[#list + 1] = { item = item, capacity = pack.capacity, slot = best.slot, charge = math.floor(best.charge) } end
        else
            list[#list + 1] = { item = item, capacity = pack.capacity, charge = 100 }
        end
    end
    table.sort(list, function(a, b)
        if a.capacity ~= b.capacity then return a.capacity < b.capacity end
        return a.item < b.item
    end)
    return ok({ packs = list })
end)

callback('spare', function(src, data)
    local spare, pack = packOf(data)
    if not pack then return fail('INVALID_REQUEST') end
    local swap = swaps[src]
    if swap and swap.item == spare and not swap.done then
        if not B.actor(src) then clearSwap(src); return fail('UNAVAILABLE') end
        if swap.session and (sessions[src] ~= swap.session or swap.session.state ~= 'landed') then clearSwap(src); return fail('GONE') end
        if not swap.session and not owns(src, swap.cell) then clearSwap(src); return fail('GONE') end
        swap.done = true
        return fit(src, spare, pack, swap, swap.session, swap.slot)
    end
    local entry, problem = choosePack(src, spare, slotOf(data))
    if not entry then return fail(problem) end
    local found, session, code = target(src, pack, entry.charge)
    if not found then return fail(code) end
    return fit(src, spare, pack, found, session, entry.slot)
end)

local function use(src, item, slot)
    if C.battery.packs[item] then
        TriggerClientEvent(RESOURCE .. ':spare', src, item, D.integer(slot, 1, 1000) and slot or nil)
        return
    end
    local kindKey = D.typeByItem(item)
    if not kindKey then return end
    chosen[src] = D.integer(slot, 1, 1000) and { kind = kindKey, slot = slot, at = now() } or nil
    TriggerClientEvent(RESOURCE .. ':use', src, kindKey)
end

exports('useItem', function(event_, item, inventory, slot)
    if event_ ~= 'usingItem' or type(inventory) ~= 'table' or not D.integer(inventory.id, 1, 65535) then return end
    local name = type(item) == 'table' and item.name or item
    if type(name) == 'string' then use(inventory.id, name, slot) end
end)

exports('GetDrone', function(src)
    local session = sessions[tonumber(src) or -1]
    if not session or not alive(session.entity) then return nil end
    return { netId = NetworkGetNetworkIdFromEntity(session.entity), kind = session.kind, battery = session.battery, state = session.state }
end)

exports('RecallDrone', function(src, reason)
    src = tonumber(src)
    if not src or not sessions[src] then return false end
    S.finish(src, type(reason) == 'string' and reason:sub(1, 32) or 'recalled')
    return true
end)

exports('SetRaceProfile', function(src, profile)
    src = tonumber(src)
    if not src then return false end
    if profile == nil then
        races[src] = nil
        return true
    end
    if type(profile) ~= 'table' or not D.type(profile.kind) or type(profile.spawn) ~= 'table' then return false end
    local at = profile.spawn
    if not (D.finite(at.x) and D.finite(at.y) and D.finite(at.z)) then return false end
    races[src] = { kind = profile.kind, race = tostring(profile.race or 'race'):sub(1, 48), spawn = { x = at.x + 0.0, y = at.y + 0.0, z = at.z + 0.0, w = (D.finite(at.w) and at.w or 0.0) + 0.0 } }
    return true
end)

CreateThread(function()
    B.registerItems(function(src, name, item) use(src, name, type(item) == 'table' and item.slot or nil) end)
    while true do
        Wait(1000)
        local at = now()
        for src, swap in pairs(swaps) do
            if at - swap.at > SWAP_TIMEOUT_MS then pcall(clearSwap, src) end
        end
        for src, session in pairs(sessions) do
            if not alive(session.entity) then pcall(S.finish, src, 'gone')
            elseif math.abs(at - session.beat) > BEAT_TIMEOUT_MS then pcall(S.finish, src, 'timeout')
            elseif not session.race and at - session.started > DEAD_GRACE_MS and destroyed(session.entity) then
                session.dead = (session.dead or 0) + 1
                if session.dead >= 2 then pcall(destroy, src, session) end
            else
                session.dead = nil
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(CHARGE_REFRESH_MS)
        if B.itemsRequired() then
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                for item in pairs(C.battery.packs) do
                    for _, entry in ipairs(DroneBattery.pack.list(src, item) or {}) do pcall(DroneBattery.pack.refresh, src, item, entry) end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    S.finish(src, 'dropped')
    abandon[src], pending[src], pilots[src], chosen[src], swaps[src], races[src] = nil, nil, nil, nil, nil, nil
    local prefix = src .. ':'
    for key in pairs(rates) do if key:sub(1, #prefix) == prefix then rates[key] = nil end end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    if sessions[src] then S.finish(src, 'unloaded') end
end)

AddEventHandler('onResourceStart', function(name)
    if name == 'qbx_core' or name == 'qb-core' then
        B.reset()
        B.clearBound()
        B.registerItems(function(src, name, item) use(src, name, type(item) == 'table' and item.slot or nil) end)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= RESOURCE then return end
    for src, session in pairs(sessions) do
        pcall(DroneBattery.store, session.cell, session.battery, true)
        pcall(deleteEntity, session.entity)
        pcall(setPilot, src, false)
    end
    for src in pairs(swaps) do pcall(clearSwap, src) end
    B.releaseItems()
end)
