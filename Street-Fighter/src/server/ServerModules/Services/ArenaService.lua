local ArenaService = {}

local Workspace = game:GetService("Workspace")

local MatchService
local promptConnections = {}

local PROMPT_NAME = "QueuePrompt"
local QUEUE_INITIALIZERS_NAME = "QueueInitializers"
local REFERENCE_NAME = "Reference"

-- Gets or creates the queue prompt for an arena slot. Parameters: referencePart (BasePart), arenaId, and slotId identify where the prompt belongs.
local function getOrCreatePrompt(referencePart, arenaId, slotId)
	local prompt = referencePart:FindFirstChild(PROMPT_NAME)
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Queue"
	prompt.ObjectText = "Arena " .. arenaId .. " Side " .. slotId
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = referencePart

	return prompt
end

-- Connects a queue prompt to the match queue flow. Parameters: arenaId, slotId, and referencePart identify the slot to queue for.
local function connectQueuePrompt(arenaId, slotId, referencePart)
	local prompt = getOrCreatePrompt(referencePart, arenaId, slotId)
	-- Queues the triggering player for this arena slot and disables the prompt on success. Parameters: player (Player) is the prompt activator.
	promptConnections[prompt] = prompt.Triggered:Connect(function(player)
		local queued = MatchService.QueuePlayerForArenaSlot(player, arenaId, slotId, referencePart)
		if queued then
			prompt.Enabled = false
		end
	end)
end

-- Registers an arena and wires up its queue prompts. Parameters: arena (Model) is the arena being registered.
local function registerArena(arena)
	local arenaId = arena.Name
	MatchService.RegisterArena(arenaId, arena)

	local queueInitializers = arena:FindFirstChild(QUEUE_INITIALIZERS_NAME)
	if not queueInitializers then
		warn("Arena " .. arenaId .. " is missing " .. QUEUE_INITIALIZERS_NAME)
		return
	end

	for _, slotId in ipairs({ "1", "2" }) do
		local slot = queueInitializers:FindFirstChild(slotId)
		local referencePart = slot and slot:FindFirstChild(REFERENCE_NAME)
		if referencePart and referencePart:IsA("BasePart") then
			connectQueuePrompt(arenaId, slotId, referencePart)
		else
			warn("Arena " .. arenaId .. " queue slot " .. slotId .. " is missing a Reference part")
		end
	end
end

-- Captures service dependencies from the loader. Parameters: none.
function ArenaService.Init()
	MatchService = _G.MatchService
end

-- Registers all arenas currently under Workspace.Arenas. Parameters: none.
function ArenaService.Start()
	local arenasFolder = Workspace:FindFirstChild("Arenas")
	if not arenasFolder then
		warn("Workspace.Arenas was not found; no arenas were registered")
		return
	end

	for _, arena in ipairs(arenasFolder:GetChildren()) do
		registerArena(arena)
	end
end

return ArenaService
