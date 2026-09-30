import Foundation

// Published reference bands and thresholds behind "For you" and the recap
// copy. Everything here was checked against the paper or a reputable summary
// of it (docs/SCIENCE.md, 2026-09-24). A figure that could not be verified is
// left out, never guessed, so gaps are real gaps. Facts live in
// NormsFacts.swift. Nothing here is sex-specific beyond what the papers
// report, and nothing is a target: ranges describe who was measured.

enum AgeBand: String, CaseIterable, Codable, Sendable {
    case from16to24 = "16-24"
    case from25to34 = "25-34"
    case from35to44 = "35-44"
    case from45to54 = "45-54"
    case from55to64 = "55-64"
    case from65 = "65+"

    /// Under-16 input can't pass the age gate, but lands in the youngest band anyway.
    init(age: Int) {
        switch age {
        case ..<25: self = .from16to24
        case 25..<35: self = .from25to34
        case 35..<45: self = .from35to44
        case 45..<55: self = .from45to54
        case 55..<65: self = .from55to64
        default: self = .from65
        }
    }

    /// Only the birth year is stored, so the age can be a year high before the birthday.
    init(birthYear: Int, now: Date = Date(), calendar: Calendar = .current) {
        self.init(age: calendar.component(.year, from: now) - birthYear)
    }

    var label: String { rawValue }
}

/// Optional, because resting heart rate and HRV norms are reported by sex.
enum SexCategory: String, CaseIterable, Codable, Sendable {
    case female, male, nonBinary, undisclosed

    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .nonBinary: return "Non-binary"
        case .undisclosed: return "Prefer not to say"
        }
    }
}

/// What published studies report for one measure in one age band and sex.
struct PhysiologyNorm: Hashable, Sendable {
    enum Statistic: String, Sendable {
        /// `range` is the mean plus or minus one standard deviation: roughly
        /// the middle two thirds of the people measured.
        case meanSD
        /// `range` holds 95% of the people measured.
        case central95
    }

    let statistic: Statistic
    /// In the measure's unit (bpm or ms). nil when nothing verified covers the band.
    let range: ClosedRange<Double>?
    /// One UI-ready sentence, framed as data rather than a target.
    let summary: String
    /// Who was measured and how, for the "about this data" line.
    let basis: String
    let sources: [Norms.Source]

    /// "50–80", rounded to whole units; nil without a range.
    var rangeLabel: String? {
        guard let range = range else {
            return nil
        }
        return "\(Int(range.lowerBound.rounded()))\u{2013}\(Int(range.upperBound.rounded()))"
    }
}

enum Norms {
    struct Finding: Hashable, Sendable {
        let text: String
        let source: Source
    }

    struct Personal: Hashable, Sendable {
        let band: AgeBand
        let sex: SexCategory
        let restingHR: PhysiologyNorm
        /// Short-term SDNN in ms.
        let sdnn: PhysiologyNorm
    }

    static func baseline(for band: AgeBand, sex: SexCategory) -> Personal {
        return Personal(band: band, sex: sex, restingHR: restingHR(sex), sdnn: sdnn(band, sex: sex))
    }

    static let compareToYourself = Finding(
        text: "In 149,205 people, age and sex explained 17% of the differences in HRV; stress, mood and lifestyle under half a percent. Your own week is the yardstick.",
        source: .tegegne2018)

    static let shortSDNN = Finding(
        text: "The SDNN cut-offs cardiologists use come from 24-hour recordings. A short still-moment reading from a watch carries none of that meaning.",
        source: .shafferGinsberg2017)

    static let restingSwing = Finding(
        text: "A resting rate that moves 3 bpm across a week is the norm. Only 1 in 5 people ever see a week with a swing of 10 or more.",
        source: .quer2020)

    static let settling = Finding(
        text: "In a lab stress test, heart rate rose about 9 to 13 bpm at the peak and was back near baseline within about 10 minutes.",
        source: .helminen2023)

    static let sleepFloor = Finding(
        text: "Two expert panels put adult sleep at 7 to 9 hours a night. Regularly getting under 7 goes with worse health and performance.",
        source: .watson2015)

