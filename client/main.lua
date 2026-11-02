local C, D, U = Config, DroneDomain, DroneUtil
local DC = DroneClient
local RESOURCE = GetCurrentResourceName()
local REVISION = 'drone-3'
local TAB = 'cortex-drone'
local PICKUP = 'pickup'
local MODEL = joaat(C.model)

local DEFAULTS = {
    startMode = 'normal', boost = 'hold', acroControls = C.acro.controls, acroRates = 100,
    acroExpo = math.floor(C.acro.expo * 100.0 + 0.5), acroTilt = math.floor(C.acro.cameraTilt + 0.5),
    sensitivity = 100, invert = false, view = 'gimbal', units = C.units, legend = 'auto', cineFrame = 'off',
}
local START_MODES = { last = true, cine = true, normal = true, sport = true, acro = true }

DC.prefs = {}
for key, value in pairs(DEFAULTS) do DC.prefs[key] = value end

local CODES = {
    INVALID_REQUEST = 'notify.unavailable', UNAVAILABLE = 'notify.unavailable', ON_FOOT = 'notify.onFoot', DENIED = 'notify.denied',
    INVENTORY = 'notify.inventory', NO_ITEM = 'notify.noItem', BATTERY_LOW = 'notify.batteryLow', SPAWN_FAILED = 'notify.spawnFailed',
    TOO_FAR = 'notify.tooFar', OTHER_DRONE = 'notify.otherDrone', DOWN = 'notify.down', ABANDONED = 'notify.abandoned',
    NO_FLY = 'notify.noFly', MOVING = 'notify.moving', NOT_YOURS = 'notify.notYours', FULL = 'notify.full', GONE = 'notify.gone',
    FLYING = 'notify.flying', NO_DRONE = 'notify.noDrone', FULL_CHARGE = 'notify.fullCharge', WALK_TO_DRONE = 'notify.walkToDrone',
    WEAKER_PACK = 'notify.weakerPack',
}

local ENDINGS = {
    stowed = { 'notify.stowed', 'success' }, seized = { 'notify.seized', 'error' }, too_far = { 'notify.tooFar', 'error' },
    no_item = { 'notify.noItem', 'error' }, staff = { 'notify.staff', 'info' }, timeout = { 'notify.timeout', 'error' },
    abandoned = { 'notify.abandoned', 'info' }, gone = { 'notify.gone', 'error' }, unloaded = false, dropped = false,
    destroyed = { 'notify.destroyed', 'error' },
}

local function failure(result)
    if not result then U.notify('notify.noAnswer'); return end
    local code = result.error and result.error.code
    if code == 'RATE_LIMITED' then return end
    U.notify(CODES[code] or 'notify.unavailable', code == 'DOWN' and 'info' or 'error', { level = math.floor(C.battery.minimumToLaunch) })
end
DC.failure = failure

local function readPrefs()
    local function read(key)
        local ok, value = pcall(function() return exports['cortex-lib']:getTabSetting(TAB, key) end)
        if ok and value ~= nil then return value end
        return DEFAULTS[key]
    end
    local function number(key, low, high)
        return D.clamp(tonumber(read(key)) or DEFAULTS[key], low, high)
    end
    local function pick(key, allowed)
        local value = read(key)
        return allowed[value] and value or DEFAULTS[key]
    end
    local prefs = DC.prefs
    prefs.startMode = pick('startMode', START_MODES)
    prefs.boost = pick('boost', { hold = true, toggle = true })
    local acro = read('acroControls')
    if acro == 'classic' then acro = 'manual' elseif acro == 'mouse' or acro == 'simple' then acro = 'glide' end
    prefs.acroControls = (acro == 'glide' or acro == 'manual') and acro or DEFAULTS.acroControls
    prefs.acroRates = number('acroRates', 50, 200)
    prefs.acroExpo = number('acroExpo', 0, 80)
    prefs.acroTilt = number('acroTilt', 0, 60)
    prefs.sensitivity = number('sensitivity', 25, 250)
    prefs.invert = read('invert') == true
    prefs.view = pick('view', { gimbal = true, chase = true })
    prefs.units = pick('units', { metric = true, imperial = true })
    prefs.legend = pick('legend', { auto = true, always = true, off = true })
    prefs.cineFrame = pick('cineFrame', { off = true, vertical = true, letterbox = true })
