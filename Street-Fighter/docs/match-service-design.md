# Match Service High-Level Design

The Match Service is the central orchestrator for all player-versus-player combat. It owns three distinct phases:

- Entry
- Fight
- Exit

At any given time, a match is in exactly one of these phases, and the service is responsible for transitioning between them cleanly.

## Phase 1: Entry (Challenge, Queue & Setup)

This is where players go from "wanting to fight" to "standing in the arena, ready to fight."

The service manages players waiting to be matched. When two compatible players are found, the service pulls them from the waiting state, assigns them to a match instance, and handles all the logistics of getting them into the arena:

- Spawning them at their respective starting positions
- Initializing their health
- Loading any character-specific data

Once everything is in place, the service signals that the match is ready to begin.

This is the phase being built first.

## Phase 2: Fight (Round Management)

This is the live match. The service hands control over to the combat system and takes a supervisory role. It listens for meaningful events rather than actively driving moment-to-moment combat:

- A fighter's health hitting zero
- A disconnect
- A timeout

When a round ends, the service decides what happens next:

- Start another round
- End the match

It tracks round wins per player and drives the best-of-N loop until a winner is determined.

## Phase 3: Exit (Teardown & Return)

Once a winner is decided, the service wraps up the match. This includes:

- Cleaning up the arena
- Recording the result, including who won and how
- Returning both players to wherever they came from, such as the lobby, a queue, or a results screen

The goal of this phase is to leave zero residual state behind. The match instance is fully discarded, and both players are cleanly handed back to the broader game.
