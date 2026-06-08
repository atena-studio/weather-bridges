# weather-bridges

Integration bridges for the `std-weather` standalone resource, one per framework.

| Framework | Bridge | Status |
|-----------|--------|--------|
| atena     | `atena-bridge-weather` | present |
| ESX       | `esx-bridge-weather`   | planned |
| QBCore    | `qbcore-bridge-weather`| planned |
| OX        | `ox-bridge-weather`    | planned |

Each bridge is integration glue (calls `exports['std-weather']:*` + the framework's API). The standalone
stays pure/agnostic; the bridge does the wiring. Advanced atena-only mechanics that a framework can't map
are left as a documented comment in that framework's bridge.

Install the standalone (`std-weather`) + the ONE bridge matching your framework.

## Get the standalone (required)

This bridge is free integration glue and needs the **std-weather** standalone resource (sold separately):

➡️ **https://github.com/atena-studio/std-weather**
