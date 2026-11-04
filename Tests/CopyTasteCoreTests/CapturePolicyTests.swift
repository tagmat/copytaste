import XCTest
@testable import CopyTasteCore

final class CapturePolicyTests: XCTestCase {
    private let policy = CapturePolicy()

    func testMemoryIsDefaultAndCaptureRequiresOptIn() {
        let preferences = Preferences()
        XCTAssertEqual(preferences.storageMode, .memory)
        XCTAssertFalse(preferences.captureEnabled)
        XCTAssertTrue(preferences.captureImages)
    }

    func testEveryPrivateMarkerBlocksCaptureBeforePayloadReading() {
        for marker in CapturePolicy.privateTypes {
            XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Safari", types: [marker, "public.utf8-plain-text"])), .concealed)
        }
    }

    func testProtectedBundleFamiliesAndHelpersAreBlocked() {
        for family in CapturePolicy.protectedBundlePrefixes {
            XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: family)), .excludedApplication)
            XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: family + ".helper")), .excludedApplication)
            XCTAssertTrue(policy.isExcluded(family.uppercased()))
            XCTAssertFalse(policy.isExcluded(family + "-unrelated"))
        }
    }

    func testCustomExclusionAndClaimedProtectedSource() {
        let custom = CapturePolicy(excludedBundleIDs: ["COM.EXAMPLE.PRIVATE"])
        XCTAssertEqual(custom.rejection(for: CaptureMetadata(sourceBundleID: "com.example.private")), .excludedApplication)
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Safari", claimedSourceBundleID: "com.apple.Passwords")), .excludedApplication)
    }

    func testUntrustedClaimsCannotAllowProtectedForegroundApplication() {
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Passwords", claimedSourceBundleID: "com.apple.Notes")), .excludedApplication)
    }

    func testMissingSourceSecureInputAndSourceRacesFailClosed() {
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: nil)), .unknownSource)
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "")), .unknownSource)
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Notes", secureInput: true)), .secureInput)
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Notes", sourceChanged: true)), .sourceChanged)
    }

    func testOwnClipboardDoesNotLoop() {
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: CapturePolicy.ownBundleID)), .selfWrite)
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Notes", types: ["net.tagmat.copytaste.origin"])), .selfWrite)
    }

    func testFileMetadataPassesAndMultipleItemsAreRejected() {
        XCTAssertNil(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.finder", types: ["public.file-url"])))
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Notes", itemCount: 2)), .unsupported)
        XCTAssertEqual(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Notes", itemCount: 0)), .unsupported)
    }

    func testOrdinaryTextAndURLsAreAllowed() {
        for text in ["A useful note for tomorrow.", "struct Note { let text: String }", "https://example.org/docs", "Hello, dünya!", "A second line\nwith some details."] {
            XCTAssertNil(policy.rejection(forText: text))
        }
        XCTAssertNil(policy.rejection(for: CaptureMetadata(sourceBundleID: "com.apple.Notes", types: ["public.utf8-plain-text"])))
    }

    func testCredentialPatternsAreBlocked() {
        let secrets = ["password=example-value", "API_KEY: example-value", "Authorization: Bearer synthetic-value",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nsynthetic fixture\n-----END OPENSSH PRIVATE KEY-----",
            "ghp_" + String(repeating: "a", count: 36), "sk-" + String(repeating: "b", count: 30),
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmaXh0dXJlIn0.c3ludGhldGljZml4dHVyZQ",
            "482931", "Abc9!exampleValue", "{\"password\": \"synthetic-fixture\"}"]
        for text in secrets { XCTAssertEqual(policy.rejection(forText: text), .secret, "A synthetic credential fixture was allowed") }
    }

    func testCredentialURLsAreBlocked() {
        for text in ["https://example.org/?access_token=fixture", "https://name:fixture@example.org/", "https://example.org/#token=fixture", "https://example.org/?%74oken=fixture", "https://example.org/?code=fixture"] {
            XCTAssertEqual(policy.rejection(forText: text), .secret)
        }
    }

    func testPaymentNumbersUseLuhnValidation() {
        XCTAssertEqual(policy.rejection(forText: "Synthetic test number: 4111 1111 1111 1111"), .secret)
        XCTAssertNil(policy.rejection(forText: "Reference number: 4111 1111 1111 1112"))
    }

    func testPayloadLimitsUseUTF8Bytes() {
        XCTAssertEqual(policy.rejection(forText: String(repeating: "x", count: CapturePolicy.maxTextBytes + 1)), .tooLarge)
        XCTAssertEqual(policy.rejection(forText: String(repeating: "界", count: CapturePolicy.maxTextBytes / 3 + 1)), .tooLarge)
        XCTAssertEqual(policy.rejection(forText: " \n\t"), .empty)
    }

    func testOnlyWebURLsAreClassifiedAsLinks() {
        XCTAssertEqual(CapturePolicy.kind(for: "https://example.org/hello"), .link)
        for text in ["file:///Users/example/private", "javascript:alert(1)", "A note with https://example.org", "example.org"] {
            XCTAssertEqual(CapturePolicy.kind(for: text), .text)
        }
    }
}
