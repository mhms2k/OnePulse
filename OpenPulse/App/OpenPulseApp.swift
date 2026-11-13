import SwiftUI

@main
struct OpenPulseApp: App {
    @StateObject private var store = HealthStore()
    @StateObject private var bluetooth = BluetoothManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(bluetooth)
                .preferredColorScheme(.dark)
                .onAppear {
                    let store = self.store
                    bluetooth.onBatch = { batch in
                        Task { @MainActor in store.ingest(batch) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshIfNewDay()
                        bluetooth.sync()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if store.profile.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: store.profile.hasOnboarded)
    }
}

enum AppTab: Hashable { case today, trends, health, devices, profile }

final class Navigator: ObservableObject {
    @Published var tab: AppTab = .today
}

struct MainTabView: View {
    @StateObject private var nav = Navigator()

    var body: some View {
        TabView(selection: $nav.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.hexagongrid.circle") }
                .tag(AppTab.today)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.trends)
            HealthView()
                .tabItem { Label("Health", systemImage: "heart.text.square") }
                .tag(AppTab.health)
            DevicesView()
                .tabItem { Label("Devices", systemImage: "applewatch.radiowaves.left.and.right") }
                .tag(AppTab.devices)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.strain)
        .environmentObject(nav)
    }
}
