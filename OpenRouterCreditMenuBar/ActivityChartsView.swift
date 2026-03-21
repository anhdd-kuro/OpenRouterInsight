import Charts
import SwiftUI

enum ActivityTimeFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "1 Week"
    case twoWeeks = "2 Weeks"
    case threeWeeks = "3 Weeks"
    case month = "1 Month"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .today:
            return 1
        case .week:
            return 7
        case .twoWeeks:
            return 14
        case .threeWeeks:
            return 21
        case .month:
            return 30
        }
    }
}

enum ActivityChartStyle: String, CaseIterable, Identifiable {
    case bar = "Bar"
    case line = "Line"

    var id: String { rawValue }
}

struct ActivityChartsView: View {
    let entries: [ActivityEntry]
    @Binding var selectedTimeFilter: ActivityTimeFilter
    @Binding var selectedModelFilter: String
    @State private var prepared = PreparedChartData.empty
    @State private var activeHitID: String?
    @State private var tooltip: GlobalTooltip?
    @State private var showTooltipTask: Task<Void, Never>?
    @State private var hideTooltipTask: Task<Void, Never>?
    @State private var isHoveringTooltip = false
    @State private var hoveredDayByMetric: [ActivityMetric: Date] = [:]
    @State private var selectedChartStyle: ActivityChartStyle = .bar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            activityControls
            activityMetricsContent
        }
        .padding(8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .coordinateSpace(name: "activity_portal")
        .overlay(alignment: .topLeading, content: tooltipOverlay)
        .onChange(of: availableModels) { _, models in
            if selectedModelFilter != "All Models" && !models.contains(selectedModelFilter) {
                selectedModelFilter = "All Models"
            }
        }
        .onAppear {
            recomputePreparedData()
        }
        .onChange(of: entries.count) { _, _ in
            recomputePreparedData()
            clearTooltip()
        }
        .onChange(of: selectedTimeFilter) { _, _ in
            recomputePreparedData()
            clearTooltip()
        }
        .onChange(of: selectedModelFilter) { _, _ in
            recomputePreparedData()
            clearTooltip()
        }
    }

    private var activityControls: some View {
        HStack {
            Text("Activity")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Picker("Range", selection: $selectedTimeFilter) {
                ForEach(ActivityTimeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Picker("Chart", selection: $selectedChartStyle) {
                ForEach(ActivityChartStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Picker("Model", selection: $selectedModelFilter) {
                Text("All Models").tag("All Models")
                ForEach(prepared.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var activityMetricsContent: some View {
        Group {
            if prepared.displayedModels.isEmpty {
                Text("No activity data for this filter.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    metricCard(metric: .spend, valueText: "$\(String(format: "%.2f", prepared.totalSpend))")
                    metricCard(metric: .requests, valueText: "\(prepared.totalRequests)")
                    metricCard(metric: .tokens, valueText: compactTokenText(prepared.totalTokens))
                }
            }
        }
    }

    @ViewBuilder
    private func tooltipOverlay() -> some View {
        GeometryReader { container in
            if let tooltip {
                ActivityGlobalTooltipView(tooltip: tooltip)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
                    .offset(x: tooltipOffsetX(in: container.size, for: tooltip), y: tooltipOffsetY(in: container.size, for: tooltip))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            isHoveringTooltip = true
                            hideTooltipTask?.cancel()
                        case .ended:
                            isHoveringTooltip = false
                            scheduleTooltipHide()
                        }
                    }
            }
        }
    }

    private func metricCard(metric: ActivityMetric, valueText: String) -> some View {
        let points = prepared.pointsByMetric[metric] ?? []
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            Chart(points) { point in
                if selectedChartStyle == .bar {
                    BarMark(x: .value("Day", point.day), y: .value(metric.rawValue, point.value))
                        .foregroundStyle(colorForModel(point.model))
                        .opacity(0.85)
                } else {
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value(metric.rawValue, point.value),
                        series: .value("Model", point.model)
                    )
                    .foregroundStyle(colorForModel(point.model))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", point.day),
                        y: .value(metric.rawValue, point.value)
                    )
                    .foregroundStyle(colorForModel(point.model))
                    .symbolSize(16)
                }
            }
            .chartXScale(domain: prepared.paddedDaySlotRange)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        if let highlightRect = highlightRect(for: metric, proxy: proxy, geometry: geometry) {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: highlightRect.width, height: highlightRect.height)
                                .offset(x: highlightRect.minX, y: highlightRect.minY)
                                .allowsHitTesting(false)
                        }

                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                handleHover(phase: phase, metric: metric, proxy: proxy, geometry: geometry)
                            }
                    }
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func handleHover(phase: HoverPhase, metric: ActivityMetric, proxy: ChartProxy, geometry: GeometryProxy) {
        switch phase {
        case .active(let location):
            hideTooltipTask?.cancel()
            hoveredDayByMetric[metric] = hoveredDay(at: location, proxy: proxy, geometry: geometry)

            guard let hit = hoveredColumnHit(at: location, metric: metric, proxy: proxy, geometry: geometry) else {
                if isHoveringTooltip {
                    scheduleTooltipHide()
                } else {
                    clearTooltip(keepHoverState: true)
                }
                return
            }

            if activeHitID == hit.id, tooltip != nil {
                tooltip?.cursor = hit.cursor
                return
            }

            activeHitID = hit.id
            showTooltipTask?.cancel()
            hideTooltipTask?.cancel()
            showTooltipTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, activeHitID == hit.id else { return }
                await MainActor.run {
                    tooltip = GlobalTooltip.from(hit: hit)
                }
            }
        case .ended:
            hoveredDayByMetric[metric] = nil
            if isHoveringTooltip {
                scheduleTooltipHide()
            } else {
                clearTooltip(keepHoverState: true)
            }
        }
    }

    private func hoveredDay(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Date? {
        let plotArea = geometry[proxy.plotAreaFrame]
        guard plotArea.contains(location) else { return nil }
        guard let date: Date = proxy.value(atX: location.x - plotArea.minX) else { return nil }
        let day = Calendar.current.startOfDay(for: date)
        return prepared.daySlots.contains(day) ? day : nil
    }

    private func highlightRect(for metric: ActivityMetric, proxy: ChartProxy, geometry: GeometryProxy) -> CGRect? {
        guard let day = hoveredDayByMetric[metric] else { return nil }
        let plotArea = geometry[proxy.plotAreaFrame]
        guard let x = proxy.position(forX: day) else { return nil }

        let groupedWidth = plotArea.width / CGFloat(max(prepared.daySlots.count, 1))
        let minX = max(plotArea.minX, plotArea.minX + x - groupedWidth / 2)
        let maxX = min(plotArea.maxX, plotArea.minX + x + groupedWidth / 2)
        return CGRect(x: minX, y: plotArea.minY, width: max(0, maxX - minX), height: plotArea.height)
    }

    private func hoveredColumnHit(at location: CGPoint, metric: ActivityMetric, proxy: ChartProxy, geometry: GeometryProxy) -> HoveredBar? {
        let plotArea = geometry[proxy.plotAreaFrame]
        guard plotArea.contains(location) else { return nil }
        guard let day = hoveredDay(at: location, proxy: proxy, geometry: geometry) else { return nil }

        let points = prepared.nonZeroPointsByMetric[metric] ?? []
        guard !points.isEmpty else { return nil }

        let pointsForDay = points.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        guard let bestPoint = pointsForDay.max(by: { $0.value < $1.value }) else { return nil }

        let rootFrame = geometry.frame(in: .named("activity_portal"))
        let cursor = CGPoint(x: rootFrame.minX + location.x, y: rootFrame.minY + location.y)

        let dayValuesByModel = prepared.valuesByDayModel[bestPoint.day] ?? [:]
        let rows: [GlobalTooltipRow] = prepared.displayedModels.compactMap { model -> GlobalTooltipRow? in
            let values = dayValuesByModel[model] ?? ActivityValues()
            let metricValue = values.value(for: metric)
            guard metricValue > 0 else { return nil }
            return GlobalTooltipRow(
                model: model,
                value: metricValue,
                valueText: metric.formatted(metricValue),
                color: colorForModel(model)
            )
        }
        guard !rows.isEmpty else { return nil }
        let total = rows.reduce(0.0) { $0 + $1.value }

        return HoveredBar(
            id: "\(metric.rawValue)-\(bestPoint.model)-\(bestPoint.day.timeIntervalSince1970)",
            metric: metric,
            day: bestPoint.day,
            model: bestPoint.model,
            value: bestPoint.value,
            total: total,
            rows: rows,
            color: colorForModel(bestPoint.model),
            cursor: cursor
        )
    }

    private func clearTooltip(keepHoverState: Bool = false) {
        showTooltipTask?.cancel()
        hideTooltipTask?.cancel()
        showTooltipTask = nil
        hideTooltipTask = nil
        if !keepHoverState {
            isHoveringTooltip = false
        }
        activeHitID = nil
        tooltip = nil
    }

    private func scheduleTooltipHide() {
        showTooltipTask?.cancel()
        hideTooltipTask?.cancel()
        hideTooltipTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !isHoveringTooltip else { return }
                clearTooltip(keepHoverState: true)
            }
        }
    }

    private func tooltipOffsetX(in size: CGSize, for tooltip: GlobalTooltip) -> CGFloat {
        let width: CGFloat = 210
        let rightCandidate = tooltip.cursor.x + 16
        if rightCandidate + width <= size.width {
            return rightCandidate
        }

        let leftCandidate = tooltip.cursor.x - width - 16
        if leftCandidate >= 0 {
            return leftCandidate
        }

        return min(max(rightCandidate, 0), max(0, size.width - width))
    }

    private func tooltipOffsetY(in size: CGSize, for tooltip: GlobalTooltip) -> CGFloat {
        let height = tooltipHeight(for: tooltip)
        let aboveY = tooltip.cursor.y - height - 14
        if aboveY >= 0 { return aboveY }
        return min(tooltip.cursor.y + 14, max(0, size.height - height))
    }

    private func tooltipHeight(for tooltip: GlobalTooltip) -> CGFloat {
        let baseHeight: CGFloat = 62
        let perRowHeight: CGFloat = 18
        return baseHeight + CGFloat(tooltip.rows.count) * perRowHeight
    }

    private func colorForModel(_ model: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .mint, .purple, .yellow, .teal, .red, .indigo]
        guard let index = prepared.availableModels.firstIndex(of: model) else { return .gray }
        return palette[index % palette.count]
    }

    private var availableModels: [String] {
        Set(entries.map(\.model)).sorted()
    }

    private func recomputePreparedData() {
        prepared = PreparedChartData.build(
            entries: entries,
            selectedTimeFilter: selectedTimeFilter,
            selectedModelFilter: selectedModelFilter,
            allModels: availableModels
        )
    }

    private func compactTokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

