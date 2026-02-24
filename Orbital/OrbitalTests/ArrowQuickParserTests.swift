//
//  ArrowQuickParserTests.swift
//  OrbitalTests
//
//  Tests for the ArrowQuickParser tokenizer, parser, Codable round-trip,
//  and end-to-end compilation of quick expressions.
//

import Testing
import Foundation
@testable import Orbital

@Suite("ArrowQuickParser")
struct ArrowQuickParserTests {

    // MARK: - Tokenizer

    @Test("Tokenizes simple expression")
    func tokenizeSimple() throws {
        let tokens = try QuickTokenizer.tokenize("1 + 2")
        #expect(tokens == [.number(1), .plus, .number(2), .eof])
    }

    @Test("Tokenizes numbers with decimals")
    func tokenizeDecimals() throws {
        let tokens = try QuickTokenizer.tokenize("3.14")
        #expect(tokens == [.number(3.14), .eof])
    }

    @Test("Tokenizes identifiers")
    func tokenizeIdentifiers() throws {
        let tokens = try QuickTokenizer.tokenize("octave + amp_env")
        #expect(tokens == [.identifier("octave"), .plus, .identifier("amp_env"), .eof])
    }

    @Test("Tokenizes all operators and parens")
    func tokenizeOperators() throws {
        let tokens = try QuickTokenizer.tokenize("( + - * / )")
        #expect(tokens == [.leftParen, .plus, .minus, .star, .slash, .rightParen, .eof])
    }

