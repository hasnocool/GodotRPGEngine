# GodotRPGEngine

A modern **Godot 4.7** player client for [`hasnocool/dnd-rpg-engine`](https://github.com/hasnocool/dnd-rpg-engine). The Python engine owns campaign truth, rules, combat, movement validation, time, AI, progression, persistence, visibility, and multiplayer ownership; Godot renders authoritative state and submits intent.

## Current gameplay client

- Campaign library, creation, join/rejoin, reconnect, REST + WebSocket transport.
- Engine-driven Create Character / Hero workflow.
- Tactical 2D world with pan/zoom, selection, click-to-move and attack commands.
- Party rail, inspector, hotbar, world status, story/event feed.
- `PlayerRuntime` character sheet with progression, resources, inventory/equipment, conditions, rests, equip/unequip, resource spend and level-up lifecycle calls.
- `VisualRuntime` actor-scoped world presentation with runtime bindings, imported maps, fog/path overlays, scene transitions, VFX and packaged audio.
- Procedural visuals remain the fallback, so a fresh clone runs without an art pack.

## v0.2 — Authoritative Player Runtime

`PlayerRuntime` adds the `Tab` character sheet and lifecycle controls. Server-described actions are executable only when the server supplies an explicit command dictionary; Godot never infers trusted rules from labels or IDs.

See [`docs/PLAYER_RUNTIME.md`](docs/PLAYER_RUNTIME.md).

## v0.3 — Visual World Runtime

`VisualRuntime` adapts the WorldPlatformEngine actor-scoped `RuntimeSnapshot` into `WorldView`.

v0.3 adds:

- knowledge-scoped entity rendering: when a runtime snapshot exists, `WorldView` uses its entity set instead of merging broader campaign entities;
- packaged `VisualBinding.sprite` rendering with procedural-token fallback;
- optional frame animation through binding metadata;
- map/backdrop textures with optional world-space bounds;
- server-described hidden fog cells/regions;
- authoritative path overlays when published by runtime facts;
- `active_map_id` transition fades and camera recentering;
- WebSocket-event presentation VFX;
- packaged one-shot audio and map ambience hooks;
- strict existing-`res://` asset selection only—no arbitrary filesystem or remote resource loading.

See [`docs/VISUAL_RUNTIME.md`](docs/VISUAL_RUNTIME.md) for the binding/fact contract and examples.

## Architecture

```text
Godot UI / WorldView
       │
       ├── PlayerRuntime ── character lifecycle presentation
       ├── VisualRuntime ── RuntimeSnapshot / VisualBinding presentation
       │
       └── RPGClient / AppState
                    │
              REST + WebSocket
                    │
                    ▼
             dnd-rpg-engine
   Rules • State • Knowledge • Runtime
```

The design rule is simple: **the engine owns truth; Godot renders truth**. A rendered path, fog cell, animation or scene transition never becomes authoritative state.

## Requirements

- Godot **4.7.1 stable** recommended.
- `dnd-rpg-engine` API at `http://127.0.0.1:8000` by default.
- `AdvancedGameEngine` for character lifecycle features.
- `WorldPlatformEngine` for actor-scoped runtime snapshots and v0.3 visual bindings. Without it, the procedural tactical renderer and lifecycle UI continue to work.

## Run

```bash
# From dnd-rpg-engine
rpg-engine serve --host 127.0.0.1 --port 8000
```

Open this repository in Godot and run the project. The server endpoint can be changed from the campaign lobby.

Headless validation:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --quit-after 3
```

## Controls

| Input | Action |
|---|---|
| Left click empty ground | Submit move intent |
| Left click entity | Select / inspect |
| Right click entity | Basic attack |
| Middle drag | Pan |
| Mouse wheel | Zoom |
| `1` | Attack selected target |
| `E` | Interact |
| `Space` | Wait |
| `C` | Hero creator/lifecycle |
| `Tab` | Player Runtime character sheet |
| `Esc` | Campaign library |

## Structure

```text
autoload/
  AppState.gd
  RPGClient.gd
  VisualRuntime.gd
  PlayerRuntime.gd

game/
  WorldView.gd

ui/
  Main.gd

docs/
  PLAYER_RUNTIME.md
  VISUAL_RUNTIME.md
```

## Main engine surfaces

The client consumes campaign/session APIs, character lifecycle APIs, `GET /api/v1/campaigns/{campaign_id}/runtime?actor_id={actor_id}` in WorldPlatform mode, and `WS /api/v1/campaigns/{campaign_id}/ws`.

## Next

The v0.3 foundation is ready for typed targeting/range/LOS/cover overlays, dedicated spell/ability and inventory views, structured quests/dialogue/shop/loot, richer scene-graph/tilemap bindings, 2D skeletal animation, a 3D host for `VisualBinding.model`, and a GM workspace without moving rules into Godot.
