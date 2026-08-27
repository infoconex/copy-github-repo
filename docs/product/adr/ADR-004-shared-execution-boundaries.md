---
title: "ADR-004 – Shared Execution and Native Command Boundaries | CopyGitHubRepo"
description: "Architecture decision requiring the wizard and public command to share the approved-plan engine while Git, Git LFS, and GitHub CLI run through centralized no-shell process helpers."
---

# ADR-004: Share the approved-plan engine and centralize native command execution

Status: Accepted

## Context

Interactive and scripted entry points must preserve identical safety semantics. The implementation also invokes Git, Git LFS, and GitHub CLI, where ad hoc shell evaluation would increase injection, quoting, and cross-platform risk.

## Decision

The wizard and public command delegate to the same shared application boundary for approved-plan execution rather than maintaining separate copy engines. Native tools are invoked through centralized process helpers using argument lists and no shell evaluation.

## Alternatives and tradeoffs

- Separate wizard orchestration: can optimize UX locally, but risks behavioral drift from the public command.
- Shell command strings: concise, but create avoidable quoting/injection/platform ambiguity.

## Consequences

Presentation may differ, but planning/execution semantics must converge before mutation. Native-command behavior belongs behind infrastructure helpers and can be tested independently. New entry points should reuse these boundaries rather than bypass them.