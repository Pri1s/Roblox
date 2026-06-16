-- Owns authoritative round and match rules for the active two-player fight.
--
-- Public API:
-- MatchService.GetState() -> table
-- MatchService.GetSlot(player) -> "Player1" | "Player2" | nil
-- MatchService.ReportHealth(player, health)
-- MatchService.ResetMatch()

warn("[MatchDebug] MatchService module file loaded; waiting for loader to call Init/Start.")

local MatchService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local NetworkUtil = require(ReplicatedStorage.Modules.Utility.NetworkUtil)

local ROUND_WINS_TO_MATCH = 3
local PLAYER_ONE = "Player1"
local PLAYER_TWO = "Player2"
local ARENA_TEMPLATE_NAME = "SakuraPaths"
local SPAWN_Y_OFFSET = 4
local DEBUG_PREFIX = "[MatchDebug]"
local MATCH_CAMERA_REMOTE_NAME = "MatchCameraStateChanged"
local MATCH_CAMERA_STATE_REMOTE_NAME = "GetMatchCameraState"

local slots = {
	[PLAYER_ONE] = nil,
	[PLAYER_TWO] = nil,
}

local state = {
	currentRound = 1,
	wins = {
		[PLAYER_ONE] = 0,
		[PLAYER_TWO] = 0,
	},
	isRoundActive = false,
	isMatchComplete = false,
	matchWinner = nil,
}

local characterConnections = {}
local healthConnections = {}
local activeArena = nil
local matchCameraStateChanged = nil
local getMatchCameraState = nil
local isMatchCameraActive = false

-- Formats a player for compact debug output.
-- player: Player instance or nil
local function formatPlayer(player)
	if not player then
		return "nil"
	end

	return player.Name .. "(" .. player.UserId .. ")"
end

-- Formats the current match slots for debug output.
local function formatSlots()
	return PLAYER_ONE .. "=" .. formatPlayer(slots[PLAYER_ONE]) .. ", " .. PLAYER_TWO .. "=" .. formatPlayer(slots[PLAYER_TWO])
end

-- Formats the current round and match state for debug output.
local function formatState()
	return "round="
		.. state.currentRound
		.. ", wins="
		.. PLAYER_ONE
		.. ":"
		.. state.wins[PLAYER_ONE]
		.. "/"
		.. PLAYER_TWO
		.. ":"
		.. state.wins[PLAYER_TWO]
		.. ", roundActive="
		.. tostring(state.isRoundActive)
		.. ", matchComplete="
		.. tostring(state.isMatchComplete)
		.. ", winner="
		.. tostring(state.matchWinner)
end

-- Prints a standard match debug message.
-- message: string to send to Studio Output
local function debugPrint(message)
	print(DEBUG_PREFIX .. " " .. message)
end

-- Prints a standard match debug warning.
-- message: string to send to Studio Output as a warning
local function debugWarn(message)
	warn(DEBUG_PREFIX .. " " .. message)
end

-- Sends one match camera payload to a connected player.
-- player: Player instance receiving the camera state
-- payload: table passed to the client CameraService
local function fireMatchCameraState(player, payload)
	if player and player.Parent == Players and matchCameraStateChanged then
		debugPrint("Firing match camera state to " .. formatPlayer(player) .. ": isActive=" .. tostring(payload and payload.isActive))
		matchCameraStateChanged:FireClient(player, payload)
	end
end

-- Tells both fighters to enter the combat camera for the active arena.
local function activateMatchCamera()
	if isMatchCameraActive then return end

	local player1 = slots[PLAYER_ONE]
	local player2 = slots[PLAYER_TWO]
	if not player1 or not player2 or not activeArena then return end

	isMatchCameraActive = true

	local payload = {
		isActive = true,
		player1 = player1,
		player2 = player2,
		arena = activeArena,
	}

	fireMatchCameraState(player1, payload)
	fireMatchCameraState(player2, payload)
	debugPrint("Activated match camera for " .. PLAYER_ONE .. " and " .. PLAYER_TWO .. ".")
end

-- Tells the provided fighters to return to their default Roblox cameras.
-- player1: first Player instance to notify
-- player2: second Player instance to notify
local function deactivateMatchCamera(player1, player2)
	if not isMatchCameraActive then return end

	isMatchCameraActive = false

	local payload = {
		isActive = false,
	}

	fireMatchCameraState(player1, payload)
	if player2 ~= player1 then
		fireMatchCameraState(player2, payload)
	end

	debugPrint("Deactivated match camera.")
end

-- Finds or creates the runtime arena container in Workspace.
local function getArenasFolder()
	local arenasFolder = Workspace:FindFirstChild("Arenas")
	if arenasFolder then
		return arenasFolder
	end

	arenasFolder = Instance.new("Folder")
	arenasFolder.Name = "Arenas"
	arenasFolder.Parent = Workspace

	debugPrint("Created Workspace.Arenas runtime folder.")

	return arenasFolder
