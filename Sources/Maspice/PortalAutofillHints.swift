// SPDX-License-Identifier: MIT
import Foundation
import WebKit

/// Help system Password AutoFill recognize older Ravada login markup. This
/// changes field semantics only: no credential reads, writes, or submission.
enum PortalAutofillHints {
    static let source = #"""
    expectedOrigin => {
        if (window !== window.top || location.protocol !== 'https:' || location.origin !== expectedOrigin) return;
        for (const form of document.forms) {
            const action = new URL(form.action, document.baseURI);
            if (form.autocomplete === 'off' || action.origin !== expectedOrigin || action.username || action.password || form.method.toLowerCase() !== 'post') continue;
            const passwords = [...form.querySelectorAll('input[type="password"]')];
            if (passwords.length !== 1) continue;
            const password = passwords[0];
            if (password.autocomplete && password.autocomplete !== 'current-password') continue;
            // Match Ravada's known login fields, not arbitrary registration,
            // password-change, or one-time-code forms on the same site.
            const username = form.querySelector('input#user[name="login"][type="text"]');
            if (!username || password.id !== 'pssw' || password.name !== 'password') continue;
            if (!username.autocomplete) username.autocomplete = 'username';
            if (!password.autocomplete) password.autocomplete = 'current-password';
        }
    }
    """#

    @MainActor static func script(for portalURL: URL) -> WKUserScript? {
        guard portalURL.scheme?.lowercased() == "https", portalURL.user == nil, portalURL.password == nil,
              var components = URLComponents(url: portalURL, resolvingAgainstBaseURL: true),
              components.host != nil else { return nil }
        components.host = components.host?.lowercased()
        if components.port == 443 { components.port = nil }
        components.path = ""; components.query = nil; components.fragment = nil
        guard let origin = components.string,
              let encoded = try? JSONEncoder().encode(origin), let literal = String(data: encoded, encoding: .utf8) else { return nil }
        return WKUserScript(source: "(\(source))(\(literal));", injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true, in: .defaultClient)
    }
}
