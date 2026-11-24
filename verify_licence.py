#!/usr/bin/env python3
"""
LicenceCore.swift 的逐行参考实现，用于验证 Swift 移植的算法正确性。
逻辑必须与 CPDAzi/Core/LicenceCore.swift 一一对应。
"""
import base64
import hashlib
import hmac
import subprocess
import datetime

KEY_HEX = "C3DBE8588F56D901ABA5BC33776ADF42216B1345C6B7BE8E32CC3DF980414099"
PREFIX = "EPL1A"
VERSION = "EPL1"
SHORT_VERSION = "EPL2"
SHORT_SPACE = 1_000_000
SHORT_MODS = [7, 1, 2, 4]
SHORT_DURS = [0, 7, 30, 90, 180, 365, 730]

B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
B64MAP = {c: i for i, c in enumerate(B64)}


def hex_to_bytes(h):
    return bytes(int(h[i:i+2], 16) for i in range(0, len(h), 2))


def short_key():
    return bytes(b ^ 165 for b in hex_to_bytes(KEY_HEX))


def short_fingerprint():
    return hashlib.sha256(short_key()).hexdigest()[:16].upper()


def b64_decode(s):
    """与 Swift b64Decode 等价：手写、忽略非法字符、遇 = 停止"""
    norm = s.strip().replace("-", "+").replace("_", "/")
    out = bytearray()
    buf = 0
    bits = 0
    for ch in norm:
        if ch == "=":
            break
        v = B64MAP.get(ch)
        if v is None:
            continue
        buf = (buf << 6) | v
        bits += 6
        if bits >= 8:
            bits -= 8
            out.append((buf >> bits) & 0xFF)
    return bytes(out)


def is_six_digits(s):
    return s is not None and len(s) == 6 and s.isdigit() and s.isascii()


def short_mac(dev, mod, dur):
    msg = f"EPL2|{dev}|{mod}|{dur}".encode()
    mac = hmac.new(short_key(), msg, hashlib.sha256).digest()
    v = (mac[0] << 24) | (mac[1] << 16) | (mac[2] << 8) | mac[3]
    return "%06d" % (v % SHORT_SPACE)


def short_expiry(base, dur):
    if dur == 0:
        return "0"
    try:
        d = datetime.datetime.strptime(base, "%Y%m%d")
    except Exception:
        return "19700101"
    out = d + datetime.timedelta(days=dur)
    return out.strftime("%Y%m%d")


class Result:
    def __init__(self, ok=False, reason="", payload=None, dev=None, exp=None,
                 mod=0, iat=None, serial=None, name=None, dur=-1):
        self.ok = ok
        self.reason = reason
        self.payload = payload
        self.dev = dev
        self.exp = exp
        self.mod = mod
        self.iat = iat
        self.serial = serial
        self.name = name
        self.dur = dur

    def allows(self, m):
        return self.ok and (m & self.mod) != 0

    def __repr__(self):
        return f"Result(ok={self.ok}, reason={self.reason!r}, mod={self.mod}, dur={self.dur}, exp={self.exp})"


def fail(reason):
    return Result(ok=False, reason=reason)


def clean(code):
    return code.strip().replace(" ", "").replace("\r", "").replace("\n", "")


def verify_smart(code, dev, today, activated_at):
    if code is None:
        return fail("尚未激活")
    c = clean(code)
    if not c:
        return fail("尚未激活")
    nodash = c.replace("-", "")
    if is_six_digits(nodash):
        return verify_short(nodash, dev, today, activated_at or today)
    return verify_long(c, dev, today)


def verify_short(code, dev, today, activated_at):
    if not is_six_digits(code):
        return fail("授权码必须是 6 位纯数字")
    dev_trim = (dev or "").strip()
    if not is_six_digits(dev_trim):
        return fail("本机设备码异常")
    for cand in [dev_trim, "*"]:
        for mod in SHORT_MODS:
            for dur in SHORT_DURS:
                if code == short_mac(cand, mod, dur):
                    exp = short_expiry(activated_at or today or "", dur)
                    if exp != "0" and today and exp < today:
                        return fail(f"授权已于 {exp} 到期")
                    return Result(ok=True, reason="有效",
                                  payload=f"EPL2|{cand}|{mod}|{dur}",
                                  dev=cand, exp=exp, mod=mod, iat=activated_at,
                                  serial="6位短码", name=SHORT_VERSION, dur=dur)
    return fail("授权码不对（6 位数字不匹配本机）")


