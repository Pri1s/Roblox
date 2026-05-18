local PlayersManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local registeredPlayers = {}

local function onPlayerAdded(player)
	if registeredPlayers[player] then
		return
	end
	registeredPlayers[player] = true

	-- Add per-player setup logic here
end

local function onPlayerRemoving(player)
	registeredPlayers[player] = nil

	-- Add per-player teardown logic here
end

function PlayersManager.Init() end

function PlayersManager.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players who joined before this module loaded
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Signal the client that all server modules have finished loading
	local ClientReady = ReplicatedStorage.Networking.ClientReady
	ClientReady.OnServerInvoke = function()
		return true
	end
end

return PlayersManager
