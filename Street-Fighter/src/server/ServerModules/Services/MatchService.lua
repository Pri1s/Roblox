local MatchService = {}

-- Public API
-- MatchService.QueuePlayer(player, entryData) -> matchId?, status
-- MatchService.CancelEntry(player) -> boolean
-- MatchService.CreateDuel(challenger, opponent, entryData) -> matchId?, status
-- MatchService.BeginFight(matchId) -> boolean, status
-- MatchService.RecordRoundWin(matchId, winner, reason) -> boolean, status
-- MatchService.EndMatch(matchId, winner, reason) -> boolean, status
-- MatchService.GetMatch(matchId) -> matchSnapshot?
-- MatchService.GetMatchForPlayer(player) -> matchSnapshot?
-- MatchService.IsPlayerInMatch(player) -> boolean
-- MatchService.GetWaitingPlayers() -> { Player }
--
-- Events
-- MatchService.MatchReady fires after entry setup completes.
-- MatchService.MatchPhaseChanged fires when a match changes phase.
-- MatchService.MatchEnded fires after exit teardown completes.

local Players = game:GetService("Players")

local PHASE = {
	Entry = "Entry",
	Fight = "Fight",
	Exit = "Exit",
}

local DEFAULT_STARTING_HEALTH = 100
local DEFAULT_ROUNDS_TO_WIN = 2

local nextMatchId = 0
local waitingQueue = {}
local waitingByPlayer = {}
local matchesById = {}
local matchIdByPlayer = {}

MatchService.Phase = PHASE
MatchService.MatchReady = Instance.new("BindableEvent")
MatchService.MatchPhaseChanged = Instance.new("BindableEvent")
MatchService.MatchEnded = Instance.new("BindableEvent")

local function shallowCopy(data)
	local copy = {}
	if data then
		for key, value in pairs(data) do
			copy[key] = value
		end
	end
	return copy
end

local function getNextMatchId()
	nextMatchId = nextMatchId + 1
	return nextMatchId
end

local function isActivePlayer(player)
	return player ~= nil and player.Parent == Players
end

local function isPlayerReserved(player)
	return waitingByPlayer[player] ~= nil or matchIdByPlayer[player] ~= nil
end

local function getParticipant(match, player)
	for _, participant in ipairs(match.Participants) do
		if participant.Player == player then
			return participant
		end
	end

	return nil
end

local function removeWaitingEntry(player)
	local entry = waitingByPlayer[player]
	if not entry then
		return false
	end

	waitingByPlayer[player] = nil
	for index, queuedEntry in ipairs(waitingQueue) do
		if queuedEntry == entry then
			table.remove(waitingQueue, index)
			break
		end
	end

	return true
end

local function buildParticipantSnapshot(participant)
	return {
		Player = participant.Player,
		UserId = participant.UserId,
		CharacterId = participant.CharacterId,
		Health = participant.Health,
		RoundWins = participant.RoundWins,
	}
end

local function buildMatchSnapshot(match)
	local participants = {}
	for _, participant in ipairs(match.Participants) do
		table.insert(participants, buildParticipantSnapshot(participant))
	end

	return {
		Id = match.Id,
		Phase = match.Phase,
		Ready = match.Ready,
		Source = match.Source,
		Round = match.Round,
		RoundsToWin = match.RoundsToWin,
		Participants = participants,
		Result = match.Result,
	}
end

local function makeParticipant(player, entryData)
	local data = shallowCopy(entryData)

	return {
		Player = player,
		UserId = player.UserId,
		CharacterId = data.CharacterId,
		EntryData = data,
		Health = data.StartingHealth or DEFAULT_STARTING_HEALTH,
		RoundWins = 0,
		CharacterData = nil,
	}
end

local function playersAreCompatible(leftEntry, rightEntry)
	return leftEntry.Player ~= rightEntry.Player
end

local function reserveMatchPlayers(match)
	for _, participant in ipairs(match.Participants) do
		matchIdByPlayer[participant.Player] = match.Id
	end
end

local function releaseMatchPlayers(match)
	for _, participant in ipairs(match.Participants) do
		if matchIdByPlayer[participant.Player] == match.Id then
			matchIdByPlayer[participant.Player] = nil
		end
	end
end

local function transitionMatch(match, nextPhase)
	local previousPhase = match.Phase
	match.Phase = nextPhase

	MatchService.MatchPhaseChanged:Fire(buildMatchSnapshot(match), previousPhase, nextPhase)
end

local function assignArena(match)
	-- Arena reservation will be added when arena ownership exists.
	match.Arena = nil
end

local function loadCharacterData(match, participant)
	-- Character-specific stats, skins, and move data will be loaded here.
	participant.CharacterData = nil
end

local function initializeHealth(match, participant)
	participant.Health = participant.EntryData.StartingHealth or DEFAULT_STARTING_HEALTH
end

local function spawnParticipant(match, participant)
	-- Arena spawn placement will be added once arenas expose spawn points.
end

local function runEntrySetup(match)
	assignArena(match)

	for _, participant in ipairs(match.Participants) do
		loadCharacterData(match, participant)
		initializeHealth(match, participant)
		spawnParticipant(match, participant)
	end

	match.Ready = true
	MatchService.MatchReady:Fire(buildMatchSnapshot(match))
end

local function resetRound(match)
	match.Round = match.Round + 1

	for _, participant in ipairs(match.Participants) do
		initializeHealth(match, participant)
	end
end

