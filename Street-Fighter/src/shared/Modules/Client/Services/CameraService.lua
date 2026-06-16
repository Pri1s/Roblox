-- Owns local camera mode switching. Other client modules request named camera
-- systems here instead of touching Workspace.CurrentCamera directly.
--
-- Public API:
-- CameraService.TransitionTo(systemName, context?)

local CameraService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SYSTEM_DEFAULT = "Default"
local SYSTEM_COMBAT = "Combat"
local MATCH_CAMERA_STATE_REMOTE_NAME = "GetMatchCameraState"
local DEBUG_PREFIX = "[CameraDebug]"

local COMBAT_CONTEXT_RETRY_DELAY = 0.1
local MAX_COMBAT_CONTEXT_ATTEMPTS = 20

local RunServiceHandler
local GameConfigs
local CameraConfig

local _combatContext = nil
local _renderStepId = nil
local _cameraModeToken = 0

-- Prints a standard local camera debug message.
-- message: string to send to Studio Output
local function debugPrint(message)
	print(DEBUG_PREFIX .. " " .. Players.LocalPlayer.Name .. ": " .. message)
end

-- Clamps value between minValue and maxValue.
-- value: number to clamp
-- minValue: lowest allowed value
-- maxValue: highest allowed value
local function clamp(value, minValue, maxValue)
	return math.max(minValue, math.min(maxValue, value))
end

-- Returns the current camera instance, if Roblox has created one.
local function getCurrentCamera()
	return Workspace.CurrentCamera
end

-- Returns the local player's current Humanoid, if the character has one.
local function getLocalHumanoid()
	local character = Players.LocalPlayer.Character
	if not character then return nil end

	return character:FindFirstChildOfClass("Humanoid")
end

-- Returns the HumanoidRootPart for player, if the character currently has one.
-- player: Player whose character root should be read
local function getRootPart(player)
	local character = player and player.Character
	if not character then return nil end

	return character:FindFirstChild("HumanoidRootPart")
end

-- Chooses the horizontal camera side from a fight axis, preferring world +Z.
-- fightAxis: horizontal unit Vector3 from spawn 1 toward spawn 2
local function chooseCameraSide(fightAxis)
	local sideA = Vector3.new(-fightAxis.Z, 0, fightAxis.X)
	local sideB = -sideA
	local worldForward = Vector3.new(0, 0, 1)

	if sideB:Dot(worldForward) > sideA:Dot(worldForward) then
		return sideB
	end

	return sideA
end

-- Builds combat camera constants from the arena's spawn parts.
-- context: table containing player1, player2, and arena
local function buildCombatContext(context)
	if not context or not context.player1 or not context.player2 or not context.arena then
		return nil
	end

	local spawns = context.arena:FindFirstChild("Spawns")
	if not spawns then return nil end

	local spawn1 = spawns:FindFirstChild("1")
	local spawn2 = spawns:FindFirstChild("2")
	if not spawn1 or not spawn2 or not spawn1:IsA("BasePart") or not spawn2:IsA("BasePart") then
		return nil
	end

	local spawnDelta = spawn2.Position - spawn1.Position
	local horizontalDelta = Vector3.new(spawnDelta.X, 0, spawnDelta.Z)
	local fightAxis = Vector3.new(1, 0, 0)
	if horizontalDelta.Magnitude > 0 then
		fightAxis = horizontalDelta.Unit
	end

	local averageSpawnY = (spawn1.Position.Y + spawn2.Position.Y) / 2

	return {
		player1 = context.player1,
		player2 = context.player2,
		fightAxis = fightAxis,
		cameraSide = chooseCameraSide(fightAxis),
		targetBaseY = averageSpawnY + CameraConfig.TargetHeightOffset,
		cameraY = averageSpawnY + CameraConfig.CameraHeightOffset,
	}
end

-- Calculates the desired combat camera CFrame for the current fighter positions.
-- combatContext: prepared context returned by buildCombatContext
local function getCombatCameraCFrame(combatContext)
	local root1 = getRootPart(combatContext.player1)
	local root2 = getRootPart(combatContext.player2)
	if not root1 or not root2 then return nil end

	local midpoint = (root1.Position + root2.Position) / 2
	local separation = math.abs((root2.Position - root1.Position):Dot(combatContext.fightAxis))
	local distance = clamp(
		CameraConfig.MinCameraDistance + separation * CameraConfig.DistancePerStud,
		CameraConfig.MinCameraDistance,
		CameraConfig.MaxCameraDistance
	)
	local targetY = clamp(
		midpoint.Y,
		combatContext.targetBaseY - CameraConfig.TargetVerticalClamp,
		combatContext.targetBaseY + CameraConfig.TargetVerticalClamp
	)
	local target = Vector3.new(midpoint.X, targetY, midpoint.Z)
	local cameraPosition = Vector3.new(target.X, combatContext.cameraY, target.Z) + combatContext.cameraSide * distance

	return CFrame.lookAt(cameraPosition, target)
end