private enum ActivityMetric: String, CaseIterable {
    case spend = "Spend"
    case requests = "Requests"
    case tokens = "Tokens"

    func formatted(_ value: Double) -> String {
        switch self {
        case .spend:
            return "$\(String(format: "%.2f", value))"
        case .requests:
            return "\(Int(value))"
        case .tokens:
            if value >= 1_000_000 {
                return String(format: "%.2fM", value / 1_000_000)
            }
            if value >= 1_000 {
                return String(format: "%.1fK", value / 1_000)
            }
            return "\(Int(value))"
        }
    }
}

private struct ActivityValues {
    var spend: Double = 0
    var requests: Int = 0
    var tokens: Int = 0

    func value(for metric: ActivityMetric) -> Double {
        switch metric {
        case .spend:
            return spend
        case .requests:
            return Double(requests)
        case .tokens:
            return Double(tokens)
        }
    }
}

private struct ChartPoint: Identifiable {
    let id = UUID()
    let day: Date
    let model: String
    let metric: ActivityMetric
    let value: Double
}

private struct HoveredBar {
    let id: String
    let metric: ActivityMetric
    let day: Date
    let model: String
    let value: Double
    let total: Double
    let rows: [GlobalTooltipRow]
    let color: Color
    let cursor: CGPoint
}

