-- Wraps the ShapecastHitbox Wally package behind a server combat-facing API.
-- V1 is intentionally detection-only: it starts/stops shapecast hitboxes and
-- returns hit payloads, but does not resolve damage, blocks, reactions, or combos.

local HitboxService = {}

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShapecastHitbox = require(ReplicatedStorage.Packages.ShapecastHitbox)

local DEFAULT_CAST_SIZE = Vector3.new(1, 1, 1)
local DEFAULT_CAST_CFRAME = CFrame.identity
local DEFAULT_RESOLUTION = 60
local DEBUG_MODE = true
local DEFAULT_DEBUG_VISUAL_COLOR = Color3.fromRGB(255, 0, 0)
local DEFAULT_DEBUG_VISUAL_TRANSPARENCY = 0.35
local DEBUG_BODY_PART_TRANSPARENCY = 0.75
local DAMAGE_POINT_TAG = "DmgPoint"
local DEBUG_PREFIX = "[HitboxServiceDebug]"

local hitboxesById = {}

-- Prints a standard hitbox service debug message.
-- message: string to send to Studio Output
local function debugPrint(message)
	print(DEBUG_PREFIX .. " " .. message)
end

-- Builds a set from a list of unique hit point names.
-- pointNames: array of Attachment names that should stay active
local function buildPointNameSet(pointNames)
	local pointNameSet = {}

	for _, pointName in ipairs(pointNames or {}) do
		pointNameSet[pointName] = true
	end

	return pointNameSet
end

-- Tags uniquely named hit point descendants so ShapecastHitbox can discover them.
-- rootInstance: Instance whose descendants may include authored hit point attachments
-- pointNameSet: map of requested unique hit point names
local function tagRequestedHitPoints(rootInstance, pointNameSet)
	local taggedCount = 0
	local matchedCount = 0

	for _, descendant in ipairs(rootInstance:GetDescendants()) do
		if pointNameSet[descendant.Name] then
			matchedCount += 1

			if descendant:IsA("Attachment") or descendant:IsA("Bone") then
				if not CollectionService:HasTag(descendant, DAMAGE_POINT_TAG) then
					CollectionService:AddTag(descendant, DAMAGE_POINT_TAG)
					taggedCount += 1
				end
			else
				warn(
					"[HitboxService] Hit point '"
						.. descendant:GetFullName()
						.. "' is named correctly but must be an Attachment or Bone for ShapecastHitbox."
				)
			end
		end
	end

	return matchedCount, taggedCount
end

-- Adds filter instances to RaycastParams while preserving existing exclusions.
-- raycastParams: RaycastParams to mutate for this hitbox
-- filterInstances: array of Instances that should be ignored by casts
local function appendFilterInstances(raycastParams, filterInstances)
	local existing = raycastParams.FilterDescendantsInstances

	for _, instance in ipairs(filterInstances or {}) do
		table.insert(existing, instance)
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = existing
end

-- Creates RaycastParams for ShapecastHitbox and excludes the attacker root.
-- rootInstance: character/model whose own descendants should be ignored
-- options: optional table with raycastParams and filterDescendants fields
local function buildRaycastParams(rootInstance, options)
	local raycastParams = (options and options.raycastParams) or RaycastParams.new()
	local filterInstances = { rootInstance }

	for _, instance in ipairs((options and options.filterDescendants) or {}) do
		table.insert(filterInstances, instance)
	end

	appendFilterInstances(raycastParams, filterInstances)
	return raycastParams
end

-- Removes every discovered segment that is not listed for this hitbox.
-- hitbox: ShapecastHitbox instance returned by the package
-- pointNameSet: map of allowed hit point names
local function keepExplicitSegments(hitbox, pointNameSet)
	local foundPointNames = {}
	local keptCount = 0
	local removedCount = 0

	for segmentInstance in pairs(hitbox:GetAllSegments()) do
		local shouldKeep = pointNameSet[segmentInstance.Name] == true

		if shouldKeep then
			foundPointNames[segmentInstance.Name] = true
			keptCount += 1
		else
			hitbox:RemoveSegment(segmentInstance)
			removedCount += 1
		end
	end

	return foundPointNames, keptCount, removedCount
end

-- Warns when requested hit point names were not found under the hitbox root.
-- hitboxId: caller-provided cache key for this hitbox
-- pointNames: requested hit point names
-- foundPointNames: map of names discovered by ShapecastHitbox
local function warnMissingPoints(hitboxId, pointNames, foundPointNames)
	for _, pointName in ipairs(pointNames or {}) do
		if not foundPointNames[pointName] then
			warn("[HitboxService] Hitbox '" .. tostring(hitboxId) .. "' could not find hit point '" .. tostring(pointName) .. "'.")
		end
	end
