import SwiftUI
import AppKit
import TaskerDomain

/// 通用可编辑条目视图模型：既能装 CategoryDef 又能装 WorkTypeDef。
/// 用 id + name 就够了。
private struct EditableDef: Identifiable, Hashable {
    let id: UUID
    var name: String
}

struct SettingsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var isPresented: Bool

    @State private var categories: [EditableDef] = []
    @State private var workTypes: [EditableDef] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2)

            DataRootSection()

            HStack(alignment: .top, spacing: 20) {
                ListEditor(title: "Categories", items: $categories)
                    .frame(width: 260, height: 340)
                ListEditor(title: "Work types", items: $workTypes)
                    .frame(width: 260, height: 340)
            }
            Text("Renaming keeps existing task linkage (internal id-based reference).")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Restore defaults") {
                    categories = AppSettings.defaults.categories.map { EditableDef(id: $0.id, name: $0.name) }
                    workTypes = AppSettings.defaults.workTypes.map { EditableDef(id: $0.id, name: $0.name) }
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear {
            categories = store.settings.categories.map { EditableDef(id: $0.id, name: $0.name) }
            workTypes = store.settings.workTypes.map { EditableDef(id: $0.id, name: $0.name) }
        }
    }

    private func save() {
        let cats = categories.compactMap { d -> CategoryDef? in
            let t = d.name.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : CategoryDef(id: d.id, name: t)
        }
        let wts = workTypes.compactMap { d -> WorkTypeDef? in
            let t = d.name.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : WorkTypeDef(id: d.id, name: t)
        }
        store.updateSettings(AppSettings(categories: cats, workTypes: wts))
        isPresented = false
    }
}

private struct DataRootSection: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Data directory").font(.headline)
            HStack {
                Text(store.dataRoot.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Change…") { chooseDirectory() }
            }
            Text("Switches immediately: settings, tasks, and entries all load from the new location.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.dataRoot
        panel.prompt = "Choose data directory"
        if panel.runModal() == .OK, let url = panel.url {
            store.setDataRoot(url)
        }
    }
}

private struct ListEditor: View {
    let title: String
    @Binding var items: [EditableDef]
    @State private var newItem: String = ""
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            List(selection: $selection) {
                ForEach($items) { $item in
                    TextField("", text: $item.name)
                        .textFieldStyle(.plain)
                        .tag(item.id)
                }
                .onMove { src, dst in
                    items.move(fromOffsets: src, toOffset: dst)
                }
            }
            .border(Color.secondary.opacity(0.3))
            HStack {
                Button {
                    if let s = selection, let i = items.firstIndex(where: { $0.id == s }) {
                        items.remove(at: i)
                        selection = nil
                    }
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)

                Button {
                    if let s = selection, let i = items.firstIndex(where: { $0.id == s }), i > 0 {
                        items.swapAt(i, i - 1)
                    }
                } label: { Image(systemName: "arrow.up") }
                    .disabled(!canMove(-1))

                Button {
                    if let s = selection, let i = items.firstIndex(where: { $0.id == s }), i < items.count - 1 {
                        items.swapAt(i, i + 1)
                    }
                } label: { Image(systemName: "arrow.down") }
                    .disabled(!canMove(1))

                Spacer()

                TextField("New item", text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                    .onSubmit(addItem)

                Button(action: addItem) { Image(systemName: "plus") }
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .buttonStyle(.borderless)
        }
    }

    private func canMove(_ delta: Int) -> Bool {
        guard let s = selection, let i = items.firstIndex(where: { $0.id == s }) else { return false }
        let target = i + delta
        return target >= 0 && target < items.count
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        items.append(EditableDef(id: UUID(), name: t))
        newItem = ""
    }
}
