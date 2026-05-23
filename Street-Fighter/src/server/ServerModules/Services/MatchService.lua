local MatchService = {}

-- Public API
-- MatchService.RegisterArena(arenaId, arenaModel) -> boolean, status
-- MatchService.QueuePlayerForArenaSlot(player, arenaId, slotId, referencePart) -> boolean, status

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local setFightCameraRemote = ReplicatedStorage.Networking.SetFightCamera

local STATE = {
	Vacant = "Vacant",
	Fight = "Fight",
}

local arenaMetadataById = {}
local queuedSlotByPlayer = {}

local MATCH_SPAWN_OFFSET = Vector3.new(0, 3, 0)

MatchService.State = STATE

-- Converts an arena identifier into the metadata key. Parameters: arenaId is the identifier to normalize.
local function getArenaKey(arenaId)
	return tostring(arenaId)
end

-- Checks whether a player is still in the Players service. Parameters: player (Player?) is the player to validate.
local function isActivePlayer(player)
	return player ~= nil and player.Parent == Players
end

-- Moves a player's character above a reference part. Parameters: player (Player) is moved to referencePart (BasePart).
local function teleportPlayerToReference(player, referencePart)
	local character = player.Character
	if not character or not referencePart or not referencePart:IsA("BasePart") then
		return
	end

	character:PivotTo(referencePart.CFrame + Vector3.new(0, 3, 0))
end

