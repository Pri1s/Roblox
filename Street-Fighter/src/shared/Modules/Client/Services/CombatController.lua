-- Manages the local player's combat state machine. Registers keyboard bindings
-- via InputHandler, resolves attack inputs against held directional modifiers,
-- and drives the Attack → Recovery → Idle pipeline with timer-based transitions.
-- Prints every state change to Output until animations are wired.

local CombatController = {}

local InputHandler

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
	[State.BackPunch]    = { hitLevel = "High", reaction = "NormalStun", recovery = 0.50 },
	[State.FrontKick]    = { hitLevel = "Mid",  reaction = "NormalStun", recovery = 0.40 },
	[State.BackKick]     = { hitLevel = "Low",  reaction = "NormalStun", recovery = 0.45 },
	[State.CrouchingJab] = { hitLevel = "Mid",  reaction = "NormalStun", recovery = 0.28 },
	[State.Uppercut]     = { hitLevel = "High", reaction = "Stagger",    recovery = 0.60 },
	[State.CrouchingKick]= { hitLevel = "Low",  reaction = "NormalStun", recovery = 0.40 },
	[State.LowKick]      = { hitLevel = "Low",  reaction = "NormalStun", recovery = 0.40 },
	[State.Sweep]        = { hitLevel = "Low",  reaction = "Knockdown",  recovery = 0.70 },
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

-- Sets currentState and prints the transition to Output.
local function setState(state)
	currentState = state
	print("[Combat]", state)
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

-- Transitions into attackState, immediately enters Recovery, then returns to Idle
-- after the attack's recovery duration. Guards the timer so a stale callback cannot
-- advance the state if something else already changed it.
-- attackState: a State constant with a corresponding AttackData entry
local function initiateAttack(attackState)
	if not NeutralStates[currentState] then return end
	local data = AttackData[attackState]
	if not data then return end

	setState(attackState)
	setState(State.Recovery)

	task.delay(data.recovery, function()
		if currentState ~= State.Recovery then return end
		setState(State.Idle)
	end)
end

-- Grabs InputHandler from _G after all modules have been required.
function CombatController.Init()
	InputHandler = _G.InputHandler
end

-- Registers all keybindings with InputHandler for the duration of the session.
function CombatController.Start()
	-- Crouch / Down modifier (spec transitions 3 & 4)
	InputHandler.RegisterKeyDown(Keys.Down, function()
		modifiers.isDown = true
		if NeutralStates[currentState] then setState(State.Crouching) end
	end)
	InputHandler.RegisterKeyUp(Keys.Down, function()
		modifiers.isDown = false
		if currentState == State.Crouching then setState(State.Idle) end
	end)

	-- Walk backward / Back modifier (spec transitions 1 & 2)
	InputHandler.RegisterKeyDown(Keys.Back, function()
		modifiers.isBack = true
		if currentState == State.Idle then setState(State.Walking) end
	end)
	InputHandler.RegisterKeyUp(Keys.Back, function()
		modifiers.isBack = false
		if currentState == State.Walking then setState(State.Idle) end
	end)

	-- Walk forward (spec transitions 1 & 2)
	InputHandler.RegisterKeyDown(Keys.Forward, function()
		modifiers.isForward = true
		if currentState == State.Idle then setState(State.Walking) end
	end)
	InputHandler.RegisterKeyUp(Keys.Forward, function()
		modifiers.isForward = false
		if currentState == State.Walking then setState(State.Idle) end
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
end

return CombatController
