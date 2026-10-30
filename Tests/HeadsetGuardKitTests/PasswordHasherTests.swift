import Testing
@testable import HeadsetGuardKit

@Suite("Password Hasher Tests")
struct PasswordHasherTests {
    @Test("Hash matches Objective-C vector")
    func hashMatchesObjectiveCVector() {
        let salt = Data(0..<32)
        let hash = PasswordHasher.hash("correct horse", salt: salt)
        #expect(hash == "0iA+0KW9yVM+65HVh9L5QQMTX9ltslP3pajYJbjMft8=")
    }

    @Test("Special and edge-case passwords hash and verify consistently")
    func testEdgeCasePasswords() {
        let salt = PasswordHasher.makeSalt() ?? Data(repeating: 0x01, count: 32)

        let edgeCases = [
            "",
            String(repeating: "A", count: 10_000),
            "pässwörd👩‍💻"
        ]

        for pass in edgeCases {
            let h1 = PasswordHasher.hash(pass, salt: salt)
            let h2 = PasswordHasher.hash(pass, salt: salt)
            #expect(!h1.isEmpty)
            #expect(h1 == h2)

            let hDifferent = PasswordHasher.hash(pass + "_different", salt: salt)
            #expect(h1 != hDifferent)
        }
    }
}