    // Quer et al. (2020): 92,457 Fitbit users over two years. The paper gives
    // 95% ranges by sex and no per-age band, so every band gets the same
    // figure. By age the mean rose only a little until about 50, then eased.
    private static func restingHR(_ sex: SexCategory) -> PhysiologyNorm {
        let basis = "92,457 US adults wearing a Fitbit for two years, all ages pooled; the study reports no per-age band"
        switch sex {
        case .male:
            return PhysiologyNorm(statistic: .central95, range: 50...80,
                                  summary: "In 92,457 adults tracked for two years, 95% of men had a resting heart rate between 50 and 80 bpm.",
                                  basis: basis, sources: [.quer2020])
        case .female:
            return PhysiologyNorm(statistic: .central95, range: 53...82,
                                  summary: "In 92,457 adults tracked for two years, 95% of women had a resting heart rate between 53 and 82 bpm.",
                                  basis: basis, sources: [.quer2020])
        case .nonBinary, .undisclosed:
            return PhysiologyNorm(statistic: .central95, range: 50...82,
                                  summary: "In 92,457 adults tracked for two years, most resting heart rates sat between about 50 and 82 bpm.",
                                  basis: basis + "; men's and women's 95% ranges combined", sources: [.quer2020])
        }
    }

    // Voss et al. (2015) is reported by sex from age 25; Nunan et al. (2010)
    // pools healthy adults of all ages. Nothing verified splits under-25s
    // out, so the youngest band gets the pooled figure.
    private static func sdnn(_ band: AgeBand, sex: SexCategory) -> PhysiologyNorm {
        guard let voss = vossSDNN(band) else {
            return PhysiologyNorm(statistic: .meanSD, range: MeanSD(mean: 50, sd: 16).range,
                                  summary: "Across 44 studies of 21,438 healthy adults, 5-minute SDNN averaged 50 ms, give or take 16. The youngest ages were not reported on their own.",
                                  basis: "Healthy adults of all ages pooled, 5-minute resting recordings; no verified figure singles out under-25s",
                                  sources: [.nunan2010])
        }
        let ages = band == .from65 ? "65-74" : band.label
        let basis = "1,906 healthy adults aged 25-74 in Germany (KORA S4), 5-minute resting ECG. A Watch SDNN comes from a shorter sample and is not the same measurement"
        switch sex {
        case .female:
            return PhysiologyNorm(statistic: .meanSD, range: voss.women.range,
                                  summary: "On a 5-minute ECG, women aged \(ages) averaged \(voss.women.sentence) (1,906 healthy adults).",
                                  basis: basis, sources: [.voss2015])
        case .male:
            return PhysiologyNorm(statistic: .meanSD, range: voss.men.range,
                                  summary: "On a 5-minute ECG, men aged \(ages) averaged \(voss.men.sentence) (1,906 healthy adults).",
                                  basis: basis, sources: [.voss2015])
        case .nonBinary, .undisclosed:
            let spread = Int(max(voss.women.sd, voss.men.sd).rounded())
            return PhysiologyNorm(statistic: .meanSD,
                                  range: min(voss.women.range.lowerBound, voss.men.range.lowerBound)...max(voss.women.range.upperBound, voss.men.range.upperBound),
                                  summary: "On a 5-minute ECG, women aged \(ages) averaged \(voss.women.rounded) ms SDNN and men \(voss.men.rounded), give or take up to \(spread) (1,906 healthy adults).",
                                  basis: basis + "; women's and men's bands combined", sources: [.voss2015])
        }
    }

    /// A published mean and standard deviation.
    private struct MeanSD {
        let mean: Double
        let sd: Double

        var range: ClosedRange<Double> {
            return (mean - sd)...(mean + sd)
        }

        var rounded: Int {
            return Int(mean.rounded())
        }

        var sentence: String {
            return "\(rounded) ms SDNN, give or take \(Int(sd.rounded()))"
        }
    }

