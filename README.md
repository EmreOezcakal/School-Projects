# School-Projects

| Projekt | Was | Öffnen |
|---|---|---|
| [Kurs](kurs/) | Schulplaner fürs Abitur als iPad-App: Jetzt-Ansicht, Hausaufgaben, Stundenplan, Klausuren mit Lernplan, Fokus-Timer, Noten | [App öffnen](https://emreoezcakal.github.io/School-Projects/kurs/) |

Die frühere Adresse `punktekonto/` leitet auf `kurs/` weiter.

## Erinnerungen
`.github/workflows/erinnerungen.yml` schickt der App nach Schulschluss und um 19:30 einen Anstoß; den Text baut die App
auf dem iPad aus den eigenen Aufgaben (die Aufgaben verlassen das Gerät nicht). Einrichtung: in der App unter
Einstellungen → Mitteilungen einschalten und den angezeigten Code als Repository-Secret `PUSH_CONFIG` speichern.
