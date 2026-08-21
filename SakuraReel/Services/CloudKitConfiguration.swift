import Foundation
import CloudKit
import SwiftData

enum CloudKitConfiguration {
    static let containerIdentifier = "iCloud.com.yourdomain.SakuraReel"

    static var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    static func checkAccountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }
}
