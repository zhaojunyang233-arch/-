import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: ClipboardHistory
    var showsHeading = true
    var shortcutActive = false
    let openSettings: () -> Void
    let close: () -> Void
    @State private var pendingRemoval: Removal?
    @State private var showsRemovalAlert = false
    @State private var copiedEntryID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeading {
                Text("剪贴板历史")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(14)
                Divider()
            }

            if history.needsPermission || history.message != nil {
                statusMessage
                Divider()
            }

            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 24))
                        .accessibilityHidden(true)
                    Text("复制文字或图片后，记录会出现在这里")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(history.entries) { entry in
                            HistoryRow(
                                entry: entry,
                                justCopied: copiedEntryID == entry.id,
                                copy: {
                                    if history.restore(entry) {
                                        copiedEntryID = entry.id
                                    }
                                },
                                togglePin: {
                                    if history.togglePin(entry) == .confirmExpiredRemoval {
                                        confirmRemoval(of: entry, expiresOnUnpin: true)
                                    }
                                },
                                delete: {
                                    if history.confirmsDeletion {
                                        confirmRemoval(of: entry)
                                    } else {
                                        history.delete(entry)
                                    }
                                }
                            )
                        }
                    }
                    .padding(10)
                }
                .frame(height: 250)
            }

            Divider()
            HStack {
                Button("设置", action: openSettings)
                if !showsHeading {
                    Text(shortcutActive ? "⌃⇧V 打开历史" : "⌃⇧V 不可用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .accessibilityLabel("退出剪贴板历史")
            }
            .padding(12)
        }
        .frame(width: 360)
        .onExitCommand(perform: close)
        .task(id: copiedEntryID) {
            guard copiedEntryID != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                copiedEntryID = nil
            }
        }
        .alert(pendingRemoval?.title ?? "删除这条记录？",
               isPresented: $showsRemovalAlert, presenting: pendingRemoval) { removal in
            Button(removal.action, role: .destructive) { history.delete(removal.entry) }
            Button(removal.cancel, role: .cancel) {}
        } message: { removal in
            Text(removal.message)
        }
    }

    private func confirmRemoval(of entry: ClipboardEntry, expiresOnUnpin: Bool = false) {
        pendingRemoval = Removal(entry: entry, expiresOnUnpin: expiresOnUnpin)
        showsRemovalAlert = true
    }

    private var statusMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            if history.needsPermission {
                Text("macOS 尚未允许后台读取剪贴板。请在「隐私与安全性」中允许「从其他 App 粘贴」。")
                    .font(.callout)
            }
            if let message = history.message {
                Text(message)
                    .font(.callout)
            }
            HStack {
                if history.needsPermission {
                    Button("打开系统设置") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }
                }
                Button("重试") { history.retry() }
            }
        }
        .padding(12)
    }

    private struct Removal {
        let entry: ClipboardEntry
        let expiresOnUnpin: Bool

        var title: String { expiresOnUnpin ? "这条记录已过保留期限" : "删除这条记录？" }
        var action: String { expiresOnUnpin ? "取消置顶并删除" : "删除" }
        var cancel: String { expiresOnUnpin ? "保留置顶" : "取消" }
        var message: String {
            expiresOnUnpin ? "取消置顶后，这条记录会立即删除。" : "这条记录将从剪贴板历史中移除。"
        }
    }
}

private struct HistoryRow: View {
    let entry: ClipboardEntry
    let justCopied: Bool
    let copy: () -> Void
    let togglePin: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: copy) {
                preview
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("复制这条记录")

            Button(action: togglePin) {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.isPinned ? "取消置顶" : "置顶")
            .help(entry.isPinned ? "取消置顶" : "置顶")

            Button(action: delete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除这条记录")
            .help("删除这条记录")
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 10) {
            if let thumbnail = entry.thumbnail, let image = NSImage(data: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 48)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: entry.textPreview ?? "图片")
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(entry.copiedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                    if justCopied {
                        Text("已复制")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.caption)
            }
        }
    }
}
