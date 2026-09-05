import AppKit
import Darwin
import Foundation
import Network
import Security

struct LocalAPINetworkPolicy: Equatable, Sendable {
    static let tailscaleInterfacePrefix = "utun"

    let interfacePrefix: String
    let boundAddress: String?
    let boundInterfaceName: String?

    init(
        interfacePrefix: String = Self.tailscaleInterfacePrefix,
        boundAddress: String? = nil,
        boundInterfaceName: String? = nil
    ) {
        self.interfacePrefix = interfacePrefix
        self.boundAddress = boundAddress
        self.boundInterfaceName = boundInterfaceName
    }

    static let tailscaleOnly = LocalAPINetworkPolicy()

    func allows(
        localInterfaceName: String,
        localAddress: String,
        remoteAddress: String
    ) -> Bool {
        guard localInterfaceName.hasPrefix(interfacePrefix),
              Self.isTailscaleAddress(localAddress),
              Self.isTailscaleAddress(remoteAddress) else { return false }
        if let boundAddress, localAddress != boundAddress { return false }
        if let boundInterfaceName, localInterfaceName != boundInterfaceName { return false }
        return true
    }

    func selectBinding(from addresses: [LocalAPINetworkBinding]) -> LocalAPINetworkBinding? {
        let candidates = addresses.filter {
            $0.interfaceName.hasPrefix(interfacePrefix) && Self.isTailscaleAddress($0.address)
        }
        let scopedCandidates: [LocalAPINetworkBinding]
        if boundAddress != nil || boundInterfaceName != nil {
            scopedCandidates = candidates.filter { candidate in
                (boundAddress == nil || candidate.address == boundAddress)
                    && (boundInterfaceName == nil || candidate.interfaceName == boundInterfaceName)
            }
        } else {
            scopedCandidates = candidates
        }

        // Prefer a single IPv4 binding, which is the normal macOS Tailscale address.
        // If IPv4 is unavailable, a single Tailscale IPv6 binding is safe as well.
        let ipv4 = scopedCandidates.filter { Self.isTailscaleIPv4($0.address) }
        if ipv4.count == 1 { return ipv4[0] }
        guard ipv4.isEmpty else { return nil }
        let ipv6 = scopedCandidates.filter { Self.isTailscaleIPv6($0.address) }
        return ipv6.count == 1 ? ipv6[0] : nil
    }

    func resolveBinding() -> LocalAPINetworkBinding? {
        selectBinding(from: Self.discoverBindings())
    }

    func isCurrent(binding: LocalAPINetworkBinding) -> Bool {
        resolveBinding() == binding
    }

    static func discoverBindings() -> [LocalAPINetworkBinding] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
        defer { freeifaddrs(firstAddress) }

        var result: [LocalAPINetworkBinding] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let entry = current.pointee
            defer { cursor = entry.ifa_next }
            guard let namePointer = entry.ifa_name,
                  let addressPointer = entry.ifa_addr,
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            let interfaceName = String(cString: namePointer)
            guard let address = Self.addressString(from: addressPointer), Self.isTailscaleAddress(address) else { continue }
            let binding = LocalAPINetworkBinding(interfaceName: interfaceName, address: address)
            if !result.contains(binding) { result.append(binding) }
        }
        return result
    }

    static func isTailscaleAddress(_ address: String) -> Bool {
        isTailscaleIPv4(address) || isTailscaleIPv6(address)
    }

    static func isTailscaleIPv4(_ address: String) -> Bool {
        let components = address.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        let values = components.map(String.init)
        guard values.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        let numbers = values.compactMap(Int.init)
        guard numbers.count == 4,
              numbers.allSatisfy({ (0...255).contains($0) }) else { return false }
        let value = (numbers[0] << 24) | (numbers[1] << 16) | (numbers[2] << 8) | numbers[3]
        return (0x6440_0000...0x647F_FFFF).contains(value)
    }

    static func isTailscaleIPv6(_ address: String) -> Bool {
        let normalized = address
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: "%", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        guard !normalized.isEmpty else { return false }
        var rawAddress = in6_addr()
        guard normalized.withCString({ inet_pton(AF_INET6, $0, &rawAddress) }) == 1 else { return false }
        return withUnsafeBytes(of: &rawAddress) { bytes in
            bytes.count >= 6
                && bytes[0] == 0xFD
                && bytes[1] == 0x7A
                && bytes[2] == 0x11
                && bytes[3] == 0x5C
                && bytes[4] == 0xA1
                && bytes[5] == 0xE0
        }
    }

    private static func addressString(from pointer: UnsafeMutablePointer<sockaddr>) -> String? {
        let family = Int32(pointer.pointee.sa_family)
        var storage = pointer.pointee
        switch family {
        case AF_INET:
            var address = ""
            let success = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addressPointer in
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var addressValue = addressPointer.pointee.sin_addr
                    guard inet_ntop(AF_INET, &addressValue, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return false }
                    address = String(cString: buffer)
                    return true
                }
            }
            return success ? address : nil
        case AF_INET6:
            var address = ""
            let success = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { addressPointer in
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    var addressValue = addressPointer.pointee.sin6_addr
                    guard inet_ntop(AF_INET6, &addressValue, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return false }
                    address = String(cString: buffer)
                    return true
                }
            }
            return success ? address : nil
        default:
            return nil
        }
    }
}

