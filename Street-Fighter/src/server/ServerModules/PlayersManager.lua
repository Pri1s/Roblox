local PlayersManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local registeredPlayers = {}

-- Registers setup state for a joining player. Parameters: player (Player) is the player being added.
local function onPlayerAdded(player)
	if registeredPlayers[player] then
		return
	end
	registeredPlayers[player] = true

	-- Add per-player setup logic here
end

-- Clears setup state for a leaving player. Parameters: player (Player) is the player being removed.
local function onPlayerRemoving(player)
	registeredPlayers[player] = nil

	-- Add per-player teardown logic here
end

-- Initializes player manager dependencies. Parameters: none.
function PlayersManager.Init() end

-- Connects player lifecycle handlers and enables the client-ready handshake. Parameters: none.
function PlayersManager.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players who joined before this module loaded
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Signal the client that all server modules have finished loading
	local ClientReady = ReplicatedStorage.Networking.ClientReady
	-- Responds to client-ready handshake requests after server modules load. Parameters: none.
	ClientReady.OnServerInvoke = function()
		return true
	end
end

return PlayersManager
