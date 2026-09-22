# Macros

This directory defines the **Macros** section of Re Adventures V2.

It does not create a new Roblox window or replace the existing Loader UI. Instead, it defines the controls and public API that should be wired into the Loader's existing interface.

## Purpose

The Macros section owns the complete passive macro workflow:

- start recording
- stop and save recording
- list macros
- select a macro
- rename a macro
- delete a macro
- import JSON
- export JSON
- inspect macro metadata
- inspect recording status
- configure snapshot interval
- validate macro schema
- expose replay-readiness metadata

The actual action executor/replay transport is intentionally not part of this passive subsystem.

## Suggested existing-UI section

Section title:

```text
Macros
```

Recommended controls:

1. **Record Macro**
   - Calls `app:StartRecording(name)`

2. **Stop & Save**
   - Calls `app:StopRecording()`
   - Automatically adds the completed macro to the in-memory library

3. **Macro List / Dropdown**
   - Data source: `app:ListMacros()`
   - Selection: `app:SelectMacro(id)`

4. **Rename**
   - Calls `app:RenameMacro(id, newName)`

5. **Delete**
   - Calls `app:DeleteMacro(id)`

6. **Import Macro**
   - Receives JSON text
   - Calls `app:ImportMacro(json, optionalName)`

7. **Export Macro**
   - Selected macro: `app:ExportSelectedMacro()`
   - Specific macro: `app:ExportMacro(id)`

8. **Macro Info**
   - Reads `app:GetMacrosSummary()`
   - Shows map, level, duration, event count and snapshot count

9. **Snapshot Interval**
   - Configured when creating the Core:
   ```lua
   local app = Core.new({
       recorder = {
           snapshotInterval = 1,
           maxSnapshots = 7200,
       }
   })
   ```

## Public API

```lua
app:StartRecording("My macro")

local ok, macro, id = app:StopRecording()

local list = app:ListMacros()
local selected = app:GetSelectedMacro()
local selectedId = app:GetSelectedMacroId()

app:SelectMacro(id)
app:RenameMacro(id, "New name")
app:DeleteMacro(id)

local imported, importedId = app:ImportMacro(json)
local exported = app:ExportSelectedMacro()

local summary = app:GetMacrosSummary()
```

## Macro identity

Every saved/imported macro receives a `libraryId`.

Example:

```lua
{
    libraryId = "GUID",
    schema = "re-adventures-macro",
    version = 2,
    name = "Namek Story",
    map = {
        area = "namek",
        level = "namek_level_1",
    }
}
```

## Recorded event types

Current recorder events:

- `PLACE_DETECTED`
- `UPGRADE_DETECTED`
- `UNIT_REMOVED`
- `WAVE_CHANGED`
- `BASE_LIFE_CHANGED`
- `MATCH_PHASE_CHANGED`

Each event includes a context snapshot with wave, money, life, units placed and enemies alive.

## Runtime synchronization

Macros are not recorded as timing-only scripts.

The recorder stores:

- event time
- map/level
- wave
- wave time
- money
- base life
- enemy count
- unit count
- UUID
- unit CFrame/position
- upgrade transitions

Periodic snapshots are also recorded so later playback can resynchronize against actual match state.

## Storage

The current library is intentionally in-memory.

Import/export is JSON-based. Persistent file/account storage can be added later by the Loader/application layer without changing the macro schema.