struct LocalAPIAuthPolicy: Equatable, Sendable {
    let bearerToken: String

    init(bearerToken: String) {
        self.bearerToken = bearerToken
    }

    func authorizes(_ request: LocalAPIRequest) -> Bool {
        guard let authorization = request.header("authorization"),
              authorization.hasPrefix("Bearer ") else { return false }
        let suppliedToken = String(authorization.dropFirst("Bearer ".count))
        guard !suppliedToken.isEmpty,
              !suppliedToken.contains(where: { $0.isWhitespace }) else { return false }
        return Self.constantTimeEqual(suppliedToken, bearerToken)
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(left.count ^ right.count)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }
}

enum LocalAPITokenStore {
    static let keychainService = "com.pdg.chatgpt-micro-launchpad.local-api"
    static let keychainAccount = "rest-bearer-token"

    /// Read-only lookup used by the explicit native copy-token action.
    /// It never creates, rotates, or persists a credential.
    static func loadExistingToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              data.count == 32 else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    static func loadOrCreateToken() -> String? {
        if let existingToken = loadExistingToken() { return existingToken }

        var bytes = Data(repeating: 0, count: 32)
        guard bytes.withUnsafeMutableBytes({ buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!) == errSecSuccess
        }) else { return nil }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem { return loadExistingToken() }
        guard addStatus == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum LocalAPIServiceError: Error, Equatable, Sendable {
    case appNotRegistered
    case appUnavailable
    case bundleIdentityMismatch
    case cannotTerminate
    case cannotTargetSelf
}

@MainActor
final class LocalAPIService {
    typealias RegisteredAppsProvider = @MainActor () -> [LocalAPIRegisteredApplication]
    typealias ApplicationOperation = @MainActor (String, LocalAPIAppOperation) throws -> LocalAPIRegisteredApplication
    typealias StaticResourceProvider = @MainActor (String) -> Data?

    static let securityHeaders: [String: String] = [
        "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Cache-Control": "no-store"
    ]

    private let authPolicy: LocalAPIAuthPolicy
    private let networkPolicy: LocalAPINetworkPolicy
    private let expectedOrigin: String
    private let registeredAppsProvider: RegisteredAppsProvider
    private let applicationOperation: ApplicationOperation
    private let staticResourceProvider: StaticResourceProvider
    private var capabilityIDByBundleIdentifier: [String: String] = [:]
    private var bundleIdentifierByCapabilityID: [String: String] = [:]

    init(
        bearerToken: String,
        networkPolicy: LocalAPINetworkPolicy = .tailscaleOnly,
        expectedOrigin: String = "",
        registeredAppsProvider: @escaping RegisteredAppsProvider,
        applicationOperation: @escaping ApplicationOperation,
        staticResourceProvider: @escaping StaticResourceProvider = LocalAPIService.bundledResource
    ) {
        self.authPolicy = LocalAPIAuthPolicy(bearerToken: bearerToken)
        self.networkPolicy = networkPolicy
        self.expectedOrigin = expectedOrigin
        self.registeredAppsProvider = registeredAppsProvider
        self.applicationOperation = applicationOperation
        self.staticResourceProvider = staticResourceProvider
    }

