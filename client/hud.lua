DroneHud = {}
local H = DroneHud
local ready, open, opening, last, legend = false, false, nil, nil, 0

local function send(action, data)
    if ready then SendNUIMessage({ action = action, data = data }) end
end

local function round(value, step)
    return math.floor(value / step + 0.5) * step
end

local function signature(state)
    local target = state.target
    local payload = state.payload
    local warning = state.warning
    local cine = state.cine
    return table.concat({
        state.mode, tostring(state.boost), state.status, round(state.battery, 1), round(state.remaining, 1), state.signal,
        round(state.heading, 1), state.home and round(state.home, 1) or '-', round(state.altitude, 0.1), round(state.distance, 1),
        round(state.hspeed, 0.1), round(state.vspeed, 0.1), state.throttle or '-', round(state.gimbal, 1), round(state.zoom, 0.1), state.vision, state.view,
        tostring(state.light), round(state.lightPitch, 1), state.range and round(state.range, 1) or '-', state.lock or '-',
        state.trip and round(state.trip, 1) or '-', state.reserve and round(state.reserve, 1) or '-', state.ahead and round(state.ahead, 0.1) or '-',
        state.place and (state.place.street .. '/' .. state.place.area) or '-',
        target and (target.kind .. (target.title or '') .. (target.plate or '') .. (target.owner or '') .. (target.detail or '') .. round(target.speed or 0, 0.5)
            .. tostring(target.hidden) .. round(target.range or 0, 1)) or '-',
        payload and (payload.kind .. payload.count .. tostring(payload.ready) .. tostring(payload.armed)) or '-',
        warning and (warning.code .. warning.severity) or '-',
        cine and (cine.shot .. tostring(cine.self) .. cine.frame .. (cine.toast or '-')) or '-',
    }, '|')
end

function H.open(data)
    opening, open, last = data, true, nil
    send('drone:open', data)
end

function H.state(state)
    if not open then return end
    local sig = signature(state)
    if sig == last then return end
    last = sig
    send('drone:state', state)
end

function H.legend(px)
    px = math.floor((tonumber(px) or 0) + 0.5)
    if px == legend then return end
    legend = px
    send('drone:legend', px)
end

function H.close()
    if not open then return end
    open, opening, last = false, nil, nil
    H.legend(0)
    send('drone:close', {})
end

RegisterNUICallback('ready', function(_, cb)
    ready = true
    cb({ ok = true })
    if open and opening then
        last = nil
        send('drone:open', opening)
        send('drone:legend', legend)
    end
end)
