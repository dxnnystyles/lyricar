import XCTest

/// Drives the CarPlay display of the Simulator (I/O > External Displays > CarPlay must be on)
/// and attaches screenshots of every screen for each Lyricar CarPlay view.
/// Uses the demo clock so it renders real LRCLIB lyrics without anything playing on Spotify.
final class CarPlayTourTests: XCTestCase {
    private let car = XCUIApplication(bundleIdentifier: "com.apple.CarPlayApp")
    /// CarPlay renders third-party templates in this separate host process.
    private let host = XCUIApplication(bundleIdentifier: "com.apple.CarPlayTemplateUIHost")

    override func setUp() {
        continueAfterFailure = true
    }

    private var prefix: String { ProcessInfo.processInfo.environment["LYRICAR_LIVE"] == "1" ? "live-" : "" }

    func testCarPlayViews() throws {
        let app = XCUIApplication()
        // LYRICAR_LIVE=1 (pass as TEST_RUNNER_LYRICAR_LIVE=1 to xcodebuild) uses the real Spotify account.
        if ProcessInfo.processInfo.environment["LYRICAR_LIVE"] != "1" {
            app.launchArguments = ["-LyricarDemo", "-LyricarTheme", ProcessInfo.processInfo.environment["LYRICAR_THEME"] ?? "motorsport"]
        }
        app.launch()

        XCTAssertGreaterThan(XCUIScreen.screens.count, 1, "Enable the CarPlay external display in the Simulator first")

        let icon = car.descendants(matching: .any).matching(identifier: "Lyricar").firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 15), car.debugDescription)
        icon.tap()

        // Karaoke is the first tab. Give the demo clock time to reach a sung line.
        sleep(8)
        snap(prefix + "carplay-karaoke")

        print("HOST-TREE\n\(host.debugDescription)")
        // Jump to lyrics: tap the third visible line; it must become the current (top) line.
        let titles = host.buttons.matching(identifier: "CPListItemTitle")
        XCTAssertTrue(titles.element(boundBy: 3).waitForExistence(timeout: 5), host.debugDescription)
        let before = titles.element(boundBy: 0).label
        // A sung line (not the instrumental marker) that is not already current.
        let pick = (2..<min(titles.count, 6)).first { titles.element(boundBy: $0).label != "\u{266A}" && titles.element(boundBy: $0).label != before } ?? 2
        let targetText = titles.element(boundBy: pick).label
        host.cells.matching(identifier: "CPListItem").element(boundBy: pick).tap()
        sleep(3)
        let top = titles.element(boundBy: 0).label
        print("SEEK-CHECK before=\(before) tapped=\(targetText) nowTop=\(top)")
        XCTAssertNotEqual(targetText, before)
        XCTAssertEqual(top, targetText, "tapping a lyric line must jump the song there")
        snap(prefix + "carplay-karaoke-after-seek")

        for tab in ["Focus", "Stage", "Track"] {
            let button = host.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", tab, tab)).firstMatch
            guard button.waitForExistence(timeout: 10) else {
                XCTFail("No \(tab) tab in the template host")
                continue
            }
            button.tap()
            sleep(3)
            if tab == "Stage" {
                snap(prefix + "carplay-stage")
                let down = car.buttons.matching(identifier: "ScrollDown").firstMatch
                if down.waitForExistence(timeout: 3) { down.tap() }
                sleep(2)
                snap(prefix + "carplay-stage-styles")
                continue
            }
            snap(prefix + "carplay-\(tab.lowercased())")
        }
    }

    private func snap(_ name: String) {
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "\(name)-screen\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
