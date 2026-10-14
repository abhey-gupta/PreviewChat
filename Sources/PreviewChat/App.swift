import SwiftUI

@main
struct PreviewChatApp: App {
    @StateObject private var store = ChatStore()
    @AppStorage(Prefs.layoutKey) private var layout = PanelLayout.portrait

    var body: some Scene {
        MenuBarExtra {
            ChatView()
                .environmentObject(store)
                .frame(width: layout.size.width, height: layout.size.height)
        } label: {
            Image(systemName: store.document == nil ? "doc.text" : "doc.text.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
