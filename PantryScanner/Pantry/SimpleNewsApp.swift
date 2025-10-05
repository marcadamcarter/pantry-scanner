// Pantry Scanner Starter
// iOS 17+, SwiftUI + VisionKit (DataScanner) + SwiftData
// Notes: Add the following to Info.plist:
//  - Privacy - Camera Usage Description (NSCameraUsageDescription): "We use the camera to scan barcodes and expiration dates."
// Target -> Signing & Capabilities: add iCloud with "CloudKit" later if you want sync.

import SwiftUI
import VisionKit
import SwiftData

// MARK: - Models (SwiftData)
@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?
    var size: String?
    var barcode: String?
    var location: String // Pantry, Fridge, Freezer
    var qtyOnHand: Int
    var qtyPar: Int
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var lots: [Lot]

    init(id: UUID = UUID(), name: String = "", brand: String? = nil, size: String? = nil,
         barcode: String? = nil, location: String = "Pantry", qtyOnHand: Int = 1, qtyPar: Int = 0,
         createdAt: Date = .now, updatedAt: Date = .now, lots: [Lot] = []) {
        self.id = id
        self.name = name
        self.brand = brand
        self.size = size
        self.barcode = barcode
        self.location = location
        self.qtyOnHand = qtyOnHand
        self.qtyPar = qtyPar
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lots = lots
    }
}

@Model
final class Lot {
    @Attribute(.unique) var id: UUID
    var expirationDate: Date?
    var openedAt: Date?
    var notes: String?
    @Relationship(inverse: \Item.lots) var item: Item?

    init(id: UUID = UUID(), expirationDate: Date? = nil, openedAt: Date? = nil, notes: String? = nil, item: Item? = nil) {
        self.id = id
        self.expirationDate = expirationDate
        self.openedAt = openedAt
        self.notes = notes
        self.item = item
    }
}

// MARK: - Date Parsing Helper
enum DateParser {
    static let patterns: [String] = [
        #"(\b\d{4}-\d{2}-\d{2}\b)"#,        // YYYY-MM-DD
        #"(\b\d{1,2}/\d{1,2}/\d{2,4}\b)"#,  // MM/DD/YY(YY)
        #"(?i)best\s*by[:\s-]*([A-Za-z]{3,9}\s+\d{1,2},\s*\d{2,4})"# // Best by Month DD, YYYY
    ]

    static func parseFirstDate(in text: String) -> Date? {
        for pat in patterns {
            if let range = text.range(of: pat, options: .regularExpression) {
                let raw = String(text[range])
                let cleaned = raw.replacingOccurrences(of: "Best by", with: "", options: .caseInsensitive)
                if let d = flexibleParse(cleaned.trimmingCharacters(in: .whitespacesAndNewlines)) { return d }
            }
        }
        return nil
    }

    private static func flexibleParse(_ s: String) -> Date? {
        let fmts = ["yyyy-MM-dd", "M/d/yy", "MM/dd/yyyy", "MMM d, yyyy", "MMMM d, yyyy"]
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = .current
        for f in fmts { df.dateFormat = f; if let d = df.date(from: s) { return d } }
        return nil
    }
}

// MARK: - Barcode Lookup (stub)
actor BarcodeLookupService {
    struct Product: Codable { let name: String; let brand: String?; let size: String? }

    private var cache: [String: Product] = [:]

    func lookup(code: String) async -> Product? {
        if let cached = cache[code] { return cached }
        // TODO: Integrate Open Food Facts or your preferred API.
        // For now, return some mocked data patterns so you can demo quickly.
        let mocked: [String: Product] = [
            "012345678905": .init(name: "Tomato Soup", brand: "Acme", size: "10.75 oz"),
            "041898123456": .init(name: "Pasta Shells", brand: "Casa Viva", size: "16 oz"),
            "071234500001": .init(name: "Whole Milk", brand: "Lone Star", size: "1 gal")
        ]
        if let m = mocked[code] { cache[code] = m; return m }
        return nil
    }
}

// MARK: - Scanner (VisionKit)
struct ScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onBarcode: (String) -> Void
        var onDate: (Date) -> Void
        init(onBarcode: @escaping (String)->Void, onDate: @escaping (Date)->Void) {
            self.onBarcode = onBarcode; self.onDate = onDate
        }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                switch item {
                case .barcode(let code):
                    if let payload = code.payloadStringValue { onBarcode(payload) }
                case .text(let text):
                    if let date = DateParser.parseFirstDate(in: text.transcript) { onDate(date) }
                default: break
                }
            }
        }
    }

    var onBarcode: (String)->Void
    var onDate: (Date)->Void

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode, onDate: onDate) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .upce, .ean8, .code128, .code39, .qr]),
                .text()
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
}

