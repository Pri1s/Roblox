-- Centralizes keyboard input bindings. Modules register callbacks for specific
-- KeyCodes here instead of connecting directly to UserInputService.

local InputHandler = {}

local UserInputService = game:GetService("UserInputService")

-- keyMap[inputType]["Down"|"Up"][keyCode][id] = callback
-- Stores callbacks keyed by KeyCode and direction for O(1) dispatch per event.
local keyMap = {
	Down = {},
	Up = {},
}

-- handlers[id] = { keyCode, callback, inputType }
-- Flat lookup table so Unregister can remove an entry in O(1).
local handlers = {}

local nextId = 0

-- Shared guard applied by both InputBegan and InputEnded connections.
-- Returns true if the event should be ignored.
local function shouldIgnore(input, gameProcessed)
	return gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard
end

-- Registers callback to fire when keyCode is pressed down; returns a unique ID.
-- keyCode: Enum.KeyCode value
-- callback: function(InputObject)
function InputHandler.RegisterKeyDown(keyCode, callback)
	nextId += 1
	local id = nextId

	if not keyMap.Down[keyCode] then
		keyMap.Down[keyCode] = {}
	end
	keyMap.Down[keyCode][id] = callback
	handlers[id] = { keyCode = keyCode, callback = callback, inputType = "Down" }

	return id
end

-- Registers callback to fire when keyCode is released; returns a unique ID.
-- keyCode: Enum.KeyCode value
-- callback: function(InputObject)
function InputHandler.RegisterKeyUp(keyCode, callback)
	nextId += 1
	local id = nextId

	if not keyMap.Up[keyCode] then
		keyMap.Up[keyCode] = {}
	end
	keyMap.Up[keyCode][id] = callback
	handlers[id] = { keyCode = keyCode, callback = callback, inputType = "Up" }

	return id
end

-- Removes the callback associated with id and cleans up its keyMap entry.
function InputHandler.Unregister(id)
	local entry = handlers[id]
	if not entry then return end

	handlers[id] = nil

	local dirMap = keyMap[entry.inputType]
	if dirMap[entry.keyCode] then
		dirMap[entry.keyCode][id] = nil
		if not next(dirMap[entry.keyCode]) then
			dirMap[entry.keyCode] = nil
		end
	end
end

-- Persistent connections — live for the entire client session
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if shouldIgnore(input, gameProcessed) then return end
	local bucket = keyMap.Down[input.KeyCode]
	if not bucket then return end
	for _, cb in pairs(bucket) do
		cb(input)
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if shouldIgnore(input, gameProcessed) then return end
	local bucket = keyMap.Up[input.KeyCode]
	if not bucket then return end
	for _, cb in pairs(bucket) do
		cb(input)
	end
end)

function InputHandler.Init() end

function InputHandler.Start() end

return InputHandler
