# Look4Sat Android → iOS 移植交付报告

> 源 APK：`com.rtbishop.look4sat_289`（未混淆、未加壳；classes.dex 的 string_ids_size=0 系 R8 剥离字符串表所致，非反调试壳）
> 权威迁移基准：GitHub `rt-bishop/Look4Sat`（GPL-3.0，Kotlin 多模块；`core:domain` 纯算法模块为 1:1 移植来源）
> 部署目标：**iOS 16**（用户锁定；iOS 27 向后兼容可安装）
> 合规：无 DRM 绕过；所有状态标签如实标注；**本环境（Windows + Swift 6.4.2 工具链）无 Xcode / Apple 签名链，未构建任何 .ipa**。

---

## 1. 可行性分级与完成情况

| 级别 | 内容 | 状态 |
|------|------|------|
| **A 类** | 纯域算法 + 模型 + 可运行单测 | ✅ 已完成（SGP4/SDP4、CelestialComputer、TLE、PassPredictor、CAT 协议编码器 + 单测）；**已在 Windows 上编译通过 + 18/18 单测全绿 + CLI 端到端验证** |
| **B 类** | UI + 系统 API 重实现 | ✅ 骨架完成（SwiftUI 6 Tab、CoreLocation、MapKit、雷达、TLE 网络、日历/通知、设置持久化）；**未在本环境编译**（Windows 无 SwiftUI/MapKit SDK，须 macOS/Xcode 验证） |
| **C 类** | 蓝牙电台 CAT + SSTV/音频 | ⚠️ 框架完成（CoreBluetooth 链路 + FT-817/IC-705 字节协议 1:1 移植，单测全绿），**未对实物验证**；SSTV 音频未移植 |
| **D 类** | Xcode 构建 / 签名 / 安装 | ⛔ 平台受限（需 macOS + Apple 开发者证书；见 BUILD.md / XCODE_STEPS.md） |

---

## 2. 目录结构

```
ios_Look4Sat/
├── Package.swift                 SPM manifest (iOS 16 / macOS 12)
├── Look4Sat/Look4Sat/            Look4SatCore 算法库（纯 Swift，无 iOS 依赖）
│   ├── OrbitalMath.swift         全局常量/换算（thetaGJD、deltaET、eciToGeodetic…）
│   ├── OrbitalData.swift         TLE 轨道数据 + epoch + isDeepSpace + hasDecayed
│   ├── GeoPos.swift              观测点（Codable）
│   ├── OrbitalPos.swift          位置/多普勒/rangeCircle + OrbitalPass
│   ├── OrbitalObject.swift       开放基类（SGP4/SDP4 公共路径、converge、calcObs…）
│   ├── NearEarthObject.swift     SGP4 v2.2.5（近地，周期 < 225 min）
│   ├── DeepSpaceObject.swift     SDP4（深空；DeepSpaceCalculator 日月长周期+共振项）
│   ├── CelestialComputer.swift   日/月/RA-Dec/可见性/升落/星等/多普勒/观测角
│   ├── TLE.swift                 TLE 解析 + 校验和（0 起列位）
│   ├── TLESource.swift           CelesTrak TLE 网络 + 本地缓存（URLSession）
│   ├── SatItem.swift / SatRadio  卫星行 / 收发器（SatNOGS 模式）
│   ├── Settings.swift            设置模型（OtherSettings/PassesSettings/RC…）
│   ├── PassPredictor.swift       过站预测（二分法 refineEdge）
│   ├── Ft817CatProtocol.swift    FT-817 BCD CAT（1:1 Kotlin）
│   └── IcomCivProtocol.swift    IC-705 CI-V CAT（1:1 Kotlin）
├── app/                           SwiftUI 应用壳（B 类 + C 类框架）
│   ├── Look4SatApp.swift         @main + AppModel + 6 Tab + 设置
│   ├── MapFeatureView.swift      MapKit 地图 + 离线瓦片 stub（iOS 16 API）
│   ├── RadarFeatureView.swift    Canvas 雷达 + 扫掠 + 过站倒计时
│   ├── StatusFeatureView.swift   实时状态读数
│   ├── Services.swift            EventKit 日历 + 本地通知
│   └── RadioLink.swift          CoreBluetooth 电台链路（C 类，未实物验证）
├── look4sat-cli/main.swift       CLI 验证驱动（SGP4/SDP4/TLE/日月）
├── Look4SatTests/
│   ├── OrbitalMathTests.swift    算法层 XCTest
│   └── RadioProtocolTests.swift  CAT 协议 BCD/CI-V 往返测试（无硬件依赖）
├── Info.plist                    权限描述 + 后台模式
├── BUILD.md                      macOS 构建/签名/安装 + Android→iOS API 映射表
└── XCODE_STEPS.md                手动 Xcode 工程引导
```

---

## 3. Android → iOS API 映射（对应关系）

