# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **oo7 task context injection**: `ask.sh` walks up from the current directory
  to the nearest `TASK.md` and sends that folder as `task_root`; the proxy
  reads the task's markdown live on every request (`TASK.md` → `[TASK]`,
  `AGENTS.md` → `[AGENTS]`, other docs → `[TASK FILES]`) alongside vault
  memory. Worktrees (dirs with `.git`), dot-dirs, and the `CLAUDE.md` /
  `GEMINI.md` symlink twins are skipped. Opt out with `ASK_NO_TASK=1`.
- `task_root` accepted as an optional extension field on
  `POST /v1/chat/completions` (absent = unchanged behaviour).

## [0.2.0] - 2026-05-30

### Added
- OpenAI-compatible local proxy server (Gleam / BEAM).
- Dual-brain routing: **Planner** (Sonnet 4.6) for design/planning, **Coder** (Kimi K2.6) for code.
- Obsidian vault integration for long-term memory (external "brain").
- Token-budget context assembly — never overflows the model window.
- Subscription CLI fallback chain (claude → Dedalus API, kimi-cli → Dedalus API).
- Read-only agent mode for safe code generation.
- Session logging and automatic vault index regeneration.
- Rule-based intent classifier (no LLM for routing decisions).
- Comprehensive test suite with mocked CLIs.

## [0.1.0] - 2026-05-20

### Added
- Initial prototype and spec.
