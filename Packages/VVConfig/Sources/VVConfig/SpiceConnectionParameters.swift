// SPDX-License-Identifier: MIT
import Foundation

/// Direct SPICE connection parameters derived from a validated `.vv` file.
/// Proxy routing never crosses this boundary. A validated `host-subject` is
/// carried intact for SwiftSpice's explicit virt-viewer certificate policy.
public struct SpiceConnectionParameters: Equatable, Sendable {
    public var host: String
    public var port: Int?
    public var tlsPort: Int?
    public var password: String?
    /// Optional PEM CA supplied by a direct TLS `.vv` file.
    public var caCertificate: String?
    /// Complete virt-viewer `host-subject` expected on the TLS leaf certificate.
    public var certificateSubject: String?
    public var title: String?
    public var fullscreen: Bool

    public init(
        host: String,
        port: Int? = nil,
        tlsPort: Int? = nil,
        password: String? = nil,
        caCertificate: String? = nil,
        certificateSubject: String? = nil,
        title: String? = nil,
        fullscreen: Bool = false
    ) {
        self.host = host
        self.port = port
        self.tlsPort = tlsPort
        self.password = password
        self.caCertificate = caCertificate
        self.certificateSubject = certificateSubject
        self.title = title
        self.fullscreen = fullscreen
    }

    public var isTLS: Bool { tlsPort != nil }
}

extension SpiceConnectionParameters {
    public init(from config: VVConfig) throws {
        try config.validate()
        self.init(
            host: config.host ?? "",
            port: config.port,
            tlsPort: config.tlsPort,
            password: config.password,
            caCertificate: config.caCertificate,
            certificateSubject: config.hostSubject,
            title: config.title,
            fullscreen: config.fullscreen ?? false
        )
    }
}
