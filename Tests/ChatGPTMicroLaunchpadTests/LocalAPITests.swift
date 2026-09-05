import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

@MainActor
final class LocalAPITests: XCTestCase {
    private let token = String(repeating: "a", count: 64)
    private let expectedOrigin = "http://100.64.1.2:43124"

    private var context: LocalAPIRequestContext {
        LocalAPIRequestContext(
            localInterfaceName: "utun42",
            localAddress: "100.64.1.2",
            remoteAddress: "100.64.1.3",
            expectedOrigin: expectedOrigin
        )
    }

    private var registeredTerminal: LocalAPIRegisteredApplication {
        LocalAPIRegisteredApplication(bundleIdentifier: "com.apple.Terminal", name: "Terminal", running: false)
    }

    func testNetworkPolicy_acceptsOnlyTailnetAddressesOnValidatedInterface() {
        let policy = LocalAPINetworkPolicy(boundAddress: "100.64.1.2", boundInterfaceName: "utun42")

        XCTAssertTrue(policy.allows(
            localInterfaceName: "utun42",
            localAddress: "100.64.1.2",
            remoteAddress: "100.64.1.3"
        ))
        XCTAssertFalse(policy.allows(
            localInterfaceName: "en0",
            localAddress: "100.64.1.2",
            remoteAddress: "100.64.1.3"
        ))
        XCTAssertFalse(policy.allows(
            localInterfaceName: "utun42",
            localAddress: "192.168.1.10",
            remoteAddress: "100.64.1.3"
        ))
        XCTAssertFalse(policy.allows(
            localInterfaceName: "utun42",
            localAddress: "100.64.1.2",
            remoteAddress: "127.0.0.1"
        ))
        XCTAssertNil(policy.selectBinding(from: [
            LocalAPINetworkBinding(interfaceName: "en0", address: "192.168.1.10")
        ]))
    }

    func testNetworkPolicy_selectsOnlyTheConfiguredExactTailnetBindingWhenUtunPathsAreAmbiguous() {
        let policy = LocalAPINetworkPolicy(boundAddress: "100.64.1.2", boundInterfaceName: "utun42")
        let staleBinding = LocalAPINetworkBinding(interfaceName: "utun7", address: "100.64.1.2")
        let activeBinding = LocalAPINetworkBinding(interfaceName: "utun42", address: "100.64.1.2")

        XCTAssertEqual(policy.selectBinding(from: [staleBinding, activeBinding]), activeBinding)
        XCTAssertTrue(policy.allows(
            localInterfaceName: activeBinding.interfaceName,
            localAddress: activeBinding.address,
            remoteAddress: "100.64.1.3"
        ))
        XCTAssertFalse(policy.allows(
            localInterfaceName: staleBinding.interfaceName,
            localAddress: staleBinding.address,
            remoteAddress: "100.64.1.3"
        ))
    }

    func testHTTPParser_isIncrementalAndRejectsAmbiguousOrOversizedFraming() {
        let firstPart = Data("GET /api/apps HTTP/1.1\r\nHost: 100.64.1.2\r\n".utf8)
        XCTAssertEqual(LocalAPIHTTPParser.parse(firstPart), .incomplete)

        let complete = firstPart + Data("Authorization: Bearer \(token)\r\n\r\n".utf8)
        guard case let .request(request, consumedBytes) = LocalAPIHTTPParser.parse(complete) else {
            return XCTFail("expected a complete request")
        }
        XCTAssertEqual(consumedBytes, complete.count)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/api/apps")
        XCTAssertEqual(request.header("authorization"), "Bearer \(token)")

        let duplicateLength = Data("POST /api/apps/x/launch HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n".utf8)
        XCTAssertEqual(LocalAPIHTTPParser.parse(duplicateLength), .invalid(.duplicateHeader))

        let chunked = Data("GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        XCTAssertEqual(LocalAPIHTTPParser.parse(chunked), .invalid(.unsupportedTransferEncoding))

        let oversizedBody = Data("POST /api/apps/x/launch HTTP/1.1\r\nContent-Length: 4097\r\n\r\n".utf8)
        XCTAssertEqual(LocalAPIHTTPParser.parse(oversizedBody), .invalid(.bodyTooLarge))
    }

    func testApps_requiresBearerTokenAndExposesOnlyOpaqueFields() throws {
        let service = makeService(provider: { [self] in [self.registeredTerminal] }) { _, _ in
            XCTFail("listing must not execute an app operation")
            return self.registeredTerminal
        }

        let missingToken = service.handle(LocalAPIRequest(method: "GET", target: "/api/apps"), context: context)
        XCTAssertEqual(missingToken.statusCode, 401)
        XCTAssertFalse(String(decoding: missingToken.body, as: UTF8.self).contains("Terminal"))

        let response = service.handle(
            LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token)"]),
            context: context
        )
        XCTAssertEqual(response.statusCode, 200)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let apps = try XCTUnwrap(object["apps"] as? [[String: Any]])
        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(Set(app.keys), Set(["id", "name", "running"]))
        XCTAssertEqual(app["name"] as? String, "Terminal")
        let capabilityID = try XCTUnwrap(app["id"] as? String)
        XCTAssertNotEqual(capabilityID, "com.apple.Terminal")
        XCTAssertNotNil(UUID(uuidString: capabilityID))
        XCTAssertFalse(String(decoding: response.body, as: UTF8.self).contains("bundleIdentifier"))
    }

