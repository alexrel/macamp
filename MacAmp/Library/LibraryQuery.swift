import Foundation

/// Winamp Media Library view queries (docs/UI-screens/library-add view.png):
/// `field <comparison> value [&|| ...]`, parentheses, `!` / `NOT`.
/// Fields: TYPE, FILENAME, LENGTH, ARTIST, ALBUM, TITLE, TRACKNO, GENRE, YEAR, COMMENT.
/// Comparisons: HAS, LIKE, BEGINS, ENDS, =, !=, <, >, <=, >= (text compares ignore case).
/// Examples: `type = 0`, `type = 0 & artist = "air" & length > 360`, `filename BEGINS /Volumes`.
public indirect enum LibraryQuery: Equatable {
    case match(field: String, op: String, value: String)
    case and(LibraryQuery, LibraryQuery)
    case or(LibraryQuery, LibraryQuery)
    case not(LibraryQuery)
    case all

    public static func parse(_ text: String) throws -> LibraryQuery {
        var parser = Parser(tokens: try tokenize(text))
        if parser.tokens.isEmpty { return .all }
        let query = try parser.orExpression()
        guard parser.position == parser.tokens.count else { throw QueryError.unexpected(parser.tokens[parser.position]) }
        return query
    }

    public enum QueryError: Error, Equatable {
        case unexpected(String), missingValue(String), unknownField(String), unterminatedQuote
    }

    static let fields: Set<String> = ["TYPE", "FILENAME", "LENGTH", "ARTIST", "ALBUM", "TITLE", "TRACKNO", "GENRE", "YEAR", "COMMENT"]
    static let comparisons: [String] = ["<=", ">=", "!=", "=", "<", ">"]
    static let wordComparisons: Set<String> = ["HAS", "LIKE", "BEGINS", "ENDS"]

    // MARK: Evaluation

    public func matches(_ item: MediaLibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .not(let q): return !q.matches(item)
        case .and(let a, let b): return a.matches(item) && b.matches(item)
        case .or(let a, let b): return a.matches(item) || b.matches(item)
        case .match(let field, let op, let value):
            let numeric: Double?
            let text: String
            switch field {
            case "TYPE": numeric = item.isVideo ? 1 : 0; text = item.isVideo ? "1" : "0"
            case "LENGTH": numeric = item.length > 0 ? item.length : -1; text = String(Int(item.length))
            case "TRACKNO": numeric = Double(item.trackNumber); text = String(item.trackNumber)
            case "YEAR": numeric = Double(item.year); text = item.year
            case "FILENAME": numeric = nil; text = item.url.isFileURL ? item.url.path : item.url.absoluteString
            case "ARTIST": numeric = nil; text = item.artist
            case "ALBUM": numeric = nil; text = item.album
            case "TITLE": numeric = nil; text = item.title
            case "GENRE": numeric = nil; text = item.genre
            default: numeric = nil; text = item.comment
            }
            let a = text.lowercased(), b = value.lowercased()
            switch op {
            case "HAS": return a.contains(b)
            case "LIKE": return LibraryQuery.like(a, b)
            case "BEGINS": return a.hasPrefix(b)
            case "ENDS": return a.hasSuffix(b)
            case "=": return numeric.map { $0 == Double(value) } ?? (a == b)
            case "!=": return !(numeric.map { $0 == Double(value) } ?? (a == b))
            default:
                if let n = numeric, let v = Double(value) {
                    switch op {
                    case "<": return n < v
                    case ">": return n > v
                    case "<=": return n <= v
                    default: return n >= v
                    }
                }
                switch op {
                case "<": return a < b
                case ">": return a > b
                case "<=": return a <= b
                default: return a >= b
                }
            }
        }
    }

    /// LIKE: `*` any run, `?` one character (whole value).
    static func like(_ text: String, _ pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
        return text.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }

    // MARK: Parsing

    static func tokenize(_ text: String) throws -> [String] {
        var tokens: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c.isWhitespace { i = text.index(after: i); continue }
            if c == "\"" || c == "'" {
                var j = text.index(after: i)
                while j < text.endIndex, text[j] != c { j = text.index(after: j) }
                guard j < text.endIndex else { throw QueryError.unterminatedQuote }
                tokens.append("\"" + text[text.index(after: i)..<j])
                i = text.index(after: j)
                continue
            }
            if let op = comparisons.first(where: { text[i...].hasPrefix($0) }) {
                tokens.append(op)
                i = text.index(i, offsetBy: op.count)
                continue
            }
            if "()&|!".contains(c) {
                tokens.append(String(c))
                i = text.index(after: i)
                continue
            }
            var j = i
            while j < text.endIndex, !text[j].isWhitespace, !"()&|!<>=\"'".contains(text[j]) { j = text.index(after: j) }
            tokens.append(String(text[i..<j]))
            i = j
        }
        return tokens
    }

    struct Parser {
        let tokens: [String]
        var position = 0

        var peek: String? { position < tokens.count ? tokens[position] : nil }
        mutating func next() -> String? { defer { position += 1 }; return peek }

        mutating func orExpression() throws -> LibraryQuery {
            var left = try andExpression()
            while let t = peek, t == "|" || t.uppercased() == "OR" {
                position += 1
                left = .or(left, try andExpression())
            }
            return left
        }

        mutating func andExpression() throws -> LibraryQuery {
            var left = try unary()
            while let t = peek, t == "&" || t.uppercased() == "AND" {
                position += 1
                left = .and(left, try unary())
            }
            return left
        }

        mutating func unary() throws -> LibraryQuery {
            if let t = peek, t == "!" || t.uppercased() == "NOT" {
                position += 1
                return .not(try unary())
            }
            if peek == "(" {
                position += 1
                let inner = try orExpression()
                guard next() == ")" else { throw QueryError.unexpected(peek ?? "end") }
                return inner
            }
            guard let field = next()?.uppercased() else { throw QueryError.unexpected("end") }
            guard LibraryQuery.fields.contains(field) else { throw QueryError.unknownField(field) }
            guard let op = next().map({ LibraryQuery.wordComparisons.contains($0.uppercased()) ? $0.uppercased() : $0 }),
                  LibraryQuery.comparisons.contains(op) || LibraryQuery.wordComparisons.contains(op) else {
                throw QueryError.unexpected(tokens.indices.contains(position - 1) ? tokens[position - 1] : "end")
            }
            guard let raw = next(), !["&", "|", ")", "("].contains(raw) else { throw QueryError.missingValue(field) }
            return .match(field: field, op: op, value: raw.hasPrefix("\"") ? String(raw.dropFirst()) : raw)
        }
    }
}
