-- atena-bridge-weather — CLIENT: the weather debug. A STATUS card (kv): current zone/climate/weather + force +
-- viz toggles + the ALTITUDE breakdown for WHERE YOU ARE (snow-line bands, current one marked). Plus a clean
-- NEARBY table (HERE + N/E/S/W, one row each — no confusing sub-rows). Two world overlays: ground climate
-- squares + floating snow-line/peak squares (world-fixed). View-only + intents. ROBUST REGISTRATION.

local OPEN_ID, PANEL, NWIN = 'std-weather:open', 'std-weather:panel', 'std-weather:nearby'
local open, showGround, showHeights = false, false, false
local STEP, N = 60.0, 3                   -- viz grid: cell spacing (m), radius (cells from center)
local grid, lastKey = {}, nil            -- cached cells (invalidated when the grid params or your cell change)

local function atenaUp()   return GetResourceState('atena') == 'started' end
local function weatherUp() return GetResourceState('std-weather') == 'started' end
local function climateOf(zone) return (weatherUp() and exports['std-weather']:climateOf(zone)) or 'temperate' end
local function levels() return (weatherUp() and exports['std-weather']:levels()) or { snowLine = 450.0, snowPeak = 700.0 } end

-- box color by the actual WEATHER (so the 3D boxes show what it's doing there, incl. altitude snow).
local WEATHER_COLOR = {
    EXTRASUNNY = { 240, 210, 90 }, CLEAR = { 205, 210, 120 }, CLOUDS = { 150, 160, 170 }, OVERCAST = { 110, 120, 135 },
    CLEARING = { 120, 175, 210 }, RAIN = { 70, 120, 215 }, THUNDER = { 110, 90, 200 }, FOGGY = { 175, 180, 185 },
    SMOG = { 160, 155, 120 }, SNOW = { 205, 230, 240 }, XMAS = { 240, 245, 250 }, BLIZZARD = { 215, 230, 245 },
}
local NEIGH_DIST = 150.0
local NEIGH = { { l = 'HERE', dx = 0, dy = 0 }, { l = 'N', dx = 0, dy = NEIGH_DIST }, { l = 'E', dx = NEIGH_DIST, dy = 0 },
                { l = 'S', dx = 0, dy = -NEIGH_DIST }, { l = 'W', dx = -NEIGH_DIST, dy = 0 } }

local function bandKey(z, lv) if z >= lv.snowPeak then return 'high' elseif z >= lv.snowLine then return 'mid' else return 'low' end end
local BAND_NAME = { low = 'rain / normal', mid = 'mixed (snow-line)', high = 'snow (peak)' }
-- weather at an altitude band — DELEGATES to the weather resource (single source: Climate.atAltitude) so the
-- debug never drifts from what the client applies. Maps the band to a representative z.
local function bandWeather(climate, planW, band, lv)
    local z = (band == 'high' and (lv.snowPeak + 1.0)) or (band == 'mid' and ((lv.snowLine + lv.snowPeak) * 0.5)) or 0.0
    return (weatherUp() and exports['std-weather']:atAltitude(climate, planW, z)) or planW
end

-- ── STATUS card (kv): current + controls + altitude breakdown HERE ───────────────────────────────────
local function statusRows()
    local climates = (GlobalState.weatherPlan or {}).climates or {}
    local forced = (GlobalState.weatherPlan or {}).forced
    local p = GetEntityCoords(PlayerPedId())
    local zone = GetNameOfZone(p.x, p.y, p.z)
    local climate = climateOf(zone)
    local planW = climates[climate] or '—'
    local cur = (weatherUp() and exports['std-weather']:current()) or {}
    local lv = levels()
    local hereBand = bandKey(p.z, lv)
    local r = {
        { key = 'zone',    value = tostring(zone), tone = 'accent' },
        { key = 'climate', value = tostring(climate) },
        { key = 'weather (now)', value = tostring(cur.type or planW), tone = 'green' },           -- ACTUALLY applied
        { key = 'rain',    value = ('%.2f'):format(cur.rain or 0.0), tone = ((cur.rain or 0) > 0.05) and 'warn' or 'dim' },
        { key = 'cell plan', value = tostring(planW) .. ((cur.type and cur.type ~= planW) and '  (transitioning…)' or ''), tone = 'dim' },
        { key = 'force',   value = (forced and planW) or 'auto', kind = 'select',
          options = { 'auto', 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER', 'FOGGY', 'XMAS', 'SNOW' } },
        { key = 'viz: boxes', value = showGround,  kind = 'toggle', tone = (showGround and 'green' or 'dim') },   -- 3D weather boxes
        { key = 'viz: bands', value = showHeights, kind = 'toggle', tone = (showHeights and 'green' or 'dim') },  -- snow-line/peak slabs
        { key = 'grid step (m)',       value = STEP, kind = 'number', step = 10.0 },
        { key = 'grid radius (cells)', value = N,    kind = 'number', step = 1.0 },
        { key = 'altitude (here)', value = ('Z %.0fm'):format(p.z), kind = 'header' },
    }
    -- the three altitude bands at your position, current one marked. Only meaningful (varies) on alpine.
    if climate == 'alpine' then
        for _, b in ipairs({ 'high', 'mid', 'low' }) do
            local hi = (b == 'high' and ('> %.0fm'):format(lv.snowPeak)) or (b == 'mid' and ('%.0f–%.0fm'):format(lv.snowLine, lv.snowPeak)) or ('< %.0fm'):format(lv.snowLine)
            r[#r + 1] = { key = (hereBand == b and '► ' or '  ') .. BAND_NAME[b], value = ('%s · %s'):format(hi, bandWeather(climate, planW, b, lv)),
                          tone = (hereBand == b and 'green') or 'dim' }
        end
    else
        r[#r + 1] = { key = '  ' .. BAND_NAME[hereBand], value = 'altitude n/a (not alpine)', tone = 'dim' }
    end

    -- ENVIRONMENT readout (the bundle the clothing/thermal system consumes) — see the model live + tune it.
    -- pcall-isolated: a throw in the cross-resource call must NOT blank the whole panel (nui.md §8).
    local okEnv, env = pcall(function() return weatherUp() and exports['std-weather']:environment() or nil end)
    if not okEnv then r[#r + 1] = { key = 'env ERROR', value = tostring(env), tone = 'warn' } end
    if okEnv and env then
        local fl = env.feelsLike or 20.0
        r[#r + 1] = { key = 'environment', value = tostring(env.season or '—'), kind = 'header' }
        r[#r + 1] = { key = 'temp',       value = ('%.1f°C'):format(env.tempC or 0.0), tone = 'accent' }
        r[#r + 1] = { key = 'feels like', value = ('%.1f°C'):format(fl), tone = ((fl < 5.0 or fl > 35.0) and 'warn') or 'green' }
        r[#r + 1] = { key = 'wetness',    value = ('%.0f%%'):format((env.wetness or 0.0) * 100.0), tone = ((env.wetness or 0) > 0.05 and 'warn' or 'dim') }
        r[#r + 1] = { key = 'sun · humid', value = ('%.0f%% · %.0f%%'):format((env.sun or 0) * 100.0, (env.humidity or 0) * 100.0), tone = 'dim' }
        r[#r + 1] = { key = 'wind',       value = ('%.1f @ %.0f°'):format(GetWindSpeed(), env.windHeading or 0.0), tone = 'dim' }
        r[#r + 1] = { key = 'waves',      value = ('%.1f'):format(env.waves or 1.0), tone = 'dim' }
        r[#r + 1] = { key = 'where', value = (env.indoors and 'indoors') or (env.inWater and ('in water %.0f%%'):format((env.submerged or 0) * 100.0))
                          or (env.nearWater and 'near water') or 'open',
                      tone = (env.indoors and 'green') or (env.inWater and 'warn') or 'dim' }
    end
    return r
end

-- ── NEARBY table: HERE + N/E/S/W, one clean row each ────────────────────────────────────────────────
local function nearbyWin()
    local climates = (GlobalState.weatherPlan or {}).climates or {}
    local lv = levels()
    local p = GetEntityCoords(PlayerPedId())
    local items = {}
    for _, n in ipairs(NEIGH) do
        local x, y = p.x + n.dx, p.y + n.dy
        local zone = GetNameOfZone(x, y, p.z)
        local climate = climateOf(zone)
        local gz, band
        if n.dx == 0 and n.dy == 0 then gz, band = p.z, bandKey(p.z, lv)
        else local ok, g = GetGroundZFor_3dCoord(x, y, p.z + 300.0, false); if ok then gz, band = g, bandKey(g, lv) end end
        local now = bandWeather(climate, climates[climate] or '—', band or 'low', lv)
        items[#items + 1] = { id = n.l, cells = {
            (n.l == 'HERE' and '► HERE') or (n.l .. ' (' .. tostring(math.floor(NEIGH_DIST)) .. 'm)'),
            zone, climate,
            { text = tostring(now), tone = 'green' },
            gz and ('%.0fm · %s'):format(gz, BAND_NAME[band]) or '—',
        } }
    end
    return { source = 'debug', kind = 'table', title = 'WEATHER · NEARBY', columns = { 'cell', 'zone', 'climate', 'weather', 'ground · band' }, items = items }
end

local function push()
    if not (open and atenaUp()) then return end
    exports.atena:uiDebugPanel(PANEL, { title = 'WEATHER', rows = statusRows() })
    exports.atena:uiWindow(NWIN, nearbyWin())
end
local function close() exports.atena:uiDebugPanel(PANEL, nil); exports.atena:uiWindow(NWIN, nil) end

-- ── registration (robust: thread one-shot + events) ──────────────────────────────────────────────────
-- toggle entry: the launcher badge mirrors whether the card is open (debugSet keeps it true).
local function reg() if atenaUp() then exports.atena:debugAdd({ id = OPEN_ID, group = 'world', label = 'Weather', icon = 'cloud', toggle = true, value = open, peekWin = PANEL }) end end
local function badge() if atenaUp() then exports.atena:debugSet(OPEN_ID, open) end end
CreateThread(function() while not atenaUp() do Wait(250) end; reg() end)
AddEventHandler('onResourceStart', function(res) if res == 'atena' then reg() end end)
AddEventHandler('atena:debug:ready', reg)
AddEventHandler('atena:debug:refresh', reg)

AddEventHandler('atena:debug:invoke', function(id)
    if id ~= OPEN_ID then return end
    open = not open
    if open then exports.atena:uiDebugArrange(true); push() else close() end
    badge()
end)
AddEventHandler('atena:debug:action', function(panel, key, value)
    if panel ~= PANEL then return end
    if key == 'force' then
        if value == 'auto' then TriggerServerEvent('std-weather:op:auto') else TriggerServerEvent('std-weather:op:set', value) end
    elseif key == 'viz: boxes' then showGround = not showGround
    elseif key == 'viz: bands' then showHeights = not showHeights
    elseif key == 'grid step (m)'       then STEP = math.max(20.0, tonumber(value) or STEP); lastKey = nil
    elseif key == 'grid radius (cells)' then N = math.max(1, math.min(8, math.floor(tonumber(value) or N))); lastKey = nil
    end
    push()
end)
AddEventHandler('atena:debug:panelClosed', function(p) if p == PANEL then open = false; exports.atena:uiWindow(NWIN, nil); badge() end end)
CreateThread(function() while true do if open then push() end; Wait(2000) end end)

-- hover-PEEK (view-only): preview ONLY the status PANEL (not the NEARBY table) without opening for
-- real (no open flag, no badge); peekEnd clears it. The full open (+ NWIN) is the pin (invoke).
AddEventHandler('atena:debug:peek', function(win)
    if win == PANEL and not open and atenaUp() then exports.atena:uiDebugPanel(PANEL, { title = 'WEATHER', rows = statusRows() }) end
end)
AddEventHandler('atena:debug:peekEnd', function(win)
    if win == PANEL and not open and atenaUp() then exports.atena:uiDebugPanel(PANEL, nil) end
end)

-- ── world overlays: FILLED weather boxes per cell (DrawBox, translucent) colored by the weather + ONE
-- filled SLAB per division (snow-line / snow-peak) across the whole grid. Readable, not a wire-mesh.
local function fbox(cx, cy, z0, z1, half, col, a)
    DrawBox(cx - half, cy - half, z0, cx + half, cy + half, z1, col[1], col[2], col[3], a)   -- AABB, one call
end
local function wcol(t) return WEATHER_COLOR[t] or { 180, 180, 180 } end
local gbX, gbY = 0.0, 0.0   -- grid base (world-aligned) for the division slabs
CreateThread(function()
    while true do
        if (showGround or showHeights) and weatherUp() then
            local p = GetEntityCoords(PlayerPedId())
            local plan = (GlobalState.weatherPlan or {}).climates or {}
            local lv = levels()
            local key = ('%d:%d'):format(math.floor(p.x / STEP), math.floor(p.y / STEP))
            if key ~= lastKey then
                lastKey = key; grid = {}
                gbX, gbY = math.floor(p.x / STEP) * STEP, math.floor(p.y / STEP) * STEP   -- world-fixed
                for ix = -N, N do for iy = -N, N do
                    local x, y = gbX + ix * STEP, gbY + iy * STEP
                    local gz = p.z
                    local ok, gr = GetGroundZFor_3dCoord(x, y, p.z + 300.0, false); if ok then gz = gr end
                    local climate = climateOf(GetNameOfZone(x, y, p.z))
                    local planW = plan[climate] or 'EXTRASUNNY'
                    grid[#grid + 1] = { x = x, y = y, gz = gz, alpine = (climate == 'alpine'),
                        cl = wcol(planW),
                        cm = wcol(exports['std-weather']:atAltitude(climate, planW, (lv.snowLine + lv.snowPeak) * 0.5)),
                        ch = wcol(exports['std-weather']:atAltitude(climate, planW, lv.snowPeak + 1.0)) }
                end end
            end
            local half = STEP * 0.45
            if showGround then
                -- each cell = filled column; every band SEGMENT fills the Z-range of the state it represents.
                local top = lv.snowPeak + 80.0
                for _, g in ipairs(grid) do
                    if g.alpine then
                        if g.gz < lv.snowLine then fbox(g.x, g.y, g.gz, lv.snowLine, half, g.cl, 70) end             -- low band
                        local m0 = math.max(g.gz, lv.snowLine)
                        if m0 < lv.snowPeak then fbox(g.x, g.y, m0, lv.snowPeak, half, g.cm, 70) end                  -- mid band
                        local h0 = math.max(g.gz, lv.snowPeak)
                        fbox(g.x, g.y, h0, math.max(top, h0 + 40.0), half, g.ch, 70)                                  -- high band
                    else
                        fbox(g.x, g.y, g.gz, math.max(top, g.gz + 40.0), half, g.cl, 70)   -- one state at all altitudes
                    end
                end
            end
            if showHeights then
                -- ONE filled slab per division, spanning the whole grid (a clean plane, NOT a per-cell mesh).
                local ext = (N + 0.5) * STEP
                DrawBox(gbX - ext, gbY - ext, lv.snowLine - 1.0, gbX + ext, gbY + ext, lv.snowLine + 1.0, 120, 210, 230, 110)
                DrawBox(gbX - ext, gbY - ext, lv.snowPeak - 1.0, gbX + ext, gbY + ext, lv.snowPeak + 1.0, 240, 240, 245, 120)
            end
            Wait(0)
        else
            lastKey = nil
            Wait(500)
        end
    end
end)