end

local function choices(key, values)
    local options = {}
    for i, value in ipairs(values) do options[i] = { value = value, label = L(('settings.%s.%s'):format(key, value)) } end
    return options
end

local function registerSettings()
    local flight, acro, camera, display = L('settings.section.flight'), L('settings.section.acro'), L('settings.section.camera'), L('settings.section.display')
    local manual = { acroControls = 'manual' }
    local rows = {
        { key = 'startMode', section = flight, type = 'select', label = L('settings.startMode'), description = L('settings.startMode.help'),
            options = choices('startMode', { 'normal', 'cine', 'sport', 'acro', 'last' }) },
        { key = 'boost', section = flight, type = 'select', label = L('settings.boost'), description = L('settings.boost.help'),
            options = choices('boost', { 'hold', 'toggle' }) },
        { key = 'acroControls', section = acro, type = 'select', label = L('settings.acro'), description = L('settings.acro.help'),
            options = choices('acro', { 'glide', 'manual' }) },
        { key = 'acroRates', section = acro, type = 'slider', label = L('settings.acroRates'), description = L('settings.acroRates.help'),
            min = 50, max = 200, step = 5, suffix = '%' },
        { key = 'acroExpo', section = acro, type = 'slider', label = L('settings.acroExpo'), description = L('settings.acroExpo.help'),
            min = 0, max = 80, step = 5, suffix = '%', showWhen = manual },
        { key = 'acroTilt', section = acro, type = 'slider', label = L('settings.acroTilt'), description = L('settings.acroTilt.help'),
            min = 0, max = 60, step = 5, suffix = '°', showWhen = manual },
        { key = 'view', section = camera, type = 'select', label = L('settings.view'), description = L('settings.view.help'),
            options = choices('view', { 'gimbal', 'chase' }) },
        { key = 'sensitivity', section = camera, type = 'slider', label = L('settings.sensitivity'), description = L('settings.sensitivity.help'),
            min = 25, max = 250, step = 5, suffix = '%' },
        { key = 'invert', section = camera, type = 'toggle', label = L('settings.invert'), description = L('settings.invert.help') },
        { key = 'units', section = display, type = 'select', label = L('settings.units'), description = L('settings.units.help'),
            options = choices('units', { 'metric', 'imperial' }) },
        { key = 'legend', section = display, type = 'select', label = L('settings.legend'), description = L('settings.legend.help'),
            options = choices('legend', { 'auto', 'always', 'off' }) },
        { key = 'cineFrame', section = display, type = 'select', label = L('settings.cineFrame'), description = L('settings.cineFrame.help'),
            options = choices('cineFrame', { 'off', 'vertical', 'letterbox' }) },
    }
    pcall(function() exports['cortex-lib']:registerSettings(TAB, L('settings.tab'), 'cortex-drone:', rows, DEFAULTS) end)
    readPrefs()
end

AddEventHandler('cortex-lib:settingsChanged', function(tabId) if tabId == TAB then readPrefs() end end)
AddEventHandler('onClientResourceStart', function(name) if name == 'cortex-lib' then registerSettings() end end)

local beatGen = 0

local function finishLocal(reason)
    if DC.piloting then Pilot.stop(reason or 'ended') end
    DC.session = nil
    beatGen = beatGen + 1
    Autopilot.cancel()
end

