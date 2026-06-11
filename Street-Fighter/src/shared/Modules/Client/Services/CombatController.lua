-- Manages the local player's combat state machine. Registers keyboard bindings
-- via InputHandler, resolves attack inputs against held directional modifiers,
-- and drives the Attack → Recovery → Idle pipeline with timer-based transitions.
-- Plays matching local animation tracks through AnimationService on transition.

local CombatController = {}

local InputHandler
local AnimationService

-- All spec states. The local player is always in exactly one.
local State = {
	-- Neutral
	Idle           = "Idle",
	Walking        = "Walking",
	Crouching      = "Crouching",
	-- Basic attacks (inputs 1–4)
	Jab            = "Jab",          -- 1: Front Punch (High)
	BackPunch      = "BackPunch",    -- 2: Back Punch  (High)
	FrontKick      = "FrontKick",    -- 3: Front Kick  (Mid)
	BackKick       = "BackKick",     -- 4: Back Kick   (Low)
	-- Directional modifier attacks
	CrouchingJab   = "CrouchingJab",  -- D+1 (Mid)
	Uppercut       = "Uppercut",      -- D+2 (High → Stagger)
	CrouchingKick  = "CrouchingKick", -- D+3 (Low)
	LowKick        = "LowKick",       -- D+4 (Low)
	Sweep          = "Sweep",         -- B+4 (Low → Knockdown)
	-- Post-attack hub (all offensive actions drain here)
	Recovery       = "Recovery",
	-- Blocking — not wired yet
	StandingBlock  = "StandingBlock",
	CrouchBlock    = "CrouchBlock",
	FlawlessBlock  = "FlawlessBlock",
	-- Active — not wired yet
	Grab           = "Grab",
	ComboActive    = "ComboActive",
	ComboBlocked   = "ComboBlocked",
	-- Hit reactions (opponent FSM) — not wired yet
	NormalStun     = "NormalStun",
	Stagger        = "Stagger",
	Pushback       = "Pushback",
	Knockdown      = "Knockdown",
	Downed         = "Downed",
	WakeUpAttack   = "WakeUpAttack",
}

-- Per-attack metadata. recovery = duration of the Recovery state before returning to Idle.
-- hitLevel and reaction are reserved for hit-resolution networking.
-- All durations are placeholder values; tune when animations land.
local AttackData = {
	[State.Jab]          = { hitLevel = "High", reaction = "NormalStun", recovery = 0.30 },
	[State.BackPunch]    = { hitLevel = "High", reaction = "NormalStun", recovery = 0.50, animationId = "rbxassetid://133996136684331" },
	[State.FrontKick]    = { hitLevel = "Mid",  reaction = "NormalStun", recovery = 0.40, animationId = "rbxassetid://83388883154741" },
	[State.BackKick]     = { hitLevel = "Low",  reaction = "NormalStun", recovery = 0.45, animationId = "rbxassetid://124099366082829" },
	[State.CrouchingJab] = { hitLevel = "Mid",  reaction = "NormalStun", recovery = 0.28 },
	[State.Uppercut]     = { hitLevel = "High", reaction = "Stagger",    recovery = 0.60 },
	[State.CrouchingKick]= { hitLevel = "Low",  reaction = "NormalStun", recovery = 0.40 },
	[State.LowKick]      = { hitLevel = "Low",  reaction = "NormalStun", recovery = 0.40 },
	[State.Sweep]        = { hitLevel = "Low",  reaction = "Knockdown",  recovery = 0.70 },
}

-- Per-state animation metadata for non-attack combat states.
local StateAnimationData = {
	[State.Idle] = {
		animationId = "rbxassetid://113160966831548",
		priority = Enum.AnimationPriority.Idle,
		looped = true,
	},
}

-- Attacks may be initiated from any of these states.
local NeutralStates = {
	[State.Idle]      = true,
	[State.Walking]   = true,
	[State.Crouching] = true,
}

-- Keybindings. FG notation: D = Down/crouch, B = Back, F = Forward.
local Keys = {
	Down    = Enum.KeyCode.S,     -- D modifier / crouch
	Back    = Enum.KeyCode.A,     -- B modifier / walk backward
	Forward = Enum.KeyCode.D,     -- walk forward
	Attack1 = Enum.KeyCode.One,   -- Front Punch
	Attack2 = Enum.KeyCode.Two,   -- Back Punch
	Attack3 = Enum.KeyCode.Three, -- Front Kick
	Attack4 = Enum.KeyCode.Four,  -- Back Kick
}

local currentState = State.Idle
local modifiers = { isDown = false, isBack = false, isForward = false }

-- Applies combat playback settings to a loaded track before play.
-- track: AnimationTrack returned by AnimationService
-- data: animation metadata table with optional priority and looped fields
local function configureTrack(track, data)
	if not track then return end

	track.Priority = data.priority or Enum.AnimationPriority.Action
	track.Looped = data.looped == true
