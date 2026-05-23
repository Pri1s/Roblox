-- Collects all modules from ServerModules and Shared,
-- sorts them by a Priority attribute (lower number = higher priority),
-- calls Init on all of them first, then Start on all of them.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerModules = ServerScriptService.ServerModules
local SharedModules = ReplicatedStorage.Modules.Shared

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
for _, m in ipairs(collectModules(ServerModules)) do
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
