local S, D, B = DroneServer, DroneDomain, Bridge
local RESOURCE = GetCurrentResourceName()

local function reply(src, text)
    if src == 0 then print(('[%s] %s'):format(RESOURCE, text))
    else TriggerClientEvent(RESOURCE .. ':operator', src, text) end
end

local function target(raw)
    local id = tonumber(raw)
    if not D.integer(id, 1, 65535) or not GetPlayerName(tostring(id)) then return nil end
    return id
end

RegisterCommand('drone_list', function(src)
    local lines = {}
    for id, session in pairs(S.sessions) do
        local kind = D.type(session.kind)
        lines[#lines + 1] = ('%d %s: %s %s %d%%'):format(id, GetPlayerName(tostring(id)) or '?', kind and kind.label or session.kind,
            session.state, math.floor(session.battery))
    end
    table.sort(lines)
    reply(src, #lines == 0 and 'no drones are out' or table.concat(lines, '\n'))
end, true)

RegisterCommand('drone_recall', function(src, args)
    local id = target(args[1])
    if not id then reply(src, 'usage: drone_recall <player id>'); return end
    if not S.sessions[id] then reply(src, ('player %d has no drone out'):format(id)); return end
    S.finish(id, 'staff')
    DroneAudit.log('staff', 'Drone recalled by staff', { Player = DroneAudit.actor(id), By = DroneAudit.actor(src) })
    reply(src, ('recalled player %d\'s drone'):format(id))
end, true)

RegisterCommand('drone_charge', function(src, args)
    local id = target(args[1])
    if not id then reply(src, 'usage: drone_charge <player id>'); return end
    local owner = B.identifier(id)
    if not owner then reply(src, 'that player has no identifier yet'); return end
    for _, drone in ipairs(S.fleet(id, owner)) do DroneBattery.store(drone.cell, 100.0, true) end
    local session = S.sessions[id]
    if session then
        session.battery, session.charged = 100.0, true
        DroneBattery.store(session.cell, 100.0, true)
        TriggerClientEvent(RESOURCE .. ':charged', id)
    end
    DroneAudit.log('staff', 'Drone batteries charged by staff', { Player = DroneAudit.actor(id), By = DroneAudit.actor(src) })
    reply(src, ('charged player %d\'s drone batteries'):format(id))
end, true)
