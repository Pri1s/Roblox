local CameraService = {}

-- Public API
-- CameraService.EnableEntrance(arenaId, playerOne, playerTwo) -> boolean
-- CameraService.EnableRound(arenaId, playerOne, playerTwo) -> boolean
-- CameraService.Disable(reason) -> nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local setFightCameraRemote
local RunSchedulerService
local activeCameraPart
local warnedMessages = {}
local debugSessionId = 0

local DEBUG_PREFIX = "[CameraService][FightCamera] "
local CHARACTER_ROOT_WAIT_SECONDS = 2
local ROUND_CAMERA_LOOP_ID = "CameraService.RoundCamera"
local ROUND_CAMERA_TRACKING_SPEED = 12
local PRIMARY_TRACKER_NAME = "Tracker"
local LEGACY_TRACKER_NAME = "1"
local PLAYER_ONE_TRACKER_NAME = "1"
local PLAYER_TWO_TRACKER_NAME = "2"
local CAMERA_MODE = {
	Entrance = "Entrance",
	Round = "Round",
}

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

-- Warns once for a repeated camera setup issue. Parameters: key (string) deduplicates the warning and message (string) is shown.
local function warnOnce(key, message)
	if warnedMessages[key] then
		return
	end

	warnedMessages[key] = true
	warn(DEBUG_PREFIX .. message)
end

-- Gets a player's character root part if it is available. Parameters: player (Player?) owns the character to inspect.
local function getCharacterRoot(player)
	local character = player and player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

-- Waits briefly for both fighter root parts to replicate. Parameters: playerOne and playerTwo are the fighters, timeoutSeconds (number) is the max wait time.
local function waitForFighterRoots(playerOne, playerTwo, timeoutSeconds)
	local deadline = os.clock() + timeoutSeconds
	local playerOneRoot = getCharacterRoot(playerOne)
	local playerTwoRoot = getCharacterRoot(playerTwo)

	while (not playerOneRoot or not playerTwoRoot) and os.clock() < deadline do
		task.wait()
		playerOneRoot = getCharacterRoot(playerOne)
		playerTwoRoot = getCharacterRoot(playerTwo)
	end

	return playerOneRoot, playerTwoRoot
end

-- Finds the camera parts folder for an arena. Parameters: arenaId identifies Workspace.Arenas/<arenaId>/CameraParts.
local function getCameraPartsFolder(arenaId)
	local arenas = Workspace:FindFirstChild("Arenas")
	local arena = arenas and arenas:FindFirstChild(tostring(arenaId))

	return arena and arena:FindFirstChild("CameraParts")
end

-- Finds the configured entrance camera part for an arena. Parameters: cameraParts is Workspace.Arenas/<arenaId>/CameraParts.
local function getEntranceCameraPart(cameraParts)
	local cameraPart = cameraParts and cameraParts:FindFirstChild("Entrance")

	if cameraPart and cameraPart:IsA("BasePart") then
		return cameraPart
	end

	return nil
end

-- Finds the local player's slot-specific tracker if one exists. Parameters: cameraParts is the arena camera folder, playerOne/playerTwo identify fighter slots.
local function getSlotCameraTrackerPart(cameraParts, playerOne, playerTwo)
	local trackers = cameraParts and cameraParts:FindFirstChild("Trackers")
	if not trackers then
		return nil
	end

	local trackerName
	if localPlayer == playerOne then
		trackerName = PLAYER_ONE_TRACKER_NAME
	elseif localPlayer == playerTwo then
		trackerName = PLAYER_TWO_TRACKER_NAME
	end

	local slotTracker = trackerName and trackers:FindFirstChild(trackerName)
	if slotTracker and slotTracker:IsA("BasePart") then
		return slotTracker
	end

	return nil
end

