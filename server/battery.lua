DroneBattery = {}
local D = DroneDomain
local saved = {}
local issued = 0

function DroneBattery.key(owner, kind, id)
    if id then return 'battery:drone:' .. id end
    return ('battery:%s:%s'):format(owner, kind)
end

function DroneBattery.newId(item)
    if type(item) == 'string' and item ~= '' then return item end
    issued = (issued + 1) % 0x10000
    return ('%x%04x%04x'):format(os.time(), math.random(0, 0xffff), issued)
end

function DroneBattery.drop(name)
    saved[name] = nil
    DeleteResourceKvp(name)
end

local function read(name)
    if saved[name] then return saved[name] end
    local entry
    local raw = GetResourceKvpString(name)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' and D.finite(decoded.level) and D.finite(decoded.at) then
            local capacity = D.finite(decoded.capacity) and decoded.capacity > 0.0 and decoded.capacity or 1.0
            entry = { level = D.clamp(decoded.level + 0.0, 0.0, 100.0), at = decoded.at, capacity = capacity, stored = math.floor(decoded.level) }
        end
    end
    entry = entry or { level = 100.0, at = os.time(), capacity = 1.0, stored = -1 }
    saved[name] = entry
    return entry
end

function DroneBattery.charge(name)
    local entry = read(name)
    return D.recharged(entry.level, math.max(0, os.time() - entry.at), entry.capacity)
end

function DroneBattery.capacity(name)
    return read(name).capacity
end

local function write(name, entry)
    entry.stored = math.floor(entry.level)
    SetResourceKvp(name, json.encode({ level = entry.level, at = entry.at, capacity = entry.capacity }))
end

function DroneBattery.store(name, level, force)
    local entry = read(name)
    entry.level = D.clamp(level + 0.0, 0.0, 100.0)
    entry.at = os.time()
    if force or math.floor(entry.level) ~= entry.stored then write(name, entry) end
end

function DroneBattery.fit(name, capacity)
    local entry = read(name)
    entry.level, entry.at, entry.capacity = 100.0, os.time(), capacity
    write(name, entry)
end

function DroneBattery.fitPack(name, capacity, level)
    local entry = read(name)
    entry.level, entry.at, entry.capacity = D.clamp((tonumber(level) or 100.0) + 0.0, 0.0, 100.0), os.time(), capacity
    write(name, entry)
end

local Pack = {}
DroneBattery.pack = Pack

function Pack.charge(metadata, capacity)
    local meta = type(metadata) == 'table' and metadata or {}
    if not (D.finite(meta.charge) and D.finite(meta.chargedAt)) then return 100.0 end
    return D.recharged(D.clamp(meta.charge, 0.0, 100.0), math.max(0, os.time() - meta.chargedAt), capacity)
end

function Pack.describe(level, capacity)
    if level >= 99.5 then return L('item.charged') end
    local minutes = Config.battery.rechargeMinutes * capacity * (100.0 - level) / 100.0
    return L('item.charging', { level = math.floor(level), minutes = math.max(1, math.ceil(minutes)) })
end

function Pack.metadata(level, capacity, base)
    local meta = {}
    for key, value in pairs(type(base) == 'table' and base or {}) do meta[key] = value end
    level = D.clamp(level + 0.0, 0.0, 100.0)
    meta.charge = math.floor(level * 10.0 + 0.5) / 10.0
    meta.chargedAt = os.time()
    meta.durability = math.max(1, math.floor(level))
    meta.description = Pack.describe(level, capacity)
    return meta
end

function Pack.item(capacity)
    local best, gap
    for item, pack in pairs(Config.battery.packs) do
        local d = math.abs(pack.capacity - (capacity or 1.0))
        if not best or d < gap - 0.0001 or (math.abs(d - gap) <= 0.0001 and #item < #best) then best, gap = item, d end
    end
    return best
end

function Pack.list(src, item)
    local pack = Config.battery.packs[item]
    local found = Bridge.drones(src, item)
    if not pack or not found then return nil end
    for _, entry in ipairs(found) do entry.charge = Pack.charge(entry.metadata, pack.capacity) end
    return found
end

function Pack.refresh(src, item, entry)
    local meta = entry.metadata
    if not (D.finite(meta.charge) and D.finite(meta.chargedAt)) or meta.charge >= 100.0 then return end
    local capacity = Config.battery.packs[item].capacity
    local level = Pack.charge(meta, capacity)
    if math.floor(level) == meta.durability and level < 99.5 then return end
    local fresh = Pack.metadata(level >= 99.5 and 100.0 or level, capacity, meta)
    Bridge.setMetadata(src, entry.slot, item, fresh)
end
