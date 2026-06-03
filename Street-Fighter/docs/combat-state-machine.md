# Combat State Machine — Transition Reference

> Implementation spec for the Roblox Street Fighter combat system.
> Every arrow in the state diagram is documented below as a discrete transition.
> Read this top to bottom and you should be able to build the FSM without the diagram.

---

## States (the nodes)

These are every state a player can occupy. A player is always in exactly one.

| State                  | Group                 | Description                                                                     |
| ---------------------- | --------------------- | ------------------------------------------------------------------------------- |
| `Idle`                 | Neutral               | Default standing state. Free to act.                                            |
| `Walking`              | Neutral               | Moving forward or backward on the ground.                                       |
| `Crouching`            | Neutral               | Down direction held. Changes which attacks land / which blocks apply.           |
| `Grab`                 | Active                | Throw attempt. Unblockable, bypasses both block states.                         |
| `StandingBlock`        | Blocking              | Guard up while standing. Stops High, Mid, Overhead.                             |
| `CrouchBlock`          | Blocking              | Guard up while crouching. Stops High, Mid, Low.                                 |
| `FlawlessBlock`        | Blocking              | Block input landed in the pre-impact window. No chip, max distance.             |
| `Jab`                  | Attack                | Front Punch (input `1`). Low recovery, low damage.                              |
| `BackPunch`            | Attack                | Back Punch (input `2`). High recovery, high damage.                             |
| `Uppercut`             | Attack                | `D+2`. Produces a Stagger on the opponent.                                      |
| `Sweep`                | Attack                | `B+4`. Produces a Knockdown on the opponent.                                    |
| `ComboActive`          | Attack                | A dialed-input string is in progress.                                           |
| `ComboBlocked`         | Attack                | A full combo was blocked. Pushback applied, attacker owes a punish window.      |
| `Recovery`             | Active                | Post-attack lockout. Cannot act until it ends. Length scales with hit severity. |
| `NormalStun`           | Hit reaction          | Receiver flinched from a standard hit.                                          |
| `Stagger`              | Hit reaction          | Receiver of an Uppercut. Grounded, long stun.                                   |
| `Pushback`             | Hit reaction          | Receiver displaced by a max combo. Standing, brief stun.                        |
| `Knockdown` → `Downed` | Hit reaction → Downed | Receiver of a Sweep. Goes to ground.                                            |
| `Downed`               | Downed                | On the ground, in the process of getting up.                                    |
| `WakeUpAttack`         | Downed                | Optional armored strike performed on get-up.                                    |

> **Reading note for the two-sided states:** Attack states (`Jab`, `Uppercut`, etc.) describe the _attacker_. Hit reaction states (`NormalStun`, `Stagger`, `Pushback`, `Knockdown`/`Downed`) describe the _opponent_ receiving that attack. A single landed attack drives a transition on _both_ players' state machines simultaneously — the attacker into `Recovery`, the opponent into a reaction. Keep these as two independent FSM instances that message each other on hit resolution.

---

## Transitions (the arrows)

Each transition is listed as **From → To**, with the trigger that fires it and any condition that must hold. Solid arrows are immediate/active transitions; dashed arrows in the diagram are _self-resolving_ returns (the state ends on its own timer and routes the player back).

### 1. Neutral movement

| #   | From        | To          | Trigger                 | Condition / Notes            |
| --- | ----------- | ----------- | ----------------------- | ---------------------------- |
| 1   | `Idle`      | `Walking`   | Movement input pressed  | Forward or backward.         |
| 2   | `Walking`   | `Idle`      | Movement input released | Returns to neutral standing. |
| 3   | `Idle`      | `Crouching` | Down (`D`) held         | —                            |
| 4   | `Crouching` | `Idle`      | Down released           | —                            |
| 5   | `Idle`      | `Grab`      | Grab input              | Enters the throw attempt.    |

> Movement (1/2) is a bidirectional pair — model it as a single toggle driven by input state, not two separate edges.

### 2. Entering block

