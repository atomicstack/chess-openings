import SwiftUI

struct RootTabsView: View {
    var body: some View {
        TabView {
            OpeningListView()
                .tabItem { Label("train", systemImage: "graduationcap") }
            LibraryListView()
                .tabItem { Label("library", systemImage: "books.vertical") }
        }
    }
}
