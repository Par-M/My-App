import XCTest

final class MyAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDevSignInAndLogout() throws {
        let app = XCUIApplication()
        app.launch()

        let logoutButton = app.buttons["Log Out"]
        if logoutButton.waitForExistence(timeout: 3) {
            logoutButton.tap()
        }

        let devButton = app.buttons["Development Sign In"]
        XCTAssertTrue(devButton.waitForExistence(timeout: 10), "Login screen should be shown")
        devButton.tap()

        let dashboard = app.navigationBars["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 15), "Dashboard should appear after sign in")

        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5))
        logoutButton.tap()

        let loginTitle = app.staticTexts["AI Scheduler"]
        XCTAssertTrue(loginTitle.waitForExistence(timeout: 10), "Login screen should reappear after logout")
    }
}