    @Test("Rejects unexpected characters")
    func tokenizeRejectsUnexpected() {
        #expect(throws: QuickParseError.self) {
            _ = try QuickTokenizer.tokenize("1 @ 2")
        }
    }

    // MARK: - Parser: Atoms

    @Test("Parses numeric literal to const")
    func parseNumber() throws {
        let result = try QuickParser.parse("42")
        #expect(result == .const(name: "_42", val: 42))
    }

    @Test("Parses decimal literal")
    func parseDecimal() throws {
        let result = try QuickParser.parse("3.14")
        #expect(result == .const(name: "_3.14", val: 3.14))
    }

    @Test("Parses identifier to emitterValue")
    func parseIdentifier() throws {
        let result = try QuickParser.parse("octaves")
        #expect(result == .emitterValue(name: "octaves"))
    }

    @Test("Parses eventNote keyword")
    func parseEventNote() throws {
        let result = try QuickParser.parse("eventNote")
        #expect(result == .eventNote)
    }

    @Test("Parses eventVelocity keyword")
    func parseEventVelocity() throws {
        let result = try QuickParser.parse("eventVelocity")
        #expect(result == .eventVelocity)
    }

    // MARK: - Parser: Operators

    @Test("Parses addition")
    func parseAddition() throws {
        let result = try QuickParser.parse("a + b")
        #expect(result == .sum(of: [
            .emitterValue(name: "a"),
            .emitterValue(name: "b")
        ]))
    }

    @Test("Parses subtraction as sum with negation")
    func parseSubtraction() throws {
        let result = try QuickParser.parse("a - b")
        #expect(result == .sum(of: [
            .emitterValue(name: "a"),
            .prod(of: [.const(name: "_neg", val: -1), .emitterValue(name: "b")])
        ]))
    }

    @Test("Parses multiplication")
    func parseMultiplication() throws {
        let result = try QuickParser.parse("a * b")
        #expect(result == .prod(of: [
            .emitterValue(name: "a"),
            .emitterValue(name: "b")
        ]))
    }

    @Test("Parses division as prod with reciprocal")
    func parseDivision() throws {
        let result = try QuickParser.parse("a / b")
        #expect(result == .prod(of: [
            .emitterValue(name: "a"),
            .reciprocal(of: .emitterValue(name: "b"))
        ]))
    }

    @Test("Parses unary negation")
    func parseUnaryNeg() throws {
        let result = try QuickParser.parse("-a")
        #expect(result == .prod(of: [
            .const(name: "_neg", val: -1),
            .emitterValue(name: "a")
        ]))
    }

    // MARK: - Precedence

    @Test("Multiplication binds tighter than addition")
    func precedenceMulOverAdd() throws {
        // 1 + 2 * 3 => sum([1, prod([2, 3])])
        let result = try QuickParser.parse("1 + 2 * 3")
        #expect(result == .sum(of: [
            .const(name: "_1", val: 1),
            .prod(of: [.const(name: "_2", val: 2), .const(name: "_3", val: 3)])
        ]))
    }

    @Test("Parentheses override precedence")
    func precedenceParens() throws {
        // (1 + 2) * 3 => prod([sum([1, 2]), 3])
        let result = try QuickParser.parse("(1 + 2) * 3")
        #expect(result == .prod(of: [
            .sum(of: [.const(name: "_1", val: 1), .const(name: "_2", val: 2)]),
            .const(name: "_3", val: 3)
        ]))
    }

    // MARK: - Flattening

    @Test("Consecutive additions flatten into single sum")
    func flattenAddition() throws {
        let result = try QuickParser.parse("a + b + c")
        #expect(result == .sum(of: [
            .emitterValue(name: "a"),
            .emitterValue(name: "b"),
            .emitterValue(name: "c")
        ]))
    }

    @Test("Consecutive multiplications flatten into single prod")
    func flattenMultiplication() throws {
        let result = try QuickParser.parse("a * b * c")
        #expect(result == .prod(of: [
            .emitterValue(name: "a"),
            .emitterValue(name: "b"),
            .emitterValue(name: "c")
        ]))
    }

    @Test("Mixed add/subtract flattens correctly")
    func flattenMixedAddSub() throws {
        // a + b - c => sum([a, b, prod([-1, c])])
        let result = try QuickParser.parse("a + b - c")
        #expect(result == .sum(of: [
            .emitterValue(name: "a"),
            .emitterValue(name: "b"),
            .prod(of: [.const(name: "_neg", val: -1), .emitterValue(name: "c")])
        ]))
    }

    // MARK: - Complex Expressions

    @Test("Parses 1 / (octaves + 1)")
    func parseOctaveAmpMod() throws {
        let result = try QuickParser.parse("1 / (octaves + 1)")
        // 1 / (octaves + 1) => prod([const(1), reciprocal(sum([emitterValue(octaves), const(1)]))])
        #expect(result == .prod(of: [
            .const(name: "_1", val: 1),
            .reciprocal(of: .sum(of: [
                .emitterValue(name: "octaves"),
                .const(name: "_1", val: 1)
            ]))
        ]))
    }

    @Test("Parses nested parentheses")
    func parseNestedParens() throws {
        let result = try QuickParser.parse("((a))")
        #expect(result == .emitterValue(name: "a"))
    }

    // MARK: - Error Cases

    @Test("Empty expression throws error")
    func parseEmpty() {
        #expect(throws: QuickParseError.self) {
            _ = try QuickParser.parse("")
        }
    }

    @Test("Whitespace-only expression throws error")
    func parseWhitespaceOnly() {
        #expect(throws: QuickParseError.self) {
            _ = try QuickParser.parse("   ")
        }
    }

    @Test("Unmatched left parenthesis throws error")
    func parseUnmatchedLeftParen() {
        #expect(throws: QuickParseError.self) {
            _ = try QuickParser.parse("(a + b")
        }
    }

    @Test("Unmatched right parenthesis throws error")
    func parseUnmatchedRightParen() {
        #expect(throws: QuickParseError.self) {
            _ = try QuickParser.parse("a + b)")
        }
    }

    @Test("Trailing operator throws error")
    func parseTrailingOperator() {
        #expect(throws: QuickParseError.self) {
            _ = try QuickParser.parse("a +")
        }
    }

    // MARK: - Codable Round-trip

    @Test("quickExpression round-trips through JSON")
    func codableRoundTrip() throws {
        let syntax = ArrowSyntax.quickExpression("1 / (octaves + 1)")
        let data = try JSONEncoder().encode(syntax)
        let decoded = try JSONDecoder().decode(ArrowSyntax.self, from: data)
        #expect(decoded == .quickExpression("1 / (octaves + 1)"))
    }

    @Test("quickExpression JSON format is correct")
    func codableJsonFormat() throws {
        let syntax = ArrowSyntax.quickExpression("x + 1")
        let data = try JSONEncoder().encode(syntax)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["quickExpression"] as? String == "x + 1")
    }

    // MARK: - Compilation

    @Test("quickExpression compiles and evaluates correctly")
    func compilesAndEvaluates() throws {
        let syntax = ArrowSyntax.quickExpression("1 / (octaves + 1)")
        let compiled = syntax.compile()

        // Wire the emitter value: octaves = 3 => 1 / (3 + 1) = 0.25
        if let placeholders = compiled.namedEmitterValues["octaves"] {
            let shadow = ArrowConst(value: 3.0)
            for placeholder in placeholders {
                placeholder.forwardTo = shadow
            }
        }

        // Render one sample using the shared test helper
        let output = renderArrow(compiled.wrappedArrow, sampleCount: 1)
        // 1 / (3 + 1) = 0.25
        #expect(abs(output[0] - 0.25) < 0.001)
    }

    @Test("Simple constant expression compiles")
    func compilesConstant() throws {
        let syntax = ArrowSyntax.quickExpression("42")
        let compiled = syntax.compile()
        let output = renderArrow(compiled.wrappedArrow, sampleCount: 1)
        #expect(abs(output[0] - 42.0) < 0.001)
    }
}
