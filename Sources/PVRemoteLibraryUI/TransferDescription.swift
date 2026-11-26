import Foundation
import PVRemoteLibrary

/// The words and numbers a transfer shows, so every app says the same thing.
public struct TransferDescription: Equatable, Sendable {
    /// "Downloading", "Checking files", "Adding to Library", …
    public var phase: String
    /// 0...1 while the amount done is known; nil shows an indeterminate bar.
    public var fraction: Double?
    /// "42%" while downloading, else nil.
    public var percent: String?
    /// The reason, when the transfer failed.
    public var failure: String?
    /// False once the importer has the files: there is nothing left to cancel.
    public var canCancel: Bool

    public init(_ state: TransferState) {
        failure = nil
        percent = nil
        fraction = nil
        canCancel = true
        switch state {
        case .queued:
            phase = "Preparing"
        case .downloadingIndeterminate:
            phase = "Downloading"
        case .downloading(let done):
            let clamped = min(max(done, 0), 1)
            phase = "Downloading"
            fraction = clamped
            percent = "\(Int((clamped * 100).rounded(.down)))%"
        case .verifying:
            phase = "Checking files"
        case .importing:
            phase = "Adding to Library"
            canCancel = false
        case .failed(let reason):
            phase = "Couldn't download"
            failure = reason
            canCancel = false
        }
    }
}