local function startBeat()
    beatGen = beatGen + 1
    local gen = beatGen
    CreateThread(function()
        while gen == beatGen and DC.session and not DC.stopped do
            Wait(2000)
            local s = DC.session
            if gen ~= beatGen or not s then break end
            if not DoesEntityExist(s.entity) and NetworkDoesEntityExistWithNetworkId(s.netId) then s.entity = NetToVeh(s.netId) end
            local kind = D.type(s.kind)
            if kind and not DC.piloting and not s.race and s.state == 'unattended' and Pilot.tracking() then
                local rate = D.drainPerSecond(kind, { hover = true, spotlight = s.light, track = true }, s.capacity)
                s.battery = math.max(0.0, s.battery - rate * 2.0)
            end
            local result = U.call('beat', { battery = s.battery, state = s.state, piloting = DC.piloting })
            if gen ~= beatGen or DC.session ~= s then break end
            if result and result.ok and type(result.data) == 'table' then
                local level = result.data.battery
                if D.finite(level) and level < s.battery then s.battery = level end
                if s.state == 'unattended' and s.battery <= 0.0 and not DC.piloting and not Pilot.tracking() and not s.descending and DoesEntityExist(s.entity) then
                    s.descending = true
                    Autopilot.fall(s.entity)
                end
            elseif result and result.error and result.error.code == 'ENDED' then
                finishLocal('ended')
            end
        end
    end)
    CreateThread(function()
        local dead, retryAt = 0, 0
        while gen == beatGen and DC.session and not DC.stopped do
            Wait(250)
            local s = DC.session
            if gen ~= beatGen or not s then break end
            local e = s.entity
            local wrecked = false
            if not s.fresh and DoesEntityExist(e) then
                wrecked = IsEntityDead(e) or GetVehicleEngineHealth(e) <= 0.0
                if not wrecked and NetworkGetEntityOwner(e) == PlayerId() then U.foldEngineDamage(e) end
                wrecked = wrecked or GetVehicleBodyHealth(e) <= 0.0
                if NetworkGetEntityOwner(e) == PlayerId() and not DC.piloting and not Pilot.tracking() then
                    local ground = U.underWorld(e)
                    if ground then
                        if C.debug then print(('[%s] rescued drone from below world z=%.1f ground=%.1f state=%s'):format(RESOURCE, GetEntityCoords(e).z, ground, s.state)) end
                        U.lift(e, ground, Autopilot.rest(e))
                        if s.state == 'crashed' or s.state == 'landed' then FreezeEntityPosition(e, true) end
                    end
                end
            end
            if not DC.piloting and wrecked then
                dead = dead + 1
            else
                dead = 0
            end
            if dead >= 2 and U.now() >= retryAt then
                retryAt = U.now() + 4000
                local result = U.call('crash', { reason = 'destroyed' })
                if result and result.ok and result.data and result.data.destroyed and DC.session == s then
                    finishLocal('destroyed')
                    U.notify('notify.destroyed')
                end
            end
        end
    end)
end

local busy = false

local function deploy(kindKey, race)
    if busy or DC.piloting or DC.stopped or Pilot.launching() or DroneSwap.active then return end
    local conf = D.type(kindKey)
    if not conf then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, true) then U.notify('notify.onFoot'); return end
    if not DC.session and not race then
        local at = GetEntityCoords(ped)
        if not conf.ignoreNoFly and D.noFly(at.x, at.y) then U.notify('notify.noFly'); return end
    end
    busy = true
    CreateThread(function()
        local result = U.call('deploy', { kind = kindKey })
        if not result or not result.ok then
            busy = false
            if result and result.error and result.error.code == 'DOWN' and type(result.error.at) == 'table' then
                SetNewWaypoint(U.F(result.error.at.x), U.F(result.error.at.y))
            end
            failure(result)
            return
        end
        local data = result.data
        local entity = U.entity(data.netId, 5000)
        if entity == 0 then busy = false; U.notify('notify.spawnFailed'); return end
        Autopilot.cancel()
        local fields = {
            netId = data.netId, entity = entity, kind = data.kind, conf = D.type(data.kind),
            battery = D.finite(data.battery) and data.battery or 100.0, capacity = D.finite(data.capacity) and data.capacity or 1.0,
            payload = tonumber(data.payload) or 0,
            state = type(data.state) == 'string' and data.state or 'landed', light = data.light == true, fresh = not data.reconnect,
            launch = not data.reconnect and data.race ~= true, descending = false, race = data.race == true,
        }
        local previous = DC.session
        if previous and previous.netId == data.netId then
            for key, value in pairs(fields) do previous[key] = value end
        else
            DC.session = fields
            startBeat()
        end
        local started, err = pcall(Pilot.start)
        busy = false
        if not started then print(('[%s] pilot start failed: %s'):format(RESOURCE, err)) end
    end)
