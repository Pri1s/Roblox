local RunSchedulerService = {}

-- Public API
-- RunSchedulerService.BindHeartbeat(id, callback) -> RBXScriptConnection
-- RunSchedulerService.BindStepped(id, callback) -> RBXScriptConnection
-- RunSchedulerService.BindRenderStep(id, priority, callback) -> nil
-- RunSchedulerService.Unbind(id) -> boolean
-- RunSchedulerService.UnbindAll() -> nil
-- RunSchedulerService.IsBound(id) -> boolean

local RunService = game:GetService("RunService")

local activeLoops = {}

local RENDER_STEP_PREFIX = "RunSchedulerService:"

-- Builds the internal Roblox render step name for a scheduler id. Parameters: id (string) is the public loop id.
local function getRenderStepName(id)
	return RENDER_STEP_PREFIX .. id
end

-- Disconnects or unbinds a stored loop entry. Parameters: entry (table) is the scheduler record to clean up.
local function disconnectEntry(entry)
	if entry.kind == "RenderStep" then
		RunService:UnbindFromRenderStep(entry.renderStepName)
	elseif entry.connection then
		entry.connection:Disconnect()
	end
end

-- Ensures a scheduler id is usable as a lookup key. Parameters: id (string) is the public loop id.
local function assertValidId(id)
	assert(type(id) == "string" and id ~= "", "RunSchedulerService id must be a non-empty string")
end

-- Ensures a scheduler callback is callable. Parameters: callback (function) is the loop callback.
local function assertValidCallback(callback)
	assert(type(callback) == "function", "RunSchedulerService callback must be a function")
end

-- Binds a Heartbeat callback under a unique id. Parameters: id (string) names the loop and callback (function) receives Heartbeat arguments.
function RunSchedulerService.BindHeartbeat(id, callback)
	assertValidId(id)
	assertValidCallback(callback)
	RunSchedulerService.Unbind(id)

	local connection = RunService.Heartbeat:Connect(callback)
	activeLoops[id] = {
		kind = "Heartbeat",
		connection = connection,
	}

	return connection
end

-- Binds a Stepped callback under a unique id. Parameters: id (string) names the loop and callback (function) receives Stepped arguments.
function RunSchedulerService.BindStepped(id, callback)
	assertValidId(id)
	assertValidCallback(callback)
	RunSchedulerService.Unbind(id)

	local connection = RunService.Stepped:Connect(callback)
	activeLoops[id] = {
		kind = "Stepped",
		connection = connection,
	}

	return connection
end

-- Binds a RenderStep callback under a unique id on the client. Parameters: id (string) names the loop, priority (number) sets render order, and callback (function) receives RenderStep arguments.
function RunSchedulerService.BindRenderStep(id, priority, callback)
	assertValidId(id)
	assertValidCallback(callback)
	RunSchedulerService.Unbind(id)

	if not RunService:IsClient() then
		warn("RunSchedulerService.BindRenderStep can only be used on the client")
		return
	end

	local renderStepName = getRenderStepName(id)
	RunService:BindToRenderStep(renderStepName, priority, callback)
	activeLoops[id] = {
		kind = "RenderStep",
		renderStepName = renderStepName,
	}
end

-- Removes a loop by id if it exists. Parameters: id (string) is the public loop id to remove.
function RunSchedulerService.Unbind(id)
	assertValidId(id)

	local entry = activeLoops[id]
	if not entry then
		return false
	end

	disconnectEntry(entry)
	activeLoops[id] = nil
	return true
end

-- Removes every loop currently owned by the scheduler. Parameters: none.
function RunSchedulerService.UnbindAll()
	while true do
		local id, entry = next(activeLoops)
		if not id then
			break
		end

		disconnectEntry(entry)
		activeLoops[id] = nil
	end
end

-- Reports whether a loop id is currently registered. Parameters: id (string) is the public loop id to check.
function RunSchedulerService.IsBound(id)
	assertValidId(id)
	return activeLoops[id] ~= nil
end

-- Initializes scheduler dependencies. Parameters: none.
function RunSchedulerService.Init() end

-- Starts the scheduler service. Parameters: none.
function RunSchedulerService.Start() end

return RunSchedulerService
