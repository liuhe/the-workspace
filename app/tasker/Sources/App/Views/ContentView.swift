import SwiftUI
import TaskerDomain

struct ContentView: View {
    @EnvironmentObject var store: WorkspaceStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 240)
        } detail: {
            if store.selectedTask != nil {
                TaskDetailView()
            } else {
                ContentUnavailableView("Select a task", systemImage: "text.append",
                                       description: Text("Select from sidebar or create new"))
            }
        }
        .navigationTitle(navTitle)
        .alert("Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .onChange(of: store.dayFilter) { _, _ in store.pruneSelectionIfOffscreen() }
        .onChange(of: store.showCurrent) { _, _ in store.pruneSelectionIfOffscreen() }
    }

    private var navTitle: String {
        let base: String
        switch store.dayFilter {
        case .day(let d): base = d.descriptionWithWeekday
        case .backlog: base = "Backlog"
        }
        return store.showCurrent ? "\(base) · Current" : base
    }
}