end
DC.deploy = deploy

local function defaultKind()
    if DC.session then return DC.session.kind end
    if C.types.drone then return 'drone' end
    return next(C.types)
end

RegisterNetEvent(RESOURCE .. ':use', function(kindKey)
    if DC.piloting then return end
    deploy(kindKey)
end)

function DC.charged(data)
    local kind = D.type(data.kind)
    local capacity = D.finite(data.capacity) and data.capacity or 1.0
    local charge = D.finite(data.charge) and data.charge or 100.0
    local vars = {
        label = kind and kind.label or '', charge = math.floor(charge),
        minutes = kind and math.floor(D.flightSeconds(kind, capacity) * charge / 100.0 / 60.0 + 0.5) or 0,
    }
    local returned = type(data.returned) == 'table' and data.returned
    if returned then vars.old = math.floor(tonumber(returned.charge) or 0) end
    U.notify(returned and 'notify.chargedReturned' or 'notify.charged', 'success', vars)
    if DC.session and data.kind == DC.session.kind then DC.session.battery, DC.session.capacity = charge, capacity end
end

function DC.instant(item, slot)
    CreateThread(function()
        local result = U.call('spare', { item = item, slot = slot })
        if not result or not result.ok then failure(result); return end
        DC.charged(result.data or {})
    end)
end

local function fitSpare(item, slot)
    if DC.piloting or Pilot.launching() then U.notify('notify.flying'); return end
    if busy then return end
    slot = math.tointeger(slot)
    if not DroneSwap.start(item, slot) then DC.instant(item, slot) end
end

RegisterNetEvent(RESOURCE .. ':spare', fitSpare)

RegisterNetEvent(RESOURCE .. ':charged', function()
    if DC.session then DC.session.battery = 100.0 end
end)

RegisterNetEvent(RESOURCE .. ':ended', function(reason)
    if not DC.session then return end
    finishLocal(reason)
    local ending = ENDINGS[reason]
    if ending then U.notify(ending[1], ending[2]) end
end)

if C.command then
    RegisterCommand(C.command, function(_, args)
        if DC.piloting then Pilot.stop('leave'); return end
        local kindKey = args[1] and args[1]:lower() or defaultKind()
        if not D.type(kindKey) then U.notify('notify.unknownType'); return end
        deploy(kindKey)
    end, false)
end

RegisterCommand('cortexdrone_connect', function()
    if DC.piloting then Pilot.stop('leave'); return end
    local kindKey = defaultKind()
    if kindKey then deploy(kindKey) end
end, false)
RegisterKeyMapping('cortexdrone_connect', L('key.connect'), 'keyboard', '')

local SWAP = 'swap'
local SWAP_ROWS = 3
local PROMPT_KEY = C.keys.pickup ~= '' and C.keys.pickup or 'E'
local prompt = { entity = nil, own = false, swap = false, holding = false, rows = 0, packs = {}, token = 0 }

local function anchor(entity)
    return { type = 'entity', entity = entity, model = GetEntityModel(entity), offset = { z = 0.15 }, maxDistance = C.pickup.distance }
end

local function hideRows()
    prompt.token = prompt.token + 1
    for i = 1, prompt.rows do pcall(lib.hideInteraction, SWAP .. i) end
    prompt.rows, prompt.packs = 0, {}
end

