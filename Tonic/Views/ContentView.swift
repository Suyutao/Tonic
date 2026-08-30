import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TunerView()
                .tabItem { Label("调音器", systemImage: "tuningfork") }
            MetronomeView()
                .tabItem { Label("节拍器", systemImage: "metronome") }
        }
        .tint(.indigo)
    }
}

#Preview {
    ContentView()
}
