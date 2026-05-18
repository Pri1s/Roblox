# Workflow

> Read this before starting any task. These conventions apply to every session, every file, every change. When uncertain about an architectural decision, ask the engineer rather than guessing.

---

## Project Structure

This project uses a module-based architecture. Before writing any code, understand where things live:

```
ServerScriptService/
├── ServerModules/          ← Server-only ModuleScripts
│   └── Services/           ← Server services
└── loader.server.lua       ← Server loader (do not modify unless changing load behavior)

ReplicatedStorage/
├── Modules/
│   ├── Client/             ← Client-only ModuleScripts
│   │   └── Services/       ← Client services
│   ├── Shared/             ← ModuleScripts used by both server and client
│   │   ├── Services/       ← Shared services
│   │   └── Behaviors/      ← Behaviors reused across multiple services
│   └── Utility/            ← Stateless helpers, no Init/Start needed
├── Networking/             ← All RemoteEvents and RemoteFunctions
└── Assets/                 ← Models, sounds, effects, animations

StarterPlayerScripts/
└── Starter.client.lua      ← Client loader (do not modify unless changing load behavior)
```

When adding any new script, answer this first: **who runs it — server, client, or both?** That answer determines the folder. Do not place scripts anywhere outside this structure.

---

## Child Access

Use dot notation or bracket notation when a child is known to exist at runtime:

```lua
-- Correct
local Networking = ReplicatedStorage.Networking
local ClientReady = ReplicatedStorage.Networking.ClientReady

-- Also correct for dynamic keys
local module = ServerModules["MyModule"]
```

Only use `:WaitForChild()` on the **client**, when accessing `ReplicatedStorage` contents. Replication timing from the server is not guaranteed when a LocalScript first runs. This is the only acceptable use.

```lua
-- Correct — client accessing ReplicatedStorage on startup
local ClientModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Client")

-- Wrong — server does not need WaitForChild
local ServerModules = ServerScriptService:WaitForChild("ServerModules") -- never do this
```

Only use `:FindFirstChild()` when the child's existence is genuinely uncertain and you are explicitly handling the nil case. If you are not handling nil, use dot notation.

---

## Networking

- Use `RemoteEvent` for one-way server → client or client → server communication.
- Use `RemoteFunction` when a response is required (e.g. the client handshake in the loader).
- All remotes live in `ReplicatedStorage.Networking`. Never create remotes elsewhere.
- Do not use third-party networking libraries.

---

## Module Conventions

Every module that auto-runs on game start exposes exactly two functions:

```lua
function MyModule.Init()
    -- Fetch dependencies, set up state other modules may need.
    -- Do not call other modules' functions here.
end

function MyModule.Start()
    -- Main logic. All Init functions across all modules have already run.
end
```

- `Init` runs first across all modules, then `Start` runs across all modules.
- Modules that are only ever `require()`d by other modules do not need `Init` or `Start`.
- Utility modules in `Modules/Utility/` do not need `Init` or `Start`.

**Load order** is controlled by a `Priority` attribute (integer) on each ModuleScript. Lower numbers load first. `PlayersManager` always runs last on the server at priority `10`.

---

## Cross-Module References

When a module needs another module, use `_G` lookup. The loader places every loaded module into `_G` keyed by its name, so any module can access any other after the loader's first pass.

```lua
function WeaponService.Init()
    -- Capture references during Init. Do not call methods yet.
    DataService = _G.DataService
end

function WeaponService.Start()
    -- Safe to call other services here; all Inits have run.
    DataService.GetPlayerData(player)
end
```

- Do not `require()` other services directly. It risks circular dependencies and bypasses the load order.
- Capture references in `Init`, use them in `Start` or later.
- `_G` loses intellisense — this is a deliberate trade for decoupling.

---

## Server / Client Boundary

The server loads fully before the client starts. This is enforced by the loader handshake — `PlayersManager` fires `ClientReady` only after all server modules have run. Do not write code that assumes the client is ready before this signal.

When deciding where a system lives:

- Does it touch player data, game state, or anything that must be authoritative? → Server.
- Does it touch UI, input, or local visual feedback? → Client.
- Does both sides need the same logic (e.g. a math utility, a shared config)? → Shared or Utility.

---

## Services

A service is a singleton module that other modules depend on. Services own foundational responsibilities (data, players, vehicles, weapons) and expose a public API for systems to consume.

- Services live in a `Services/` subfolder within their domain (server, client, or shared).
- Services get a low `Priority` (1–4) so they initialize before systems that depend on them.
- Services expose a documented public API at the top of the module. Systems consume only that API — never reach into service internals.
- Name services with the `Service` suffix: `DataService`, `VehicleService`, `WeaponService`.

**Decision rule:** if other modules depend on it to function, it is a service.

---

## Systems and Composition

Systems are feature-level modules built **by composition, not inheritance**. A system is composed of:

- A **Base** module (shared lifecycle: equip, cooldowns, ownership)
- One or more **Behaviors** (single-responsibility logic: Hitscan, Melee, Engine, Steering)
- A **Registry** (data-only entries declaring which behaviors and stats a variant uses)

**Inheritance is not used.** Do not write metatable class hierarchies. Variants differ by data and behavior composition, not by class extension.

**Behavior placement:**

- Used by one service only → inside that service's folder.
- Reused across multiple services → in `Modules/Shared/Behaviors/`.

---

## Adding a New Feature

1. Decide: is this a **service** (other modules will depend on it) or a **system** (a feature consuming services)?
2. Place the module in the correct folder per the rules above.
3. If it auto-runs, add `Init` and `Start`.
4. If it is a service, set `Priority` 1–4 and document its public API at the top of the file.
5. If it is a system using composition, define the Registry as data and split logic into Behaviors.
6. If it depends on another service, capture the `_G` reference in `Init`.
7. Do not modify the loaders unless the loading behavior itself needs to change.