end

-- Joins requested hit point names for readable debug output.
-- pointNames: array of unique hit point names
local function formatPointNames(pointNames)
	return table.concat(pointNames or {}, ", ")
end

-- Applies the service's default Blockcast settings to a ShapecastHitbox.
-- hitbox: ShapecastHitbox instance returned by the package
-- options: optional table with resolution, castSize, castCFrame, and filterPartsHit fields
local function configureHitbox(hitbox, options)
	hitbox:SetResolution((options and options.resolution) or DEFAULT_RESOLUTION)
	hitbox:SetCastData({
		CastType = ShapecastHitbox.CastTypes.Blockcast,
		Size = (options and options.castSize) or DEFAULT_CAST_SIZE,
		CFrame = (options and options.castCFrame) or DEFAULT_CAST_CFRAME,
		Radius = 0,
	})
	hitbox.FilterPartsHit = not (options and options.filterPartsHit == false)
end

-- Returns the cached record for a hitbox id, warning when it is missing.
-- hitboxId: caller-provided cache key for this hitbox
local function getRecord(hitboxId)
	local record = hitboxesById[hitboxId]

	if not record then
		warn("[HitboxService] Unknown hitbox id '" .. tostring(hitboxId) .. "'.")
	end

	return record
end

-- Builds the callback payload returned by HitboxService.StartHitbox.
-- raycastResult: RaycastResult returned by ShapecastHitbox's cast operation
-- segment: ShapecastHitbox segment that produced the hit
local function buildHitPayload(raycastResult, segment)
	return {
		result = raycastResult,
		segment = segment,
		hitInstance = raycastResult.Instance,
		hitPosition = raycastResult.Position,
		hitPointName = segment and segment.Instance and segment.Instance.Name or nil,
	}
end

-- Returns the world CFrame for a hit point segment.
-- segment: ShapecastHitbox segment whose Instance is usually an Attachment
local function getSegmentWorldCFrame(segment)
	if segment.Instance:IsA("Attachment") then
		return segment.Instance.WorldCFrame
	end

	if segment.Instance:IsA("Bone") then
		return segment.Instance.TransformedWorldCFrame
	end

	if segment.Instance:IsA("BasePart") then
		return segment.Instance.CFrame
	end

	return CFrame.new(segment.Position or Vector3.zero)
end

-- Returns whether this hitbox should show active debug parts.
-- options: optional CreateHitbox options table with debugVisualize override
local function shouldDebugVisualize(options)
	if not DEBUG_MODE then
		return false
	end

	if options and options.debugVisualize ~= nil then
		return options.debugVisualize == true
	end

	return true
end

-- Returns the exact world CFrame used for the visible Blockcast region.
-- segment: ShapecastHitbox segment with CastData configured by this service
local function getDebugVisualCFrame(segment)
	return getSegmentWorldCFrame(segment) * segment.CastData.CFrame
end

-- Returns the body BasePart that owns this hit point segment.
-- segment: ShapecastHitbox segment whose Instance may be parented under a limb
local function getSegmentBodyPart(segment)
	local instance = segment.Instance

	while instance do
		if instance:IsA("BasePart") then
			return instance
		end

		instance = instance.Parent
	end

	return nil
end

-- Restores any body part transparency changed for active debug visuals.
-- record: cached hitbox record with originalBodyPartTransparency values
local function restoreDebugBodyParts(record)
	for bodyPart, originalTransparency in pairs(record.originalBodyPartTransparency or {}) do
		if bodyPart.Parent then
			bodyPart.Transparency = originalTransparency
		end
	end

	record.originalBodyPartTransparency = {}
end

-- Makes hit point body parts transparent so debug visual blocks are visible.
-- record: cached hitbox record whose segments map onto character body parts
local function applyDebugBodyPartTransparency(record)
	if not DEBUG_MODE then return end

	for _, segment in pairs(record.hitbox:GetAllSegments()) do
		local bodyPart = getSegmentBodyPart(segment)

		if bodyPart and record.originalBodyPartTransparency[bodyPart] == nil then
			record.originalBodyPartTransparency[bodyPart] = bodyPart.Transparency
			bodyPart.Transparency = math.max(bodyPart.Transparency, DEBUG_BODY_PART_TRANSPARENCY)
		end
	end
end

