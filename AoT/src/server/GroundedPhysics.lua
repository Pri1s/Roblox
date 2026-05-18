local GroundedPhysics = {}

local Workspace = game:GetService("Workspace")

local GroundedPhysicsConfig

function GroundedPhysics.Init()
	GroundedPhysicsConfig = _G.GroundedPhysicsConfig
end

function GroundedPhysics.Start()
	Workspace.Gravity = GroundedPhysicsConfig.Gravity
end

return GroundedPhysics
