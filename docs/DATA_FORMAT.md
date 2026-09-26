# `studydesk/v1` data format

StudyDesk reads two UTF-8 Markdown files from the current user's Desktop:

- `StudyDesk-Email.md`
- `StudyDesk-Study-Group.md`

## Front matter

```yaml
---
schema: studydesk/v1
source: email
title: Email Updates
updated_at: 2030-01-07 09:00
timezone: Europe/Paris
---
```

`schema` must be exactly `studydesk/v1`. The `source` value should be `email` or `study_group`.

## Items table

The document must contain an `## Items` heading followed by this exact column order:

| Column | Meaning |
|---|---|
| `ID` | Stable unique identifier; never reuse it for a different item |
| `Priority` | `P0`, `P1`, `P2`, or `P3` |
| `Type` | Suggested values: `deadline`, `event`, `task`, `reference` |
| `Course / Group` | Short context label |
| `Item` | Human-readable title |
| `Start` | Optional `YYYY-MM-DD` or `YYYY-MM-DD HH:MM` |
| `Deadline` | Optional `YYYY-MM-DD` or `YYYY-MM-DD HH:MM` |
| `Status` | Suggested values: `action_required`, `confirmed`, `tentative`, `registered`, `optional`, `reference`, `completed` |
| `Details` | Context that should survive summarization |
| `Next Action` | Concrete next step |
| `Link` | Zero or more angle-bracket URLs separated by spaces |
| `Last Updated` | Date or timestamp of the latest material change |

Cells containing a literal pipe must escape it as `\|`.

## Notes

Content after a `## Notes` heading is preserved by the row writer. It is not currently rendered in the application.

## Privacy guidance

Keep real source files outside the repository. If you want to report a parser bug, reproduce it with a fictional document that contains no names, email addresses, private URLs, meeting locations, or institutional identifiers.
