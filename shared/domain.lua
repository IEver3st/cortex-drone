DroneDomain = {}
local D = DroneDomain

function D.finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function D.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function D.integer(value, low, high)
    local number = math.tointeger(value)
    if not number then return nil end
    if (low and number < low) or (high and number > high) then return nil end
    return number
end

function D.typeByItem(item)
    for key, kind in pairs(Config.types) do
        if kind.item == item then return key, kind end
    end
end

function D.type(key)
    if type(key) ~= 'string' then return nil end
    return Config.types[key]
end

function D.signal(distance, range, obstructed)
    local fadeStart = range * Config.signal.fadeStart
    local quality = 1.0
    if distance >= range then
        quality = 0.0
    elseif distance > fadeStart then
        quality = 1.0 - (distance - fadeStart) / (range - fadeStart)
    end
    if obstructed then quality = quality - Config.signal.obstructionPenalty end
    return D.clamp(quality, 0.0, 1.0)
end

function D.bars(quality)
    if quality <= 0.0 then return 0 end
    return D.clamp(math.ceil(quality * 5.0 - 0.0001), 1, 5)
end

function D.noFly(x, y)
    for _, zone in ipairs(Config.noFly) do
        local dx, dy = x - zone.x, y - zone.y
        if dx * dx + dy * dy <= zone.radius * zone.radius then return zone end
    end
end

function D.flightSeconds(kind, capacity)
    return kind.batterySeconds * (D.finite(capacity) and capacity > 0.0 and capacity or 1.0)
end

local ACCESSORIES = { 'spotlight', 'thermal', 'night', 'track' }

function D.accessoryDrain(flags)
    local drain, factor = Config.battery.drain, 0.0
    for _, key in ipairs(ACCESSORIES) do
        if flags[key] then factor = factor + (drain[key] or 0.0) end
    end
    return factor
end

function D.drainPerSecond(kind, flags, capacity)
    local drain = Config.battery.drain
    local factor = 0.0
    if flags.motors ~= false then
        factor = drain.normal
        if flags.hover then factor = drain.hover
        elseif flags.boost then factor = drain.boost
        elseif flags.mode and drain[flags.mode] then factor = drain[flags.mode] end
        if flags.load then factor = factor * D.clamp(flags.load, 0.3, 2.0) end
    end
    return 100.0 / D.flightSeconds(kind, capacity) * (factor + D.accessoryDrain(flags))
end

function D.minimumDrainPerSecond(kind, capacity, light)
    local drain = Config.battery.drain
    return 100.0 / D.flightSeconds(kind, capacity) * (drain.hover + (light and drain.spotlight or 0.0))
end

function D.recharged(level, seconds, capacity)
    local minutes = Config.battery.rechargeMinutes * (D.finite(capacity) and capacity > 0.0 and capacity or 1.0)
    if minutes <= 0 then return 100.0 end
    return D.clamp(level + seconds / (minutes * 60.0) * 100.0, 0.0, 100.0)
end
