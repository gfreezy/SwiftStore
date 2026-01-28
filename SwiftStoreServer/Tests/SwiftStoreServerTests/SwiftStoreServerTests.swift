import Testing
import Foundation
@testable import SwiftStoreServer

@Suite("SwiftStoreServer Tests")
struct SwiftStoreServerTests {

    @Suite("JSONValue Tests")
    struct JSONValueTests {

        @Test("JSONValue encodes null correctly")
        func encodeNull() throws {
            let value = JSONValue.null
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "null")
        }

        @Test("JSONValue encodes integer correctly")
        func encodeInteger() throws {
            let value = JSONValue.int(42)
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "42")
        }

        @Test("JSONValue encodes double correctly")
        func encodeDouble() throws {
            let value = JSONValue.double(3.14)
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "3.14")
        }

        @Test("JSONValue encodes string correctly")
        func encodeString() throws {
            let value = JSONValue.string("hello")
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "\"hello\"")
        }

        @Test("JSONValue encodes bool correctly")
        func encodeBool() throws {
            let value = JSONValue.bool(true)
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "true")
        }

        @Test("JSONValue encodes data as base64")
        func encodeData() throws {
            let data = Data([0x48, 0x65, 0x6c, 0x6c, 0x6f]) // "Hello"
            let value = JSONValue.data(data)
            let encoded = try JSONEncoder().encode(value)
            let json = String(data: encoded, encoding: .utf8)
            #expect(json == "\"SGVsbG8=\"") // Base64 of "Hello"
        }

        @Test("JSONValue encodes array correctly")
        func encodeArray() throws {
            let value = JSONValue.array([.int(1), .int(2), .int(3)])
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            #expect(json == "[1,2,3]")
        }

        @Test("JSONValue encodes object correctly")
        func encodeObject() throws {
            let value = JSONValue.object(["name": .string("John"), "age": .int(30)])
            let data = try JSONEncoder().encode(value)
            // Parse JSON to verify (order may vary)
            let parsed = try JSONDecoder().decode([String: JSONValue].self, from: data)
            #expect(parsed["name"] == .string("John"))
            #expect(parsed["age"] == .int(30))
        }

        @Test("JSONValue decodes correctly")
        func decodeValues() throws {
            let json = """
            {"name": "John", "age": 30, "active": true, "score": 95.5, "tags": ["a", "b"]}
            """
            let data = json.data(using: .utf8)!
            let value = try JSONDecoder().decode(JSONValue.self, from: data)

            if case .object(let dict) = value {
                #expect(dict["name"] == .string("John"))
                #expect(dict["age"] == .int(30))
                #expect(dict["active"] == .bool(true))
                #expect(dict["score"] == .double(95.5))
                #expect(dict["tags"] == .array([.string("a"), .string("b")]))
            } else {
                Issue.record("Expected object")
            }
        }
    }

    @Suite("ServerConfiguration Tests")
    struct ServerConfigurationTests {

        @Test("Default configuration values")
        func defaultValues() {
            let config = ServerConfiguration()
            #expect(config.host == "127.0.0.1")
            #expect(config.port == 8080)
            #expect(config.readOnly == false)
            #expect(config.maxPageSize == 1000)
            #expect(config.defaultPageSize == 50)
            #expect(config.enableCORS == true)
        }

        @Test("Custom configuration values")
        func customValues() {
            let config = ServerConfiguration(
                host: "0.0.0.0",
                port: 3000,
                readOnly: true,
                maxPageSize: 500,
                defaultPageSize: 25,
                enableCORS: false
            )
            #expect(config.host == "0.0.0.0")
            #expect(config.port == 3000)
            #expect(config.readOnly == true)
            #expect(config.maxPageSize == 500)
            #expect(config.defaultPageSize == 25)
            #expect(config.enableCORS == false)
        }
    }

    @Suite("PaginationInfo Tests")
    struct PaginationInfoTests {

        @Test("Total pages calculation")
        func totalPagesCalculation() {
            let pagination = PaginationInfo(page: 1, pageSize: 10, totalRows: 25)
            #expect(pagination.totalPages == 3)
        }

        @Test("Total pages with exact division")
        func totalPagesExact() {
            let pagination = PaginationInfo(page: 1, pageSize: 10, totalRows: 20)
            #expect(pagination.totalPages == 2)
        }

        @Test("Total pages with zero rows")
        func totalPagesZeroRows() {
            let pagination = PaginationInfo(page: 1, pageSize: 10, totalRows: 0)
            #expect(pagination.totalPages == 1)
        }
    }

    @Suite("HTTPRequest Parser Tests")
    struct HTTPRequestParserTests {

        @Test("Parse simple GET request")
        func parseGetRequest() throws {
            let raw = "GET /api/health HTTP/1.1\r\nHost: localhost\r\n\r\n"
            let request = try HTTPRequestParser.parse(Data(raw.utf8))

            #expect(request.method == .get)
            #expect(request.path == "/api/health")
            #expect(request.headers["host"] == "localhost")
        }

        @Test("Parse POST request with body")
        func parsePostRequest() throws {
            let body = """
            {"sql": "SELECT * FROM users"}
            """
            let raw = """
            POST /api/query HTTP/1.1\r
            Host: localhost\r
            Content-Type: application/json\r
            \r
            \(body)
            """
            let request = try HTTPRequestParser.parse(Data(raw.utf8))

            #expect(request.method == .post)
            #expect(request.path == "/api/query")
            #expect(request.headers["content-type"] == "application/json")
            #expect(request.body != nil)

            if request.body != nil {
                let decoded = try request.decodeBody(QueryRequest.self)
                #expect(decoded.sql == "SELECT * FROM users")
            }
        }

        @Test("Parse URL with query parameters")
        func parseQueryParams() throws {
            let raw = "GET /api/search?q=test&page=2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
            let request = try HTTPRequestParser.parse(Data(raw.utf8))

            #expect(request.path == "/api/search")
            #expect(request.queryParams["q"] == "test")
            #expect(request.queryParams["page"] == "2")
        }
    }

    @Suite("HTTPResponse Tests")
    struct HTTPResponseTests {

        @Test("Build simple response")
        func buildSimpleResponse() {
            let response = HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/plain"],
                body: Data("Hello".utf8)
            )

            let data = response.build()
            let string = String(data: data, encoding: .utf8)!

            #expect(string.contains("HTTP/1.1 200 OK"))
            #expect(string.contains("Content-Type: text/plain"))
            #expect(string.contains("Content-Length: 5"))
            #expect(string.contains("Hello"))
        }

        @Test("JSON response includes CORS headers")
        func jsonResponseCORS() {
            let response = HTTPResponse.json(["key": "value"], corsEnabled: true)

            let data = response.build()
            let string = String(data: data, encoding: .utf8)!

            #expect(string.contains("Access-Control-Allow-Origin: *"))
            #expect(string.contains("application/json"))
        }

        @Test("Error response format")
        func errorResponse() {
            let response = HTTPResponse.error("Something went wrong", status: .badRequest)

            #expect(response.status == .badRequest)

            let data = response.build()
            let string = String(data: data, encoding: .utf8)!

            #expect(string.contains("400 Bad Request"))
            #expect(string.contains("Something went wrong"))
        }
    }

    @Suite("QueryRequest Tests")
    struct QueryRequestTests {

        @Test("Decode query request")
        func decodeQueryRequest() throws {
            let json = """
            {
                "sql": "SELECT * FROM users WHERE status = ?",
                "params": ["active"],
                "page": 1,
                "pageSize": 20
            }
            """

            let request = try JSONDecoder().decode(QueryRequest.self, from: Data(json.utf8))

            #expect(request.sql == "SELECT * FROM users WHERE status = ?")
            #expect(request.params?.count == 1)
            #expect(request.page == 1)
            #expect(request.pageSize == 20)
        }

        @Test("Decode execute request")
        func decodeExecuteRequest() throws {
            let json = """
            {
                "sql": "INSERT INTO users (name) VALUES (?)",
                "params": ["Jane"]
            }
            """

            let request = try JSONDecoder().decode(ExecuteRequest.self, from: Data(json.utf8))

            #expect(request.sql == "INSERT INTO users (name) VALUES (?)")
            #expect(request.params?.count == 1)
        }
    }

    @Suite("QueryResponse Tests")
    struct QueryResponseTests {

        @Test("Success response encoding")
        func successResponseEncoding() throws {
            let response = QueryResponse.success(
                data: [.object(["id": .int(1), "name": .string("John")])],
                columns: ["id", "name"],
                pagination: PaginationInfo(page: 1, pageSize: 10, totalRows: 1)
            )

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)

            #expect(decoded.success == true)
            #expect(decoded.error == nil)
            #expect(decoded.rowCount == 1)
            #expect(decoded.columns == ["id", "name"])
            #expect(decoded.pagination?.page == 1)
        }

        @Test("Error response encoding")
        func errorResponseEncoding() throws {
            let response = QueryResponse.error("Invalid SQL")

            let data = try JSONEncoder().encode(response)
            let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)

            #expect(decoded.success == false)
            #expect(decoded.error == "Invalid SQL")
            #expect(decoded.data == nil)
        }
    }
}
