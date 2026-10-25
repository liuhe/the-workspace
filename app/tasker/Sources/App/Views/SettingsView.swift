import SwiftUI
import AppKit
import TaskerDomain

/// 通用可编辑条目视图模型：既能装 CategoryDef 又能装 WorkTypeDef。
/// 用 id + name 就够了。
private struct EditableDef: Identifiable, Hashable {
    let id: UUID
    var name: String
    /// 仅分类使用；nil = 自动（按顺序取调色板槽位色）
    var colorHex: String? = nil
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
                ListEditor(title: "Categories", items: $categories, showsColor: true)
                    .frame(width: 300, height: 340)
                ListEditor(title: "Work types", items: $workTypes)
                    .frame(width: 260, height: 340)
            }
            Text("Renaming keeps existing task linkage (internal id-based reference). Category color is used by the Gantt chart; Auto follows list order.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Restore defaults") {
                    categories = AppSettings.defaults.categories.map { EditableDef(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
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
            categories = store.settings.categories.map { EditableDef(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
            workTypes = store.settings.workTypes.map { EditableDef(id: $0.id, name: $0.name) }
        }
    }

    private func save() {
        let cats = categories.compactMap { d -> CategoryDef? in
            let t = d.name.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : CategoryDef(id: d.id, name: t, colorHex: d.colorHex)
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
    var showsColor: Bool = false
    @State private var newItem: String = ""
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            List(selection: $selection) {
                ForEach($items) { $item in
                    HStack(spacing: 8) {
                        if showsColor {
                            CategoryColorControl(colorHex: $item.colorHex,
                                                 slot: items.firstIndex(where: { $0.id == item.id }))
                        }
                        TextField("", text: $item.name)
                            .textFieldStyle(.plain)
                    }
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

// MARK: - 分类颜色：色块按钮 → 弹出 8 槽位调色板 / Auto / 自定义取色

private struct CategoryColorControl: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var colorHex: String?
    let slot: Int?
    @State private var showing = false

    private var current: Color {
        if let hex = colorHex, let c = CategoryColor.color(hex: hex) { return c }
        return CategoryColor.auto(slot: slot, scheme: scheme)
    }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(current)
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: colorHex == nil ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(colorHex == nil ? "Auto (by list order)" : colorHex!)
        .popover(isPresented: $showing, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Category color").font(.headline)
                HStack(spacing: 6) {
                    ForEach(0..<CategoryPalette.lightHex.count, id: \.self) { i in
                        let hex = scheme == .dark ? CategoryPalette.darkHex[i] : CategoryPalette.lightHex[i]
                        Button {
                            colorHex = hex
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(CategoryColor.color(hex: hex) ?? .gray)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    ColorPicker("Custom", selection: Binding(
                        get: { current },
                        set: { colorHex = CategoryColor.hex(from: $0) }
                    ), supportsOpacity: false)
                    Spacer()
                    Button("Auto") { colorHex = nil }
                        .disabled(colorHex == nil)
                }
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}