private struct GlobalTooltipRow: Identifiable {
    let id = UUID()
    let model: String
    let value: Double
    let valueText: String
    let color: Color
}

private struct GlobalTooltip {
    let title: String
    let model: String
    let valueText: String
    let totalText: String
    let color: Color
    let rows: [GlobalTooltipRow]
    var cursor: CGPoint

    static func from(hit: HoveredBar) -> GlobalTooltip {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        let dayText = formatter.string(from: hit.day)
        return GlobalTooltip(
            title: "\(hit.metric.rawValue) · \(dayText)",
            model: hit.model,
            valueText: hit.metric.formatted(hit.value),
            totalText: hit.metric.formatted(hit.total),
            color: hit.color,
            rows: hit.rows,
            cursor: hit.cursor
        )
    }
}

private struct ActivityGlobalTooltipView: View {
    let tooltip: GlobalTooltip

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tooltip.title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            HStack(spacing: 6) {
                Circle()
                    .fill(tooltip.color)
                    .frame(width: 6, height: 6)
                Text(tooltip.model)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text(tooltip.valueText)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.95))
            }

            ForEach(tooltip.rows.filter { $0.model != tooltip.model }) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 6, height: 6)
                    Text(row.model)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer(minLength: 8)
                    Text(row.valueText)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            HStack {
                Text("Total")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text(tooltip.totalText)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
        .frame(width: 210)
    }
}