local function runExitTeardown(match, result)
	match.Result = result
	-- Arena cleanup, result persistence, and lobby return will be added here.
end

local function createMatch(participantEntries, source, entryData)
	local match = {
		Id = getNextMatchId(),
		Phase = PHASE.Entry,
		Ready = false,
		Source = source,
		Round = 1,
		RoundsToWin = (entryData and entryData.RoundsToWin) or DEFAULT_ROUNDS_TO_WIN,
		Participants = {},
		Result = nil,
		Arena = nil,
	}

	for _, entry in ipairs(participantEntries) do
		table.insert(match.Participants, makeParticipant(entry.Player, entry.EntryData))
	end

	matchesById[match.Id] = match
	reserveMatchPlayers(match)
	runEntrySetup(match)

	return match.Id, "MatchReady"
end

local function queueEntry(player, entryData)
	local entry = {
		Player = player,
		EntryData = shallowCopy(entryData),
		QueuedAt = os.clock(),
	}

	waitingByPlayer[player] = entry
	table.insert(waitingQueue, entry)

	return entry
end

local function tryCreateQueuedMatch(entry)
	for _, candidate in ipairs(waitingQueue) do
		if candidate ~= entry and playersAreCompatible(candidate, entry) then
			removeWaitingEntry(candidate.Player)
			removeWaitingEntry(entry.Player)

			return createMatch({
				candidate,
				entry,
			}, "Queue")
		end
	end

	return nil, "WaitingForOpponent"
end

local function getDisconnectWinner(match, disconnectingPlayer)
	for _, participant in ipairs(match.Participants) do
		if participant.Player ~= disconnectingPlayer and isActivePlayer(participant.Player) then
			return participant.Player
		end
	end

	return nil
end

local function onPlayerRemoving(player)
	MatchService.CancelEntry(player)

	local matchId = matchIdByPlayer[player]
	if not matchId then
		return
	end

	local match = matchesById[matchId]
	if not match then
		return
	end

	MatchService.EndMatch(matchId, getDisconnectWinner(match, player), "Disconnect")
end

function MatchService.QueuePlayer(player, entryData)
	if not isActivePlayer(player) then
		return nil, "InvalidPlayer"
	end

	if isPlayerReserved(player) then
		return nil, "PlayerUnavailable"
	end

	local entry = queueEntry(player, entryData)
	return tryCreateQueuedMatch(entry)
end

function MatchService.CancelEntry(player)
	return removeWaitingEntry(player)
end

function MatchService.CreateDuel(challenger, opponent, entryData)
	if not isActivePlayer(challenger) or not isActivePlayer(opponent) then
		return nil, "InvalidPlayer"
	end

	if challenger == opponent then
		return nil, "SamePlayer"
	end

	if matchIdByPlayer[challenger] or matchIdByPlayer[opponent] then
		return nil, "PlayerUnavailable"
	end

	removeWaitingEntry(challenger)
	removeWaitingEntry(opponent)

	local data = shallowCopy(entryData)
	return createMatch({
		{
			Player = challenger,
			EntryData = data.Challenger or data,
		},
		{
			Player = opponent,
			EntryData = data.Opponent or data,
		},
	}, "Challenge", data)
end

function MatchService.BeginFight(matchId)
	local match = matchesById[matchId]
	if not match then
		return false, "MatchNotFound"
	end

	if match.Phase ~= PHASE.Entry then
		return false, "InvalidPhase"
	end

	if not match.Ready then
		return false, "MatchNotReady"
	end

	transitionMatch(match, PHASE.Fight)
	return true, "FightStarted"
end

function MatchService.RecordRoundWin(matchId, winner, reason)
	local match = matchesById[matchId]
	if not match then
		return false, "MatchNotFound"
	end

	if match.Phase ~= PHASE.Fight then
		return false, "InvalidPhase"
	end

	local participant = getParticipant(match, winner)
	if not participant then
		return false, "PlayerNotInMatch"
	end

	participant.RoundWins = participant.RoundWins + 1
	if participant.RoundWins >= match.RoundsToWin then
		return MatchService.EndMatch(matchId, winner, reason or "RoundWins")
	end

	resetRound(match)
	return true, "NextRound"
end

function MatchService.EndMatch(matchId, winner, reason)
	local match = matchesById[matchId]
	if not match then
		return false, "MatchNotFound"
	end

	if match.Phase == PHASE.Exit then
		return false, "InvalidPhase"
	end

	transitionMatch(match, PHASE.Exit)

	local result = {
		Winner = winner,
		WinnerUserId = winner and winner.UserId or nil,
		Reason = reason or "Completed",
		EndedAt = os.clock(),
	}

	runExitTeardown(match, result)
	MatchService.MatchEnded:Fire(buildMatchSnapshot(match))

	releaseMatchPlayers(match)
	matchesById[match.Id] = nil

	return true, "MatchEnded"
end

function MatchService.GetMatch(matchId)
	local match = matchesById[matchId]
	if not match then
		return nil
	end

	return buildMatchSnapshot(match)
end

function MatchService.GetMatchForPlayer(player)
	local matchId = matchIdByPlayer[player]
	if not matchId then
		return nil
	end

	return MatchService.GetMatch(matchId)
end

function MatchService.IsPlayerInMatch(player)
	return matchIdByPlayer[player] ~= nil
end

function MatchService.GetWaitingPlayers()
	local players = {}
	for _, entry in ipairs(waitingQueue) do
		table.insert(players, entry.Player)
	end

	return players
end

function MatchService.Init() end

function MatchService.Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return MatchService