end

-- Finds the configured arena template in ServerStorage.
local function getArenaTemplate()
	local arenaTemplates = ServerStorage:FindFirstChild("ArenaTemplates")
	if not arenaTemplates then
		debugWarn("Arena clone blocked: ServerStorage.ArenaTemplates is missing.")
		return nil
	end

	local arenaTemplate = arenaTemplates:FindFirstChild(ARENA_TEMPLATE_NAME)
	if not arenaTemplate then
		debugWarn("Arena clone blocked: ServerStorage.ArenaTemplates." .. ARENA_TEMPLATE_NAME .. " is missing.")
		return nil
	end

	return arenaTemplate
end

-- Clones the configured arena template into Workspace.Arenas once per match.
local function getActiveArena()
	if activeArena and activeArena.Parent then
		return activeArena
	end

	local arenaTemplate = getArenaTemplate()
	if not arenaTemplate then
		return nil
	end

	activeArena = arenaTemplate:Clone()
	activeArena.Name = ARENA_TEMPLATE_NAME
	activeArena.Parent = getArenasFolder()

	debugPrint("Cloned arena template into Workspace.Arenas: " .. activeArena:GetFullName())

	return activeArena
end

-- Reads one spawn CFrame from a cloned arena and applies the Y offset.
-- arena: cloned arena model/folder containing Spawns
-- spawnName: string name of the spawn part, usually "1" or "2"
local function getSpawnCFrame(arena, spawnName)
	local spawns = arena:FindFirstChild("Spawns")
	if not spawns then
		debugWarn("Arena teleport blocked: " .. arena:GetFullName() .. ".Spawns is missing.")
		return nil
	end

	local spawnPart = spawns:FindFirstChild(spawnName)
	if not spawnPart then
		debugWarn("Arena teleport blocked: spawn " .. spawnName .. " is missing under " .. spawns:GetFullName() .. ".")
		return nil
	end

	if not spawnPart:IsA("BasePart") then
		debugWarn("Arena teleport blocked: spawn " .. spawnName .. " is not a BasePart.")
		return nil
	end

	return spawnPart.CFrame + Vector3.new(0, SPAWN_Y_OFFSET, 0)
end

-- Teleports one player's character to a provided spawn CFrame.
-- player: Player instance to move
-- spawnCFrame: CFrame target for the HumanoidRootPart
-- slotName: match slot name used for debug output
local function teleportPlayerToSpawn(player, spawnCFrame, slotName)
	local character = player.Character
	if not character then
		debugWarn("Arena teleport blocked: " .. slotName .. " has no character. Player=" .. formatPlayer(player))
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		debugWarn("Arena teleport blocked: " .. slotName .. " has no HumanoidRootPart. Player=" .. formatPlayer(player))
		return false
	end

	rootPart.CFrame = spawnCFrame
	debugPrint("Teleported " .. slotName .. " " .. formatPlayer(player) .. " to arena spawn.")

	return true
end

-- Prepares the active arena and teleports both assigned players into it.
local function teleportPlayersToArena()
	local arena = getActiveArena()
	if not arena then
		return false
	end

	local spawn1CFrame = getSpawnCFrame(arena, "1")
	local spawn2CFrame = getSpawnCFrame(arena, "2")
	if not spawn1CFrame or not spawn2CFrame then
		return false
	end

	local player1 = slots[PLAYER_ONE]
	local player2 = slots[PLAYER_TWO]
	local teleportedPlayer1 = teleportPlayerToSpawn(player1, spawn1CFrame, PLAYER_ONE)
	local teleportedPlayer2 = teleportPlayerToSpawn(player2, spawn2CFrame, PLAYER_TWO)

	return teleportedPlayer1 and teleportedPlayer2
end

-- Destroys the cloned match arena when the match state is reset.
local function clearActiveArena()
	if activeArena then
		debugPrint("Destroying active arena: " .. activeArena:GetFullName())
		activeArena:Destroy()
		activeArena = nil
	end
end

-- Returns the opposing slot name for a tracked match slot.
-- slotName: "Player1" or "Player2"
local function getOpponentSlot(slotName)
	if slotName == PLAYER_ONE then
		return PLAYER_TWO
	elseif slotName == PLAYER_TWO then
		return PLAYER_ONE
	end

	return nil
end

-- Finds the match slot assigned to the given player.
-- player: Player instance to look up
local function getPlayerSlot(player)
	for slotName, slotPlayer in pairs(slots) do
		if slotPlayer == player then
			return slotName
		end
	end

	return nil
end

