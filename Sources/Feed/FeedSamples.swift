import Foundation

/// One label/value line of a pay stub.
struct FeedSampleLine: Hashable {
    let label: String
    let value: String
}

/// What a sample post carries under its headline.
enum FeedSampleBody: Hashable {
    case payStub([FeedSampleLine])
    case permissionSlip(text: String, signed: String)
    case recap(summary: Moment.RecapSummary)
}

/// A friend's post as it will look once friends exist. `DemoData.friendPosts`
/// fills these; the feed shows them under "Until your friends arrive".
struct FeedSample: Identifiable, Hashable {
    let id: String
    let author: String
    let initials: String
    let anonymous: Bool
    let hoursAgo: Int
    let dayType: String
    let headline: String
    let subline: String
    let body: FeedSampleBody
    let reactionCounts: [ReactionKind: Int]
}

/// One row of the feed: the user's own recap moment or a sample post.
enum FeedPost: Identifiable {
    case own(Moment)
    case sample(FeedSample)

    var id: String {
        switch self {
        case .own(let moment): return moment.id.uuidString
        case .sample(let sample): return sample.id
        }
    }

    var isOwn: Bool {
        if case .own = self {
            return true
        }
        return false
    }

    var isAnonymous: Bool {
        switch self {
        case .own(let moment): return moment.visibility == .anonymous
        case .sample(let sample): return sample.anonymous
        }
    }

    /// The named friend behind a post, whose history it can open; nil for
    /// your own posts and for anonymous ones.
    var friend: FeedSample? {
        if case .sample(let sample) = self, !sample.anonymous {
            return sample
        }
        return nil
    }

    var author: String {
        switch self {
        case .own: return "You"
        case .sample(let sample): return sample.author
        }
    }

    /// "Just a Thursday" for a recap moment, the sample's own label otherwise;
    /// nil while a recap's type is still pending.
    var dayTypeLabel: String? {
        switch self {
        case .own(let moment):
            guard let raw = moment.recap?.dayType, let type = DayType(rawValue: raw) else {
                return nil
            }
            let weekday = RecapCopy.weekday(of: moment.start, calendar: .current)
            return RecapCopy.typeName(type, values: ["weekday": weekday])
        case .sample(let sample):
            return sample.dayType.isEmpty ? nil : sample.dayType
        }
    }

    /// The one-line version for Quiet mode's list: "Just a Thursday · 6 spikes".
    var listHeadline: String {
        switch self {
        case .own(let moment):
            let n = moment.recap?.spikeCount ?? 0
            let spikes = n == 1 ? "1 spike" : "\(n) spikes"
            if let label = dayTypeLabel {
                return "\(label) · \(spikes)"
            }
            return spikes
        case .sample(let sample):
            if !sample.headline.isEmpty {
                return sample.headline
            }
            if case .permissionSlip(let text, _) = sample.body {
                return text
            }
            return sample.dayType
        }
    }

    /// "2 h ago", "Anonymous · 4 h ago", "Thu Sep 24 · recap".
    var meta: String {
        switch self {
        case .own(let moment):
            let who = moment.visibility == .anonymous ? "anonymous" : "recap"
            return "\(FrayedFormat.dayStamp(moment.start)) · \(who)"
        case .sample(let sample):
            let ago = sample.hoursAgo < 24 ? "\(sample.hoursAgo) h ago" : "\(sample.hoursAgo / 24) d ago"
            return sample.anonymous ? "Anonymous · \(ago)" : ago
        }
    }
}
