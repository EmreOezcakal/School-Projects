# Motiv – Kamera mit Bildaufbau-Coach

Eigene iPhone-Kamera-App, die beim Bildaufbau hilft: Sie findet in der Szene das stärkste Motiv,
markiert es mit einem gelben Rahmen und führt dich dorthin („näher ran“, „etwas nach links“ …),
bis der Rahmen das Bild füllt. Dann leuchtet der Auslöser.

## Funktionen

| Funktion | Wie |
|---|---|
| **✦ Scan** | Sucht das Motiv direkt auf dem iPhone (Apple Vision) – kostenlos, offline, unbegrenzt |
| **Smart-Scan** (optional) | Schickt ein verkleinertes Sucherbild an Claude und bekommt Ausschnitt + Foto-Tipp zurück. Braucht einen eigenen API-Schlüssel |
| **Führung** | Gelber Rahmen folgt dem Motiv (Tracking), Hinweise zu Richtung und Zoom, Auslöser leuchtet + vibriert, wenn es passt |
| **Rahmen zeichnen** | Kritzel-Symbol oben → Rahmen um dein Motiv ziehen → die App führt dich hin |
| **Kamera** | .5x / 1x / 2x / Tele (je nach iPhone), Zwei-Finger-Zoom, Tippen = Fokus, Blitz |
| **Formate** | 9:16, 3:4, 4:5, 1:1 – das Foto wird passend zugeschnitten |
| **Fotoqualität** | Volle Sensorauflösung (bei neueren Pro-iPhones bis 48 MP), Apples volle Bildverarbeitung, Speichern als HEIF oder JPEG. Bei 3:4 bleibt die Originaldatei der Kamera unverändert |
| **Hilfen** | Drittel-Raster, Wasserwaage (wird gelb, wenn das iPhone gerade ist) |
| **Editor** | 9 eigene Looks (Sonnig, Film 400, Golden, S/W …) und Regler für Belichtung, Kontrast, Sättigung, Wärme, Lichter, Tiefen, Verblassen, Vignette, Körnung – gesichert wird in voller Auflösung |

Kein Abo, keine Limits – alles ist freigeschaltet.

## Auf das iPhone bringen (Windows-PC, kostenlose Apple-ID)

Die App wird bei jedem Push automatisch auf einem Mac-Server von GitHub gebaut.
Die fertige Datei liegt immer hier:

**https://github.com/EmreOezcakal/School-Projects/releases/download/motiv-latest/Motiv.ipa**

Installiert wird sie per **Sideloading** mit [SideStore](https://sidestore.io) oder [AltStore](https://altstore.io).
Die Schritte dort ändern sich gelegentlich – halte dich an deren aktuelle Anleitung. Grob:

1. **Einmalig am PC:** SideStore (oder AltStore) laut Anleitung mit deiner Apple-ID auf das iPhone bringen.
2. **Auf dem iPhone:** *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* einschalten (Neustart nötig)
   und unter *Einstellungen → Allgemein → VPN & Geräteverwaltung* deiner Apple-ID vertrauen.
3. **Motiv.ipa** über den Link oben in Safari laden („In Dateien sichern“).
4. In SideStore/AltStore auf **+** tippen und die Datei aus *Dateien* wählen.

**Wichtig:** Mit einer kostenlosen Apple-ID läuft die Signatur nach **7 Tagen** ab.
SideStore kann sie direkt auf dem iPhone erneuern, AltStore braucht dafür den PC im selben WLAN.
Wenn die App nicht mehr startet: in SideStore/AltStore auf *Refresh* tippen.

## Smart-Scan einrichten (optional)

1. Auf [platform.claude.com](https://platform.claude.com) ein Konto anlegen, Guthaben aufladen und einen API-Schlüssel erstellen.
2. In Motiv: **⋯ → API-Schlüssel** einfügen, „✦ nutzt Smart-Scan mit Claude“ einschalten.
3. Modell wählen: **Opus 5.5** liefert die besten Vorschläge, **Haiku 5.5** ist viel günstiger und schneller.

Der Schlüssel liegt nur im Schlüsselbund deines iPhones, nicht im Code.
Lang drücken auf ✦ nutzt jeweils den anderen Scan-Modus.

## Aufbau

```
motiv/
├── project.yml              XcodeGen-Beschreibung → wird auf dem Mac-Server zum Xcode-Projekt
└── Motiv/
    ├── Camera/              AVFoundation-Kamera, Vorschau, Wasserwaage
    ├── Coach/               Motivsuche (Vision), Tracking, Hinweise, Claude-Smart-Scan
    ├── Editor/              Core-Image-Filter, Looks, Editor-Ansicht
    ├── UI/                  Kamera-Bildschirm, Einstellungen
    └── Support/             Formate, Schlüsselbund, Fotos sichern, Haptik
```

Gebaut wird über `.github/workflows/motiv-ios.yml`.
