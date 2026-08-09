# ZT Monitor 打包构建指南

本文档汇总**桌面客户端（Electron Widget）**与**移动端 App（Flutter）**在各平台上的打包命令与产物路径。  
**仅供本地参考，未纳入版本控制提交策略**（按需自行保存或提交）。

---

## 环境要求（通用）

| 组件 | 版本 / 说明 |
|------|-------------|
| **Node.js** | `>= 22.13.0`（桌面端、`npm run verify`、SaaS Hub） |
| **npm** | 随 Node 安装；仓库根目录执行 `npm install` |
| **Flutter（移动 App）** | Dart `>= 3.9`；标准通道 **3.35+**（Android / iOS / Web） |
| **Flutter（鸿蒙）** | OpenHarmony SIG 分支 **3.41+**（与标准 Flutter **分开安装**，勿混用 `pub get`） |
| **Xcode** | iOS 打包必需（仅 macOS） |
| **Android SDK** | Android 打包；需 JDK 17 |
| **DevEco Studio** | 鸿蒙 `.hap` 打包（可选，亦可用命令行 `hvigorw`） |

> **交叉编译限制**：`electron-builder` **不能**在 Windows 上打 macOS `.dmg`，也不能在 macOS 上打 Windows `.exe`。必须在**目标操作系统**上执行对应的 `dist:*` 命令。

---

## 一、桌面客户端（Electron · ZT Monitor Widget）

代码目录：**仓库根目录**（`package.json` 的 `main` 指向 `src/electron/main.js`）。

### 1.1 安装依赖

```bash
cd /path/to/ztoken-monitor
npm install
```

### 1.2 开发运行（不打包）

```bash
npm start          # 或 npm run widget / npm run dev
```

### 1.3 打包前检查（推荐）

```bash
npm run verify     # ESLint + 全量 node:test
```

### 1.4 各平台打包命令

所有安装包产物默认输出到 **`dist/`**。

| 平台 | 命令 | 产物（示例） |
|------|------|----------------|
| **macOS Apple Silicon (arm64)** | `npm run dist:mac` | `dist/ZT-Monitor-<version>-arm64.dmg`、`dist/ZT-Monitor-<version>-arm64-mac.zip` |
| **macOS Intel (x64)** | `npm run dist:mac:x64` | `dist/ZT-Monitor-<version>-x64.dmg`、对应 `.zip` |
| **Windows x64 安装包 + 便携版** | `npm run dist:win` | `dist/ZT-Monitor-Setup-<version>.exe`（NSIS）、`dist/ZT-Monitor-<version>.exe`（portable） |
| **Windows 仅目录（调试）** | `npm run dist:win:dir` | `dist/win-unpacked/` |
| **Windows 二次打包（已有 unpacked）** | `npm run dist:win:prepackaged` | 基于 `dist/win-unpacked` 再打 NSIS/portable |
| **Linux x64 AppImage** | `npm run dist:linux` | `dist/ZT-Monitor-<version>.AppImage` |
| **本机快速测包（无安装程序）** | `npm run pack` | `dist/mac-arm64/` 或 `dist/linux-unpacked/` 等未封装目录 |

### 1.5 macOS 签名说明

- `package.json` 中 `mac.forceCodeSigning: false`，本地未配置证书时仍可打出未签名包。
- **对外发布**建议在 Mac 上配置 **Developer ID Application**，并在 `electron-builder` 中启用签名与公证（当前仓库未写死签名身份，需自行在 CI 或本机配置）。

### 1.6 发布产物名校验（可选）

```bash
npm run verify:release-artifact-names
```

---

## 二、移动端 App（Flutter · `app/`）

代码目录：**`app/`**  
应用 ID：

- Android：`com.zneox.ztoken.ztoken_monitor`
- iOS：`com.zneox.ztoken.ztokenMonitor`
- 版本号：`app/pubspec.yaml` 的 `version:`（当前正式版 `1.0.0+2003`）

图标等资源：主仓库 `assets/tools-icon/`、`assets/icons/` 需与 `app/assets/icons/` 保持同步（见 `app-prototype/GOAL.md`）。

### 2.1 Android / iOS / Web — 拉依赖

**必须使用标准 Flutter SDK**（不要用鸿蒙版 Flutter）：

```bash
cd app
./scripts/pub_get_mobile.sh
# 等价于：flutter pub get
```

### 2.2 Android

**环境**：Android SDK、JDK 17；首次需 `flutter doctor` 通过 Android  toolchain。

```bash
cd app

# 官网分发版（允许从官网检查并下载签名 APK）
flutter run --release --flavor website

# 官网 Release APK（侧载 / 官网更新）
flutter build apk --release --flavor website
# 产物：app/build/app/outputs/flutter-apk/app-website-release.apk

# Google Play / 应用商店版（不声明 APK 安装权限）
flutter build appbundle --release --flavor store
# 产物：app/build/app/outputs/bundle/storeRelease/app-store-release.aab
```

商店版默认不传入官网直装策略地址，由应用商店负责版本更新；即使误配置了直装策略，商店渠道也不会下载或安装 APK。
官网更新策略地址 `https://zt.zneox.com/app-update.json` 已直接内置在 App，Android 和鸿蒙构建都不需要额外传入环境变量。

**签名**：Release 构建从被 Git 忽略的 `android/key.properties` 读取长期签名路径，字段参考 `android/key.properties.example`。签名口令使用项目外的独立文件，密钥库和口令文件必须一起备份。官网 APK 的每个后续版本必须保持同一 application ID 和签名证书。