-- Finds the camera tracker for this client with shared fallbacks. Parameters: cameraParts is Workspace.Arenas/<arenaId>/CameraParts, and playerOne/playerTwo identify fighter slots.
local function getCameraTrackerPart(cameraParts, playerOne, playerTwo)
	local slotTracker = getSlotCameraTrackerPart(cameraParts, playerOne, playerTwo)
	if slotTracker then
		return slotTracker
	end

	local directTracker = cameraParts and cameraParts:FindFirstChild(PRIMARY_TRACKER_NAME)
	if directTracker and directTracker:IsA("BasePart") then
		return directTracker
	end

	local trackers = cameraParts and cameraParts:FindFirstChild("Trackers")
	if not trackers then
		return nil
	end

	local namedTracker = trackers:FindFirstChild(PRIMARY_TRACKER_NAME) or trackers:FindFirstChild(LEGACY_TRACKER_NAME)
	if namedTracker and namedTracker:IsA("BasePart") then
		return namedTracker
	end

	for _, tracker in ipairs(trackers:GetChildren()) do
		if tracker:IsA("BasePart") then
			return tracker
		end
	end

	return nil
end

-- Stops the active round camera render loop. Parameters: none.
local function stopRoundCameraTracking()
	if RunSchedulerService then
		RunSchedulerService.Unbind(ROUND_CAMERA_LOOP_ID)
	end
end

-- Stops the scriptable fight camera and restores Roblox's default camera mode. Parameters: reason (string?) describes why it stopped.
function CameraService.Disable(reason)
	debugLog(
		"Disable requested; reason="
			.. tostring(reason or "unspecified")
			.. ", activeCameraPart="
			.. formatInstancePath(activeCameraPart)
	)

	stopRoundCameraTracking()
	activeCameraPart = nil

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

-- Applies the entrance camera through the client-local tracker. Parameters: entranceCameraPart (BasePart), cameraTrackerPart (BasePart), playerOneRoot (BasePart), and playerTwoRoot (BasePart) define the static shot.
local function applyEntranceCamera(entranceCameraPart, cameraTrackerPart, playerOneRoot, playerTwoRoot)
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		warnOnce("MissingCurrentCamera", "CurrentCamera is nil; entrance camera was not enabled")
		return false
	end

	local currentCFrame = entranceCameraPart.CFrame
	local currentRotation = currentCFrame - currentCFrame.Position
	local averageRootY = (playerOneRoot.Position.Y + playerTwoRoot.Position.Y) / 2
	local newPosition = Vector3.new(
		currentCFrame.Position.X,
		averageRootY,
		currentCFrame.Position.Z
	)

	cameraTrackerPart.CFrame = CFrame.new(newPosition) * currentRotation
	currentCamera.CameraType = Enum.CameraType.Scriptable
	currentCamera.CFrame = cameraTrackerPart.CFrame

	debugLog(
		"Entrance camera applied; playerOneRoot="
			.. formatVector3(playerOneRoot.Position)
			.. ", playerTwoRoot="
			.. formatVector3(playerTwoRoot.Position)
			.. ", cameraPartBefore="
			.. formatVector3(currentCFrame.Position)
			.. ", trackerAfter="
			.. formatVector3(cameraTrackerPart.Position)
			.. ", currentCamera="
			.. formatVector3(currentCamera.CFrame.Position)
	)

	return true
end

-- Gets the midpoint between two fighter roots. Parameters: playerOneRoot and playerTwoRoot (BasePart) define the tracked fighter positions.
local function getFighterMidpoint(playerOneRoot, playerTwoRoot)
	return (playerOneRoot.Position + playerTwoRoot.Position) / 2
end

-- Builds the round camera CFrame by preserving the configured tracker offset from the fighters. Parameters: initialCameraCFrame (CFrame), initialMidpoint (Vector3), playerOneRoot/playerTwoRoot (BasePart) define the tracked shot.
local function getRoundCameraCFrame(initialCameraCFrame, initialMidpoint, playerOneRoot, playerTwoRoot)
	local currentMidpoint = getFighterMidpoint(playerOneRoot, playerTwoRoot)
	local cameraOffset = initialCameraCFrame.Position - initialMidpoint
	local cameraRotation = initialCameraCFrame - initialCameraCFrame.Position

	return CFrame.new(currentMidpoint + cameraOffset) * cameraRotation
