DroneValidate = {}
local V = DroneValidate
local D = DroneDomain

local function show(value)
    if type(value) == 'string' then return ('%q'):format(value:sub(1, 40)) end
    if type(value) == 'table' then return 'a table' end
    return tostring(value)
end

local function name(value, max)
    return type(value) == 'string' and value:match('^[%w_%-%.]+$') ~= nil and #value <= (max or 64)
end

local function rule(value)
    if value == false then return true end
    if type(value) ~= 'table' or value.jobs == nil then return false end
    for key in pairs(value) do if key ~= 'jobs' and key ~= 'duty' then return false end end
    if value.duty ~= nil and type(value.duty) ~= 'boolean' then return false end
    if type(value.jobs) ~= 'table' or next(value.jobs) == nil then return false end
    for job, grade in pairs(value.jobs) do
        if not name(job, 64) or not D.integer(grade, 0, 100) then return false end
    end
    return true
end
V.rule = rule

local MODES = { 'cine', 'normal', 'sport' }
local SPEED_DEFAULT = {
    cine = { horizontal = 4.0, vertical = 2.0, yaw = 45.0, accel = 3.0, tilt = 10.0 },
    normal = { horizontal = 10.0, vertical = 4.0, yaw = 90.0, accel = 8.0, tilt = 18.0 },
    sport = { horizontal = 19.0, vertical = 6.0, yaw = 150.0, accel = 14.0, tilt = 30.0 },
}
local SPEED_LIMIT = { horizontal = { 0.5, 60.0 }, vertical = { 0.5, 30.0 }, yaw = { 5.0, 400.0 }, accel = { 0.5, 60.0 }, tilt = { 0.0, 60.0 } }
local CONTROL_KEYS = { 'up', 'down', 'boost', 'mode', 'zoomIn', 'zoomOut', 'vision', 'spotlight', 'lock', 'payload', 'view', 'home', 'leave', 'acro', 'cinematic' }
local KIND_FEATURES = { 'night', 'thermal', 'spotlight', 'track', 'follow', 'lookup', 'cinematic' }
local FEATURES = { 'night', 'thermal', 'spotlight', 'track', 'follow', 'lookup', 'payload', 'cinematic' }
local VOLUME_DEFAULT = {
    alpha = { 250, 0, 255 }, coneScale = { 1.0, 0.05, 2.0 }, sourceRadius = { 0.05, 0.0, 1.0 },
    falloff = { 1.5, 0.0, 3.0 }, openFade = { 0.5, 0.05, 1.0 }, maxLength = { 60.0, 1.0, 300.0 }, dayFactor = { 0.0, 0.0, 1.0 },
    maxDrawDistance = { 250.0, 10.0, 2000.0 },
}

local ACRO_DEFAULT = {
    thrust = { 3.5, 1.5, 10.0 }, topSpeed = { 37.5, 5.0, 80.0 }, pitchRate = { 540.0, 30.0, 1800.0 }, rollRate = { 600.0, 30.0, 1800.0 },
    yawRate = { 300.0, 30.0, 1800.0 }, expo = { 0.35, 0.0, 1.0 }, keyRamp = { 0.3, 0.0, 2.0 }, mouse = { 1.0, 0.1, 5.0 },
    cameraTilt = { 25.0, -10.0, 60.0 }, tumble = { 540.0, 0.0, 3600.0 }, cruise = { 37.5, 5.0, 80.0 }, creep = { 2.0, 0.0, 10.0 }, keyEase = { 2.0, 0.0, 3.0 }, climb = { 12.0, 2.0, 40.0 }, tilt = { 50.0, 15.0, 70.0 }, brake = { 0.8, 0.0, 1.0 },
    response = { 10.0, 0.5, 20.0 }, authority = { 3.0, 1.0, 6.0 }, grip = { 15.0, 0.0, 80.0 }, carve = { 0.6, 0.0, 1.0 }, flipRate = { 480.0, 90.0, 1440.0 }, lookFlip = { 2.0, 0.5, 6.0 }, float = { 0.6, 0.0, 1.0 }, viewPitch = { 0.4, 0.0, 1.0 },
    levelBand = { 10.0, 0.0, 30.0 }, descent = { 12.0, 1.0, 40.0 }, diveAccel = { 20.0, 2.0, 40.0 }, pullOut = { 20.0, 4.0, 40.0 }, floor = { 1.0, 0.3, 10.0 }, nose = { 0.6, 0.0, 1.0 }, loopDetent = { 25.0, 0.0, 180.0 }, lookRest = { 0.4, 0.1, 2.0 },
}

