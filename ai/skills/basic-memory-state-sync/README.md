# Skill: basic-memory-state-sync

## Goal

Den Projekt-Ist-Zustand als Basic-Memory-Notiz konsistent halten.

## Inputs

- Geaenderte Dateien im Repo
- Bestehende Notizen unter `ai/basic-memory/notes/`

## Preconditions

- Repo ist lokal verfuegbar
- Markdown-Notizen sind versioniert
- Optional: Basic-Memory CLI (`basic-memory` oder `bm`) installiert

## Steps

1. Lies die relevanten Projektquellen (mindestens `README.md`, `AGENTS.md`, `Makefile`).
2. Extrahiere nur belastbare Fakten (keine Spekulation).
3. Aktualisiere die passende Notiz unter `ai/basic-memory/notes/`.
4. Schreibe neue Punkte im Format `- [category] fact` unter `## Observations`.
5. Setze/aktualisiere Verlinkungen unter `## Relations` mit `[[Note Name]]`.
6. Pruefe, dass keine Secrets in der Notiz stehen.
7. Optional: validiere per Basic-Memory-Suche (`basic-memory tools search --query "current state"`).
8. Optional: nutze `run.sh`, um eine Update-Vorlage fuer den aktuellen Git-Stand zu erzeugen.

## Output format

- Status: `updated` oder `no-change`
- Updated note path
- Delta als kurze Bulletliste (added/changed/removed observations)

## Verification commands

- `basic-memory tools search --query="current state"`
- `basic-memory tools read-note --identifier="openclaw-azure-current-state"` (wenn verfuegbar)
- `./ai/skills/basic-memory-state-sync/run.sh`

## Failure handling

- Wenn Fakten unklar sind: nur gesicherte Informationen eintragen und offene Punkte explizit als Frage markieren.
- Wenn CLI nicht installiert ist: rein dateibasiert arbeiten, Notiz trotzdem aktualisieren.