| Android 模块 / API | iOS 替换 | 所在文件 |
|--------------------|----------|----------|
| `core:domain` PREDICT v2.2.5 SGP4/SDP4 | 1:1 移植（`NearEarthObject`/`DeepSpaceObject`/`DeepSpaceCalculator`） | OrbitalObject / NearEarthObject / DeepSpaceObject.swift |
| TLE 解析 + 校验和 | `TLE.parse` + `verifyChecksum`（0 起列位，padding69） | TLE.swift |
| CelestialComputer（日月/升落/星等） | 同名 enum（`thetaGJD` 替代 `thetaGJ1_1`） | CelestialComputer.swift |
| 过站预测 | `PassPredictor`（Brent/二分 refineEdge） | PassPredictor.swift |
| `SharedPreferences` | `UserDefaults` + Codable JSON（`AppModel.load/persist`） | Look4SatApp.swift |
| `RemoteSource`（TLE 网络） | `TLESource.refresh/loadCached`（URLSession + `tle_cache.txt`） | TLESource.swift |
| osmdroid 离线瓦片地图 | MapKit `Map(coordinateRegion:annotationItems:)` + MKTileOverlay stub | MapFeatureView.swift |
| Android 定位设置 + 自动定位 | CoreLocation `CLLocationManager`（AppModel 委托） | Look4SatApp.swift |
| CalendarProvider / EventReminder | EventKit `EKEventStore.addPasses` | Services.swift |
| NotificationManagerService | `UNUserNotificationCenter.schedule` | Services.swift |
| BluetoothGatt（FT817/IC705 CAT） | CoreBluetooth `RadioLink` + 1:1 `Ft817CatProtocol`/`IcomCivProtocol` | RadioLink.swift / *.swift |
| AudioRecord/AudioTrack（SSTV） | **未移植**（需 AVAudioEngine） | — |
| Kotlin 协程 / StateFlow | Swift async/await + `@Published`/`@StateObject` | 全 app |
| Compose Navigation3 6 Tab | SwiftUI `TabView(selection:)` + 各 FeatureView | Look4SatApp.swift |
| Room / SQLite SatelliteRepo | 本地 TLE 文本缓存 + 解析（无数据库） | TLESource.swift |

---

## 4. 算法正确性依据（A 类）

- **SGP4/SDP4**：直接移植 PREDICT v2.2.5（Whitelان/Griffin 变体），含日月长周期项 `dpsec/dpper`、地电位共振项 `d2201…d5433`、`thetaG(epoch)`、TLE 历元换算、`converge()` 10 次 EPSILON 收敛、`calcObs` 象限修正（`atan(-topE/topS)+PI`）。
- **深空判定**：`isDeepSpace = (orbitalPeriod ≥ 225 min)` → SDP4 路径；近地 → SGP4。`DeepSpaceValueObject` 为 `final class`（引用语义，与 Kotlin data class by-ref 行为一致）。
- **校验**（已在 Windows Swift 6.4.2 工具链 `swift test` 18/18 全绿）：
  - `julianDateOfYear(2000) = 2451544.5`（J2000，Meeus 公式；PREDICT C 代码的 C-整数截断语义 1:1）✅
  - `epochToDaynum(19000.0) = 14246.0`（1 Jan 2019 00:00 UTC = 自 31 Dec 1979 第 14246 天）✅
  - 多普勒：`f·(299792.458 − rangeRate_km_s)/299792.458`（无 ×1000）✅
  - 日升日落：`riseTimeMillis = sunrise`（已修正顺序）✅
  - TLE 列位（0 起，半开区间）：incl 8..15、raan 16..23、ecc 25..32、argper 34..41、meanan 43..50、**meanmo 52..62（10 字符，含小数点；修正前的旧实现误用 53..62 导致 ISS 周期误读为 262 min、被错判为深空）** ✅
  - BCD 往返：FT-817 `145500000 Hz → [0x14,0x55,0x00,0x00]`；IC-705 `145500000 Hz → [0x00,0x00,0x50,0x45,0x01]` ✅
  - 负 Int8 常量（0xFE/0xA4/0x88 等）全部经 `Int8(bitPattern:)` 构造，避免 Swift 字面量溢出；CI-V 帧构造用 `UInt8(bitPattern:)` 做符号扩展（Swift 的 `UInt8(negative Int8)` 是陷阱崩溃，已修）✅
- **单测**：`OrbitalMathTests`（历元/日月/TLE/过站/常量）+ `RadioProtocolTests`（BCD/CI-V 编码、帧解析、ACK、波段码）— **已在 Windows `swift test` 上实际运行 18/18 全绿**；macOS/Xcode 上同样可直接运行。
- **Windows 编译**：`pwsh build-windows.ps1 [build|test|cli]`（MSVC 14.44 + Swift 6.4.2；关键修复是 `SDKROOT` 环境变量，而非 junction）；CLI 端到端输出：ISS SGP4 过站（London，3 passes，maxEl 65°）、GEO-1 SDP4（az 89.99° el −13.15° dist 43159 km alt 35790 km）、Sun az 74.17° el −30.35° Dec −14.41°、Moon az 134.11° el 53.73°、日出日落时间。