local CONTROL_DEFAULT = {
    keyboard = { up = 22, down = 36, boost = 21, mode = 26, zoomIn = 172, zoomOut = 173, vision = 44, spotlight = 23, lock = 24, payload = 25, view = 0, home = 20, leave = 194, acro = 73, cinematic = 74 },
    pad = { up = 24, down = 25, boost = 21, mode = 26, zoomIn = 172, zoomOut = 173, vision = 44, spotlight = 175, lock = 22, payload = 23, view = 0, home = 174, leave = 194, acro = 37, cinematic = 36 },
}

local CINE_DEFAULT = {
    look = { 3.5, 0.5, 30.0 }, aim = { 3.0, 0.5, 30.0 }, zoom = { 2.0, 0.2, 30.0 }, ease = { 0.6, 0.0, 3.0 }, maxSpeed = { 30.0, 2.0, 80.0 },
    accel = { 9.0, 1.0, 60.0 }, minDistance = { 4.0, 2.0, 50.0 }, hideGrace = { 5.0, 0.0, 30.0 }, regain = { 2.0, 0.0, 10.0 },
}

local CINE_SHOTS = {
    framing = { yaw = { 15.0, 0.0, 45.0 }, pitch = { 10.0, 0.0, 30.0 } },
    follow = { swing = { 45.0, 5.0, 180.0 }, distance = { 60.0, 5.0, 300.0 } },
    orbit = { speed = { 3.0, 0.5, 30.0 }, radius = { 80.0, 5.0, 300.0 } },
    dronie = { speed = { 4.0, 0.5, 30.0 }, climb = { 30.0, 0.0, 80.0 }, distance = { 45.0, 5.0, 300.0 } },
    rocket = { speed = { 3.0, 0.5, 20.0 }, height = { 40.0, 5.0, 300.0 } },
    helix = { speed = { 4.0, 0.5, 30.0 }, out = { 1.0, 0.0, 10.0 }, up = { 0.8, 0.0, 10.0 }, radius = { 35.0, 5.0, 300.0 } },
}

