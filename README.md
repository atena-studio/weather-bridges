# atena-bridges-weather

Integration bridges for the `atena-std-weather` standalone resource, one per framework.

| Framework | Bridge | Status |
|-----------|--------|--------|
| atena     | `atena-bridge-weather` | present |
| ESX       | `esx-bridge-weather`   | planned |
| QBCore    | `qbcore-bridge-weather`| planned |
| OX        | `ox-bridge-weather`    | planned |

Each bridge is integration glue (calls `exports['atena-std-weather']:*` + the framework's API). The standalone
stays pure/agnostic; the bridge does the wiring. Advanced atena-only mechanics that a framework can't map
are left as a documented comment in that framework's bridge.

Install the standalone (`atena-std-weather`) + the ONE bridge matching your framework.