---

## 5. 已知问题 / 未实现项（如实列出）

1. ~~未在任何平台编译过~~ → **已在本 Windows 环境（Swift 6.4.2 工具链）编译通过 + 18/18 单测全绿 + CLI 验证**。B 类 UI（SwiftUI/MapKit/CoreBluetooth/EventKit，`app/*.swift`）仍**未在本环境编译**（Windows 无这些 SDK）；必须在 macOS 上 `swift build`/Xcode 验证。
2. **SSTV / 音频链路未移植** — Android `AudioRecord/AudioTrack` 无 1:1 CoreAudio 封装，需 `AVAudioEngine` 重写（C 类，超出本次范围）。
3. **离线瓦片下载为 stub** — MapKit 不暴露瓦片 provider；当前仅 UI 占位，未接入 OSM 瓦片源（`OfflineTilePicker` 标注"not wired to a provider yet"）。
4. **电台协议未对实物验证** — `Ft817CatProtocol`/`IcomCivProtocol` 为 Kotlin 字节级 1:1 移植（含 BCD/CI-V 帧/ACK/波段码，11 项单测全绿），但未在真实 FT-817/IC-705 上联调；`RadioLink` 的 BLE 服务/特征 UUID 仍为占位（需按实际电台 SPP 服务调整）。
5. **IC-705 SPLIT 双 VFO 逻辑** — `buildSetWorkingFreqCommand` / `buildSetUnselectedVfoFreqCommand` 已移植，但 PTT 联动时"选中/未选中 VFO 切换"的完整状态机未在本框架中实现（属 C 类未验证部分）。
6. **数据库层简化** — Android Room/SQLite（SatEntry/SatRadio 表）以"本地 TLE 文本缓存 + 解析"替代，未建 SQLite；若需离线电台库，需补 `GRDB`/`Core Data`。
7. **后台定位 / 过站提醒的后台保活** — `UIBackgroundModes = [fetch, location]` 已声明，但后台过站跟踪的精确唤醒策略（BGTaskScheduler）未实现。
8. **过站预测器边缘 clamping** — `PassPredictor` 二分法在 30 s 扫描步长下对 1 ms 级伪过站会保留一条 spurious pass（cosmetic，不影响 maxEl 正确性；未修）。
9. **Windows XCTest 缺少 `XCTAssertLess`** — Swift 6.4.2 Windows 工具链的 XCTest 实现不含 `XCTAssertLess`；测试已改用等价的 `XCTAssertGreaterThanOrEqual` + 显式区间 helper（`XCTAssertLesserPassDuration`），macOS 上无此限制。

---

## 6. 在 macOS / CI 上完成 D 类（构建/签名/安装）

**Windows 端零 Mac 方案（已落地）**：

1. 打开 `.github/workflows/ios-build.yml`（GitHub Actions 免费 macOS 14 runner）与
   `project.yml`（xcodegen 规格，headless 生成 Xcode 工程）。
2. 把 `ios_Look4Sat` 推到 GitHub 公开仓库 → 点一次 "Run workflow"
   （或自动触发 push）→ 等 5–10 分钟 → 下载 `look4sat-ios` artifact 里的
   `Look4Sat.ipa`（**未签名 / 手动签名无效，专门给 AltStore 重签用**）。
3. Windows 本机装 [AltStore](https://altstore.io) → 登录免费 Apple ID →
   拖入 `Look4Sat.ipa` → AltStore 本机用你的 Apple ID 重签 → USB 连 iPhone
   安装。详见 `ALTSTORE_GUIDE.md`。
4. 7 天到期 → AltStore → "Update" 一键续期（或 `altserverclient installapp`）。

**完整 D 类（Ad Hoc / 付费）**：按 `BUILD.md` 第 5 节在 macOS/Xcode 上
Archive → 导出 .ipa；或付费 $99 后把 workflow 的 `CODE_SIGNING_ALLOWED`
改成 `YES` + 付费 teamID 出 Ad Hoc 签名 .ipa（7 天限制解除）。

**macOS 本地快速验证**：
1. 打开 `BUILD.md`（macOS 前置 + 命令）与 `XCODE_STEPS.md`（手动 Xcode 工程引导）。
2. `swift build && swift test && swift run look4sat-cli` — A 类算法层已在 Windows
   验证；macOS 上可直接复跑确认平台无关。
3. Xcode 新建 iOS App（iOS 16）→ 挂本地 SPM 包 → 导入 `app/*.swift` + `Info.plist` 键
   → 自动签名。
4. Archive → Development/Ad Hoc 分发 .ipa → 已注册 UDID 的非越狱 iPhone 安装。

> 本报告不声称任何 .ipa 已构建或可安装；B 类 UI 未经 macOS 编译验证
>（GitHub Actions 首次运行前需确认 xcodegen 生成的工程结构正确）。
