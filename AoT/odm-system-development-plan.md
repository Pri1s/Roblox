# ODM System Development Plan

This plan breaks ODM development into staged chunks so the system can be built from the movement foundation upward, with each stage producing something testable before adding more complexity.

## Stage 1 — Grounded Physics

**Goal:** Make freefall feel good before introducing hooks.

### Build

- Gravity strength
- Basic air control during freefall
- Controllable falling without hooks

### Done When

- The player can jump, fall, steer slightly in the air, and land in a way that feels stable and predictable.
- Falling feels controllable rather than frustrating.
- Movement already has a satisfying sense of weight before any ODM mechanics are added.

## Stage 2 — Basic Hook Attachment

**Goal:** Fire one hook, attach to a surface, and swing as a pendulum.

### Build

- One functional hook
- Visible hook travel speed rather than instant attachment
- Attachment to valid surfaces
- Hook range limits
- Exact contact-point attachment or chosen snapping behavior
- Single-hook cable constraint
- Pendulum motion under gravity
- Independent hook release

### Intentionally Excluded For Now

- Retraction
- Dual hooks
- Chaining
- Advanced aim assist

### Done When

- The player can fire one hook, attach to a valid surface, hang from it, swing naturally, and release cleanly.
- The swing preserves momentum instead of resetting movement.

## Stage 3 — Dual Hooks & Swinging

**Goal:** Add the core ODM identity: independent left and right hooks with controlled dual-hook movement.

### Build

- Two independent hooks, left and right
- Separate fire and release behavior for each hook
- Re-firing a hook while attached
- Re-firing a hook while mid-flight
- Dual-hook tension and triangulated movement arcs
- Momentum carry across releases
- Behavior for both hooks attaching to the same point
- Behavior for hooks attaching behind the player

### Done When

- The player can use either hook independently or both together.
- Dual-hook movement feels meaningfully different from one-hook swinging: tighter, more controlled, and capable of shaping arcs.
- Releasing one or both hooks does not destroy accumulated momentum.

## Stage 4 — Retraction & Launch

**Goal:** Turn swinging into active traversal by adding pull, thrust, and expressive release timing.

### Build

- Active reel-in toward hook points
- Variable retraction speed
- Reel-in while moving perpendicular to the hook direction
- Dual-hook pull creating forward thrust between anchors
- Release timing affecting launch trajectory
- Apex release for distance
- Bottom-of-swing release for speed
- Upward release for vertical launch
- Simultaneous versus staggered dual-hook release
- Speed preservation on release

### Done When

- The player can intentionally gain speed and shape launches through hook placement, retraction, and release timing.
- Different release timings produce visibly different outcomes.
- ODM starts to feel like a skill-based traversal system rather than a rope swing.

## Stage 5 — Flow & Chaining

**Goal:** Make repeated ODM actions feel seamless, fast, and expressive.

### Build

- No cooldown between hook fires
- No dead zones between actions
- Seamless release → fire → attach → swing → release loop
- Momentum compounding across well-timed chains
- Speed decay when not actively chaining
- Cancellable animations
- Fast aerial aiming support
- Input mapping that avoids conflicts during chains

### Done When

- Skilled play naturally produces faster, smoother movement than hesitant play.
- The player can continuously chain hooks without the controls fighting them.
- There are no obvious pauses, lockouts, or animation gates interrupting traversal.

## Stage 6 — Environment & Edge Cases

**Goal:** Make the ODM system hold up in a real level instead of only in ideal test conditions.

### Build

- Landing on rooftops, branches, and ground without losing all momentum
- Running along surfaces after landing
- Wall contact and wall push-off
- Sliding along surfaces when grazing them
- Hooking vertical walls, slanted surfaces, and undersides of overhangs
- Hooking moving objects such as Titans or vehicles
- Automatic detachment when an anchor is destroyed or moves out of range
- Handling invalid anchors mid-swing
- Decision on thin geometry behavior
- Aim assist and snapping tuning
- Visual pre-fire indicator for intended hook landing point

### Done When

- The system behaves predictably across common real-world surfaces and traversal situations.
- Edge cases are defined instead of producing broken or surprising movement.
- Hook targeting is reliable enough that failures feel like player mistakes, not system mistakes.

## Stage 7 — Feel & Polish

**Goal:** Dial in sensation, readability, and presentation after the mechanics are stable.

### Build

- Third-person camera follow behavior
- Camera smoothing during fast direction changes
- High-speed FOV widening
- Optional banking tilt or roll
- Final choice between stable horizon and full 6DOF freedom
- Visible cables and tension states
- Wind streaks, speed lines, motion blur, and gas trails
- Hook impact effects
- Wind, cable, retraction, footstep, and landing audio
- Body lean and force-reactive animation
- Smooth blends between idle, hooked, swinging, falling, and landing
- Procedural or IK reaching toward hook points
- Final tuning of:
  - gravity strength
  - reel-in force
  - launch impulse
  - swing dampening
  - hook travel speed
  - movement speed cap
  - player inertia
  - aerial turning responsiveness

### Done When

- The system is not only functional, but feels fast, readable, and satisfying.
- Camera, sound, animation, and effects reinforce movement instead of masking mechanical problems.
- Final tuning supports the intended fantasy of smooth, dynamic, free ODM traversal.

## Development Order Summary

| Stage | Focus                    | Outcome                                                |
| ----- | ------------------------ | ------------------------------------------------------ |
| 1     | Grounded physics         | Freefall feels right                                   |
| 2     | Basic hook attachment    | One-hook pendulum movement works                       |
| 3     | Dual hooks & swinging    | Core ODM movement exists                               |
| 4     | Retraction & launch      | Player can actively generate traversal speed           |
| 5     | Flow & chaining          | Movement becomes seamless and expressive               |
| 6     | Environment & edge cases | System survives real gameplay conditions               |
| 7     | Feel & polish            | The mechanic becomes satisfying and presentation-ready |

## Recommended Rule for Progression

Do not advance to the next stage until the current stage is fun in isolation. If freefall feels bad, hooks will only hide it. If one-hook swinging feels bad, dual hooks will multiply the problem. If chaining feels bad, polish will only decorate the weakness.
