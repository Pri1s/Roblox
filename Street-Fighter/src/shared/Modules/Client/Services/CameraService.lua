local CameraService = {}

-- Public API
-- CameraService.EnableForSlot(arenaId, slotId) -> boolean
-- CameraService.Disable(reason) -> nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local setFightCameraRemote
local RunSchedulerService
local activeCameraPart
local initialHeightOffset = 0
local warnedMessages = {}
local debugSessionId = 0
local debugUpdateCount = 0
local debugStartedAt = 0
local lastDebugUpdateLogAt = 0

local SCHEDULER_ID = "FightCamera"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value
local DEBUG_PREFIX = "[CameraService][FightCamera] "
local INITIAL_UPDATE_LOG_COUNT = 8
local UPDATE_LOG_INTERVAL_SECONDS = 1
local UPDATE_LOG_DURATION_SECONDS = 8

-- Prints a fight camera debug message. Parameters: message (string) is the diagnostic text to emit.
local function debugLog(message)
	print(DEBUG_PREFIX .. message)
end

-- Formats a Vector3 for readable debug output. Parameters: value (Vector3?) is the position to format.
local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return "nil"
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

-- Formats an Instance path for readable debug output. Parameters: instance (Instance?) is the object to describe.
local function formatInstancePath(instance)
	if not instance then
		return "nil"
	end

	return instance:GetFullName()
end

-- Reports whether an update tick should be logged. Parameters: now (number) is the current os.clock value.
local function shouldLogUpdate(now)
	if debugUpdateCount <= INITIAL_UPDATE_LOG_COUNT then
		return true
	end

	return now - debugStartedAt <= UPDATE_LOG_DURATION_SECONDS
		and now - lastDebugUpdateLogAt >= UPDATE_LOG_INTERVAL_SECONDS
end

-- Warns once for a repeated camera setup issue. Parameters: key (string) deduplicates the warning and message (string) is shown.
local function warnOnce(key, message)
	if warnedMessages[key] then
		return
	end

	warnedMessages[key] = true
	warn(DEBUG_PREFIX .. message)
end

-- Gets the local character root part if it is available. Parameters: none.
local function getCharacterRoot()
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

-- Finds the configured camera part for an arena slot. Parameters: arenaId and slotId identify Workspace.Arenas/<arenaId>/CameraParts/<slotId>.
local function getCameraPart(arenaId, slotId)
	local arenas = Workspace:FindFirstChild("Arenas")
	local arena = arenas and arenas:FindFirstChild(tostring(arenaId))
	local cameraParts = arena and arena:FindFirstChild("CameraParts")
	local cameraPart = cameraParts and cameraParts:FindFirstChild(tostring(slotId))

	if cameraPart and cameraPart:IsA("BasePart") then
		return cameraPart
	end

	return nil
end

-- Stops the scriptable fight camera and restores Roblox's default camera mode. Parameters: reason (string?) describes why it stopped.
function CameraService.Disable(reason)
	local wasBound = RunSchedulerService and RunSchedulerService.IsBound(SCHEDULER_ID)
	debugLog(
		"Disable requested; reason="
			.. tostring(reason or "unspecified")
			.. ", wasBound="
			.. tostring(wasBound)
			.. ", activeCameraPart="
			.. formatInstancePath(activeCameraPart)
	)

	if RunSchedulerService then
		RunSchedulerService.Unbind(SCHEDULER_ID)
	end

	activeCameraPart = nil

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

-- Updates the active camera part and applies it to CurrentCamera. Parameters: none.
local function updateCamera()
	local rootPart = getCharacterRoot()
	local currentCamera = Workspace.CurrentCamera
	if not rootPart or not currentCamera or not activeCameraPart or activeCameraPart.Parent == nil then
		warnOnce(
			"LostCameraTarget",
			"Fight camera target was lost; rootPart="
				.. formatInstancePath(rootPart)
				.. ", currentCamera="
				.. formatInstancePath(currentCamera)
				.. ", activeCameraPart="
				.. formatInstancePath(activeCameraPart)
		)
		CameraService.Disable("LostCameraTarget")
		return
	end

	debugUpdateCount = debugUpdateCount + 1

	local currentCFrame = activeCameraPart.CFrame
	local currentRotation = currentCFrame - currentCFrame.Position
	local newPosition = Vector3.new(
		rootPart.Position.X,
		rootPart.Position.Y + initialHeightOffset,
		currentCFrame.Position.Z
	)

	activeCameraPart.CFrame = CFrame.new(newPosition) * currentRotation
	currentCamera.CFrame = activeCameraPart.CFrame

	local now = os.clock()
	if shouldLogUpdate(now) then
		lastDebugUpdateLogAt = now
		debugLog(
			"Update #"
				.. tostring(debugUpdateCount)
				.. "; root="
				.. formatVector3(rootPart.Position)
				.. ", cameraPartBefore="
				.. formatVector3(currentCFrame.Position)
				.. ", cameraPartAfter="
				.. formatVector3(activeCameraPart.Position)
				.. ", currentCamera="
				.. formatVector3(currentCamera.CFrame.Position)
				.. ", initialHeightOffset="
				.. tostring(initialHeightOffset)
		)
	end
