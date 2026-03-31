import Foundation

enum SearchWorkflowState: Sendable, Equatable {
    case idle
    case searching
    case loaded(appID: String, versions: [AppVersion])
    case failed(AppError)
}
