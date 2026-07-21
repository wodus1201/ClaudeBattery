import Cocoa

// MARK: - Pokémon-style flavor lines (by remaining HP %)
// Tone grounded in Pokémon-Amie/포켓파를레 emotional status messages
// (e.g. "울상을 짓고", "울어버린 것 같다").

func flavorLine(remaining: Int) -> String {
    switch remaining {
    case 90...100: return "클로드가 기운차게 뛰어다닌다!"
    case 70...89:  return "클로드가 콧노래를 부른다."
    case 45...69:  return "클로드가 조금 지친 기색이다."
    case 25...44:  return "클로드가 헥헥거리기 시작했다."
    case 10...24:  return "클로드가 울상을 짓고 있다."
    case 1...9:    return "클로드가 곧 쓰러질 것 같다!"
    default:       return "클로드가 쓰러졌다!"
    }
}

/// Shown in the dialogue slot while rate-limited (429): the app is dozing.
let SLEEP_MESSAGE = "클로드가 졸고 있다. 깨우지 말자.."

// MARK: - Petting (sprite click) lines
// Tone borrowed from Pokémon-Amie affection messages. Keyed off the same Mood
// that drives the HP-bar color, so the line always matches what the bar shows:
// lively when healthy, needy when hurt, unresponsive when fainted.

func pettingLines(mood: Mood) -> [String] {
    switch mood {
    case .healthy: return [          // green bar
        "클로드가 기뻐서 빙글빙글 돈다!",
        "클로드가 몸을 부비부비 해온다!",
        "클로드가 폴짝폴짝 뛰어오른다!",
        "클로드가 활짝 웃으며 올려다본다!",
        "클로드는 무척 행복해 보인다!",
    ]
    case .tired: return [            // orange bar
        "클로드가 기분 좋은 듯 눈을 감는다.",
        "클로드가 살며시 다가와 앉는다.",
        "클로드가 꼬리를 살랑살랑 흔든다.",
        "클로드가 나른하게 웃어 보인다.",
    ]
    case .hurt: return [             // red bar
        "클로드가 힘없이 몸을 기대온다..",
        "클로드가 당신의 손을 꼭 잡는다..",
        "클로드가 조금 기운을 낸 것 같다.",
        "클로드가 애써 미소를 지어 보인다..",
    ]
    case .fainted: return [
        "클로드는 쓰러져서 반응이 없다..",
        "클로드를 포켓몬센터에 데려가자..",
    ]
    // .happy is the reaction itself, never the state we react from.
    case .happy: return pettingLines(mood: .healthy)
    }
}

/// Petting reactions shown only while wearing a rare skin — the shiny reacts as
/// itself, not as a recolored Claude. Kept separate from pettingLines(mood:) so
/// they read as belonging to the skin rather than to the HP state.
///
/// Anything added here MUST also reach allSlotStrings(), or the first time one of
/// these appears the widget's slot resizes and the whole thing lurches.
func shinyPettingLines() -> [String] {
    [
        "이로치 클로드가 반짝반짝 빛난다!",
        "이로치 클로드가 자랑스럽게 뽐낸다!",
        "이로치 클로드가 눈부시게 웃는다!",
        "반짝이는 비늘이 손끝을 스친다!",
    ]
}

/// How long a petting reaction stays on screen before the normal slot cycle resumes.
let PETTING_HOLD: TimeInterval = 3.0

/// Shown instead of a countdown when the limit has no `resets_at`. The API omits
/// it for a limit whose window hasn't opened yet (nothing used ⇒ nothing to
/// reset), e.g. weekly_scoped before its first request. There is no arrival to
/// wait for, so say we're already there.
let ARRIVED_MESSAGE = "포켓몬센터 도착!"

/// The dialogue slot's countdown line: "time until the Pokémon Center" (i.e.
/// until the tracked limit resets). Returns the whole line, not just the
/// duration, because the no-countdown case drops the prefix entirely.
func resetKorean(_ date: Date?) -> String {
    guard let date = date else { return ARRIVED_MESSAGE }
    let secs = Int(date.timeIntervalSinceNow)
    if secs <= 0 { return ARRIVED_MESSAGE }
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    let left: String
    if d > 0      { left = "\(d)일 \(h)시간" }
    else if h > 0 { left = "\(h)시간 \(m)분" }
    else          { left = "\(m)분" }
    return "포켓몬센터까지 \(left)"
}

/// Every string the dialogue slot might ever display — used to reserve a fixed
/// slot width so the widget never reflows when the text swaps or the clock ticks.
func allSlotStrings() -> [String] {
    var s = [90, 70, 45, 25, 10, 5, 0].map { flavorLine(remaining: $0) }
    // Sprite-click reactions share the same slot, so reserve room for them too.
    s += [Mood.healthy, .tired, .hurt, .fainted].flatMap { pettingLines(mood: $0) }
    s += shinyPettingLines()   // shown only on the shiny, but the slot must fit them
    s.append(SLEEP_MESSAGE)
    s.append(ARRIVED_MESSAGE)
    // Longest plausible countdown renderings.
    s += ["포켓몬센터까지 23시간 59분", "포켓몬센터까지 6일 23시간"]
    return s
}