end

-- Enables the dynamic round camera for an arena. Parameters: arenaId identifies the arena, playerOne and playerTwo are the fighters to track.
function CameraService.EnableRound(arenaId, playerOne, playerTwo)
	debugSessionId = debugSessionId + 1

	debugLog(
		"EnableRound start; session="
			.. tostring(debugSessionId)
			.. ", arenaId="
			.. tostring(arenaId)
			.. ", playerOne="
			.. formatInstancePath(playerOne)
			.. ", playerTwo="
			.. formatInstancePath(playerTwo)
	)

	local cameraParts = getCameraPartsFolder(arenaId)
	local cameraTrackerPart = getCameraTrackerPart(cameraParts, playerOne, playerTwo)
	if not cameraTrackerPart then
		warnOnce(
			"MissingCameraTrackerPart:" .. tostring(arenaId),
			"Arena " .. tostring(arenaId) .. " camera tracker part was not found"
		)
		CameraService.Disable("MissingCameraTrackerPart")
		return false
	end

	local playerOneRoot, playerTwoRoot = waitForFighterRoots(playerOne, playerTwo, CHARACTER_ROOT_WAIT_SECONDS)
	if not playerOneRoot or not playerTwoRoot then
		warnOnce(
			"MissingRoundCharacterRoot",
			"One or both fighters are missing HumanoidRootPart after "
				.. tostring(CHARACTER_ROOT_WAIT_SECONDS)
				.. " seconds; round camera was not enabled"
		)
		CameraService.Disable("MissingRoundCharacterRoot")
		return false
	end

	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		warnOnce("MissingCurrentCamera", "CurrentCamera is nil; round camera was not enabled")
		return false
	end

	if not RunSchedulerService then
		warnOnce("MissingRunSchedulerService", "RunSchedulerService is nil; round camera was not enabled")
		return false
	end

	stopRoundCameraTracking()
	activeCameraPart = cameraTrackerPart
	currentCamera.CameraType = Enum.CameraType.Scriptable

	local initialCameraCFrame = cameraTrackerPart.CFrame
	local initialMidpoint = getFighterMidpoint(playerOneRoot, playerTwoRoot)

	RunSchedulerService.BindRenderStep(ROUND_CAMERA_LOOP_ID, Enum.RenderPriority.Camera.Value, function(deltaTime)
		local currentPlayerOneRoot = getCharacterRoot(playerOne)
		local currentPlayerTwoRoot = getCharacterRoot(playerTwo)
		if not currentPlayerOneRoot or not currentPlayerTwoRoot then
			CameraService.Disable("MissingFighterRootDuringRound")
			return
		end

		local targetCFrame = getRoundCameraCFrame(
			initialCameraCFrame,
			initialMidpoint,
			currentPlayerOneRoot,
			currentPlayerTwoRoot
		)
		local alpha = math.clamp(deltaTime * ROUND_CAMERA_TRACKING_SPEED, 0, 1)
		cameraTrackerPart.CFrame = cameraTrackerPart.CFrame:Lerp(targetCFrame, alpha)
		currentCamera.CameraType = Enum.CameraType.Scriptable
		currentCamera.CFrame = cameraTrackerPart.CFrame
	end)

	debugLog(
		"EnableRound complete; session="
			.. tostring(debugSessionId)
			.. ", cameraTrackerPart="
			.. formatInstancePath(cameraTrackerPart)
			.. ", initialMidpoint="
			.. formatVector3(initialMidpoint)
	)

	return true
end

