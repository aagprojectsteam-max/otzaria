# AAG Fork Handoff — Otzaria

## Why this repository exists

This is a **fork/upstream-contribution workspace**, not an AAG-owned replacement for Otzaria. The fork exists to develop, validate and submit narrowly scoped Linux/WebView fixes back to the upstream Otzaria project. Upstream project documentation and licensing remain authoritative for Otzaria itself.

## AAG contribution context

The 2026 Linux work investigated rendering and touch problems in the packaged Linux application. The accepted patch set addressed Linux WebView/plugin rendering behavior, black-surface/fallback behavior, touch handling and compatibility with the related `flutter_inappwebview` fork change. Validation was performed against the real Otzaria Linux package used during development rather than only a synthetic Flutter sample.

The coordinated upstream contribution is tracked in upstream pull request **Otzaria/otzaria#1261**. A related lower-level WebView change is tracked separately in **Otzaria/flutter_inappwebview#21**. Keep these two layers separate when debugging: an application-level symptom may originate in the embedded WebView implementation.

## Fork workflow

Do not treat `dev` in this fork as an independent product release branch. Before new work, fetch upstream and identify whether the existing AAG commits have been merged, superseded or conflicted. New changes intended for upstream should be minimal, based on the current upstream target branch, tested on Linux, and submitted as a focused PR.

## Validation expectations

For Linux rendering/touch changes, test at least: application startup; affected WebView content rendering rather than a black surface; plugin/content rendering; touch input on the affected views; fallback path when the preferred rendering path is unavailable; and regression on unaffected navigation. Record the exact Otzaria package/Flutter/WebView revision used.

## Historical integrity rule

Do not describe the entire fork as AAG-authored software. Do not rewrite upstream history. Keep AAG-specific rationale in this file/PRs and keep source changes suitable for upstream review. If upstream merges the fix, prefer rebasing/syncing the fork rather than maintaining a permanent divergent product unless there is a documented reason.

## Current status

As of the 2026-09-15 portfolio documentation audit, this fork is retained because it participates in the coordinated Linux fix submitted upstream. The authoritative discussion/review status remains the upstream PR, not this handoff file.