    func handle(_ request: LocalAPIRequest, context: LocalAPIRequestContext) -> LocalAPIHTTPResponse {
        guard networkPolicy.allows(
            localInterfaceName: context.localInterfaceName,
            localAddress: context.localAddress,
            remoteAddress: context.remoteAddress
        ) else {
            return error(403, "Forbidden")
        }

        guard let path = request.path else { return error(400, "Bad request") }
        if path.hasPrefix("/api/") || path == "/api" {
            guard authPolicy.authorizes(request) else { return unauthorized() }
            return handleAPI(request, path: path, context: context)
        }

        guard request.method == LocalAPIHTTPMethod.get.rawValue else {
            return error(405, "Method not allowed")
        }
        guard request.query == nil,
              let resourcePath = staticResourcePath(for: path),
              let data = staticResourceProvider(resourcePath) else {
            return error(404, "Not found")
        }
        var headers = Self.securityHeaders
        headers["Content-Type"] = contentType(for: resourcePath)
        return LocalAPIHTTPResponse(statusCode: 200, headers: headers, body: data)
    }

    private func handleAPI(_ request: LocalAPIRequest, path: String, context: LocalAPIRequestContext) -> LocalAPIHTTPResponse {
        guard request.query == nil else { return error(400, "Bad request") }
        if path == "/api/apps" {
            guard request.method == LocalAPIHTTPMethod.get.rawValue else {
                return error(405, "Method not allowed")
            }
            guard request.body.isEmpty else { return error(400, "Bad request") }
            let apps = refreshCatalog().map { app in
                LocalAPIApplication(id: capabilityID(for: app.bundleIdentifier), name: app.name, running: app.running)
            }
            return json(statusCode: 200, LocalAPIApplicationsResponse(apps: apps))
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 5,
              components[1] == "api",
              components[2] == "apps",
              let operation = LocalAPIAppOperation(rawValue: String(components[4])) else {
            return error(404, "Not found")
        }
        guard request.method == LocalAPIHTTPMethod.post.rawValue else {
            return error(405, "Method not allowed")
        }
        guard request.body.isEmpty else { return error(400, "Bad request") }
        let actualOrigin = context.expectedOrigin.isEmpty ? expectedOrigin : context.expectedOrigin
        guard let origin = request.header("origin"),
              !origin.isEmpty,
              origin != "null",
              !actualOrigin.isEmpty,
              origin == actualOrigin else {
            return error(403, "Forbidden")
        }

        let registeredApps = refreshCatalog()
        guard let capabilityID = decodedCapabilityID(from: String(components[3])),
              let bundleIdentifier = bundleIdentifierByCapabilityID[capabilityID] else {
            return error(404, "Not found")
        }
        guard registeredApps.contains(where: { $0.bundleIdentifier == bundleIdentifier }),
              bundleIdentifierByCapabilityID[capabilityID] == bundleIdentifier else {
            return error(404, "Not found")
        }

        do {
            let app = try applicationOperation(bundleIdentifier, operation)
            guard app.bundleIdentifier == bundleIdentifier else {
                return error(409, "App unavailable")
            }
            return json(
                statusCode: 200,
                LocalAPIApplication(id: capabilityID, name: app.name, running: app.running)
            )
        } catch LocalAPIServiceError.appNotRegistered {
            return error(404, "Not found")
        } catch LocalAPIServiceError.appUnavailable {
            return error(404, "App unavailable")
        } catch LocalAPIServiceError.cannotTargetSelf {
            return error(403, "Forbidden")
        } catch LocalAPIServiceError.bundleIdentityMismatch {
            return error(409, "App unavailable")
        } catch LocalAPIServiceError.cannotTerminate {
            return error(409, "App could not be terminated")
        } catch _ {
            return error(500, "Internal server error")
        }
    }

    private func refreshCatalog() -> [LocalAPIRegisteredApplication] {
        let candidates = registeredAppsProvider()
            .filter { LocalAPIService.isSafeBundleIdentifier($0.bundleIdentifier) }
        var uniqueByBundle: [String: LocalAPIRegisteredApplication] = [:]
        for candidate in candidates where uniqueByBundle[candidate.bundleIdentifier] == nil {
            uniqueByBundle[candidate.bundleIdentifier] = candidate
        }

        let removedBundles = Set(capabilityIDByBundleIdentifier.keys).subtracting(uniqueByBundle.keys)
        for bundleIdentifier in removedBundles {
            if let capabilityID = capabilityIDByBundleIdentifier.removeValue(forKey: bundleIdentifier) {
                bundleIdentifierByCapabilityID.removeValue(forKey: capabilityID)
            }
        }
        for bundleIdentifier in uniqueByBundle.keys.sorted() where capabilityIDByBundleIdentifier[bundleIdentifier] == nil {
            var capabilityID = UUID().uuidString.lowercased()
            while bundleIdentifierByCapabilityID[capabilityID] != nil || capabilityID == bundleIdentifier {
                capabilityID = UUID().uuidString.lowercased()
            }
            capabilityIDByBundleIdentifier[bundleIdentifier] = capabilityID
            bundleIdentifierByCapabilityID[capabilityID] = bundleIdentifier
        }
        return uniqueByBundle.values.sorted { lhs, rhs in
            if lhs.name == rhs.name { return lhs.bundleIdentifier < rhs.bundleIdentifier }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func capabilityID(for bundleIdentifier: String) -> String {
        // refreshCatalog creates IDs before this helper is called.
        capabilityIDByBundleIdentifier[bundleIdentifier] ?? ""
    }

    private func decodedCapabilityID(from rawSegment: String) -> String? {
        guard !rawSegment.isEmpty,
              !rawSegment.contains("\\"),
              let decoded = rawSegment.removingPercentEncoding,
              decoded == rawSegment,
              UUID(uuidString: decoded) != nil else { return nil }
        return decoded
    }

    static func isSafeBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("."),
              !value.hasSuffix("."),
              value.split(separator: ".", omittingEmptySubsequences: false).count >= 2 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E:
                return true
            default:
                return false
            }
        }
    }

