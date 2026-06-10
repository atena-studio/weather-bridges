-- atena-bridge-weather — SERVER: fill `weather`'s seams with atena's policy + drive its runtime overrides from
-- Atena.Settings (event-driven). NO permanent bail at load (bridge-registration.md §5a): bind handlers
-- ALWAYS, gate every cross-resource call at call-time, re-sync on (re)start of atena/weather.
local function ready() return GetResourceState('atena') == 'started' and GetResourceState('std-weather') == 'started' end

-- (1) SEAMS onto weather: authorizer (weather:control → perm 'debug') + inbound guard (atena's checkInbound)
-- + hour-provider (TIME → WEATHER: feed the `time` clock so the roll weights by hour; soft, nil when down).
-- pcall + state-guard: a re-arm can fire while weather's export host is mid-restart (the call would throw a
-- transient SCRIPT ERROR) → swallow it; the next onResourceStart re-arms cleanly. fail-safe, never crash.
local function arm()
    if GetResourceState('std-weather') ~= 'started' then return false end
    return (pcall(function()
        exports['std-weather']:setAuthorizer(function(src, _action) return exports.atena:can(src, 'debug') end)
        exports['std-weather']:setGuard(function(opts, src, args) return exports.atena:checkInbound(opts, src, args) end)
        exports['std-weather']:setHourProvider(function()
            if GetResourceState('std-time') ~= 'started' then return nil end
            local ok, t = pcall(function() return exports['std-time']:getState() end)
            return (ok and t and t.h) or nil
        end)
    end))
end

-- (2) SETTINGS → weather (event-driven, no poll). Each apply* calls exports['std-weather']; callers gate readiness.
local function applyForce(v)
    if not v or v == 'auto' or v == '' then exports['std-weather']:setAuto() else exports['std-weather']:setAll(v) end
end
local function applyCycle(v) v = tonumber(v); if v and v > 0 then exports['std-weather']:setCycle(v) end end
local function applyLevels()
    local l = exports.atena:settingsGet('snowLine', nil)   -- to a local first: an export returning zero
    local p = exports.atena:settingsGet('snowPeak', nil)   -- values would make inline tonumber() arg-less
    local line, peak = tonumber(l or nil), tonumber(p or nil)
    if line or peak then exports['std-weather']:setLevels(line, peak) end
end
local function applySeason(v) exports['std-weather']:setSeason(v or 'auto') end
local function applyWaveScale(v) v = tonumber(v); if v and v >= 0 then exports['std-weather']:setWaveScale(v) end end

-- pull ALL settings from atena → weather (needs BOTH up). Re-runnable on (re)start.
-- BOUNDED RETRY: at the onResourceStart tick the just-(re)started resource's export
-- host can still be registering, so a cross-resource call in that same tick throws —
-- a bare pcall swallowed that silently (verified live: zero sync after a std-weather
-- restart). Retry until the calls land, and LOG what was applied: a silent sync is
-- unverifiable from the server log (the automated settings→weather check greps this).
local function sync()
    CreateThread(function()
        -- ready() goes INSIDE the loop: at the onResourceStart tick the restarting
        -- resource still reads as 'starting', so a pre-check here returned silently
        -- and the restart re-sync never happened (verified live).
        for _ = 1, 10 do
            local ok = ready() and arm() and pcall(function()
                local force = exports.atena:settingsGet('weatherForce', nil)
                local cyc   = exports.atena:settingsGet('cycleSec', nil)
                local sea   = exports.atena:settingsGet('season', nil)
                local wav   = exports.atena:settingsGet('waveScale', nil)
                applyForce(force)
                applyCycle(cyc or nil)
                applyLevels()
                applySeason(sea)
                applyWaveScale(wav or nil)
                print(('[weather-bridge] sync applied: force=%s cycle=%s season=%s wave=%s')
                    :format(tostring(force), tostring(cyc), tostring(sea), tostring(wav)))
            end)
            if ok then return end
            Wait(500)
        end
        print('[weather-bridge] sync FAILED: weather/atena exports unavailable after 5s')
    end)
end

arm(); sync()
AddEventHandler('onResourceStart', function(res) if res == 'atena' or res == 'std-weather' then arm(); sync() end end)
-- The onResourceStart('atena') sync above fires while atena's settings cache is still
-- EMPTY (the DB fill is async — verified live: it applied nils on every atena restart).
-- This is the real readiness signal: atena announces every completed settings refresh.
AddEventHandler('atena:settings:ready', function() arm(); sync() end)
AddEventHandler('atena:settings:changed', function(key, value)
    if GetResourceState('std-weather') ~= 'started' then return end   -- gate: weather may be mid-restart
    local hit = true
    if key == 'weatherForce' then applyForce(value)
    elseif key == 'cycleSec' then applyCycle(value)
    elseif key == 'snowLine' or key == 'snowPeak' then applyLevels()
    elseif key == 'season' then applySeason(value)
    elseif key == 'waveScale' then applyWaveScale(value)
    else hit = false end
    -- on-change diagnostic for OUR keys only (a silent flip is unverifiable from the log)
    if hit then print(('[weather-bridge] applied %s=%s'):format(key, tostring(value))) end
end)
