import Foundation

/// Versions of the focus ledger's format and of the counting rules (F1 design §3).
public enum FocusRules {
    /// The ledger event format. New kinds and fields don't change it; only an incompatible change would.
    public static let schemaVersion = 1
    /// The counting rules a day is counted under (R11): a rule change applies only to later days.
    public static let version = 1
}
