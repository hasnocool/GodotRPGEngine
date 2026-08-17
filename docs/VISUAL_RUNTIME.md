# Visual World Runtime v0.3

`VisualRuntime` is the Godot presentation adapter for the `dnd-rpg-engine` `RuntimeSnapshot` contract.

The server remains authoritative. Godot consumes actor-scoped runtime snapshots and renders only the entities, facts, and bindings the engine exposes to that actor.

## Authority model

When a WorldPlatform runtime snapshot is available, `WorldView` uses `snapshot.entities` instead of merging the broader campaign entity collection. This is deliberate: unknown or hidden entities must stay absent from the renderer.

Godot does not calculate:

- visibility or fog ownership;
- movement validity or pathfinding;
- line of sight, cover, or range;
- combat results;
- scene activation rules;
- AI decisions;
- authoritative action availability.

The renderer may animate an already-authoritative event or draw a server-described path/fog region, but the presentation never turns that visual into trusted state.

## Runtime snapshot

The adapter consumes:

```json
{
  "sequence": 12,
  "campaign_id": "campaign-id",
  "simulation_time": 42.5,
  "active_map_id": "blackwater",
  "entities": {},
  "facts": {},
  "bindings": {},
  "snapshot_hash": "..."
}
```

The endpoint used is:

```text
GET /api/v1/campaigns/{campaign_id}/runtime?actor_id={actor_id}
```

If the server is running only `AdvancedGameEngine`, the endpoint may return `409`. `VisualRuntime` treats that as a graceful downgrade and the original procedural `WorldView` remains usable.

## Visual bindings

The engine's `VisualBinding` model can expose:

```json
{
  "entity_id": "hero-1",
  "scene": null,
  "sprite": "res://content/heroes/ranger.png",
  "model": null,
  "animation_set": "idle",
  "metadata": {
    "scale": 1.0,
    "sprite_size": 64,
    "token_radius": 24,
    "tint": "ffffff",
    "animation_fps": 8,
    "animation_frames": {
      "idle": [
        "res://content/heroes/ranger_idle_0.png",
        "res://content/heroes/ranger_idle_1.png"
      ]
    }
  }
}
```

v0.3 renders `sprite` and optional frame sequences. `scene` and `model` remain reserved for richer 2D/3D presentation hosts.

### Asset safety

Runtime metadata can select only packaged Godot resources that already exist under `res://`.

The client rejects:

- HTTP/HTTPS assets;
- absolute filesystem paths;
- paths containing `..`;
- missing resources.

That keeps the server from turning presentation metadata into arbitrary local file access.

## Map presentation facts

The client recognizes any of these fact IDs:

```text
map_visual
visual_map
map_presentation
```

A useful value is:

```json
{
  "texture": "res://content/maps/blackwater.png",
  "world_rect": {
    "x": -20,
    "y": -15,
    "width": 40,
    "height": 30
  },
  "hide_grid": false,
  "tint": "ffffff"
}
```

When `world_rect` is omitted, the texture is treated as a screen-filling backdrop.

## Fog and visibility presentation

The knowledge snapshot itself is the primary visibility boundary. In addition, the renderer can draw explicit obscured cells or regions when the server publishes one of:

```text
fog_of_war
fog
visibility_mask
```

Example:

```json
{
  "cell_size": 1,
  "hidden_cells": [[3, 4], [4, 4]],
  "hidden_regions": [
    {"x": 8, "y": 2, "width": 5, "height": 3, "alpha": 0.85}
  ]
}
```

The client does not infer hidden cells from distance or obstacles.

## Authoritative path overlays

The renderer recognizes:

```text
movement_path
path_preview
authoritative_path
```

Example:

```json
{
  "authoritative": true,
  "points": [
    {"x": 1, "y": 1},
    {"x": 2, "y": 1},
    {"x": 3, "y": 2}
  ]
}
```

This is visual-only. A movement click still submits a normal movement command and the engine validates it.

## Scene transitions

A change in `active_map_id` emits `VisualRuntime.map_changed`. `WorldView` recenters on the player and displays a short fade/title transition. The client does not activate maps or scenes itself.

## Event presentation

Authoritative WebSocket events feed lightweight VFX:

- source pulses;
- attack/spell/impact lines;
- target pulses;
- short labels;
- optional packaged one-shot audio.

If an event payload contains a local `audio` or `sound` path under `res://`, the client can play it. No event changes state locally.

## Ambience

Runtime facts may expose one of:

```text
ambience
ambient_audio
map_ambience
```

The value may be a resource path or a dictionary containing `path`/`audio`. Only safe packaged `res://` audio is loaded.

## Fallback behavior

A fresh clone still works with no visual assets at all:

1. procedural dark backdrop;
2. tactical grid;
3. colored entity tokens;
4. nameplates and HP bars.

A content pack can incrementally replace those fallbacks with maps, sprites, animation frames, fog descriptors, paths, VFX cues, and ambience without changing trusted gameplay code.
