-- atena-bridge-weather — the weather <-> atena integration (bridge doctrine, atena-framework §6). EXEMPT from
-- the anti-bias rule. Self-guards on both resources so it stays inert unless weather AND atena are started.
-- Lives in the [bridge] container, versioned with `weather`.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'atena-bridge-weather'
author 'SirTheo'
description 'Bridge: weather <-> atena (seam injection, Atena.Settings weatherForce, debug overlay card)'
version '0.0.1'

server_scripts {
    'server/main.lua',          -- inject seams + apply Atena.Settings weatherForce → weather
}
client_scripts {
    'client/debug.lua',         -- atena debug overlay card: read the plan, force weather / resume auto
}
