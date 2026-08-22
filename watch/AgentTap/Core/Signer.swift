// HMAC signing for Needs You verdicts — the v2 protocol twin of
// components/app_tokens/needs_you_send_policy.c (:215-277).
import Foundation
import CryptoKit

enum Verdict: String {
    case approve
    case deny
    case leaveIt = "leave_it"
}

struct Signer {
    /// The 64 ASCII hex characters are the HMAC key — never the decoded bytes.
    private let key: SymmetricKey
    let hasKey: Bool

    init(deviceKeyHex: String) {
        let trimmed = deviceKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hasKey = trimmed.count == 64
        self.key = SymmetricKey(data: Data(trimmed.utf8))
    }

    func hmacHex(_ message: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Body for POST /api/interaction/<request_id>. `ts` must serialize as a
    /// bare JSON integer — the server rejects floats and booleans.
    func answerBody(provider: String, requestID: String, viewSHA256: String,
                    verdict: Verdict, ts: Int) -> Data {
        let msg = "v2|\(provider)|\(requestID)|\(viewSHA256)|\(verdict.rawValue)|\(ts)"
        let sig = hmacHex(msg)
        let body = "{\"provider\":\"\(provider)\",\"view_sha256\":\"\(viewSHA256)\","
            + "\"verdict\":\"\(verdict.rawValue)\",\"ts\":\(ts),\"hmac\":\"\(sig)\"}"
        return Data(body.utf8)
    }

    /// Body for POST /api/panic — the v1 primitive over "panic|deny|<ts>".
    func panicBody(ts: Int) -> Data {
        let sig = hmacHex("panic|deny|\(ts)")
        return Data("{\"ts\":\(ts),\"hmac\":\"\(sig)\"}".utf8)
    }
}

func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}
