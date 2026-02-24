//
//  ArrowQuickParser.swift
//  Orbital
//
//  Tokenizer and recursive-descent parser for quick arithmetic expressions
//  like "1 / (octaves + 1)" that produce ArrowSyntax trees.
//

import Foundation

// MARK: - Errors

enum QuickParseError: Error, CustomStringConvertible {
    case unexpectedCharacter(Character, position: Int)
    case unexpectedToken(String, expected: String)
    case unexpectedEndOfExpression
    case emptyExpression

    var description: String {
        switch self {
        case .unexpectedCharacter(let ch, let pos):
            return "Unexpected character '\(ch)' at position \(pos)"
        case .unexpectedToken(let tok, let expected):
            return "Unexpected token '\(tok)', expected \(expected)"
        case .unexpectedEndOfExpression:
            return "Unexpected end of expression"
        case .emptyExpression:
            return "Expression is empty"
        }
    }
}

// MARK: - Tokens

enum QuickToken: Equatable, CustomStringConvertible {
    case number(CoreFloat)
    case identifier(String)
    case plus
    case minus
    case star
    case slash
    case leftParen
    case rightParen
    case eof

    var description: String {
        switch self {
        case .number(let v): return "\(v)"
        case .identifier(let s): return s
        case .plus: return "+"
        case .minus: return "-"
        case .star: return "*"
        case .slash: return "/"
        case .leftParen: return "("
        case .rightParen: return ")"
        case .eof: return "EOF"
        }
    }
}

// MARK: - Tokenizer

struct QuickTokenizer {
    static func tokenize(_ input: String) throws -> [QuickToken] {
        var tokens: [QuickToken] = []
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            // Skip whitespace
            if ch.isWhitespace {
                i += 1
                continue
            }

            // Number: digits and optional decimal point
            if ch.isNumber || (ch == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var numStr = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    numStr.append(chars[i])
                    i += 1
                }
                guard let val = CoreFloat(numStr) else {
                    throw QuickParseError.unexpectedCharacter(ch, position: i - numStr.count)
                }
                tokens.append(.number(val))
                continue
            }

            // Identifier: letter or underscore, then alphanumeric or underscore
            if ch.isLetter || ch == "_" {
                var ident = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    ident.append(chars[i])
                    i += 1
                }
                tokens.append(.identifier(ident))
                continue
            }

            // Single-character operators
            switch ch {
            case "+": tokens.append(.plus); i += 1
            case "-": tokens.append(.minus); i += 1
            case "*": tokens.append(.star); i += 1
            case "/": tokens.append(.slash); i += 1
            case "(": tokens.append(.leftParen); i += 1
            case ")": tokens.append(.rightParen); i += 1
            default:
                throw QuickParseError.unexpectedCharacter(ch, position: i)
            }
        }

        tokens.append(.eof)
        return tokens
    }
}

// MARK: - Parser

/// Recursive-descent parser producing ArrowSyntax from quick expressions.
///
/// Grammar:
/// ```
/// expression     = additive
/// additive       = multiplicative (('+' | '-') multiplicative)*
/// multiplicative = unary (('*' | '/') unary)*
/// unary          = '-' unary | primary
/// primary        = NUMBER | IDENTIFIER | '(' expression ')'
/// ```
struct QuickParser {
    private var tokens: [QuickToken]
    private var pos: Int = 0

    /// Parse an expression string into an ArrowSyntax tree.
    static func parse(_ input: String) throws -> ArrowSyntax {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw QuickParseError.emptyExpression
        }
        let tokens = try QuickTokenizer.tokenize(trimmed)
        var parser = QuickParser(tokens: tokens)
        let result = try parser.parseExpression()
        // Ensure we consumed everything
        if parser.current != .eof {
            throw QuickParseError.unexpectedToken(
                parser.current.description,
                expected: "end of expression"
            )
        }
        return result
    }

    // MARK: - Token access

    private var current: QuickToken {
        pos < tokens.count ? tokens[pos] : .eof
    }

    private mutating func advance() {
        pos += 1
    }

    private mutating func expect(_ expected: QuickToken) throws {
        guard current == expected else {
            throw QuickParseError.unexpectedToken(
                current.description,
                expected: expected.description
            )
        }
        advance()
    }

    // MARK: - Grammar rules

    private mutating func parseExpression() throws -> ArrowSyntax {
        try parseAdditive()
    }

    /// additive = multiplicative (('+' | '-') multiplicative)*
    /// Flattens consecutive additions into a single .sum.
    private mutating func parseAdditive() throws -> ArrowSyntax {
        var terms: [ArrowSyntax] = [try parseMultiplicative()]

        while true {
            switch current {
            case .plus:
                advance()
                terms.append(try parseMultiplicative())
            case .minus:
                advance()
                let right = try parseMultiplicative()
                // a - b  =>  a + (-1 * b)
                let negated = ArrowSyntax.prod(of: [
                    .const(name: "_neg", val: -1),
                    right
                ])
                terms.append(negated)
            default:
                if terms.count == 1 { return terms[0] }
                return .sum(of: terms)
            }
        }
    }

    /// multiplicative = unary (('*' | '/') unary)*
    /// Flattens consecutive multiplications into a single .prod.
    private mutating func parseMultiplicative() throws -> ArrowSyntax {
        var factors: [ArrowSyntax] = [try parseUnary()]

        while true {
            switch current {
            case .star:
                advance()
                factors.append(try parseUnary())
            case .slash:
                advance()
                let right = try parseUnary()
                // a / b  =>  a * (1/b)
                factors.append(.reciprocal(of: right))
            default:
                if factors.count == 1 { return factors[0] }
                return .prod(of: factors)
            }
        }
    }

    /// unary = '-' unary | primary
    private mutating func parseUnary() throws -> ArrowSyntax {
        if current == .minus {
            advance()
            let operand = try parseUnary()
            return .prod(of: [.const(name: "_neg", val: -1), operand])
        }
        return try parsePrimary()
    }

    /// primary = NUMBER | IDENTIFIER | '(' expression ')'
    private mutating func parsePrimary() throws -> ArrowSyntax {
        switch current {
        case .number(let val):
            advance()
            // Use a descriptive synthetic name for the literal
            let name = "_\(formatNumber(val))"
            return .const(name: name, val: val)

        case .identifier(let ident):
            advance()
            // Special keywords
            if ident == "eventNote" { return .eventNote }
            if ident == "eventVelocity" { return .eventVelocity }
            // All other identifiers are emitter value references
            return .emitterValue(name: ident)

        case .leftParen:
            advance()
            let inner = try parseExpression()
            try expect(.rightParen)
            return inner

        case .eof:
            throw QuickParseError.unexpectedEndOfExpression

        default:
            throw QuickParseError.unexpectedToken(
                current.description,
                expected: "number, identifier, or '('"
            )
        }
    }

    // MARK: - Helpers

    /// Format a number for use as a const name: "1" not "1.0", "3.14" not "3.14000..."
    private func formatNumber(_ val: CoreFloat) -> String {
        if val == val.rounded(.towardZero) && !val.isInfinite {
            return String(Int(val))
        }
        return String(val)
    }
}