private struct PreparedChartData {
    let availableModels: [String]
    let displayedModels: [String]
    let daySlots: [Date]
    let daySlotRange: ClosedRange<Date>
    let paddedDaySlotRange: ClosedRange<Date>
    let valuesByDayModel: [Date: [String: ActivityValues]]
    let pointsByMetric: [ActivityMetric: [ChartPoint]]
    let nonZeroPointsByMetric: [ActivityMetric: [ChartPoint]]
    let totalSpend: Double
    let totalRequests: Int
    let totalTokens: Int

    static let empty: PreparedChartData = {
        let now = Calendar.current.startOfDay(for: Date())
        return PreparedChartData(
            availableModels: [],
            displayedModels: [],
            daySlots: [now],
            daySlotRange: now...now,
            paddedDaySlotRange: now...now,
            valuesByDayModel: [:],
            pointsByMetric: [:],
            nonZeroPointsByMetric: [:],
            totalSpend: 0,
            totalRequests: 0,
            totalTokens: 0
        )
    }()

    static func build(
        entries: [ActivityEntry],
        selectedTimeFilter: ActivityTimeFilter,
        selectedModelFilter: String,
        allModels: [String]
    ) -> PreparedChartData {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -(selectedTimeFilter.days - 1), to: endDay) ?? endDay
        let daySlots = (0..<selectedTimeFilter.days).compactMap { calendar.date(byAdding: .day, value: $0, to: startDay) }
        let daySlotRange: ClosedRange<Date> = (daySlots.first ?? endDay)...(daySlots.last ?? endDay)
        let paddedStart = calendar.date(byAdding: .hour, value: -12, to: daySlotRange.lowerBound) ?? daySlotRange.lowerBound
        let paddedEnd = calendar.date(byAdding: .hour, value: 12, to: daySlotRange.upperBound) ?? daySlotRange.upperBound
        let paddedDaySlotRange: ClosedRange<Date> = paddedStart...paddedEnd

        let displayedModels = selectedModelFilter == "All Models"
            ? allModels
            : (allModels.contains(selectedModelFilter) ? [selectedModelFilter] : [])

        let slotSet = Set(daySlots)
        var valuesByDayModel: [Date: [String: ActivityValues]] = [:]

        for entry in entries {
            guard let parsedDate = entry.parsedDate else { continue }
            let day = calendar.startOfDay(for: parsedDate)
            guard slotSet.contains(day) else { continue }
            if selectedModelFilter != "All Models" && entry.model != selectedModelFilter { continue }

            var dayModels = valuesByDayModel[day] ?? [:]
            var values = dayModels[entry.model] ?? ActivityValues()
            values.spend += entry.usage
            values.requests += entry.requests
            values.tokens += entry.totalTokens
            dayModels[entry.model] = values
            valuesByDayModel[day] = dayModels
        }

        var pointsByMetric: [ActivityMetric: [ChartPoint]] = [:]
        var nonZeroByMetric: [ActivityMetric: [ChartPoint]] = [:]

        for metric in ActivityMetric.allCases {
            let points = daySlots.flatMap { day in
                displayedModels.map { model in
                    let values = valuesByDayModel[day]?[model] ?? ActivityValues()
                    return ChartPoint(day: day, model: model, metric: metric, value: values.value(for: metric))
                }
            }
            pointsByMetric[metric] = points
            nonZeroByMetric[metric] = points.filter { $0.value > 0 }
        }

        let totalSpend = valuesByDayModel.values.flatMap { $0.values }.reduce(0) { $0 + $1.spend }
        let totalRequests = valuesByDayModel.values.flatMap { $0.values }.reduce(0) { $0 + $1.requests }
        let totalTokens = valuesByDayModel.values.flatMap { $0.values }.reduce(0) { $0 + $1.tokens }

        return PreparedChartData(
            availableModels: allModels,
            displayedModels: displayedModels,
            daySlots: daySlots,
            daySlotRange: daySlotRange,
            paddedDaySlotRange: paddedDaySlotRange,
            valuesByDayModel: valuesByDayModel,
            pointsByMetric: pointsByMetric,
            nonZeroPointsByMetric: nonZeroByMetric,
            totalSpend: totalSpend,
            totalRequests: totalRequests,
            totalTokens: totalTokens
        )
    }
}