-- Builds the current camera payload for a fighter that may have missed the RemoteEvent.
-- player: Player instance requesting the latest match camera state
local function getMatchCameraPayloadFor(player)
	if not isMatchCameraActive or not activeArena or not getPlayerSlot(player) then
		return {
			isActive = false,
		}
	end

	return {
		isActive = true,
		player1 = slots[PLAYER_ONE],
		player2 = slots[PLAYER_TWO],
		arena = activeArena,
	}
end

-- Reports whether both tracked players currently have living humanoids.
local function canStartRound()
	for _, slotName in ipairs({ PLAYER_ONE, PLAYER_TWO }) do
		local player = slots[slotName]
		if not player then
			debugPrint("Round start blocked: " .. slotName .. " has no assigned player. Slots: " .. formatSlots())
			return false
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			debugPrint("Round start blocked: " .. slotName .. " has no Humanoid yet. Player=" .. formatPlayer(player))
			return false
		end

		if humanoid.Health <= 0 then
			debugPrint("Round start blocked: " .. slotName .. " health is " .. humanoid.Health .. ". Player=" .. formatPlayer(player))
			return false
		end
	end

	return true
end

-- Marks the current round active once both assigned players are alive.
local function tryStartRound()
	if state.isMatchComplete or state.isRoundActive then
		debugPrint("Round start skipped: already complete or active. " .. formatState())
		return
	end

	if canStartRound() then
		if not teleportPlayersToArena() then
			debugWarn("Round start blocked: arena setup or teleport failed.")
			return
		end

		state.isRoundActive = true
		activateMatchCamera()
		debugPrint("Round started. " .. formatState() .. ". Slots: " .. formatSlots())
	end
end

-- Awards the round to winnerSlot and advances or completes the match.
-- winnerSlot: slot name receiving the round win
local function awardRound(winnerSlot)
	if not winnerSlot or state.isMatchComplete or not state.isRoundActive then
		debugPrint("Round award skipped: winnerSlot=" .. tostring(winnerSlot) .. ". " .. formatState())
		return
	end

	state.isRoundActive = false
	state.wins[winnerSlot] = state.wins[winnerSlot] + 1
	debugPrint("Round awarded to " .. winnerSlot .. ". " .. formatState())

	if state.wins[winnerSlot] >= ROUND_WINS_TO_MATCH then
		state.isMatchComplete = true
		state.matchWinner = winnerSlot
		debugWarn("Match complete. Winner=" .. winnerSlot .. ". " .. formatState())
		deactivateMatchCamera(slots[PLAYER_ONE], slots[PLAYER_TWO])
		return
	end

	state.currentRound = state.currentRound + 1
	debugPrint("Advanced to next round. " .. formatState())
end

-- Applies the HP-zero loss rule for the player in loserSlot.
-- loserSlot: slot name whose player reached zero health
local function resolveRoundLoss(loserSlot)
	local winnerSlot = getOpponentSlot(loserSlot)
	debugPrint("Resolving round loss: loser=" .. tostring(loserSlot) .. ", winner=" .. tostring(winnerSlot))
	awardRound(winnerSlot)
end

-- Disconnects previous health tracking for a player.
-- player: Player instance whose humanoid connection should be removed
local function clearHealthConnection(player)
	local connection = healthConnections[player]
	if connection then
		connection:Disconnect()
		healthConnections[player] = nil
		debugPrint("Cleared health listener for " .. formatPlayer(player))
	end
end

-- Watches the player's character humanoid for the HP-zero round loss rule.
-- player: Player instance assigned to a match slot
-- character: Character model containing a Humanoid
local function trackCharacterHealth(player, character)
	clearHealthConnection(player)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		debugWarn("Could not track health: character has no Humanoid. Player=" .. formatPlayer(player))
		return
	end

	debugPrint("Tracking Humanoid health for " .. formatPlayer(player) .. ". Initial health=" .. humanoid.Health)

	-- Applies each Humanoid health update to the round-loss rule.
	-- health: current numeric health passed by Humanoid.HealthChanged
	healthConnections[player] = humanoid.HealthChanged:Connect(function(health)
		debugPrint("Humanoid health changed: player=" .. formatPlayer(player) .. ", health=" .. health)
		MatchService.ReportHealth(player, health)
	end)

	MatchService.ReportHealth(player, humanoid.Health)
	tryStartRound()
end

