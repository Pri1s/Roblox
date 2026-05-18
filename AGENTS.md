# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Workspace Context

The actual Roblox project lives on the other side of the Roblox MCP bridge. This local directory contains only supporting artifacts such as markdown files, documentation, and related notes.

When working on the Roblox experience itself, inspect and modify the live project through the Roblox MCP bridge rather than assuming the game source exists in this local filesystem.

The engineer can run playtests and validate Roblox code directly. Agents do not need to perform playtesting or in-Studio validation unless explicitly asked.

## Core Workflow

Read `docs/workflow.md` before starting any task.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Define Success Before Starting

Before implementing, restate the goal as a verifiable outcome:

- "Add validation" → "Invalid inputs are rejected with an appropriate error"
- "Fix the bug" → "The described input no longer produces the described output"

If you can't define what done looks like, ask before writing code.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## Project Docs

Consult these only when relevant:

- `docs/roblox-project-setup.md` — scaffolding a new Roblox project from scratch.
  Read this when: working with a newly initialized game, setting up folder structure, or writing a loader/module system.