-- Applies one combat camera update, snapping or smoothing toward the target.
-- deltaTime: seconds since the previous RenderStepped update
-- shouldSnap: true to set the exact target CFrame immediately
local function updateCombatCamera(deltaTime, shouldSnap)
	if not _combatContext then return end

	local camera = getCurrentCamera()
	if not camera then return end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local targetCFrame = getCombatCameraCFrame(_combatContext)
	if not targetCFrame then return end

	if shouldSnap then
		camera.CFrame = targetCFrame
		return
	end

	local alpha = 1 - math.exp(-CameraConfig.TrackingResponse * deltaTime)
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, alpha)
end

-- Advances the active combat camera after each rendered frame.
-- deltaTime: seconds since the previous RenderStepped update
local function onRenderStepped(deltaTime)
	updateCombatCamera(deltaTime, false)
end

-- Removes the active RenderStepped camera callback, if one is registered.
local function unregisterCombatStep()
	if not _renderStepId then return end

	RunServiceHandler.Unregister(_renderStepId)
	_renderStepId = nil
end

-- Restores Roblox's default local player camera behavior.
local function transitionToDefault()
	_cameraModeToken += 1
	unregisterCombatStep()
	_combatContext = nil

	local camera = getCurrentCamera()
	if not camera then
		debugPrint("Default camera transition deferred because CurrentCamera is nil.")
		return
	end

	camera.CameraType = Enum.CameraType.Custom

	local humanoid = getLocalHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end

	debugPrint("Transitioned to default camera.")
end

-- Activates the combat camera using the provided match context.
-- context: table containing player1, player2, and arena
-- attempt: optional retry count while replicated arena children arrive
-- token: optional camera mode token used to cancel stale retries
local function transitionToCombat(context, attempt, token)
	attempt = attempt or 1
	if not token then
		_cameraModeToken += 1
		token = _cameraModeToken
	elseif token ~= _cameraModeToken then
		return
	end

	local combatContext = buildCombatContext(context)
	if not combatContext then
		if attempt < MAX_COMBAT_CONTEXT_ATTEMPTS then
			debugPrint("Combat camera context incomplete; retrying attempt " .. tostring(attempt + 1) .. ".")
			-- Retries combat activation after replicated arena children have more time to arrive.
			-- No parameters are passed by task.delay beyond the closed-over context, attempt, and token.
			task.delay(COMBAT_CONTEXT_RETRY_DELAY, function()
				transitionToCombat(context, attempt + 1, token)
			end)
			return
		end

		warn("[CameraService] Combat camera activation ignored because match context is incomplete after retries.")
		return
	end

	unregisterCombatStep()
	_combatContext = combatContext

	local camera = getCurrentCamera()
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	else
		debugPrint("Combat camera transition continued without CurrentCamera; RenderStepped will retry CFrame updates.")
	end

	updateCombatCamera(0, true)

	_renderStepId = RunServiceHandler.Register("RenderStepped", onRenderStepped)
	debugPrint("Transitioned to combat camera. Player1=" .. tostring(context.player1) .. ", Player2=" .. tostring(context.player2) .. ", Arena=" .. tostring(context.arena))
end

-- Handles match camera remote payloads from the server.
-- payload: table with isActive, player1, player2, and arena fields
local function onMatchCameraStateChanged(payload)
	debugPrint("Received match camera event: isActive=" .. tostring(payload and payload.isActive))
	if payload and payload.isActive then
		CameraService.TransitionTo(SYSTEM_COMBAT, payload)
	else
		CameraService.TransitionTo(SYSTEM_DEFAULT)
	end
end

-- Requests the current camera state in case the server event fired before this client connected.
-- getMatchCameraState: RemoteFunction that returns the current match camera payload
local function syncCurrentMatchCameraState(getMatchCameraState)
	-- Invokes the server safely to fetch the latest camera payload.
	-- No parameters are passed to the protected callback.
	local didInvoke, payload = pcall(function()
		return getMatchCameraState:InvokeServer()
	end)

	if not didInvoke then
		warn("[CameraService] Failed to sync match camera state: " .. tostring(payload))
		return
	end

	debugPrint("Synced match camera state: isActive=" .. tostring(payload and payload.isActive))
	onMatchCameraStateChanged(payload)
end

-- Transitions to a named camera system.
-- systemName: "Default" or "Combat"
-- context: optional table required by the Combat system
function CameraService.TransitionTo(systemName, context)
	if systemName == SYSTEM_DEFAULT then
		transitionToDefault()
	elseif systemName == SYSTEM_COMBAT then
		transitionToCombat(context)
	else
		warn("[CameraService] Unknown camera system: " .. tostring(systemName))
	end
end

-- Captures client service dependencies from _G after all modules are required.
function CameraService.Init()
	RunServiceHandler = _G.RunServiceHandler
	GameConfigs = _G.GameConfigs
	CameraConfig = GameConfigs.Camera
end

-- Listens for server-authoritative match camera state changes.
function CameraService.Start()
	local networking = ReplicatedStorage:WaitForChild("Networking")
	local matchCameraStateChanged = networking:WaitForChild("MatchCameraStateChanged")
	local getMatchCameraState = networking:WaitForChild(MATCH_CAMERA_STATE_REMOTE_NAME)

	matchCameraStateChanged.OnClientEvent:Connect(onMatchCameraStateChanged)
	debugPrint("Connected match camera listener; syncing current state.")
	syncCurrentMatchCameraState(getMatchCameraState)
end

return CameraService
