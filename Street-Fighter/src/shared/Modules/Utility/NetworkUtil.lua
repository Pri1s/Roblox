-- Shared utilities for creating Roblox networking instances at runtime.
-- Use on the server to instantiate RemoteEvents, RemoteFunctions, etc.
-- Clients access them via WaitForChild on the same parent.

local NetworkUtil = {}

-- Creates a new Instance of className, assigns name, parents it, and returns it.
-- className: Roblox ClassName string (e.g. "RemoteFunction", "RemoteEvent")
-- name: the Name to assign to the instance
-- parent: Instance to parent to
function NetworkUtil.create(className, name, parent)
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

return NetworkUtil