end

-- Preloads every configured combat animation before any state transition plays.
local function preloadConfiguredAnimations()
	for state, data in pairs(StateAnimationData) do
		local track = AnimationService.Preload(state, data.animationId)
		configureTrack(track, data)
	end

	for state, data in pairs(AttackData) do
		if data.animationId then
			local track = AnimationService.Preload(state, data.animationId)
			configureTrack(track, data)
		end
	end
end

-- Plays the animation tied to a state and stops any previous combat animation.
-- state: State string to look up in StateAnimationData
local function playStateAnimation(state)
	local data = StateAnimationData[state]
	if not data then return end

	AnimationService.StopAll(0.1)

	local track = AnimationService.Load(state, data.animationId)
	if not track then return end

	configureTrack(track, data)
	track:Play(0.1)
end

-- Updates currentState and plays the state's combat animation when configured.
-- state: State string to enter
local function transitionTo(state)
	if currentState == state and AnimationService.IsPlaying(state) then return end

	currentState = state
	playStateAnimation(state)
end

-- Returns the attack state for button n (1–4) given the currently held modifiers.
-- Checks directional modifiers first; falls back to basic attacks.
local function resolveAttack(n)
	if modifiers.isDown then
		if     n == 1 then return State.CrouchingJab
		elseif n == 2 then return State.Uppercut
		elseif n == 3 then return State.CrouchingKick
		elseif n == 4 then return State.LowKick
		end
	elseif modifiers.isBack then
		if n == 4 then return State.Sweep end
	end
	if     n == 1 then return State.Jab
	elseif n == 2 then return State.BackPunch
	elseif n == 3 then return State.FrontKick
	elseif n == 4 then return State.BackKick
	end
end

-- Transitions through Recovery and returns to Idle after the given delay.
-- attackState: State string that must still be current when recovery starts
-- delaySeconds: number of seconds before entering Recovery
local function scheduleRecovery(attackState, delaySeconds)
	task.delay(delaySeconds, function()
		if currentState ~= attackState then return end

		transitionTo(State.Recovery)
		transitionTo(State.Idle)
	end)
end

-- Transitions into attackState, plays its configured local animation when present,
-- then returns to Idle after the animation or placeholder recovery duration.
-- attackState: a State constant with a corresponding AttackData entry
local function initiateAttack(attackState)
	if not NeutralStates[currentState] then return end
	local data = AttackData[attackState]
	if not data then return end

	transitionTo(attackState)
	if not data.animationId then
		scheduleRecovery(attackState, data.recovery)
		return
	end

	AnimationService.StopAll(0.1)
	local track = AnimationService.Load(attackState, data.animationId)
	configureTrack(track, data)
	if track then track:Play(0.1) end

	local delaySeconds = track and track.Length > 0 and track.Length or data.recovery
	scheduleRecovery(attackState, delaySeconds)
end

-- Grabs client services from _G after all modules have been required.
function CombatController.Init()
	InputHandler = _G.InputHandler
	AnimationService = _G.AnimationService
end

-- Registers all keybindings with InputHandler for the duration of the session.
function CombatController.Start()
	preloadConfiguredAnimations()

	-- Crouch / Down modifier (spec transitions 3 & 4)
	InputHandler.RegisterKeyDown(Keys.Down, function()
		modifiers.isDown = true
		if NeutralStates[currentState] then transitionTo(State.Crouching) end
	end)
	InputHandler.RegisterKeyUp(Keys.Down, function()
		modifiers.isDown = false
		if currentState == State.Crouching then transitionTo(State.Idle) end
	end)

	-- Walk backward / Back modifier (spec transitions 1 & 2)
	InputHandler.RegisterKeyDown(Keys.Back, function()
		modifiers.isBack = true
		if currentState == State.Idle then transitionTo(State.Walking) end
	end)
	InputHandler.RegisterKeyUp(Keys.Back, function()
		modifiers.isBack = false
		if currentState == State.Walking then transitionTo(State.Idle) end
	end)

	-- Walk forward (spec transitions 1 & 2)
	InputHandler.RegisterKeyDown(Keys.Forward, function()
		modifiers.isForward = true
		if currentState == State.Idle then transitionTo(State.Walking) end
	end)
	InputHandler.RegisterKeyUp(Keys.Forward, function()
		modifiers.isForward = false
		if currentState == State.Walking then transitionTo(State.Idle) end
	end)

	-- Attack buttons 1–4 (spec transitions 10–13 and directional equivalents)
	local attackKeys = { Keys.Attack1, Keys.Attack2, Keys.Attack3, Keys.Attack4 }
	for i, keyCode in ipairs(attackKeys) do
		local n = i
		InputHandler.RegisterKeyDown(keyCode, function()
			local attackState = resolveAttack(n)
			if attackState then initiateAttack(attackState) end
		end)
	end

	transitionTo(State.Idle)
end

return CombatController
