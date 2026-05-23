local ControlsService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local controls
local setControlsEnabledRemote

-- Enables or disables the local player's controls. Parameters: enabled (boolean) determines the requested control state.
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

-- Captures local player controls and networking dependencies. Parameters: none.
function ControlsService.Init()
	local playerScripts = localPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()

	setControlsEnabledRemote = ReplicatedStorage
		:WaitForChild("Networking")
		:WaitForChild("SetControlsEnabled")
end

-- Listens for server control-toggle requests. Parameters: none.
function ControlsService.Start()
	setControlsEnabledRemote.OnClientEvent:Connect(setControlsEnabled)
end

return ControlsService