    // Voss et al. (2015), tables 5 and 7: SDNN in ms, mean and SD, 5-minute
    // ECG at rest. n per cell 62-330.
    private static func vossSDNN(_ band: AgeBand) -> (women: MeanSD, men: MeanSD)? {
        switch band {
        case .from16to24: return nil
        case .from25to34: return (MeanSD(mean: 48.7, sd: 19.0), MeanSD(mean: 50.0, sd: 20.9))
        case .from35to44: return (MeanSD(mean: 45.4, sd: 20.5), MeanSD(mean: 44.6, sd: 16.8))
        case .from45to54: return (MeanSD(mean: 36.9, sd: 13.8), MeanSD(mean: 36.8, sd: 14.6))
        case .from55to64: return (MeanSD(mean: 30.6, sd: 12.4), MeanSD(mean: 32.8, sd: 14.7))
        case .from65: return (MeanSD(mean: 27.8, sd: 11.8), MeanSD(mean: 29.6, sd: 13.2))
        }
    }

    /// A number the detector or the copy leans on (SCIENCE.md section 11).
    struct Threshold: Hashable, Sendable {
        let name: String
        let range: ClosedRange<Double>
        let unit: String
        let sources: [Source]

        var isSingle: Bool {
            return range.lowerBound == range.upperBound
        }
    }

    enum Thresholds {
        static let wristRestingError = Threshold(name: "Wrist heart-rate error at rest", range: 4...5, unit: "bpm", sources: [.bent2020, .nelsonAllen2019])
        static let labStressRise = Threshold(name: "Heart-rate rise in a lab stress test", range: 9...13, unit: "bpm", sources: [.helminen2023, .fellinger2025])
        static let heartRateSettles = Threshold(name: "Heart rate back near baseline", range: 10...10, unit: "min", sources: [.helminen2023])
        static let cortisolPeak = Threshold(name: "Cortisol peak after a stressor starts", range: 21...40, unit: "min", sources: [.dickersonKemeny2004])
        static let cortisolSettles = Threshold(name: "Cortisol near baseline after a stressor ends", range: 60...60, unit: "min", sources: [.dickersonKemeny2004])
        static let unusualRestingSwing = Threshold(name: "Week-to-week resting swing only 1 in 5 people ever see", range: 10...10, unit: "bpm", sources: [.quer2020])
        static let sleepTarget = Threshold(name: "Sleep for adults 18-64", range: 7...9, unit: "h", sources: [.hirshkowitz2015, .watson2015])
        static let caffeineCutoff = Threshold(name: "A coffee (107 mg) before bed", range: 8.8...8.8, unit: "h", sources: [.gardiner2023])
        static let breathingPace = Threshold(name: "Resonance breathing pace", range: 4.5...6.5, unit: "breaths/min", sources: [.lehrerGevirtz2014, .shafferMeehan2020, .zaccaro2018])
        static let breathworkEffect = Threshold(name: "Breathwork on self-reported stress, Hedges' g", range: (-0.35)...(-0.35), unit: "g", sources: [.fincham2023])
        static let hrvBiofeedbackEffect = Threshold(name: "HRV biofeedback on stress, Hedges' g", range: 0.83...0.83, unit: "g", sources: [.goessl2017])
        static let socialMediaLimit = Threshold(name: "Social-media limit per platform per day", range: 10...10, unit: "min", sources: [.hunt2018])
        static let facebookDeactivation = Threshold(name: "Facebook deactivation, wellbeing", range: 0.09...0.09, unit: "SD", sources: [.allcott2020])

        static let all: [Threshold] = [
            wristRestingError, labStressRise, heartRateSettles, cortisolPeak, cortisolSettles,
            unusualRestingSwing, sleepTarget, caffeineCutoff, breathingPace, breathworkEffect,
            hrvBiofeedbackEffect, socialMediaLimit, facebookDeactivation
        ]
    }
}

extension Norms {
    enum Source: String, CaseIterable, Sendable {
        case quer2020, nunan2010, voss2015, shafferGinsberg2017, tegegne2018
        case helminen2023, fellinger2025, dickersonKemeny2004
        case hirshkowitz2015, watson2015, gardiner2023
        case lehrerGevirtz2014, shafferMeehan2020, zaccaro2018, fincham2023, goessl2017
        case hunt2018, allcott2020, bent2020, nelsonAllen2019

