import SwiftUI
import CoreBluetooth

struct DevicesView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if bluetooth.bluetoothState != .poweredOn && bluetooth.bluetoothState != .unknown {
                        bluetoothBanner
                    }
                    if let bpm = bluetooth.liveHeartRate { LiveHeartRateCard(bpm: bpm) }

                    if bluetooth.devices.isEmpty {
                        emptyCard
                    } else {
                        ForEach(bluetooth.devices) { d in DeviceCard(device: d) }
                    }

                    Button { showAdd = true } label: {
                        Label("Add a device", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    if bluetooth.devices.contains(where: { $0.kind == .cmfWatch }) { WatchSettingsCard() }
                    supportedCard

                    NavigationLink {
                        DebugLogView()
                    } label: {
                        HStack {
                            Label("Bluetooth log", systemImage: "terminal")
                            Spacer()
                            Text("\(bluetooth.log.count)").foregroundStyle(Theme.textTertiary)
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Devices")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .refreshable { bluetooth.sync() }
            .sheet(isPresented: $showAdd) { AddDeviceView() }
        }
    }

    private var bluetoothBanner: some View {
        Card {
            Label(bluetooth.bluetoothState == .unauthorized ? "Bluetooth permission needed" : "Bluetooth is off",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(Theme.recoveryYellow)
            Text(bluetooth.bluetoothState == .unauthorized
                 ? "Allow OpenPulse to use Bluetooth in Settings › Privacy & Security › Bluetooth."
                 : "Turn on Bluetooth in Control Center to sync your devices.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var emptyCard: some View {
        Card(padding: 22) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.strain)
            Text("No devices yet").font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text("OpenPulse talks to your wearable directly over Bluetooth — no other app in between. Your data stays on this iPhone.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var supportedCard: some View {
        Card {
            SectionLabel(text: "Supported devices")
            ForEach(DeviceKind.allCases, id: \.self) { kind in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kind.symbol).font(.title3).foregroundStyle(Theme.strain).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind == .cmfWatch ? "CMF Watch 3 Pro, Watch Pro 2, Watch Pro" : "Any Bluetooth heart-rate sensor")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(kind.capabilities).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Device card

struct DeviceCard: View {
    var device: KnownDevice
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var confirmForget = false

    private var isConnected: Bool { bluetooth.connected.contains(device.id) }
    private var isSyncing: Bool { bluetooth.syncing.contains(device.id) }

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isConnected ? Theme.recoveryGreen : Theme.textTertiary)
                    .frame(width: 50, height: 50)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.headline).foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Circle().fill(isConnected ? Theme.recoveryGreen : Theme.textTertiary).frame(width: 7, height: 7)
                        Text(bluetooth.status[device.id] ?? (isConnected ? "Connected" : "Not connected"))
                            .lineLimit(2)
                    }
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let b = device.battery {
                    Label("\(b)%", systemImage: batterySymbol(b)).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 16) {
                StatCell(label: "Last sync", value: device.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                if let fw = device.firmware { StatCell(label: "Firmware", value: fw) }
            }

            HStack(spacing: 10) {
                action(isSyncing ? "Syncing…" : (isConnected ? "Sync now" : "Connect"),
                       symbol: "arrow.triangle.2.circlepath", primary: true) { bluetooth.sync(device) }
                    .disabled(isSyncing)
                if device.kind == .cmfWatch && isConnected {
                    action("Find", symbol: "bell.and.waves.left.and.right") { bluetooth.find(device) }
                }
                Menu {
                    if isConnected {
                        Button("Disconnect", systemImage: "bolt.horizontal.circle") { bluetooth.disconnect(device) }
                    }
                    Button("Forget device", systemImage: "trash", role: .destructive) { confirmForget = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 40)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .confirmationDialog("Forget \(device.name)?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { bluetooth.forget(device) }
        } message: {
            Text("The pairing key is deleted. Data already synced stays on this iPhone.")
        }
    }

    private func action(_ title: String, symbol: String, primary: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(primary ? Theme.strain : Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(primary ? Color.black : Theme.textPrimary)
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Live HR

struct LiveHeartRateCard: View {
    var bpm: Int
    @State private var beat = false

    var body: some View {
        Card {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.recoveryRed)
                    .scaleEffect(beat ? 1.15 : 0.92)
                    .animation(.easeInOut(duration: 60.0 / Double(max(bpm, 30)) / 2).repeatForever(autoreverses: true), value: beat)
                    .onAppear { beat = true }
                VStack(alignment: .leading) {
                    Text("Live heart rate").font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bpm)").font(.score(38)).contentTransition(.numericText())
                        Text("bpm").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Watch settings

struct WatchSettingsCard: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        Card {
            SectionLabel(text: "Watch measurements")
            Toggle(isOn: $bluetooth.watchSettings.allDayHeartRate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All-day heart rate").foregroundStyle(Theme.textPrimary)
                    Text("Required for Strain and resting heart rate").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            Toggle(isOn: $bluetooth.watchSettings.stressMonitoring) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stress monitoring").foregroundStyle(Theme.textPrimary)
                    Text("Used as the HRV signal for Recovery").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            Toggle(isOn: $bluetooth.watchSettings.spo2Monitoring) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blood oxygen").foregroundStyle(Theme.textPrimary)
                    Text("Overnight SpO₂ readings").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .tint(Theme.recoveryGreen)
    }
}

// MARK: - Debug log

struct DebugLogView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(bluetooth.log) { line in
                    Text(line.formatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(color(line.direction))
                        .listRowBackground(Theme.background)
                        .id(line.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .onAppear { if let last = bluetooth.log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
        .navigationTitle("Bluetooth log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: bluetooth.logText) { Image(systemName: "square.and.arrow.up") }
                Button { bluetooth.clearLog() } label: { Image(systemName: "trash") }
            }
        }
    }

    private func color(_ d: LogLine.Direction) -> Color {
        switch d {
        case .tx: return Theme.strain
        case .rx: return Theme.recoveryGreen
        case .info: return Theme.textSecondary
        case .error: return Theme.recoveryRed
        }
    }
}
