import Foundation
import CryptoKit
import Security

/// 与 Android com.z6.fusion.LicenseCore 完全等价的授权校验
/// 长码 EPL1：RSA-SHA256 签名；短码 EPL2：HMAC-SHA256 派生的 6 位数字
enum LicenceCore {

    static let KEY_HEX = "C3DBE8588F56D901ABA5BC33776ADF42216B1345C6B7BE8E32CC3DF980414099"
    static let PREFIX = "EPL1A"
    static let SHORT_VERSION = "EPL2"
    static let VERSION = "EPL1"
    static let SHORT_SPACE: UInt32 = 1_000_000
    static let SHORT_MODS = [7, 1, 2, 4]
    static let SHORT_DURS = [0, 7, 30, 90, 180, 365, 730]

    /// X.509 SubjectPublicKeyInfo（Android 端原样存储的格式）
    static let PUBLIC_KEY_B64 = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6F0P8jXqLujdT2Bn2z0dFvW5j9DD5owboJUbOGgpiioM4nQt0v6W1jY4VzzHFv2+6OFnIN1VN4Do+UTPrVreYSj9HW3nKeORUWFvuPmjIvf9PjkezUkbl/VgxHubY3AWHOuhttrmrA5/xYIY0q/evtIaQJXiz4dPTHQC+4TkEUAE9/JEGSJ5ynU60IJF5qtJLCFEejG/lSyPsWijvdc62G+OS/ZndYyluBV8pLc/9S+UQSpJC0YPplMF8Ook0HXIJy0f62TwYpF1ZYbGfWz2Dot3oQ+Simw9u1Psuu41LINT796QH/XiZKX8k0sh6EpTm2PiLuAnBYIp2U8iLY5uTwIDAQAB"

    /// 供人工核对：模数指纹（SHA-256 of PKCS#1 DER 的前 8 字节）
    static let PUBLIC_FINGERPRINT = "423388B28E122237"

    enum Module: Int {
        case bridge = 1
        case epview = 2
        case device = 4
        case all = 7
    }

    struct Result {
        var ok: Bool = false
        var reason: String = ""
        var payload: String? = nil
        var dev: String? = nil
        var exp: String? = nil
        var mod: Int = 0
        var iat: String? = nil
        var serial: String? = nil
        var name: String? = nil
        var dur: Int = -1

        func allows(_ m: Module) -> Bool { ok && (m.rawValue & mod) != 0 }

        var expText: String { exp == "0" ? "永久" : (exp ?? "—") }

        var modText: String {
            var s: [String] = []
            if mod & 1 != 0 { s.append("融合桥") }
            if mod & 2 != 0 { s.append("EPview") }
            if mod & 4 != 0 { s.append("设备功能") }
            return s.isEmpty ? "无" : s.joined(separator: " ")
        }
    }

    static func fail(_ reason: String) -> Result {
        Result(ok: false, reason: reason, mod: 0, dur: -1)
    }

    static func isSixDigits(_ s: String?) -> Bool {
        guard let s, s.count == 6 else { return false }
        return s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: - 入口

    static func verifySmart(_ code: String?, dev: String?, today: String?, activatedAt: String?) -> Result {
        guard let code else { return fail("尚未激活") }
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        if cleaned.isEmpty { return fail("尚未激活") }
        let noDash = cleaned.replacingOccurrences(of: "-", with: "")
        if isSixDigits(noDash) {
            return verifyShort(noDash, dev: dev, today: today, activatedAt: activatedAt ?? today)
        }
        return verifyLong(cleaned, dev: dev, today: today)
    }

    // MARK: - 短码

    static func shortKey() -> [UInt8] {
        hexToBytes(KEY_HEX).map { $0 ^ 165 }
    }

    static func shortFingerprint() -> String {
        let digest = SHA256.hash(data: Data(shortKey()))
        return digest.prefix(8).map { String(format: "%02X", $0) }.joined()
    }

    private static func shortMac(_ dev: String, _ mod: Int, _ dur: Int, key: [UInt8]) -> String {
        let msg = "EPL2|\(dev)|\(mod)|\(dur)"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: SymmetricKey(data: Data(key)))
        let bytes = Array(mac)
        guard bytes.count >= 4 else { return "------" }
        let v: UInt32 = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        return String(format: "%06d", Int(v % SHORT_SPACE))
    }

