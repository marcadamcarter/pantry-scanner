// Pantry Scanner
// iOS 17+, SwiftUI + VisionKit (DataScanner) + SwiftData
// Camera usage description is supplied by the Xcode build settings.
// Target -> Signing & Capabilities: add iCloud with "CloudKit" later if you want sync.

import SwiftUI
import VisionKit
import SwiftData
import UserNotifications
import AVFoundation

// MARK: - Models (SwiftData)
@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var name: String
    var brand: String?
    var size: String?
    var barcode: String?
    var imageURL: String?
    var location: String // Pantry, Fridge, Freezer
    var qtyOnHand: Int
    var qtyPar: Int
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var lots: [Lot]

    init(id: UUID = UUID(), name: String = "", brand: String? = nil, size: String? = nil,
         barcode: String? = nil, imageURL: String? = nil, location: String = "Pantry", qtyOnHand: Int = 1, qtyPar: Int = 0,
         createdAt: Date = .now, updatedAt: Date = .now, lots: [Lot] = []) {
        self.id = id
        self.name = name
        self.brand = brand
        self.size = size
        self.barcode = barcode
        self.imageURL = imageURL
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

// MARK: - Barcode Lookup (Open Food Facts)
actor BarcodeLookupService {
    struct Product { let name: String; let brand: String?; let size: String?; let imageURL: String? }

    private var cache: [String: Product] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func lookup(code: String) async throws -> Product? {
        if let cached = cache[code] { return cached }

        guard let escapedCode = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(escapedCode).json") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("PantryScanner/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { return nil }
        guard (200...299).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? Int == 1,
              let productDict = json["product"] as? [String: Any] else {
            return nil
        }

        let name = productDict["product_name"] as? String
        guard let name, !name.isEmpty else { return nil }

        let brand = productDict["brands"] as? String
        let quantity = productDict["quantity"] as? String

        let product = Product(name: name, brand: brand, size: quantity,
                              imageURL: productDict["image_front_small_url"] as? String)
        cache[code] = product
        return product
    }
}

// MARK: - Notification Manager
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleNotifications(for item: Item) {
        let itemName = item.name.isEmpty ? "Item" : item.name
        for lot in item.lots {
            guard let exp = lot.expirationDate else { continue }
            schedule(itemID: item.id, lotID: lot.id, itemName: itemName, expirationDate: exp, daysBefore: 3,
                     body: "⏰ \(itemName) expires in 3 days")
            schedule(itemID: item.id, lotID: lot.id, itemName: itemName, expirationDate: exp, daysBefore: 0,
                     body: "🚨 \(itemName) expires today!")
        }
    }

    func cancelNotifications(for item: Item) {
        cancelNotifications(itemID: item.id)
    }

    func cancelNotifications(itemID: UUID) {
        let prefix = "pantry-\(itemID.uuidString)"
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func rescheduleAll(items: [Item]) {
        center.removeAllPendingNotificationRequests()
        for item in items {
            scheduleNotifications(for: item)
        }
    }

    private func schedule(itemID: UUID, lotID: UUID, itemName: String, expirationDate: Date, daysBefore: Int, body: String) {
        guard let targetDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: expirationDate) else { return }

        // Don't schedule notifications in the past
        var components = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        components.hour = 9
        components.minute = 0

        if let fireDate = Calendar.current.date(from: components), fireDate <= .now { return }

        let content = UNMutableNotificationContent()
        content.title = "Pantry Scanner"
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "pantry-\(itemID.uuidString)-\(lotID.uuidString)-\(daysBefore)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}

// MARK: - Scanner (VisionKit)
struct ScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onBarcode: (String) -> Void
        var onDate: (Date) -> Void
        var onUnavailable: () -> Void
        init(onBarcode: @escaping (String)->Void, onDate: @escaping (Date)->Void,
             onUnavailable: @escaping () -> Void) {
            self.onBarcode = onBarcode; self.onDate = onDate
            self.onUnavailable = onUnavailable
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

        func dataScanner(_ scanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onUnavailable()
        }
    }

    var onUnavailable: () -> Void
    var onBarcode: (String)->Void
    var onDate: (Date)->Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode, onDate: onDate, onUnavailable: onUnavailable)
    }

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
        do {
            try vc.startScanning()
        } catch {
            DispatchQueue.main.async { context.coordinator.onUnavailable() }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.onBarcode = onBarcode
        context.coordinator.onDate = onDate
        context.coordinator.onUnavailable = onUnavailable
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
}

