#  Look4Sat iOS — AltStore 侧载安装指南（Windows 端）

> 前提：你已经有一个通过 GitHub Actions 下载的 `Look4Sat.ipa`（见
> `.github/workflows/ios-build.yml` 的 artifact），以及 **AltStore for Windows**
> （https://altstore.io，免费下载）。本指南把未签名的 .ipa 用你的**免费 Apple ID**
> 在本机签名并推进非越狱 iPhone。

**License: GPL-3.0（随 App 源码）**

---

## 0. 一次性准备

| 项 | 说明 |
|----|------|
| AltStore for Windows | 从 altstore.io 下载 .exe 安装 |
| 免费 Apple ID | 任意 @icloud / @apple 个人账号（不需要 $99 付费开发者） |
| iPhone UDID 注册 | 免费 Apple ID 最多注册 **1 台设备**。首次签名时 AltStore 会自动在 Xcode 的
  免费开发者门户注册你连上 USB 的那台 iPhone；若已注册过其他设备，需先在
  <https://developer.apple.com/account> 删除再重新注册 |
| USB 线 | 支持数据传输的 Apple 原装线（"充电专用"线不行） |
| iPhone 状态 | 解锁、开发者模式已开（iOS 16 以下无需；iOS 17+ 需
  Settings → Privacy → Developer 里打开"开发者模式"） |

---

## 1. 连接并信任

1. iPhone 用数据线连到 Windows，解锁屏幕，弹窗点 **"信任此电脑"**。
2. 打开 AltStore，登录你的 Apple ID。
3. AltStore 顶部会出现你的 iPhone 设备图标。

---

## 2. 导入 .ipa

1. AltStore 主界面 → 点左上角 **"+"** 或拖拽 `Look4Sat.ipa` 进窗口。
2. AltStore 在**本机（Windows）**用你的免费 Apple ID 完成 Ad Hoc / Development
   重签（这一步不需要 Mac，AltStore 内置了签名工具链）。
   - 第一次签名需要 1–3 分钟（生成描述文件 + 注册设备）。
   - 若提示 "App not signed" / "invalid signing"，见 §5 排错。
3. 签名成功后，设备图标上出现 **Look4Sat** 图标 → 点 **"Install"**。
4. iPhone 上：设置 → 通用 → VPN 与设备管理 → 信任 "com.example.look4sat"
   （或你的 Apple ID 名）。
5. 回到桌面，点 Look4Sat 图标即可启动。

---

## 3. 7 天续期（免费 Apple ID 的核心限制）

免费 Apple ID 签名的 Development 描述文件 **有效期 7 天**。到期后 App 会闪退
（图标消失，需重装）。续期方法（Windows 上，**每月 7 天一次**，或提前 1 天做）：

1. 打开 AltStore → 选中你的 iPhone。
2. 找到 Look4Sat → 点 **"Update"**（AltStore 自动用本地缓存的已签名 App 重新签 + 推送）。
3. 等待推送完成，App 在 iPhone 上原地更新，**无需重新导入 .ipa**。

> 备选：用 [AltServer](https://github.com/lyk1a/AltServer)（Windows 版 AltStore 的
> 服务器组件，随 AltStore 安装）命令行：
> ```powershell
> altserverclient installapp --app <path-to-Look4Sat.ipa>
> ```

---

## 4. 安装失败 / 闪退排查

| 症状 | 原因 | 解决 |
|------|------|------|
| "The app failed to install" (错误 -49) | 免费 Apple ID 设备已注册满（>1 台） | developer.apple.com →
  Hardware → Devices → 删除旧 UDID → AltStore 重新签名 |
| "App not signed" | GitHub Actions 的 .ipa 是未签名 / 手动签名无效 | 确认用的是
  `build/export/Look4Sat.ipa`（AltStore 会重签，不要求源 .ipa 已签名） |
| 装好后闪退 | 7 天过期 / 描述文件被 Apple 撤销 | AltStore → Update，或重新安装 |
| iPhone 提示 "未受信任的开发者" | 首次装需信任 | Settings → General →
  Device Management → 信任 |
| AltStore 一直转圈 | 网络到 Apple 服务器慢 | 换网络 / 重试 / 用 AltServer 命令行 |

---

## 5. 验证安装成功

1. iPhone 桌面有 Look4Sat 图标。
2. 启动后能看到 6-Tab 界面（Satellites / Passes / Radar / Map / Settings / Status）。
3. 首次进 Satellites 会弹定位权限 → 允许 → 列表从 CelesTrak 拉 TLE。
4. 若看到 "No satellites" 或地图空白，检查网络连接 / 是否被 App 内设置里的
   最低仰角过滤掉了。

---

## 6. 进阶：完全脱离 AltStore 的长期方案（可选）

免费 7 天续期对长期使用偏烦。若愿意付 $99/年，可改为 **Ad Hoc / 企业证书**：

1. 注册 Apple Developer Program（付费）。
2. 在 developer.apple.com 注册 100 台设备的 Ad Hoc 描述文件。
3. GitHub Actions 里把 `CODE_SIGNING_ALLOWED=NO` 改成你的付费 teamID +
   `CODE_SIGN_STYLE=Automatic`，直接出可 Ad Hoc 安装（7 天限制解除，每年需
   手动在 Xcode 上重新提交一次）。

---

## 文件清单

```
ios_Look4Sat/
├── .github/workflows/ios-build.yml   # CI 编译打包（GitHub 免费 macOS runner）
├── project.yml                       # xcodegen 规格（headless Xcode 工程）
└── ALTSTORE_GUIDE.md                 # 本文件
```

> 本指南不改变 PORTING_REPORT 的合规立场：未在任何付费渠道分发；所有签名
> 均为个人开发 / 自用性质。
