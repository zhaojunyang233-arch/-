import AppKit
import Combine
import ImageIO

enum HistoryRetention: Int, CaseIterable {
    case oneDay = 1
    case threeDays = 3
    case fiveDays = 5

    var interval: TimeInterval { TimeInterval(rawValue) * 24 * 60 * 60 }
}

@MainActor
final class ClipboardHistory: ObservableObject {
    enum PinChange {
        case handled
        case confirmExpiredRemoval
    }

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var needsPermission = false
    @Published private(set) var message: String?
    @Published private(set) var retention: HistoryRetention
    @Published var confirmsDeletion: Bool {
        didSet { defaults.set(confirmsDeletion, forKey: Self.confirmDeletionKey) }
    }

    private static let retentionKey = "historyRetentionDays"
    private static let confirmDeletionKey = "confirmHistoryDeletion"
    private static let restored = NSPasteboard.PasteboardType("local.clipboard-history.restored")
    private static let excludedTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL, restored, .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType")
    ]
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, .init("public.jpeg"), .init("com.compuserve.gif"),
        .init("public.heic"), .init("org.webmproject.webp")
    ]

    private let pasteboard: NSPasteboard
    private let storeURL: URL?
    private let defaults: UserDefaults
    private var store: HistoryStore?
    private var timer: Timer?
    private var lastChange: Int
    private var nextCleanup = Date.distantPast

    init(pasteboard: NSPasteboard, storeURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.storeURL = storeURL
        self.defaults = defaults
        retention = HistoryRetention(rawValue: defaults.integer(forKey: Self.retentionKey)) ?? .threeDays
        confirmsDeletion = defaults.object(forKey: Self.confirmDeletionKey) as? Bool ?? true
        lastChange = pasteboard.changeCount
        loadHistory()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func retry() {
        if let store {
            do {
                entries = try store.entries()
                message = nil
            } catch {
                message = "无法打开本机历史记录。请检查磁盘空间或文件权限后重试。"
            }
        } else {
            loadHistory()
        }
        poll(userRequested: true)
    }

    func poll(at time: Date = Date(), userRequested: Bool = false) {
        guard let store else { return }
        do {
            if time >= nextCleanup {
                try cleanExpired(in: store, at: time)
            }

            if #available(macOS 15.4, *) {
                let access = pasteboard.accessBehavior
                if access == .alwaysDeny {
                    needsPermission = true
                    return
                }
                if access == .alwaysAllow {
                    needsPermission = false
                } else if needsPermission && !userRequested {
                    return
                }
            }

            let change = pasteboard.changeCount
            guard change != lastChange else { return }
            let items = pasteboard.pasteboardItems
            let candidates = (items ?? []).filter(Self.supports)
            let captures = candidates.compactMap(Self.capture)
            guard pasteboard.changeCount == change else { return }
            if #available(macOS 15.4, *), pasteboard.accessBehavior == .ask,
               captures.isEmpty && (items == nil || !candidates.isEmpty) {
                needsPermission = true
                return
            }
            needsPermission = false

            if !captures.isEmpty {
                try store.insert(captures, at: time)
            }
            lastChange = change
            if !captures.isEmpty {
                entries = try store.entries()
                message = nil
            }
        } catch {
            message = "保存或读取历史时出错。请检查磁盘空间后重试。"
        }
    }

    @discardableResult
    func restore(_ entry: ClipboardEntry) -> Bool {
        do {
            let cutoff = Date().addingTimeInterval(-retention.interval)
            guard let payload = try store?.payload(id: entry.id, retainingAfter: cutoff) else {
                message = "这条记录已过期或已不存在。"
                return false
            }
            let item = NSPasteboardItem()
            let type = NSPasteboard.PasteboardType(payload.format)
            let prepared: Bool
            if type == .string, let text = String(data: payload.data, encoding: .utf8) {
                prepared = item.setString(text, forType: .string)
            } else {
                prepared = item.setData(payload.data, forType: type)
            }
            guard prepared, item.setString("1", forType: Self.restored) else {
                message = "无法复制这条记录。"
                return false
            }
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                message = "无法写入剪贴板，请重试。"
                return false
            }
            message = nil
            return true
        } catch {
            message = "无法读取这条记录。"
            return false
        }
    }

    func wouldRemoveEntries(with period: HistoryRetention, at time: Date = Date()) -> Bool {
        let cutoff = time.addingTimeInterval(-period.interval)
        return period.rawValue < retention.rawValue
            && entries.contains { !$0.isPinned && $0.copiedAt <= cutoff }
    }

    func setRetention(_ period: HistoryRetention, at time: Date = Date()) {
        guard period != retention else { return }
        defaults.set(period.rawValue, forKey: Self.retentionKey)
        retention = period
        nextCleanup = .distantPast
        guard let store else { return }

        do {
            try cleanExpired(in: store, at: time)
            message = nil
        } catch {
            message = "保留时间已保存，暂时无法清理过期记录。"
        }
    }

    func togglePin(_ entry: ClipboardEntry, at time: Date = Date()) -> PinChange {
        if entry.isPinned && entry.copiedAt <= time.addingTimeInterval(-retention.interval) {
            return .confirmExpiredRemoval
        }
        updateEntries(failure: "无法更改这条记录的置顶状态。") { store in
            try store.setPinned(!entry.isPinned, id: entry.id)
        }
        return .handled
    }

    func delete(_ entry: ClipboardEntry) {
        updateEntries(failure: "无法删除这条记录。") { store in
            try store.delete(id: entry.id)
        }
    }

    private func updateEntries(failure: String, action: (HistoryStore) throws -> Void) {
        guard let store else {
            message = failure
            return
        }
        do {
            try action(store)
            entries = try store.entries()
            message = nil
        } catch {
            message = failure
        }
    }

    private func loadHistory() {
        do {
            let database = try HistoryStore(url: storeURL ?? HistoryStore.defaultURL())
            let now = Date()
            _ = try database.removeExpired(at: now.addingTimeInterval(-retention.interval))
            entries = try database.entries()
            nextCleanup = now.addingTimeInterval(60)
            store = database
            message = nil
        } catch {
            message = "无法打开本机历史记录。请检查磁盘空间或文件权限后重试。"
        }
    }

    private func cleanExpired(in store: HistoryStore, at time: Date) throws {
        if try store.removeExpired(at: time.addingTimeInterval(-retention.interval)) {
            entries = try store.entries()
        }
        nextCleanup = time.addingTimeInterval(60)
    }

    private static func supports(_ item: NSPasteboardItem) -> Bool {
        let types = item.types
        return Self.excludedTypes.isDisjoint(with: types)
            && (types.contains(.string) || types.contains(where: imageTypes.contains))
    }

    private static func capture(_ item: NSPasteboardItem) -> ClipboardCapture? {
        for type in imageTypes where item.types.contains(type) {
            if let data = item.data(forType: type), let thumbnail = makeThumbnail(data) {
                return ClipboardCapture(
                    payload: ClipboardPayload(format: type.rawValue, data: data),
                    textPreview: nil, thumbnail: thumbnail
                )
            }
        }
        guard let text = item.string(forType: .string),
              text.contains(where: { !$0.isWhitespace }) else { return nil }
        return ClipboardCapture(
            payload: ClipboardPayload(format: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)),
            textPreview: String(text.prefix(240)), thumbnail: nil
        )
    }

    private static func makeThumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 144
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
