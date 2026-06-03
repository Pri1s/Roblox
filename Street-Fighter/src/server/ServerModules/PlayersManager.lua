-- Manages player lifecycle. Must be the last server module to load (Priority = 10).
-- Signals the client that the server is ready via the ClientReady RemoteFunction.

local PlayersManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local registeredPlayers = {}

-- Runs per-player setup logic; guards against duplicate calls
local function onPlayerAdded(player)
	if registeredPlayers[player] then return end
	registeredPlayers[player] = true

	-- Add per-player setup logic here
end

-- Cleans up per-player state on departure
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
