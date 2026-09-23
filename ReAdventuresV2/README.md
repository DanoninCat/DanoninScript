# Re Adventures V2

The existing Cat Empire Loader embeds `Core.lua`, `UI.lua` and `Entry.lua`.
Match `138271828389486` and lobby `94823097601547` share the payload.

## Features

- Auto Place: select equipped units, select a Marker Unit and click **Place Marker**, then click a valid map position. Each selected slot has one marker. Enable Auto Place to maintain a placement at that marker. Server placement rules still apply.
- Auto Upgrade: upgrades owned units matching selected equipped slots.
- After Match: mutually exclusive Next, Replay or Return Lobby. Next is only attempted after a victory. Result capture and webhook submission precede the action.
- Macros: record local-player placements/upgrades and passive state events; save, select, rename, delete, import and export. Replay uses recorded coordinates and resolves equipped units against the current session. It waits for state confirmation and stops with an error if an action cannot complete within 60 seconds. Ambiguous unit matches fail explicitly.
- Unit removal is recorded as an observation, never interpreted as a sell action: removal may mean death or round cleanup.
- Auto Story pauses during recording and replay to avoid competing actions. Stop replay interrupts pending retries.
- Macros persist at `CatEmpire/ReAdventures/macros.json` when file APIs are available. Otherwise Export provides a portable copy (clipboard when available, console fallback).
- Webhooks use the environment's HTTP request capability when available, otherwise Roblox HttpService. HTTP errors are reported. Autosave subscribes to controller events without replacing feature callbacks.
- Re-execution stops the previous app; closing Fluent stops background automation.

Markers are session-local and must be set for the current map. The script must be loaded in the destination server after teleporting; this change does not install teleport auto-execution. Start recording before placing units; units already present at recording start are not new placement events.

## Rebuild

From the repository root:

```sh
python tools/build_loader.py
```

The builder replaces only the Re Adventures entry, preserving other games, the shared Fluent payload and the lobby alias. Rebuild after changing any of the three Lua source files.

## Verification

```sh
python -m pip install lupa
python -m unittest discover -s tests -v
```

Offline tests cover syntax, source/payload equality, preservation of other loader entries, selected-slot placement and money checks, automation exclusion, post-match action gating, replay cancellation/errors/confirmation, endpoint argument forwarding, macro refresh events and HTTP success/failure handling.

**Live validation remains required.** The supplied Namek dump confirms endpoint names/classes and the equipped-unit UUID attribute, but does not capture invocation arguments or server implementations. The adapter currently uses these contracts, which need confirmation in the current game:

| Action | Endpoint | Arguments |
| --- | --- | --- |
| Place | `spawn_unit` | equipped UUID, CFrame |
| Upgrade | `upgrade_unit_ingame` | owned unit Model |
| Next | `set_game_finished_vote` | `"next_story"` |
| Replay | `set_game_finished_vote` | `"replay"` |
| Lobby | `teleport_back_to_lobby` | none |

`app:SetActionAdapter(callback)` can replace the default dispatch. The callback receives `{kind, unit?, cframe?, model?, slot?, event?}` and returns `success, error`. No server signature compatibility or live execution is claimed by the offline tests.

In a match, verify one marked placement, an upgrade, a short record/replay, then each post-match option and the Discord webhook. Check macro persistence after reloading. The existing result parser's reward/EXP extraction also needs comparison with live results.
