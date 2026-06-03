-- Centralizes RunService step bindings. Modules register callbacks here
-- instead of connecting directly to RunService.

local RunServiceHandler = {}

local RunService = game:GetService("RunService")

-- Maps string step keys to their RunService events.
-- Heartbeat and Stepped are supported but disabled; uncomment to activate.
local STEP_TYPES = {
	RenderStepped = RunService.RenderStepped,
	-- Heartbeat = RunService.Heartbeat,
	-- Stepped = RunService.Stepped,
}

-- handlers[stepType][id] = callback
local handlers = {}
-- One persistent RBXScriptConnection per active step type
local connections = {}

local nextId = 0

-- Registers callback on the given stepType event; returns a unique integer ID.
-- stepType: string key from STEP_TYPES (e.g. "RenderStepped")
-- callback: function called each tick with the same args as the RunService event
function RunServiceHandler.Register(stepType, callback)
	assert(STEP_TYPES[stepType], "Unsupported stepType: " .. tostring(stepType))

	if not handlers[stepType] then
		handlers[stepType] = {}
	end

	nextId += 1
	local id = nextId
	handlers[stepType][id] = callback

	-- Lazily create the connection on the first registration for this step type
	if not connections[stepType] then
		connections[stepType] = STEP_TYPES[stepType]:Connect(function(...)
			for _, cb in pairs(handlers[stepType]) do
				cb(...)
			end
		end)
	end

	return id
end

-- Removes the callback associated with id.
-- Disconnects the underlying RunService connection if no handlers remain for that step type.
function RunServiceHandler.Unregister(id)
	for stepType, stepHandlers in pairs(handlers) do
		if stepHandlers[id] then
			stepHandlers[id] = nil

			-- Disconnect if this was the last handler for the step type
			if not next(stepHandlers) then
				connections[stepType]:Disconnect()
				connections[stepType] = nil
				handlers[stepType] = nil
			end

			return
		end
	end
end

function RunServiceHandler.Init() end

function RunServiceHandler.Start() end

return RunServiceHandler
