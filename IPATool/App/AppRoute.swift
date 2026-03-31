import Foundation

enum AppRoute: Hashable, Identifiable, CaseIterable {
    case auth
    case search
    case tasks
    case logs
    case compliance
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .auth:
            "Account"
        case .search:
            "Search"
        case .tasks:
            "Tasks"
        case .logs:
            "Logs"
        case .compliance:
            "Risks"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .auth:
            "person.crop.circle"
        case .search:
            "magnifyingglass"
        case .tasks:
            "square.stack.3d.down.right"
        case .logs:
            "text.justify.left"
        case .compliance:
            "exclamationmark.shield"
        case .settings:
            "gearshape"
        }
    }
}