function V.run(config, quiet)
    local problems = {}
    local function problem(path, expected, got, action)
        problems[#problems + 1] = ('config.lua: Config.%s expected %s, got %s; %s'):format(path, expected, show(got), action)
    end
    local function section(key, default)
        if type(config[key]) ~= 'table' then
            problem(key, 'a table', config[key], 'using the defaults')
            config[key] = default
        end
        return config[key]
    end
    local function num(tbl, key, path, low, high, default)
        local value = tbl[key]
        if D.finite(value) and value >= low and value <= high then tbl[key] = value + 0.0; return end
        problem(path, ('a number from %s to %s'):format(low, high), value, 'using ' .. tostring(default))
        tbl[key] = default
    end
    local function int(tbl, key, path, low, high, default)
        if D.integer(tbl[key], low, high) then return end
        problem(path, ('a whole number from %d to %d'):format(low, high), tbl[key], 'using ' .. tostring(default))
        tbl[key] = default
    end
    local function bool(tbl, key, path, default)
        if type(tbl[key]) == 'boolean' then return end
        problem(path, 'true or false', tbl[key], 'using ' .. tostring(default))
        tbl[key] = default
    end
    local function oneOf(tbl, key, path, options, default)
        for _, option in ipairs(options) do if tbl[key] == option then return end end
        problem(path, 'one of ' .. table.concat(options, ', '), tbl[key], 'using ' .. tostring(default))
        tbl[key] = default
    end

    if config.Locale ~= nil and not (type(config.Locale) == 'string' and config.Locale:match('^[%a%-]+$')) then
        problem('Locale', 'a language code like "en"', config.Locale, 'using en'); config.Locale = 'en'
    end
    bool(config, 'debug', 'debug', false)
    if not name(config.model) then problem('model', 'a vehicle model name', config.model, 'using rcmavic'); config.model = 'rcmavic' end
    if config.command ~= false and not (type(config.command) == 'string' and config.command:match('^[%w_]+$') and #config.command <= 32) then
        problem('command', 'a command name or false', config.command, 'using drone'); config.command = 'drone'
    end
    if config.requireItem ~= true and config.requireItem ~= false and config.requireItem ~= 'auto' then
        problem('requireItem', 'true, false or "auto"', config.requireItem, 'using "auto"'); config.requireItem = 'auto'
    end
    oneOf(config, 'units', 'units', { 'metric', 'imperial' }, 'metric')

    if config.features == nil then config.features = {} end
    local features = section('features', {})
    for _, feature in ipairs(FEATURES) do
        if features[feature] == nil then features[feature] = true end
        bool(features, feature, 'features.' .. feature, true)
    end

    if type(config.types) ~= 'table' then problem('types', 'a table of drone types', config.types, 'no drones are available'); config.types = {} end
    local items = {}
    for key, kind in pairs(config.types) do
        local base = 'types.' .. tostring(key)
        if not name(key, 32) or type(kind) ~= 'table' then
            problem(base, 'a drone type table', kind, 'removing it'); config.types[key] = nil
        elseif not name(kind.item) or items[kind.item] then
            problem(base .. '.item', 'a unique item name', kind.item, 'removing the type'); config.types[key] = nil
        else
            items[kind.item] = true
            if type(kind.label) ~= 'string' or kind.label == '' or #kind.label > 48 then
                problem(base .. '.label', 'a short name', kind.label, 'using ' .. key); kind.label = key
            end
            if type(kind.colours) ~= 'table' or not D.integer(kind.colours[1], 0, 160) or not D.integer(kind.colours[2], 0, 160) then
                problem(base .. '.colours', 'two paint indexes from 0 to 160', kind.colours, 'using 0, 0'); kind.colours = { 0, 0 }
            end
            if not rule(kind.access) then
                problem(base .. '.access', 'false or { jobs = { name = grade }, duty = true }', kind.access, 'police only')
                kind.access = { jobs = { police = 0 }, duty = true }
            end
            num(kind, 'range', base .. '.range', 20.0, 2000.0, 300.0)
            num(kind, 'maxAltitude', base .. '.maxAltitude', 5.0, 1500.0, 120.0)
            int(kind, 'batterySeconds', base .. '.batterySeconds', 30, 14400, 720)
            num(kind, 'zoomMax', base .. '.zoomMax', 1.0, 40.0, 4.0)
            int(kind, 'health', base .. '.health', 1, 5000, 600)
            bool(kind, 'ignoreNoFly', base .. '.ignoreNoFly', false)
            if kind.sensing == nil then kind.sensing = true end
            bool(kind, 'sensing', base .. '.sensing', true)
            if kind.acro == nil then kind.acro = false end
            bool(kind, 'acro', base .. '.acro', false)
            if type(kind.features) ~= 'table' then problem(base .. '.features', 'a table', kind.features, 'all off'); kind.features = {} end
            for _, feature in ipairs(KIND_FEATURES) do
                if kind.features[feature] == nil then kind.features[feature] = false end
                bool(kind.features, feature, base .. '.features.' .. feature, false)
                kind.features[feature] = kind.features[feature] and features[feature]
            end
            if kind.features.follow and not kind.features.track then kind.features.follow = false end
            if not features.payload then kind.payload = false end
            local payload = kind.payload
            if payload ~= false then
                if type(payload) ~= 'table' or (payload.kind ~= 'taser' and payload.kind ~= 'explosive') then
                    problem(base .. '.payload', 'false or a taser or explosive payload', payload, 'no payload'); kind.payload = false
                elseif payload.kind == 'taser' then
                    int(payload, 'count', base .. '.payload.count', 1, 50, 3)
                    num(payload, 'cooldown', base .. '.payload.cooldown', 0.5, 60.0, 4.0)
                    num(payload, 'range', base .. '.payload.range', 2.0, 100.0, 30.0)
                else
                    num(payload, 'armSeconds', base .. '.payload.armSeconds', 0.0, 10.0, 1.0)
                    num(payload, 'impactSpeed', base .. '.payload.impactSpeed', 1.0, 60.0, 9.0)
                    int(payload, 'explosion', base .. '.payload.explosion', 0, 82, 2)
                    num(payload, 'scale', base .. '.payload.scale', 0.1, 5.0, 1.0)
                end
            end
            if type(kind.speeds) ~= 'table' then problem(base .. '.speeds', 'a table', kind.speeds, 'using the defaults'); kind.speeds = {} end
            for _, mode in ipairs(MODES) do
                if type(kind.speeds[mode]) ~= 'table' then
                    problem(base .. '.speeds.' .. mode, 'a table', kind.speeds[mode], 'using the defaults')
                    kind.speeds[mode] = {}
                end
                for field, limit in pairs(SPEED_LIMIT) do
                    if kind.speeds[mode][field] == nil then kind.speeds[mode][field] = SPEED_DEFAULT[mode][field] end
                    num(kind.speeds[mode], field, ('%s.speeds.%s.%s'):format(base, mode, field), limit[1], limit[2], SPEED_DEFAULT[mode][field])
                end
            end
        end
    end
    if next(config.types) == nil then problem('types', 'at least one drone type', nil, 'no drones are available') end

    local battery = section('battery', {})
    num(battery, 'rechargeMinutes', 'battery.rechargeMinutes', 0.0, 1440.0, 20.0)
    num(battery, 'minimumToLaunch', 'battery.minimumToLaunch', 0.0, 100.0, 5.0)
    num(battery, 'returnAt', 'battery.returnAt', 0.0, 100.0, 15.0)
    num(battery, 'taserShot', 'battery.taserShot', 0.0, 25.0, 1.5)
    if type(battery.drain) ~= 'table' then problem('battery.drain', 'a table', battery.drain, 'using the defaults'); battery.drain = {} end
    for field, default in pairs({ hover = 0.8, cine = 0.9, normal = 1.0, sport = 1.5, boost = 1.8, acro = 1.4, spotlight = 0.3, thermal = 0.15, night = 0.08, track = 0.06 }) do
        if battery.drain[field] == nil then battery.drain[field] = default end
        num(battery.drain, field, 'battery.drain.' .. field, 0.0, 10.0, default)
    end
    if battery.packs == nil and battery.spareItem ~= nil then
        if battery.spareItem == false then battery.packs = {}
        elseif name(battery.spareItem) then battery.packs = { [battery.spareItem] = { capacity = 1.0 } }
        else
            problem('battery.spareItem', 'an item name or false', battery.spareItem, 'using drone_battery')
            battery.packs = { drone_battery = { capacity = 1.0 } }
        end
    end
    if type(battery.packs) ~= 'table' then
        problem('battery.packs', 'a table of battery items', battery.packs, 'using drone_battery'); battery.packs = { drone_battery = { capacity = 1.0 } }
    end
    for item, pack in pairs(battery.packs) do
        if not name(item) or type(pack) ~= 'table' then
            problem('battery.packs', '{ item_name = { capacity = 1.0 } }', item, 'skipping it'); battery.packs[item] = nil
        elseif items[item] then
            problem('battery.packs.' .. item, 'an item that is not also a drone', item, 'skipping it'); battery.packs[item] = nil
        else
            num(pack, 'capacity', 'battery.packs.' .. item .. '.capacity', 0.1, 10.0, 1.0)
        end
    end

    local signal = section('signal', {})
    num(signal, 'fadeStart', 'signal.fadeStart', 0.0, 0.99, 0.7)
    num(signal, 'obstructionPenalty', 'signal.obstructionPenalty', 0.0, 1.0, 0.35)
    num(signal, 'lostGraceSeconds', 'signal.lostGraceSeconds', 0.0, 30.0, 3.0)
    oneOf(signal, 'onLost', 'signal.onLost', { 'return', 'hover', 'land' }, 'return')

    local flight = section('flight', {})
    if flight.launchHeight == nil then flight.launchHeight = 1.0 end
    num(flight, 'launchHeight', 'flight.launchHeight', 0.3, 3.0, 1.0)
    num(flight, 'takeoffHeight', 'flight.takeoffHeight', 0.3, 10.0, 1.2)
    num(flight, 'crashSpeed', 'flight.crashSpeed', 2.0, 100.0, 13.0)
    num(flight, 'landingSpeed', 'flight.landingSpeed', 0.3, 5.0, 1.2)
    num(flight, 'returnAltitude', 'flight.returnAltitude', 5.0, 300.0, 30.0)
    num(flight, 'returnSpeed', 'flight.returnSpeed', 2.0, 40.0, 10.0)
    oneOf(flight, 'leave', 'flight.leave', { 'hover', 'land', 'return' }, 'hover')
    bool(flight, 'pilotHitDropsLink', 'flight.pilotHitDropsLink', true)

    if config.launch == nil then config.launch = {} end
    local launch = section('launch', {})
    if launch.enabled == nil then launch.enabled = true end
    bool(launch, 'enabled', 'launch.enabled', true)
    if type(launch.anim) ~= 'table' or type(launch.anim.dict) ~= 'string' or type(launch.anim.name) ~= 'string' then
        if launch.anim ~= nil then problem('launch.anim', 'a { dict, name } table', launch.anim, 'using the heist drone toss') end
        launch.anim = { dict = 'anim_heist@hs3f@ig4_drone@male@', name = 'enter', flag = 48 }
    end
    if launch.anim.flag == nil then launch.anim.flag = 48 end
    int(launch.anim, 'flag', 'launch.anim.flag', 0, 1023, 48)
    if launch.grab == nil then launch.grab = 0.2 end
    if launch.release == nil then launch.release = 0.55 end
    num(launch, 'grab', 'launch.grab', 0.0, 0.9, 0.2)
    num(launch, 'release', 'launch.release', 0.05, 0.95, 0.55)
    if launch.release <= launch.grab then
        problem('launch.release', 'a phase after launch.grab', launch.release, 'using launch.grab + 0.05')
        launch.release = launch.grab + 0.05
    end
    if type(launch.hold) ~= 'table' then
        if launch.hold ~= nil then problem('launch.hold', 'a { bone, forward, up } table', launch.hold, 'using the left hand') end
        launch.hold = {}
    end
    if launch.hold.bone == nil then launch.hold.bone = 60309 end
    if launch.hold.forward == nil then launch.hold.forward = 0.1 end
    if launch.hold.up == nil then launch.hold.up = 0.0 end
    int(launch.hold, 'bone', 'launch.hold.bone', 0, 65535, 60309)
    num(launch.hold, 'forward', 'launch.hold.forward', -1.0, 1.0, 0.1)
    num(launch.hold, 'up', 'launch.hold.up', -1.0, 1.0, 0.0)
    if launch.lift == nil then launch.lift = 2.2 end
    if launch.maxSpeed == nil then launch.maxSpeed = 5.0 end
    if launch.watch == nil then launch.watch = 0.6 end
    if launch.push == nil then launch.push = 1.5 end
    if launch.clearance == nil then launch.clearance = 0.3 end
    num(launch, 'lift', 'launch.lift', 0.0, 8.0, 2.2)
    num(launch, 'push', 'launch.push', 0.0, 8.0, 1.5)
    num(launch, 'maxSpeed', 'launch.maxSpeed', 0.5, 12.0, 5.0)
    num(launch, 'clearance', 'launch.clearance', 0.15, 3.0, 0.3)
    num(launch, 'watch', 'launch.watch', 0.0, 3.0, 0.6)

    local camera = section('camera', {})
    if type(camera.offset) ~= 'table' then camera.offset = {} end
    num(camera.offset, 'x', 'camera.offset.x', -2.0, 2.0, 0.0)
    num(camera.offset, 'y', 'camera.offset.y', -2.0, 2.0, 0.24)
    num(camera.offset, 'z', 'camera.offset.z', -2.0, 2.0, -0.045)
    if type(camera.chase) ~= 'table' then camera.chase = {} end
    num(camera.chase, 'distance', 'camera.chase.distance', 0.5, 20.0, 2.4)
    num(camera.chase, 'height', 'camera.chase.height', -5.0, 10.0, 0.7)
    num(camera, 'fov', 'camera.fov', 20.0, 100.0, 70.0)
    num(camera, 'gimbalMin', 'camera.gimbalMin', -90.0, 0.0, -90.0)
    num(camera, 'gimbalMax', 'camera.gimbalMax', 0.0, 45.0, 20.0)

    local spot = section('spotlight', {})
    num(spot, 'distance', 'spotlight.distance', 1.0, 300.0, 60.0)
    num(spot, 'brightness', 'spotlight.brightness', 0.1, 100.0, 8.0)
    num(spot, 'hardness', 'spotlight.hardness', 0.0, 100.0, 3.0)
    num(spot, 'radius', 'spotlight.radius', 1.0, 90.0, 13.0)
    num(spot, 'falloff', 'spotlight.falloff', 1.0, 300.0, 40.0)
    if spot.onAtLaunch == nil then spot.onAtLaunch = false end
    bool(spot, 'onAtLaunch', 'spotlight.onAtLaunch', false)
    if spot.slew == nil then spot.slew = 120.0 end
    num(spot, 'slew', 'spotlight.slew', 10.0, 720.0, 120.0)
    if spot.traverse == nil then spot.traverse = {} end
    if type(spot.traverse) ~= 'table' then problem('spotlight.traverse', 'a table', spot.traverse, 'using -90 to -10'); spot.traverse = {} end
    if spot.traverse.min == nil then spot.traverse.min = -90.0 end
    if spot.traverse.max == nil then spot.traverse.max = -10.0 end
    num(spot.traverse, 'min', 'spotlight.traverse.min', -90.0, 0.0, -90.0)
    num(spot.traverse, 'max', 'spotlight.traverse.max', spot.traverse.min, 20.0, -10.0)
    local colour = spot.colour
    if type(colour) ~= 'table' or not D.integer(colour[1], 0, 255) or not D.integer(colour[2], 0, 255) or not D.integer(colour[3], 0, 255) then
        problem('spotlight.colour', 'three whole numbers from 0 to 255', colour, 'using white'); spot.colour = { 255, 244, 225 }
    end
    if spot.volumetric == nil then spot.volumetric = {} end
    if type(spot.volumetric) ~= 'table' then
        problem('spotlight.volumetric', 'a table', spot.volumetric, 'no light beam'); spot.volumetric = { enabled = false }
    end
    local volume = spot.volumetric
    if volume.enabled == nil then volume.enabled = true end
    bool(volume, 'enabled', 'spotlight.volumetric.enabled', true)
    for field, limit in pairs(VOLUME_DEFAULT) do
        if volume[field] == nil then volume[field] = limit[1] end
        num(volume, field, 'spotlight.volumetric.' .. field, limit[2], limit[3], limit[1])
    end

    if config.track == nil then config.track = {} end
    local track = section('track', {})
    if track.hideGrace == nil then track.hideGrace = 1.5 end
    num(track, 'hideGrace', 'track.hideGrace', 0.0, 10.0, 1.5)
    if track.orbitMinRadius == nil then track.orbitMinRadius = 3.0 end
    num(track, 'orbitMinRadius', 'track.orbitMinRadius', 0.5, 50.0, 3.0)

    if config.cinematic == nil then config.cinematic = {} end
    local cine = section('cinematic', {})
    if cine.speedMode == nil then cine.speedMode = 'cine' end
    if cine.speedMode ~= false then oneOf(cine, 'speedMode', 'cinematic.speedMode', MODES, 'cine') end
    for field, limit in pairs(CINE_DEFAULT) do
        if cine[field] == nil then cine[field] = limit[1] end
        num(cine, field, 'cinematic.' .. field, limit[2], limit[3], limit[1])
    end
    for group, fields in pairs(CINE_SHOTS) do
        if cine[group] == nil then cine[group] = {} end
        if type(cine[group]) ~= 'table' then problem('cinematic.' .. group, 'a table', cine[group], 'using the defaults'); cine[group] = {} end
        for field, limit in pairs(fields) do
            if cine[group][field] == nil then cine[group][field] = limit[1] end
            num(cine[group], field, ('cinematic.%s.%s'):format(group, field), limit[2], limit[3], limit[1])
        end
    end
    cine.follow.distance = math.max(cine.follow.distance, cine.minDistance)
    cine.orbit.radius = math.max(cine.orbit.radius, cine.minDistance)
    if cine.filmMe == nil then cine.filmMe = true end
    bool(cine, 'filmMe', 'cinematic.filmMe', true)

    if config.acro == nil then config.acro = {} end
    local acro = section('acro', {})
    for field, limit in pairs(ACRO_DEFAULT) do
        if acro[field] == nil then acro[field] = limit[1] end
        num(acro, field, 'acro.' .. field, limit[2], limit[3], limit[1])
    end
    if acro.controls == nil then acro.controls = 'glide' end
    oneOf(acro, 'controls', 'acro.controls', { 'glide', 'manual' }, 'glide')

    if config.sensing == nil then config.sensing = {} end
    local sensing = section('sensing', {})
    for field, limit in pairs({ margin = { 0.7, 0.2, 5.0 }, radius = { 0.3, 0.05, 1.5 }, lookahead = { 0.6, 0.1, 3.0 } }) do
        if sensing[field] == nil then sensing[field] = limit[1] end
        num(sensing, field, 'sensing.' .. field, limit[2], limit[3], limit[1])
    end

    local lookup = section('lookup', {})
    num(lookup, 'range', 'lookup.range', 5.0, 1000.0, 200.0)
    bool(lookup, 'plates', 'lookup.plates', true)
    bool(lookup, 'people', 'lookup.people', true)
    bool(lookup, 'showStandaloneNames', 'lookup.showStandaloneNames', false)

    local swap = section('swap', {})
    if swap.enabled == nil then swap.enabled = true end
    bool(swap, 'enabled', 'swap.enabled', true)
    if swap.camera == nil then swap.camera = true end
    bool(swap, 'camera', 'swap.camera', true)
    if swap.reach == nil then swap.reach = 3.0 end
    num(swap, 'reach', 'swap.reach', 1.0, 10.0, 3.0)
    if swap.kneel == nil then swap.kneel = 0.55 end
    num(swap, 'kneel', 'swap.kneel', 0.3, 1.2, 0.55)
    local SWAP_ANIM = {
        enter = { dict = 'amb@medic@standing@tendtodead@enter', name = 'enter' },
        base = { dict = 'amb@medic@standing@tendtodead@base', name = 'base' },
        exit = { dict = 'amb@medic@standing@tendtodead@exit', name = 'exit' },
    }
    if type(swap.anim) ~= 'table' then
        if swap.anim ~= nil then problem('swap.anim', 'an { enter, base, exit } table', swap.anim, 'kneeling at the drone') end
        swap.anim = {}
    end
    for _, stage in ipairs({ 'enter', 'base', 'exit' }) do
        local a = swap.anim[stage]
        if type(a) ~= 'table' or type(a.dict) ~= 'string' or type(a.name) ~= 'string' then
            if a ~= nil then problem('swap.anim.' .. stage, 'a { dict, name } table', a, 'kneeling at the drone') end
            swap.anim[stage] = SWAP_ANIM[stage]
        end
    end

    local pickup = section('pickup', {})
    num(pickup, 'distance', 'pickup.distance', 1.0, 6.0, 2.2)
    bool(pickup, 'othersCanSeize', 'pickup.othersCanSeize', true)
    bool(pickup, 'loseItemWhenDestroyed', 'pickup.loseItemWhenDestroyed', true)
    if not rule(pickup.seize) then
        problem('pickup.seize', 'false or { jobs = { name = grade }, duty = true }', pickup.seize, 'police only')
        pickup.seize = { jobs = { police = 0 }, duty = true }
    end

    local pilot = section('pilot', {})
    if type(pilot.anim) ~= 'table' or type(pilot.anim.dict) ~= 'string' or type(pilot.anim.name) ~= 'string' then
        problem('pilot.anim', 'a { dict, name } table', pilot.anim, 'using the tablet idle')
        pilot.anim = { dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@idle_a', name = 'idle_a', flag = 49 }
    end
    int(pilot.anim, 'flag', 'pilot.anim.flag', 0, 1023, 49)
    if pilot.prop ~= false then
        local prop = pilot.prop
        if type(prop) ~= 'table' or not name(prop.model) or not D.integer(prop.bone, 0, 65535)
            or type(prop.offset) ~= 'table' or type(prop.rotation) ~= 'table' then
            problem('pilot.prop', 'false or a { model, bone, offset, rotation } table', prop, 'using the tablet')
            pilot.prop = { model = 'prop_cs_tablet', bone = 28422, offset = { x = -0.05, y = 0.0, z = 0.0 }, rotation = { x = 0.0, y = -90.0, z = 0.0 } }
        else
            for _, axis in ipairs({ 'x', 'y', 'z' }) do
                num(prop.offset, axis, 'pilot.prop.offset.' .. axis, -2.0, 2.0, 0.0)
                num(prop.rotation, axis, 'pilot.prop.rotation.' .. axis, -360.0, 360.0, 0.0)
            end
        end
    end
    bool(pilot, 'othersSeeTablet', 'pilot.othersSeeTablet', true)

    if type(config.noFly) ~= 'table' then problem('noFly', 'a list of zones', config.noFly, 'no zones'); config.noFly = {} end
    for index = #config.noFly, 1, -1 do
        local zone = config.noFly[index]
        if type(zone) ~= 'table' or not D.finite(zone.x) or not D.finite(zone.y) or not D.finite(zone.radius) or zone.radius <= 0 then
            problem(('noFly[%d]'):format(index), '{ name, x, y, radius }', zone, 'removing it'); table.remove(config.noFly, index)
        elseif type(zone.name) ~= 'string' then zone.name = ('Zone %d'):format(index) end
    end

    local keys = section('keys', {})
    if not (type(keys.pickup) == 'string' and (keys.pickup == '' or keys.pickup:match('^[%w_]+$')) and #keys.pickup <= 32) then
        problem('keys.pickup', 'a key name', keys.pickup, 'using E'); keys.pickup = 'E'
    end

    local controls = section('controls', {})
    for _, device in ipairs({ 'keyboard', 'pad' }) do
        if type(controls[device]) ~= 'table' then controls[device] = {} end
        for _, key in ipairs(CONTROL_KEYS) do
            if controls[device][key] == nil then controls[device][key] = CONTROL_DEFAULT[device][key] end
            int(controls[device], key, ('controls.%s.%s'):format(device, key), 0, 360, CONTROL_DEFAULT[device][key])
        end
    end

    bool(config, 'hideHud', 'hideHud', true)
    local rotors = section('rotors', { idle = 0.55, hover = 0.8, full = 1.0 })
    num(rotors, 'idle', 'rotors.idle', 0.0, 1.0, 0.55)
    num(rotors, 'hover', 'rotors.hover', 0.0, 1.0, 0.8)
    num(rotors, 'full', 'rotors.full', 0.0, 1.0, 1.0)

    local audit = section('audit', {})
    for _, key in ipairs({ 'deploys', 'destroyed', 'seized', 'payloads', 'staff' }) do
        if audit[key] == nil then audit[key] = false end
        bool(audit, key, 'audit.' .. key, false)
    end

    local sounds = section('sounds', {})
    for _, key in ipairs({ 'start', 'toggle', 'warning', 'lost', 'release', 'latch', 'led' }) do
        local sound = sounds[key]
        if sound ~= false and (type(sound) ~= 'table' or type(sound.name) ~= 'string' or type(sound.set) ~= 'string') then
            problem('sounds.' .. key, 'false or { name, set }', sound, 'silent'); sounds[key] = false
        end
    end

    if not quiet then
        for _, line in ipairs(problems) do print(('^3[%s]^0 %s'):format(GetCurrentResourceName(), line)) end
    end
    return problems
end

V.run(Config)
