# Basic Memory in diesem Repo

Dieses Repo nutzt jetzt eine schlanke Basic-Memory-Struktur, um den
Projektkontext dauerhaft als Markdown-Wissensbasis zu pflegen.

## Ziel

- Den Ist-Zustand des Projekts nachvollziehbar dokumentieren.
- Kontext fuer Agenten und Menschen konsistent halten.
- Wissen in kleinen, verlinkbaren Notizen statt in einem Monolithen pflegen.

## Struktur

```text
ai/basic-memory/
  README.md
  notes/
    openclaw-azure-current-state.md
```

## Start (laut Basic-Memory-Doku)

Die Context7-Doku fuer `/basicmachines-co/basic-memory` zeigt je nach Version
die CLI als `basic-memory` oder `bm`.

Beispiel fuer lokales Projekt-Setup:

```bash
basic-memory project create openclaw-azure-setup --path ./ai/basic-memory --set-default
basic-memory tools basic-memory-guide
basic-memory tools search --query="current state"
```

Alternative (Kurzform in Teilen der Doku):

```bash
bm project add openclaw-azure-setup --default
bm tools search --query "current state"
```

## Notiz-Konvention

- Jede Notiz hat klare Sections `## Observations` und `## Relations`.
- Beobachtungen folgen dem Format `- [category] fact`.
- Beziehungen folgen dem Format `- relates_to [[Other Note]]`.
- Keine Secrets, Tokens oder Passwoerter in Notizen speichern.

## Pflegeprozess

1. Bei relevanten Aenderungen zuerst betroffene Notiz aktualisieren.
2. Neue Fakten als `Observations` ergaenzen.
3. Verknuepfungen als `Relations` zu bestehenden Notizen setzen.
4. Bei groesseren Features eigene Notiz erstellen und zur Ist-Zustand-Notiz verlinken.

## PR-/Change-Routine

Bei jeder relevanten Aenderung im Repo:

1. Betroffene Notiz identifizieren (`current-state`, `security-state`, `deploy-workflow`, `ops-runbook`, `known-risks`).
2. Nur verifizierte Fakten in `## Observations` aktualisieren.
3. Neue/veraenderte Verweise in `## Relations` setzen.
4. Optional den Skill-Helper laufen lassen:

```bash
make memory-sync-template
# oder direkt:
./ai/skills/basic-memory-state-sync/run.sh
```

Der Helper erzeugt eine Update-Vorlage unter
`ai/basic-memory/notes/_state-update-template.md`.

## Optional: Git Hook Guard

Installiere einmal lokal:

```bash
make install-pre-commit
```

Der Hook blockiert Commits mit infra-/ops-relevanten Aenderungen, wenn keine
Memory-Notiz unter `ai/basic-memory/notes/*.md` mitgestaged ist.

Einmalig ueberspringen (falls begruendet):

```bash
SKIP_MEMORY_CHECK=1 git commit -m "..."
```

## Hinweise

- Diese Struktur ist absichtlich minimal gehalten und kann spaeter in mehrere
  thematische Notizen (Security, Deploy, Ops, Costs) aufgeteilt werden.
- Der Inhalt in `notes/` ist git-versioniert und damit reviewbar.
