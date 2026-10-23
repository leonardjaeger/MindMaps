# MindMaps

MindMaps ist eine Mindmap-App für macOS nach Vorbild von MindNode. Gedanken, Referate, Lernzettel und Projektpläne entstehen als Mindmap und gleichzeitig als Gliederung. Beide Ansichten bleiben synchron, so dass du in der Map frei anordnen und in der Outline schnell tippen kannst.

- Mindmap und Outline nebeneinander, Einklappen, Rückgängig/Wiederholen, Zoom
- Bibliothek mit Ordnern, Suche, Papierkorb, Vorlagen und Beispieldokumenten; Vorschau im Finder per Quick Look
- Notizen, Tags und Aufgaben, Querverbindungen, Links, Bilder und Formeln
- Gestaltung mit 8 Themes, eigenen Themes, 4 Layouts und 10 Knotenformen; Präsentationsmodus
- Import und Export: Markdown, OPML, FreeMind, Text, RTF, TextBundle, PDF, PNG und SVG; Drucken
- Dokumentverlauf: frühere Zwischenstände ansehen und wiederherstellen
- macOS-Integration mit Erinnerungen, Kurzbefehlen, Siri und Spotlight
- Oberfläche auf Deutsch und Englisch

Ab macOS 15, SwiftUI.

## Download für macOS

