# Authoritative Player Runtime

`PlayerRuntime` is the v0.2 player-facing bridge between the existing Godot tactical client and the richer character/world services exposed by `dnd-rpg-engine`.

## Design rule

Godot never calculates trusted RPG outcomes.

The client may format, sort, highlight, and offer controls, but HP, tracked resources, equipment, progression, rest outcomes, available knowledge, movement, combat, and action resolution remain server-owned.

```text
player input
    │
    ▼
Godot presentation
    │  REST / WebSocket intent
    ▼
dnd-rpg-engine
    │  validate / resolve / persist / emit
    ▼
authoritative snapshot + events
    │
    ▼
Godot presentation
```

## Implemented in v0.2

The `PlayerRuntime` autoload activates automatically once the engine resolves a player-owned actor.

### Compact runtime dock

- hero name and total level;
- class summary;
- live HP / max HP;
- authoritative timing/action-economy summary when the ruleset publishes it;
- one-click runtime refresh;
- `Tab` character sheet toggle.

### Character runtime sheet

The sheet renders the authoritative character detail endpoint:

- identity and progression;
- six ability scores;
- HP, temporary HP, and energy;
- tracked class resources;
- equipment slots;
- inventory quantities;
- conditions when exposed by the entity model;
- level eligibility;
- actor-scoped world runtime metadata.

### Lifecycle controls

The sheet calls the existing lifecycle API instead of editing state locally:

```text
POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/rest
POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/equip
POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/unequip
POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/resources/spend
POST /api/v1/campaigns/{campaign_id}/characters/{actor_id}/level-up
```

Rest profiles, equipment metadata, and class choices are populated from the live character catalog.

Level-up remains owner-authorized and is disabled in the UI for clients without an owner identity.

### Server-described actions

The runtime looks for action descriptors in authoritative entity/runtime metadata using the keys:

- `available_actions`;
- `action_palette`;
- `actions`.

It will display descriptors immediately. An action is executable only when the server includes an explicit `command` dictionary. The client deliberately refuses to guess a command from an action name or ID.

This creates a forward-compatible path for a fully ruleset-driven action palette without duplicating D&D action logic in GDScript.

### Knowledge-scoped runtime

When WorldPlatform mode is available, the client requests:

```text
GET /api/v1/campaigns/{campaign_id}/runtime?actor_id={player_actor_id}
```

This is intentionally actor-scoped. The server's knowledge authority determines which entities, bindings, map state, and facts are visible to the player.

Selected known facts whose IDs contain `quest`, `objective`, `journal`, `dialogue`, or `scene` are surfaced as an initial Journal / Known World Facts section. This is a presentation bridge, not a client-owned quest state store.

## Failure modes

The character lifecycle API requires `AdvancedGameEngine`. Actor-scoped runtime snapshots require `WorldPlatformEngine`.

If WorldPlatform runtime is unavailable, the sheet continues to operate with character lifecycle data and normal WebSocket campaign state. The optional runtime section reports that the snapshot is unavailable instead of fabricating world data.

## Next runtime slices

The next extensions should build on this contract rather than introduce local rules:

1. typed server `available_actions` / targeting schema;
2. authoritative valid-target, range, LOS, and cover overlays;
3. dedicated spell/ability book backed by ruleset capabilities;
4. structured quest journal rather than fact-name discovery;
5. dialogue graph/session UI;
6. loot and shop transaction surfaces;
7. scene/travel transitions;
8. initiative/reaction windows and richer action-economy visualization;
9. runtime visual bindings for imported maps, sprites, animation sets, VFX, and audio.
