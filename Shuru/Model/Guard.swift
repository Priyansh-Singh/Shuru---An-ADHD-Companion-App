import Foundation

/// Apps Shuru knows how to name and send you back to.
/// Any other app (games included) still works: it's named from what Shortcuts passes in.
struct GuardedAppInfo {
    let key: String
    let name: String
    let bundleIDs: [String]
    /// URL that opens the app again after you buy time. nil = you go back yourself.
    let returnURL: String?

    static let known: [GuardedAppInfo] = [
        GuardedAppInfo(key: "instagram", name: "Instagram", bundleIDs: ["com.burbn.instagram"], returnURL: "instagram://app"),
        GuardedAppInfo(key: "youtube", name: "YouTube", bundleIDs: ["com.google.ios.youtube"], returnURL: "youtube://"),
        GuardedAppInfo(key: "x", name: "X", bundleIDs: ["com.atebits.tweetie2"], returnURL: "twitter://"),
        GuardedAppInfo(key: "safari", name: "Safari", bundleIDs: ["com.apple.mobilesafari"], returnURL: nil),
        GuardedAppInfo(key: "twitch", name: "Twitch", bundleIDs: ["tv.twitch"], returnURL: "twitch://"),
        GuardedAppInfo(key: "tiktok", name: "TikTok", bundleIDs: ["com.zhiliaoapp.musically"], returnURL: "snssdk1233://"),
        GuardedAppInfo(key: "reddit", name: "Reddit", bundleIDs: ["com.reddit.reddit"], returnURL: "reddit://"),
        GuardedAppInfo(key: "snapchat", name: "Snapchat", bundleIDs: ["com.toyopagroup.picaboo"], returnURL: "snapchat://"),
        GuardedAppInfo(key: "facebook", name: "Facebook", bundleIDs: ["com.facebook.facebook"], returnURL: "fb://"),
        GuardedAppInfo(key: "threads", name: "Threads", bundleIDs: ["com.burbn.barcelona"], returnURL: "barcelona://"),
        GuardedAppInfo(key: "netflix", name: "Netflix", bundleIDs: ["com.netflix.netflix"], returnURL: "nflx://"),
        GuardedAppInfo(key: "discord", name: "Discord", bundleIDs: ["com.hammerandchisel.discord"], returnURL: "discord://"),
        GuardedAppInfo(key: "pinterest", name: "Pinterest", bundleIDs: ["pinterest"], returnURL: "pinterest://")
    ]

    static let anyApp = GuardedAppInfo(key: "any", name: "the app", bundleIDs: [], returnURL: nil)

    /// Works with whatever Shortcuts passes: an app name ("YouTube"), a bundle ID, or nothing.
    static func match(_ input: String?) -> GuardedAppInfo {
        guard let raw = input?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return anyApp }
        let lower = raw.lowercased()
        if let k = known.first(where: { info in
            info.bundleIDs.contains(lower) || info.name.lowercased() == lower || info.key == lower
                || (lower == "twitter" && info.key == "x")
        }) {
            return k
        }
        let key = "app." + lower.filter { $0.isLetter || $0.isNumber || $0 == "." }
        return GuardedAppInfo(key: key, name: raw, bundleIDs: [lower], returnURL: nil)
    }
}

/// An app that has run the pause automation at least once.
struct SeenApp: Codable, Hashable {
    var name: String
    var lastSeen: Date
}
