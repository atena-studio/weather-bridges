-- atena-bridge-weather — SERVER: fill `weather`'s seams with atena's policy + drive its runtime overrides from
-- Atena.Settings (event-driven). NO permanent bail at load (bridge-registration.md §5a): bind handlers
-- ALWAYS, gate every cross-resource call at call-time, re-sync on (re)start of atena/weather.
local function ready() return GetResourceState('atena') == 'started' and GetResourceState('atena-std-weather') == 'started' end

-- (1) SEAMS onto weather: authorizer (weather:control → perm 'debug') + inbound guard (atena's checkInbound)
-- + hour-provider (TIME → WEATHER: feed the `time` clock so the roll weights by hour; soft, nil when down).
-- pcall + state-guard: a re-arm can fire while weather's export host is mid-restart (the call would throw a
-- transient SCRIPT ERROR) → swallow it; the next onResourceStart re-arms cleanly. fail-safe, never crash.
local function arm()
    if GetResourceState('atena-std-weather') ~= 'started' then return end
    pcall(function()
        exports['atena-std-weather']:setAuthorizer(function(src, _action) return exports.atena:can(src, 'debug') end)
        exports['atena-std-weather']:setGuard(function(opts, src, args) return exports.atena:checkInbound(opts, src, args) end)
        exports['atena-std-weather']:setHourProvider(function()
            if GetResourceState('time') ~= 'started' then return nil end
            local ok, t = pcall(function() return exports.time:getState() end)
            return (ok and t and t.h) or nil
        end)
    end)
end

-- (2) SETTINGS → weather (event-driven, no poll). Each apply* calls exports['atena-std-weather']; callers gate readiness.
local function applyForce(v)
    if not v or v == 'auto' or v == '' then exports['atena-std-weather']:setAuto() else exports['atena-std-weather']:setAll(v) end
end
local function applyCycle(v) v = tonumber(v); if v and v > 0 then exports['atena-std-weather']:setCycle(v) end end
local function applyLevels()
    local l = exports.atena:settingsGet('snowLine', nil)   -- to a local first: an export returning zero
    local p = exports.atena:settingsGet('snowPeak', nil)   -- values would make inline tonumber() arg-less
    local line, peak = tonumber(l or nil), tonumber(p or nil)
    if line or peak then exports['atena-std-weather']:setLevels(line, peak) end
end
local function applySeason(v) exports['atena-std-weather']:setSeason(v or 'auto') end
local function applyWaveScale(v) v = tonumber(v); if v and v >= 0 then exports['atena-std-weather']:setWaveScale(v) end end

-- pull ALL settings from atena → weather (needs BOTH up). Re-runnable on (re)start.
local function sync()
    if not ready() then return end
    pcall(function()
        applyForce(exports.atena:settingsGet('weatherForce', nil))
        applyCycle(exports.atena:settingsGet('cycleSec', nil) or nil)
        applyLevels()
        applySeason(exports.atena:settingsGet('season', nil))
        applyWaveScale(exports.atena:settingsGet('waveScale', nil) or nil)
    end)
end

arm(); sync()
AddEventHandler('onResourceStart', function(res) if res == 'atena' or res == 'weather' then arm(); sync() end end)
AddEventHandler('atena:settings:changed', function(key, value)
    if GetResourceState('atena-std-weather') ~= 'started' then return end   -- gate: weather may be mid-restart
    if key == 'weatherForce' then applyForce(value)
    elseif key == 'cycleSec' then applyCycle(value)
    elseif key == 'snowLine' or key == 'snowPeak' then applyLevels()
    elseif key == 'season' then applySeason(value)
    elseif key == 'waveScale' then applyWaveScale(value) end
end)
