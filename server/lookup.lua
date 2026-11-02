local C, D, B, S = Config, DroneDomain, Bridge, DroneServer

local function trim(text) return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local function query(sql, params)
    if GetResourceState('oxmysql') ~= 'started' then return nil end
    local p, settled = promise.new(), false
    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value)
    end
    local success = pcall(function()
        exports.oxmysql:single(sql, params, function(row) settle(row or false) end)
    end)
    if not success then return nil end
    SetTimeout(3000, function() settle(false) end)
    local row = Citizen.Await(p)
    return row or nil
end

local function plateOwner(plate)
    if B.framework() == nil then return nil end
    local row = query('SELECT p.charinfo FROM player_vehicles v LEFT JOIN players p ON p.citizenid = v.citizenid WHERE TRIM(v.plate) = ? LIMIT 1', { plate })
    if not row or type(row.charinfo) ~= 'string' then return nil end
    local ok, info = pcall(json.decode, row.charinfo)
    if not ok or type(info) ~= 'table' or type(info.firstname) ~= 'string' then return nil end
    return ('%s %s'):format(info.firstname, info.lastname or '')
end

local function playerFor(ped)
    for _, raw in ipairs(GetPlayers()) do
        local id = tonumber(raw)
        if id and GetPlayerPed(id) == ped then return id end
    end
end

S.callback('lookup', function(src, data)
    local session = S.sessions[src]
    if not session or session.state ~= 'flying' then return S.fail('NOT_FLYING') end
    local kind = D.type(session.kind)
    if not kind.features.lookup then return S.fail('DENIED') end
    local netId = D.integer(data.netId, 1, 65535)
    if not netId then return S.fail('INVALID_REQUEST') end
    local target = NetworkGetEntityFromNetworkId(netId)
    if not target or target == 0 or not DoesEntityExist(target) then return S.fail('GONE') end
    if #(GetEntityCoords(target) - GetEntityCoords(session.entity)) > C.lookup.range then return S.fail('TOO_FAR') end

    local kindOf = GetEntityType(target)
    if kindOf == 2 and C.lookup.plates then
        local plate = trim(GetVehicleNumberPlateText(target))
        return S.ok({ plate = plate, owner = plate ~= '' and plateOwner(plate) or nil })
    elseif kindOf == 1 and C.lookup.people then
        local id = IsPedAPlayer(target) and playerFor(target) or nil
        if not id then return S.ok({ person = true }) end
        local name = B.characterName(id)
        local data_ = B.data(id)
        local job = data_ and data_.job and data_.job.label or nil
        return S.ok({ person = true, name = name, job = job })
    end
    return S.ok({})
end)
