import Foundation
import Testing
import WebKit
@testable import Maspice

@MainActor struct PortalAutofillHintsTests {
    @Test func annotatesOnlySameOriginLoginFieldsWithoutReadingOrFillingPasswords() async throws {
        let portal = URL(string: "https://portal.example/")!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(try #require(PortalAutofillHints.script(for: portal)))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        let loader = AutofillPageLoader()
        view.navigationDelegate = loader
        view.loadSimulatedRequest(URLRequest(url: portal), responseHTML: """
        <form method="post"><input id="user" name="login" type="text"><input id="pssw" name="password" type="password"><button>Login</button></form>
        <form method="post" action="https://other.example/"><input id="user" name="login" type="text"><input id="pssw" name="password" type="password"></form>
        <form method="post"><input id="user" name="login" type="text"><input id="pssw" name="password" type="password" autocomplete="new-password"></form>
        <form method="post"><input id="user" name="login" type="text"><input id="pssw" name="password" type="password" autocomplete="off"></form>
        <form method="post"><input name="email"><input type="password" name="password"></form>
        <form method="post" autocomplete="off"><input id="user" name="login" type="text"><input id="pssw" name="password" type="password"></form>
        <form method="post"><input id="user" name="login" type="text" autocomplete="email"><input id="pssw" name="password" type="password"></form>
        <form method="post"><input id="user" name="login" type="text"><input id="pssw" name="password" type="password"><input type="password" name="confirm"></form>
        """)
        for _ in 0..<100 {
            if loader.loaded { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(loader.loaded)
        let types = try await view.callAsyncJavaScript("return [...document.querySelectorAll('input')].map(i => i.autocomplete);",
                                                       in: nil, contentWorld: .page) as? [String]
        #expect(types == ["username", "current-password", "", "", "", "new-password", "", "off", "", "", "", "", "email", "current-password", "", "", ""])
        let empty = try await view.callAsyncJavaScript("return [...document.querySelectorAll('input')].every(i => i.value === '');",
                                                       in: nil, contentWorld: .page) as? Bool
        #expect(empty == true)
        #expect(PortalAutofillHints.script(for: URL(string: "http://portal.example")!) == nil)
    }
}

@MainActor private final class AutofillPageLoader: NSObject, WKNavigationDelegate {
    var loaded = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
}
