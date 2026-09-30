import Foundation

/// One short, sourced line for the "For you" facts deck.
struct Fact: Identifiable, Hashable, Sendable {
    /// Which deck a fact belongs to. `all` facts show in every deck.
    enum Audience: String, CaseIterable, Sendable {
        case all, sleep, hrv, breathing, social
    }

    let id: String
    let text: String
    /// Authors, year and journal.
    let citation: String
    /// A DOI or publisher link, kept as text; the view turns it into a URL.
    let url: String
    let audience: Audience
}

// Every text stays at or under 160 characters, says what bodies did in a
// study and cites authors, year and journal (App Store 1.4.1: associations
// only, no health claims). No fact names a condition the app could seem to
// detect. Source of truth is docs/facts.json; eight lines were shortened to
// fit and two reworded off the never-say list.
enum Facts {
    static let all: [Fact] = [
        Fact(id: "hr-01", text: "Across 92,457 people tracked for two years, average resting heart rate was 65.5 bpm. Individual averages ran from 40 to 109. Yours is yours.", citation: "Quer, Gouda, Galarnyk, Topol & Steinhubl 2020, PLoS ONE", url: "https://doi.org/10.1371/journal.pone.0227709", audience: .all),
        Fact(id: "hr-04", text: "A resting heart rate that wanders 3 bpm across a week is the norm. Only about 1 in 5 people ever have a week where it swings 10 or more.", citation: "Quer et al. 2020, PLoS ONE", url: "https://doi.org/10.1371/journal.pone.0227709", audience: .all),
        Fact(id: "hr-05", text: "The lowest resting heart rates in a 92,457-person cohort belonged to people averaging 7 to 7.5 hours of sleep. Sleeping less, or more, ran slightly higher.", citation: "Quer et al. 2020, PLoS ONE", url: "https://doi.org/10.1371/journal.pone.0227709", audience: .sleep),
        Fact(id: "hrv-01", text: "HRV is the jitter between heartbeats, in milliseconds. More jitter usually means the calm branch of your nervous system is getting a word in.", citation: "Shaffer & Ginsberg 2017, Frontiers in Public Health", url: "https://doi.org/10.3389/fpubh.2017.00258", audience: .hrv),
        Fact(id: "hrv-02", text: "Apple Watch's classic HRV number is SDNN: the spread of your beat-to-beat intervals, from short samples taken while still. Newer watches add Recovery HRV.", citation: "Apple Developer Documentation (HealthKit heartRateVariabilitySDNN); Apple Support 120277; Empirical Health, How wearables measure HRV", url: "https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn", audience: .hrv),
        Fact(id: "hrv-04", text: "HRV falls with age. In 1,906 healthy adults, RMSSD averaged 43 ms for women aged 25-34 and 19 ms at 65-74. Men: 40 down to 19.", citation: "Voss, Schroeder, Heitmann, Peters & Perz 2015, PLoS ONE", url: "https://doi.org/10.1371/journal.pone.0118308", audience: .hrv),
        Fact(id: "hrv-05", text: "In 8.2 million tracker users, the high-frequency part of HRV fell about 80% between ages 20 and 60. Comparing your HRV to a 25-year-old's is unfair.", citation: "Natarajan, Pantelopoulos, Emir-Farinas & Natarajan 2020, The Lancet Digital Health", url: "https://doi.org/10.1016/S2589-7500(20)30246-6", audience: .hrv),
        Fact(id: "hrv-06", text: "In 149,205 people, age and sex explained 17% of the differences in HRV. Stress, mood and lifestyle together explained under half a percent. Compare you to you.", citation: "Tegegne, Man, van Roon, Riese & Snieder 2018, Heart Rhythm", url: "https://www.sciencedirect.com/science/article/abs/pii/S1547527118304727", audience: .hrv),
        Fact(id: "hrv-07", text: "Cardiologists have 24-hour SDNN cut-offs from heart-attack studies. A 5-minute SDNN from a watch is a different animal and carries none of that meaning.", citation: "Shaffer & Ginsberg 2017, Frontiers in Public Health", url: "https://doi.org/10.3389/fpubh.2017.00258", audience: .hrv),
        Fact(id: "hrv-09", text: "Wrist HRV gets shaky when you move or talk. In one lab test the watch produced no reading at all in 44% of conversation sessions. Stillness is the price.", citation: "Bonneval, Wing, Sharp et al. 2025, Sensors", url: "https://doi.org/10.3390/s25082380", audience: .hrv),
        Fact(id: "stress-01", text: "The lab's favourite stress test is a short speech plus mental arithmetic in front of an unimpressed panel. Cortisol typically rises 2- to 4-fold.", citation: "Kirschbaum, Pirke & Hellhammer 1993, Neuropsychobiology", url: "https://doi.org/10.1159/000119004", audience: .all),
        Fact(id: "stress-02", text: "In two recent versions of that lab stress test, heart rate rose about 9 to 13 bpm at the peak and was back near baseline within 10 minutes.", citation: "Helminen & Scheer 2023, International Journal of Psychophysiology; Fellinger et al. 2025, Neurobiology of Stress", url: "https://doi.org/10.1016/j.ijpsycho.2023.03.005", audience: .all),
        Fact(id: "stress-03", text: "Across 208 lab studies, the stressors that moved cortisol most were the ones where you could be judged and could not control the outcome. Meetings, basically.", citation: "Dickerson & Kemeny 2004, Psychological Bulletin", url: "https://doi.org/10.1037/0033-2909.130.3.355", audience: .all),
        Fact(id: "stress-04", text: "Cortisol peaks 21 to 40 min after a stressor starts; after a judged, no-control task it was still up at 60 min. The body's exit is slower than yours.", citation: "Dickerson & Kemeny 2004, Psychological Bulletin", url: "https://doi.org/10.1037/0033-2909.130.3.355", audience: .all),
        Fact(id: "stress-05", text: "Replaying a stressful thing keeps the body in it: worry and rumination go with higher heart rate, higher cortisol and lower HRV across 60 studies.", citation: "Ottaviani, Thayer, Verkuil et al. 2016, Psychological Bulletin", url: "https://doi.org/10.1037/bul0000036", audience: .all),
        Fact(id: "sleep-01", text: "Two expert panels: 7 to 9 hours a night for adults 18-64, 7 to 8 at 65 and over. Regularly getting under 7 is linked with worse health and performance.", citation: "Hirshkowitz et al. 2015, Sleep Health; Watson et al. 2015, Journal of Clinical Sleep Medicine", url: "https://doi.org/10.1016/j.sleh.2014.12.010", audience: .sleep),
        Fact(id: "sleep-02", text: "After one night without sleep, people found a mildly annoying task more stressful and angering than rested people did. The big stressor felt the same to both.", citation: "Minkel et al. 2012, Emotion", url: "https://doi.org/10.1037/a0026871", audience: .sleep),
        Fact(id: "sleep-03", text: "Skip a night of sleep and the brain's alarm centre reacts over 60% more strongly to upsetting images, with the prefrontal brakes loosened.", citation: "Yoo, Gujar, Hu, Jolesz & Walker 2007, Current Biology", url: "https://doi.org/10.1016/j.cub.2007.08.007", audience: .sleep),
        Fact(id: "sleep-04", text: "154 experiments, 5,717 people: losing sleep reliably flattens good mood and raises unease. Bad mood is less consistent. Flatness is the tell.", citation: "Palmer, Bower, Cho et al. 2024, Psychological Bulletin", url: "https://doi.org/10.1037/bul0000410", audience: .sleep),
        Fact(id: "sleep-05", text: "In 1,982 adults tracked for 8 days, a shorter-than-usual night meant bigger dips in good mood after a stressor and less lift from good news.", citation: "Sin, Wen, Klaiber, Buxton & Almeida 2020, Health Psychology", url: "https://doi.org/10.1037/hea0001033", audience: .sleep),
        Fact(id: "sleep-07", text: "Sleep-deprived people pulled back from others, and well-rested strangers felt lonelier after watching a short video of them. Loneliness is catching.", citation: "Ben Simon & Walker 2018, Nature Communications", url: "https://doi.org/10.1038/s41467-018-05377-0", audience: .sleep),
        Fact(id: "caff-01", text: "Across 24 studies, caffeine cost about 45 minutes of sleep. To stay clear, a cup of coffee (107 mg) wants to be 8.8 hours before bed.", citation: "Gardiner, Weakley, Burke et al. 2023, Sleep Medicine Reviews", url: "https://doi.org/10.1016/j.smrv.2023.101764", audience: .sleep),
        Fact(id: "caff-03", text: "500 mg of caffeine on a workday raised blood pressure by 4/3 mmHg and adrenaline by 32%, and amplified the heart-rate rise on stressful moments.", citation: "Lane, Pieper, Phillips-Bute, Bryant & Kuhn 2002, Psychosomatic Medicine", url: "https://doi.org/10.1097/01.psy.0000021946.90613.db", audience: .all),
        Fact(id: "caff-04", text: "In 77 people, vagal HRV went up after espresso, decaf and warm water alike; caffeine did not tank it. Its stress story is mostly about sleep.", citation: "Zimmermann-Viehoff, Thayer, Koenig et al. 2016, Nutritional Neuroscience", url: "https://doi.org/10.1179/1476830515Y.0000000018", audience: .hrv),
        Fact(id: "caff-05", text: "Caffeine's half-life in adults is 3 to 7 hours. A 3 pm coffee is still half there at bedtime for a lot of people.", citation: "Temple, Bernard, Lipshultz, Czachor, Westphal & Mestre 2017, Frontiers in Psychiatry", url: "https://doi.org/10.3389/fpsyt.2017.00080", audience: .all),
        Fact(id: "breath-01", text: "Slow breathing raises vagal HRV while you do it, right after, and after a few weeks of practice. 223 studies, one meta-analysis.", citation: "Laborde, Allen, Borges et al. 2022, Neuroscience & Biobehavioral Reviews", url: "https://doi.org/10.1016/j.neubiorev.2022.104711", audience: .breathing),
        Fact(id: "breath-02", text: "Most adults' resonance breathing rate is 4.5 to 6.5 breaths a minute: roughly a 10-second breath. Slower than you think. That is the point.", citation: "Shaffer & Meehan 2020, Frontiers in Neuroscience", url: "https://doi.org/10.3389/fnins.2020.570400", audience: .breathing),
        Fact(id: "breath-03", text: "Training HRV with slow breathing eased stress and worry with an effect size of 0.83 versus controls across 24 studies. Large, for breathing.", citation: "Goessl, Curtiss & Hofmann 2017, Psychological Medicine", url: "https://doi.org/10.1017/S0033291717001003", audience: .breathing),
        Fact(id: "breath-04", text: "Across 12 randomised trials (785 adults), breathwork lowered self-reported stress by a small-to-medium amount (g = -0.35). Not magic. Real.", citation: "Fincham, Strauss, Montero-Marin & Cavanagh 2023, Scientific Reports", url: "https://doi.org/10.1038/s41598-022-27247-y", audience: .breathing),
        Fact(id: "breath-05", text: "Five minutes a day of cyclic sighing (double inhale, long exhale) lifted mood and slowed breathing more than five minutes of mindfulness, over a month.", citation: "Balban, Neri, Kogon et al. 2023, Cell Reports Medicine", url: "https://doi.org/10.1016/j.xcrm.2022.100895", audience: .breathing),
        Fact(id: "social-01", text: "Naming a feeling, even just labelling a face as 'afraid', dampened the brain's alarm centre in scans and engaged the prefrontal cortex. Words are not nothing.", citation: "Lieberman, Eisenberger, Crockett, Tom, Pfeifer & Way 2007, Psychological Science", url: "https://doi.org/10.1111/j.1467-9280.2007.01916.x", audience: .social),
        Fact(id: "social-03", text: "Roughly nine in ten emotional experiences get told to someone in Rimé's studies, usually more than once. You were going to share this anyway.", citation: "Rimé, Mesquita, Philippot & Boca 1991, Cognition & Emotion; Rimé 2009, Emotion Review", url: "https://doi.org/10.1080/02699939108411052", audience: .social),
        Fact(id: "social-04", text: "People underestimate how often their peers feel bad, partly because bad feelings get hidden. Lower guesses went with more loneliness.", citation: "Jordan, Monin, Dweck, Lovett, John & Gross 2011, Personality and Social Psychology Bulletin", url: "https://doi.org/10.1177/0146167210390822", audience: .social),
        Fact(id: "social-05", text: "Having a best friend nearby before a lab stress test lowered the cortisol response in 37 men. Company changes chemistry.", citation: "Heinrichs, Baumgartner, Kirschbaum & Ehlert 2003, Biological Psychiatry", url: "https://doi.org/10.1016/S0006-3223(03)00465-7", audience: .social),
        Fact(id: "compare-02", text: "Scrolling without posting lowered mood over time, and the study's explanation was envy. Other people's highlight reels are not your baseline.", citation: "Verduyn, Lee, Park et al. 2015, Journal of Experimental Psychology: General", url: "https://doi.org/10.1037/xge0000057", audience: .social),
        Fact(id: "compare-03", text: "Limiting Instagram, Facebook and Snapchat to 10 minutes each a day for 3 weeks lowered loneliness and low mood in 143 students.", citation: "Hunt, Marx, Lipson & Young 2018, Journal of Social and Clinical Psychology", url: "https://doi.org/10.1521/jscp.2018.37.10.751", audience: .social),
        Fact(id: "compare-05", text: "Honesty note: in 355,358 teenagers, screen use explained at most 0.4% of wellbeing. Feeds are not the whole story; how you use them might be.", citation: "Orben & Przybylski 2019, Nature Human Behaviour", url: "https://doi.org/10.1038/s41562-018-0506-1", audience: .social),
        Fact(id: "wear-01", text: "Wrist sensors are good at rest: about 4 to 5 bpm off in a 53-person test. Errors ran about 30% higher when moving. Skin tone did not matter.", citation: "Bent, Goldstein, Kibbe & Dunn 2020, npj Digital Medicine", url: "https://doi.org/10.1038/s41746-020-0226-6", audience: .all),
        Fact(id: "wear-02", text: "Wearable stress algorithms score 70-97% in lab studies, nearly all with under 30 people. Almost none were tested on a separate dataset. We say so.", citation: "Vos, Trinh, Sarnyai & Rahimi Azghadi 2023, International Journal of Medical Informatics", url: "https://doi.org/10.1016/j.ijmedinf.2023.105026", audience: .all),
        Fact(id: "wear-03", text: "In 1,002 people wearing sensors for 5 days, some bodies barely reacted to reported stress. A wearable can miss you entirely. Your tag beats our guess.", citation: "Smets, Rios Velazquez, Schiavone et al. 2018, npj Digital Medicine", url: "https://doi.org/10.1038/s41746-018-0074-9", audience: .all)
    ]

    /// The general facts plus the ones for `audience`; `.all` returns every fact.
    static func `for`(audience: Fact.Audience) -> [Fact] {
        guard audience != .all else {
            return all
        }
        return all.filter { $0.audience == .all || $0.audience == audience }
    }
}