    func testCapabilityID_isStableAndMapsPrivatelyToExactBundleIdentifier() throws {
        var operationBundleIdentifier: String?
        let service = makeService(provider: { [self] in [self.registeredTerminal] }) { bundleIdentifier, operation in
            operationBundleIdentifier = bundleIdentifier
            XCTAssertEqual(operation, .launch)
            return LocalAPIRegisteredApplication(bundleIdentifier: bundleIdentifier, name: "Terminal", running: true)
        }
        let listRequest = LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token)"])
        let firstList = service.handle(listRequest, context: context)
        let firstID = try capabilityID(from: firstList)
        let secondID = try capabilityID(from: service.handle(listRequest, context: context))
        XCTAssertEqual(firstID, secondID)

        let launchRequest = LocalAPIRequest(
            method: "POST",
            target: "/api/apps/\(firstID)/launch",
            headers: ["Authorization": "Bearer \(token)", "Origin": expectedOrigin]
        )
        let response = service.handle(launchRequest, context: context)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(operationBundleIdentifier, "com.apple.Terminal")
        XCTAssertFalse(String(decoding: response.body, as: UTF8.self).contains("bundleIdentifier"))
    }

    func testMutations_requireExactOriginTokenAndEmptyBody() throws {
        var operationCount = 0
        let service = makeService(provider: { [self] in [self.registeredTerminal] }) { bundleIdentifier, operation in
            operationCount += 1
            return LocalAPIRegisteredApplication(
                bundleIdentifier: bundleIdentifier,
                name: "Terminal",
                running: operation == .launch
            )
        }
        let list = service.handle(
            LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token)"]),
            context: context
        )
        let capabilityID = try capabilityID(from: list)

        let missingOrigin = service.handle(
            LocalAPIRequest(method: "POST", target: "/api/apps/\(capabilityID)/launch", headers: ["Authorization": "Bearer \(token)"]),
            context: context
        )
        XCTAssertEqual(missingOrigin.statusCode, 403)

        let crossOrigin = service.handle(
            LocalAPIRequest(method: "POST", target: "/api/apps/\(capabilityID)/launch", headers: ["Authorization": "Bearer \(token)", "Origin": "https://evil.example"]),
            context: context
        )
        XCTAssertEqual(crossOrigin.statusCode, 403)

        let terminalPayload = Data(#"{"kind":"terminalCommand","value":"echo hacked"}"#.utf8)
        let bodyRequest = LocalAPIRequest(
            method: "POST",
            target: "/api/apps/\(capabilityID)/launch",
            headers: ["Authorization": "Bearer \(token)", "Origin": expectedOrigin],
            body: terminalPayload
        )
        XCTAssertEqual(service.handle(bodyRequest, context: context).statusCode, 400)
        XCTAssertEqual(operationCount, 0)

        let valid = LocalAPIRequest(
            method: "POST",
            target: "/api/apps/\(capabilityID)/launch",
            headers: ["Authorization": "Bearer \(token)", "Origin": expectedOrigin]
        )
        XCTAssertEqual(service.handle(valid, context: context).statusCode, 200)
        XCTAssertEqual(operationCount, 1)
    }

    func testQuit_usesTheSameOpaqueCapabilityAndReturnsNoBundleMetadata() throws {
        var operationBundleIdentifier: String?
        var operation: LocalAPIAppOperation?
        let service = makeService(provider: { [self] in [self.registeredTerminal] }) { bundleIdentifier, requestedOperation in
            operationBundleIdentifier = bundleIdentifier
            operation = requestedOperation
            return LocalAPIRegisteredApplication(bundleIdentifier: bundleIdentifier, name: "Terminal", running: false)
        }
        let list = service.handle(
            LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token)"]),
            context: context
        )
        let capabilityID = try capabilityID(from: list)
        let response = service.handle(
            LocalAPIRequest(
                method: "POST",
                target: "/api/apps/\(capabilityID)/quit",
                headers: ["Authorization": "Bearer \(token)", "Origin": expectedOrigin]
            ),
            context: context
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(operationBundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(operation, .quit)
        XCTAssertFalse(String(decoding: response.body, as: UTF8.self).contains("bundleIdentifier"))
    }

    func testMutation_rejectsBundleIDsPathsArrayIndexesAndTraversal() throws {
        var operationCount = 0
        let service = makeService(provider: { [self] in [self.registeredTerminal] }) { bundleIdentifier, _ in
            operationCount += 1
            return LocalAPIRegisteredApplication(bundleIdentifier: bundleIdentifier, name: "Terminal", running: false)
        }
        _ = service.handle(
            LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token)"]),
            context: context
        )
        let paths = [
            "/api/apps/com.apple.Terminal/launch",
            "/api/apps/0/launch",
            "/api/apps/../launch",
            "/api/apps/%2e%2e/launch",
            "/api/apps/%252e%252e/launch",
            "/api/apps//launch"
        ]
        for path in paths {
            let request = LocalAPIRequest(
                method: "POST",
                target: path,
                headers: ["Authorization": "Bearer \(token)", "Origin": expectedOrigin]
            )
            XCTAssertEqual(service.handle(request, context: context).statusCode, 404, path)
        }
        XCTAssertEqual(operationCount, 0)
    }

    func testStaticRoutes_serveOnlyFixedEmbeddedResourcesWithSecurityHeaders() {
        let resources = [
            "Web/index.html": Data("<html>index</html>".utf8),
            "Web/styles.css": Data("body{}".utf8),
            "Web/app.js": Data("console.log('ok')".utf8)
        ]
        let service = makeService(provider: { [] }, staticResources: resources) { _, _ in
            XCTFail("static routes must not execute app operations")
            return self.registeredTerminal
        }
        for (path, expectedBody) in [
            ("/", resources["Web/index.html"]!),
            ("/index.html", resources["Web/index.html"]!),
            ("/styles.css", resources["Web/styles.css"]!),
            ("/app.js", resources["Web/app.js"]!)
        ] {
            let response = service.handle(LocalAPIRequest(method: "GET", target: path), context: context)
            XCTAssertEqual(response.statusCode, 200, path)
            XCTAssertEqual(response.body, expectedBody, path)
            XCTAssertEqual(response.headers["X-Content-Type-Options"], "nosniff")
            XCTAssertEqual(response.headers["Referrer-Policy"], "no-referrer")
            XCTAssertEqual(response.headers["Cache-Control"], "no-store")
        }
        XCTAssertEqual(service.handle(LocalAPIRequest(method: "GET", target: "/../secret"), context: context).statusCode, 404)
        XCTAssertEqual(service.handle(LocalAPIRequest(method: "GET", target: "/Web/index.html"), context: context).statusCode, 404)
        XCTAssertEqual(service.handle(LocalAPIRequest(method: "POST", target: "/"), context: context).statusCode, 405)
    }

    func testBundledResource_lookupUsesTheNativeWebResourceDirectory() {
        XCTAssertNotNil(LocalAPIService.bundledResource("Web/index.html"))
        XCTAssertNotNil(LocalAPIService.bundledResource("Web/styles.css"))
        XCTAssertNotNil(LocalAPIService.bundledResource("Web/app.js"))
        XCTAssertNil(LocalAPIService.bundledResource("Web/../Package.swift"))
    }

    func testServer_failsClosedWhenTailscaleBindingIsUnavailable() {
        let service = makeService(provider: { [] }) { _, _ in
            XCTFail("unreachable operation")
            return self.registeredTerminal
        }
        let server = LocalAPIServer(
            networkPolicy: LocalAPINetworkPolicy(),
            service: service,
            bindingProvider: { nil }
        )

        XCTAssertFalse(server.start())
        XCTAssertEqual(server.lastError, .tailscaleUnavailable)
        XCTAssertFalse(server.isRunning)
        server.stop()
    }

    func testServer_keepsIdleAndHardRequestDeadlinesBoundedToFifteenSeconds() {
        XCTAssertEqual(LocalAPIServer.idleReadTimeout, 15)
        XCTAssertEqual(LocalAPIServer.maximumRequestDuration, 15)
        XCTAssertLessThanOrEqual(LocalAPIServer.idleReadTimeout, LocalAPIServer.maximumRequestDuration)
    }

    func testAuthPolicy_doesNotAcceptQueryCredentialsOrMalformedBearerValues() {
        let policy = LocalAPIAuthPolicy(bearerToken: token)
        XCTAssertTrue(policy.authorizes(LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token)"])))
        XCTAssertFalse(policy.authorizes(LocalAPIRequest(method: "GET", target: "/api/apps?token=\(token)", headers: [:])))
        XCTAssertFalse(policy.authorizes(LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": token])))
        XCTAssertFalse(policy.authorizes(LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(token) "])))
        XCTAssertFalse(policy.authorizes(LocalAPIRequest(method: "GET", target: "/api/apps", headers: ["Authorization": "Bearer \(String(token.dropLast()))"])))
    }

    private func makeService(
        provider: @escaping LocalAPIService.RegisteredAppsProvider,
        staticResources: [String: Data] = [:],
        operation: @escaping LocalAPIService.ApplicationOperation
    ) -> LocalAPIService {
        LocalAPIService(
            bearerToken: token,
            networkPolicy: LocalAPINetworkPolicy(boundAddress: "100.64.1.2"),
            expectedOrigin: expectedOrigin,
            registeredAppsProvider: provider,
            applicationOperation: operation,
            staticResourceProvider: { path in staticResources[path] }
        )
    }

    private func capabilityID(from response: LocalAPIHTTPResponse) throws -> String {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let apps = try XCTUnwrap(object["apps"] as? [[String: Any]])
        return try XCTUnwrap(apps.first?["id"] as? String)
    }
}
