DroneProfile = { enabled = false, enter = ProfilerEnterScope, leave = ProfilerExitScope }
local P = DroneProfile
local TAG = '[cortex-drone]'
local busy = false
local generation = 0
local status = { phase = 'off' }

function P.control(args, opts)
    if args and args[1] == 'off' then
        generation = generation + 1
        P.enabled, busy = false, false
        status = { phase = 'off' }
        print(TAG .. ' Profiler labels disabled. Any native recording is unchanged.')
        return
    end
    if busy then
        print(TAG .. ' Labels already armed. Run profiler record 500 directly in F8.')
        return
    end
    if type(ProfilerIsRecording) ~= 'function' or type(P.enter) ~= 'function' or type(P.leave) ~= 'function' then
        status = { phase = 'unavailable' }
        print(TAG .. ' Profiler natives are unavailable on this client.')
        return
    end
    if ProfilerIsRecording() then
        status = { phase = 'busy_elsewhere' }
        print(TAG .. ' Another profiler capture is running; let it finish first.')
        return
    end

    busy = true
    generation = generation + 1
    local captureGeneration = generation
    local armedAt = GetGameTimer()
    local labels = not (opts and opts.labels == false)
    P.enabled = labels
    status = { phase = 'armed', armedAt = armedAt, labels = labels }
    print(TAG .. ' Labels armed for 30 seconds. Run profiler record 500 directly in F8, close F8 and fly the drone.')
    CreateThread(function()
        local ok, err = xpcall(function()
            while not ProfilerIsRecording() do
                if captureGeneration ~= generation then return end
                local now = GetGameTimer()
                if now < armedAt or now - armedAt >= 30000 then
                    status = { phase = 'expired', armedAt = armedAt, labels = labels }
                    print(TAG .. ' No recording detected; labels disabled. Run profiler record 500 directly in F8 to check access.')
                    return
                end
                Wait(100)
            end
            if captureGeneration ~= generation then return end
            local startedAt = GetGameTimer()
            status = { phase = 'recording', armedAt = armedAt, startedAt = startedAt, labels = labels }
            while ProfilerIsRecording() do
                if captureGeneration ~= generation then return end
                local now = GetGameTimer()
                if now < startedAt or now - startedAt >= 120000 then
                    status = { phase = 'timeout', armedAt = armedAt, startedAt = startedAt, labels = labels }
                    print(TAG .. ' Capture timed out. Labels disabled; inspect profiler status manually.')
                    return
                end
                Wait(250)
            end
            if captureGeneration ~= generation then return end
            P.enabled = false
            local save = ('cortex-drone-%d.json'):format(startedAt)
            status = { phase = 'finished', armedAt = armedAt, startedAt = startedAt, finishedAt = GetGameTimer(), labels = labels, save = save }
            print(('%s Recording finished. Run directly in F8: profiler saveJSON %s'):format(TAG, save))
        end, debug.traceback)
        if captureGeneration == generation then P.enabled, busy = false, false end
        if not ok then
            status = { phase = 'failed', armedAt = armedAt }
            print(TAG .. ' Capture failed: ' .. tostring(err))
        end
    end)
end

function P.state()
    return {
        armed = P.enabled == true, busy = busy,
        recording = type(ProfilerIsRecording) == 'function' and ProfilerIsRecording() == true or false,
        phase = status.phase, labels = status.labels, armedAt = status.armedAt, startedAt = status.startedAt,
        finishedAt = status.finishedAt, save = status.save,
    }
end

RegisterCommand('drone_profile', function(_, args) P.control(args) end, false)

local depth = 0

function P.on(name)
    if not P.enabled then return end
    depth = depth + 1
    P.enter(name)
end

function P.off()
    if depth == 0 then return end
    depth = depth - 1
    P.leave()
end