def pkcs1_from_spki(der):
    b = der
    def read_len(i):
        if i >= len(b):
            return None, i
        ln = b[i]; i += 1
        if ln & 0x80:
            n = ln & 0x7F
            if n == 0 or n > 3 or i + n > len(b):
                return None, i
            ln = 0
            for _ in range(n):
                ln = (ln << 8) | b[i]; i += 1
        return ln, i

    i = 0
    if b[i] != 0x30: return None
    i += 1
    outer, i = read_len(i)
    if outer is None or i + outer > len(b): return None
    if b[i] != 0x30: return None
    i += 1
    alg, i = read_len(i)
    i += alg
    if i >= len(b) or b[i] != 0x03: return None
    i += 1
    bit, i = read_len(i)
    if b[i] != 0x00: return None
    i += 1
    end = min(i + bit - 1, len(b))
    if i >= end: return None
    if b[i] != 0x30: return None
    return b[i:end]


PUBLIC_KEY_B64 = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6F0P8jXqLujdT2Bn2z0dFvW5j9DD5owboJUbOGgpiioM4nQt0v6W1jY4VzzHFv2+6OFnIN1VN4Do+UTPrVreYSj9HW3nKeORUWFvuPmjIvf9PjkezUkbl/VgxHubY3AWHOuhttrmrA5/xYIY0q/evtIaQJXiz4dPTHQC+4TkEUAE9/JEGSJ5ynU60IJF5qtJLCFEejG/lSyPsWijvdc62G+OS/ZndYyluBV8pLc/9S+UQSpJC0YPplMF8Ook0HXIJy0f62TwYpF1ZYbGfWz2Dot3oQ+Simw9u1Psuu41LINT796QH/XiZKX8k0sh6EpTm2PiLuAnBYIp2U8iLY5uTwIDAQAB"


def verify_long(code, dev, today):
    c = clean(code)
    if not c:
        return fail("尚未激活")
    idxs = [i for i, ch in enumerate(c) if ch == "."]
    if len(idxs) != 2:
        return fail("授权码格式不对（v7 请用 6 位数字）")
    d1, d2 = idxs[0], idxs[1]
    if c[:d1] != PREFIX:
        return fail("授权码格式不对（v7 请用 6 位数字）")
    payload = b64_decode(c[d1+1:d2])
    sig = b64_decode(c[d2+1:])
    if not payload or not sig:
        return fail("授权码里有非法字符")
    # 用 openssl 代替 Swift Security 做签名校验（同为 PKCS#1 v1.5 SHA-256）
    import tempfile, os
    with tempfile.TemporaryDirectory() as td:
        pf = os.path.join(td, "p.bin"); sf = os.path.join(td, "s.bin")
        kf = os.path.join(td, "k.der")
        open(pf, "wb").write(payload)
        open(sf, "wb").write(sig)
        open(kf, "wb").write(pkcs1_from_spki(base64.b64decode(PUBLIC_KEY_B64)))
        r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", kf,
                            "-signature", sf, pf], capture_output=True, text=True)
        if "Verified OK" not in r.stdout:
            return fail("签名无效（不是本工具签发的码）")
    body = payload.decode("utf-8", "replace")
    parts = body.split("|")
    if len(parts) != 7 or parts[0] != VERSION:
        return fail("授权码版本不匹配")
    try:
        mod = int(parts[3])
    except ValueError:
        return fail("模块位超出范围")
    if mod < 1 or mod > 7:
        return fail("模块位超出范围")
    code_dev = parts[1].upper()
    my_dev = (dev or "").upper().replace("-", "")
    if code_dev != "*" and code_dev != my_dev:
        return fail("设备码不匹配（这码不是给本机的）")
    exp = parts[2]
    if exp != "0":
        if len(exp) != 8 or not exp.isdigit():
            return fail("到期日损坏")
        if today and exp < today:
            return fail(f"授权已于 {exp} 到期")
    return Result(ok=True, reason="有效", payload=body, dev=code_dev, exp=exp,
                  mod=mod, iat=parts[4], serial=parts[5], name=parts[6], dur=-1)


