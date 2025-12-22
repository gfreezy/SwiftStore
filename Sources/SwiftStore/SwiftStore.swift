@_exported import SwiftStoreCore
@_exported import SwiftStoreChangeTracker
@_exported import SwiftStoreSync
@_exported import SwiftStoreConnectionQueue


@Entity
struct User {
    #Index<Self>(\.name)
    var id: UUIDV4
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

struct Size: Codable {
    let width: Int
    let height: Int
}

struct Pic: Codable {
    let ident: String
    let size: Size
}

@Entity
struct UserPosts {
    #SyncKey<Self>(\.name)
    var name: String = "hoyo"
    var content: String
    var image: Pic = Pic(ident: "ident", size: .init(width: 10, height: 10))
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
