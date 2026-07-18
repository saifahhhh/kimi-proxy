---
title: Coding Conventions
tags: [conventions, style, naming, rules]
keywords: style, naming, convention, format, lint, import, pattern, rule
updated: 2026-05-30
summary: Coding style + naming rules all code must follow (edit to match your language / team)
---

# Coding Conventions

> This file is priority 1 — Coder (Kimi) reads it to write code that matches the style
> Include only rules that are actually enforced, don't add non-mandatory opinions

## Naming
- functions / variables: <e.g. snake_case>
- types / constructors: <e.g. PascalCase>
- files / folders: <e.g. kebab-case folders>
- private modules: <e.g. `_` prefix>

## Language rules
- <e.g.: do not use `any`, use `type` not `interface`>
- <e.g.: errors must always be custom types, never throw bare strings>
- <e.g.: use `use` for Result chains, `case` for branching>

## Imports
- <e.g.: use alias `@/`, no relative `../../`>
- <e.g.: order stdlib → ecosystem → internal>

## Formatting / Lint
- formatter: <e.g. gleam format / biome>
- pre-commit rule: <e.g. lint must pass with 0 errors>

## Testing
- framework: <e.g. gleeunit>
- rule: <e.g. do not hit real APIs in tests, use mocks>

## Don't do
- <e.g.: no debug prints (echo / io.debug) left in delivered files>