// MARK: - Views
enum InventoryCategory: String, CaseIterable, Identifiable {
    case inStock = "In Stock"
    case lowStock = "Low Stock"
    case expiringSoon = "Expiring Soon"
    case outOfStock = "Out of Stock"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inStock: return "shippingbox"
        case .lowStock: return "exclamationmark.circle"
        case .expiringSoon: return "clock"
        case .outOfStock: return "cart"
        }
    }

    func includes(_ item: Item, now: Date = .now) -> Bool {
        switch self {
        case .inStock: return item.qtyOnHand > 0
        case .lowStock: return item.qtyPar > 0 && item.qtyOnHand < item.qtyPar
        case .outOfStock: return item.qtyOnHand == 0
        case .expiringSoon:
            let today = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: 8, to: today) ?? today
            return item.qtyOnHand > 0 && item.lots.contains {
                guard let date = $0.expirationDate else { return false }
                return date >= today && date < end
            }
        }
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.imageURL.flatMap { URL(string: $0) }) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            Text(item.name.isEmpty ? "Unnamed Item" : item.name)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text("Qty: \(item.qtyOnHand)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct InventoryView: View {
    var body: some View {
        NavigationStack {
            InventoryListView()
        }
    }
}

struct InventoryListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Item.updatedAt, order: .reverse) private var items: [Item]
    @State private var search = ""
    @State private var showAdd = false
    @State private var deletionFailed = false
    var category: InventoryCategory? = nil

    var body: some View {
        List {
            if category == nil {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(InventoryCategory.allCases) { category in
                            NavigationLink {
                                InventoryListView(category: category)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(category.rawValue, systemImage: category.symbol)
                                        .font(.subheadline)
                                    Text(items.filter { category.includes($0) }.count, format: .number)
                                        .font(.title2.bold())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section(category?.rawValue ?? "All Items") {
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No items" : "No matches",
                                           systemImage: "shippingbox",
                                           description: Text(search.isEmpty ? "Items in this category will appear here." : "Try another search."))
                }
                ForEach(filtered) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        ItemRow(item: item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(category?.rawValue ?? "Pantry")
        .searchable(text: $search, prompt: "Search pantry")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add item")
            }
        }
        .sheet(isPresented: $showAdd) { AddItemView() }
        .alert("Couldn’t remove item", isPresented: $deletionFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your item was kept. Please try again.")
        }
    }

    private var filtered: [Item] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            (category?.includes(item) ?? true) && (query.isEmpty ||
                item.name.localizedCaseInsensitiveContains(query) ||
                (item.brand?.localizedCaseInsensitiveContains(query) ?? false) ||
                (item.barcode?.contains(query) ?? false))
        }
    }

    private func delete(_ item: Item) {
        let itemID = item.id
        ctx.delete(item)
        do {
            try ctx.save()
            NotificationManager.shared.cancelNotifications(itemID: itemID)
        } catch {
            ctx.rollback()
            deletionFailed = true
        }
    }
}
enum ScanStatus: Equatable {
    case searching, lookingUp, found, notFound, failed

