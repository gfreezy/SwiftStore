import SwiftStoreCore

@Entity
public struct Person {
    public var id: UUIDV7 = UUIDV7()
    public var displayName: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
}
