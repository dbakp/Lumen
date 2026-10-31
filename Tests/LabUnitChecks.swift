import Foundation

enum LabUnitChecks {
    static func run() throws {
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); print("PASS: " + label) }
        func converted(_ value: String, _ from: String, _ to: String, _ style: LabHistory.DecimalStyle? = .dot) -> String? {
            guard let a = try? LabUnit.parse(from), let b = try? LabUnit.parse(to),
                  let result = try? LabUnit.convert(value, style: style, from: a, to: b) else { return nil }
            return result.number.canonical
        }
        func fails(_ value: String, _ from: String, _ to: String, as expected: LabUnit.Failure) -> Bool {
            do { _ = try LabUnit.convert(value, style: .dot, from: LabUnit.parse(from), to: LabUnit.parse(to)); return false }
            catch let error as LabUnit.Failure { return error == expected }
            catch { return false }
        }
        for (value, from, to, expected) in [
            ("12.00", "g/dL", "g/L", "120"), ("120", "g/L", "g/dL", "12"),
            ("100", "mg/dL", "g/L", "1"), ("2.5", "ug/L", "ng/mL", "2.5"),
            ("3.75", "mmol/L", "umol/L", "3750"), ("5", "10*9/L", "10*3/uL", "5"),
            ("7.1", "10^12/L", "/pL", "7.1"), ("1", "mL", "cm3", "1"),
            ("2.5", "m2", "cm2", "25000"), ("2", "km", "m", "2000"),
            ("1", "mg", "Mg", "0.000000001"), ("1", "dag", "g", "10"),
            ("2", "min", "s", "120"), ("2", "h", "min", "120"),
            ("1", "d", "h", "24"), ("2", "wk", "d", "14"),
            ("25", "%", "1", "0.25"), ("1", "[ppm]", "%", "0.0001"),
            ("1", "[pptr]", "[ppb]", "0.001"), ("5", "[ppth]", "1", "0.005"),
            ("1", "kat", "U", "60000000"), ("60", "U/L", "ukat/L", "1"),
            ("60", "1/min", "1/s", "1"), ("7", "1/wk", "1/d", "1"),
            ("1", "m/s/s", "m/s2", "1"), ("1", "m/s.s", "m", "1"),
            ("1", "m/(s.s)", "m/s2", "1"), ("1", "/m.s", "s/m", "1"),
            ("1", "3.g", "g", "3"), ("1", "2.5", "1", "10"),
            ("1", "2+10", "1", "1024"), ("1", "2-1", "1", "0.5"),
            ("1", "1000000000", "10*9", "1"), ("1", "0001", "1", "1"),
            ("-12.25", "g/dL", "g/L", "-122.5"), ("+0.50", "g/L", "mg/L", "500"),
            ("-0.000", "g/dL", "g/L", "0"), ("1.2300e-9", "g/L", "ng/L", "1.23"),
            ("0", "U", "kat", "0"), ("1", "10*-24", "1", "0.000000000000000000000001")
        ] {
            check(converted(value, from, to) == expected, "exact linear unit conversion: \(value) \(from) → \(expected) \(to)")
        }
        // Independent SI definitions, including charge-based electrical axes.
        for (atom, definition) in [
            ("sr", "rad2"), ("Hz", "/s"), ("N", "kg.m/s2"), ("Pa", "N/m2"),
            ("J", "N.m"), ("W", "J/s"), ("A", "C/s"), ("V", "J/C"),
            ("F", "C/V"), ("Ohm", "V/A"), ("S", "/Ohm"), ("Wb", "V.s"),
            ("T", "Wb/m2"), ("H", "Wb/A"), ("lm", "cd.sr"), ("lx", "lm/m2"),
            ("Bq", "/s"), ("Gy", "J/kg"), ("Sv", "J/kg"), ("L", "dm3"),
            ("l", "L"), ("ar", "100.m2"), ("t", "1000.kg"), ("kat", "mol/s"), ("U", "umol/min")
        ] {
            check(converted("1", atom, definition) == "1", "supported unit agrees with its independent UCUM definition: " + atom)
        }
        for (prefix, expected) in [("Y", 24), ("Z", 21), ("E", 18), ("P", 15), ("T", 12), ("G", 9), ("M", 6), ("k", 3), ("h", 2), ("da", 1), ("d", -1), ("c", -2), ("m", -3), ("u", -6), ("n", -9), ("p", -12), ("f", -15), ("a", -18), ("z", -21), ("y", -24)] {
            let result = try LabUnit.convert("1", style: .dot, from: LabUnit.parse(prefix + "g"), to: LabUnit.parse("g"))
            check(result.number.decimal == Decimal(string: "1e\(expected)", locale: Locale(identifier: "en_US_POSIX")), "case-sensitive metric prefix has its normative magnitude: " + prefix)
        }
        for code in ["", "g L", "g\n", "µg/L", "μg/L", "mg·L-1", "mg⁄L", "g×L", "(g/L)2", "g//L", "g..L", ".g", "g/", "()", "g(+L)", "g+", "g-", "mg=1", "g\"", "[ppm", "ppm]", "g[[]]", "g/{x}", "{RBC}", "g{creat}", "123m", "g1.0", "1e3", "g/Lxyz", "g/L)ignored", "(g/L"] {
            check((try? LabUnit.parse(code)) == nil, "whole malformed/display/annotated unit is refused without prefix acceptance: " + code)
        }
        for code in ["Cel", "mCel", "Cel0", "Cel/Cel", "[degF]", "[IU]", "[iU]", "m[IU]", "[arb'U]", "[USP'U]", "[IU]/[IU]", "mmin", "k%", "k10*3", "MOL", "KG", "mln", "mmHg", "mm[Hg]"] {
            check((try? LabUnit.parse(code)) == nil, "unsupported special/arbitrary/unknown/nonmetric-prefixed unit cannot be cancelled or guessed: " + code)
        }
        for code in [String(repeating: "g", count: 129), String(repeating: "(", count: 9) + "g" + String(repeating: ")", count: 9), Array(repeating: "1", count: 65).joined(separator: "."), "g25", "g-25", "g99999999999999999999999999", "g24.g24.g24", "1000000001", "0", "kg24.kg24.kg24.kg24.kg24"] {
            check((try? LabUnit.parse(code)) == nil, "bounded unit parsing rejects the whole over-limit term: " + String(code.prefix(60)))
        }
        check((try? LabUnit.parse(String(repeating: "(", count: 8) + "g" + String(repeating: ")", count: 8))) != nil && (try? LabUnit.parse(Array(repeating: "1", count: 64).joined(separator: "."))) != nil, "unit parser accepts its actual depth and component boundaries")
        for (from, to) in [("g/L", "mol/L"), ("mol/L", "1/L"), ("g/L", "g"), ("g/L", "g/kg"), ("m/s", "m.s"), ("U/L", "g/L"), ("rad", "1"), ("g/g", "mol/mol"), ("mg/g", "mmol/mol")] {
            check(fails("1", from, to, as: .dimensions), "dimensional and amount/count conflicts do not create a conversion: \(from) → \(to)")
        }
        check(converted("0.25", "g/g", "%") == "25" && converted("0.25", "mol/mol", "%") == "25" && converted("1", "g0", "1") == "1", "fractions can use a generic target without discarding the distinct source mass/amount basis; a zero unit power is unity")
        check(fails("1", "U", "kat", as: .nonterminating) && fails("1", "1/min", "1/s", as: .nonterminating) && fails("1", "1/wk", "1/d", as: .nonterminating), "nonterminating rational conversions are withheld rather than rounded")
        check(converted("0.3", "1/min", "1/s") == "0.005" && converted("0.07", "1/wk", "1/d") == "0.01", "fractional source coefficients cancel denominator primes exactly")
        check(converted("1e-100", "g", "ug") == "0." + String(repeating: "0", count: 93) + "1", "exact very small unit conversion never becomes zero")
        check(fails(String(repeating: "9", count: 38), "7.g", "g", as: .precision), "multiplication that exceeds exact decimal precision is withheld")
        check(converted("1e-128", "g", "kg") == nil && converted("1e164", "kg", "g") == nil, "unit conversion rejects decimal underflow and overflow")
        for value in ["<5", ">=3", "Not detected", "NaN", "5 mg/L", "false", "1–2"] {
            check(converted(value, "g", "mg") == nil, "unit conversion cannot erase a qualifier or nonnumeric value: " + value)
        }
        check(converted("1,25", "g", "mg", .comma) == "1250" && converted("1,25", "g", "mg", .dot) == nil && converted("1.25", "g", "mg", .literal) == nil && converted("1.25", "g", "mg", nil) == nil, "conversion obeys explicit decimal punctuation and wording-only choice")
        let a = try LabUnit.parse("g/dL"), b = try LabUnit.parse("g/L")
        check(try LabUnit.factor(from: a, to: b) == "×10", "conversion factor is retained separately with readable exact notation")
        check(try LabUnit.factor(from: b, to: a) == "×0.1" && LabUnit.factor(from: LabUnit.parse("min"), to: LabUnit.parse("s")) == "×60", "small decimal and integer factors remain exact readable maths")
        check(try LabUnit.factor(from: LabUnit.parse("s"), to: LabUnit.parse("min")) == "÷(60)" && LabUnit.factor(from: LabUnit.parse("Yg"), to: LabUnit.parse("g")) == "×10²⁴", "rational and large factors retain exact division or superscript notation")
        check(try LabUnit.parse("ug/L").sameMagnitude(as: LabUnit.parse("ng/mL")) && !LabUnit.parse("g/L").sameMagnitude(as: a), "unit assignments can reject a known printed unit remapped to a different magnitude")
    }
}
