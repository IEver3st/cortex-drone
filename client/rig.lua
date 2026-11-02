DroneRig = {}
local R = DroneRig
local U = DroneUtil

R.IDENTITY = vector4(0.0, 0.0, 0.0, 1.0)

function R.ease(t)
    t = math.max(0.0, math.min(1.0, t))
    return t * t * (3.0 - 2.0 * t)
end

function R.span(t, from, to)
    if to <= from then return t >= to and 1.0 or 0.0 end
    return math.max(0.0, math.min(1.0, (t - from) / (to - from)))
end

function R.lerp(a, b, t) return a + (b - a) * t end

function R.curve(a, via, b, t)
    local u = 1.0 - t
    return a * (u * u) + via * (2.0 * u * t) + b * (t * t)
end

function R.compose(pos, rot, offset, turn)
    return pos + U.qrot(rot, offset), turn and U.qnorm(U.qmul(rot, turn)) or rot
end

function R.pose(entity)
    return GetEntityCoords(entity), U.quaternion(entity)
end

local function basis(right, forward, up)
    local m00, m01, m02 = right.x, forward.x, up.x
    local m10, m11, m12 = right.y, forward.y, up.y
    local m20, m21, m22 = right.z, forward.z, up.z
    local trace = m00 + m11 + m22
    if trace > 0.0 then
        local s = 0.5 / math.sqrt(trace + 1.0)
        return U.qnorm(vector4((m21 - m12) * s, (m02 - m20) * s, (m10 - m01) * s, 0.25 / s))
    elseif m00 > m11 and m00 > m22 then
        local s = 2.0 * math.sqrt(1.0 + m00 - m11 - m22)
        return U.qnorm(vector4(0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s))
    elseif m11 > m22 then
        local s = 2.0 * math.sqrt(1.0 + m11 - m00 - m22)
        return U.qnorm(vector4((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s))
    end
    local s = 2.0 * math.sqrt(1.0 + m22 - m00 - m11)
    return U.qnorm(vector4((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s))
end

function R.bone(ped, bone)
    local origin = GetPedBoneCoords(ped, bone, 0.0, 0.0, 0.0)
    local right = GetPedBoneCoords(ped, bone, 1.0, 0.0, 0.0) - origin
    local forward = GetPedBoneCoords(ped, bone, 0.0, 1.0, 0.0) - origin
    local up = GetPedBoneCoords(ped, bone, 0.0, 0.0, 1.0) - origin
    return origin, basis(right, forward, up)
end

function R.place(entity, pos, rot)
    SetEntityCoordsNoOffset(entity, pos.x, pos.y, pos.z, false, false, false)
    SetEntityQuaternion(entity, rot.x, rot.y, rot.z, rot.w)
end

function R.prop(model, pos, rot)
    local hash = U.loadModel(model, 3000)
    if not hash then return nil end
    local object = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if object == 0 then return nil end
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)
    SetEntityInvincible(object, true)
    R.place(object, pos, rot or R.IDENTITY)
    return object
end

function R.ground(x, y, z, ignore)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(x, y, z + 0.6, x, y, z - 2.0, 1 | 16, ignore or 0, 7)
    local _, hit, coords = GetShapeTestResult(probe)
    if hit == 1 or hit == true then return coords.z end
    return nil
end

function R.camera(from, at, fov, ease)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', from.x, from.y, from.z, 0.0, 0.0, 0.0, fov or 40.0, false, 2)
    PointCamAtCoord(cam, at.x, at.y, at.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, ease or 700, true, false)
    return cam
end

function R.release(cam, ease)
    if not cam then return end
    RenderScriptCams(false, (ease or 0) > 0, ease or 0, true, false)
    DestroyCam(cam, false)
end