local function showRows(entity, packs, kind)
    local rows = #packs > 0 and packs or { false }
    local count = math.min(#rows, SWAP_ROWS)
    for i = 1, count do
        local pack = rows[i]
        local label = L('prompt.battery')
        local charge = pack and tonumber(pack.charge) or 100
        if kind and pack and (count > 1 or charge < 100) then
            label = L('prompt.batteryTime', { minutes = math.floor(D.flightSeconds(kind, pack.capacity) * charge / 100.0 / 60.0 + 0.5) })
        end
        pcall(lib.showInteraction, { id = SWAP .. i, label = label, key = PROMPT_KEY, priority = 40 - i, anchor = anchor(entity) })
    end
    for i = count + 1, prompt.rows do pcall(lib.hideInteraction, SWAP .. i) end
    prompt.rows, prompt.packs = count, rows
end

local function loadRows(entity, kind)
    local token = prompt.token
    CreateThread(function()
        for attempt = 1, 3 do
            if attempt > 1 then Wait(400) end
            if prompt.token ~= token or prompt.entity ~= entity or not prompt.swap then return end
            local result = U.call('packs', {})
            if prompt.token ~= token or prompt.entity ~= entity or not prompt.swap then return end
            if result and result.ok and type(result.data) == 'table' and type(result.data.packs) == 'table' then
                showRows(entity, result.data.packs, D.type(kind))
                return
            end
        end
    end)
end

local function hidePrompt()
    if prompt.entity and lib and lib.hideInteraction then
        pcall(lib.hideInteraction, PICKUP)
        hideRows()
    end
    prompt.entity, prompt.own, prompt.swap = nil, false, false
end

local function showPrompt(entity, own, landed, kind)
    local swap = own and landed
    if prompt.entity == entity and prompt.own == own and prompt.swap == swap then return end
    if prompt.entity and lib and lib.hideInteraction and (prompt.entity ~= entity or not swap) then hideRows() end
    local reload = swap and (prompt.entity ~= entity or not prompt.swap)
    prompt.entity, prompt.own, prompt.swap = entity, own, swap
    if not (lib and lib.showInteraction) then return end
    pcall(lib.showInteraction, {
        id = PICKUP, label = L(own and 'prompt.pickup' or 'prompt.seize'), key = PROMPT_KEY,
        priority = 40, holdDuration = 700, anchor = anchor(entity),
    })
    if reload then loadRows(entity, kind) end
end

local function pickup(entity)
    if not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then return end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    TaskTurnPedToFaceEntity(PlayerPedId(), entity, 600)
    U.playOnce('pickup_object', 'pickup_low', 1200, 0)
    Wait(800)
    local result = U.call('pickup', { netId = netId })
    if not result or not result.ok then failure(result); return end
    if result.data and result.data.seized then U.notify('notify.seizedOther', 'success') end
    hidePrompt()
end

RegisterCommand('+cortexdrone_pickup', function()
    local entity = prompt.entity
    if not entity or DC.piloting or busy or Pilot.launching() or DroneSwap.active or prompt.holding then return end
    for i = 1, prompt.rows do
        if lib.isInteractionVisible(SWAP .. i) then
            local pack = prompt.packs[i]
            if not pack then U.notify('notify.noBattery'); return end
            hidePrompt()
            fitSpare(pack.item, pack.slot)
            return
        end
    end
    if lib and lib.isInteractionVisible and not lib.isInteractionVisible(PICKUP) then return end
    prompt.holding = true
    pcall(lib.startInteractionHold, PICKUP)
    CreateThread(function()
        local started = U.now()
        while prompt.holding and prompt.entity == entity do
            if DroneSwap.active then
                prompt.holding = false
                pcall(lib.cancelInteractionHold, PICKUP)
                return
            end
            if U.now() - started >= 700 then
                prompt.holding = false
                pickup(entity)
                return
            end
            Wait(0)
        end
    end)
end, false)
RegisterCommand('-cortexdrone_pickup', function()
    if not prompt.holding then return end
    prompt.holding = false
    pcall(lib.cancelInteractionHold, PICKUP)
end, false)
RegisterKeyMapping('+cortexdrone_pickup', L('key.pickup'), 'keyboard', C.keys.pickup)

local GROUNDED = { landed = true, crashed = true, unattended = true }

CreateThread(function()
    local me = GetPlayerServerId(PlayerId())
    while not DC.stopped do
        local sleep = 1000
        local known = DroneRemote and DroneRemote.known or {}
        if not DC.piloting and not busy and not Pilot.launching() and not DroneSwap.active and next(known) then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local onFoot = not IsPedInAnyVehicle(ped, false)
            local best, bestDist, own, bestInfo
            for entity, info in pairs(known) do
                if DoesEntityExist(entity) then
                    local dist = #(GetEntityCoords(entity) - pos)
                    if dist < 30.0 then sleep = 300 end
                    if dist <= C.pickup.distance + 0.6 and GROUNDED[info.state] and GetEntitySpeed(entity) < 1.0 then
                        local mine = info.owner == me
                        if (mine or C.pickup.othersCanSeize) and (not best or dist < bestDist) then best, bestDist, own, bestInfo = entity, dist, mine, info end
                    end
                end
            end
            if best then showPrompt(best, own, onFoot and bestInfo.state == 'landed', bestInfo.kind) else hidePrompt() end
        elseif prompt.entity then
            hidePrompt()
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    AddTextEntry(C.model, L('vehicle.name'))
    Wait(250)
    registerSettings()
    Wait(750)
    local result = U.call('session', {})
    if result and result.ok and type(result.data) == 'table' and result.data.netId and not DC.session then
        local data = result.data
        local entity = U.entity(data.netId, 3000)
        if entity ~= 0 then
            DC.session = {
                netId = data.netId, entity = entity, kind = data.kind, conf = D.type(data.kind),
                battery = D.finite(data.battery) and data.battery or 100.0, capacity = D.finite(data.capacity) and data.capacity or 1.0,
                payload = tonumber(data.payload) or 0,
                state = data.state == 'flying' and 'unattended' or data.state, light = data.light == true, fresh = false, race = data.race == true,
            }
            if DC.session.conf then startBeat() else DC.session = nil end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= RESOURCE then return end
    DC.stopped = true
    if DC.piloting then pcall(Pilot.stop, 'stopped') end
    pcall(Autopilot.cancel)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if GetEntityModel(vehicle) == MODEL and (not NetworkGetEntityIsNetworked(vehicle) or NetworkGetEntityOwner(vehicle) == PlayerId()) then
            pcall(U.deleteEntity, vehicle)
        end
    end
    pcall(SetModelAsNoLongerNeeded, MODEL)
    pcall(SetNuiFocus, false, false)
    pcall(ClearFocus)
    pcall(ClearTimecycleModifier)
    pcall(SetNightvision, false)
    pcall(SetSeethrough, false)
    if lib and lib.hideHelp then pcall(lib.hideHelp) end
end)

exports('IsPiloting', function() return DC.piloting == true end)
exports('GetDrone', function()
    local s = DC.session
    if not s then return nil end
    return { netId = s.netId, entity = s.entity, kind = s.kind, battery = s.battery, state = s.state, piloting = DC.piloting == true }
end)
exports('Deploy', function(kindKey) deploy(kindKey or defaultKind()) end)
exports('Disconnect', function() if DC.piloting then Pilot.stop('leave') end end)
exports('DeployRace', function(kindKey) deploy(kindKey, true) end)
exports('RaceHold', function(on) return Pilot.raceHold(on == true) end)
exports('RaceRespawn', function(x, y, z, h) return Pilot.raceRespawn(x, y, z, h) end)
exports('RaceGo', function() return Pilot.raceGo() end)

if C.debug then
    RegisterCommand('drone_diag', function()
        local s = DC.session
        if not s then print(('[%s] %s no session'):format(RESOURCE, REVISION)); return end
        local e = s.entity
        local pos = DoesEntityExist(e) and GetEntityCoords(e) or vector3(0.0, 0.0, 0.0)
        print(('[%s] %s kind=%s state=%s piloting=%s battery=%.1f exists=%s control=%s engine=%s pos=%.1f,%.1f,%.1f body=%.0f eng=%.0f'):format(
            RESOURCE, REVISION, s.kind, s.state, tostring(DC.piloting), s.battery, tostring(DoesEntityExist(e)),
            tostring(DoesEntityExist(e) and NetworkHasControlOfEntity(e)), tostring(DoesEntityExist(e) and GetIsVehicleEngineRunning(e)),
            pos.x, pos.y, pos.z, DoesEntityExist(e) and GetVehicleBodyHealth(e) or -1, DoesEntityExist(e) and GetVehicleEngineHealth(e) or -1))
    end, false)
end
