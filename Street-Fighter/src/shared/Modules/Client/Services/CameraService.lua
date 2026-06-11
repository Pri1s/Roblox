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

local MIN_CAMERA_DISTANCE = 18
local MAX_CAMERA_DISTANCE = 42
local DISTANCE_PER_STUD = 0.65
local CAMERA_HEIGHT_OFFSET = 7
local TARGET_HEIGHT_OFFSET = 3
local TARGET_VERTICAL_CLAMP = 4
local TRACKING_RESPONSE = 12

local RunServiceHandler

local _combatContext = nil
local _renderStepId = nil

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
		targetBaseY = averageSpawnY + TARGET_HEIGHT_OFFSET,
		cameraY = averageSpawnY + CAMERA_HEIGHT_OFFSET,
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
		MIN_CAMERA_DISTANCE + separation * DISTANCE_PER_STUD,
		MIN_CAMERA_DISTANCE,
		MAX_CAMERA_DISTANCE
	)
	local targetY = clamp(
		midpoint.Y,
		combatContext.targetBaseY - TARGET_VERTICAL_CLAMP,
		combatContext.targetBaseY + TARGET_VERTICAL_CLAMP
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

	local targetCFrame = getCombatCameraCFrame(_combatContext)
	if not targetCFrame then return end

	if shouldSnap then
		camera.CFrame = targetCFrame
		return
	end

	local alpha = 1 - math.exp(-TRACKING_RESPONSE * deltaTime)
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
	unregisterCombatStep()
	_combatContext = nil

	local camera = getCurrentCamera()
	if not camera then return end

	camera.CameraType = Enum.CameraType.Custom

	local humanoid = getLocalHumanoid()
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Activates the combat camera using the provided match context.
-- context: table containing player1, player2, and arena
local function transitionToCombat(context)
	local combatContext = buildCombatContext(context)
	if not combatContext then
		warn("[CameraService] Combat camera activation ignored because match context is incomplete.")
		return
	end

	unregisterCombatStep()
	_combatContext = combatContext

	local camera = getCurrentCamera()
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	updateCombatCamera(0, true)

	_renderStepId = RunServiceHandler.Register("RenderStepped", onRenderStepped)
end

-- Handles match camera remote payloads from the server.
-- payload: table with isActive, player1, player2, and arena fields
local function onMatchCameraStateChanged(payload)
	if payload and payload.isActive then
		CameraService.TransitionTo(SYSTEM_COMBAT, payload)
	else
		CameraService.TransitionTo(SYSTEM_DEFAULT)
	end
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
end

-- Listens for server-authoritative match camera state changes.
function CameraService.Start()
	local networking = ReplicatedStorage:WaitForChild("Networking")
	local matchCameraStateChanged = networking:WaitForChild("MatchCameraStateChanged")

	matchCameraStateChanged.OnClientEvent:Connect(onMatchCameraStateChanged)
end

return CameraService
