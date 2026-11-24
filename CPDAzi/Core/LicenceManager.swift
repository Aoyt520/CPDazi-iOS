import Foundation
import UIKit
import CryptoKit

/// 对应 Android com.z6.fusion.License（状态持久化 + 失败锁）
final class LicenceManager {
    static let shared = LicenceManager()

    private let keyCode = "code"
    private let keyActivated = "activated_at"
    private let keyFails = "fail_count"
    private let keyLock = "lock_until"
    private let maxFails = 10
    private let lockMs: TimeInterval = 300

    private var d: UserDefaults { .standard }

    /// 与 Android License.deviceCode() 等价：identifierForVendor → SHA256 前 4 字节 → %06d
    /// iOS 无 android_id，用 IDFV 作替代源（同一 vendor 下稳定）
    static func deviceCode() -> String {
        let base: String
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            base = idfv
        } else {
            base = "\(UIDevice.current.model)/\(UIDevice.current.systemVersion)/z6"
        }
        let digest = SHA256Digest.digest(Data(base.utf8))
        guard digest.count >= 4 else { return "000000" }
        let v: UInt32 = (UInt32(digest[0]) << 24) | (UInt32(digest[1]) << 16) | (UInt32(digest[2]) << 8) | UInt32(digest[3])
        return String(format: "%06d", Int(v % 1_000_000))
    }

    static func legacyDeviceCode() -> String {
        let base: String
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            base = idfv
        } else {
            base = "\(UIDevice.current.model)/\(UIDevice.current.systemVersion)/z6"
        }
        let digest = SHA256Digest.digest(Data(base.utf8))
        guard digest.count >= 8 else { return "0000000000000000" }
        return digest.prefix(8).map { String(format: "%02X", $0) }.joined()
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    var savedCode: String? { d.string(forKey: keyCode) }

    var hasCode: Bool {
        guard let c = savedCode else { return false }
        return !c.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var activatedAt: String { d.string(forKey: keyActivated) ?? Self.today() }

    func check() -> LicenceCore.Result {
        let code = savedCode
        let t = Self.today()
        let norm = (code ?? "").trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        if !norm.isEmpty && !LicenceCore.isSixDigits(norm.replacingOccurrences(of: "-", with: "")) {
            return LicenceCore.verifySmart(code, dev: Self.legacyDeviceCode(), today: t, activatedAt: t)
        }
        return LicenceCore.verifySmart(code, dev: Self.deviceCode(), today: t, activatedAt: activatedAt)
    }

    func allowed(_ m: LicenceCore.Module) -> Bool { check().allows(m) }

    var failCount: Int { d.integer(forKey: keyFails) }

    var lockRemainSec: Int {
        let until = d.double(forKey: keyLock)
        let remain = until - Date().timeIntervalSince1970
        return remain > 0 ? Int(ceil(remain)) : 0
    }

    @discardableResult
    func activate(_ input: String) -> LicenceCore.Result {
        let remain = lockRemainSec
        if remain > 0 {
            return LicenceCore.fail("连续输错太多次，请 \(remain) 秒后再试")
        }
        let norm = input.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let noDash = norm.replacingOccurrences(of: "-", with: "")
        let isShort = LicenceCore.isSixDigits(noDash)
        let t = Self.today()
        let dev = isShort ? Self.deviceCode() : Self.legacyDeviceCode()
        let res = LicenceCore.verifySmart(norm, dev: dev, today: t, activatedAt: t)
        guard res.ok else {
            let fails = failCount + 1
            if fails >= maxFails {
                d.set(Date().timeIntervalSince1970 + lockMs, forKey: keyLock)
                d.set(0, forKey: keyFails)
                return LicenceCore.fail("连续输错 10 次，已锁定 5 分钟")
            }
            d.set(fails, forKey: keyFails)
            return res
        }
        d.set(isShort ? noDash : norm, forKey: keyCode)
        d.removeObject(forKey: keyFails)
        d.removeObject(forKey: keyLock)
        if isShort {
            d.set(t, forKey: keyActivated)
        } else {
            d.removeObject(forKey: keyActivated)
        }
        return res
    }

    func clear() {
        [keyCode, keyActivated, keyFails, keyLock].forEach { d.removeObject(forKey: $0) }
    }

    var summary: String {
        let r = check()
        return r.ok ? "已授权 · \(r.expText) · \(r.modText) · \(r.serial ?? "")" : "未授权 · \(r.reason)"
    }
}

enum SHA256Digest {
    static func digest(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
}
