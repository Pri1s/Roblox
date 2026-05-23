local CameraService = {}

-- Public API
-- CameraService.EnableEntrance(arenaId, playerOne, playerTwo) -> boolean
-- CameraService.Disable(reason) -> nil

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local setFightCameraRemote
local activeCameraPart
local warnedMessages = {}
local debugSessionId = 0

local DEBUG_PREFIX = "[CameraService][FightCamera] "
local CHARACTER_ROOT_WAIT_SECONDS = 2

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

-- Finds the configured entrance camera part for an arena. Parameters: arenaId identifies Workspace.Arenas/<arenaId>/CameraParts/Entrance.
local function getEntranceCameraPart(arenaId)
	local arenas = Workspace:FindFirstChild("Arenas")
	local arena = arenas and arenas:FindFirstChild(tostring(arenaId))
	local cameraParts = arena and arena:FindFirstChild("CameraParts")
	local cameraPart = cameraParts and cameraParts:FindFirstChild("Entrance")

	if cameraPart and cameraPart:IsA("BasePart") then
		return cameraPart
	end

	return nil
end

-- Stops the scriptable fight camera and restores Roblox's default camera mode. Parameters: reason (string?) describes why it stopped.
function CameraService.Disable(reason)
	debugLog(
		"Disable requested; reason="
			.. tostring(reason or "unspecified")
			.. ", activeCameraPart="
			.. formatInstancePath(activeCameraPart)
	)

	activeCameraPart = nil

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

-- Applies the entrance camera part to CurrentCamera. Parameters: cameraPart (BasePart), playerOneRoot (BasePart), and playerTwoRoot (BasePart) define the static shot.
local function applyEntranceCamera(cameraPart, playerOneRoot, playerTwoRoot)
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		warnOnce("MissingCurrentCamera", "CurrentCamera is nil; entrance camera was not enabled")
		return false
	end

	local currentCFrame = cameraPart.CFrame
	local currentRotation = currentCFrame - currentCFrame.Position
	local averageRootY = (playerOneRoot.Position.Y + playerTwoRoot.Position.Y) / 2
	local newPosition = Vector3.new(
		currentCFrame.Position.X,
		averageRootY,
		currentCFrame.Position.Z
	)

	cameraPart.CFrame = CFrame.new(newPosition) * currentRotation
	currentCamera.CameraType = Enum.CameraType.Scriptable
	currentCamera.CFrame = cameraPart.CFrame

	debugLog(
		"Entrance camera applied; playerOneRoot="
			.. formatVector3(playerOneRoot.Position)
			.. ", playerTwoRoot="
			.. formatVector3(playerTwoRoot.Position)
			.. ", cameraPartBefore="
			.. formatVector3(currentCFrame.Position)
			.. ", cameraPartAfter="
			.. formatVector3(cameraPart.Position)
			.. ", currentCamera="
			.. formatVector3(currentCamera.CFrame.Position)
	)

	return true
end

-- Enables the static entrance fight camera for an arena. Parameters: arenaId identifies the arena, playerOne and playerTwo are the fighters to frame.
function CameraService.EnableEntrance(arenaId, playerOne, playerTwo)
	debugSessionId = debugSessionId + 1

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

	local cameraPart = getEntranceCameraPart(arenaId)
	if not cameraPart then
		warnOnce(
			"MissingEntranceCameraPart:" .. tostring(arenaId),
			"Arena " .. tostring(arenaId) .. " entrance camera part was not found"
		)
		CameraService.Disable("MissingCameraPart")
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

	activeCameraPart = cameraPart
	debugLog(
		"Resolved targets; cameraPart="
			.. formatInstancePath(cameraPart)
			.. ", cameraPartPosition="
			.. formatVector3(cameraPart.Position)
			.. ", playerOneRoot="
			.. formatInstancePath(playerOneRoot)
			.. ", playerTwoRoot="
			.. formatInstancePath(playerTwoRoot)
	)

	if not applyEntranceCamera(cameraPart, playerOneRoot, playerTwoRoot) then
		CameraService.Disable("ApplyEntranceCameraFailed")
		return false
	end

	debugLog("EnableEntrance complete; session=" .. tostring(debugSessionId))

	return true
end

-- Captures replicated networking dependencies. Parameters: none.
function CameraService.Init()
	setFightCameraRemote = ReplicatedStorage
		:WaitForChild("Networking")
		:WaitForChild("SetFightCamera")
	debugLog("Init; SetFightCamera remote=" .. formatInstancePath(setFightCameraRemote))
end

-- Listens for server fight camera assignment requests. Parameters: none.
function CameraService.Start()
	debugLog("Start; connecting SetFightCamera remote listener")

	-- Applies a server camera assignment. Parameters: enabled (boolean), arenaId, playerOne, and playerTwo describe the camera state.
	setFightCameraRemote.OnClientEvent:Connect(function(enabled, arenaId, playerOne, playerTwo)
		debugLog(
			"SetFightCamera received; enabled="
				.. tostring(enabled)
				.. ", arenaId="
				.. tostring(arenaId)
				.. ", playerOne="
				.. formatInstancePath(playerOne)
				.. ", playerTwo="
				.. formatInstancePath(playerTwo)
		)

		if enabled then
			CameraService.EnableEntrance(arenaId, playerOne, playerTwo)
		else
			CameraService.Disable("RemoteDisabled")
		end
	end)
end

return CameraService