| #   | From                                              | To              | Trigger                            | Condition / Notes                                                                                        |
| --- | ------------------------------------------------- | --------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 6   | `Idle`                                            | `StandingBlock` | Block held                         | Standing guard.                                                                                          |
| 7   | `Idle`                                            | `FlawlessBlock` | Block pressed in pre-impact window | Timing-gated. If the precise window is missed, this resolves as `StandingBlock` instead.                 |
| 8   | `Crouching`                                       | `CrouchBlock`   | Block held while crouching         | Crouching guard.                                                                                         |
| 9   | `StandingBlock` / `CrouchBlock` / `FlawlessBlock` | `Idle`          | Block released                     | **Dashed** — the block state ends and returns to neutral. One return edge covers all three block states. |

> **On a successful block:** the blocker stays in the block state (or transitions to `Recovery`/neutral per the hit's pushback), takes chip damage on a normal block, and takes **no** chip on a `FlawlessBlock`. The block itself does not change which state the _blocker_ is in — only the released-block edge (9) does. The _attacker_ whose attack was blocked still proceeds into their own `Recovery`.

### 3. Initiating an attack

All four attacks fire from neutral. In the diagram these are the four purple arrows from `Idle` labeled "any attack input."

| #   | From   | To          | Trigger     | Condition / Notes |
| --- | ------ | ----------- | ----------- | ----------------- |
| 10  | `Idle` | `Jab`       | Input `1`   | Front Punch.      |
| 11  | `Idle` | `BackPunch` | Input `2`   | Back Punch.       |
| 12  | `Idle` | `Uppercut`  | Input `D+2` | —                 |
| 13  | `Idle` | `Sweep`     | Input `B+4` | —                 |

> Only `Jab`/`BackPunch`/`Uppercut`/`Sweep` are drawn for clarity; the other basic and directional attacks (Front Kick, Back Kick, Crouching Jab, Crouching Kicks) follow the **identical pattern** — `Idle` → `<Attack>` → `Recovery`, with their own hit level and reaction. Implement attack entry generically: one transition per attack definition, all sharing the same downstream `Recovery` edge.

### 4. Combo branching

| #   | From                  | To             | Trigger                                            | Condition / Notes                                                                                                                                           |
| --- | --------------------- | -------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 14  | `Jab` (or any attack) | `ComboActive`  | Next dialed input arrives **in time**              | **Dashed** — the follow-up input must land inside the combo window. If it doesn't, no transition: the current attack just proceeds to `Recovery` (edge 18). |
| 15  | `ComboActive`         | `Recovery`     | Combo ends (string completes or input chain stops) | Labeled "combo ends."                                                                                                                                       |
| 16  | `ComboActive`         | `ComboBlocked` | Full combo connects but opponent is blocking       | Attacker is committed; opponent gets pushback + a punish window.                                                                                            |
| 17  | `ComboBlocked`        | `Recovery`     | —                                                  | Attacker enters recovery and owes the opponent a punish window.                                                                                             |

> **Backward-modifier attacks unlock deeper combo branches.** Model `ComboActive` as a state that re-enters itself on each successful dialed input (extending the string) until either the string ends (15) or it's blocked (16). A failed/late input ends the chain at the last successful attack and falls through to `Recovery`.

### 5. Attack resolution → Recovery

Every attack and combo terminus funnels through `Recovery`. This is the central chokepoint.

| #   | From                                       | To         | Trigger                                     | Condition / Notes                                        |
| --- | ------------------------------------------ | ---------- | ------------------------------------------- | -------------------------------------------------------- |
| 18  | `Jab` / `BackPunch` / `Uppercut` / `Sweep` | `Recovery` | Attack animation reaches its recovery phase | One edge per attack; all converge on `Recovery`.         |
| 19  | `Recovery`                                 | `Idle`     | Recovery timer elapses                      | **Resolving** — "recovery ends." Player regains control. |

> **Recovery length scales with the attack's severity/speed** and with the **moveset archetype** (Rushdown = short, Heavy Hitter = long). All recoveries are **under 1 second**. During `Recovery` the player is locked: no cancel, no block, no act.
>
> **Full whiff:** if the attack misses entirely, the player is _fully_ locked for the whole recovery and the opponent may punish freely the instant the attack whiffs. This is not a separate state — it's `Recovery` with no hit registered. The "Full whiff → opponent punishes freely" callout in the diagram annotates edge 18/19, it is not its own node.

### 6. Landing a hit → opponent reaction

These edges fire on the **opponent's** state machine when an attack connects. The source in the diagram is the attacker's attack state (green/coral arrows labeled "opponent's state"); the _destination_ is a state on the receiving player.

| #   | Attacker state (source)                             | Opponent →             | Trigger                   | Condition / Notes                                                    |
| --- | --------------------------------------------------- | ---------------------- | ------------------------- | -------------------------------------------------------------------- |
| 20  | Standard hit (e.g. `Jab`, kicks, crouching attacks) | `NormalStun`           | Hit connects, unblocked   | Brief flinch.                                                        |
| 21  | `Uppercut`                                          | `Stagger`              | Hit connects, unblocked   | Grounded, long stun window for attacker.                             |
| 22  | Max combo terminus                                  | `Pushback`             | Combo connects, unblocked | Opponent stays standing but is displaced; brief stun, not comboable. |
| 23  | `Sweep`                                             | `Knockdown` → `Downed` | Hit connects, unblocked   | Opponent goes to the ground.                                         |

> The trigger for all four is "hit resolution on the opponent." The _reaction type_ is a property of the attack that landed (see the per-attack Hit Reaction column in the design doc), not a choice made at reaction time.

### 7. Hit reactions resolving back to neutral

| #   | From                                  | To     | Trigger            | Condition / Notes                                                                                                                |
| --- | ------------------------------------- | ------ | ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| 24  | `NormalStun` / `Stagger` / `Pushback` | `Idle` | Stun timer elapses | **Resolving** — "recover → idle." One shared return edge; these three all recover into neutral standing with no special options. |

> `Stagger` has a _longer_ timer than `NormalStun`; `Pushback` additionally applies displacement. All three differ only in duration and displacement — they share the same destination (`Idle`) and the same lack of special wake-up options.

### 8. Knockdown / wake-up

| #   | From           | To             | Trigger                            | Condition / Notes                                                                            |
| --- | -------------- | -------------- | ---------------------------------- | -------------------------------------------------------------------------------------------- |
| 25  | `Knockdown`    | `Downed`       | Player hits the ground             | The receiver is now getting up.                                                              |
| 26  | `Downed`       | `WakeUpAttack` | Wake-up attack input on get-up     | **Optional** — player's choice. Armored strike to deter pressure.                            |
| 27  | `Downed`       | `Idle`         | No wake-up input; get-up completes | **Resolving** — "stand up → idle." Player simply rises into neutral.                         |
| 28  | `WakeUpAttack` | `Recovery`     | Wake-up attack performed           | **Resolving** — the wake-up strike has its own recovery, then routes to `Recovery` → `Idle`. |

> **Wake-up is a fork at `Downed`:** either the player commits to `WakeUpAttack` (26, armored, then recovery) **or** the get-up timer completes and they stand neutral (27). The attacker has a brief pressure window during `Downed` before either fork resolves.

---

## Implementation summary

- **Central hub:** `Recovery`. Every offensive action (attacks, combo enders, blocked combos, wake-up attacks) drains into it, and it has exactly one exit: `Recovery → Idle` on timer.
- **Neutral hub:** `Idle`. Almost every resolving edge (block release, recovery end, stun recovery, stand-up) returns here. It is the only state attacks initiate from.
- **Two-player coupling:** a single landed hit fires two simultaneous transitions — attacker → `Recovery`, opponent → a reaction state. Build the hit-resolution event to dispatch to both FSM instances.
- **Timer-driven returns** (the dashed/resolving edges): 9, 19, 24, 27, 28. These need no input — they fire when their state's timer expires.
- **Input-gated entries:** 1, 3, 5, 6, 7, 8, 10–14, 26. These fire on player input (some, like 7 and 14, are additionally window-gated on timing).
- **Hit-gated reactions:** 20–23. These fire on the opponent's machine at hit resolution; the reaction type is fixed by the attack.

> **Scope note:** This machine reflects only confirmed features. Airborne/juggle, meter (enhanced specials, combo breaker, fatal blow), aerial combat, and stage interactions are faded — there are deliberately no states or edges for them. When the meter system lands, expect new edges off `ComboActive` (enhanced special) and an interrupt edge from any reaction state back toward neutral (combo breaker).
