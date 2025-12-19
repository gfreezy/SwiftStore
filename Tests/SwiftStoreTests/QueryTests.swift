import Testing
import Foundation
@testable import SwiftStore

@Suite("Query Builder Tests")
struct QueryBuilderTests {
    @Test("Order by clause")
    func testOrderBy() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 30,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 25,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date().addingTimeInterval(1),
            updatedAt: Date().addingTimeInterval(1)
        )

        try store.insert(user1)
        try store.insert(user2)

        let ordered = try store.fetch(TestUser.self)
            .order(by: \.name, ascending: true)
            .all()

        #expect(ordered.count == 2)
        #expect(ordered.first?.name == "Alice")
    }

    @Test("Limit and offset")
    func testLimitOffset() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        for i in 0..<5 {
            let user = TestUser(
                id: UUIDV4(),
                name: "User\(i)",
                email: "user\(i)@example.com",
                age: 20 + i,
                address: Address(street: "\(i) Main St", city: "City", zipCode: "10000\(i)"),
                createdAt: Date(),
                updatedAt: Date()
            )
            try store.insert(user)
        }

        let limited = try store.fetch(TestUser.self)
            .limit(2)
            .all()

        #expect(limited.count == 2)

        let offsetted = try store.fetch(TestUser.self)
            .limit(2)
            .offset(2)
            .all()

        #expect(offsetted.count == 2)
    }

    @Test("First query")
    func testFirst() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        let first = try store.fetch(TestUser.self).first()
        #expect(first != nil)
        #expect(first?.name == "Alice")
    }

    @Test("Exists query")
    func testExists() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let existsBefore = try store.fetch(TestUser.self).exists()
        #expect(existsBefore == false)

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        let existsAfter = try store.fetch(TestUser.self).exists()
        #expect(existsAfter == true)
    }

    @Test("UpdateAll with KeyPath assignments")
    func testUpdateAll() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 30,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user1)
        try store.insert(user2)

        // Update all users with age >= 25 to age 100 (KeyPath syntax)
        let updated = try store.fetch(TestUser.self)
            .filter(\TestUser.age >= 25)
            .updateAll([\TestUser.age <- 100])

        #expect(updated == 2)

        var users = try store.fetch(TestUser.self).all()
        #expect(users.allSatisfy { $0.age == 100 })

        // Update using closure syntax with .set()
        let updated2 = try store.fetch(TestUser.self)
            .filter { $0.age == 100 }
            .updateAll { $0.age.set(50) }

        #expect(updated2 == 2)

        users = try store.fetch(TestUser.self).all()
        #expect(users.allSatisfy { $0.age == 50 })

        // Test += operator
        let updated3 = try store.fetch(TestUser.self)
            .filter { $0.age == 50 }
            .updateAll { $0.age += 10 }

        #expect(updated3 == 2)

        users = try store.fetch(TestUser.self).all()
        #expect(users.allSatisfy { $0.age == 60 })

        // Test multiple updates with result builder
        let updated4 = try store.fetch(TestUser.self)
            .filter { $0.age == 60 && $0.name == "Alice" }
            .updateAll {
                $0.age.set(99)
                $0.name.set("Alice Updated")
            }

        #expect(updated4 == 1)

        let alice = try store.fetch(TestUser.self)
            .filter { $0.name == "Alice Updated" }
            .first()
        #expect(alice?.age == 99)

        // Test complex filter with || and multiple updates
        let updated5 = try store.fetch(TestUser.self)
            .filter { $0.name == "Alice Updated" || $0.name == "Bob" }
            .updateAll {
                $0.age -= 9
            }

        #expect(updated5 == 2)
    }

    @Test("DeleteAll")
    func testDeleteAll() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        for i in 0..<5 {
            let user = TestUser(
                id: UUIDV4(),
                name: "User\(i)",
                email: "user\(i)@example.com",
                age: 20 + i,
                address: Address(street: "\(i) Main St", city: "City", zipCode: "10000\(i)"),
                createdAt: Date(),
                updatedAt: Date()
            )
            try store.insert(user)
        }

        // Delete users with age >= 23
        let deleted = try store.fetch(TestUser.self)
            .filter(\TestUser.age >= 23)
            .deleteAll()

        #expect(deleted == 2)

        let remaining = try store.fetch(TestUser.self).count()
        #expect(remaining == 3)
    }

    @Test("Filter alias for where")
    func testFilterAlias() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        // Test filter with KeyPath predicate (no closure)
        let result = try store.fetch(TestUser.self)
            .filter(\TestUser.name == "Alice")
            .first()

        #expect(result != nil)
        #expect(result?.name == "Alice")

        // Test filter with closure syntax
        let result2 = try store.fetch(TestUser.self)
            .filter { $0.name == "Alice" }
            .first()

        #expect(result2 != nil)
    }

    @Test("Filter with && and || operators")
    func testFilterLogicalOperators() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 30,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user3 = TestUser(
            id: UUIDV4(),
            name: "Charlie",
            email: "charlie@example.com",
            age: 20,
            address: Address(street: "789 Pine Rd", city: "Guangzhou", zipCode: "510000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user1)
        try store.insert(user2)
        try store.insert(user3)

        // Test && operator
        let andResult = try store.fetch(TestUser.self)
            .filter { $0.age >= 25 && $0.name == "Alice" }
            .all()

        #expect(andResult.count == 1)
        #expect(andResult.first?.name == "Alice")

        // Test || operator
        let orResult = try store.fetch(TestUser.self)
            .filter { $0.name == "Alice" || $0.name == "Bob" }
            .all()

        #expect(orResult.count == 2)

        // Test ! operator
        let notResult = try store.fetch(TestUser.self)
            .filter { !($0.name == "Alice") }
            .all()

        #expect(notResult.count == 2)
        #expect(notResult.allSatisfy { $0.name != "Alice" })
    }

    @Test("SQL interpolation with values")
    func testSQLInterpolation() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        // Test SQL interpolation with value parameters
        let newName = "Alice Updated"
        let minAge = 20
        let sql: SQL = "UPDATE \(TestUser.self) SET \(\TestUser.name) = \(newName) WHERE \(\TestUser.age) >= \(minAge)"
        try store.execute(sql)

        let updated = try store.fetch(TestUser.self).first()
        #expect(updated?.name == "Alice Updated")

        // Test query with SQL interpolation
        let rows = try store.query(
            "SELECT \(\TestUser.name), \(\TestUser.age) FROM \(TestUser.self)" as SQL
        )
        #expect(rows.count == 1)

        // Test with multiple value types
        let newAge = 30
        let sql2: SQL = "UPDATE \(TestUser.self) SET \(\TestUser.age) = \(newAge) WHERE \(\TestUser.name) = \(newName)"
        try store.execute(sql2)

        let updated2 = try store.fetch(TestUser.self).first()
        #expect(updated2?.age == 30)
    }

    @Test("SQL interpolation with different types")
    func testSQLInterpolationTypes() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let userId = UUIDV4()
        let user = TestUser(
            id: userId,
            name: "Bob",
            email: "bob@example.com",
            age: 35,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        // Test with Bool
        let isActive = true
        let sqlBool: SQL = "SELECT * FROM \(TestUser.self) WHERE \(isActive)"
        #expect(sqlBool.sql == "SELECT * FROM test_user WHERE ?")
        #expect(sqlBool.values.count == 1)

        // Test with Double
        let score = 95.5
        let sqlDouble: SQL = "SELECT * FROM \(TestUser.self) WHERE score > \(score)"
        #expect(sqlDouble.values.first == .real(95.5))

        // Test with Date
        let date = Date(timeIntervalSince1970: 1000000)
        let sqlDate: SQL = "SELECT * FROM \(TestUser.self) WHERE created_at > \(date)"
        #expect(sqlDate.values.first == .real(1000000))

        // Test with UUIDV4
        let sqlUUID: SQL = "SELECT * FROM \(TestUser.self) WHERE \(\TestUser.id) = \(userId)"
        #expect(sqlUUID.sql == "SELECT * FROM test_user WHERE id = ?")

        // Test query execution with UUIDV4
        let rows = try store.query(sqlUUID)
        #expect(rows.count == 1)
    }

    @Test("SQL raw interpolation")
    func testSQLRawInterpolation() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        for i in 0..<3 {
            let user = TestUser(
                id: UUIDV4(),
                name: "User\(i)",
                email: "user\(i)@example.com",
                age: 20 + i,
                address: Address(street: "\(i) Main St", city: "City", zipCode: "10000\(i)"),
                createdAt: Date(),
                updatedAt: Date()
            )
            try store.insert(user)
        }

        // Test raw interpolation for ORDER BY
        let orderColumn = "age"
        let sql: SQL = "SELECT * FROM \(TestUser.self) ORDER BY \(raw: orderColumn) DESC"
        #expect(sql.sql == "SELECT * FROM test_user ORDER BY age DESC")
        #expect(sql.values.isEmpty)

        let rows = try store.query(sql)
        #expect(rows.count == 3)
    }

    @Test("SQL queryOne and queryScalar")
    func testSQLQueryMethods() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user = TestUser(
            id: UUIDV4(),
            name: "Charlie",
            email: "charlie@example.com",
            age: 28,
            address: Address(street: "789 Pine Rd", city: "Guangzhou", zipCode: "510000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        // Test queryOne
        let name = "Charlie"
        let row = try store.queryOne("SELECT * FROM \(TestUser.self) WHERE \(\TestUser.name) = \(name)" as SQL)
        #expect(row != nil)
        #expect(row?["name"] == .text("Charlie"))

        // Test queryScalar (COUNT returns Int64)
        let count: Int64? = try store.queryScalar("SELECT COUNT(*) FROM \(TestUser.self)" as SQL)
        #expect(count == 1)

        // Test queryScalar with filter
        let minAge = 25
        let countFiltered: Int64? = try store.queryScalar(
            "SELECT COUNT(*) FROM \(TestUser.self) WHERE \(\TestUser.age) >= \(minAge)" as SQL
        )
        #expect(countFiltered == 1)

        // Test SELECT with value interpolation
        let rows = try store.query(
            "SELECT \(\TestUser.age) FROM \(TestUser.self) WHERE \(\TestUser.age) >= \(minAge)" as SQL
        )
        #expect(rows.count == 1)
        #expect(rows.first![\TestUser.age] == 28)
    }

    @Test("Filter with multiple KeyPath conditions")
    func testFilterMultipleKeyPathConditions() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let user1 = TestUser(
            id: UUIDV4(),
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 30,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        let user3 = TestUser(
            id: UUIDV4(),
            name: "Charlie",
            email: "charlie@example.com",
            age: 20,
            address: Address(street: "789 Pine Rd", city: "Guangzhou", zipCode: "510000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user1)
        try store.insert(user2)
        try store.insert(user3)

        // Test chained filter with KeyPath syntax
        let result1 = try store.fetch(TestUser.self)
            .filter(\TestUser.age >= 25)
            .filter(\TestUser.age <= 30)
            .all()
        #expect(result1.count == 2)

        // Test combined && with KeyPath syntax
        let result2 = try store.fetch(TestUser.self)
            .filter(\TestUser.age >= 25 && \TestUser.name == "Alice")
            .all()
        #expect(result2.count == 1)
        #expect(result2.first?.name == "Alice")

        // Test combined || with KeyPath syntax
        let result3 = try store.fetch(TestUser.self)
            .filter(\TestUser.name == "Alice" || \TestUser.name == "Bob")
            .all()
        #expect(result3.count == 2)

        // Test complex condition with KeyPath syntax
        let result4 = try store.fetch(TestUser.self)
            .filter((\TestUser.age >= 25 && \TestUser.age < 30) || \TestUser.name == "Charlie")
            .all()
        #expect(result4.count == 2)  // Alice (25) and Charlie (name match)
    }

    @Test("Row with KeyPath subscript")
    func testRowKeyPathSubscript() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        let userId = UUIDV4()
        let user = TestUser(
            id: userId,
            name: "Alice",
            email: "alice@example.com",
            age: 25,
            address: Address(street: "123 Main St", city: "Shanghai", zipCode: "200000"),
            createdAt: Date(),
            updatedAt: Date()
        )

        try store.insert(user)

        // Test query with KeyPath subscript
        let rows = try store.query("SELECT * FROM \(TestUser.self)" as SQL)
        #expect(rows.count == 1)

        let row = rows.first!
        let name: String = row[\TestUser.name]
        let age: Int? = row[\TestUser.age]  // age is optional in TestUser
        let id: UUIDV4 = row[\TestUser.id]

        #expect(name == "Alice")
        #expect(age == 25)
        #expect(id == userId)

        // Test get() for optional access
        let optionalName: String? = row.get(\TestUser.name)
        #expect(optionalName == "Alice")

        // Test queryOne (single row)
        let singleRow = try store.queryOne("SELECT * FROM \(TestUser.self) WHERE \(\TestUser.name) = \("Alice")" as SQL)
        #expect(singleRow != nil)
        #expect(singleRow![\TestUser.name] == "Alice")
        #expect(singleRow![\TestUser.age] == 25)

        // Test with multiple rows
        let user2 = TestUser(
            id: UUIDV4(),
            name: "Bob",
            email: "bob@example.com",
            age: 30,
            address: Address(street: "456 Oak Ave", city: "Beijing", zipCode: "100000"),
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.insert(user2)

        let allRows = try store.query("SELECT * FROM \(TestUser.self) ORDER BY \(raw: "age")" as SQL)
        #expect(allRows.count == 2)
        #expect(allRows[0][\TestUser.name] == "Alice")
        #expect(allRows[1][\TestUser.name] == "Bob")
    }

    @Test("Distinct query")
    func testDistinct() throws {
        let store = try createTestStore()
        try store.register(TestUser.self)
        try store.migrate()

        // Insert users with same age
        for i in 0..<3 {
            let user = TestUser(
                id: UUIDV4(),
                name: "User\(i)",
                email: "user\(i)@example.com",
                age: 25,  // Same age
                address: Address(street: "\(i) Main St", city: "City", zipCode: "10000\(i)"),
                createdAt: Date(),
                updatedAt: Date()
            )
            try store.insert(user)
        }

        // Distinct should work with select
        let query = store.fetch(TestUser.self)
            .distinct()
            .select("age")

        let (sql, _) = query.buildSQL()
        #expect(sql.contains("DISTINCT"))
    }
}
