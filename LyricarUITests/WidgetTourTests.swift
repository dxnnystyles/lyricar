import XCTest

/// Adds Lyricar widgets through SpringBoard and attaches screenshots to the Simulator tour.
/// Demo mode first, so the App Group holds a real lyric snapshot for the widgets to schedule from.
final class WidgetTourTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testAddLyricWidgets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LyricarDemo"]
        app.launch()
        sleep(8)
        XCUIDevice.shared.press(.home)
        sleep(2)

        addWidget(swipes: 0) // Lyric Line, small
        addWidget(swipes: 1) // Verse, medium

        let done = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Fertig", "Done"])).firstMatch
        if done.waitForExistence(timeout: 5) { done.tap() }
        sleep(6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "home-widgets"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func addWidget(swipes: Int) {
        let edit = springboard.buttons.matching(NSPredicate(format: "label == 'Bearbeiten' OR label CONTAINS[c] 'Edit'")).firstMatch
        if !edit.exists {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 2)
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Widget'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Lyricar")
        let cell = springboard.cells["Lyricar"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        sleep(2)
        for _ in 0..<swipes {
            springboard.swipeLeft()
            sleep(1)
        }
        let confirm = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hinzufügen' OR label CONTAINS[c] 'Add'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), springboard.buttons.debugDescription)
        confirm.tap()
        sleep(2)
    }
}
