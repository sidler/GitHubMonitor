import Foundation

/// Lifecycle of a lazily fetched comment preview.
public enum PreviewState: Equatable, Sendable {
    case loading
    case text(String)
    /// The thread has no comment body at all -- a review request or a state
    /// change, for instance.
    case empty
    case failed(String)
}
