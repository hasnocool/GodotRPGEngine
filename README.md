# GodotRPGEngine

A modern **Godot 4.7** player client for [`hasnocool/dnd-rpg-engine`](https://github.com/hasnocool/dnd-rpg-engine).

The project is intentionally a presentation/client layer. The Python RPG engine remains the authority for campaign state, rules, movement validation, combat, timing, AI, resources, progression, persistence, visibility, and multiplayer ownership. Godot renders that state and submits commands.

## What the redesign includes

- Modern campaign library and server connection screen.
- Campaign creation with all engine timing modes.
- Session join/rejoin before gameplay so persisted campaigns remain controllable after reconnect/restart.
- Dedicated **Create Character / Hero** workflow driven by the engine's live character catalog.
- Six ability scores, class selection, species/background IDs, and starting equipment.
- Tactical 2D world renderer with pan/zoom, grid, entity tokens, player/target highlighting, HP bars, and area filtering.
- Click-to-move and right-click attack routed through authoritative engine commands.
- Player hotbar for attack, interact, wait, and hero management.
- Party rail, entity inspector, live world status, connection status, and story/event feed.
- WebSocket state/event/ack processing with reconnect and throttled authoritative state refresh.
- Non-blocking REST requests using independent `HTTPRequest` nodes, allowing concurrent UI requests without blocking the main thread.
- Asset-free procedural presentation so a fresh clone is immediately runnable before custom art is added.

## v0.2 — Authoritative Player Runtime

The next gameplay layer is now integrated through the `PlayerRuntime` autoload. It activates automatically when the server resolves the local player's actor and adds a compact runtime dock plus a detailed `Tab` character sheet.

The runtime currently provides:

- live hero/class/level/HP presentation;
- full ability-score and progression summary;
- tracked class resources;
- inventory and equipped-slot display;
- active conditions when exposed by the authoritative entity;
- catalog-backed rest profiles and equipment labels;
- server-authoritative rest, equip, unequip, resource-spend, and level-up controls;
- owner-aware level-up authorization;
- actor-scoped WorldPlatform runtime snapshots;
- initial Journal / Known World Facts surfacing for quest/objective/dialogue/scene facts;
- forward-compatible server-described action palette support.

A described action is only executable when the server supplies an explicit command envelope. Godot will not infer combat/rules commands from labels or IDs.

See [`docs/PLAYER_RUNTIME.md`](docs/PLAYER_RUNTIME.md) for the authority model and extension points.

## Architecture

```text
┌──────────────────────────────────────────────────────────┐
│                    GODOT 4.7 CLIENT                      │
│                                                          │
│  Campaign Lobby  Hero Creator  Tactical World  HUD/UX   │
│          │             │            │          │         │
│          └─────────────┴──────┬─────┴──────────┘         │
│                               │                           │
│          PlayerRuntime + RPGClient / AppState             │
└───────────────────────────────┼───────────────────────────┘
                                │ REST + WebSocket
                                ▼
┌──────────────────────────────────────────────────────────┐
│                  dnd-rpg-engine server                   │
│                                                          │
│ Rules • State • Events • Commands • AI • Time • Saves   │
│ Character Lifecycle • Knowledge • Runtime Snapshots     │
└──────────────────────────────────────────────────────────┘
```

The client follows one rule: **the engine owns truth; Godot renders truth**. A movement, attack, rest, equip, resource, or level action never edits campaign state locally. It sends an intent/request and updates from the next authoritative response or state snapshot.

## Requirements

- Godot **4.7.1 stable** recommended.
- A running `dnd-rpg-engine` API, defaulting to `http://127.0.0.1:8000`.
- `AdvancedGameEngine` mode for Hero Creator and character lifecycle controls.
- `WorldPlatformEngine` mode for actor-scoped runtime/knowledge snapshots. The player sheet still works without this optional layer.

## Run

Start the D&D RPG engine first, then open this repository in Godot and run the project.

```bash
# From the dnd-rpg-engine repository
rpg-engine serve --host 127.0.0.1 --port 8000
```

In the Godot lobby, change the server address from `http://127.0.0.1:8000` to the correct endpoint and select **Refresh**.

For a headless project validation pass:

```bash
godot --headless --path . --editor --quit
```

## Controls

| Input | Action |
|---|---|
| Left click empty ground | Move hero |
| Left click entity | Select / inspect |
| Right click entity | Basic attack |
| Middle drag | Pan tactical camera |
| Mouse wheel | Zoom |
| `1` | Attack selected target |
| `E` | Interact with selected target |
| `Space` | Wait |
| `C` | Open Hero Creator / lifecycle view |
| `Tab` | Toggle authoritative Player Runtime character sheet |
| `Esc` | Return to campaign library |

## Main project structure

```text
autoload/
  AppState.gd       Persistent endpoint, identity, campaign and selection state
  RPGClient.gd      Non-blocking REST + WebSocket engine bridge
  PlayerRuntime.gd  Authoritative player character/runtime HUD and lifecycle UI

game/
  WorldView.gd      Tactical map renderer and world input

scenes/
  Main.tscn         Playable entry scene

ui/
  Main.gd           Lobby, Hero Creator, HUD, party, inspector and event feed

docs/
  PLAYER_RUNTIME.md Runtime authority model and extension contract
```

## Engine surfaces used

The client integrates with:

- `GET /api/v1/campaigns`
- `POST /api/v1/campaigns`
- `POST /api/v1/campaigns/{campaign_id}/join`
- `GET /api/v1/campaigns/{campaign_id}/characters`
- `GET /api/v1/campaigns/{campaign_id}/characters/catalog`
- `POST /api/v1/campaigns/{campaign_id}/characters`
- `GET /api/v1/campaigns/{campaign_id}/characters/{actor_id}`
- `POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/rest`
- `POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/equip`
- `POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/unequip`
- `POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/resources/spend`
- `POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/level-up`
- `GET /api/v1/campaigns/{campaign_id}/runtime?actor_id={actor_id}` when WorldPlatform mode is available
- `WS /api/v1/campaigns/{campaign_id}/ws`

The WebSocket sends `state` requests and command envelopes and consumes authoritative `state`, `event`, `ack`, and `error` messages.

## Next presentation layer expansions

The v0.2 runtime creates a safe base for typed server `available_actions`, authoritative target/range/LOS/cover overlays, dedicated inventory and spell/ability views, structured quest journal, dialogue, shop/loot, scene travel, encounter initiative/reactions, richer animation/VFX/audio, runtime visual bindings, imported campaign maps, and a GM-specific workspace without moving rules into Godot.
