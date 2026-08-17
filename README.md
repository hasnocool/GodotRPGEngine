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

## Architecture

```text
┌──────────────────────────────────────────────────────────┐
│                    GODOT 4.7 CLIENT                      │
│                                                          │
│  Campaign Lobby  Hero Creator  Tactical World  HUD/UX   │
│          │             │            │          │         │
│          └─────────────┴──────┬─────┴──────────┘         │
│                               │                           │
│                    RPGClient / AppState                   │
└───────────────────────────────┼───────────────────────────┘
                                │ REST + WebSocket
                                ▼
┌──────────────────────────────────────────────────────────┐
│                  dnd-rpg-engine server                   │
│                                                          │
│  Rules • State • Events • Commands • AI • Time • Saves  │
└──────────────────────────────────────────────────────────┘
```

The client follows one rule: **the engine owns truth; Godot renders truth**. A movement or attack click never edits campaign state locally. It sends a command and updates from the next authoritative state snapshot.

## Requirements

- Godot **4.7.1 stable** recommended.
- A running `dnd-rpg-engine` API, defaulting to `http://127.0.0.1:8000`.
- Advanced engine mode is required for the character lifecycle endpoints used by the Hero Creator.

## Run

Start the D&D RPG engine first, then open this repository in Godot and run the project.

```bash
# Example: from the dnd-rpg-engine repository
python -m dnd_rpg_engine.api
```

If your engine uses a different launch command, use that command instead. In the Godot lobby, change the server address from `http://127.0.0.1:8000` to the correct endpoint and select **Refresh**.

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
| `Esc` | Return to campaign library |

## Main project structure

```text
autoload/
  AppState.gd       Persistent endpoint, identity, campaign and selection state
  RPGClient.gd      Non-blocking REST + WebSocket engine bridge

game/
  WorldView.gd      Tactical map renderer and world input

scenes/
  Main.tscn         Playable entry scene

ui/
  Main.gd           Lobby, Hero Creator, HUD, party, inspector and event feed
```

## Engine surfaces used

The client currently integrates with:

- `GET /api/v1/campaigns`
- `POST /api/v1/campaigns`
- `POST /api/v1/campaigns/{campaign_id}/join`
- `GET /api/v1/campaigns/{campaign_id}/characters`
- `GET /api/v1/campaigns/{campaign_id}/characters/catalog`
- `POST /api/v1/campaigns/{campaign_id}/characters`
- `WS /api/v1/campaigns/{campaign_id}/ws`

The WebSocket sends `state` requests and command envelopes and consumes authoritative `state`, `event`, `ack`, and `error` messages.

## Next presentation layer expansions

The architecture is ready for dedicated inventory/equipment, spellbook, quest journal, dialogue, shop/loot, codex, fog-of-war, encounter initiative/reactions, richer animation/VFX/audio, imported campaign maps, and a GM-specific workspace without moving rules into Godot.
