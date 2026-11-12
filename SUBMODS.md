# GCapture submods

A **submod** is a separate addon (usually a Steam Workshop item) that extends GCapture without touching its files.
Submods can add national spirits, spirit modifiers, structures, right-click actions and react to game events.

GCapture loads submods automatically from every mounted addon, so players just subscribe to the submod on the Workshop.

## Folder layout of a submod

```
my_submod/                       <- your addon folder (what you upload to the Workshop)
├─ addon.json
├─ lua/gcapture/mods/my_submod/  <- the folder name is the submod id (lowercase, no spaces)
│   ├─ shared.lua                <- runs on server AND client: register content here
│   ├─ server.lua                <- optional, server only: hooks with game logic
│   └─ client.lua                <- optional, client only: UI, effects
└─ materials/my_submod/...       <- your icons (png), sounds, etc.
```

A folder starting with `_` or `.` is ignored. At least one of the three files must exist. A ready-to-copy template is in `example_submod/`.

## Load order

1. GCapture core `shared.lua` → all `shared.lua` of submods (alphabetical by folder name) → core `server.lua` / `client.lua`.
2. After every core file is loaded: `server.lua` / `client.lua` of submods, then the hook `GCapture_ModsLoaded` fires.

The client asks the server which submods are active and loads exactly those, in the same order, so numeric ids of structures and actions are identical on both sides. Because of this **never register content conditionally** in `shared.lua` (no `if math.random()`, no `if file.Exists(...)` that can differ between server and client).

## API (call it from `shared.lua`)

`local GC = GCapture; local M = GC.Mods`

### `M.Register(info)`
Optional metadata. `{ name, version, author, desc, api = 1, workshop = "1234567890" }`.
`workshop` is the Workshop id of your submod: the server then calls `resource.AddWorkshop` for you, so clients download your icons and sounds.

### `M.AddSpirit(id, def)`
Adds a national spirit. It automatically appears in the "choose 1 of 3" screen and chests.
`def` is the same table as for core spirits (`GC.SpiritDefs` in `shared.lua`):
`name`, `mods = { attack = 0.05, ... }`, `biome = { [GC.FOREST] = { attack = 0.1 } }`, `rare = true` (chests only), `target`/`vs` (like the Hate spirit).

- `id` must be unique across the whole game, so prefix it with your submod id (`my_submod_spirit`). No spaces or `:`.
- Allowed keys in `mods`: the core ones (`GC.ModOrder`) plus those you added with `AddModifier`.

### `M.AddModifier(key, info)`
Adds a new spirit modifier: `{ label = "Tax income", pct = false, unit = " sec", income = "coins" }`.
With `income = "coins" | "pop" | "weapons"` the sum of the modifier over the player's spirits is added to that resource every second.
Without `income` it is only stored; read it with `GCapture.Mod(slot, key)` in your own code.

### `M.AddBuild(key, def)` → numeric id
Adds a structure: `{ name, icon, coin, weapon, popinc, lifetime }`.
`icon` is a path relative to `materials/`. `coin` / `weapon` / `popinc` are income per second, `lifetime` is how many seconds the structure lasts (nil = forever).
The id is 14 or more. Look it up later with `GC.Mods.BuildId[key]`, and compare with `GC.build[cell]`.

### `M.AddAction(key, def)` → numeric id
Adds an item to the right-click menu of a cell.

| field | meaning |
|---|---|
| `name`, `icon`, `desc` | label, menu icon (default brown action icon), tooltip |
| `coins`, `pop`, `weapons` | price; checked and paid by the core |
| `build = "key"` | the action builds that structure (core rules apply: own empty cell connected to the capital) |
| `biome = 3`, `coast = true` | only on that biome / only on the coast (like core actions) |
| `run = function(ply, slot, cell, cell2, P)` | **server**: effect of an action without a structure (price is already paid) |
| `can = function(ply, slot, cell, cell2)` | **server**: return `true`, or `false, "reason shown to the player"` |
| `where` | `"empty_own"` (default for `build`), `"own"` (default for `run`), `"enemy"`, `"neutral"`, `"any"` |
| `on = "build_key"` | only on your own cell with that structure |
| `water = true`, `any = true` | action for water cells / for any cell (like in the core) |
| `show = function(slot, cell)` | **client**: extra condition to show the item |

Always validate on the server (`can`, `where`, `on`); the client only decides what to show.
Actions that need to select a second target cell are not supported yet (`cell2` is always 0).

## Hooks

Server:

| hook | arguments |
|---|---|
| `GCapture_GameStarted` | – |
| `GCapture_GameEnded` | `winnerSlot` |
| `GCapture_CellChanged` | `cell, oldOwner, newOwner, oldBuild, newBuild` |
| `GCapture_Placed` | `cell, slot, buildId` (structure built or placed) |
| `GCapture_Income` | `slot, I, P` – every second; `I[1]` coins, `I[2]` population, `I[3]` weapons per second, change them freely |

Both realms: `GCapture_ModsLoaded` (all submods loaded).

Handy core globals: `GC.owner[cell]`, `GC.build[cell]`, `GC.biome[cell]`, `GC.army[cell]`, `GC.Slots[slot]` (server: `coins`, `pop`, `weapons`, `spirits`), `GC.Mod(slot, key)`, `GCN` (cell count), `GC.XY(cell)`.

## Publishing to the Workshop

1. Make an addon folder like in the layout above with an `addon.json` (see `example_submod/addon.json`; `type` can stay `"tool"`).
2. Upload it with **gmpublisher** (easiest) or `gmad.exe` + `gmpublish.exe`.
3. Put your own Workshop id into `M.Register({ workshop = "..." })` after the first upload and update the item.
4. Server owners: add the submod to the server's Workshop collection (or `resource.AddWorkshop`). Players on listen servers get the Lua automatically; the `workshop` field makes them download the icons too.

## For server owners

* `gc_mods` in the console lists loaded submods and shows `(FAILED)` for those that raised an error (the rest keep working).
* To disable a submod without unsubscribing, put its id (one per line) into `garrysmod/data/gcapture_disabled_mods.txt` and restart the map. Lines starting with `#` are comments.

## Limitations (API version 1)

* Not extensible yet: biomes, game options, random events, bot AI (bots ignore submod structures and actions), the income estimate shown in the HUD (real income is correct, the preview ignores submod structures).
* A replay that contains a submod structure or spirit shows "Unknown" for it if the viewer does not have that submod.
* Do not change the set or order of submods in the middle of a match.
* Structure ids are limited to 63 and action ids to 255 (core uses 13 and 31).

## What changed in the core files

* `shared.lua`: `GC.BuildBits = 6`, `GC.ActBits = 8` (network id width; was 4 and 5 bits and already full) and the whole submod loader/API at the end of the file.
* `server.lua`: the widths above, hooks (`CellChanged`, `Placed`, `Income`, `GameStarted`, `GameEnded`), submod actions in `GCapture_Act`, `lifetime`/`popinc` for submod structures.
* `client.lua`: the widths above, submod items in the cell menu, icons of submod structures (`GC.BuildMats`), safe tooltip for an unknown structure.

Clients and servers must run the same GCapture version, as the network format changed.
