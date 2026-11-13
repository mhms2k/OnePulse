import Foundation

/// A piece of personalised feedback shown on the Today screen.
struct Insight: Identifiable, Hashable {
    enum Tone: Hashable { case positive, neutral, caution }
    enum Category: String, Hashable { case recovery, sleep, strain, vitals, trend }

    var id: String
    var category: Category
    var tone: Tone
    var symbol: String   // SF Symbol name
    var title: String
    var message: String
}

/// Rule-based coach that turns scores into plain-language feedback.
struct Coach {
    var engine: ScoreEngine

    /// Bedtime plan for tonight based on today's strain, current sleep debt and wake time.
    struct BedtimePlan {
        var need: TimeInterval
        var bedtime: Date
        var wake: Date
        var breakdown: ScoreEngine.SleepNeed
    }

    func bedtimePlan(today: DayScore, history: [DayScore], now: Date = Date()) -> BedtimePlan {
        let need = engine.sleepNeed(after: today, priorNights: history)
        let wakeMinutes = engine.typicalWakeMinutes(history: history + [today])
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today.day)) ?? now
        let wake = cal.date(byAdding: .minute, value: wakeMinutes, to: tomorrow) ?? now
        // Allow for time awake in bed using recent efficiency.
        let efficiency = Stats.mean(history.suffix(7).compactMap(\.efficiency)).map { max(75, $0) / 100 } ?? 0.9
        let inBed = need.total / efficiency
        return BedtimePlan(need: need.total, bedtime: wake.addingTimeInterval(-inBed), wake: wake, breakdown: need)
    }

    func insights(today s: DayScore, history: [DayScore]) -> [Insight] {
        var out: [Insight] = []

        // 1. Recovery headline & strain target
        if let rec = s.recovery {
            let zone = RecoveryZone(rec)
            let target = zone.strainTarget
            let range = "\(Int(target.lowerBound))–\(Int(target.upperBound))"
            switch zone {
            case .green:
                out.append(Insight(id: "rec", category: .recovery, tone: .positive, symbol: "bolt.heart.fill",
                                   title: "Green light: \(Int(rec))% recovered",
                                   message: "Your body is primed for load. A strain of \(range) today will build fitness without digging a hole."))
            case .yellow:
                out.append(Insight(id: "rec", category: .recovery, tone: .neutral, symbol: "heart.circle.fill",
                                   title: "Moderately recovered (\(Int(rec))%)",
                                   message: "Train, but keep it controlled — aim for a strain of \(range). Quality sleep tonight will move you back to green."))
            case .red:
                out.append(Insight(id: "rec", category: .recovery, tone: .caution, symbol: "bed.double.fill",
                                   title: "Low recovery (\(Int(rec))%)",
                                   message: "Your body is still absorbing stress. Keep strain under \(Int(target.upperBound)): easy movement, hydration and an early night."))
            }
        } else if s.isCalibrating {
            let n = max(1, s.nightsUntilCalibrated)
            out.append(Insight(id: "cal", category: .recovery, tone: .neutral, symbol: "hourglass",
                               title: "Learning your baseline",
                               message: "Wear your watch to sleep for \(n) more night\(n == 1 ? "" : "s") to unlock your Recovery score. Everything is judged against your own normal, not population averages."))
        }

        // 2. Sleep sufficiency
        if let perf = s.sleepPerformance {
            let short = s.sleepNeed - s.asleep
            if perf >= 90 {
                out.append(Insight(id: "sleep", category: .sleep, tone: .positive, symbol: "moon.stars.fill",
                                   title: "You met your sleep need",
                                   message: "\(Format.duration(s.asleep)) of the \(Format.duration(s.sleepNeed)) your body asked for (\(Int(perf))%)."))
            } else if perf < 70 {
                out.append(Insight(id: "sleep", category: .sleep, tone: .caution, symbol: "moon.zzz.fill",
                                   title: "Short night: \(Int(perf))% of need",
                                   message: "You were \(Format.duration(short)) short. Most of that carries into tonight as sleep debt — performance and mood dip noticeably below 70%."))
            } else {
                out.append(Insight(id: "sleep", category: .sleep, tone: .neutral, symbol: "moon.fill",
                                   title: "\(Int(perf))% of your sleep need",
                                   message: "\(Format.duration(s.asleep)) asleep vs \(Format.duration(s.sleepNeed)) needed. An extra \(Format.duration(max(0, short))) would have topped you up."))
            }
        }

        // 3. Sleep quality details
        if s.asleep >= 5 * 3600, s.deep + s.rem > 0 {
            let deepPct = s.deep / s.asleep * 100
            let remPct = s.rem / s.asleep * 100
            if deepPct < 12 {
                out.append(Insight(id: "deep", category: .sleep, tone: .caution, symbol: "waveform.path.ecg",
                                   title: "Light on deep sleep (\(Int(deepPct))%)",
                                   message: "Deep sleep is when your body repairs muscle. Alcohol, late meals and a warm room are the usual culprits; a hard training day often increases it."))
            }
            if remPct < 17 {
                out.append(Insight(id: "rem", category: .sleep, tone: .neutral, symbol: "brain.head.profile",
                                   title: "REM was low (\(Int(remPct))%)",
                                   message: "REM sleep concentrates in the last hours of the night, so cutting sleep short or an alarm too early trims it first."))
            }
        }
        if let eff = s.efficiency, s.hasSleep, eff < 85 {
            out.append(Insight(id: "eff", category: .sleep, tone: .neutral, symbol: "clock.badge.exclamationmark",
                               title: "\(Format.duration(s.awake)) awake in bed",
                               message: "Sleep efficiency was \(Int(eff))%. Keep the bed for sleep, and if you can't fall asleep in ~20 minutes, get up briefly."))
        }
        if let cons = s.consistency, cons < 65 {
            out.append(Insight(id: "cons", category: .sleep, tone: .neutral, symbol: "calendar.badge.clock",
                               title: "Irregular sleep schedule (\(Int(cons))%)",
                               message: "Your bed and wake times have been shifting. A steady schedule is one of the strongest levers for a lower resting HR and higher HRV."))
        }

        // 4. Vitals out of range
        if let rhr = s.restingHR, let b = s.rhrBaseline, rhr - b.mean >= max(4, 1.5 * b.sd) {
            out.append(Insight(id: "rhr", category: .vitals, tone: .caution, symbol: "heart.text.square.fill",
                               title: "Resting HR up \(Int((rhr - b.mean).rounded())) bpm",
                               message: "\(Int(rhr)) bpm vs your normal \(Int(b.mean.rounded())). Common causes: alcohol, a late meal, dehydration, heat, accumulated training or the start of an illness."))
        }
        if let st = s.overnightStress, let b = s.stressBaseline, b.z(st) >= 1.5 {
            out.append(Insight(id: "stress", category: .vitals, tone: .caution, symbol: "brain",
                               title: "Elevated overnight stress",
                               message: "Your nervous system stayed more 'switched on' than usual while you slept (\(Int(st)) vs \(Int(b.mean)))."))
        }
        if let hrv = s.hrv, let b = s.hrvBaseline, hrv > 0, b.z(log(hrv)) <= -1.5 {
            out.append(Insight(id: "hrv", category: .vitals, tone: .caution, symbol: "waveform.path",
                               title: "HRV below your normal",
                               message: "\(Int(hrv)) ms vs a typical \(Int(exp(b.mean))) ms. Your body is prioritising recovery — go easier today."))
        }
        if let spo2 = s.spo2, spo2 < 94 {
            out.append(Insight(id: "spo2", category: .vitals, tone: .caution, symbol: "lungs.fill",
                               title: String(format: "Overnight SpO₂ %.1f%%", spo2),
                               message: "Lower than typical. Wrist readings can be thrown off by a loose fit; if it stays low or you snore heavily, mention it to a doctor."))
        }

        // 5. Strain context
        if let prev = history.last, let rec = s.recovery, prev.strain >= 17, rec < 50 {
            out.append(Insight(id: "load", category: .strain, tone: .neutral, symbol: "flame.fill",
                               title: "Yesterday's strain (\(String(format: "%.1f", prev.strain))) is showing",
                               message: "A big day followed by a lower recovery is normal. Two or three such days in a row is when to schedule a rest day."))
        }
        let weekStrain = history.suffix(6).map(\.strain) + [s.strain]
        if weekStrain.count >= 5, let avg = Stats.mean(weekStrain), avg < 6, s.recovery.map({ $0 >= 50 }) ?? true {
            out.append(Insight(id: "under", category: .strain, tone: .neutral, symbol: "figure.walk",
                               title: "Low weekly load",
                               message: String(format: "Average strain this week is %.1f. Adding two moderate sessions would raise your fitness without hurting recovery.", avg)))
        }

        // 6. Trends
        let last7 = history.suffix(6).compactMap(\.recovery) + (s.recovery.map { [$0] } ?? [])
        let prior = history.dropLast(6).suffix(21).compactMap(\.recovery)
        if last7.count >= 4, prior.count >= 7, let a = Stats.mean(last7), let b = Stats.mean(prior) {
            if a - b >= 8 {
                out.append(Insight(id: "trendUp", category: .trend, tone: .positive, symbol: "chart.line.uptrend.xyaxis",
                                   title: "Recovery trending up",
                                   message: "This week's average is \(Int(a))%, up from \(Int(b))% before. Whatever you changed, it's working."))
            } else if b - a >= 8 {
                out.append(Insight(id: "trendDown", category: .trend, tone: .caution, symbol: "chart.line.downtrend.xyaxis",
                                   title: "Recovery trending down",
                                   message: "This week's average is \(Int(a))%, down from \(Int(b))%. Look at sleep timing, alcohol and training load."))
            }
        }
        return out
    }
}
