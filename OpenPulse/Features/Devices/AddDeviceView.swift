import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    @State private var choosing: BluetoothManager.Discovered?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    tipsRow
                }
                .listRowBackground(Theme.card)

                Section {
                    if bluetooth.discovered.isEmpty {
                        HStack(spacing: 12) {
                            if bluetooth.isScanning { ProgressView() }
                            Text(bluetooth.isScanning ? "Looking for nearby devices…" : "No devices found")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    ForEach(bluetooth.discovered) { d in
                        Button {
                            if let kind = d.kind { connect(d, kind) } else { choosing = d }
                        } label: {
                            row(d)
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby")
                        Spacer()
                        if bluetooth.isScanning { ProgressView().controlSize(.small) }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Show all Bluetooth devices", isOn: $bluetooth.showAllDevices)
                        .tint(Theme.strain)
                } footer: {
                    Text("Turn this on if your device isn't recognised automatically — you'll be asked how to talk to it.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(bluetooth.isScanning ? "Stop" : "Scan") {
                        if bluetooth.isScanning { bluetooth.stopScan() } else { bluetooth.startScan() }
                    }
                }
            }
            .onAppear { bluetooth.startScan() }
            .onDisappear { bluetooth.stopScan() }
            .onChange(of: bluetooth.showAllDevices) { _, _ in bluetooth.startScan() }
            .confirmationDialog("How should OpenPulse talk to \(choosing?.name ?? "this device")?",
                                isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                                titleVisibility: .visible) {
                ForEach(DeviceKind.allCases, id: \.self) { kind in
                    Button(kind.title) { if let d = choosing { connect(d, kind) } }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var tipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pairing a CMF watch", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.strain)
            Text("A watch can only talk to one app. Before pairing, unpair it in the Nothing X app and remove it under iPhone Settings › Bluetooth, then keep the watch close to your phone.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func row(_ d: BluetoothManager.Discovered) -> some View {
        HStack(spacing: 12) {
            Image(systemName: d.kind?.symbol ?? "questionmark.circle")
                .font(.title3)
                .foregroundStyle(d.kind == nil ? Theme.textTertiary : Theme.strain)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(d.alreadyConnected ? "Linked to this iPhone" : (d.kind?.title ?? "Unknown device"))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !d.alreadyConnected { SignalBars(rssi: d.rssi) }
            if bluetooth.connected.contains(d.id) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.recoveryGreen)
            }
        }
    }

    private func connect(_ d: BluetoothManager.Discovered, _ kind: DeviceKind) {
        bluetooth.connect(d, as: kind)
        choosing = nil
        dismiss()
    }
}

struct SignalBars: View {
    var rssi: Int
    private var level: Int { rssi > -60 ? 3 : (rssi > -75 ? 2 : 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.textSecondary : Theme.track)
                    .frame(width: 4, height: CGFloat(4 + i * 4))
            }
        }
    }
}