**[MindMaps 1.3 herunterladen (.dmg)](https://github.com/leonardjaeger/MindMaps/releases/download/v1.3/MindMaps-1.3.dmg)** – DMG öffnen und MindMaps in „Programme“ ziehen. Alle Versionen stehen unter [Releases](https://github.com/leonardjaeger/MindMaps/releases).

MindMaps ist nicht bei Apple notarisiert. Beim ersten Start blockt macOS die App deshalb: Systemeinstellungen › Datenschutz & Sicherheit › „Dennoch öffnen“.

## Starten

**Mit Xcode (empfohlen)**
1. `MindMaps.xcodeproj` doppelklicken.
2. Oben das Ziel **MindMaps › My Mac** wählen.
3. **⌘ R** startet die App, **⌘ U** führt die Tests aus.

Falls Xcode beim ersten Start nach Signierung fragt: *Signing & Capabilities › Team* auf „None“ lassen, *Signing Certificate* „Sign to Run Locally“.

**Ohne Xcode-Oberfläche (Terminal)**
```bash
./build.sh --run
```

**Referenz-Dokument:** `Docs/Referenz.mindmaps` (53 Knoten in 4 Ebenen).

## Bibliothek

Die Bibliothek öffnet sich beim Start (sonst **Fenster › Bibliothek**, ⇧ ⌘ L). Sie zeigt alle Mindmaps im Bibliotheksordner – Standard `Dokumente/MindMaps`, änderbar unter **MindMaps › Einstellungen …** (⌘ ,).

| Aktion | So geht's |
|---|---|
| Neues Dokument | Knopf „Neues Dokument“, Pfeil daneben für Vorlagen (Referat, Lernzettel, Projektplan) |
| Beispiele anlegen | Pfeil neben „Neues Dokument“ › Beispieldokumente hinzufügen (20 Dokumente in Ordnern) |
| Öffnen | Doppelklick |
| Neuer Ordner | Knopf „Neuer Ordner“ (legt ihn im gewählten Ordner an) |
| Verschieben | Karte auf einen Ordner ziehen (Seitenleiste oder Raster) oder Rechtsklick › Bewegen nach |
| Umbenennen | Rechtsklick › Umbenennen … |
| Löschen | ⌫ oder Rechtsklick › In den Papierkorb – im Papierkorb der Bibliothek wiederherstellbar |
| Suchen | Suchfeld oben rechts: findet Titel und jeden Knotentext |
| Raster / Liste, Sortierung | Knöpfe in der Werkzeugleiste |

**Quick Look:** Jede Datei enthält ab dem nächsten Sichern ein Vorschaubild (`QuickLook/Preview.png`). Die Erweiterung „MindMaps Vorschau“ zeigt es im Finder mit der Leertaste.

## Bedienung

**In der Mindmap** (vorher einmal in die Arbeitsfläche klicken)

| Aktion | Eingabe |
|---|---|
| Knoten auswählen | Klick (leere Fläche: Auswahl aufheben) |
| Auswahl bewegen | Pfeiltasten |
| Knoten bearbeiten | Doppelklick oder Leertaste; ↩ übernimmt, Esc bricht ab |
| Unterknoten | Tab oder „+“-Griff am ausgewählten Knoten |
| Knoten danach (gleiche Ebene) | ↩ |
| Knoten löschen | ⌫ |
| Einklappen / Aufklappen | Knopf „−“ neben dem ausgewählten Knoten / Klick auf den Zähler neben einem eingeklappten Knoten |
| Knoten umhängen | Knoten auf einen anderen ziehen (Ziel wird gestrichelt markiert) |
| Arbeitsfläche verschieben | Leere Fläche ziehen oder mit zwei Fingern scrollen |
| Zoomen | Pinch, ⌘ + Scrollen, ⌘ + / ⌘ – |
| An Fenster anpassen / Originalgröße | ⌘ 0 / ⌥ ⌘ 0 (Menü „Darstellung“) |
| Rückgängig / Wiederholen | ⌘ Z / ⇧ ⌘ Z |

**In der Outline**

| Aktion | Taste |
|---|---|
| Bearbeiten | In den Text klicken (oder Zeile auswählen und ↩) |
| Neuer Knoten darunter (gleiche Ebene) | ↩ beim Tippen |
| Eine Ebene tiefer / höher | Tab / ⇧ Tab |
| Vorige / nächste Zeile | ↑ / ↓ |
| Änderung verwerfen | Esc |
| Umsortieren / umhängen | Griff ≡ rechts in der Zeile ziehen: obere Hälfte einer Zeile = davor, Mitte = hinein (Rahmen), untere Hälfte = danach (Linie) |
| Knoten löschen | ⌫ (Zeile ausgewählt) oder ⌘ ⌫ |

**Überall**

| Aktion | Taste |
|---|---|
| Ansicht wechseln (beides → nur Mindmap → nur Outline) | ⌘ ⇧ O oder Umschalter links in der Werkzeugleiste |
| Einklappen / Aufklappen | ⌘ . (Menü „Knoten“), Pfeil in der Outline, Knopf „−“ bzw. Zähler in der Map |
| Unterknoten / Knoten danach | ⌘ ↩ / ⇧ ⌘ ↩ |

Das Thema wechselt man über das Menü „Thema“ in der Werkzeugleiste.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `MindMaps/Core` | Datenmodell, Speichern (JSON), Baum-Operationen, Themes, Layout, Zoom-Geometrie, Pfeiltasten-Navigation, Bibliothek (Einlesen, Ordner, Papierkorb), Vorlagen – ohne SwiftUI, voll getestet |
| `MindMaps/Document` | Dateityp `.mindmaps` (Paket mit `document.json` und `assets/`), Rückgängig/Wiederholen |
| `MindMaps/Views` | Oberfläche: Fenster, Outline, Mindmap-Arbeitsfläche, Zeichnen, Zoom, Menüs, Einstellungen, Theme-Farben |
| `MindMaps/Views/Library` | Bibliotheksfenster |
| `MindMapsQuickLook` | Quick-Look-Erweiterung (Vorschau im Finder) |
| `MindMaps/Resources/Themes.json` | Die 8 Themes (hell + dunkel) |
| `MindMapsTests` | Unit-Tests |
| `Config/Info.plist` | Dokumenttyp-Registrierung |
| `Config/QuickLook-*` | Einstellungen der Quick-Look-Erweiterung |
| `Docs` | Referenz-Dokument, Theme-Vorschau, App-Icon in 1024 px |

## Lizenz

MIT-Lizenz, siehe [`LICENSE`](LICENSE).