-- Prevents a character from moving or jumping. Parameters: character (Model?) is the character model to update.
local function disableCharacterControls(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.Jump = false
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.WalkSpeed = 0
end

-- Prevents the player's current character from moving or jumping while queued. Parameters: player (Player) owns the character to update.
local function disableQueuedCharacterControls(player)
	disableCharacterControls(player.Character)
end

-- Builds a match spawn CFrame that faces another spawn when possible. Parameters: referencePart (BasePart) defines position, facingReferencePart (BasePart?) defines the look target.
local function getMatchSpawnCFrame(referencePart, facingReferencePart)
	local spawnPosition = referencePart.Position + MATCH_SPAWN_OFFSET

	if facingReferencePart and facingReferencePart:IsA("BasePart") then
		local targetPosition = Vector3.new(facingReferencePart.Position.X, spawnPosition.Y, facingReferencePart.Position.Z)
		if (targetPosition - spawnPosition).Magnitude > 0.001 then
			return CFrame.lookAt(spawnPosition, targetPosition)
		end
	end

	return referencePart.CFrame + MATCH_SPAWN_OFFSET
end

-- Replaces a player's character with the ReplicatedStorage.Default rig at a reference part. Parameters: player (Player) receives the rig, referencePart (BasePart) defines the spawn position, and facingReferencePart (BasePart?) defines who they face.
local function spawnMatchCharacter(player, referencePart, facingReferencePart)
	local defaultRig = ReplicatedStorage:FindFirstChild("Default")
	if not defaultRig or not defaultRig:IsA("Model") then
		warn("ReplicatedStorage.Default character rig was not found")
		return false
	end

	if not referencePart or not referencePart:IsA("BasePart") then
		return false
	end

	local previousCharacter = player.Character
	local matchCharacter = defaultRig:Clone()
	local humanoid = matchCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("ReplicatedStorage.Default character rig is missing a Humanoid")
		return false
	end

	matchCharacter.Name = player.Name
	matchCharacter:PivotTo(getMatchSpawnCFrame(referencePart, facingReferencePart))
	disableCharacterControls(matchCharacter)
	player.Character = matchCharacter
	matchCharacter.Parent = Workspace

	if previousCharacter and previousCharacter ~= matchCharacter then
		previousCharacter:Destroy()
	end

	return true
end

-- Removes a player from any queue slot they occupy and clears their active match if needed. Parameters: player (Player) is the player to clear.
local function clearQueuedSlot(player)
	local queuedSlot = queuedSlotByPlayer[player]
	if not queuedSlot then
		return
	end

	local arenaMetadata = arenaMetadataById[queuedSlot.ArenaId]
	if arenaMetadata and arenaMetadata.QueueSlots[queuedSlot.SlotId] == player then
		arenaMetadata.QueueSlots[queuedSlot.SlotId] = nil
	end

	if arenaMetadata and arenaMetadata.CurrentMatch and arenaMetadata.CurrentMatch.Fighters[queuedSlot.SlotId] == player then
		arenaMetadata.CurrentMatch = nil
		arenaMetadata.State = STATE.Vacant
	end

	queuedSlotByPlayer[player] = nil
end

-- Finds the fight spawn reference for an arena slot. Parameters: arenaMetadata stores the arena instance, slotId identifies the spawn slot.
local function getSpawnReference(arenaMetadata, slotId)
	local arena = arenaMetadata.Arena
	local map = arena and arena:FindFirstChild("Map")
	local spawns = map and map:FindFirstChild("Spawns")
	local slot = spawns and spawns:FindFirstChild(tostring(slotId))
	local reference = slot and slot:FindFirstChild("Reference")

	if reference and reference:IsA("BasePart") then
		return reference
	end

	return nil
end

-- Starts a fight when both queue slots are filled and no fight is active. Parameters: arenaMetadata is the arena state to inspect and update.
local function startMatchIfReady(arenaMetadata)
	if arenaMetadata.State ~= STATE.Vacant then
		return false, "MatchInProgress"
	end

	local playerOne = arenaMetadata.QueueSlots["1"]
	local playerTwo = arenaMetadata.QueueSlots["2"]
	if not isActivePlayer(playerOne) or not isActivePlayer(playerTwo) then
		return false, "WaitingForPlayers"
	end

	local playerOneSpawn = getSpawnReference(arenaMetadata, "1")
	local playerTwoSpawn = getSpawnReference(arenaMetadata, "2")
	if not playerOneSpawn or not playerTwoSpawn then
		warn("Arena " .. arenaMetadata.ArenaId .. " is missing fight spawn references")
		return false, "MissingSpawnReference"
	end

	local playerOneSpawned = spawnMatchCharacter(playerOne, playerOneSpawn, playerTwoSpawn)
	local playerTwoSpawned = spawnMatchCharacter(playerTwo, playerTwoSpawn, playerOneSpawn)
	if not playerOneSpawned or not playerTwoSpawned then
		return false, "MissingDefaultRig"
	end

	arenaMetadata.State = STATE.Fight
	arenaMetadata.CurrentMatch = {
		State = STATE.Fight,
		Fighters = {
			["1"] = playerOne,
			["2"] = playerTwo,
		},
		StartedAt = os.clock(),
	}

	setFightCameraRemote:FireClient(playerOne, true, arenaMetadata.ArenaId, playerOne, playerTwo)
	setFightCameraRemote:FireClient(playerTwo, true, arenaMetadata.ArenaId, playerOne, playerTwo)

	return true, "MatchStarted"
end

-- Registers or updates arena metadata for queueing. Parameters: arenaId identifies the arena, arenaModel (Model) is the arena instance.
function MatchService.RegisterArena(arenaId, arenaModel)
	local arenaKey = getArenaKey(arenaId)
	local arenaMetadata = arenaMetadataById[arenaKey]

	if arenaMetadata then
		arenaMetadata.Arena = arenaModel
		return true, "ArenaAlreadyRegistered"
	end

	arenaMetadataById[arenaKey] = {
		ArenaId = arenaKey,
		Arena = arenaModel,
		State = STATE.Vacant,
		QueueSlots = {},
		CurrentMatch = nil,
	}

	return true, "ArenaRegistered"
end

-- Queues a player for a specific arena slot and moves them into place. Parameters: player (Player), arenaId, slotId, and referencePart (BasePart) identify the queue request.
function MatchService.QueuePlayerForArenaSlot(player, arenaId, slotId, referencePart)
	if not isActivePlayer(player) then
		return false, "InvalidPlayer"
	end

	if queuedSlotByPlayer[player] then
		return false, "PlayerAlreadyQueued"
	end

	local arenaKey = getArenaKey(arenaId)
	local arenaMetadata = arenaMetadataById[arenaKey]
	if not arenaMetadata then
		return false, "ArenaNotRegistered"
	end

	if arenaMetadata.State == STATE.Fight then
		return false, "MatchInProgress"
	end

	local slotKey = tostring(slotId)
	local queuedPlayer = arenaMetadata.QueueSlots[slotKey]
	if queuedPlayer and isActivePlayer(queuedPlayer) then
		return false, "SlotOccupied"
	end

	arenaMetadata.QueueSlots[slotKey] = player
	queuedSlotByPlayer[player] = {
		ArenaId = arenaKey,
		SlotId = slotKey,
	}

	teleportPlayerToReference(player, referencePart)
	disableQueuedCharacterControls(player)

	local matchStarted, matchStatus = startMatchIfReady(arenaMetadata)
	if matchStarted then
		return true, matchStatus
	end

	return true, "Queued"
end

-- Initializes match service dependencies. Parameters: none.
function MatchService.Init() end

-- Connects cleanup for players leaving the game. Parameters: none.
function MatchService.Start()
	Players.PlayerRemoving:Connect(clearQueuedSlot)
end

return MatchService
