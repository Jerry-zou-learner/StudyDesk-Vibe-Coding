# Contributing

Thank you for considering a contribution.

## Principles

- Keep StudyDesk local-first and understandable.
- Prefer AppKit and system frameworks over new dependencies.
- Do not add telemetry, analytics, accounts, or cloud storage.
- Never commit real email summaries, schedules, private links, or personal paths.
- Preserve unchanged Markdown content during write-back.

## Before opening a pull request

1. Build the app with `./build_app.sh`.
2. Copy the fictional examples to the Desktop.
3. Run `dist/StudyDesk.app/Contents/MacOS/StudyDesk --validate examples`.
4. Test editing with copied fixtures, not irreplaceable data.
5. Confirm Cancel creates no file diff.
6. Scan the diff for personal information and generated app bundles.

Small pull requests with one clear purpose are easiest to review.