-- Enables the static entrance fight camera for an arena. Parameters: arenaId identifies the arena, playerOne and playerTwo are the fighters to frame.
function CameraService.EnableEntrance(arenaId, playerOne, playerTwo)
	debugSessionId = debugSessionId + 1
	stopRoundCameraTracking()

	debugLog(
		"EnableEntrance start; session="
			.. tostring(debugSessionId)
			.. ", arenaId="
			.. tostring(arenaId)
			.. ", playerOne="
			.. formatInstancePath(playerOne)
			.. ", playerTwo="
			.. formatInstancePath(playerTwo)
	)

	local cameraParts = getCameraPartsFolder(arenaId)
	local cameraPart = getEntranceCameraPart(cameraParts)
	if not cameraPart then
		warnOnce(
			"MissingEntranceCameraPart:" .. tostring(arenaId),
			"Arena " .. tostring(arenaId) .. " entrance camera part was not found"
		)
		CameraService.Disable("MissingCameraPart")
		return false
	end

	local cameraTrackerPart = getCameraTrackerPart(cameraParts, playerOne, playerTwo)
	if not cameraTrackerPart then
		warnOnce(
			"MissingCameraTrackerPart:" .. tostring(arenaId),
			"Arena " .. tostring(arenaId) .. " camera tracker part was not found"
		)
		CameraService.Disable("MissingCameraTrackerPart")
		return false
	end

	local playerOneRoot, playerTwoRoot = waitForFighterRoots(playerOne, playerTwo, CHARACTER_ROOT_WAIT_SECONDS)
	if not playerOneRoot or not playerTwoRoot then
		warnOnce(
			"MissingCharacterRoot",
			"One or both fighters are missing HumanoidRootPart after "
				.. tostring(CHARACTER_ROOT_WAIT_SECONDS)
				.. " seconds; fight camera was not enabled"
		)
		CameraService.Disable("MissingCharacterRoot")
		return false
	end

	activeCameraPart = cameraTrackerPart
	debugLog(
		"Resolved targets; cameraPart="
			.. formatInstancePath(cameraPart)
			.. ", cameraPartPosition="
			.. formatVector3(cameraPart.Position)
			.. ", cameraTrackerPart="
			.. formatInstancePath(cameraTrackerPart)
			.. ", cameraTrackerPartPosition="
			.. formatVector3(cameraTrackerPart.Position)
			.. ", playerOneRoot="
			.. formatInstancePath(playerOneRoot)
			.. ", playerTwoRoot="
			.. formatInstancePath(playerTwoRoot)
	)

	if not applyEntranceCamera(cameraPart, cameraTrackerPart, playerOneRoot, playerTwoRoot) then
		CameraService.Disable("ApplyEntranceCameraFailed")
		return false
	end

	debugLog("EnableEntrance complete; session=" .. tostring(debugSessionId))

	return true
end

-- Captures replicated networking dependencies. Parameters: none.
function CameraService.Init()
	RunSchedulerService = _G.RunSchedulerService
	setFightCameraRemote = ReplicatedStorage
		:WaitForChild("Networking")
		:WaitForChild("SetFightCamera")
	debugLog("Init; SetFightCamera remote=" .. formatInstancePath(setFightCameraRemote))
end

-- Listens for server fight camera assignment requests. Parameters: none.
function CameraService.Start()
	debugLog("Start; connecting SetFightCamera remote listener")

	-- Applies a server camera assignment. Parameters: enabled (boolean), arenaId, playerOne, playerTwo, and mode describe the camera state.
	setFightCameraRemote.OnClientEvent:Connect(function(enabled, arenaId, playerOne, playerTwo, mode)
		local cameraMode = mode or CAMERA_MODE.Entrance
		debugLog(
			"SetFightCamera received; enabled="
				.. tostring(enabled)
				.. ", arenaId="
				.. tostring(arenaId)
				.. ", playerOne="
				.. formatInstancePath(playerOne)
				.. ", playerTwo="
				.. formatInstancePath(playerTwo)
				.. ", mode="
				.. tostring(cameraMode)
		)

		if not enabled then
			CameraService.Disable("RemoteDisabled")
		elseif cameraMode == CAMERA_MODE.Round then
			CameraService.EnableRound(arenaId, playerOne, playerTwo)
		else
			CameraService.EnableEntrance(arenaId, playerOne, playerTwo)
		end
	end)
end

return CameraService
