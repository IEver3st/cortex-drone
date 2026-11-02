Cinematic = {}
local CI = Cinematic
local C, D, U = Config, DroneDomain, DroneUtil

CI.order = { 'track', 'follow', 'orbit', 'dronie', 'rocket', 'helix' }
CI.auto = { dronie = true, rocket = true, helix = true }

local NEXT = {}
for index, name in ipairs(CI.order) do NEXT[name] = CI.order[index % #CI.order + 1] end

function CI.next(name) return NEXT[name] or 'track' end

local function flat(v) return vector3(v.x, v.y, 0.0) end

local function unit(v, fallback)
    local length = #v
    if length < 0.05 then return fallback end
    return v / length
end

local function bearing(heading)
    local h = math.rad(heading)
    return vector3(-math.sin(h), math.cos(h), 0.0)
end

local function eased(remaining, span)
    return D.clamp(remaining / span, 0.2, 1.0)
end

local function facing(shot, subject, dt)
    local want
    if subject.vehicle then
        want = subject.heading
    else
        local v = flat(subject.vel)
        if #v > 0.6 then want = U.heading(v.x, v.y) end
    end
    if not shot.facing then
        shot.facing = want or subject.heading
    elseif want then
        shot.facing = (shot.facing + U.angleDelta(shot.facing, want) * math.min(1.0, dt * 1.5)) % 360.0
    end
    return shot.facing
end

local function rise(shot, hidden, dt)
    local M = C.cinematic
    local now = U.now()
    shot.rise = shot.rise or 0.0
    if hidden then
        shot.seenAt = nil
        shot.rise = math.min(shot.rise + M.regain * dt, 30.0)
    elseif shot.rise > 0.0 then
        shot.seenAt = shot.seenAt or now
        if now - shot.seenAt > 3000 then shot.rise = math.max(0.0, shot.rise - M.regain * 0.25 * dt) end
    end
    return shot.rise
end

local function stalled(shot, remaining)
    local now = U.now()
    if not shot.mark or remaining < shot.mark - 0.3 then
        shot.mark, shot.markAt = remaining, now
        return false
    end
    return now - shot.markAt > 2500
end

function CI.begin(name, subject, pos, previous)
    local M = C.cinematic
    local rel = pos - subject.at
    local ground = flat(rel)
    local out = unit(ground, -bearing(subject.heading))
    local shot = { name = name, out = out, height = math.max(rel.z, 0.5), radius = math.max(#ground, M.minDistance) }
    if name == 'follow' then
        shot.radius = math.min(shot.radius, M.follow.distance)
        shot.angle = U.angleDelta((facing(shot, subject, 0.0) + 180.0) % 360.0, U.heading(out.x, out.y))
    elseif name == 'orbit' or name == 'helix' then
        local turn = previous and previous.spin and previous.spin < 0.0 and -1.0 or 1.0
        shot.radius = math.min(shot.radius, M.orbit.radius)
        shot.spin = (name == 'helix' and M.helix.speed or M.orbit.speed) * turn
        shot.limit = math.max(M.helix.radius, shot.radius + 10.0)
    elseif name == 'dronie' then
        shot.limit = math.max(M.dronie.distance, #rel + 15.0)
    elseif name == 'rocket' then
        shot.offset = ground
        shot.top = rel.z + M.rocket.height
    end
    return shot
end

function CI.step(shot, subject, pos, input, dt, sp, hidden, ceiling)
    local M = C.cinematic
    local name = shot.name
    local rel = pos - subject.at
    local ground = flat(rel)
    local lift = hidden and M.regain or 0.0
    local raised = rise(shot, hidden, dt)
    local tv, done = vector3(0.0, 0.0, 0.0), false
    if name == 'follow' then
        shot.radius = D.clamp(shot.radius - input.y * sp.horizontal * dt, M.minDistance, M.follow.distance)
        shot.angle = shot.angle + input.x * M.follow.swing * dt
        shot.height = math.max(0.5, shot.height + input.z * sp.vertical * dt)
        local dir = bearing(facing(shot, subject, dt) + 180.0 + shot.angle)
        local want = subject.at + dir * shot.radius + vector3(0.0, 0.0, shot.height + raised)
        tv = (want - pos) * 1.2 + subject.vel
    elseif name == 'orbit' or name == 'helix' then
        local out = unit(ground, shot.out)
        shot.out = out
        if name == 'helix' then
            shot.radius = shot.radius + M.helix.out * dt
            shot.height = shot.height + M.helix.up * dt
            local remaining = shot.limit - #ground
            done = remaining <= 0.0 or stalled(shot, remaining)
        else
            shot.spin = D.clamp(shot.spin + input.x * M.orbit.speed * dt, -sp.horizontal, sp.horizontal)
            shot.radius = D.clamp(shot.radius - input.y * sp.horizontal * dt, M.minDistance, M.orbit.radius)
            shot.height = math.max(0.5, shot.height + input.z * sp.vertical * dt)
        end
        local tangent = vector3(-out.y, out.x, 0.0)
        local hold = D.clamp((shot.radius - #ground) * 1.5, -sp.horizontal, sp.horizontal)
        tv = tangent * shot.spin + out * hold + vector3(0.0, 0.0, (shot.height + raised - rel.z) * 1.2) + subject.vel
    elseif name == 'dronie' then
        local remaining = shot.limit - #rel
        local speed = M.dronie.speed * eased(remaining, 8.0)
        local climb = math.rad(M.dronie.climb)
        tv = shot.out * (speed * math.cos(climb)) + vector3(0.0, 0.0, speed * math.sin(climb) + lift) + subject.vel
        done = remaining <= 0.0 or stalled(shot, remaining)
    elseif name == 'rocket' then
        local remaining = shot.top - rel.z
        local speed = M.rocket.speed * eased(remaining, 6.0)
        tv = (shot.offset - ground) * 1.2 + flat(subject.vel) + vector3(0.0, 0.0, speed + subject.vel.z)
        done = remaining <= 0.2 or ceiling or stalled(shot, remaining)
    end
    local speed = #tv
    if speed > M.maxSpeed then tv = tv * (M.maxSpeed / speed) end
    return tv, done
end
