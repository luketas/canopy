import Foundation
import CanopyCore

/// Discovery may enumerate a newly focused Chrome window before older ones.
/// Soft fingerprints must never claim the identity of another live window.
enum WindowIdentity {
    static func record(for fingerprint: WindowFingerprint,app: String,processID: Int32,
                       nativeNumber: UInt32?,session: WindowRecord?,saved: [WindowRecord],
                       liveIDs: Set<String>,claimed: Set<String>) -> WindowRecord {
        let available = saved.filter { !claimed.contains($0.id) && $0.bundleID == fingerprint.bundle }
        let compatibleSession = session.flatMap { old -> WindowRecord? in
            guard !claimed.contains(old.id),old.bundleID == fingerprint.bundle else { return nil }
            if let nativeNumber,old.nativeProcessID == processID,let oldNumber = old.nativeWindowNumber,oldNumber != nativeNumber { return nil }
            return available.first { $0.id == old.id } ?? old
        }
        let native = nativeNumber.flatMap { number in
            available.first { $0.nativeProcessID == processID && $0.nativeWindowNumber == number }
        }
        let candidates = available.filter { candidate in
            guard !liveIDs.contains(candidate.id) else { return false }
            // A different native ID in the same process is a different window,
            // even if its title, identifier, ordinal, and frame are identical.
            if let nativeNumber,candidate.nativeProcessID == processID,
               let oldNumber = candidate.nativeWindowNumber,oldNumber != nativeNumber { return false }
            return true
        }
        let matchedID = compatibleSession == nil && native == nil
            ? WindowMatcher.match(fingerprint,candidates: candidates.map { ($0.id,$0.fingerprint) }) : nil
        var record = compatibleSession ?? native ?? candidates.first { $0.id == matchedID }
            ?? WindowRecord(id: UUID().uuidString,bundleID: fingerprint.bundle,app: app,title: fingerprint.title,
                            ordinal: fingerprint.ordinal,originalFrame: fingerprint.frame)
        record.title = fingerprint.title; record.ordinal = fingerprint.ordinal
        record.axIdentifier = fingerprint.identifier; record.document = fingerprint.document
        // Only a real native lookup or exact session continuity can carry a
        // native ID. A title/geometry match cannot establish WindowServer identity.
        record.nativeWindowNumber = nativeNumber ?? compatibleSession?.nativeWindowNumber
        record.nativeProcessID = record.nativeWindowNumber == nil ? nil : processID
        return record
    }
}