end

-- Enables the scriptable fight camera for an arena slot. Parameters: arenaId and slotId identify the configured camera part to follow.
function CameraService.EnableForSlot(arenaId, slotId)
	debugSessionId = debugSessionId + 1
	debugUpdateCount = 0
	debugStartedAt = os.clock()
	lastDebugUpdateLogAt = 0

	debugLog(
		"EnableForSlot start; session="
			.. tostring(debugSessionId)
			.. ", arenaId="
			.. tostring(arenaId)
			.. ", slotId="
			.. tostring(slotId)
			.. ", schedulerAvailable="
			.. tostring(RunSchedulerService ~= nil)
	)

	if not RunSchedulerService then
		warnOnce("MissingRunSchedulerService", "RunSchedulerService is missing; fight camera was not enabled")
		return false
	end

	local cameraPart = getCameraPart(arenaId, slotId)
	if not cameraPart then
		warnOnce(
			"MissingCameraPart:" .. tostring(arenaId) .. ":" .. tostring(slotId),
			"Arena " .. tostring(arenaId) .. " camera slot " .. tostring(slotId) .. " was not found"
		)
		CameraService.Disable("MissingCameraPart")
		return false
	end

	local rootPart = getCharacterRoot()
	if not rootPart then
		warnOnce("MissingCharacterRoot", "Local character is missing HumanoidRootPart; fight camera was not enabled")
		CameraService.Disable("MissingCharacterRoot")
		return false
	end

	activeCameraPart = cameraPart
	initialHeightOffset = cameraPart.Position.Y - rootPart.Position.Y
	debugLog(
		"Resolved targets; cameraPart="
			.. formatInstancePath(cameraPart)
			.. ", cameraPartPosition="
			.. formatVector3(cameraPart.Position)
			.. ", rootPart="
			.. formatInstancePath(rootPart)
			.. ", rootPosition="
			.. formatVector3(rootPart.Position)
			.. ", initialHeightOffset="
			.. tostring(initialHeightOffset)
	)

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Scriptable
		debugLog("CurrentCamera set to Scriptable; camera=" .. formatInstancePath(currentCamera))
	else
		debugLog("CurrentCamera is nil before binding render step")
	end

	RunSchedulerService.BindRenderStep(SCHEDULER_ID, RENDER_PRIORITY, updateCamera)
	debugLog(
		"BindRenderStep requested; schedulerId="
			.. SCHEDULER_ID
			.. ", priority="
			.. tostring(RENDER_PRIORITY)
			.. ", isBound="
			.. tostring(RunSchedulerService.IsBound(SCHEDULER_ID))
	)

	updateCamera()
	debugLog("EnableForSlot complete; session=" .. tostring(debugSessionId))

	return true
end

-- Captures replicated networking dependencies. Parameters: none.
function CameraService.Init()
	RunSchedulerService = _G.RunSchedulerService
	debugLog("Init; RunSchedulerService available=" .. tostring(RunSchedulerService ~= nil))

	setFightCameraRemote = ReplicatedStorage
		:WaitForChild("Networking")
		:WaitForChild("SetFightCamera")
	debugLog("Init; SetFightCamera remote=" .. formatInstancePath(setFightCameraRemote))
end

-- Listens for server fight camera assignment requests. Parameters: none.
function CameraService.Start()
	debugLog("Start; connecting SetFightCamera remote listener")

	-- Applies a server camera assignment. Parameters: enabled (boolean), arenaId, and slotId describe the camera state.
	setFightCameraRemote.OnClientEvent:Connect(function(enabled, arenaId, slotId)
		debugLog(
			"SetFightCamera received; enabled="
				.. tostring(enabled)
				.. ", arenaId="
				.. tostring(arenaId)
				.. ", slotId="
				.. tostring(slotId)
		)

		if enabled then
			CameraService.EnableForSlot(arenaId, slotId)
		else
			CameraService.Disable("RemoteDisabled")
		end
	end)
end

return CameraService