// MARK: - Views
struct InventoryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Item.updatedAt, order: .reverse) private var items: [Item]
    @State private var search = ""
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { item in
                        NavigationLink(value: item.id) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name.isEmpty ? "(Unnamed Item)" : item.name)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        if let brand = item.brand, !brand.isEmpty { Text(brand).foregroundStyle(.secondary) }
                                        if let size = item.size, !size.isEmpty { Text(size).foregroundStyle(.secondary) }
                                    }
                                    if let soon = soonestExpiration(for: item) {
                                        Text("Expires: \(soon.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.subheadline)
                                            .foregroundStyle(colorFor(expiration: soon))
                                    } else {
                                        Text("No expiration set").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Qty: \(item.qtyOnHand)").bold()
                                    if item.qtyPar > 0 && item.qtyOnHand < item.qtyPar {
                                        Text("Low").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(.yellow.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Pantry")
            .searchable(text: $search, prompt: "Search ‘milk’, ‘soup’, barcode…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showAdd) { AddItemView() }
            .navigationDestination(for: UUID.self) { id in
                if let item = items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item)
                }
            }
        }
    }

    private var filtered: [Item] {
        guard !search.isEmpty else { return items }
        let q = search.lowercased()
        return items.filter { i in
            i.name.lowercased().contains(q) || (i.brand?.lowercased().contains(q) ?? false) || (i.barcode?.contains(q) ?? false)
        }
    }

    private func soonestExpiration(for item: Item) -> Date? {
        item.lots.compactMap { $0.expirationDate }.sorted().first
    }

    private func colorFor(expiration: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: .now, to: expiration).day ?? 999
        if days < 0 { return .red }
        if days <= 7 { return .orange }
        return .secondary
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { ctx.delete(items[i]) }
        try? ctx.save()
    }
}

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var name = ""
    @State private var brand = ""
    @State private var size = ""
    @State private var barcode = ""
    @State private var location = "Pantry"
    @State private var qtyOnHand = 1
    @State private var qtyPar = 0
    @State private var expDate: Date? = nil

    @State private var isScanning = true
    private let lookup = BarcodeLookupService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if DataScannerViewController.isSupported && isScanning {
                    ScannerView(onBarcode: { code in
                        barcode = code
                        Task { await autoFill(from: code) }
                    }, onDate: { date in
                        expDate = date
                    })
                    .frame(height: 320)
                    .overlay(alignment: .topLeading) {
                        Label("Scan barcode + date", systemImage: "camera.viewfinder").padding(8).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 10)).padding(8)
                    }
                } else {
                    ContentUnavailableView("Scanner unavailable", systemImage: "camera.slash", description: Text("Use the form below."))
                        .frame(height: 320)
                }

                Form {
                    Section("Product") {
                        TextField("Name", text: $name)
                        TextField("Brand", text: $brand)
                        TextField("Size", text: $size)
                        TextField("Barcode", text: $barcode)
                    }
                    Section("Stock") {
                        Stepper("Quantity: \(qtyOnHand)", value: $qtyOnHand, in: 0...999)
                        Stepper("Par level: \(qtyPar)", value: $qtyPar, in: 0...99)
                        Picker("Location", selection: $location) {
                            Text("Pantry").tag("Pantry"); Text("Fridge").tag("Fridge"); Text("Freezer").tag("Freezer")
                        }
                    }
                    Section("Expiration") {
                        DatePicker("Expiration", selection: Binding($expDate, Date()), displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private func autoFill(from code: String) async {
        if let product = await lookup.lookup(code: code) {
            if name.isEmpty { name = product.name }
            if brand.isEmpty { brand = product.brand ?? "" }
            if size.isEmpty { size = product.size ?? "" }
        }
    }

    private func save() {
        let item = Item(name: name, brand: brand.isEmpty ? nil : brand, size: size.isEmpty ? nil : size,
                        barcode: barcode.isEmpty ? nil : barcode, location: location, qtyOnHand: qtyOnHand, qtyPar: qtyPar,
                        createdAt: .now, updatedAt: .now)
        if expDate != nil { item.lots.append(Lot(expirationDate: expDate)) }
        ctx.insert(item)
        try? ctx.save()
        dismiss()
    }
}

struct ItemDetailView: View {
    @Environment(\.modelContext) private var ctx
    @State var item: Item
    @State private var newExp: Date = .now

    var body: some View {
        Form {
            Section("Info") {
                TextField("Name", text: Binding(get: { item.name }, set: { item.name = $0 }))
                TextField("Brand", text: Binding(get: { item.brand ?? "" }, set: { item.brand = $0.isEmpty ? nil : $0 }))
                TextField("Size", text: Binding(get: { item.size ?? "" }, set: { item.size = $0.isEmpty ? nil : $0 }))
                TextField("Barcode", text: Binding(get: { item.barcode ?? "" }, set: { item.barcode = $0.isEmpty ? nil : $0 }))
                Picker("Location", selection: Binding(get: { item.location }, set: { item.location = $0 })) {
                    Text("Pantry").tag("Pantry"); Text("Fridge").tag("Fridge"); Text("Freezer").tag("Freezer")
                }
                Stepper("Quantity: \(item.qtyOnHand)", value: Binding(get: { item.qtyOnHand }, set: { item.qtyOnHand = $0 }), in: 0...999)
                Stepper("Par level: \(item.qtyPar)", value: Binding(get: { item.qtyPar }, set: { item.qtyPar = $0 }), in: 0...99)
            }
            Section("Lots & Expiration") {
                if item.lots.isEmpty { Text("No lots yet.").foregroundStyle(.secondary) }
                ForEach(item.lots) { lot in
                    HStack {
                        Text(lot.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        Spacer()
                        Button(role: .destructive) { ctx.delete(lot); try? ctx.save() } label: { Image(systemName: "trash") }
                    }
                }
                DatePicker("New expiration", selection: $newExp, displayedComponents: .date)
                Button("Add lot") { item.lots.append(Lot(expirationDate: newExp, item: item)); try? ctx.save() }
            }
        }
        .navigationTitle(item.name.isEmpty ? "Item" : item.name)
        .onDisappear { try? ctx.save() }
    }
}

// MARK: - App Entry
@main
struct PantryScannerApp: App {
    var body: some Scene {
        WindowGroup {
            InventoryView()
        }
        .modelContainer(for: [Item.self, Lot.self])
    }
}