    private func staticResourcePath(for path: String) -> String? {
        switch path {
        case "/", "/index.html": "Web/index.html"
        case "/styles.css": "Web/styles.css"
        case "/app.js": "Web/app.js"
        default: nil
        }
    }

    private func contentType(for path: String) -> String {
        switch path {
        case "Web/index.html": "text/html; charset=utf-8"
        case "Web/styles.css": "text/css; charset=utf-8"
        case "Web/app.js": "text/javascript; charset=utf-8"
        default: "application/octet-stream"
        }
    }

    private func unauthorized() -> LocalAPIHTTPResponse {
        var headers = Self.securityHeaders
        headers["WWW-Authenticate"] = "Bearer"
        return LocalAPIHTTPResponse.json(statusCode: 401, LocalAPIErrorResponse(error: "Unauthorized"), headers: headers)
    }

    private func json<T: Encodable>(statusCode: Int, _ value: T) -> LocalAPIHTTPResponse {
        LocalAPIHTTPResponse.json(statusCode: statusCode, value, headers: Self.securityHeaders)
    }

    private func error(_ statusCode: Int, _ message: String) -> LocalAPIHTTPResponse {
        LocalAPIHTTPResponse.json(statusCode: statusCode, LocalAPIErrorResponse(error: message), headers: Self.securityHeaders)
    }

    nonisolated static func bundledResource(_ path: String) -> Data? {
        guard path.hasPrefix("Web/"),
              !path.contains(".."),
              !path.contains("\\"),
              let separator = path.lastIndex(of: ".") else { return nil }
        let name = String(path[path.index(path.startIndex, offsetBy: 4)..<separator])
        let ext = String(path[path.index(after: separator)...])
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Web")
            ?? Bundle.module.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: path, withExtension: nil)
        guard let url else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

@MainActor
enum LocalAPIAppRegistry {
    private static let preferencesSuite = "com.pdg.chatgpt-micro-launchpad.native"
    static func registeredApps() -> [LocalAPIRegisteredApplication] {
        let preferences = UserDefaults(suiteName: preferencesSuite) ?? .standard
        preferences.synchronize()
        let smartphonePages = SmartphoneDefaults.persistedPages()
        let identifiers = smartphonePages
            .flatMap(\.buttons)
            .compactMap(bundleIdentifier(for:))
        let uniqueIdentifiers = Set(identifiers.filter(LocalAPIService.isSafeBundleIdentifier))
        return uniqueIdentifiers.sorted().map { identifier in
            LocalAPIRegisteredApplication(
                bundleIdentifier: identifier,
                name: AppRegistrationService.displayName(for: identifier) ?? "Registered app",
                running: !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
            )
        }
    }

