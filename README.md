# CP搭子 iOS 移植版

腾讯融合 CP搭子一体版（`com.tencent.wecarnavi` 9.11.0.159）融合层的原生 iOS 重写。

## 这个工程是什么

原 APK 是 Android 车机专属应用。Android 的 dex / .so / 资源与 iOS 的 Mach-O / UIKit
不存在运行时可转换性，因此没有「APK 转 IPA」这种操作。本工程把其中**唯一与平台无关**
的部分——`com.z6.fusion` 融合层（classes9.dex，27 个类 5693 行）——按字节级语义重写为
Swift，输出一个可编译、可自签的原生 iOS 工程。

原 APK 中其余 180MB 是腾讯地图车机版本体（腾讯地图 SDK、TTS、Bugly、Tinker、微信 SDK、
BYD/NIO/BMW 车厂 HAL 适配），依赖 Android 专有 API，不在移植范围。iOS 上的导航数据
需要另行接入高德 iOS SDK 的 `AMapNaviKit`，本工程已用 `NavDataSource` 协议留出接口。

## 目录

```
CPDazi.xcodeproj/           Xcode 工程
CPDAzi/
  CPDAziApp.swift           @main 入口 + TabView
  Info.plist                ATS 允许本地网络 / 本地网络用途说明
  Core/
    FusionConfig.swift      配置持久化（与 Android FusionPrefs 键名一致）
    FusionProtocol.swift    协议帧构造（字段名逐字节对齐）
    UDPSender.swift         UDP 发送器（7706 / 7707 / 7795）
    DeviceClient.swift      :7000 HTTP 客户端（params_bulk / param_set / heartbeat）
    DeviceDiscovery.swift   网段扫描发现设备
    LicenceCore.swift       授权算法（EPL1 RSA / EPL2 HMAC）
    LicenceManager.swift    授权状态与失败锁
    LicenceSelfTest.swift   算法自测（可在调试页跑）
    NavSource.swift         导航数据源协议
    FusionBridge.swift      500ms 主循环，导航下发 + 心跳 + 变道辅助
    EpFetcher.swift         :7002 MJPEG 拉流
  Views/
    StatusView.swift        状态与链路诊断
    LicenceView.swift       授权页
    DeviceView.swift        手动控制面板
    EPViewScreen.swift      画面页
    SettingsView.swift      设置与设备发现
verify_licence.py           算法的 Python 参考实现 + 25 项测试
.github/workflows/…         macOS runner 出未签名 IPA
```

## 协议对照表（逆向自 classes9.dex）

| 通道 | 端口 | 端点 / 帧 | 原实现 |
|---|---|---|---|
| 导航下发 | UDP 7706 | nav JSON（500ms） | TcBridge.sendNav |
| 手动指令 | UDP 7706 | `carrotCmd` / `carrotArg` | FusionBridge.sendCommand |
| 目的地点 | UDP 7706 | `goalPosX/Y` + `szGoalName` | DeviceActivity.sendGoal |
| 心跳 | UDP 7795 | `{"z6Hb":1}` | TcBridge.sendHb |
| 诊断镜像 | UDP 7706/7707 | `z6Lane` / `z6Flag` / `z6Raw` | TcBridge.emit*Diag |
| 参数读 | HTTP 7000 | `GET /api/params_bulk?names=` | DeviceHttp.readParams |
| 参数写 | HTTP 7000 | `POST /api/param_set` | DeviceHttp.setParam |
| 心跳查询 | HTTP 7000 | `GET /api/heartbeat_status` | DeviceHttp.heartbeat |
| 运行时 | HTTP 7000 | `GET /api/live_runtime?force=1` | DeviceHttp.liveRuntime |
| 视频流 | HTTP 7002 | `GET /f?t=<ms>` 单帧 JPEG | EpFetcher.fetch |
| 存活探测 | HTTP 7002 | `GET /stat` 含 `seq=`/`fps=`/`out=` | DeviceScanner.probe |

转向类型映射：`2,4→12` `3,5→13` `6→16` `7→19` `8→14` 其他 `-1`。
变道方向：`2,4,6` 为左；`3,5,7` 为右。

## 授权算法

**EPL1 长码**：`EPL1A.<b64(payload)>.<b64(sig)>`
- payload = `EPL1|设备码|到期日|模块位|签发时间|序列号|名称`（7 段）
- 签名 = SHA-256 with RSA PKCS#1 v1.5
- 公钥：X.509 SPKI，`LicenceCore.pkcs1FromSPKI` 剥出 PKCS#1 后交给 Security.framework
- 模块位：1 融合桥 / 2 EPview / 4 设备功能

**EPL2 短码**：6 位数字
- `HMAC-SHA256(key, "EPL2|设备码|模块位|天数")` 前 4 字节 mod 1e6
- key = `KEY_HEX` 每字节 XOR 0xA5 → 指纹应为 `59BA5D02A3AA0437`
- 天数 ∈ {0 永久, 7, 30, 90, 180, 365, 730}

设备码：Android 用 `android_id` 的 SHA-256 前 4 字节取模；iOS 用 `identifierForVendor` 作替代源。
两端设备码算法不同，因此**同一个短码在两平台不通用**，需按平台分别签发。

## 构建

本机 macOS + Xcode 15+：

```bash
xcodebuild -project CPDazi.xcodeproj -scheme CPDazi \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

没有 Mac 时用仓库里的 GitHub Actions（`macos-14` runner），推上去自动出未签名 IPA。

## 自签安装

产物是**未签名** IPA，需自己用以下任一工具重签后安装：
- Sideloadly（Windows/macOS，需 Apple ID）
- AltStore / SideStore
- TrollStore（支持的系统版本）
- 自备证书 + `codesign` + `ldid`

重签命令（自备 mobileprovision 时）：

```bash
unzip CPDAzi.ipa -d tmp
codesign -f -s "iPhone Distribution: YOUR TEAM" \
  --entitlements ent.plist tmp/Payload/CPDAzi.app
zip -qry resigned.ipa tmp/Payload
```

## 自测

```bash
python3 verify_licence.py     # 25 项算法一致性测试
```

Swift 侧另有一份等价实现 `LicenceSelfTest.swift`，可在真机/模拟器上跑。

## 已知限制

1. **导航数据源**：Android 端反射高德 SDK 内部类 `qa.y2` 拿引导数据，iOS 无此路径。
   需自行接 `AMapNaviKit` 的 `AMapNaviDriveManager` 回调，填进 `NavDataSource`。
   未接入前可用 `ManualNavSource` 手动构造数据验证整条 UDP 链路。
2. **悬浮窗**：iOS 无跨应用悬浮窗，EPview 改为应用内可缩放画面。
3. **设备发现**：iOS 无法读 ARP 表，按本机网段 + `:7002/stat` 探测；需授权本地网络。
4. **唤醒词 / TTS 问候**：原实现用离线 PCM + 车机 TTS 通道，本移植未包含。
5. **设备码跨平台不通用**（见上）。
