import XCTest
@testable import MindMaps

/// Tests für die aufgeräumte Oberfläche (Version 1.1.2).
final class Oberflaeche112Tests: XCTestCase {

    func testLibraryShowsTodayAndYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 12))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 1, minute: 28))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 16, minute: 25))!
        let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9))!

        XCTAssertTrue(FriendlyDate.text(today, now: now, calendar: calendar).hasPrefix("Heute, "))
        XCTAssertTrue(FriendlyDate.text(yesterday, now: now, calendar: calendar).hasPrefix("Gestern, "))
        let plain = FriendlyDate.text(older, now: now, calendar: calendar)
        XCTAssertFalse(plain.hasPrefix("Heute") || plain.hasPrefix("Gestern"))
        XCTAssertTrue(plain.contains("2026"))
    }

    func testPlusStaysClickableWhenZoomedOut() {
        // Seit 1.2: auf dem Bildschirm nie kleiner als 11 pt – auch bei 100 % (vorher 9 pt).
        XCTAssertEqual(MapRenderer.handleRadius(zoom: 1), 11, accuracy: 0.001, "normal mindestens 11 pt")
        XCTAssertEqual(MapRenderer.handleRadius(zoom: 2), MapRenderer.handleRadius, "hineingezoomt nicht kleiner als 9 pt in der Map")
        // Herausgezoomt: auf dem Bildschirm mindestens 11 pt Radius.
        XCTAssertEqual(MapRenderer.handleRadius(zoom: 0.5) * 0.5, 11, accuracy: 0.001)
        // Aber nie riesig in der Map.
        XCTAssertEqual(MapRenderer.handleRadius(zoom: 0.05), MapRenderer.handleRadius * 3)
    }

    /// Knoten-Werkzeuge oben in der Leiste, Thema und Layout in der Seitenleiste.
    func testNodeToolsInToolbarAndMapSettingsInSidebar() {
        XCTAssertEqual(NodeTool.allCases, [.task, .tags, .note, .media, .style])
        XCTAssertEqual(InspectorTab.style.nodeTool, .style)
        XCTAssertEqual(InspectorTab.info.nodeTool, .task)
        XCTAssertNil(InspectorTab.layout.nodeTool)
        XCTAssertNil(InspectorTab.theme.nodeTool)
        XCTAssertEqual(Set(NodeTool.allCases.map(\.symbol)).count, NodeTool.allCases.count, "jedes Werkzeug hat sein Symbol")
    }

    func testViewSwitchCyclesThroughAllLayouts() {
        var layout = EditorLayout.map
        var seen: [EditorLayout] = []
        for _ in 0..<3 {
            seen.append(layout)
            layout = layout.next
        }
        XCTAssertEqual(Set(seen), Set(EditorLayout.allCases))
        XCTAssertEqual(layout, .map)
    }
}