def run_tests():
    ok = 0; bad = 0
    def check(name, cond, detail=""):
        nonlocal ok, bad
        if cond:
            ok += 1
            print(f"  PASS  {name}")
        else:
            bad += 1
            print(f"  FAIL  {name}  {detail}")

    print("[1] 短码密钥派生")
    k = short_key()
    check("长度 32", len(k) == 32, len(k))
    check("首字节 0x66", k[0] == 0x66, hex(k[0]))
    check("末字节 0x3C", k[31] == 0x3C, hex(k[31]))

    print("[2] 密钥指纹 == APK SHORT_FINGERPRINT")
    check("59BA5D02A3AA0437", short_fingerprint() == "59BA5D02A3AA0437", short_fingerprint())

    print("[3] 短码测试向量 dev=123456")
    vectors = [("691233", 7, 0), ("979841", 7, 7), ("360546", 7, 30),
               ("994420", 7, 90), ("544807", 7, 180), ("712177", 7, 365),
               ("556045", 7, 730), ("673292", 1, 0), ("015238", 2, 30),
               ("600006", 4, 365)]
    for code, mod, dur in vectors:
        check(f"{code} → mod={mod} dur={dur}",
              short_mac("123456", mod, dur) == code,
              short_mac("123456", mod, dur))

    print("[4] 短码校验（正确/错误/过期）")
    r = verify_short("691233", "123456", "20260101", "20260101")
    check("正确码通过", r.ok and r.mod == 7 and r.dur == 0, r)
    r = verify_short("000000", "123456", "20260101", "20260101")
    check("错误码被拒", not r.ok, r)
    r = verify_short("979841", "123456", "20270101", "20250101")
    check("过期码被拒", not r.ok and "到期" in r.reason, r)
    r = verify_short("691233", "999999", "20260101", "20260101")
    check("别机码被拒", not r.ok, r)

    print("[5] 长码格式")
    check("EPL1A.xxx 被拒", not verify_long("EPL1A.xxx", "ABC", "20260101").ok)
    check("前缀错误被拒", not verify_long("EPL1B.a.b", "ABC", "20260101").ok)

    print("[6] base64 往返")
    raw = "EPL1|ABC|0|7|20260101|SN01|name".encode()
    enc = base64.b64encode(raw).decode()
    check("往返一致", b64_decode(enc) == raw)
    check("urlsafe 容忍", b64_decode(enc.replace("+", "-").replace("/", "_").rstrip("=")) == raw)

    print("[7] SPKI → PKCS#1")
    spki = base64.b64decode(PUBLIC_KEY_B64)
    p1 = pkcs1_from_spki(spki)
    check("长度 270", p1 is not None and len(p1) == 270, len(p1) if p1 else None)
    check("以 SEQUENCE 开头", p1 is not None and p1[0] == 0x30)

    print("[8] 长码端到端（自签密钥，验证解析链路而非生产签名）")
    # 用临时密钥对签一个 payload，验证 b64/切分/字段解析
    import tempfile, os
    with tempfile.TemporaryDirectory() as td:
        priv = os.path.join(td, "k.pem")
        subprocess.run(["openssl", "genrsa", "-out", priv, "2048"],
                       capture_output=True)
        payload = b"EPL1|ABC123|0|7|20260101|SN0001|test"
        pf = os.path.join(td, "p.bin"); sf = os.path.join(td, "s.bin")
        open(pf, "wb").write(payload)
        subprocess.run(["openssl", "dgst", "-sha256", "-sign", priv,
                        "-out", sf, pf], capture_output=True)
        sig = open(sf, "rb").read()
        b64 = lambda x: base64.b64encode(x).decode().rstrip("=")
        code = f"EPL1A.{b64(payload)}.{b64(sig)}"
        # 用生产公钥验签必然失败，这正是期望：证明签名校验真的在生效
        r = verify_long(code, "ABC123", "20260101")
        check("非生产签名被拒", not r.ok and "签名" in r.reason, r)

    print(f"\n结果：{ok} 通过 / {bad} 失败")
    return bad == 0


if __name__ == "__main__":
    import sys
    sys.exit(0 if run_tests() else 1)