-- Destroys all active debug visualization parts for a record.
-- record: cached hitbox record that may own debug parts and a connection
local function destroyDebugVisuals(record)
	if record.debugConnection then
		record.debugConnection:Disconnect()
		record.debugConnection = nil
	end

	for _, entry in ipairs(record.debugParts or {}) do
		entry.part:Destroy()
	end

	record.debugParts = {}
	restoreDebugBodyParts(record)
end

-- Updates debug Blockcast parts so they follow their authored hit points.
-- record: cached hitbox record with debug part entries
local function updateDebugVisuals(record)
	for _, entry in ipairs(record.debugParts or {}) do
		if entry.segment.Instance.Parent then
			local castData = entry.segment.CastData
			entry.part.Size = castData.Size
			entry.part.CFrame = getDebugVisualCFrame(entry.segment)
		end
	end
end

-- Creates temporary server-visible Blockcast debug parts for this active hitbox.
-- record: cached hitbox record whose options enable debug visualization
local function createDebugVisuals(record)
	if not shouldDebugVisualize(record.options) then return end

	destroyDebugVisuals(record)
	applyDebugBodyPartTransparency(record)

	local transparency = record.options.debugVisualTransparency
	if transparency == nil then
		transparency = DEFAULT_DEBUG_VISUAL_TRANSPARENCY
	end

	for _, segment in pairs(record.hitbox:GetAllSegments()) do
		local castData = segment.CastData
		local part = Instance.new("Part")

		part.Name = "HitboxDebug_" .. tostring(segment.Instance.Name)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.ForceField
		part.Color = record.options.debugVisualColor or DEFAULT_DEBUG_VISUAL_COLOR
		part.Transparency = transparency
		part.Size = castData.Size
		part.CFrame = getDebugVisualCFrame(segment)
		part.Parent = workspace

		table.insert(record.debugParts, {
			part = part,
			segment = segment,
		})
	end

	debugPrint("Created " .. tostring(#record.debugParts) .. " debug visual part(s) for " .. tostring(record.hitboxId) .. ".")

	record.debugConnection = RunService.Heartbeat:Connect(function()
		updateDebugVisuals(record)
	end)
end

-- Creates and caches a Blockcast-backed hitbox for explicit authored hit points.
-- hitboxId: unique string key for future start/stop/destroy calls
-- rootInstance: Instance whose descendants include tagged DmgPoint attachments
-- pointNames: array of unique DmgPoint attachment names to keep active
-- options: optional table for raycastParams, filterDescendants, resolution, castSize, castCFrame, filterPartsHit, debugVisualize, debugVisualColor, debugVisualTransparency
function HitboxService.CreateHitbox(hitboxId, rootInstance, pointNames, options)
	assert(hitboxId ~= nil, "HitboxService.CreateHitbox requires hitboxId")
	assert(rootInstance ~= nil, "HitboxService.CreateHitbox requires rootInstance")

	-- TODO: Add generic anti-exploit bounds before attack wiring calls this with live data.
	-- Keep these wrapper-level checks limited to cast safety: server-owned pointNames,
	-- capped castSize, capped resolution, capped duration, and valid root ownership.
	if hitboxesById[hitboxId] then
		HitboxService.DestroyHitbox(hitboxId)
	end

	debugPrint(
		"CreateHitbox "
			.. tostring(hitboxId)
			.. " root="
			.. rootInstance:GetFullName()
			.. " points=["
			.. formatPointNames(pointNames)
			.. "]"
	)

	local raycastParams = buildRaycastParams(rootInstance, options)
	local pointNameSet = buildPointNameSet(pointNames)
	local matchedCount, taggedCount = tagRequestedHitPoints(rootInstance, pointNameSet)

	debugPrint(
		"CreateHitbox "
			.. tostring(hitboxId)
			.. " matched "
			.. tostring(matchedCount)
			.. " requested descendant(s), tagged "
			.. tostring(taggedCount)
			.. "."
	)

	local hitbox = ShapecastHitbox.new(rootInstance, raycastParams)

	configureHitbox(hitbox, options)

	local foundPointNames, keptCount, removedCount = keepExplicitSegments(hitbox, pointNameSet)
	debugPrint(
		"CreateHitbox "
			.. tostring(hitboxId)
			.. " kept "
			.. tostring(keptCount)
			.. " segment(s), removed "
			.. tostring(removedCount)
			.. "."
	)
	warnMissingPoints(hitboxId, pointNames, foundPointNames)

	hitboxesById[hitboxId] = {
		hitboxId = hitboxId,
		hitbox = hitbox,
		rootInstance = rootInstance,
		pointNames = table.clone(pointNames or {}),
		options = options or {},
		debugParts = {},
		debugConnection = nil,
		originalBodyPartTransparency = {},
	}

	return hitbox
end

-- Starts a cached hitbox and calls onHit with a normalized hit payload.
-- hitboxId: unique string key passed to CreateHitbox
-- duration: optional seconds before the hitbox automatically stops
-- onHit: optional callback receiving the normalized hit payload
function HitboxService.StartHitbox(hitboxId, duration, onHit)
	local record = getRecord(hitboxId)
	if not record then return end

	-- TODO: Clamp duration to the active window declared by server attack data.
	-- Clients should request attacks only; they should never choose hitbox timing.
	if record.hitbox.Active then
		record.hitbox:HitStop()
	end

	createDebugVisuals(record)
	debugPrint("StartHitbox " .. tostring(hitboxId) .. " duration=" .. tostring(duration) .. ".")

	if onHit then
		record.hitbox:OnHit(function(raycastResult, segment)
			-- TODO: Combat resolution should validate the hit before damage/stun:
			-- same match, target is opponent, target is alive, attacker is in range,
			-- attacker is facing target when required, and target was not already hit
			-- during this active window.
			onHit(buildHitPayload(raycastResult, segment))
		end)
	end

	record.hitbox:OnStopped(function(cleanCallbacks)
		destroyDebugVisuals(record)
		cleanCallbacks()
	end)

	record.hitbox:HitStart(duration)
end

-- Stops a cached hitbox if it is currently active.
-- hitboxId: unique string key passed to CreateHitbox
function HitboxService.StopHitbox(hitboxId)
	local record = getRecord(hitboxId)
	if not record then return end

	record.hitbox:HitStop()
	destroyDebugVisuals(record)
	debugPrint("StopHitbox " .. tostring(hitboxId) .. ".")
end

-- Destroys a cached hitbox and removes its service record.
-- hitboxId: unique string key passed to CreateHitbox
function HitboxService.DestroyHitbox(hitboxId)
	local record = hitboxesById[hitboxId]
	if not record then return end

	destroyDebugVisuals(record)
	record.hitbox:Destroy()
	hitboxesById[hitboxId] = nil
	debugPrint("DestroyHitbox " .. tostring(hitboxId) .. ".")
end

-- Re-scans a cached hitbox's root and keeps only the requested explicit points.
-- hitboxId: unique string key passed to CreateHitbox
-- pointNames: optional replacement array of unique DmgPoint attachment names
function HitboxService.ReconcileHitbox(hitboxId, pointNames)
	local record = getRecord(hitboxId)
	if not record then return end

	if pointNames then
		record.pointNames = table.clone(pointNames)
	end

	local pointNameSet = buildPointNameSet(record.pointNames)
	local matchedCount, taggedCount = tagRequestedHitPoints(record.rootInstance, pointNameSet)
	debugPrint(
		"ReconcileHitbox "
			.. tostring(hitboxId)
			.. " matched "
			.. tostring(matchedCount)
			.. " requested descendant(s), tagged "
			.. tostring(taggedCount)
			.. "."
	)
	record.hitbox:Reconcile()

	local foundPointNames, keptCount, removedCount = keepExplicitSegments(record.hitbox, pointNameSet)
	debugPrint(
		"ReconcileHitbox "
			.. tostring(hitboxId)
			.. " kept "
			.. tostring(keptCount)
			.. " segment(s), removed "
			.. tostring(removedCount)
			.. "."
	)
	warnMissingPoints(hitboxId, record.pointNames, foundPointNames)
end

-- Destroys every cached hitbox tied to the provided root instance.
-- rootInstance: character/model used when creating hitboxes
function HitboxService.DestroyCharacterHitboxes(rootInstance)
	local idsToDestroy = {}

	for hitboxId, record in pairs(hitboxesById) do
		if record.rootInstance == rootInstance then
			table.insert(idsToDestroy, hitboxId)
		end
	end

	for _, hitboxId in ipairs(idsToDestroy) do
		HitboxService.DestroyHitbox(hitboxId)
	end
end

-- Initializes service dependencies; HitboxService currently has none.
function HitboxService.Init() end

-- Starts service behavior; HitboxService currently waits for callers.
function HitboxService.Start() end

-- TODO: Put request-level anti-exploit checks in the future server CombatService:
-- rate limit attack remotes, verify attacker state, enforce recovery/cooldowns,
-- validate combo routes, and reject attacks outside the active match/arena.

return HitboxService
