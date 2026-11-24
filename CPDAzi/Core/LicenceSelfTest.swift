import Foundation
import CryptoKit
import Security

/// 授权算法离线自测 —— 用已知向量校验 Swift 实现与 Android 端字节级一致
enum LicenceSelfTest {

    struct Failure { let name: String; let detail: String }

    static func run() -> [Failure] {
        var fails: [Failure] = []

        func expect(_ name: String, _ cond: Bool, _ detail: String = "") {
            if !cond { fails.append(Failure(name: name, detail: detail)) }
        }

        // 1. 短码密钥派生：KEY_HEX 每字节 XOR 0xA5
        let key = LicenceCore.shortKey()
        expect("shortKey 长度", key.count == 32, "got \(key.count)")
        expect("shortKey 首字节", key[0] == 0x66, String(format: "%02X", key[0]))
        expect("shortKey 末字节", key[31] == 0x3C, String(format: "%02X", key[31]))

        // 2. 密钥指纹必须等于 APK 中硬编码的 SHORT_FINGERPRINT
        expect("shortFingerprint", LicenceCore.shortFingerprint() == "59BA5D02A3AA0437",
               LicenceCore.shortFingerprint())

        // 3. 已知测试向量（由 Python 参考实现产出，dev=123456）
        let vectors: [(dev: String, mod: Int, dur: Int, code: String)] = [
            ("123456", 7, 0, "691233"),
            ("123456", 7, 7, "979841"),
            ("123456", 7, 30, "360546"),
            ("123456", 7, 90, "994420"),
            ("123456", 7, 180, "544807"),
            ("123456", 7, 365, "712177"),
            ("123456", 7, 730, "556045"),
            ("123456", 1, 0, "673292"),
            ("123456", 2, 30, "015238"),
            ("123456", 4, 365, "600006")
        ]
        for v in vectors {
            let r = LicenceCore.verifyShort(v.code, dev: v.dev, today: "20260101", activatedAt: "20260101")
            expect("短码 \(v.code) (mod=\(v.mod) dur=\(v.dur))",
                   r.ok && r.mod == v.mod && r.dur == v.dur,
                   "ok=\(r.ok) reason=\(r.reason) mod=\(r.mod) dur=\(r.dur)")
        }

        // 4. 通配设备码 "*"
        let wild = LicenceCore.verifyShort("691233", dev: "123456", today: "20260101", activatedAt: "20260101")
        expect("短码解析设备码", wild.dev == "123456", wild.dev ?? "nil")

        // 5. 错误短码必须失败
        let bad = LicenceCore.verifyShort("000000", dev: "123456", today: "20260101", activatedAt: "20260101")
        expect("错误短码被拒", !bad.ok, bad.reason)

        // 6. 到期判定
        let expired = LicenceCore.verifyShort("979841", dev: "123456", today: "20270101", activatedAt: "20250101")
        expect("过期短码被拒", !expired.ok && expired.reason.contains("到期"), expired.reason)

        // 7. 长码：PREFIX 与格式判定
        let malformed = LicenceCore.verifyLong("EPL1A.xxx", dev: "ABC", today: "20260101")
        expect("长码格式错误被拒", !malformed.ok, malformed.reason)

        // 8. RSA 公钥必须能从 SPKI 剥出 PKCS#1 并装入 Security
        if let spki = Data(base64Encoded: LicenceCore.PUBLIC_KEY_B64),
           let pkcs1 = LicenceCore.pkcs1FromSPKI(spki) {
            expect("PKCS#1 长度", pkcs1.count == 270, "got \(pkcs1.count)")
            var err: Unmanaged<CFError>?
            let attrs: [CFString: Any] = [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic
            ]
            let k = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &err)
            expect("公钥可装入 Security", k != nil, "\(String(describing: err))")
            if let k { expect("公钥位长", SecKeyGetBlockSize(k) == 256, "\(SecKeyGetBlockSize(k))") }
        } else {
            fails.append(Failure(name: "公钥解析", detail: "SPKI/PKCS#1 解析失败"))
        }

        // 9. 手写 base64 解码正确性
        let raw = Data("EPL1|ABC|0|7|20260101|SN01|name".utf8)
        let enc = raw.base64EncodedString()
        let dec = LicenceCore.b64Decode(enc)
        expect("base64 往返", dec == raw, "roundtrip failed")

        // 10. 签名验证器：空数据不得通过
        expect("空签名被拒", !LicenceCore.verifySignature(payload: Data(), signature: Data()))

        return fails
    }
}