    var message: String {
        switch self {
        case .searching: return "Looking for a barcode…"
        case .lookingUp: return "Barcode recognized. Looking up product…"
        case .found: return "Product found. Review and save."
        case .notFound: return "Product not found. Enter its name below."
        case .failed: return "Lookup failed. Retry or enter details below."
        }
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
    @State private var imageURL: String?

    @State private var cameraReady = false
    @State private var cameraUnavailable = false
    @State private var scanStatus = ScanStatus.searching
    @State private var acceptedBarcode: String?
    @State private var lookupRequestID: UUID?
    @State private var scannerSessionID = UUID()
    @State private var saveFailed = false
    @State private var lookup = BarcodeLookupService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cameraReady && !cameraUnavailable {
                    ScannerView(onUnavailable: { cameraUnavailable = true }, onBarcode: { code in
                        guard acceptedBarcode == nil, barcode.isEmpty else { return }
                        beginLookup(code)
                    }, onDate: { date in
                        expDate = date
                    })
                    .id(scannerSessionID)
                    .frame(height: 240)
                } else if !cameraUnavailable {
                    ProgressView("Starting camera…").frame(height: 240)
                } else {
                    ContentUnavailableView("Scanner unavailable", systemImage: "camera.slash", description: Text("Use the form below."))
                        .frame(height: 240)
                }

                scanFeedback

                Form {
                    Section("Product") {
                        TextField("Name", text: $name)
                        TextField("Brand", text: $brand)
                        TextField("Size", text: $size)
                        TextField("Barcode", text: $barcode)
                            .onChange(of: barcode) { _, newValue in
                                if newValue != acceptedBarcode { imageURL = nil }
                            }
                        if !barcode.isEmpty && barcode != acceptedBarcode {
                            Button("Look up barcode") { beginLookup(barcode) }
                        }
                    }
                    .disabled(scanStatus == .lookingUp)
                    Section("Stock") {
                        Stepper("Quantity: \(qtyOnHand)", value: $qtyOnHand, in: 0...999)
                        Stepper("Par level: \(qtyPar)", value: $qtyPar, in: 0...99)
                        Picker("Location", selection: $location) {
                            Text("Pantry").tag("Pantry"); Text("Fridge").tag("Fridge"); Text("Freezer").tag("Freezer")
                        }
                    }
                    Section("Expiration") {
                        Toggle("Track expiration", isOn: Binding(
                            get: { expDate != nil },
                            set: { expDate = $0 ? (expDate ?? .now) : nil }
                        ))
                        if expDate != nil {
                            DatePicker("Expiration", selection: Binding(
                                get: { expDate ?? .now }, set: { expDate = $0 }
                            ), displayedComponents: .date)
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scanStatus == .lookingUp)
                }
            }
            .task {
                guard DataScannerViewController.isSupported else {
                    cameraUnavailable = true
                    return
                }
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                cameraReady = granted && DataScannerViewController.isAvailable
                cameraUnavailable = !cameraReady
            }
            .task(id: lookupRequestID) {
                guard lookupRequestID != nil, let code = acceptedBarcode else { return }
                await autoFill(from: code)
            }
            .alert("Couldn’t save item", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your entries are still here. Please try again.")
            }
        }
    }

    private var scanFeedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if scanStatus == .lookingUp || (scanStatus == .searching && cameraReady && !cameraUnavailable) {
                    ProgressView()
                }
                Text(scanStatus == .searching && cameraUnavailable ? "Enter product details manually." : scanStatus.message)
                    .font(.subheadline)
            }
            if scanStatus == .failed || scanStatus == .notFound {
                Button("Retry lookup") {
                    beginLookup(barcode)
                }
            }
            if acceptedBarcode != nil {
                Button("Scan again") {
                    lookupRequestID = nil
                    acceptedBarcode = nil
                    barcode = ""
                    name = ""
                    brand = ""
                    size = ""
                    imageURL = nil
                    expDate = nil
                    scanStatus = .searching
                    scannerSessionID = UUID()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
    }

    private func beginLookup(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        if let previousCode = acceptedBarcode, previousCode != code {
            name = ""
            brand = ""
            size = ""
            expDate = nil
        }
        imageURL = nil
        acceptedBarcode = code
        barcode = code
        scanStatus = .lookingUp
        lookupRequestID = UUID()
    }

    @MainActor
    private func autoFill(from code: String) async {
        do {
            let product = try await lookup.lookup(code: code)
            guard !Task.isCancelled, acceptedBarcode == code else { return }
            if let product {
                if name.isEmpty { name = product.name }
                if brand.isEmpty { brand = product.brand ?? "" }
                if size.isEmpty { size = product.size ?? "" }
                imageURL = product.imageURL
                scanStatus = .found
            } else {
                scanStatus = .notFound
            }
        } catch {
            guard !Task.isCancelled, acceptedBarcode == code else { return }
            scanStatus = .failed
        }
    }

    private func save() {
        let item = Item(name: name, brand: brand.isEmpty ? nil : brand, size: size.isEmpty ? nil : size,
                        barcode: barcode.isEmpty ? nil : barcode, imageURL: imageURL,
                        location: location, qtyOnHand: qtyOnHand, qtyPar: qtyPar,
                        createdAt: .now, updatedAt: .now)
        if expDate != nil { item.lots.append(Lot(expirationDate: expDate)) }
        ctx.insert(item)
        do {
            try ctx.save()
            NotificationManager.shared.scheduleNotifications(for: item)
            dismiss()
        } catch {
            ctx.rollback()
            saveFailed = true
        }
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
                        Button(role: .destructive) {
                            ctx.delete(lot)
                            try? ctx.save()
                            NotificationManager.shared.cancelNotifications(for: item)
                            NotificationManager.shared.scheduleNotifications(for: item)
                        } label: { Image(systemName: "trash") }
                    }
                }
                DatePicker("New expiration", selection: $newExp, displayedComponents: .date)
                Button("Add lot") {
                    item.lots.append(Lot(expirationDate: newExp, item: item))
                    try? ctx.save()
                    NotificationManager.shared.cancelNotifications(for: item)
                    NotificationManager.shared.scheduleNotifications(for: item)
                }
            }
        }
        .navigationTitle(item.name.isEmpty ? "Item" : item.name)
        .onDisappear { try? ctx.save() }
    }
}

// MARK: - App Entry
@main
struct PantryScannerApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(for: Item.self, Lot.self)
        NotificationManager.shared.requestPermission()
        let context = container.mainContext
        let descriptor = FetchDescriptor<Item>()
        if let items = try? context.fetch(descriptor) {
            NotificationManager.shared.rescheduleAll(items: items)
        }
    }

    var body: some Scene {
        WindowGroup {
            InventoryView()
        }
        .modelContainer(container)
    }
}
