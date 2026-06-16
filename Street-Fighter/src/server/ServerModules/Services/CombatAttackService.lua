-- Receives client attack requests and starts server-owned debug hitboxes.
-- V1 is intentionally debug-only: it validates mapped attacks, starts an
-- immediate active window, and prints OnHit payloads without applying combat effects.

local CombatAttackService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkUtil = require(ReplicatedStorage.Modules.Utility.NetworkUtil)

local REMOTE_NAME = "CombatAttackRequested"
local DEBUG_PREFIX = "[CombatAttackDebug]"

local HitboxService
local combatAttackRequested

local AttackData = {
	BackPunch = {
		hitPoints = {
			{ name = "RightArmHitPoint", limbName = "Right Arm", cFrame = CFrame.new(0, -0.85, 0) },
		},
		activeDuration = 0.20,
		castSize = Vector3.new(1, 1, 1),
		debugVisualize = true,
	},
	FrontKick = {
		hitPoints = {
			{ name = "RightLegHitPoint", limbName = "Right Leg", cFrame = CFrame.new(0, -0.85, 0) },
		},
		activeDuration = 0.20,
		castSize = Vector3.new(1, 1, 1),
		debugVisualize = true,
	},
	BackKick = {
		hitPoints = {
			{ name = "RightLegHitPoint", limbName = "Right Leg", cFrame = CFrame.new(0, -0.85, 0) },
		},
		activeDuration = 0.20,
		castSize = Vector3.new(1, 1, 1),
		debugVisualize = true,
	},
}

-- Prints a standard combat attack debug message.
-- message: string to send to Studio Output
local function debugPrint(message)
	print(DEBUG_PREFIX .. " " .. message)
end

-- Returns the player's live character and root part when an attack can be tested.
-- player: Player that requested an attack
local function getLiveCharacter(player)
	local character = player.Character
	if not character then
		debugPrint("Rejected attack request from " .. player.Name .. ": no character.")
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		debugPrint("Rejected attack request from " .. player.Name .. ": no living Humanoid.")
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		debugPrint("Rejected attack request from " .. player.Name .. ": no HumanoidRootPart.")
		return nil, nil
	end

	return character, rootPart
end

-- Builds a deterministic hitbox id for the player's requested attack.
-- player: Player that requested an attack
-- attackState: mapped attack state string
local function getHitboxId(player, attackState)
	return tostring(player.UserId) .. ":" .. attackState
end

-- Returns the unique hit point Attachment names declared for an attack.
-- attackData: mapped server attack metadata with hitPoints entries
local function getPointNames(attackData)
	local pointNames = {}

	for _, hitPoint in ipairs(attackData.hitPoints or {}) do
		table.insert(pointNames, hitPoint.name)
	end

	return pointNames
end

-- Ensures an R6 character owns the server-authored hit point Attachments for an attack.
-- character: player character model; attackData: mapped server attack metadata with limb hitPoints
local function ensureAttackHitPoints(character, attackData)
	for _, hitPoint in ipairs(attackData.hitPoints or {}) do
		local limb = character:FindFirstChild(hitPoint.limbName)
		if not limb or not limb:IsA("BasePart") then
			warn(
				"[CombatAttackService] Missing R6 limb '"
					.. tostring(hitPoint.limbName)
					.. "' for hit point '"
					.. tostring(hitPoint.name)
					.. "'."
			)
			continue
		end

		local attachment = limb:FindFirstChild(hitPoint.name)
		if attachment and not attachment:IsA("Attachment") then
			warn(
				"[CombatAttackService] Existing hit point '"
					.. attachment:GetFullName()
					.. "' must be an Attachment."
			)
			continue
		end

		if not attachment then
			attachment = Instance.new("Attachment")
			attachment.Name = hitPoint.name
			attachment.Parent = limb
			debugPrint("Created R6 hit point " .. attachment:GetFullName() .. ".")
		else
			debugPrint("Reusing R6 hit point " .. attachment:GetFullName() .. ".")
		end

		attachment.CFrame = hitPoint.cFrame
	end
end

-- Starts a debug hitbox for a validated mapped attack request.
-- player: Player that requested the attack
-- attackState: mapped attack state string sent by the client
local function startDebugAttack(player, attackState)
	local attackData = AttackData[attackState]
	if not attackData then
		debugPrint("Rejected unmapped attack '" .. tostring(attackState) .. "' from " .. player.Name .. ".")
		return
	end

	local character = getLiveCharacter(player)
	if not character then return end

	local hitboxId = getHitboxId(player, attackState)
	ensureAttackHitPoints(character, attackData)

	local pointNames = getPointNames(attackData)
	debugPrint(
		"Accepted "
			.. attackState
			.. " from "
			.. player.Name
			.. "; starting hitbox "
			.. hitboxId
			.. " with points=["
			.. table.concat(pointNames, ", ")
			.. "]."
	)

	HitboxService.CreateHitbox(hitboxId, character, pointNames, {
		castSize = attackData.castSize,
		debugVisualize = attackData.debugVisualize,
	})

	HitboxService.StartHitbox(hitboxId, attackData.activeDuration, function(hit)
		debugPrint(
			player.Name
				.. " "
				.. attackState
				.. " hit "
				.. hit.hitInstance:GetFullName()
				.. " from "
				.. tostring(hit.hitPointName)
				.. " at "
				.. tostring(hit.hitPosition)
		)
	end)
end

-- Handles client attack requests and ignores unmapped or invalid requests.
-- player: Player who fired CombatAttackRequested
-- attackState: string attack state requested by the client
local function onCombatAttackRequested(player, attackState)
	debugPrint("Received attack request from " .. player.Name .. ": " .. tostring(attackState) .. ".")

	if typeof(attackState) ~= "string" then
		debugPrint("Rejected attack request from " .. player.Name .. ": attackState was not a string.")
		return
	end

	startDebugAttack(player, attackState)
end

-- Captures service dependencies and creates the combat attack request remote.
function CombatAttackService.Init()
	HitboxService = _G.HitboxService
	combatAttackRequested = NetworkUtil.create("RemoteEvent", REMOTE_NAME, ReplicatedStorage.Networking)
	debugPrint("Created remote " .. REMOTE_NAME .. ".")
end

-- Connects the combat attack request remote for server-owned hitbox activation.
function CombatAttackService.Start()
	combatAttackRequested.OnServerEvent:Connect(onCombatAttackRequested)
	debugPrint("Listening for " .. REMOTE_NAME .. " requests.")
end

return CombatAttackService
