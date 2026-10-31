import Foundation

/// A deliberately bounded linear UCUM subset, not a terminology service or
/// clinical comparability rule. Unknown/special/arbitrary units never cancel
/// out of a term. Original printed units are kept by the comparison separately.
enum LabUnit {
    enum Failure: Error, Equatable, Sendable {
        case syntax, unsupported(String), annotation, limit, dimensions, nonterminating, precision
        case number(LabHistory.NumberIssue)
        var message: String {
            switch self {
            case .syntax: return "Use a supported case-sensitive UCUM code. No spaces or display abbreviations are inferred."
            case .unsupported(let code): return "This unit code is not supported for linear conversion: " + code
            case .annotation: return "Annotated units are kept as wording. Their clinical meaning was not inferred."
            case .limit: return "The unit expression exceeds the supported conversion limits."
            case .dimensions: return "These units describe different quantities. No conversion was made."
            case .nonterminating: return "This conversion has no exact finite decimal result. No rounded value was used."
            case .precision: return "The exact converted value exceeds the supported decimal precision or range."
            case .number(let issue): return issue.message
            }
        }
    }
    struct Unit: Equatable, Sendable {
        let code: String
        // Mole is an additional semantic tag here. Never reduce it to count or
        // infer a mass/mole or analyte conversion from dimensional arithmetic.
        fileprivate let dimensions: [String: Int]
        fileprivate let primes: [Int: Int]
        fileprivate let ratioBasis: Set<String>
        func compatibleQuantity(with other: Unit) -> Bool {
            dimensions == other.dimensions && (ratioBasis.isEmpty || other.ratioBasis.isEmpty || ratioBasis == other.ratioBasis)
        }
        func sameMagnitude(as other: Unit) -> Bool { dimensions == other.dimensions && primes == other.primes && ratioBasis == other.ratioBasis }
    }
    struct Conversion: Sendable {
        let number: LabHistory.Number
        let from: Unit
        let to: Unit
        let factor: String
    }
    private struct Term {
        var dimensions: [String: Int] = [:]
        var primes: [Int: Int] = [:]
        var chemicalAxes: Set<String> = []
        func combining(_ other: Term, power: Int = 1) throws -> Term {
            var next = self
            if power != 0 { next.chemicalAxes.formUnion(other.chemicalAxes) }
            for (key, value) in other.dimensions { next.dimensions[key, default: 0] += value * power }
            for (key, value) in other.primes { next.primes[key, default: 0] += value * power }
            next.dimensions = next.dimensions.filter { $0.value != 0 }; next.primes = next.primes.filter { $0.value != 0 }
            guard next.dimensions.values.allSatisfy({ abs($0) <= 64 }), next.primes.count <= 16,
                  next.primes.values.allSatisfy({ abs($0) <= 1024 }) else { throw Failure.limit }
            return next
        }
        func raised(_ power: Int) throws -> Term { try Term().combining(self, power: power) }
    }
    private struct Atom {
        let term: Term
        var metric = true
    }
    // Independently expressed definitions from the UCUM2.2 specification.
    // g and C are base axes in this representation; SI derived mass uses kg.
    private static func scaled(_ dimensions: [String: Int] = [:], ten: Int = 0, primes: [Int: Int] = [:]) -> Term {
        var factors = primes; factors[2, default: 0] += ten; factors[5, default: 0] += ten
        return Term(dimensions: dimensions, primes: factors.filter { $0.value != 0 }, chemicalAxes: Set(dimensions.keys).intersection(["g", "mol"]))
    }
    private static let atoms: [String: Atom] = [
        "m": .init(term: scaled(["m": 1])), "g": .init(term: scaled(["g": 1])),
        "s": .init(term: scaled(["s": 1])), "K": .init(term: scaled(["K": 1])),
        "C": .init(term: scaled(["C": 1])), "cd": .init(term: scaled(["cd": 1])),
        "rad": .init(term: scaled(["rad": 1])), "mol": .init(term: scaled(["mol": 1])),
        "sr": .init(term: scaled(["rad": 2])), "Hz": .init(term: scaled(["s": -1])),
        "N": .init(term: scaled(["g": 1, "m": 1, "s": -2], ten: 3)),
        "Pa": .init(term: scaled(["g": 1, "m": -1, "s": -2], ten: 3)),
        "J": .init(term: scaled(["g": 1, "m": 2, "s": -2], ten: 3)),
        "W": .init(term: scaled(["g": 1, "m": 2, "s": -3], ten: 3)),
        "A": .init(term: scaled(["C": 1, "s": -1])),
        "V": .init(term: scaled(["g": 1, "m": 2, "s": -2, "C": -1], ten: 3)),
        "F": .init(term: scaled(["g": -1, "m": -2, "s": 2, "C": 2], ten: -3)),
        "Ohm": .init(term: scaled(["g": 1, "m": 2, "s": -1, "C": -2], ten: 3)),
        "S": .init(term: scaled(["g": -1, "m": -2, "s": 1, "C": 2], ten: -3)),
        "Wb": .init(term: scaled(["g": 1, "m": 2, "s": -1, "C": -1], ten: 3)),
        "T": .init(term: scaled(["g": 1, "s": -1, "C": -1], ten: 3)),
        "H": .init(term: scaled(["g": 1, "m": 2, "C": -2], ten: 3)),
        "lm": .init(term: scaled(["cd": 1, "rad": 2])),
        "lx": .init(term: scaled(["cd": 1, "rad": 2, "m": -2])),
        "Bq": .init(term: scaled(["s": -1])),
        "Gy": .init(term: scaled(["m": 2, "s": -2])), "Sv": .init(term: scaled(["m": 2, "s": -2])),
        "l": .init(term: scaled(["m": 3], ten: -3)), "L": .init(term: scaled(["m": 3], ten: -3)),
        "ar": .init(term: scaled(["m": 2], ten: 2)), "t": .init(term: scaled(["g": 1], ten: 6)),
        "min": .init(term: scaled(["s": 1], primes: [2: 2, 3: 1, 5: 1]), metric: false),
        "h": .init(term: scaled(["s": 1], primes: [2: 4, 3: 2, 5: 2]), metric: false),
        "d": .init(term: scaled(["s": 1], primes: [2: 7, 3: 3, 5: 2]), metric: false),
        "wk": .init(term: scaled(["s": 1], primes: [2: 7, 3: 3, 5: 2, 7: 1]), metric: false),
        "kat": .init(term: scaled(["mol": 1, "s": -1])),
        "U": .init(term: scaled(["mol": 1, "s": -1], ten: -6, primes: [2: -2, 3: -1, 5: -1])),
        "%": .init(term: scaled(ten: -2), metric: false),
        "[ppth]": .init(term: scaled(ten: -3), metric: false),
        "[ppm]": .init(term: scaled(ten: -6), metric: false),
        "[ppb]": .init(term: scaled(ten: -9), metric: false),
        "[pptr]": .init(term: scaled(ten: -12), metric: false),
        "10*": .init(term: scaled(ten: 1), metric: false), "10^": .init(term: scaled(ten: 1), metric: false)
    ]
    private static let prefixes: [(String, Int)] = [("da", 1), ("Y", 24), ("Z", 21), ("E", 18), ("P", 15), ("T", 12), ("G", 9), ("M", 6), ("k", 3), ("h", 2), ("d", -1), ("c", -2), ("m", -3), ("u", -6), ("n", -9), ("p", -12), ("f", -15), ("a", -18), ("z", -21), ("y", -24)]

