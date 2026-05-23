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

-- Collects every ModuleScript descendant in the given folder. Parameters: folder (Instance) is the root to scan.
local function collectModules(folder)
	local modules = {}
	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("ModuleScript") then
			table.insert(modules, obj)
		end
	end
	return modules
end

-- Sorts modules in-place by their Priority attribute. Parameters: modules ({ModuleScript}) is the list to sort.
local function sortByPriority(modules)
	-- Compares two modules by Priority for table.sort. Parameters: a and b (ModuleScript) are the modules being ordered.
	table.sort(modules, function(a, b)
		local pa = a:GetAttribute("Priority") or 0
		local pb = b:GetAttribute("Priority") or 0
		return pa < pb
	end)
end

local allModules = {}
for _, m in ipairs(collectModules(ClientModules)) do
	table.insert(allModules, m)
end
for _, m in ipairs(collectModules(SharedModules)) do
	table.insert(allModules, m)
end

sortByPriority(allModules)

local loaded = {}
for _, m in ipairs(allModules) do
	local mod = require(m)
	_G[m.Name] = mod
	table.insert(loaded, mod)
end

for _, mod in ipairs(loaded) do
	if mod.Init then
		mod.Init()
	end
end

for _, mod in ipairs(loaded) do
	if mod.Start then
		mod.Start()
	end
end
