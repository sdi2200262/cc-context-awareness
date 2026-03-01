# apm-handoff

Automatic Handoff triggers for [APM](https://github.com/sdi2200262/agentic-project-management) (Agentic Project Management) agents, powered by [cc-context-awareness](https://github.com/sdi2200262/cc-context-awareness). Agents never silently hit the context wall - they automatically initiate a Handoff before context runs out.

> **Note:** This template is built for APM v1.0.0-dev. APM is under active development - refer to the [APM repository](https://github.com/sdi2200262/agentic-project-management) for the latest version and any breaking changes.

## What It Does

Two components work together to make Handoffs automatic:

**Outgoing side** - when context usage hits a configurable threshold (default 70%), cc-context-awareness injects an instruction that tells the agent to stop and perform its Handoff procedure:

```
70% context → Manager: stop, read and execute /apm-6-handoff-manager
            → Worker:  stop, read and execute /apm-7-handoff-worker
            → Planner: warn User, be concise in chat, preserve document quality
```

After completing the Handoff procedure, the agent pauses and directs the User to exit and start a new session with the appropriate initiation command.

**Incoming side** - a SessionStart hook scans the APM Handoff Bus for pending handoff prompts and injects a signal into the new session's context. The incoming agent knows it's replacing an outgoing agent before it processes any commands.

The Planner does not support Handoff (single session by design). Instead, it is told to inform the User about context pressure and minimize chat verbosity while maintaining full quality in all planning documents - Specifications, Implementation Plan, and Execution Standards.

## How It Works

**Threshold trigger** - cc-context-awareness monitors context usage via a statusLine bridge and evaluates thresholds when hooks fire. This template adds a single threshold that fires at 70%. The agent self-identifies its type and follows the matching instruction - Manager reads `/apm-6-handoff-manager`, Worker reads `/apm-7-handoff-worker`.

**Handoff detection hook** - a `SessionStart` hook runs when any new session begins. It checks `.apm/bus/` for non-empty `apm-handoff.md` files. If found, it injects an `additionalContext` signal listing which agents have pending Handoffs. The agent's initiation command then handles the full Handoff processing - the hook is a deterministic safety net, not a replacement for APM's own detection.

The template does not perform the Handoff itself - APM's own Handoff commands ([`/apm-6-handoff-manager`](https://github.com/sdi2200262/agentic-project-management), [`/apm-7-handoff-worker`](https://github.com/sdi2200262/agentic-project-management)) handle the full procedure including Handoff Memory Log creation, Handoff Bus writing, and User review.

## Requirements

- [cc-context-awareness](https://github.com/sdi2200262/cc-context-awareness) (installed automatically)
- [APM](https://github.com/sdi2200262/agentic-project-management) v1.0.0-dev installed in your workspace
- [`jq`](https://jqlang.github.io/jq/download/) (runtime dependency)
- [Node.js](https://nodejs.org/) >= 18 (for `npx`)

## Install

```bash
npx cc-context-awareness install apm-handoff
npx cc-context-awareness install apm-handoff --global  # global
```

The base system is installed automatically if not already present. Restart Claude Code after installing.

### Install Options

| Flag | Effect |
|------|--------|
| `--global` | Install globally to `~/.claude/` instead of locally to `./.claude/` |
| `--no-claude-md` | Skip appending Handoff instructions to `CLAUDE.md` |

## What Gets Installed

**Threshold** added to cc-context-awareness `config.json`:

| Percent | Level | Action |
|---------|-------|--------|
| 70% | `apm-handoff` | Agent stops and initiates its type-appropriate Handoff procedure |

**Hook** installed and registered in `settings.json`:

| Hook | Event | Matcher | Action |
|------|-------|---------|--------|
| `detect-apm-handoff.sh` | `SessionStart` | `""` (all sessions) | Scans Handoff Bus, signals pending Handoffs |

Optionally, a brief note is appended to `CLAUDE.md`.

## Customization

Change the trigger percentage by editing the `apm-handoff` threshold in your cc-context-awareness config:

```bash
# Local
.claude/cc-context-awareness/config.json

# Global
~/.claude/cc-context-awareness/config.json
```

Find the entry with `"level": "apm-handoff"` and change the `"percent"` value.

## Design Notes

> **Why 70%?** Handoff procedures produce multiple artifacts (Handoff Memory Log, Handoff Bus prompt, User review) and require significant context to execute properly. 70% leaves enough room for the full procedure while triggering early enough to avoid emergency conditions.

> **Why a single threshold?** Handoff is a binary decision - either the agent performs it or it doesn't. Multiple warning tiers add noise without actionable value. If you want an earlier heads-up, add a second threshold with a different `level` name and a lighter message.

> **Why the detection hook?** APM's initiation commands already check the Handoff Bus, but that detection is LLM-driven - it's an instruction that can be missed. The SessionStart hook is deterministic bash that always runs and injects the signal before the LLM processes anything. It's a safety net that guarantees the incoming agent knows a Handoff is pending.

## Uninstall

```bash
npx cc-context-awareness remove apm-handoff
npx cc-context-awareness remove apm-handoff --global  # global
```

If you appended Handoff instructions to `CLAUDE.md`, remove them manually.
