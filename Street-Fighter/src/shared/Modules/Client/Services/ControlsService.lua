local ControlsService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local controls
local setControlsEnabledRemote

local function setControlsEnabled(enabled)
	if not controls then
		return
	end

	if enabled then
		controls:Enable()
	else
		controls:Disable()
	end
end

function ControlsService.Init()
	local playerScripts = localPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()

	setControlsEnabledRemote = ReplicatedStorage
		:WaitForChild("Networking")
		:WaitForChild("SetControlsEnabled")
end

function ControlsService.Start()
	setControlsEnabledRemote.OnClientEvent:Connect(setControlsEnabled)
end

return ControlsService
