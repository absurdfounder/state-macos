import Foundation

enum Brand {
    static let name = "State"
    static let mountPath = "/Volumes/State"
    static let site = "https://statelanding.netlify.app"
    /// Individual included storage. Binary tebibyte so the UI prints 1.0 TB.
    static let includedBytes: UInt64 = 1 << 40
    static let extraBlockBytes: UInt64 = 500 * 1_073_741_824
    static let extraBlockDollars: Double = 6
    static let individualDollars: Double = 15
    static let trialDays = 7
}
