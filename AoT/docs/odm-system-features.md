# ODM System Features

An exhaustive list of the aspects that contribute to smooth, dynamic, free ODM movement.

## Grappling Hooks

- Two independent hooks, left and right, fired separately
- Hooks travel through the air with visible speed rather than attaching instantly
- Hooks attach to any valid surface they touch
- Each hook can be released independently at any moment
- Re-fire a hook while one is already attached
- Re-fire a hook while one is mid-flight, overriding it
- Aim assist or snapping to nearby anchor points, or fully manual aim
- Visual indicator showing where hooks will land before firing
- Hook range limits and defined out-of-range behavior
- Hooks attach at the exact contact point or snap to the nearest valid spot

## Swinging & Physics

- Pendulum motion when hanging from one hook
- Dual-hook tension creating triangulated, more controlled arcs
- Gravity continuously pulls the player
- Cable length can be fixed at firing distance or dynamically retracting
- Cable acts as a rigid constraint and does not stretch past max length
- Momentum carries between swings and is never reset
- Centripetal acceleration at the bottom of swings
- Player body orientation follows swing direction and leans into turns
- Minimal air resistance or drag, just enough to feel grounded
- Terminal velocity cap so freefall remains controllable

## Retraction & Propulsion

- Active reel-in pulls the player toward the hook point
- Variable retraction speed, from slow drift to aggressive pull
- Reel-in works independently of swing direction
- Releasing during retraction preserves forward momentum
- Pulling toward two hooks simultaneously creates forward thrust between them

## Release & Launch

- Release timing determines launch trajectory
- Releasing at swing apex maximizes forward distance
- Releasing at the bottom of a swing maximizes forward speed with a low arc
- Releasing upward enables vertical launch
- Support both simultaneous and staggered dual-hook release
- Preserve speed on release with no momentum penalty

## Aerial Control

- Player input subtly influences trajectory mid-flight
- Body rotation and orientation can be player-controlled or auto-aligned to velocity
- Player can look around without changing flight direction
- Mid-air turning while hooked
- Mid-air turning while unhooked through freefall steering

## Chaining & Flow

- No cooldown between hook fires
- No input dead zones between actions
- Seamless transition from release to fire to attach to swing to release
- Momentum compounds across well-timed chains
- Speed decays when not actively chaining
- Animations are cancellable so new hooks can be fired mid-action

## Surface & Environment Interaction

- Landing on rooftops, branches, and ground does not erase all momentum
- Running along surfaces after landing
- Wall contact and pushing off
- Sliding along surfaces when grazing them
- Hooks work on vertical walls, undersides of overhangs, and slanted surfaces
- Hooks work on moving objects such as Titans or vehicles
- Hooks detach automatically if an anchor point is destroyed or moves out of range

## Camera

- Third-person camera follows the player without whipping around
- Camera lag and smoothing during fast direction changes
- Field of view widens at high speed to convey velocity
- Optional camera tilt or roll on banking turns
- Camera remains player-controlled rather than forcing cinematic angles
- Support either a stable horizon line or full six-degrees-of-freedom movement

## Visual & Audio Feedback

- Visible cables between the player and hook points
- Cable tension visualization for taut versus slack states
- Wind streaks or speed lines at high velocity
- Motion blur scaling with speed
- Gas vapor trails from the gear, even without fuel mechanics
- Hook impact effects such as sparks, debris, or dust
- Whoosh and wind audio scaling with speed
- Cable whip or whistle sounds
- Retraction mechanical sounds such as ratcheting or gas hiss
- Footstep and landing sounds with weight

## Input Mapping

- Left trigger and right trigger for left and right hooks, or left mouse and right mouse
- Separate inputs for firing and releasing hooks
- Auto-aim toggle versus fully manual reticle
- Sensitivity curves tuned for fast aerial aiming
- No conflicting button assignments during chains

## Freefall & Recovery

- Falling without hooks feels controllable rather than punishing
- Hooks can be fired during freefall to recover
- Air control during freefall
- Repeatable strong evasive dashes during freefall with a small debounce
- No fall damage, or extremely lenient fall damage, to encourage risk-taking

## Player Capabilities

- Jumping from a standstill or run to initiate flight
- Wall jumping when standing against a surface
- Crouching or sliding on landing to preserve momentum
- Sprinting on the ground transitions smoothly into hook fire

## Hook Behavior Edge Cases

- Defined behavior when both hooks attach to the same point
- Defined behavior when hooks attach to points behind the player
- Defined behavior when an anchor becomes invalid mid-swing
- Hooks may pass through thin geometry or catch on it, depending on design
- Maximum active cable count, whether strictly two or more for flair

## Tuning Knobs

These are not features by themselves, but they are critical to feel.

- Gravity strength
- Reel-in force
- Launch impulse multiplier on release
- Swing dampening and energy loss per swing
- Hook travel speed
- Maximum movement speed cap, or uncapped movement
- Player mass and inertia
- Turning responsiveness in air

## Animation

- Body convincingly reacts to forces, with trailing limbs and leaning
- Smooth blending between idle, hooked, swinging, falling, and landing states
- Procedural or IK reaching toward hook points
- No animation lock; animations never gate input
- Player silhouette remains readable from any angle
