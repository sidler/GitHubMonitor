import AppKit
import SwiftUI

/// The pictures people put in issue bodies, kept in memory by address.
///
/// Separate from the avatar cache, which fetches with nothing: a picture
/// dragged into an issue on a private repository is served from
/// `github.com/user-attachments/...`, which is not an API endpoint, is
/// documented nowhere, and wants the account behind it. A classic token
/// in the header is reported to be enough. Reported, not documented --
/// so nothing here depends on it, and a refusal is an ordinary outcome
/// with a view of its own rather than a hole in the text.
@MainActor
public final class BodyImageCache {
    public static let shared = BodyImageCache()

    /// How to fetch one. Set by whoever holds the account; nil means
    /// nobody is signed in, which is also an answer -- the view shows a
    /// link rather than waiting for something that cannot arrive.
    public var fetch: (@Sendable (URL) async throws -> Data)?

    private var images: [URL: NSImage] = [:]
    /// Addresses that came back refused or undecodable. Kept so that a
    /// body with a picture nobody can see does not ask again on every
    /// rebuild of the pane, which is every refresh.
    private var refused: Set<URL> = []
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    public func cached(_ url: URL) -> NSImage? { images[url] }

    public func wasRefused(_ url: URL) -> Bool { refused.contains(url) }

    public func image(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        if refused.contains(url) { return nil }
        if let existing = inFlight[url] { return await existing.value }
        guard let fetch else {
            refused.insert(url)
            return nil
        }

        let task = Task<NSImage?, Never> {
            do {
                let data = try await fetch(url)
                return NSImage(data: data)
            } catch {
                Log.avatars.notice(
                    "body image \(url, privacy: .public) refused: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image {
            images[url] = image
        } else {
            refused.insert(url)
        }
        return image
    }
}

@MainActor
private final class BodyImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isRefused = false

    func load(_ url: URL) async {
        if let cached = BodyImageCache.shared.cached(url) {
            image = cached
            return
        }
        image = await BodyImageCache.shared.image(for: url)
        isRefused = image == nil
    }
}

/// A picture from a body: the thing itself where it can be fetched, and a
/// way to it where it cannot.
///
/// The second case is not a failure to apologise for. Half of these
/// addresses need a browser session the app does not have, and the
/// browser is one click away with the session already in it -- so what a
/// refusal earns is a link, not an error.
struct BodyImageView: View {
    let url: URL
    let alt: String

    @StateObject private var loader = BodyImageLoader()

    /// Tall enough to tell what a screenshot is of, short enough that two
    /// of them do not push the text out of the pane. The real thing is a
    /// click away either way.
    private static let tallest: CGFloat = 220

    var body: some View {
        Group {
            if let image = loader.image {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: Self.tallest, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Open the full size picture")
            } else if loader.isRefused {
                link
            } else {
                // Not a spinner: most of these settle in well under a
                // second, and a body with four pictures would otherwise
                // open as a column of spinning wheels.
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary.opacity(0.4))
                    .frame(height: 60)
            }
        }
        .task(id: url) { await loader.load(url) }
    }

    private var link: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo")
                Text(alt.isEmpty ? "Picture" : alt)
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(Ink.blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.4), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("This one needs a signed-in browser \u{2014} opens on GitHub")
    }
}