    static func perform(_ bundleIdentifier: String, _ operation: LocalAPIAppOperation) throws -> LocalAPIRegisteredApplication {
        guard registeredApps().contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw LocalAPIServiceError.appNotRegistered
        }
        guard Bundle.main.bundleIdentifier != bundleIdentifier else {
            throw LocalAPIServiceError.cannotTargetSelf
        }

        switch operation {
        case .launch:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw LocalAPIServiceError.appUnavailable
            }
            guard Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
                throw LocalAPIServiceError.bundleIdentityMismatch
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .quit:
            let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            for application in runningApplications where !application.terminate() {
                throw LocalAPIServiceError.cannotTerminate
            }
        }

        let resolvedName = AppRegistrationService.displayName(for: bundleIdentifier) ?? "Registered app"
        return LocalAPIRegisteredApplication(
            bundleIdentifier: bundleIdentifier,
            name: resolvedName,
            running: !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        )
    }

    private static func bundleIdentifier(for button: SmartphoneButton) -> String? {
        switch button.action.kind {
        case .app:
            button.action.value
        case .shortcut:
            button.action.targetAppBundleIdentifier.isEmpty ? nil : button.action.targetAppBundleIdentifier
        case .terminalCommand, .url, .none:
            nil
        }
    }
}

@MainActor
final class LocalAPIServer {
    static let defaultPort: UInt16 = 43_124
    static let maximumConnections = 32
    static let idleReadTimeout: TimeInterval = 15
    static let maximumRequestDuration: TimeInterval = 15

    private let port: UInt16
    private let networkPolicy: LocalAPINetworkPolicy
    private let service: LocalAPIService?
    private let bindingProvider: () -> LocalAPINetworkBinding?
    private let queue = DispatchQueue(label: "MicroLaunchpad.local-api", qos: .userInitiated)
    private var listener: NWListener?
    private var pathMonitor: NWPathMonitor?
    private var activeBinding: LocalAPINetworkBinding?
    private var connections: [UUID: NWConnection] = [:]
    private var buffers: [UUID: Data] = [:]
    private var connectionTimeouts: [UUID: DispatchWorkItem] = [:]
    private var requestDeadlines: [UUID: DispatchWorkItem] = [:]

    private(set) var isRunning = false
    private(set) var lastError: LocalAPIServerError?

    enum LocalAPIServerError: Error, Equatable, Sendable {
        case authenticationUnavailable
        case tailscaleUnavailable
        case listenerFailed
    }

    init(
        port: UInt16 = LocalAPIServer.defaultPort,
        networkPolicy: LocalAPINetworkPolicy = .tailscaleOnly,
        service: LocalAPIService? = nil,
        bearerTokenProvider: () -> String? = LocalAPITokenStore.loadOrCreateToken,
        bindingProvider: (() -> LocalAPINetworkBinding?)? = nil
    ) {
        self.port = port
        self.networkPolicy = networkPolicy
        if let service {
            self.service = service
        } else if let token = bearerTokenProvider() {
            self.service = LocalAPIService(
                bearerToken: token,
                networkPolicy: networkPolicy,
                registeredAppsProvider: LocalAPIAppRegistry.registeredApps,
                applicationOperation: LocalAPIAppRegistry.perform
            )
        } else {
            self.service = nil
        }
        self.bindingProvider = bindingProvider ?? networkPolicy.resolveBinding
    }

    @discardableResult
    func start() -> Bool {
        guard listener == nil else { return true }
        guard service != nil else {
            lastError = .authenticationUnavailable
            return false
        }
        guard let binding = bindingProvider(),
              networkPolicy.allows(
                  localInterfaceName: binding.interfaceName,
                  localAddress: binding.address,
                  remoteAddress: binding.address
              ) else {
            lastError = .tailscaleUnavailable
            return false
        }

        activeBinding = binding
        lastError = nil
        startPathMonitor(for: binding)
        // NWPathMonitor delivers the exact NWInterface asynchronously. The
        // listener is intentionally not created until that check succeeds.
        return true
    }

