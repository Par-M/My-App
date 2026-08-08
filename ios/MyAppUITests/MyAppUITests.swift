import XCTest

final class MyAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openTasksTabIfNeeded(_ app: XCUIApplication) {
        let tasksTab = app.tabBars.buttons["Tasks"]
        if tasksTab.waitForExistence(timeout: 3) {
            tasksTab.tap()
        }
    }

    @MainActor
    private func signOutIfSignedIn(_ app: XCUIApplication) {
        openTasksTabIfNeeded(app)
        let accountButton = app.buttons["Account"]
        guard accountButton.waitForExistence(timeout: 3) else { return }
        accountButton.tap()
        let logout = app.buttons["Log Out"]
        if logout.waitForExistence(timeout: 2) {
            logout.tap()
        }
    }

    @MainActor
    private func completeOnboardingIfPresent(_ app: XCUIApplication) {
        let getStarted = app.buttons["Get Started"]
        guard getStarted.waitForExistence(timeout: 3) else { return }
        getStarted.tap()
        for _ in 0..<3 {
            if app.buttons["Continue"].waitForExistence(timeout: 3) {
                app.buttons["Continue"].tap()
            }
        }
        if app.buttons["Done"].waitForExistence(timeout: 3) {
            app.buttons["Done"].tap()
        }
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        signOutIfSignedIn(app)
        let devButton = app.buttons["Development Sign In"]
        XCTAssertTrue(devButton.waitForExistence(timeout: 10), "Login screen should be shown")
        devButton.tap()
        completeOnboardingIfPresent(app)
        openTasksTabIfNeeded(app)
        let tasksBar = app.navigationBars["Tasks"]
        XCTAssertTrue(tasksBar.waitForExistence(timeout: 15), "Tasks screen should appear after sign in")
    }

    @MainActor
    private func deleteAllVisibleTasks(_ app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        while true {
            let firstRow = list.cells.firstMatch
            guard firstRow.waitForExistence(timeout: 3) else { break }
            firstRow.swipeLeft()
            let delete = app.buttons["Delete"].firstMatch
            guard delete.waitForExistence(timeout: 2) else { break }
            delete.tap()
            if !app.staticTexts["No Tasks Yet"].exists {
                _ = firstRow.waitForNonExistence(timeout: 5)
            }
        }
    }

    @MainActor
    func testDevSignInAndLogout() throws {
        let app = XCUIApplication()
        app.launch()

        signIn(app)

        signOutIfSignedIn(app)

        let loginTitle = app.staticTexts["Lock In Bud"]
        XCTAssertTrue(loginTitle.waitForExistence(timeout: 10), "Login screen should reappear after logout")
    }

    @MainActor
    func testCreateEditSearchArchiveRestoreDelete() throws {
        let app = XCUIApplication()
        app.launch()

        signIn(app)
        deleteAllVisibleTasks(app)

        let baseTitle = "BaseTask"
        let editSuffix = "Updated"

        app.buttons["addTaskButton"].tap()
        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(baseTitle)
        app.buttons["saveTaskButton"].tap()

        let createdRow = app.staticTexts[baseTitle]
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10), "New task should appear in the list")

        createdRow.tap()
        XCTAssertTrue(app.staticTexts[baseTitle].waitForExistence(timeout: 5), "Detail should show the task")

        app.buttons["editTaskButton"].tap()
        let editField = app.textFields["taskTitleField"]
        XCTAssertTrue(editField.waitForExistence(timeout: 5))
        editField.tap()
        editField.typeText(editSuffix)
        app.buttons["saveTaskButton"].tap()

        let editedTitle = "\(baseTitle)\(editSuffix)"
        XCTAssertTrue(app.staticTexts[editedTitle].waitForExistence(timeout: 5), "Detail should show the edited title")

        app.navigationBars[editedTitle].buttons["Tasks"].tap()

        let searchField = app.searchFields.firstMatch
        if !searchField.waitForExistence(timeout: 3) {
            let searchButton = app.buttons["Search"]
            if searchButton.waitForExistence(timeout: 3) {
                searchButton.tap()
            }
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(editSuffix)
        XCTAssertTrue(app.staticTexts[editedTitle].waitForExistence(timeout: 5), "Search should find the task")
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        } else {
            app.keyboards.buttons["Search"].tap()
        }

        app.staticTexts[editedTitle].tap()
        app.buttons["moreMenuButton"].tap()
        app.buttons["Archive"].tap()

        XCTAssertTrue(
            app.staticTexts[editedTitle].waitForNonExistence(timeout: 10),
            "Archived task should disappear from the active list"
        )

        app.buttons["archiveToggleButton"].tap()
        XCTAssertTrue(
            app.staticTexts[editedTitle].waitForExistence(timeout: 10),
            "Archived task should appear in the archived list"
        )

        app.staticTexts[editedTitle].tap()
        app.buttons["moreMenuButton"].tap()
        app.buttons["Restore"].tap()

        XCTAssertTrue(
            app.staticTexts[editedTitle].waitForNonExistence(timeout: 10),
            "Restored task should leave the archived list"
        )

        app.buttons["archiveToggleButton"].tap()
        XCTAssertTrue(
            app.staticTexts[editedTitle].waitForExistence(timeout: 10),
            "Restored task should be back in the active list"
        )

        app.staticTexts[editedTitle].tap()
        app.buttons["moreMenuButton"].tap()
        app.buttons["Delete"].tap()
        app.buttons["Delete"].tap()

        XCTAssertTrue(
            app.staticTexts[editedTitle].waitForNonExistence(timeout: 10),
            "Deleted task should disappear from the list"
        )
    }

    @MainActor
    func testScheduleTabShowsDayWeekMonthViews() throws {
        let app = XCUIApplication()
        app.launch()

        signIn(app)
        app.tabBars.buttons["Schedule"].tap()

        let dayButton = app.buttons["Day"]
        XCTAssertTrue(dayButton.waitForExistence(timeout: 10), "Day segmented control should exist")
        XCTAssertTrue(app.buttons["Week"].exists, "Week segmented control should exist")
        XCTAssertTrue(app.buttons["Month"].exists, "Month segmented control should exist")

        XCTAssertTrue(
            app.staticTexts["Today"].waitForExistence(timeout: 10),
            "Day view should default to today"
        )

        app.buttons["Month"].tap()
        XCTAssertTrue(
            dayButton.waitForExistence(timeout: 5),
            "App should stay responsive after switching to month view"
        )

        app.buttons["Week"].tap()
        XCTAssertTrue(
            dayButton.waitForExistence(timeout: 5),
            "App should stay responsive after switching to week view"
        )
    }

    @MainActor
    func testEmptyState() throws {
        let app = XCUIApplication()
        app.launch()

        signIn(app)
        deleteAllVisibleTasks(app)

        let emptyTitle = app.staticTexts["No Tasks Yet"]
        XCTAssertTrue(
            emptyTitle.waitForExistence(timeout: 10),
            "Empty state should be shown when there are no tasks"
        )
    }
}
