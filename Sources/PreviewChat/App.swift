import SwiftUI

@main
struct PreviewChatApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        MenuBarExtra {
            ChatView()
                .environmentObject(store)
                .frame(width: 440, height: 600)
        } label: {
            Image(systemName: store.document == nil ? "doc.text" : "doc.text.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
