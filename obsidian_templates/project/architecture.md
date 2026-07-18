---
title: System Architecture
tags: [architecture, stack, core]
keywords: stack, constraint, design, system, overview, framework, database
updated: 2026-05-30
summary: Overview of stack + main constraints of the project (edit to match your real project)
---

# System Architecture

> This file is priority 1 — loaded into context almost every time, keep it concise but complete
> Write only what "every task should know", don't stuff in minor details (those go in decisions/)

## Stack
- Language / Runtime: <e.g. Gleam 1.16 / BEAM, or TypeScript/Bun>
- Web framework: <e.g. Wisp + Mist>
- Database: <e.g. Postgres / SQLite — specify version>
- External services: <e.g. Dedalus API, Kimi, Moonshot>

## High-level structure

```
<Place project structure diagram here>
```

## Hard constraints (things that must not be violated)
- <e.g.: every endpoint must be type-safe>
- <e.g.: do not use dependency X>
- <e.g.: single-user, localhost only>

## Key decisions (summary — details are in decisions/)
- <important decision in 1 line> → see [[decisions/...]]

## Don't do (anti-patterns)
- <e.g.: don't let the LLM do what code can do, e.g. token counting>