**网络权限**：Release 需在 `android/app/src/main/AndroidManifest.xml` 声明 `INTERNET`（debug/profile 清单不能替代 main）。

### 2.3 iOS

**环境**：仅 **macOS**；安装 Xcode、CocoaPods；Apple 开发者账号（真机 / 上架）。

```bash
cd app
flutter pub get

# 模拟器 / 真机调试
flutter run --release

# Archive / IPA（需配置签名与 Provisioning Profile）
flutter build ipa --release
# 产物：app/build/ios/ipa/*.ipa

# 或只编 iOS 应用包（再由 Xcode Organizer 导出）
flutter build ios --release
# 产物：app/build/ios/iphoneos/Runner.app
```

在 Xcode 中打开：`open ios/Runner.xcworkspace`。

### 2.4 Web（可选）

```bash
cd app
flutter pub get
flutter build web --release
# 产物：app/build/web/
# 部署到静态站点；API 需 HTTPS（浏览器限制）
```

### 2.5 鸿蒙 HarmonyOS NEXT（`.hap`）

**与 Android/iOS 分开**：依赖 **OpenHarmony SIG 版 Flutter**，路径示例（按本机修改）：

```bash
export FLUTTER_OHOS=/path/to/flutter_ohos_3.41   # SIG 分支 SDK
```

**拉依赖（仅鸿蒙构建前）**：

```bash
cd app
./scripts/pub_get_ohos.sh
# 内部执行：$FLUTTER_OHOS/bin/flutter pub get
# 会写入 plugins.ohos；不要用标准 flutter pub get 覆盖
```

**打包**（任选一种方式，以本机 DevEco / SIG 文档为准）：

```bash
cd app

# 方式 A：Flutter 命令（OH Flutter SDK）
$FLUTTER_OHOS/bin/flutter build hap --release

# 方式 B：hvigor（在 ohos 子工程）
cd ohos
./hvigorw assembleHap -p product=default -p buildMode=release
```

**签名**：`app/ohos/build-profile.json5` 中的 `signingConfigs` 需替换为本机或 CI 的 `.p12` / `.p7b` / `.cer` 路径（仓库内示例路径为开发者本机，**不要**把密码提交到 Git）。

**产物位置**（典型）：`app/ohos/entry/build/default/outputs/default/entry-default-signed.hap` 或 `entry-default-unsigned.hap`（以 hvigor 输出为准）。

### 2.6 App 测试

```bash
cd app
flutter test
```

---

## 三、云端 SaaS Hub（Docker · 可选）

与桌面/App **安装包无关**；运维部署云端 Hub 时使用。

```bash
# 在仓库根目录（构建上下文必须包含 src/shared/）
docker build -t ztoken-monitor-saas-hub -f saas-hub/Dockerfile .

# 运行示例见 saas-hub/DOCKER.md
docker run -d --name saas-hub -p 8787:8787 \
  -e SAAS_HUB_JWT_SECRET=... \
  -e SAAS_HUB_MYSQL_HOST=... \
  ... \
  ztoken-monitor-saas-hub

# 首次建表
docker exec -it saas-hub node scripts/migrate.js
```

非 Docker 部署见 `saas-hub/DEPLOY.md`。

---

## 四、Headless Agent（无 GUI · 可选）

不生成安装包；服务器上直接跑 Node：

```bash
cd /path/to/ztoken-monitor
npm install
node src/agent/agent.js          # 常驻
node src/agent/agent.js --once   # 单次采集
```

---

## 五、命令速查表

### 桌面（仓库根目录）

```bash
npm install
npm start                    # 开发
npm run verify               # 检查
npm run dist:mac             # macOS arm64
npm run dist:mac:x64         # macOS x64
npm run dist:win             # Windows
npm run dist:linux           # Linux AppImage
npm run pack                 # 未封装目录
```

### 移动 App（`app/`）

```bash
cd app
./scripts/pub_get_mobile.sh  # Android / iOS / Web
flutter build apk --release
flutter build appbundle --release
flutter build ipa --release      # macOS only
flutter build web --release

./scripts/pub_get_ohos.sh      # 鸿蒙专用 pub get
$FLUTTER_OHOS/bin/flutter build hap --release
```

### SaaS Hub

```bash
docker build -t ztoken-monitor-saas-hub -f saas-hub/Dockerfile .
```

---

## 六、常见问题

1. **桌面打包报 tokscale / native 模块错误**  
   确保在目标平台执行 `npm install`；`electron-builder` 会解包 `asarUnpack` 中的 `@tokscale/*`、`koffi` 等原生依赖。

2. **Android Release 无法联网**  
   检查 `android/app/src/main/AndroidManifest.xml` 是否包含 `INTERNET`。

3. **鸿蒙与 Android 混用 `flutter pub get`**  
   鸿蒙构建前只用 `pub_get_ohos.sh`；Android 构建前只用 `pub_get_mobile.sh`，避免 `plugins.ohos` 被标准 Flutter 覆盖。

4. **iOS 签名失败**  
   在 Xcode 中设置 Team、Bundle ID，或使用 `flutter build ipa` 配合 ExportOptions.plist。

5. **版本号**  
   - 桌面：`package.json` → `version`（当前与 Electron 包名 `ZT Monitor` 一致）  
   - App：`app/pubspec.yaml` → `version: x.y.z+build`

---

*文档生成自仓库当前 `package.json`、`app/` 工程结构与 `README.md` 说明。若脚本有变更，以代码为准。*
