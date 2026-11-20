import AppKit
import MacThermalWatchCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var monitor: MonitorViewModel
    @State private var showsRecovery = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    healthBanner

                    LazyVGrid(columns: columns, spacing: 12) {
                        MetricCard(
                            title: "État thermique",
                            value: thermalLabel,
                            detail: "Mesure officielle macOS",
                            symbol: "thermometer.medium",
                            tint: healthColor
                        )
                        MetricCard(
                            title: "Vitesse CPU",
                            value: percent(monitor.snapshot?.limits.speedPercent),
                            detail: "100 % = aucune limitation",
                            symbol: "cpu",
                            tint: speedColor
                        )
                        MetricCard(
                            title: "Planificateur",
                            value: percent(monitor.snapshot?.limits.schedulerPercent),
                            detail: "Capacité de calcul accordée",
                            symbol: "gauge.with.dots.needle.67percent",
                            tint: schedulerColor
                        )
                        MetricCard(
                            title: "Charge système",
                            value: loadLabel,
                            detail: "File de travail sur une minute",
                            symbol: "waveform.path.ecg",
                            tint: loadColor
                        )
                    }

                    HStack(alignment: .top, spacing: 18) {
                        historyCard
                        recommendationCard
                    }

                    HStack(alignment: .top, spacing: 18) {
                        processCard
                        alertCard
                    }

                    footer
                }
                .padding(24)
            }
        }
        .overlay(alignment: .top) {
            if let feedback = monitor.feedback {
                FeedbackBanner(feedback: feedback)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: monitor.feedback?.id)
        .sheet(isPresented: $showsRecovery) {
            RecoveryView()
                .environmentObject(monitor)
        }
        .alert(item: $monitor.pendingAction) { request in
            switch request.kind {
            case .quit:
                return Alert(
                    title: Text("Quitter \(request.applicationName) ?"),
                    message: Text("L’application recevra une demande de fermeture normale et pourra proposer d’enregistrer son travail."),
                    primaryButton: .destructive(Text("Quitter")) {
                        monitor.confirm(request)
                    },
                    secondaryButton: .cancel()
                )
            case .forceQuit:
                return Alert(
                    title: Text("Forcer la fermeture ?"),
                    message: Text("\(request.applicationName) sera arrêté immédiatement. Les modifications non enregistrées pourront être perdues."),
                    primaryButton: .destructive(Text("Forcer à quitter")) {
                        monitor.confirm(request)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "thermometer.and.liquid.waves")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacThermalWatch")
                    .font(.title2.bold())
                Text("Diagnostic thermique et performances")
                    .foregroundColor(.secondary)
            }

            Spacer()

            if monitor.isSampling {
                ProgressView()
                    .controlSize(.small)
            }

            Menu {
                Button("5 secondes") { monitor.updateInterval(5) }
                Button("10 secondes") { monitor.updateInterval(10) }
                Button("30 secondes") { monitor.updateInterval(30) }
            } label: {
                Label("Toutes les \(Int(monitor.interval)) s", systemImage: "clock")
            }

            Button {
                monitor.toggleMonitoring()
            } label: {
                Label(
                    monitor.isRunning ? "Mettre en pause" : "Démarrer",
                    systemImage: monitor.isRunning ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var healthBanner: some View {
        HStack(spacing: 18) {
            Image(systemName: monitor.health.symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(healthColor)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(monitor.health.title)
                    .font(.title2.bold())
                Text(monitor.health.detail)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(monitor.isRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(monitor.isRunning ? "Surveillance active" : "Surveillance en pause")
                }
                .font(.subheadline.weight(.semibold))

                if let date = monitor.snapshot?.date {
                    Text("Dernière mesure à \(date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    showsRecovery = true
                } label: {
                    Label("Réduire la charge", systemImage: "snowflake")
                }
                .buttonStyle(.bordered)
                .padding(.top, 5)
                .disabled(monitor.snapshot == nil)
            }
        }
        .padding(20)
        .background(healthColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(healthColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var historyCard: some View {
        Card(title: "Historique de la vitesse CPU", symbol: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(percent(monitor.snapshot?.limits.speedPercent))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("sur les \(monitor.speedHistory.count) dernières mesures")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HistoryGraph(values: monitor.speedHistory, maximum: 100, tint: speedColor)
                    .frame(height: 105)

                HStack {
                    Label("100 % : normal", systemImage: "circle.fill")
                        .foregroundColor(.green)
                    Spacer()
                    Label("< 60 % : sévère", systemImage: "circle.fill")
                        .foregroundColor(.red)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var recommendationCard: some View {
        Card(title: "Conseil actuel", symbol: "lightbulb.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Text(monitor.recommendation)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Label("L’application ne désactive jamais les protections thermiques et ne ferme aucun processus automatiquement.", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 340)
    }

    private var processCard: some View {
        Card(title: "Applications les plus actives", symbol: "list.number") {
            VStack(spacing: 0) {
                if let processes = monitor.snapshot?.topProcesses, !processes.isEmpty {
                    ForEach(Array(processes.prefix(8).enumerated()), id: \.element.pid) { index, process in
                        ProcessRow(
                            rank: index + 1,
                            name: monitor.friendlyProcessName(process),
                            process: process,
                            canQuit: monitor.canQuit(process),
                            onQuit: { monitor.requestQuit(process) },
                            onForceQuit: { monitor.requestQuit(process, force: true) }
                        )
                        if index < min(processes.count, 8) - 1 { Divider() }
                    }
                } else {
                    PlaceholderView(
                        symbol: "hourglass",
                        text: "Les processus apparaîtront après la première mesure."
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var alertCard: some View {
        Card(title: "Incidents récents", symbol: "exclamationmark.bubble.fill") {
            VStack(spacing: 0) {
                if monitor.alerts.isEmpty {
                    PlaceholderView(
                        symbol: "checkmark.circle",
                        text: "Aucun incident détecté pendant cette session."
                    )
                } else {
                    ForEach(Array(monitor.alerts.prefix(6).enumerated()), id: \.element.id) { index, event in
                        AlertRow(event: event)
                        if index < min(monitor.alerts.count, 6) - 1 { Divider() }
                    }
                }
            }
        }
        .frame(width: 360)
    }

    private var footer: some View {
        HStack {
            Text("Développé par Richard BATHIEBO")
                .font(.caption.weight(.semibold))
            Text("•")
                .foregroundColor(.secondary)
            Text(monitor.snapshot?.architecture ?? "macOS")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
            Spacer()
            Button("Afficher le journal") { monitor.revealLog() }
            Button("Moniteur d’activité") { monitor.openActivityMonitor() }
            Button("Mesurer maintenant") { monitor.refresh() }
                .disabled(monitor.isSampling)
        }
    }

    private var healthColor: Color {
        switch monitor.health {
        case .waiting: .secondary
        case .normal: .green
        case .attention: .orange
        case .danger: .red
        }
    }

    private var speedColor: Color {
        guard let value = monitor.snapshot?.limits.speedPercent else { return .secondary }
        if value < 60 { return .red }
        if value < 90 { return .orange }
        return .green
    }

    private var schedulerColor: Color {
        guard let value = monitor.snapshot?.limits.schedulerPercent else { return .secondary }
        if value < 60 { return .red }
        if value < 90 { return .orange }
        return .green
    }

    private var loadColor: Color {
        guard let snapshot = monitor.snapshot, let load = snapshot.loadAverage.first else { return .secondary }
        let cores = Double(max(1, snapshot.activeProcessorCount))
        if load > cores * 4 { return .red }
        if load > cores * 2 { return .orange }
        return .blue
    }

    private var thermalLabel: String {
        guard let value = monitor.snapshot?.thermalLevel else { return "—" }
        switch value {
        case .nominal: return "Normal"
        case .fair: return "Élevé"
        case .serious: return "Sérieux"
        case .critical: return "Critique"
        case .unknown: return "Indisponible"
        }
    }

    private var loadLabel: String {
        guard let value = monitor.snapshot?.loadAverage.first else { return "—" }
        return String(format: "%.1f", value)
    }

    private func percent(_ value: Int?) -> String {
        value.map { "\($0) %" } ?? "N/D"
    }
}

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundColor(tint)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ProcessRow: View {
    let rank: Int
    let name: String
    let process: ProcessUsage
    let canQuit: Bool
    let onQuit: () -> Void
    let onForceQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text("PID \(process.pid) • actif depuis \(process.elapsed)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f %%", process.cpuPercent))
                    .font(.body.monospacedDigit().weight(.semibold))
                Text(String(format: "%.1f %% mémoire", process.memoryPercent))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if canQuit {
                Button("Quitter", action: onQuit)
                    .buttonStyle(.bordered)

                Menu {
                    Button("Quitter proprement", action: onQuit)
                    Divider()
                    Button("Forcer à quitter", role: .destructive, action: onForceQuit)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
        }
        .padding(.vertical, 8)
        .help(process.command)
    }
}

private struct FeedbackBanner: View {
    let feedback: ActionFeedback

    var body: some View {
        Label(
            feedback.message,
            systemImage: feedback.isError ? "xmark.octagon.fill" : "checkmark.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(
                feedback.isError ? Color.red.opacity(0.5) : Color.green.opacity(0.5),
                lineWidth: 1
            )
        )
        .shadow(radius: 8, y: 3)
    }
}

private struct RecoveryView: View {
    @EnvironmentObject private var monitor: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    private var speed: Double {
        Double(monitor.snapshot?.limits.speedPercent ?? 100)
    }

    private var recoveryColor: Color {
        switch monitor.health {
        case .danger: return .red
        case .attention: return .orange
        case .normal: return .green
        case .waiting: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Réduire la charge")
                        .font(.title2.bold())
                    Text("Assistant de récupération thermique")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 14) {
                Image(systemName: monitor.health.symbol)
                    .font(.system(size: 30))
                    .foregroundColor(recoveryColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.health.title)
                        .font(.headline)
                    ProgressView(value: speed, total: 100) {
                        Text("Capacité CPU disponible")
                    } currentValueLabel: {
                        Text("\(Int(speed)) %").monospacedDigit()
                    }
                    .tint(recoveryColor)
                }
            }
            .padding(16)
            .background(recoveryColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 10) {
                Label("Actions immédiates", systemImage: "checklist")
                    .font(.headline)
                StepRow(number: 1, text: "Arrêtez le partage d’écran, la caméra ou l’export en cours.")
                StepRow(number: 2, text: "Posez le Mac sur une surface dure et libérez ses aérations.")
                StepRow(number: 3, text: "Quittez une application lourde ci-dessous si elle n’est plus nécessaire.")
            }

            Divider()

            Text("Applications que MacThermalWatch peut fermer proprement")
                .font(.headline)

            if monitor.manageableProcesses.isEmpty {
                PlaceholderView(
                    symbol: "shield.checkered",
                    text: "Aucune application utilisateur fermable parmi les processus les plus actifs. Les services macOS sont protégés."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(monitor.manageableProcesses.prefix(4).enumerated()), id: \.element.pid) { index, process in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(monitor.friendlyProcessName(process))
                                    .font(.subheadline.weight(.semibold))
                                Text(String(format: "%.1f %% CPU", process.cpuPercent))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Quitter proprement") {
                                dismiss()
                                DispatchQueue.main.async {
                                    monitor.requestQuit(process)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 9)
                        if index < min(monitor.manageableProcesses.count, 4) - 1 { Divider() }
                    }
                }
            }

            Spacer()

            HStack {
                Button("Ouvrir le Moniteur d’activité") { monitor.openActivityMonitor() }
                Spacer()
                Text("Objectif : état normal et CPU ≥ 90 %")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 600, height: 620)
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AlertRow: View {
    let event: TimedAlert

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.alert.severity >= 3 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(event.alert.severity >= 3 ? .red : .orange)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.alert.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(event.alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct PlaceholderView: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

private struct HistoryGraph: View {
    let values: [Double]
    let maximum: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    Divider()
                    Spacer()
                    Divider()
                    Spacer()
                    Divider()
                }
                .opacity(0.35)

                if values.count > 1 {
                    Path { path in
                        for (index, value) in values.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                            let ratio = min(max(value / maximum, 0), 1)
                            let y = geometry.size.height * (1 - CGFloat(ratio))
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                } else {
                    Text("Historique en cours…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
