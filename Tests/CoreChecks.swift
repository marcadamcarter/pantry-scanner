import Foundation

// Model fixtures for the production category predicates.
struct Lot { var expirationDate: Date? }
struct Item {
    var qtyOnHand: Int
    var qtyPar: Int
    var lots: [Lot] = []
}

final class MockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { }

    override func startLoading() {
        let code = request.url!.deletingPathExtension().lastPathComponent
        if code == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let status = code == "server-error" ? 503 : (code == "missing" ? 404 : 200)
        let body: String
        switch code {
        case "known":
            body = #"{"status":1,"product":{"product_name":"Milk","brands":"Example","quantity":"1 L","image_front_small_url":"https://example.com/milk.jpg"}}"#
        case "unknown": body = #"{"status":0}"#
        case "unnamed": body = #"{"status":1,"product":{"product_name":""}}"#
        default: body = "invalid JSON"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct CoreChecks {
    static func main() async throws {
        let today = Calendar.current.startOfDay(for: .now)
        func date(_ days: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: days, to: today)!
        }
        let stocked = Item(qtyOnHand: 3, qtyPar: 2)
        let low = Item(qtyOnHand: 1, qtyPar: 2)
        let empty = Item(qtyOnHand: 0, qtyPar: 2)
        let untracked = Item(qtyOnHand: 0, qtyPar: 0)
        assert(InventoryCategory.inStock.includes(stocked))
        assert(InventoryCategory.inStock.includes(low))
        assert(!InventoryCategory.inStock.includes(empty))
        assert(!InventoryCategory.lowStock.includes(stocked))
        assert(!InventoryCategory.lowStock.includes(Item(qtyOnHand: 2, qtyPar: 2)))
        assert(InventoryCategory.lowStock.includes(low))
        assert(InventoryCategory.lowStock.includes(empty))
        assert(!InventoryCategory.lowStock.includes(untracked))
        assert(InventoryCategory.outOfStock.includes(empty))
        assert(!InventoryCategory.outOfStock.includes(low))
        for days in [-1, 0, 7, 8] {
            let item = Item(qtyOnHand: 1, qtyPar: 0, lots: [Lot(expirationDate: date(days))])
            assert(InventoryCategory.expiringSoon.includes(item, now: today) == (days == 0 || days == 7))
        }
        assert(!InventoryCategory.expiringSoon.includes(Item(qtyOnHand: 0, qtyPar: 1, lots: [Lot(expirationDate: today)])))
        assert(!InventoryCategory.expiringSoon.includes(stocked))
        let mixed = Item(qtyOnHand: 1, qtyPar: 0, lots: [Lot(expirationDate: nil), Lot(expirationDate: date(-1)), Lot(expirationDate: date(7))])
        assert(InventoryCategory.expiringSoon.includes(mixed, now: today))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let lookup = BarcodeLookupService(session: session)
        let product = try await lookup.lookup(code: "known")
        assert(product?.name == "Milk" && product?.brand == "Example" && product?.size == "1 L")
        assert(product?.imageURL == "https://example.com/milk.jpg")
        for code in ["missing", "unknown", "unnamed"] {
            let result = try await lookup.lookup(code: code)
            assert(result == nil, "Expected no product for \(code)")
        }
        for code in ["server-error", "offline", "malformed"] {
            do {
                _ = try await lookup.lookup(code: code)
                fatalError("Expected lookup error for \(code)")
            } catch { /* Errors must reach the UI, not masquerade as no match. */ }
        }
        print("PASS: category boundaries and lookup success, no match, HTTP, network, and malformed-response cases")
    }
}
