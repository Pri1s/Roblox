# Roblox Project Setup Guide

> This document instructs an AI agent on how to scaffold a new Roblox game project using a module-based architecture with a clean, predictable folder structure. Follow every step precisely before writing any game logic.

---

## Philosophy

All game logic lives in **ModuleScripts**. Plain Scripts and LocalScripts are only used as thin loaders — they do not contain logic themselves. Every module is placed based on a single question:

> **Who runs this code — the server, the client, or both?**

This determines exactly where the module lives.

---

## Step 1 — Build the Folder Structure

Create the following folders in the Roblox Explorer. Do not deviate from this layout.

### ServerScriptService

```
ServerScriptService/
├── ServerModules/          ← ModuleScripts run only by the server
└── loader.server.lua       ← Server loader script (see Step 3)
```

### ReplicatedStorage

```
ReplicatedStorage/
├── Modules/
│   ├── Client/             ← ModuleScripts run only by the client
│   ├── Shared/             ← ModuleScripts accessed by both server and client
│   └── Utility/            ← Stateless helper modules (converters, generators, etc.)
├── Networking/             ← RemoteEvents and RemoteFunctions
└── Assets/                 ← Models, effects, sounds, animations (organized into subfolders by category)
```

### StarterPlayerScripts

```
StarterPlayerScripts/
└── Starter.client.lua      ← Client loader script (see Step 3)
```

---

## Step 2 — Module Script Conventions

Every ModuleScript that needs to run on game start must expose exactly two functions:

```lua
local MyModule = {}

-- Runs first. Use this to fetch dependencies or set up state
-- that other modules may need before Start is called.
function MyModule.Init()

end

-- Runs after all Init functions have completed.
-- Main logic goes here.
function MyModule.Start()

end

return MyModule
```

**Rules:**

- `Init` always runs before `Start`, across all modules.
- If a module does not need to auto-run (i.e., it is only ever `require()`d by another module), it does not need `Init` or `Start`.
- Utility modules in `Modules/Utility/` typically do not need `Init` or `Start`.

### Handling Circular Dependencies

Two options are available:

1. **Declare variables at the top, assign inside `Init`** — you lose Luau intellisense but avoid the dependency cycle.
2. **Use `_G` as a global module table** — load each module into `_G` during the loader pass so any module can access others via `_G.ModuleName`. Note: `_G` is non-standard and you lose intellisense. Use it deliberately.

---

## Step 3 — Write the Module Loaders

### Server Loader (`ServerScriptService/loader.server.lua`)

```lua
-- Collects all modules from ServerModules and Shared,
-- sorts them by a Priority attribute (lower number = higher priority),
-- calls Init on all of them first, then Start on all of them.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerModules = ServerScriptService.ServerModules
local SharedModules = ReplicatedStorage.Modules.Shared

local function collectModules(folder)
    local modules = {}
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("ModuleScript") then
            table.insert(modules, obj)
        end
    end
    return modules
end

local function sortByPriority(modules)
    table.sort(modules, function(a, b)
        local pa = a:GetAttribute("Priority") or 0
        local pb = b:GetAttribute("Priority") or 0
        return pa < pb
    end)
end

local allModules = {}
for _, m in ipairs(collectModules(ServerModules)) do table.insert(allModules, m) end
for _, m in ipairs(collectModules(SharedModules)) do table.insert(allModules, m) end

sortByPriority(allModules)

local loaded = {}
for _, m in ipairs(allModules) do
    local mod = require(m)
    _G[m.Name] = mod
    table.insert(loaded, mod)
end

for _, mod in ipairs(loaded) do
    if mod.Init then mod.Init() end
end

for _, mod in ipairs(loaded) do
    if mod.Start then mod.Start() end
end
```

### Client Loader (`StarterPlayerScripts/Starter.client.lua`)

```lua
-- Waits for the server to signal that all server modules have finished loading,
-- then loads all Client and Shared modules.
-- WaitForChild is used here intentionally — replication timing from the server
-- is not guaranteed when this LocalScript first runs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Client")
local SharedModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared")
local ClientReady = ReplicatedStorage:WaitForChild("Networking"):WaitForChild("ClientReady")

-- Block until server confirms all server modules have loaded
ClientReady:InvokeServer()

local function collectModules(folder)
    local modules = {}
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("ModuleScript") then
            table.insert(modules, obj)
        end
    end
    return modules
end

local function sortByPriority(modules)
    table.sort(modules, function(a, b)
        local pa = a:GetAttribute("Priority") or 0
        local pb = b:GetAttribute("Priority") or 0
        return pa < pb
    end)
end

local allModules = {}
for _, m in ipairs(collectModules(ClientModules)) do table.insert(allModules, m) end
for _, m in ipairs(collectModules(SharedModules)) do table.insert(allModules, m) end

sortByPriority(allModules)

local loaded = {}
for _, m in ipairs(allModules) do
    local mod = require(m)
    _G[m.Name] = mod
    table.insert(loaded, mod)
end

for _, mod in ipairs(loaded) do
    if mod.Init then mod.Init() end
end

for _, mod in ipairs(loaded) do
    if mod.Start then mod.Start() end
end
```

---

## Step 4 — Create the Players Manager Module

This is a **server module** and must be the last server module to load. Set its `Priority` attribute to `10` (or the highest number among all server modules).

Place it at: `ServerScriptService/ServerModules/PlayersManager`

```lua
local PlayersManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local registeredPlayers = {}

local function onPlayerAdded(player)
    if registeredPlayers[player] then return end
    registeredPlayers[player] = true

    -- Add per-player setup logic here
end

local function onPlayerRemoving(player)
    registeredPlayers[player] = nil

    -- Add per-player teardown logic here
end

function PlayersManager.Init()

end

function PlayersManager.Start()
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Handle players who joined before this module loaded
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end

    -- Signal the client that all server modules have finished loading
    local ClientReady = ReplicatedStorage.Networking.ClientReady
    ClientReady.OnServerInvoke = function() return true end
end

return PlayersManager
```

---

## Step 5 — Set Module Priorities

Each ModuleScript can have a `Priority` attribute (integer). Lower numbers load first.

| Priority | Use case                                                                |
| -------- | ----------------------------------------------------------------------- |
| `0`      | Default — no specific load order needed                                 |
| `1–4`    | Core systems other modules depend on (e.g., data stores, configuration) |
| `5–9`    | Feature systems                                                         |
| `10`     | `PlayersManager` — always last on the server                            |

To set a priority in Studio: select the ModuleScript → Add Attribute → name it `Priority`, type `number`.

---

## Step 6 — Organize Assets

Inside `ReplicatedStorage/Assets/`, create subfolders by category. Example:

```
Assets/
├── Models/
├── Effects/
├── Sounds/
└── Animations/
```

All asset references in code should point here. Never scatter assets across the workspace or other services.

---

## Checklist Before Writing Any Game Logic

- [ ] Folder structure matches Step 1 exactly
- [ ] Server loader exists in `ServerScriptService`
- [ ] Client loader exists in `StarterPlayerScripts`
- [ ] `PlayersManager` module exists with `Priority = 10`
- [ ] `ClientReady` RemoteFunction exists inside `ReplicatedStorage/Networking/`
- [ ] All new modules are placed in the correct folder based on who runs them
- [ ] All modules that auto-run expose `Init` and `Start`
