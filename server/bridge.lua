Bridge = {}
local B = Bridge
local RESOURCE = GetCurrentResourceName()
local qb

local function started(name)
    local state = GetResourceState(name)
    return state == 'started' or state == 'starting'
end

local function qbCore()
    if not qb and started('qb-core') then
        local success, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        qb = success and core or nil
    end
    return qb
end

function B.reset() qb = nil end

function B.framework()
    if started('qbx_core') then return 'qbx' end
    if started('qb-core') and qbCore() then return 'qb' end
end

function B.inventory()
    if started('ox_inventory') then return 'ox' end
    if B.framework() == 'qb' then return 'qb' end
end

function B.player(src)
    local kind = B.framework()
    if kind == 'qbx' then
        local success, value = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        return success and value or nil
    elseif kind == 'qb' then
        local success, value = pcall(function() return qb.Functions.GetPlayer(src) end)
        return success and value or nil
    end
end

function B.data(src)
    local object = B.player(src)
    return object and object.PlayerData or nil
end

function B.identifier(src)
    local data = B.data(src)
    if data and type(data.citizenid) == 'string' then return 'cid:' .. data.citizenid end
    local license = GetPlayerIdentifierByType(tostring(src), 'license')
    if license then return license end
    return nil
end

function B.actor(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return nil end
    local data = B.data(src)
    local meta = data and data.metadata or {}
    if meta.isdead or meta.inlaststand or meta.ishandcuffed then return nil end
    return ped, data
end

function B.allowed(src, rule, data)
    if not rule then return true end
    if not B.framework() then return true end
    data = data or B.data(src)
    local job = data and data.job
    if type(job) ~= 'table' then return false end
    local minimum = rule.jobs[job.name]
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade or 0
    return minimum ~= nil and (tonumber(grade) or 0) >= minimum and (not rule.duty or job.onduty == true)
end

function B.itemsRequired()
    if Config.requireItem == 'auto' then return B.inventory() ~= nil end
    return Config.requireItem == true
end

function B.count(src, item)
    local inventory = B.inventory()
    if inventory == 'ox' then
        local success, amount, reason = pcall(function() return exports.ox_inventory:GetItemCount(src, item) end)
        if not success or type(amount) ~= 'number' then
            print(('^3[%s]^0 ox_inventory:GetItemCount(%s, %s) failed: %s'):format(RESOURCE, src, item, tostring(success and reason or amount)))
            return nil
        end
        return amount
    elseif inventory == 'qb' then
        local object = B.player(src)
        if not object then return nil end
        local success, found = pcall(function() return object.Functions.GetItemByName(item) end)
        if not success then return nil end
        return type(found) == 'table' and (tonumber(found.amount) or 0) or 0
    end
end

function B.remove(src, item, amount, slot, metadata)
    local inventory = B.inventory()
    if inventory == 'ox' then
        local success, result = pcall(function() return exports.ox_inventory:RemoveItem(src, item, amount or 1, metadata, slot) end)
        return success and result == true
    elseif inventory == 'qb' then
        local object = B.player(src)
        if not object then return false end
        local success, result = pcall(function() return object.Functions.RemoveItem(item, amount or 1, slot) end)
        return success and result ~= false
    end
    return false
end

function B.add(src, item, amount, metadata)
    local inventory = B.inventory()
    if inventory == 'ox' then
        local success, result = pcall(function()
            if not exports.ox_inventory:CanCarryItem(src, item, amount or 1, metadata) then return false end
            return exports.ox_inventory:AddItem(src, item, amount or 1, metadata)
        end)
        return success and result ~= false and result ~= nil
    elseif inventory == 'qb' then
        local object = B.player(src)
        if not object then return false end
        local success, result = pcall(function() return object.Functions.AddItem(item, amount or 1, nil, metadata) end)
        return success and result ~= false
    end
    return false
end

B.ID = 'droneId'

local function details(value)
    return type(value) == 'table' and value or {}
end

function B.identity(entry)
    return entry.metadata[B.ID] or entry.item
end

function B.drones(src, item)
    local inventory = B.inventory()
    local found = {}
    if inventory == 'ox' then
        local success, slots = pcall(function() return exports.ox_inventory:Search(src, 'slots', item) end)
        if not success or type(slots) ~= 'table' then return nil end
        for _, entry in pairs(slots) do
            if type(entry) == 'table' and entry.slot then found[#found + 1] = { slot = entry.slot, item = entry.id, metadata = details(entry.metadata) } end
        end
    elseif inventory == 'qb' then
        local data = B.data(src)
        if not data then return nil end
        for slot, entry in pairs(details(data.items)) do
            local at = type(entry) == 'table' and math.tointeger(entry.slot or slot)
            if at and entry.name == item then found[#found + 1] = { slot = at, metadata = details(entry.info) } end
        end
    else
        return nil
    end
    table.sort(found, function(a, b) return a.slot < b.slot end)
    return found
end

function B.tag(src, item, slot, id)
    local inventory = B.inventory()
    if inventory == 'ox' then
        local success, result = pcall(function()
            local entry = exports.ox_inventory:GetSlot(src, slot)
            if type(entry) ~= 'table' or entry.name ~= item then return nil end
            local current = details(entry.metadata)
            if current[B.ID] then return current[B.ID] end
            local metadata = {}
            for key, value in pairs(current) do metadata[key] = value end
            metadata[B.ID] = id
            exports.ox_inventory:SetMetadata(src, slot, metadata)
            local check = exports.ox_inventory:GetSlot(src, slot)
            return type(check) == 'table' and details(check.metadata)[B.ID] or nil
        end)
        return success and result or nil
    elseif inventory == 'qb' then
        local object = B.player(src)
        local items = object and object.PlayerData.items
        local entry = type(items) == 'table' and items[slot]
        if type(entry) ~= 'table' or entry.name ~= item then return nil end
        if type(entry.info) ~= 'table' then entry.info = {} end
        if entry.info[B.ID] then return entry.info[B.ID] end
        entry.info[B.ID] = id
        local success = pcall(function() object.Functions.SetPlayerData('items', items) end)
        return success and id or nil
    end
end

function B.setMetadata(src, slot, item, metadata)
    local inventory = B.inventory()
    if inventory == 'ox' then
        local success, result = pcall(function()
            local entry = exports.ox_inventory:GetSlot(src, slot)
            if type(entry) ~= 'table' or entry.name ~= item then return false end
            exports.ox_inventory:SetMetadata(src, slot, metadata)
            return true
        end)
        return success and result == true
    elseif inventory == 'qb' then
        local object = B.player(src)
        local items = object and object.PlayerData.items
        local entry = type(items) == 'table' and items[slot]
        if type(entry) ~= 'table' or entry.name ~= item then return false end
        entry.info = metadata
        return pcall(function() object.Functions.SetPlayerData('items', items) end)
    end
    return false
end

function B.removeDrone(src, item, id)
    if not id then return B.remove(src, item, 1) end
    for _, entry in ipairs(B.drones(src, item) or {}) do
        if B.identity(entry) == id then return B.remove(src, item, 1, entry.slot, entry.metadata) end
    end
    return false
end

function B.characterName(src)
    local data = B.data(src)
    local info = data and data.charinfo
    if type(info) == 'table' and type(info.firstname) == 'string' then
        return ('%s %s'):format(info.firstname, info.lastname or '')
    end
    if B.framework() == nil and Config.lookup.showStandaloneNames then return GetPlayerName(src) end
end

function B.notify(src, key, kind, vars)
    TriggerClientEvent('cortex-drone:notify', src, key, kind or 'error', vars)
end

local bound = {}

function B.registerItems(use)
    local kind = B.framework()
    if not kind then return end
    local canUse = kind == 'qbx' and function(name) return exports.qbx_core:CanUseItem(name) end
        or function(name) return qb.Functions.CanUseItem(name) end
    local create = kind == 'qbx' and function(name) exports.qbx_core:CreateUseableItem(name, function(src, item) use(src, name, item) end) end
        or function(name) qb.Functions.CreateUseableItem(name, function(src, item) use(src, name, item) end) end
    local names = {}
    for _, drone in pairs(Config.types) do names[#names + 1] = drone.item end
    for pack in pairs(Config.battery.packs) do names[#names + 1] = pack end
    for _, name in ipairs(names) do
        if not bound[name] then
            local success, owner = pcall(canUse, name)
            local ours = GetResourceKvpString('usable:' .. name) == '1'
            if success and owner and not ours then
                print(('^3[%s]^0 %s is already usable through another resource; leaving it alone'):format(RESOURCE, name))
            elseif success and pcall(create, name) then
                SetResourceKvp('usable:' .. name, '1')
                bound[name] = kind
            end
        end
    end
end

function B.releaseItems()
    if not started('qbx_core') then return end
    for name, owner in pairs(bound) do
        if owner == 'qbx' then
            pcall(function() exports.qbx_core:CreateUseableItem(name, nil) end)
            DeleteResourceKvp('usable:' .. name)
        end
    end
    bound = {}
end

function B.clearBound() bound = {} end
