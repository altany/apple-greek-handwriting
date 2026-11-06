import Foundation

/// Number mode (the 123 key): ML Kit has no digits-only model, so the keyboard re-ranks the
/// language model's candidates to prefer digits, and turns obvious look-alikes into digits.
enum NumberMode {
    /// Letters that, written alone in number mode, almost always meant a digit.
    static let lookalikes: [Character: Character] = [
        "O": "0", "o": "0", "Ο": "0", "ο": "0", "D": "0",
        "l": "1", "I": "1", "|": "1", "ι": "1", "Ι": "1", "i": "1",
        "Z": "2", "z": "2", "Ζ": "2",
        "S": "5", "s": "5",
        "b": "6", "G": "6",
        "T": "7", "Τ": "7",
        "B": "8", "Β": "8",
        "q": "9", "g": "9",
    ]
    /// Characters that belong in numbers besides digits.
    static let numberSymbols = Set(".,:/-+%€$°'\"()=×*")

    /// Reorders candidates so the most number-like come first. A candidate made only of digits,
    /// number symbols and look-alikes also gets a converted copy (e.g. "ιΟ" → "10").
    static func rank(_ candidates: [String]) -> [String] {
        var out: [String] = []
        for c in candidates {
            if let converted = convert(c), converted != c { out.append(converted) }
            out.append(c)
        }
        var seen = Set<String>()
        let unique = out.filter { seen.insert($0).inserted }
        // Stable sort by share of digits/symbols, highest first.
        return unique.enumerated()
            .sorted { a, b in
                let sa = numberShare(a.element), sb = numberShare(b.element)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
    }

    private static func convert(_ s: String) -> String? {
        var result = ""
        var hasDigit = false
        for ch in s where !ch.isWhitespace {
            if ch.isNumber { result.append(ch); hasDigit = true }
            else if numberSymbols.contains(ch) { result.append(ch) }
            else if let d = lookalikes[ch] { result.append(d); hasDigit = true }
            else { return nil }
        }
        return hasDigit ? result : nil
    }

    private static func numberShare(_ s: String) -> Double {
        let chars = s.filter { !$0.isWhitespace }
        guard !chars.isEmpty else { return 0 }
        let n = chars.filter { $0.isNumber || numberSymbols.contains($0) }.count
        return Double(n) / Double(chars.count)
    }
}
