-- Owns local player animation loading and playback. Other client modules call
-- this service instead of touching Humanoid, Animator, or AnimationTrack objects.
--
-- Public API:
-- AnimationService.Load(name, animationId?) -> AnimationTrack?
-- AnimationService.Preload(name, animationId?) -> AnimationTrack?
-- AnimationService.Play(name, fadeTime?, animationId?) -> AnimationTrack?
-- AnimationService.Stop(name, fadeTime?)
-- AnimationService.StopAll(fadeTime?)
-- AnimationService.IsPlaying(name) -> boolean
-- AnimationService.OnReady(callback)

local AnimationService = {}

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_FADE_TIME = 0.1
local DEFAULT_ANIMATIONS = {}
local DEBUG_PREFIX = "[AnimationDebug]"

local _tracks = {}
local _loaded = {}
local _humanoid = nil
local _animator = nil
local _animationsFolder = nil
local _isReady = false
local _readyCallbacks = {}

-- Prints a standard local animation debug message.
-- message: string to send to Studio Output
local function debugPrint(message)
	print(DEBUG_PREFIX .. " " .. Players.LocalPlayer.Name .. ": " .. message)
end

-- Loads an Animation asset into the current Animator.
-- name: string key for the cached track
-- animation: Animation instance to load
local function loadTrack(name, animation)
	if not _animator or not animation then return nil end

	local track = _animator:LoadAnimation(animation)
	_tracks[name] = track

	return track
end

-- Fetches or creates the Animation asset for a name and optional id.
-- name: animation asset name under ReplicatedStorage.Assets.Animations
-- animationId: optional rbxassetid string used when no asset exists in the folder
local function getAnimation(name, animationId)
	local animation = _loaded[name]

	if not animation then
		animation = _animationsFolder and _animationsFolder:FindFirstChild(name)

		if animation and not animation:IsA("Animation") then
			warn("[AnimationService] " .. name .. " is not an Animation")
			return nil
		end

		if not animation and animationId then
			animation = Instance.new("Animation")
			animation.Name = name
			animation.AnimationId = animationId
		end

		if not animation then
			warn("[AnimationService] Missing animation: " .. name)
			return nil
		end

		_loaded[name] = animation
	end

	return animation
end

-- Rebuilds AnimationTrack objects from cached Animation assets after respawn.
local function reloadTracks()
	_tracks = {}

	for name, animation in pairs(_loaded) do
		loadTrack(name, animation)
	end
end

-- Notifies registered consumers that the current character Animator can load tracks.
-- character: Player character model whose Animator is ready
local function notifyReady(character)
	_isReady = true
	debugPrint("Animator ready for " .. character:GetFullName() .. "; callbacks=" .. tostring(#_readyCallbacks))

	for _, callback in ipairs(_readyCallbacks) do
		-- Runs one consumer callback with the ready character.
		-- character: Player character model whose Animator is ready
		local didRun, callbackError = pcall(callback, character)
		if not didRun then
			warn("[AnimationService] Ready callback failed: " .. tostring(callbackError))
		end
	end
end

-- Caches the new character's animation refs and rebuilds tracks.
-- character: Player character model containing Humanoid and Animator
local function onCharacterAdded(character)
	_isReady = false
	debugPrint("Character added; waiting for Humanoid and Animator. Character=" .. character:GetFullName())

	_humanoid = character:WaitForChild("Humanoid")
	_animator = _humanoid:WaitForChild("Animator")

	reloadTracks()
	notifyReady(character)
end

-- Fetches and loads an animation by name, with an optional fallback id.
-- name: animation asset name under ReplicatedStorage.Assets.Animations
-- animationId: optional rbxassetid string used when no asset exists in the folder
function AnimationService.Load(name, animationId)
	if _tracks[name] then return _tracks[name] end

	local animation = getAnimation(name, animationId)
	return loadTrack(name, animation)
end

-- Preloads and caches an animation before it is played by the state machine.
-- name: animation asset name under ReplicatedStorage.Assets.Animations
-- animationId: optional rbxassetid string used when no asset exists in the folder
function AnimationService.Preload(name, animationId)
	local animation = getAnimation(name, animationId)
	if not animation then return nil end

	debugPrint("Preloading animation " .. name .. ".")
	-- Runs the blocking Roblox preload call safely for this animation asset.
	-- No parameters are passed into the protected callback.
	local didPreload, preloadError = pcall(function()
		ContentProvider:PreloadAsync({ animation })
	end)
	if not didPreload then
		warn("[AnimationService] Failed to preload " .. name .. ": " .. tostring(preloadError))
	else
		debugPrint("Finished preloading animation " .. name .. ".")
	end

	if _tracks[name] then return _tracks[name] end

	return loadTrack(name, animation)
end

-- Plays a named animation track, loading it first if needed.
-- name: cached or asset-backed animation name
-- fadeTime: optional blend duration in seconds
-- animationId: optional rbxassetid string used when no asset exists in the folder
function AnimationService.Play(name, fadeTime, animationId)
	local track = _tracks[name] or AnimationService.Load(name, animationId)
	if not track then return nil end

	track:Play(fadeTime or DEFAULT_FADE_TIME)

	return track
end

-- Stops one named animation track when it exists and is playing.
-- name: cached animation name
-- fadeTime: optional blend duration in seconds
function AnimationService.Stop(name, fadeTime)
	local track = _tracks[name]
	if not track or not track.IsPlaying then return end

	track:Stop(fadeTime or DEFAULT_FADE_TIME)
end

-- Stops every loaded animation track.
-- fadeTime: optional blend duration in seconds
function AnimationService.StopAll(fadeTime)
	for _, track in pairs(_tracks) do
		if track.IsPlaying then
			track:Stop(fadeTime or DEFAULT_FADE_TIME)
		end
	end
end

-- Reports whether a named animation track is currently playing.
-- name: cached animation name
function AnimationService.IsPlaying(name)
	local track = _tracks[name]

	return track ~= nil and track.IsPlaying
end

-- Registers a callback to run whenever the local character Animator is ready.
-- callback: function called with the current character model
function AnimationService.OnReady(callback)
	table.insert(_readyCallbacks, callback)

	if _isReady and Players.LocalPlayer.Character then
		-- Runs the newly registered callback immediately when the Animator is already ready.
		-- Players.LocalPlayer.Character: current character model passed to the callback
		local didRun, callbackError = pcall(callback, Players.LocalPlayer.Character)
		if not didRun then
			warn("[AnimationService] Ready callback failed: " .. tostring(callbackError))
		end
	end
end

-- Initializes service dependencies; no _G dependencies are needed currently.
function AnimationService.Init() end

-- Caches animation assets and character animation refs for the local player.
function AnimationService.Start()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	_animationsFolder = assets:WaitForChild("Animations")

	local localPlayer = Players.LocalPlayer
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	else
		onCharacterAdded(localPlayer.CharacterAdded:Wait())
	end

	localPlayer.CharacterAdded:Connect(onCharacterAdded)

	for _, name in ipairs(DEFAULT_ANIMATIONS) do
		AnimationService.Load(name)
	end
end

return AnimationService
