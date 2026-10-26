import SwiftUI
import TaskerDomain

// MARK: - 从 Backlog 挑任务加入某天

/// 列出尚未关联 `day` 的 Backlog 任务，关键词过滤标题（不分大小写），可多选。
/// 回车 / Add = 加入选中项（没选中则加入列表第一条）；双击某行 = 只加入那一条。
struct BacklogPickerSheet: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var isPresented: Bool
    let day: Day
    /// 加入成功后的回调（甘特图用它选中新加入的任务）
    var onAdded: (([UUID]) -> Void)? = nil
    @State private var keyword = ""
    @State private var selected: Set<UUID> = []
    @FocusState private var focused: Bool

    private var candidates: [TaskAggregate] {
        TaskQueries.backlogCandidates(forDay: day, matching: keyword, in: store.tasks)
    }

    var body: some View {
        let items = candidates
        VStack(alignment: .leading, spacing: 12) {
            Text("Add from Backlog · \(day.descriptionWithWeekday)").font(.headline)
            TextField("Filter by title", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { addSelectedOrFirst(in: items) }
            List(items, id: \.id, selection: $selected) { t in
                HStack(spacing: 8) {
                    Text(t.priority(in: .backlog).titlePrefix + t.meta.title)
                        .lineLimit(1)
                    Spacer()
                    Text(SettingsLookup.categoryName(t.meta.categoryId, in: store.settings.categories))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { add([t.id]) }
                .tag(t.id)
            }
            .frame(height: 320)
            .overlay {
                if items.isEmpty {
                    Text(keyword.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "Backlog is empty" : "No backlog task matches")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(selected.isEmpty
                     ? "\(items.count) tasks"
                     : "\(selected.count) of \(items.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { isPresented = false }
                Button(selected.count > 1 ? "Add \(selected.count)" : "Add") {
                    addSelectedOrFirst(in: items)
                }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { focused = true }
        // 过滤后选中项可能已不在列表里，剔除掉
        .onChange(of: keyword) { _ in
            let visible = Set(items.map(\.id))
            selected = selected.intersection(visible)
        }
    }

    private func addSelectedOrFirst(in items: [TaskAggregate]) {
        let visible = Set(items.map(\.id))
        let chosen = selected.intersection(visible)
        if !chosen.isEmpty {
            // 保持列表顺序
            add(items.map(\.id).filter { chosen.contains($0) })
        } else if let first = items.first {
            add([first.id])
        }
    }

    private func add(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            store.addToDay(id: id, day: day, from: .backlog)
        }
        onAdded?(ids)
        isPresented = false
    }
}