-- Assigns a joining player to the first available match slot.
-- player: Player instance to register
local function assignPlayer(player)
	debugPrint("Player assignment requested for " .. formatPlayer(player))

	if getPlayerSlot(player) then
		debugPrint("Player already assigned. Player=" .. formatPlayer(player) .. ". Slots: " .. formatSlots())
		return
	end

	if not slots[PLAYER_ONE] then
		slots[PLAYER_ONE] = player
		debugPrint("Assigned " .. formatPlayer(player) .. " to " .. PLAYER_ONE)
	elseif not slots[PLAYER_TWO] then
		slots[PLAYER_TWO] = player
		debugPrint("Assigned " .. formatPlayer(player) .. " to " .. PLAYER_TWO)
	else
		debugWarn("No match slot available for " .. formatPlayer(player) .. ". Slots: " .. formatSlots())
		return
	end

	-- Rebinds health tracking whenever Roblox gives the player a new character.
	-- character: newly spawned Character model
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		debugPrint("CharacterAdded fired for " .. formatPlayer(player))
		trackCharacterHealth(player, character)
	end)

	if player.Character then
		debugPrint("Existing character found for " .. formatPlayer(player))
		trackCharacterHealth(player, player.Character)
	else
		debugPrint("Waiting for CharacterAdded for " .. formatPlayer(player))
	end
end

-- Removes all match tracking for a departing player and resets the match state.
-- player: Player instance leaving the server
local function removePlayer(player)
	debugPrint("Removing player from match tracking: " .. formatPlayer(player))

	local slotName = getPlayerSlot(player)
	if slotName then
		slots[slotName] = nil
		debugPrint("Cleared " .. slotName .. " for " .. formatPlayer(player))
	end

	local characterConnection = characterConnections[player]
	if characterConnection then
		characterConnection:Disconnect()
		characterConnections[player] = nil
	end

	clearHealthConnection(player)

	if slotName then
		MatchService.ResetMatch()
	end
end

-- Returns a snapshot of current round, win, and match winner state.
function MatchService.GetState()
	debugPrint("GetState called. " .. formatState())
	return {
		currentRound = state.currentRound,
		wins = {
			[PLAYER_ONE] = state.wins[PLAYER_ONE],
			[PLAYER_TWO] = state.wins[PLAYER_TWO],
		},
		isRoundActive = state.isRoundActive,
		isMatchComplete = state.isMatchComplete,
		matchWinner = state.matchWinner,
	}
end

-- Returns which match slot the player owns, if any.
-- player: Player instance to look up
function MatchService.GetSlot(player)
	debugPrint("GetSlot called for " .. formatPlayer(player) .. ": " .. tostring(getPlayerSlot(player)))
	return getPlayerSlot(player)
end

-- Applies health updates to round rules, treating health <= 0 as a round loss.
-- player: Player instance whose health changed
-- health: current numeric health value
function MatchService.ReportHealth(player, health)
	debugPrint("ReportHealth called: player=" .. formatPlayer(player) .. ", health=" .. health)

	if health > 0 then
		tryStartRound()
		return
	end

	local loserSlot = getPlayerSlot(player)
	if not loserSlot then
		debugWarn("Ignoring health <= 0 for unassigned player " .. formatPlayer(player))
		return
	end

	resolveRoundLoss(loserSlot)
end

-- Resets round number, win counts, and match winner state for a fresh match.
function MatchService.ResetMatch()
	debugWarn("ResetMatch called. Previous state: " .. formatState() .. ". Slots: " .. formatSlots())
	deactivateMatchCamera(slots[PLAYER_ONE], slots[PLAYER_TWO])
	clearActiveArena()

	state.currentRound = 1
	state.wins[PLAYER_ONE] = 0
	state.wins[PLAYER_TWO] = 0
	state.isRoundActive = false
	state.isMatchComplete = false
	state.matchWinner = nil

	tryStartRound()
	debugPrint("ResetMatch finished. " .. formatState())
end

-- Initializes service dependencies and creates match camera networking.
function MatchService.Init()
	matchCameraStateChanged = NetworkUtil.create("RemoteEvent", MATCH_CAMERA_REMOTE_NAME, ReplicatedStorage.Networking)
	getMatchCameraState = NetworkUtil.create("RemoteFunction", MATCH_CAMERA_STATE_REMOTE_NAME, ReplicatedStorage.Networking)

	-- Returns the latest match camera state for clients that connected after the one-shot event fired.
	-- player: Player instance that invoked the RemoteFunction
	getMatchCameraState.OnServerInvoke = function(player)
		local payload = getMatchCameraPayloadFor(player)
		debugPrint("Match camera state requested by " .. formatPlayer(player) .. ": isActive=" .. tostring(payload.isActive))
		return payload
	end

	debugPrint("Init complete.")
end

-- Registers player and humanoid health listeners for round win detection.
function MatchService.Start()
	debugWarn("Start called. Current source has no click-to-request-match client flow; MatchService auto-assigns the first two players and starts when both have living Humanoids.")

	Players.PlayerAdded:Connect(assignPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		debugPrint("Processing existing player during Start: " .. formatPlayer(player))
		assignPlayer(player)
	end

	debugPrint("Start complete. " .. formatState() .. ". Slots: " .. formatSlots())
end

return MatchService
