import Foundation

struct LocalAPIApplication: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let running: Bool

    init(id: String, name: String, running: Bool) {
        self.id = id
        self.name = name
        self.running = running
    }
}

/// Internal registry data. The bundle identifier never crosses the HTTP DTO boundary.
struct LocalAPIRegisteredApplication: Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
    let running: Bool
}

struct LocalAPIApplicationsResponse: Codable, Equatable, Sendable {
    let apps: [LocalAPIApplication]
}

struct LocalAPIErrorResponse: Codable, Equatable, Sendable {
    let error: String
}

enum LocalAPIAppOperation: String, Sendable {
    case launch
    case quit
}

struct LocalAPINetworkBinding: Equatable, Sendable {
    let interfaceName: String
    let address: String

    init(interfaceName: String, address: String) {
        self.interfaceName = interfaceName
        self.address = address
    }
}

struct LocalAPIRequestContext: Equatable, Sendable {
    let localInterfaceName: String
    let localAddress: String
    let remoteAddress: String
    let expectedOrigin: String

    init(
        localInterfaceName: String,
        localAddress: String,
        remoteAddress: String,
        expectedOrigin: String = ""
    ) {
        self.localInterfaceName = localInterfaceName
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.expectedOrigin = expectedOrigin
    }
}

enum LocalAPIHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

struct LocalAPIRequest: Equatable, Sendable {
    let method: String
    let target: String
    let headers: [String: String]
    let body: Data

    init(method: String, target: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.target = target
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }

    var path: String? {
        guard target.first == "/",
              !target.contains("#"),
              let separator = target.firstIndex(of: "?") else {
            return target.first == "/" && !target.contains("#") ? target : nil
        }
        return String(target[..<separator])
    }

    var query: String? {
        guard let separator = target.firstIndex(of: "?") else { return nil }
        return String(target[target.index(after: separator)...])
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

enum LocalAPIHTTPParseResult: Equatable, Sendable {
    case incomplete
    case request(LocalAPIRequest, consumedBytes: Int)
    case invalid(LocalAPIHTTPParseError)
}

enum LocalAPIHTTPParseError: Error, Equatable, Sendable {
    case headersTooLarge
    case malformedRequestLine
    case malformedHeader
    case duplicateHeader
    case invalidHeaderValue
    case unsupportedTransferEncoding
    case invalidContentLength
    case bodyTooLarge
    case truncatedBody
}

enum LocalAPIHTTPParser {
    static let maximumHeaderBytes = 32 * 1024
    static let maximumBodyBytes = 4 * 1024

    static func parse(_ data: Data) -> LocalAPIHTTPParseResult {
        let separator = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: separator) else {
            return data.count > maximumHeaderBytes ? .invalid(.headersTooLarge) : .incomplete
        }

        let headerEnd = headerRange.upperBound
        guard headerEnd <= maximumHeaderBytes else { return .invalid(.headersTooLarge) }
        let headerData = data.prefix(upTo: headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return .invalid(.malformedHeader)
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid(.malformedRequestLine) }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard requestParts.count == 3,
              !requestParts.contains(where: { $0.isEmpty }),
              requestParts[2] == "HTTP/1.1" || requestParts[2] == "HTTP/1.0" else {
            return .invalid(.malformedRequestLine)
        }

        let method = String(requestParts[0])
        guard method.utf8.allSatisfy(Self.isMethodByte) else { return .invalid(.malformedRequestLine) }
        let target = String(requestParts[1])
        guard !target.isEmpty,
              target.utf8.allSatisfy({ byte in byte >= 0x21 && byte != 0x7f && byte != 0x23 }) else {
            return .invalid(.malformedRequestLine)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty,
                  let colon = line.firstIndex(of: ":") else {
                return .invalid(.malformedHeader)
            }
            let name = String(line[..<colon]).lowercased()
            let rawValue = String(line[line.index(after: colon)...])
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  name.utf8.allSatisfy(Self.isHeaderNameByte),
                  value.utf8.allSatisfy(Self.isHeaderValueByte) else {
                return .invalid(.invalidHeaderValue)
            }
            guard headers[name] == nil else { return .invalid(.duplicateHeader) }
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil {
            return .invalid(.unsupportedTransferEncoding)
        }

        let bodyLength: Int
        if let contentLength = headers["content-length"] {
            guard !contentLength.isEmpty,
                  contentLength.allSatisfy(\.isNumber),
                  let parsedLength = Int(contentLength),
                  parsedLength >= 0 else {
                return .invalid(.invalidContentLength)
            }
            guard parsedLength <= maximumBodyBytes else { return .invalid(.bodyTooLarge) }
            bodyLength = parsedLength
        } else {
            bodyLength = 0
        }

        let totalLength = headerEnd + bodyLength
        guard data.count >= totalLength else { return .incomplete }
        let body = Data(data[headerEnd..<totalLength])
        let request = LocalAPIRequest(method: method, target: target, headers: headers, body: body)
        return .request(request, consumedBytes: totalLength)
    }

    private static func isMethodByte(_ byte: UInt8) -> Bool {
        isTokenByte(byte)
    }

    private static func isHeaderNameByte(_ byte: UInt8) -> Bool {
        isTokenByte(byte)
    }

    private static func isTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x21, 0x23...0x27, 0x2A, 0x2B, 0x2D...0x39, 0x3F...0x5A, 0x5E...0x7A, 0x7C, 0x7E:
            return true
        default:
            return false
        }
    }

    private static func isHeaderValueByte(_ byte: UInt8) -> Bool {
        byte == 0x09 || (byte >= 0x20 && byte <= 0x7E) || byte >= 0x80
    }
}

struct LocalAPIHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String: String]
    let body: Data

    init(statusCode: Int, reasonPhrase: String? = nil, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase ?? Self.defaultReason(for: statusCode)
        self.headers = headers
        self.body = body
    }

    var serialized: Data {
        var lines = ["HTTP/1.1 \(statusCode) \(reasonPhrase)"]
        lines.append("Content-Length: \(body.count)")
        lines.append("Connection: close")
        for (name, value) in headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            guard name.lowercased() != "content-length", name.lowercased() != "connection" else { continue }
            lines.append("\(name): \(value)")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }

    static func json<T: Encodable>(statusCode: Int, _ value: T, headers: [String: String] = [:]) -> LocalAPIHTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data(#"{"error":"Internal server error"}"#.utf8)
        var responseHeaders = headers
        responseHeaders["Content-Type"] = "application/json; charset=utf-8"
        return LocalAPIHTTPResponse(statusCode: statusCode, headers: responseHeaders, body: data)
    }

    private static func defaultReason(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Content Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}
