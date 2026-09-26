# Building StudyDesk: a two-phase vibe-coding story

StudyDesk started with a practical frustration. An AI workflow could already organize noisy information into decisions, deadlines, events, and next actions, but its output still arrived as another summary that demanded attention. The missing layer was visualization: a quiet desk object that could turn machine-organized information into a stable human attention surface.

This document describes how the idea evolved across two phases. It is a build journal, not a claim that every step was efficient or correct on the first attempt.

## Starting constraints

The product brief was intentionally small:

- macOS only;
- structured output from an upstream AI organizer;
- an explicit, inspectable boundary between AI interpretation and visualization;
- no source-system credentials inside the dashboard;
- low memory use;
- visible on the desktop but behind normal applications;
- menu-bar controls for show, hide, refresh, login launch, and quit;
- a warm, minimal visual language;
- files remain readable and editable without the app.

Those constraints led to AppKit instead of Electron. A versioned Markdown adapter was chosen for the reference implementation because it is transparent and easy to inspect, not because the product is conceptually limited to files.

## Phase 1 — From AI-organized information to a desktop object

### 1. Stabilize the input contract

The first useful decision was not visual. It was agreeing on a machine-readable boundary between probabilistic AI interpretation and deterministic rendering. The reference adapter uses YAML-style front matter and an `## Items` table with a fixed column order.

This contract made the pipeline composable: an AI assistant, script, or human can produce structured information, while the visualization layer only needs to understand one schema.

### 2. Build the smallest native shell

The first application version used AppKit directly. It created:

- an accessory application with no Dock icon;
- a menu-bar status item;
- a resizable panel;
- a file watcher based on modification time and file size;
- Markdown parsing and card rendering;
- a LaunchAgent for login startup.

The window is placed just above the desktop level. When StudyDesk loses focus, normal application windows naturally cover it. This behavior is more subtle than an always-on-top utility and better matches the idea of a desktop dashboard.

### 3. Iterate on visual tone

The early interface was functional but too much like a conventional dashboard. The design moved toward warm off-white surfaces, quiet borders, serif display type, muted metadata, and a single terracotta accent.

The lesson was simple: “minimal” is not the absence of styling. It requires deliberate hierarchy, spacing, color restraint, and consistent interaction weight.

### 4. Resolve installation identity

Repeated test builds created multiple app bundles with similar names and identifiers. macOS permission prompts and Launch Services could not reliably distinguish what the user considered “the app.” The stable solution was to choose one canonical installation path and one bundle identity, then treat every other build as disposable.

### Phase 1 outcome

At the end of Phase 1, a change in the structured information feed updated a calm desktop panel within seconds. The app consumed little memory, had no network dependency, and could be controlled from the menu bar.

## Phase 2 — From display to action

### 1. Add a “This Week” view

The two sources were merged in memory and filtered by deadline. The view includes deadlines from the current day up to, but not including, the following Monday. Past deadlines from earlier in the week are intentionally excluded.

This sounds like a filter, but it required explicit decisions about:

- timezone;
- date-only values versus date-and-time values;
- what “this week” means on Sunday;
- whether completed or optional items should appear;
- whether the source order or deadline order wins.

### 2. Add manual ordering

Up and down controls let the user establish a personal display order. The order is stored in `NSUserDefaults` as item IDs. Markdown rows remain untouched, which avoids creating noisy file diffs just because the visual order changed.

### 3. Add editing and safe write-back

Editing introduced the highest-risk path in the app: modifying the source of truth.

The writer therefore:

1. reads the complete original file;
2. creates a timestamped backup in Application Support;
3. locates the row by stable item ID;
4. replaces only that row and the document update timestamp;
5. writes atomically;
6. reparses and rerenders the result.

Multiple links in a cell are preserved even though the card opens only the first one.

### 4. Replace the modal editor

The first editor used a modal alert while a two-second refresh timer continued to rerender the dashboard. In testing, the editor could close before the user finished typing, and UI automation could accidentally activate the default Save button.

The durable fix was architectural rather than cosmetic:

- use a dedicated non-modal editor panel;
- pause automatic refresh while the editor is open;
- separate Save and Cancel actions from the originating card click;
- never run destructive write tests against the only copy of user data.

### Phase 2 outcome

StudyDesk became a small task surface rather than a passive viewer. The information contract remains portable, while the app provides weekly focus, lightweight organization, and safe human corrections to AI-organized output.

## What would be Phase 3?

A responsible third phase would focus on reliability before new features:

- automated parser and writer tests using temporary fixtures;
- configurable source paths and timezones;
- a first-run setup screen;
- schema migration and validation messages;
- notarized distribution;
- accessibility and keyboard-navigation review;
- a small release checklist that verifies only one installed bundle exists.

The point of the experiment was not that AI made software instantaneous. It made iteration conversational. The engineering work still consisted of contracts, state management, testing, platform behavior, and careful control of side effects.
