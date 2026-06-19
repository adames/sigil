import Foundation

/// Token format for `--simulate-keys`:
///
///   plain letters / digits   →  .char(c)
///   <ESC>                    →  .escape
///   <CR> / <ENTER>           →  .enter
///   <UP> / <DOWN>            →  .up / .down
///   <TAB> / <STAB>           →  .tab / .backTab
///
/// Anything else falls through as a literal char. Built for headless
/// smoke-testing with key strings like "3", "9<ESC>", or "<DOWN><CR>".
enum KeySequenceParser {
    static func parse(_ raw: String) -> [PromptKey] {
        var out: [PromptKey] = []
        var i = raw.startIndex
        while i < raw.endIndex {
            if raw[i] == "<" {
                if let close = raw[i...].firstIndex(of: ">") {
                    let token = String(raw[raw.index(after: i)..<close]).uppercased()
                    switch token {
                    case "ESC":            out.append(.escape)
                    case "CR", "ENTER":    out.append(.enter)
                    case "UP":             out.append(.up)
                    case "DOWN":           out.append(.down)
                    case "TAB":            out.append(.tab)
                    case "STAB":           out.append(.backTab)
                    default:
                        // Unknown token — emit the literal "<token>" so a
                        // typo is loud rather than silently dropped.
                        for c in "<\(token)>" { out.append(.char(c)) }
                    }
                    i = raw.index(after: close)
                    continue
                }
            }
            out.append(.char(raw[i]))
            i = raw.index(after: i)
        }
        return out
    }
}

/// Prints the final action in a stable, grep-friendly format and returns
/// the exit code.
enum SimulateReporter {
    static func print(action: PromptAction, mode: PromptMode) -> Int32 {
        switch action {
        case .idle:
            Swift.print("action=idle mode=\(mode.rawValue)")
            return 0
        case .move:
            Swift.print("action=move mode=\(mode.rawValue)")
            return 0
        case .reject:
            Swift.print("action=reject mode=\(mode.rawValue)")
            return 0
        case .commitSend(let slot):
            Swift.print("action=commit mode=send helper=ws-send-follow arg=\(slot)")
            return 0
        case .cancel:
            Swift.print("action=cancel mode=\(mode.rawValue)")
            return 1
        }
    }
}
