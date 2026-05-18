local FreefallController = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local GroundedPhysicsConfig
local humanoid
local rootPart
local lastAirDashTime = -math.huge
local lastTapTimes = {}

local DASH_KEYS = {
	[Enum.KeyCode.W] = "Forward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.S] = "Backward",
	[Enum.KeyCode.D] = "Right",
}

local function flatten(vector)
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	if flattened.Magnitude == 0 then
		return Vector3.zero
	end
	return flattened.Unit
end

local function isAirborne()
	return humanoid and humanoid.FloorMaterial == Enum.Material.Air
end

local function isFreeFalling()
	return isAirborne() and rootPart and rootPart.AssemblyLinearVelocity.Y <= 0
end

local function getDashDirection(keyCode)
	if not rootPart then
		return Vector3.zero
	end

	local forward = flatten(rootPart.CFrame.LookVector)
	local right = flatten(rootPart.CFrame.RightVector)

	if keyCode == Enum.KeyCode.W then
		return forward
	elseif keyCode == Enum.KeyCode.S then
		return -forward
	elseif keyCode == Enum.KeyCode.A then
		return -right
	elseif keyCode == Enum.KeyCode.D then
		return right
	end

	return Vector3.zero
end

local function tryAirDash(keyCode)
	if not isFreeFalling() or not rootPart then
		return
	end

	local now = os.clock()
	if now - lastAirDashTime < GroundedPhysicsConfig.AirDashDebounce then
		return
	end

	local dashDirection = getDashDirection(keyCode)
	if dashDirection == Vector3.zero then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		dashDirection.X * GroundedPhysicsConfig.AirDashSpeed,
		velocity.Y,
		dashDirection.Z * GroundedPhysicsConfig.AirDashSpeed
	)
	lastAirDashTime = now
end

local function onInputBegan(input, gameProcessed)
	if gameProcessed or not DASH_KEYS[input.KeyCode] then
		return
	end

	local now = os.clock()
	local lastTapTime = lastTapTimes[input.KeyCode]
	lastTapTimes[input.KeyCode] = now

	if lastTapTime and now - lastTapTime <= GroundedPhysicsConfig.DoubleTapWindow then
		tryAirDash(input.KeyCode)
		lastTapTimes[input.KeyCode] = nil
	end
end

local function bindCharacter(character)
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	lastAirDashTime = -math.huge
	table.clear(lastTapTimes)
end

local function updateFreefall(deltaTime)
	if not humanoid or not rootPart then
		return
	end

	if not isAirborne() then
		lastAirDashTime = -math.huge
		table.clear(lastTapTimes)
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local verticalVelocity = velocity.Y

	if verticalVelocity < 0 then
		local descentCompensation = math.max(Workspace.Gravity - GroundedPhysicsConfig.FreefallAcceleration, 0)
		verticalVelocity = math.min(verticalVelocity + descentCompensation * deltaTime, 0)
		verticalVelocity = math.max(verticalVelocity, -GroundedPhysicsConfig.TerminalFallSpeed)
	end

	local moveDirection = flatten(humanoid.MoveDirection)
	if moveDirection ~= Vector3.zero then
		local targetSpeed = math.max(horizontalVelocity.Magnitude, GroundedPhysicsConfig.AirControlMaxSpeed)
		local targetHorizontalVelocity = moveDirection * targetSpeed
		local alpha = math.clamp(GroundedPhysicsConfig.AirControlResponsiveness * deltaTime, 0, 1)
		horizontalVelocity = horizontalVelocity:Lerp(targetHorizontalVelocity, alpha)
	end

	rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, verticalVelocity, horizontalVelocity.Z)
end

function FreefallController.Init()
	GroundedPhysicsConfig = _G.GroundedPhysicsConfig
end

function FreefallController.Start()
	UserInputService.InputBegan:Connect(onInputBegan)
	RunService.Heartbeat:Connect(updateFreefall)
	LocalPlayer.CharacterAdded:Connect(bindCharacter)

	if LocalPlayer.Character then
		bindCharacter(LocalPlayer.Character)
	end
end

return FreefallController