        /// Authors, year and journal.
        var citation: String {
            switch self {
            case .quer2020: return "Quer, Gouda, Galarnyk, Topol & Steinhubl (2020), PLoS ONE"
            case .nunan2010: return "Nunan, Sandercock & Brodie (2010), Pacing and Clinical Electrophysiology"
            case .voss2015: return "Voss, Schroeder, Heitmann, Peters & Perz (2015), PLoS ONE"
            case .shafferGinsberg2017: return "Shaffer & Ginsberg (2017), Frontiers in Public Health"
            case .tegegne2018: return "Tegegne, Man, van Roon, Riese & Snieder (2018), Heart Rhythm"
            case .helminen2023: return "Helminen & Scheer (2023), International Journal of Psychophysiology"
            case .fellinger2025: return "Fellinger et al. (2025), Neurobiology of Stress"
            case .dickersonKemeny2004: return "Dickerson & Kemeny (2004), Psychological Bulletin"
            case .hirshkowitz2015: return "Hirshkowitz et al. (2015), Sleep Health"
            case .watson2015: return "Watson et al. (2015), Journal of Clinical Sleep Medicine"
            case .gardiner2023: return "Gardiner, Weakley, Burke et al. (2023), Sleep Medicine Reviews"
            case .lehrerGevirtz2014: return "Lehrer & Gevirtz (2014), Frontiers in Psychology"
            case .shafferMeehan2020: return "Shaffer & Meehan (2020), Frontiers in Neuroscience"
            case .zaccaro2018: return "Zaccaro, Piarulli, Laurino et al. (2018), Frontiers in Human Neuroscience"
            case .fincham2023: return "Fincham, Strauss, Montero-Marin & Cavanagh (2023), Scientific Reports"
            case .goessl2017: return "Goessl, Curtiss & Hofmann (2017), Psychological Medicine"
            case .hunt2018: return "Hunt, Marx, Lipson & Young (2018), Journal of Social and Clinical Psychology"
            case .allcott2020: return "Allcott, Braghieri, Eichmeyer & Gentzkow (2020), American Economic Review"
            case .bent2020: return "Bent, Goldstein, Kibbe & Dunn (2020), npj Digital Medicine"
            case .nelsonAllen2019: return "Nelson & Allen (2019), JMIR mHealth and uHealth"
            }
        }

        /// A DOI or publisher link, kept as text; the view turns it into a URL.
        var url: String {
            switch self {
            case .quer2020: return "https://doi.org/10.1371/journal.pone.0227709"
            case .nunan2010: return "https://doi.org/10.1111/j.1540-8159.2010.02841.x"
            case .voss2015: return "https://doi.org/10.1371/journal.pone.0118308"
            case .shafferGinsberg2017: return "https://doi.org/10.3389/fpubh.2017.00258"
            case .tegegne2018: return "https://www.sciencedirect.com/science/article/abs/pii/S1547527118304727"
            case .helminen2023: return "https://doi.org/10.1016/j.ijpsycho.2023.03.005"
            case .fellinger2025: return "https://doi.org/10.1016/j.ynstr.2025.100760"
            case .dickersonKemeny2004: return "https://doi.org/10.1037/0033-2909.130.3.355"
            case .hirshkowitz2015: return "https://doi.org/10.1016/j.sleh.2014.12.010"
            case .watson2015: return "https://doi.org/10.5664/jcsm.4758"
            case .gardiner2023: return "https://doi.org/10.1016/j.smrv.2023.101764"
            case .lehrerGevirtz2014: return "https://doi.org/10.3389/fpsyg.2014.00756"
            case .shafferMeehan2020: return "https://doi.org/10.3389/fnins.2020.570400"
            case .zaccaro2018: return "https://doi.org/10.3389/fnhum.2018.00353"
            case .fincham2023: return "https://doi.org/10.1038/s41598-022-27247-y"
            case .goessl2017: return "https://doi.org/10.1017/S0033291717001003"
            case .hunt2018: return "https://doi.org/10.1521/jscp.2018.37.10.751"
            case .allcott2020: return "https://doi.org/10.1257/aer.20190658"
            case .bent2020: return "https://doi.org/10.1038/s41746-020-0226-6"
            case .nelsonAllen2019: return "https://doi.org/10.2196/10828"
            }
        }
    }
}