    func stop() {
        listener?.cancel()
        listener = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        for timeout in connectionTimeouts.values { timeout.cancel() }
        connectionTimeouts.removeAll()
        for deadline in requestDeadlines.values { deadline.cancel() }
        requestDeadlines.removeAll()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        buffers.removeAll()
        activeBinding = nil
        isRunning = false
    }

    private func startPathMonitor(for binding: LocalAPINetworkBinding) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let interface = Self.validatedInterface(in: path, binding: binding)
            Task { @MainActor [weak self] in
                guard let self, self.activeBinding == binding else { return }
                guard let interface else {
                    self.isRunning = false
                    self.lastError = .tailscaleUnavailable
                    if self.listener != nil { self.stop() }
                    return
                }
                guard self.bindingProvider() == binding,
                      self.networkPolicy.allows(
                          localInterfaceName: binding.interfaceName,
                          localAddress: binding.address,
                          remoteAddress: binding.address
                      ) else {
                    self.isRunning = false
                    self.lastError = .tailscaleUnavailable
                    if self.listener != nil { self.stop() }
                    return
                }
                if self.listener == nil {
                    self.startListener(binding: binding, requiredInterface: interface)
                }
            }
        }
        pathMonitor = monitor
        monitor.start(queue: queue)
    }

    private func startListener(binding: LocalAPINetworkBinding, requiredInterface: NWInterface) {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        // `.other` is the Network.framework type used by macOS utun devices.
        // The exact NWInterface object is selected from the satisfied path below;
        // this type constraint is an additional guard against a physical path.
        parameters.requiredInterfaceType = .other
        parameters.requiredInterface = requiredInterface
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(binding.address),
            port: NWEndpoint.Port(rawValue: port)!
        )
        do {
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                    case .failed:
                        self.isRunning = false
                        self.lastError = .listenerFailed
                        self.stop()
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            lastError = .listenerFailed
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maximumConnections,
              let binding = activeBinding,
              let remoteAddress = Self.hostString(from: connection.endpoint),
              bindingProvider() == binding,
              networkPolicy.allows(
                  localInterfaceName: binding.interfaceName,
                  localAddress: binding.address,
                  remoteAddress: remoteAddress
              ) else {
            connection.cancel()
            return
        }

        let id = UUID()
        connections[id] = connection
        buffers[id] = Data()
        armTimeout(for: id)
        armRequestDeadline(for: id)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failed = state { self.remove(connectionID: id) }
                if case .cancelled = state { self.remove(connectionID: id) }
                if case .ready = state {
                    guard self.validateConnectionPath(
                        connection.currentPath,
                        binding: binding,
                        remoteAddress: remoteAddress
                    ) else {
                        self.remove(connectionID: id)
                        return
                    }
                    self.receive(from: connection, id: id, binding: binding, remoteAddress: remoteAddress)
                }
            }
        }
        connection.pathUpdateHandler = { [weak self] path in
            let pathIsValid = Self.pathUsesValidatedInterface(path, binding: binding)
            Task { @MainActor [weak self] in
                guard let self, self.connections[id] != nil else { return }
                guard pathIsValid,
                      self.bindingProvider() == binding,
                      self.networkPolicy.allows(
                          localInterfaceName: binding.interfaceName,
                          localAddress: binding.address,
                          remoteAddress: remoteAddress
                      ) else {
                    self.remove(connectionID: id)
                    return
                }
            }
        }
        connection.start(queue: queue)
    }

    private func receive(
        from connection: NWConnection,
        id: UUID,
        binding: LocalAPINetworkBinding,
        remoteAddress: String
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: LocalAPIHTTPParser.maximumHeaderBytes + LocalAPIHTTPParser.maximumBodyBytes) { [weak self] data, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self, self.connections[id] != nil else { return }
                guard self.validateConnectionPath(
                          connection.currentPath,
                          binding: binding,
                          remoteAddress: remoteAddress
                      ) else {
                    self.remove(connectionID: id)
                    return
                }
                self.armTimeout(for: id)
                if let data, !data.isEmpty {
                    self.buffers[id, default: Data()].append(data)
                    switch LocalAPIHTTPParser.parse(self.buffers[id] ?? Data()) {
                    case .incomplete:
                        break
                    case let .invalid(parseError):
                        let statusCode: Int = parseError == .bodyTooLarge || parseError == .headersTooLarge ? 413 : 400
                        self.send(LocalAPIHTTPResponse.json(
                            statusCode: statusCode,
                            LocalAPIErrorResponse(error: statusCode == 413 ? "Request too large" : "Bad request"),
                            headers: LocalAPIService.securityHeaders
                        ), on: connection, id: id)
                        return
                    case let .request(request, _):
                        let expectedOrigin = Self.origin(for: binding.address, port: self.port)
                        let context = LocalAPIRequestContext(
                            localInterfaceName: binding.interfaceName,
                            localAddress: binding.address,
                            remoteAddress: remoteAddress,
                            expectedOrigin: expectedOrigin
                        )
                        let response = self.service?.handle(request, context: context)
                            ?? LocalAPIHTTPResponse.json(statusCode: 503, LocalAPIErrorResponse(error: "Service unavailable"), headers: LocalAPIService.securityHeaders)
                        self.send(response, on: connection, id: id)
                        return
                    }
                }
                if isComplete { self.remove(connectionID: id) }
                else if self.connections[id] != nil {
                    self.receive(from: connection, id: id, binding: binding, remoteAddress: remoteAddress)
                }
            }
        }
    }

    private func send(_ response: LocalAPIHTTPResponse, on connection: NWConnection, id: UUID) {
        connection.send(content: response.serialized, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor [weak self] in self?.remove(connectionID: id) }
        })
    }

    private func armTimeout(for id: UUID) {
        connectionTimeouts[id]?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.remove(connectionID: id) }
        }
        connectionTimeouts[id] = timeout
        queue.asyncAfter(deadline: .now() + Self.idleReadTimeout, execute: timeout)
    }

    private func armRequestDeadline(for id: UUID) {
        let deadline = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.remove(connectionID: id) }
        }
        requestDeadlines[id] = deadline
        queue.asyncAfter(deadline: .now() + Self.maximumRequestDuration, execute: deadline)
    }

    private func remove(connectionID id: UUID) {
        connectionTimeouts[id]?.cancel()
        connectionTimeouts.removeValue(forKey: id)
        requestDeadlines[id]?.cancel()
        requestDeadlines.removeValue(forKey: id)
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        buffers.removeValue(forKey: id)
    }

    private func validateConnectionPath(
        _ path: NWPath?,
        binding: LocalAPINetworkBinding,
        remoteAddress: String
    ) -> Bool {
        guard Self.pathUsesValidatedInterface(path, binding: binding),
              bindingProvider() == binding,
              networkPolicy.allows(
                  localInterfaceName: binding.interfaceName,
                  localAddress: binding.address,
                  remoteAddress: remoteAddress
              ) else { return false }
        return true
    }

    nonisolated static func pathUsesValidatedInterface(_ path: NWPath?, binding: LocalAPINetworkBinding) -> Bool {
        validatedInterface(in: path, binding: binding) != nil
    }

    nonisolated static func validatedInterface(in path: NWPath?, binding: LocalAPINetworkBinding) -> NWInterface? {
        // The current macOS SDK does not expose effectiveLocalEndpoint on NWPath.
        // Exact local-address binding is therefore enforced by NWParameters' requiredLocalEndpoint,
        // while this helper proves the selected path contains the exact interface name and type.
        guard let path,
              path.status == .satisfied,
              binding.interfaceName.hasPrefix(LocalAPINetworkPolicy.tailscaleInterfacePrefix),
              LocalAPINetworkPolicy.isTailscaleAddress(binding.address),
              let interface = path.availableInterfaces.first(where: { $0.name == binding.interfaceName }),
              interface.type == .other,
              path.usesInterfaceType(interface.type) else { return nil }
        return interface
    }

    private static func hostString(from endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        return String(describing: host).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    static func origin(for address: String, port: UInt16) -> String {
        let host = address.contains(":") ? "[\(address)]" : address
        return "http://\(host):\(port)"
    }
}
