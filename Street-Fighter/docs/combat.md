# Roblox Street Fighter — Combat System

> Living document | Subject to change

---

## Basic Attack Inputs (4 defaults)

| Input | Attack      | Hit Level   |
| ----- | ----------- | ----------- |
| 1     | Front Punch | High        |
| 2     | Back Punch  | High        |
| 3     | Front Kick  | Mid         |
| 4     | Back Kick   | Low (Sweep) |

> "Front" = lead limb (faster, less damage). "Back" = rear limb (slower, more damage).

---

## Directional Modifier Attacks

| Input     | Attack          | Hit Level | Hit Reaction |
| --------- | --------------- | --------- | ------------ |
| D+1       | Crouching Jab   | Mid       | Normal stun  |
| D+3 / D+4 | Crouching Kicks | Low       | Normal stun  |
| D+2       | Uppercut        | High      | Stagger      |
| B+4       | Sweep           | Low       | Knockdown    |

> Uppercut causes a **stagger** instead of a launch (airborne state faded) — opponent stumbles backward, stays grounded, but enters a longer stun window for the attacker to capitalize.

---

## Hit Levels

| Level    | Blocked By                  | Notes                                             |
| -------- | --------------------------- | ------------------------------------------------- |
| High     | Standing or crouching block | Whiffs on crouching opponents who aren't blocking |
| Mid      | Standing or crouching block | Cannot be evaded by crouching                     |
| Low      | Crouching block only        | Standing block does NOT stop low attacks          |
| Overhead | Standing block only         | Crouching block does NOT stop overheads           |

---

## Hit Reactions

### Stagger

Triggered by **Uppercut**. Opponent stumbles backward but stays grounded.

- Longer stun than a normal hit — attacker has a window to follow up
- Opponent recovers into neutral standing position
- No special wake-up options — just a grounded stun

### Knockdown

Triggered by **Sweep**. Opponent is fully on the ground and must get up.

- Attacker has a brief window to close distance or set up pressure before opponent rises
- Downed player can use a **wake-up attack** — an armored strike on get-up to deter continued pressure
- If wake-up attack is not used, opponent simply stands up neutral

### Pushback

Triggered by **strong combos / max combos**. Opponent is still standing but displaced backward.

- Opponent enters a brief stun — not long enough to combo off of, but enough for the attacker to make a decision: **chase or reset neutral**
- Opponent recovers into neutral standing position with no special options
- The distance created naturally ends pressure loops — prevents infinite combos

---

## Combo System

- Combos are **dialed inputs** — buttons entered in quick succession
- Each basic attack can branch into a string with additional inputs
- **Backward modifier attacks** unlock more advanced combo branches — where VFX and moveset abilities come into play

### Combo Rules

| Scenario                    | What Happens                                                                                                                                                                  |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inputs fail (too slow)      | Animation plays up to last successful input, then stops                                                                                                                       |
| Full combo, opponent blocks | Full animation plays, opponent pushed back, attacker enters recovery — opponent gets punish window                                                                            |
| Full combo, miss entirely   | Full animation plays, attacker is fully locked — cannot cancel, block, or act. Opponent is under no obligation to wait and can immediately punish the moment the combo whiffs |

---

## Recovery System

- Every attack has a recovery window before the next input is valid (unless cancellable into a combo)
- **All recoveries under 1 second** to maintain fast pace
- Recovery scales with **severity and speed** of the attack — harder hits = longer recovery
- **Recovery style tied to moveset archetype** — reinforces playstyle identity
- Jabs: lowest recovery, lowest damage — spammable but punishable by a sharp opponent
- Goal: no attack should be spammable without consequence

---

## Blocking

| Block Type | Stops               | Does NOT Stop |
| ---------- | ------------------- | ------------- |
| Standing   | High, Mid, Overhead | Low           |
| Crouching  | High, Mid, Low      | Overhead      |

- Blocked attacks still deal minimum **chip damage** — small HP loss even on a successful block, preventing indefinite turtling
- Throws and unblockable moves bypass all blocking

### Block Types

| Type           | Condition                 | Result                                                                         |
| -------------- | ------------------------- | ------------------------------------------------------------------------------ |
| Normal Block   | Holding block             | Chip damage, slight pushback                                                   |
| Flawless Block | Block right before impact | No chip damage, maximum distance created between both players — resets neutral |

---

## Grab / Throw

- Cannot be blocked
- Primary tool to punish overly defensive opponents

---

## Defensive Mechanics

| Mechanic       | Description                                                                             |
| -------------- | --------------------------------------------------------------------------------------- |
| Flawless Block | Block right before impact — no chip damage, maximum distance reset between both players |
| Wake-up Attack | Armored strike on get-up after a knockdown — deters continued pressure                  |

---

## Round Reset

| Phase        | What Happens                                                                |
| ------------ | --------------------------------------------------------------------------- |
| KO           | Losing player plays KO animation — falls to knees                           |
| Taunt window | Winning player hits an emote / taunt; both HP bars reset during this window |
| Get-up       | Knocked player stands back up, both enter fighting stance                   |
| Countdown    | Quick countdown → next round begins                                         |

**Design notes:**

- Full finishing cutscenes are **reserved for the final round only** — when the match is actually won. Happening every round makes them feel less special.
- Round resets should be **quick** — this is a fast-paced game. No slow cinematic interruptions between rounds.
- The taunt is the win celebration, not a cutscene. Keep it snappy.
- Optional: brief camera pan to the kneeling player + taunting opponent, but avoid making it a full cutscene.

---

## Moveset Archetypes (Recovery tied to style)

| Archetype    | Recovery Style | Notes                                            |
| ------------ | -------------- | ------------------------------------------------ |
| Rushdown     | Short recovery | Fast pace, lower damage, high pressure           |
| Heavy Hitter | Long recovery  | High damage, punishes mistakes, rewards patience |
| TBD          | TBD            | Additional archetypes to be defined              |

---

## Balance Spreadsheet — Tracking Per Attack

- Attack name
- Damage
- Recovery time (ms)
- Hit level (High / Mid / Low / Overhead)
- Hit reaction (Normal / Stagger / Knockdown / Pushback)
- Cancellable into combo (Yes / No)

---

## Faded for Now

- Airborne / juggle state (uppercut uses stagger instead)
- Meter system (Enhanced Specials, Combo Breaker, Fatal Blow)
- Aerial combat / jump attacks
- Stage interactions / environmental hazards
- Finishing moves (Fatalities, Brutalities) — reserved for match-end only
- Cutscene-style transitions between rounds

---

_Update as decisions are finalized._

---

## Player Feedback

### Visual

- **Collision animations** — unique per attack type (punch, kick, special, etc.)
- **Hit VFX** — impact flash/spark scaled to hit severity (jab vs heavy hit feel distinct)
- **Hit stun animation** — receiver flinches or staggers based on hit type
- **Block VFX** — visually distinct from hit VFX so both players can read the block
- **Chip damage flicker** — subtle HP bar flash when a block takes chip damage
- **Flawless block** — no chip damage + maximum distance created between both players
- **HP bar drain** — weighted, not instant — slight delay/animation on bar drop adds impact feel

### Audio

- **Hit sounds** — layered SFX per attack type (punch vs kick vs special)
- **Block sounds** — distinct from hit sounds so players can hear the difference
- **Whoosh/swing sounds** — attack startup audio so players can react to incoming hits

### UI

- **HP bar** with weighted drain animation
- **Damage numbers** — optional, easy to implement, gives clear feedback on damage dealt

---