    private static func shortExpiry(_ base: String, dur: Int) -> String {
        guard dur != 0 else { return "0" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        guard let d = fmt.date(from: base) else { return "19700101" }
        guard let out = Calendar(identifier: .gregorian).date(byAdding: .day, value: dur, to: d) else {
            return "19700101"
        }
        return fmt.string(from: out)
    }

    static func verifyShort(_ code: String, dev: String?, today: String?, activatedAt: String?) -> Result {
        guard isSixDigits(code) else { return fail("授权码必须是 6 位纯数字") }
        let devTrim = (dev ?? "").trimmingCharacters(in: .whitespaces)
        guard isSixDigits(devTrim) else { return fail("本机设备码异常") }
        let key = shortKey()
        for candidate in [devTrim, "*"] {
            for mod in SHORT_MODS {
                for dur in SHORT_DURS {
                    if code == shortMac(candidate, mod, dur, key: key) {
                        let exp = shortExpiry(activatedAt ?? today ?? "", dur: dur)
                        if exp != "0", let today, exp < today {
                            return fail("授权已于 \(exp) 到期")
                        }
                        return Result(ok: true,
                                      reason: "有效",
                                      payload: "EPL2|\(candidate)|\(mod)|\(dur)",
                                      dev: candidate,
                                      exp: exp,
                                      mod: mod,
                                      iat: activatedAt,
                                      serial: "6位短码",
                                      name: SHORT_VERSION,
                                      dur: dur)
                    }
                }
            }
        }
        return fail("授权码不对（6 位数字不匹配本机）")
    }

    // MARK: - 长码

    static func verifyLong(_ code: String, dev: String?, today: String?) -> Result {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard !cleaned.isEmpty else { return fail("尚未激活") }

        let chars = Array(cleaned)
        let dots = chars.enumerated().filter { $0.element == "." }.map { $0.offset }
        guard dots.count == 2 else { return fail("授权码格式不对（v7 请用 6 位数字）") }
        let d1 = dots[0], d2 = dots[1]
        guard String(chars[0..<d1]) == PREFIX else {
            return fail("授权码格式不对（v7 请用 6 位数字）")
        }
        let payloadStr = String(chars[(d1 + 1)..<d2])
        let sigStr = String(chars[(d2 + 1)...])

        guard let payload = b64Decode(payloadStr), let sig = b64Decode(sigStr) else {
            return fail("授权码里有非法字符")
        }
        guard verifySignature(payload: payload, signature: sig) else {
            return fail("签名无效（不是本工具签发的码）")
        }
        guard let body = String(data: payload, encoding: .utf8) else {
            return fail("授权码里有非法字符")
        }
        let parts = body.components(separatedBy: "|")
        guard parts.count == 7, parts[0] == VERSION else {
            return fail("授权码版本不匹配")
        }
        guard let mod = Int(parts[3]), mod >= 1, mod <= 7 else {
            return fail("模块位超出范围")
        }
        let codeDev = parts[1].uppercased()
        let myDev = (dev ?? "").uppercased().replacingOccurrences(of: "-", with: "")
        if codeDev != "*" && codeDev != myDev {
            return fail("设备码不匹配（这码不是给本机的）")
        }
        let exp = parts[2]
        if exp != "0" {
            guard exp.count == 8, exp.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                return fail("到期日损坏")
            }
            if let today, exp < today {
                return fail("授权已于 \(exp) 到期")
            }
        }
        return Result(ok: true,
                      reason: "有效",
                      payload: body,
                      dev: codeDev,
                      exp: exp,
                      mod: mod,
                      iat: parts[4],
                      serial: parts[5],
                      name: parts[6],
                      dur: -1)
    }

    // MARK: - 底层

    static func hexToBytes(_ hex: String) -> [UInt8] {
        var out = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let b = UInt8(hex[i..<j], radix: 16) { out.append(b) }
            i = j
        }
        return out
    }

    /// 与原实现相同的手写 base64 解码（容忍 - _ 替换、忽略非法字符、遇 '=' 停止）
    static func b64Decode(_ s: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var map = [Character: Int]()
        for (i, ch) in alphabet.enumerated() { map[ch] = i }
        let norm = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        var out = [UInt8]()
        var buf = 0
        var bits = 0
        for ch in norm {
            if ch == "=" { break }
            guard let v = map[ch] else { continue }
            buf = (buf << 6) | v
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buf >> bits) & 0xFF))
            }
        }
        return Data(out)
    }

    /// 从 X.509 SPKI 中取出 PKCS#1 RSAPublicKey（Security.framework 要的是后者）
    static func pkcs1FromSPKI(_ der: Data) -> Data? {
        let b = [UInt8](der)

        func readLen(_ i: inout Int) -> Int? {
            guard i < b.count else { return nil }
            var len = Int(b[i]); i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n > 0, n <= 3, i + n <= b.count else { return nil }
                len = 0
                for _ in 0..<n { len = (len << 8) | Int(b[i]); i += 1 }
            }
            return len
        }

        var i = 0
        // 外层 SEQUENCE
        guard i < b.count, b[i] == 0x30 else { return nil }
        i += 1
        guard let outerLen = readLen(&i), i + outerLen <= b.count else { return nil }
        // AlgorithmIdentifier SEQUENCE，跳过
        guard i < b.count, b[i] == 0x30 else { return nil }
        i += 1
        guard let algLen = readLen(&i) else { return nil }
        i += algLen
        // BIT STRING
        guard i < b.count, b[i] == 0x03 else { return nil }
        i += 1
        guard let bitLen = readLen(&i) else { return nil }
        guard i < b.count, b[i] == 0x00 else { return nil }   // unused bits
        i += 1
        let end = min(i + bitLen - 1, b.count)
        guard i < end else { return nil }
        // 内层必须是 SEQUENCE（PKCS#1 RSAPublicKey）
        guard b[i] == 0x30 else { return nil }
        return Data(b[i..<end])
    }

    static func verifySignature(payload: Data, signature: Data) -> Bool {
        guard let spki = Data(base64Encoded: PUBLIC_KEY_B64),
              let pkcs1 = pkcs1FromSPKI(spki) else { return false }

        var error: Unmanaged<CFError>?
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        guard let secKey = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            return false
        }
        return SecKeyVerifySignature(secKey,
                                     .rsaSignatureMessagePKCS1v15SHA256,
                                     payload as CFData,
                                     signature as CFData,
                                     &error)
    }
}
