import Combine
import OSLog
import SwiftUI

/// Shared avatar cache.
///
/// `AsyncImage` would refetch on every list rebuild, and these lists rebuild
/// on every refresh tick, so images are kept in memory and keyed by URL.
@MainActor
public final class AvatarCache {
    public static let shared = AvatarCache()

    private var images: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    public func cached(_ url: URL) -> NSImage? {
        images[url]
    }

    public func image(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<NSImage?, Never> { [session] in
            // A missing avatar is not worth surfacing in the UI, but silently
            // swallowing the reason makes "why is nothing loading" unanswerable.
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else { return nil }
                guard http.statusCode == 200 else {
                    Log.avatars.notice("avatar \(url, privacy: .public) returned \(http.statusCode)")
                    return nil
                }
                guard let image = NSImage(data: data) else {
                    Log.avatars.notice("avatar \(url, privacy: .public) was not decodable")
                    return nil
                }
                return image
            } catch {
                Log.avatars.notice(
                    "avatar \(url, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { images[url] = image }
        return image
    }
}

@MainActor
private final class AvatarLoader: ObservableObject {
    @Published var image: NSImage?

    func load(_ url: URL?) async {
        guard let url else {
            image = nil
            return
        }
        if let cached = AvatarCache.shared.cached(url) {
            image = cached
            return
        }
        image = await AvatarCache.shared.image(for: url)
    }
}

/// A circular avatar that falls back to a neutral placeholder, so a deleted
/// user or a failed load never leaves a hole in the row.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 20

    @StateObject private var loader = AvatarLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
        .task(id: url) { await loader.load(url) }
    }
}