    static func parse(_ code: String) throws -> Unit {
        guard !code.isEmpty, code.utf8.count <= 128 else { throw Failure.limit }
        guard code.utf8.allSatisfy({ (33...126).contains($0) }) else { throw Failure.syntax }
        if code.contains("{") || code.contains("}") { throw Failure.annotation }
        var parser = Parser(bytes: Array(code.utf8))
        let value = try parser.term(depth: 0, leadingSlash: true)
        guard parser.index == parser.bytes.count else { throw Failure.syntax }
        return Unit(code: code, dimensions: value.dimensions, primes: value.primes, ratioBasis: value.dimensions.isEmpty ? value.chemicalAxes : [])
    }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var count = 0
        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func term(depth: Int, leadingSlash: Bool = false) throws -> Term {
            guard depth <= 8 else { throw Failure.limit }
            let inverted = peek == 47 && leadingSlash
            if inverted { index += 1 }
            var value = try component(depth: depth).raised(inverted ? -1 : 1)
            while peek == 46 || peek == 47 {
                let power = peek == 46 ? 1 : -1; index += 1
                value = try value.combining(component(depth: depth), power: power)
            }
            return value
        }
        mutating func component(depth: Int) throws -> Term {
            count += 1; guard count <= 64 else { throw Failure.limit }
            guard let first = peek else { throw Failure.syntax }
            if first == 40 {
                index += 1; let value = try term(depth: depth + 1)
                guard peek == 41 else { throw Failure.syntax }; index += 1
                // Current UCUM grammar does not provide powers of groups.
                return value
            }
            let start = index
            if index + 2 < bytes.count, bytes[index] == 49, bytes[index + 1] == 48, [42, 94].contains(bytes[index + 2]) { index += 3 }
            else if (48...57).contains(first) {
                while let b = peek, (48...57).contains(b) { index += 1 }
                // A digit string followed by symbol characters is one unknown
                // atom, not an integer times an implicitly adjacent unit.
                if let b = peek, isSymbol(b) { while let b = peek, isSymbol(b) || (48...57).contains(b) { index += 1 }; throw Failure.unsupported(text(start, index)) }
                guard let factor = Int(text(start, index)), (1...1_000_000_000).contains(factor) else { throw Failure.limit }
                let value = Term(primes: LabUnit.factorize(factor))
                if peek == 43 || peek == 45 { return try value.raised(exponent()) }
                return value
            } else {
                var bracket = false
                while let b = peek {
                    if b == 91 { guard !bracket else { throw Failure.syntax }; bracket = true; index += 1; continue }
                    if b == 93 { guard bracket else { throw Failure.syntax }; bracket = false; index += 1; continue }
                    if bracket { guard ![40, 41, 46, 47].contains(b) else { throw Failure.syntax }; index += 1; continue }
                    if !isSymbol(b) { break }; index += 1
                }
                guard !bracket, index > start else { throw Failure.syntax }
            }
            let symbol = text(start, index), value: Term
            if let atom = atoms[symbol] { value = atom.term }
            else if let (prefix, power) = prefixes.first(where: { symbol.hasPrefix($0.0) && atoms[String(symbol.dropFirst($0.0.count))]?.metric == true }) {
                value = try atoms[String(symbol.dropFirst(prefix.count))]!.term.combining(scaled(ten: power))
            } else { throw Failure.unsupported(symbol) }
            return try value.raised(exponent())
        }
        mutating func exponent() throws -> Int {
            var sign = 1
            let hadSign = peek == 43 || peek == 45
            if hadSign { if peek == 45 { sign = -1 }; index += 1 }
            let start = index
            while let b = peek, (48...57).contains(b) { index += 1 }
            if start == index { guard !hadSign else { throw Failure.syntax }; return 1 }
            guard index - start <= 2, let value = Int(text(start, index)), value <= 24 else { throw Failure.limit }
            return value * sign
        }
        func isSymbol(_ b: UInt8) -> Bool { ![34, 40, 41, 43, 45, 46, 47, 61, 123, 125].contains(b) && !(48...57).contains(b) }
        func text(_ start: Int, _ end: Int) -> String { String(decoding: bytes[start..<end], as: UTF8.self) }
    }
    private static func factorize(_ input: Int) -> [Int: Int] {
        var value = input, prime = 2, factors: [Int: Int] = [:]
        while prime <= value / prime {
            while value % prime == 0 { factors[prime, default: 0] += 1; value /= prime }
            prime = prime == 2 ? 3 : prime + 2
        }
        if value > 1 { factors[value, default: 0] += 1 }
        return factors
    }
    private static func ratio(_ from: Unit, _ to: Unit) throws -> [Int: Int] {
        guard from.compatibleQuantity(with: to) else { throw Failure.dimensions }
        var factors = from.primes
        for (prime, power) in to.primes { factors[prime, default: 0] -= power }
        return factors.filter { $0.value != 0 }
    }
    static func factor(from: Unit, to: Unit) throws -> String {
        let factors = try ratio(from, to)
        if factors.isEmpty { return "×1" }
        func superscript(_ power: Int) -> String {
            let glyphs: [Character: String] = ["-": "⁻", "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
            return String(power).map { glyphs[$0]! }.joined()
        }
        if factors.keys.allSatisfy({ $0 == 2 || $0 == 5 }), factors[2, default: 0] == factors[5, default: 0] {
            let power = factors[2, default: 0]
            if (1...6).contains(power) { return "×1" + String(repeating: "0", count: power) }
            if (-6 ... -1).contains(power) { return "×0." + String(repeating: "0", count: -power - 1) + "1" }
            return "×10" + superscript(power)
        }
        func side(_ positive: Bool) -> String {
            let terms = factors.sorted { $0.key < $1.key }.filter { positive ? $0.value > 0 : $0.value < 0 }
            if terms.isEmpty { return "1" }
            var integer = 1
            for (prime, power) in terms {
                for _ in 0..<abs(power) {
                    let next = integer.multipliedReportingOverflow(by: prime)
                    if next.overflow || next.partialValue > 1_000_000_000 {
                        return terms.map { String($0.key) + (abs($0.value) == 1 ? "" : superscript(abs($0.value))) }.joined(separator: " × ")
                    }
                    integer = next.partialValue
                }
            }
            return String(integer)
        }
        let numerator = side(true), denominator = side(false)
        if denominator == "1" { return "×" + numerator }
        if numerator == "1" { return "÷(" + denominator + ")" }
        return "×(" + numerator + ") / (" + denominator + ")"
    }
    static func convert(_ raw: String, style: LabHistory.DecimalStyle?, from: Unit, to: Unit) throws -> Conversion {
        let number: LabHistory.Number
        switch LabHistory.number(raw, style: style) {
        case .failure(let error): throw Failure.number(error)
        case .success(let value): number = value
        }
        let scale = try ratio(from, to), description = try factor(from: from, to: to)
        var raw = number.canonical, negative = false
        if raw.first == "-" { negative = true; raw.removeFirst() }
        let parts = raw.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var exponent = (parts.count == 2 ? Int(parts[1])! : 0) - (mantissa.count == 2 ? mantissa[1].count : 0)
        var digits = mantissa.joined().utf8.map { Int($0 - 48) }
        trim(&digits)
        if digits == [0] { return Conversion(number: number, from: from, to: to, factor: description) }
        var factors = scale
        let two = factors[2, default: 0], five = factors[5, default: 0]
        let tens = two > 0 && five > 0 ? min(two, five) : (two < 0 && five < 0 ? max(two, five) : 0)
        exponent += tens; factors[2, default: 0] -= tens; factors[5, default: 0] -= tens
        // Multiply the numerator first: integer source coefficients may cancel
        // denominator primes, including3 in minutes and7 in weeks.
        for (prime, power) in factors.sorted(by: { $0.key < $1.key }) where power > 0 {
            for _ in 0..<power { try multiply(&digits, by: prime) }
        }
        for (prime, power) in factors.sorted(by: { $0.key < $1.key }) where power < 0 {
            for _ in 0..<(-power) {
                let (quotient, remainder) = divide(digits, by: prime)
                if remainder == 0 { digits = quotient }
                else if prime == 2 || prime == 5 { try multiply(&digits, by: prime == 2 ? 5 : 2); exponent -= 1 }
                else { throw Failure.nonterminating }
            }
        }
        while digits.count > 1 && digits.last == 0 { digits.removeLast(); exponent += 1 }
        let exact = (negative ? "-" : "") + digits.map(String.init).joined() + "e" + String(exponent)
        guard case .success(let result) = LabHistory.number(exact, style: .dot) else { throw Failure.precision }
        return Conversion(number: result, from: from, to: to, factor: description)
    }
    private static func trim(_ digits: inout [Int]) { while digits.count > 1 && digits.first == 0 { digits.removeFirst() } }
    private static func multiply(_ digits: inout [Int], by factor: Int) throws {
        var carry = 0
        for i in digits.indices.reversed() { let value = digits[i] * factor + carry; digits[i] = value % 10; carry = value / 10 }
        var leading: [Int] = []
        while carry > 0 { leading.append(carry % 10); carry /= 10 }
        digits = leading.reversed() + digits
        guard digits.count <= 2048 else { throw Failure.precision }
    }
    private static func divide(_ digits: [Int], by factor: Int) -> ([Int], Int) {
        var quotient: [Int] = [], remainder = 0
        for digit in digits { let value = remainder * 10 + digit; quotient.append(value / factor); remainder = value % factor }
        trim(&quotient); return (quotient, remainder)
    }
}
