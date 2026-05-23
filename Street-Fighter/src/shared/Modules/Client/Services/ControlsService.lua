local ControlsService = {}

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local controls
local setControlsEnabledRemote
local BLOCK_FORWARD_BACK_ACTION = "ControlsService.BlockForwardBack"
local BLOCK_FORWARD_BACK_PRIORITY = Enum.ContextActionPriority.High.Value

-- Blocks keyboard forward/back movement input. Parameters: actionName, inputState, and inputObject are supplied by ContextActionService.
local function blockForwardBackMovement(actionName, inputState, inputObject)
	return Enum.ContextActionResult.Sink
end

-- Enables or disables W/S movement blocking. Parameters: blocked (boolean) determines whether forward/back movement input is swallowed.
local function setForwardBackMovementBlocked(blocked)
	if blocked then
		ContextActionService:BindActionAtPriority(
			BLOCK_FORWARD_BACK_ACTION,
			blockForwardBackMovement,
			false,
			BLOCK_FORWARD_BACK_PRIORITY,
			Enum.KeyCode.W,
			Enum.KeyCode.S
		)
	else
		ContextActionService:UnbindAction(BLOCK_FORWARD_BACK_ACTION)
	end
end

-- Enables or disables the local player's controls. Parameters: enabled (boolean) determines the requested control state, blockForwardBack (boolean?) blocks W/S movement.
local function setControlsEnabled(enabled, blockForwardBack)
	if not controls then
		return
	end

	if enabled then
		controls:Enable()
		setForwardBackMovementBlocked(blockForwardBack == true)
	else
		setForwardBackMovementBlocked(false)
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
