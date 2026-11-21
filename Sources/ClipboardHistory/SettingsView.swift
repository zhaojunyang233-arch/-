import SwiftUI

struct SettingsView: View {
    @ObservedObject var history: ClipboardHistory
    let showMenuBarIcon: () -> Void
    let close: () -> Void
    @State private var shorterRetention: HistoryRetention?
    @State private var showsRetentionAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("保留时间")
                    .font(.headline)
                Picker("保留时间", selection: retentionSelection) {
                    ForEach(HistoryRetention.allCases, id: \.self) { period in
                        Text("\(period.rawValue) 天").tag(period)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text("从复制时间算起。置顶记录会一直保留。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Toggle("删除前确认", isOn: $history.confirmsDeletion)
            Divider()
            Button("在屏幕顶部显示剪贴板图标", action: showMenuBarIcon)
                .help("点按菜单栏里的剪贴板图标可以打开历史。")
            if let message = history.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 305, alignment: .leading)
        .padding(20)
        .onExitCommand(perform: close)
        .alert("缩短保留时间？", isPresented: $showsRetentionAlert, presenting: shorterRetention) { period in
            Button("应用新保留时间", role: .destructive) { history.setRetention(period) }
            Button("保留原设置", role: .cancel) {}
        } message: { period in
            Text("达到 \(period.rawValue) 天的未置顶记录会立即删除。")
        }
    }

    private var retentionSelection: Binding<HistoryRetention> {
        Binding(
            get: { history.retention },
            set: { period in requestRetention(period) }
        )
    }

    private func requestRetention(_ period: HistoryRetention) {
        if history.wouldRemoveEntries(with: period) {
            shorterRetention = period
            showsRetentionAlert = true
        } else {
            history.setRetention(period)
        }
    }
}
