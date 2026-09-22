# Re Adventures V2 Core

This folder is the first additive implementation for Re Adventures V2.

## Current status

Implemented:

- Passive real-time match state tracking
- Map/level detection through `Workspace._MAP_CONFIG`
- Wave number/time and match phase tracking
- Player unit tracking through `Workspace._UNITS`
- UUID, owner, upgrade, stats, spent amount and placement CFrame capture
- Enemy tracking through `Workspace._PATH_UNITS`
- Enemy health/current count tracking
- Match money detection from the existing `spawn_units` GUI
- Base-life detection from the existing `Waves.HealthBar.HPDisplay`
- Runtime map profile capture for bases and lane points
- Macro recording driven by detected game-state changes
- Periodic synchronization snapshots
- JSON macro import/export
- Webhook payload builder with injectable transport
- Known profile metadata for Marineford, Walled City, Snowy Town, Sand Village and Namek

Not implemented in this core:

- A second UI (intentionally omitted)
- Any changes to `Loader/Loader.lua`
- RemoteEvent/RemoteFunction invocation
- Replay action execution

The core is intentionally independent from the current UI. The next integration step can wire the existing Loader buttons/toggles into the public Controller API without replacing the Loader.

## Public API

```lua
local core = ReAdventuresV2Core
local app = core.new({
    recorder = {
        snapshotInterval = 1,
        maxSnapshots = 7200,
    },
})

app:Start()

local state = app:GetState()
local profile = app:GetCurrentMapProfile()

app:StartRecording("Marineford run")

-- play normally

local _, macro = app:StopRecording()
local json = app:ExportMacro(macro)

local imported = app:ImportMacro(json)
```

### Existing UI integration

The module creates no ScreenGui, Window, Tab, Toggle or Button.

Wire the existing UI to:

- `app:Start()`
- `app:StartRecording(name)`
- `app:StopRecording()`
- `app:ExportMacro()`
- `app:ImportMacro(json)`
- `app:GetState()`
- `app:GetCurrentMapProfile()`

### Events

```lua
local disconnect = app:On("waveChanged", function(payload)
    print(payload.from, payload.to)
end)
```

Important tracker events:

- `unitAdded`
- `unitUpgradeChanged`
- `unitRemoved`
- `enemyAdded`
- `enemyRemoved`
- `waveChanged`
- `moneyChanged`
- `baseLifeChanged`
- `matchPhaseChanged`
- `mapChanged`

## Macro format

The recorder writes schema `re-adventures-macro`, version 2.

Actions are recorded with contextual state, including:

- time
- wave/wave time
- match phase
- money
- base life
- placed-unit count
- alive-enemy count
- unit UUID and placement CFrame where applicable

Snapshots are also stored periodically so later playback can synchronize against state instead of relying only on absolute timing.
