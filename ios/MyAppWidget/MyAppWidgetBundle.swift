import WidgetKit
import SwiftUI

@main
struct MyAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurrentTaskWidget()
        TasksRemainingWidget()
    }
}
