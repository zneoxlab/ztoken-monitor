# English

## What's changed

<!-- app-update-notes:en:start -->
### Added
- **New AI tool support:** Reasonix, DeepSeek Harness (dsh), and Hunyuan are now tracked — 30+ tools in all. Reasonix adds a native session view with prompt / completion / reasoning / cache breakdown, provider request counts, and Reasonix-reported cost (shown on this device only).
- **Fixed period ranges:** Home now offers Week, Last 7 days, and Last 30 days ranges derived from History, and you can set a default range in Settings. The floating bubble accepts `week` / `last7` / `last30` too.
- **Hub build status:** the Sync settings show whether your Hub (Node or Cloudflare Worker) is current, has an update available, or was deployed from a newer version.
- **Unclassified usage:** device breakdowns and chart tooltips now list tokens that can't be attributed to a specific client/model as "Unclassified" instead of silently dropping or inflating them.
- **Tray editor:** choose how cost is shown (abbreviated / full with 0–4 decimals) and which usage feeds the tray (all tools, or recently active tools).
- **OpenCode local-DB fallback:** an opt-in "Predict from local DB" toggle uses the local OpenCode database when web limits aren't available (off by default).

### Improved
- **OpenCode limits aggregation rewritten:** the same account is now merged across devices via its web account key and aliases, with windows reconciled by source (web over local) — multi-device sync no longer duplicates or drops balances.
- **Codex and Z.ai limits:** Codex's monthly quota is now a proper "Monthly" billing window (its 5-minute window as `session`); Z.ai GLM plans using `CREDIT_LIMIT` are recognized instead of dropped.
- **Custom pricing accepts 0** as an explicit "free" price.
- **Packaging:** the Windows installer is now a wizard-style, per-user install with a selectable directory; macOS minimum system version raised to 12.0; bundled tokscale updated.
- **Faster cold start:** the dashboard primes from the last complete scan while a fresh one runs.

### Fixed
- **macOS "Install update"** could stall or re-trigger after a failed quit-and-install; a guard now prevents re-entrancy and recovers cleanly.
- **OpenCode** windows from a different workspace could attach to the wrong account — now resolved.
- **Reasonix / DSH usage edge cases:** synthetic sessions no longer leak into aggregates or uploads, and multi-frame zstd session files decode correctly.
- **Subscriptions** stay bound to an account when it's recognized under a different key.
- **Credential store** now rejects oversized files instead of reading them into memory.
<!-- app-update-notes:en:end -->

## Download

- **macOS Apple Silicon** — [ZT-Monitor-__VERSION__-arm64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-arm64.dmg)
- **macOS Intel** — [ZT-Monitor-__VERSION__-x64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-x64.dmg)
- **Windows Installer** — [ZT-Monitor-Setup-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-Setup-__VERSION__.exe) (recommended)
- **Windows Portable** — [ZT-Monitor-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.exe) (no install required)
- **Linux x64** — [ZT-Monitor-__VERSION__.AppImage](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.AppImage)

<details>
<summary><strong>First launch and other notes</strong></summary>

### First launch

**macOS:** the app is **not code-signed or notarized**. On first launch, right-click the app and choose **Open** → **Open anyway** to bypass Gatekeeper, then drag ZT Monitor to Applications.

**Windows:** the executables are **unsigned** — SmartScreen may show "Windows protected your PC". Click **More info** → **Run anyway**.

**Linux:** mark the AppImage executable, then run it:

```bash
chmod +x ZT-Monitor-*.AppImage
./ZT-Monitor-*.AppImage
```

### Other notes

Other platforms are not pre-built — run from source per the [README](https://github.com/zneoxlab/ztoken-monitor#readme). The macOS `.zip` is the same app repackaged; ignore it unless you specifically need it.

### tokscale dependency

Tokscale is bundled with this app. See **Settings → Tokscale** for the exact version
and the option to download a newer version directly from npm. Tokscale is MIT,
open-source: https://github.com/junhoyeo/tokscale

</details>

---

# 中文

## 更新内容

<!-- app-update-notes:zh:start -->
### 新增
- **新增 AI 工具支持：** 新增追踪 Reasonix、DeepSeek Harness（dsh）与 Hunyuan，工具总数达 30+。Reasonix 提供原生会话视图，包含 prompt/completion/reasoning/cache 拆分、Provider 请求次数与 Reasonix 自报费用（仅本机可见）。
- **固定周期范围：** Home 顶部新增「本周 / 最近 7 天 / 最近 30 天」三个由历史记录派生的范围，并可在设置中选择默认统计范围；悬浮球 URL 也支持 `week`/`last7`/`last30`。
- **Hub 构建状态：** 同步设置页会显示所连接的 Hub（Node 或 Cloudflare Worker）是否为最新、是否有更新可用、或已由更新版本部署。
- **未分类用量：** 设备明细与图表 tooltip 现在会把无法归入具体客户端/模型的 token 单独列为「未分类」，不再静默丢失或虚增。
- **托盘编辑器：** 可自定义成本的显示格式（缩写 / 完整数字 + 0-4 位小数），以及托盘用量来源（全部工具 / 最近有活动的工具）。
- **OpenCode 本地 DB 后备：** 新增「使用本地 DB 预测」开关（默认关闭），在 Web 额度不可用时以本地数据库兜底。

### 改进
- **OpenCode 额度聚合重写：** 同一账号现在按 Web 账户 key 与别名跨设备合并，窗口按来源（Web 优先于本地）归并，多设备同步不再重复或丢失余额。
- **Codex 与 Z.ai 额度：** Codex 月度配额现在归类为「Monthly」计费窗口（5 分钟窗口归类为 session）；Z.ai GLM 套餐的 `CREDIT_LIMIT` 配额不再丢失。
- **自定义定价支持 0：** 0 被视为显式「免费」，不再当作未设置。
- **打包改进：** Windows 安装器改为向导式（per-user、可选安装目录）；macOS 最低系统版本提升到 12.0；内置 tokscale 更新。
- **冷启动提速：** 面板会用上一次完整扫描的结果预填首屏，等待新一轮扫描完成。

### 修复
- **macOS「立即安装更新」** 偶发卡死或失败后重复触发，现已加入防重入守卫并干净恢复。
- **OpenCode** 不同工作区的窗口可能被挂到错误账号，已修复。
- **Reasonix / DSH 用量边界：** 合成会话不再泄漏进汇总与上传；DSH 多帧 zstd 会话文件正确解码。
- **订阅绑定：** 账号以不同 key 被识别时，订阅仍会跟随正确的账户。
- **凭证存储：** 现在会拒绝超大文件，避免异常文件撑爆内存。
<!-- app-update-notes:zh:end -->

## 下载

- **macOS Apple Silicon** — [ZT-Monitor-__VERSION__-arm64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-arm64.dmg)
- **macOS Intel** — [ZT-Monitor-__VERSION__-x64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-x64.dmg)
- **Windows 安装版** — [ZT-Monitor-Setup-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-Setup-__VERSION__.exe)（推荐）
- **Windows 便携版** — [ZT-Monitor-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.exe)（免安装）
- **Linux x64** — [ZT-Monitor-__VERSION__.AppImage](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.AppImage)

<details>
<summary><strong>首次启动与其他说明</strong></summary>

### 首次启动

**macOS：** 应用**未做代码签名与公证**。首次打开时请右键点击应用，选择「打开」→「打开」，绕过 Gatekeeper 后再把 ZT Monitor 拖到 Applications。

**Windows：** 可执行文件**未签名**——首次运行时 SmartScreen 可能提示「Windows 已保护你的电脑」。点击「更多信息」→「仍要运行」。

**Linux：** 先给 AppImage 执行权限，然后运行：

```bash
chmod +x ZT-Monitor-*.AppImage
./ZT-Monitor-*.AppImage
```

### 其他说明

其他平台暂不提供预构建版本，请参考 [README](https://github.com/zneoxlab/ztoken-monitor#readme) 从源码运行。macOS 的 `.zip` 只是同一个 app 的重新打包版本，除非你明确需要，否则可以忽略。

### tokscale 依赖

Tokscale 已随应用内置。你可以在 **设置 → Tokscale** 查看确切版本，
也可以直接从 npm 下载更新版本。Tokscale 是 MIT 开源项目：
https://github.com/junhoyeo/tokscale

</details>

---

**Full Changelog:** [releases](https://github.com/zneoxlab/ztoken-monitor/releases)

<details>
<summary>繁體中文 · 한국어 · 日本語</summary>

<details>
<summary><strong>繁體中文</strong></summary>

## 繁體中文

## 更新內容

<!-- app-update-notes:zh-TW:start -->
### 新增
- **新增 AI 工具支援：** 新增追蹤 Reasonix、DeepSeek Harness（dsh）與 Hunyuan，工具總數達 30+。Reasonix 提供原生會話檢視，包含 prompt/completion/reasoning/cache 拆分、Provider 請求次數與 Reasonix 自報費用（僅本機可見）。
- **固定週期範圍：** Home 頂部新增「本週 / 最近 7 天 / 最近 30 天」三個由歷史記錄派生的範圍，並可在設定中選擇預設統計範圍；懸浮球 URL 也支援 `week`/`last7`/`last30`。
- **Hub 建置狀態：** 同步設定頁會顯示所連接的 Hub（Node 或 Cloudflare Worker）是否為最新、是否有更新可用、或已由更新版本部署。
- **未分類用量：** 裝置明細與圖表 tooltip 現在會把無法歸入具體用戶端/模型的 token 單獨列為「未分類」，不再靜默丟失或虛增。
- **托盤編輯器：** 可自訂成本的顯示格式（縮寫 / 完整數字 + 0-4 位小數），以及托盤用量來源（全部工具 / 最近有活動的工具）。
- **OpenCode 本地 DB 後備：** 新增「使用本地 DB 預測」開關（預設關閉），在 Web 額度不可用時以本地資料庫兜底。

### 改進
- **OpenCode 額度聚合重寫：** 同一帳號現在按 Web 帳戶 key 與別名跨裝置合併，視窗按來源（Web 優先於本地）歸併，多裝置同步不再重複或丟失餘額。
- **Codex 與 Z.ai 額度：** Codex 月度配額現在歸類為「Monthly」計費視窗（5 分鐘視窗歸類為 session）；Z.ai GLM 套餐的 `CREDIT_LIMIT` 配額不再丟失。
- **自訂定價支援 0：** 0 被視為顯式「免費」，不再當作未設定。
- **打包改進：** Windows 安裝器改為精靈式（per-user、可選安裝目錄）；macOS 最低系統版本提升到 12.0；內建 tokscale 更新。
- **冷啟動提速：** 面板會用上一次完整掃描的結果預填首屏，等待新一輪掃描完成。

### 修復
- **macOS「立即安裝更新」** 偶發卡死或失敗後重複觸發，現已加入防重入守衛並乾淨恢復。
- **OpenCode** 不同工作區的視窗可能被掛到錯誤帳號，已修復。
- **Reasonix / DSH 用量邊界：** 合成會話不再洩漏進彙總與上傳；DSH 多幀 zstd 會話檔案正確解碼。
- **訂閱綁定：** 帳號以不同 key 被識別時，訂閱仍會跟隨正確的帳戶。
- **憑證儲存：** 現在會拒絕超大檔案，避免異常檔案撐爆記憶體。
<!-- app-update-notes:zh-TW:end -->

## 下載

- **macOS Apple Silicon** — [ZT-Monitor-__VERSION__-arm64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-arm64.dmg)
- **macOS Intel** — [ZT-Monitor-__VERSION__-x64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-x64.dmg)
- **Windows 安裝版** — [ZT-Monitor-Setup-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-Setup-__VERSION__.exe)（推薦）
- **Windows 便攜版** — [ZT-Monitor-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.exe)（免安裝）
- **Linux x64** — [ZT-Monitor-__VERSION__.AppImage](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.AppImage)

</details>

<details>
<summary><strong>한국어</strong></summary>

## 한국어

## 업데이트 내용

<!-- app-update-notes:ko:start -->
### 추가
- **새 AI 도구 지원:** Reasonix, DeepSeek Harness(dsh), Hunyuan 추적을 추가해 총 30+ 도구를 지원합니다. Reasonix는 prompt/completion/reasoning/cache 구분, Provider 요청 횟수, Reasonix 보고 비용이 포함된 네이티브 세션 보기를 제공합니다(이 기기에서만 표시).
- **고정 기간 범위:** Home 상단에 「이번 주 / 최근 7일 / 최근 30일」 세 가지 기간을 추가했습니다. 기록(History)에서 파생되며 설정에서 기본 통계 범위를 선택할 수 있습니다. 플로팅 버블 URL도 `week`/`last7`/`last30`을 지원합니다.
- **Hub 빌드 상태:** 동기화 설정 페이지에서 연결된 Hub(Node 또는 Cloudflare Worker)가 최신인지, 업데이트가 있는지, 더 새 버전으로 배포되었는지 표시합니다.
- **미분류 사용량:** 기기 상세 및 차트 툴팁에서 특정 클라이언트/모델로 분류할 수 없는 토큰을 「미분류」로 따로 표시해 더 이상 조용히 누락되거나 부풀려지지 않습니다.
- **트레이 편집기:** 비용 표시 형식(약어 / 전체 숫자 + 소수점 0-4자리)과 트레이 사용량 출처(전체 도구 / 최근 활동한 도구)를 지정할 수 있습니다.
- **OpenCode 로컬 DB 대체:** 「로컬 DB로 예측」 스위치를 추가했습니다(기본 꺼짐). Web 한도를 사용할 수 없을 때 로컬 데이터베이스로 대체합니다.

### 개선
- **OpenCode 한도 집계 재작성:** 동일 계정을 웹 계정 키와 별칭으로 기기 간 병합하고, 창을 출처별로 조정합니다(웹 > 로컬). 다중 기기 동기화에서 잔액이 더 이상 중복되거나 누락되지 않습니다.
- **Codex 및 Z.ai 한도:** Codex 월간 할당량을 「Monthly」 청구 창으로 분류합니다(5분 창은 session). Z.ai GLM 요금제의 `CREDIT_LIMIT` 할당량이 더 이상 유실되지 않습니다.
- **사용자 정의 가격 0 지원:** 0을 명시적 「무료」로 간주합니다.
- **패키징:** Windows 설치 프로그램이 설치 디렉터리를 선택할 수 있는 마법사 방식(per-user)으로 변경되었습니다. macOS 최소 시스템 버전이 12.0으로 올라갔으며 내장 tokscale이 업데이트되었습니다.
- **콜드 스타트 가속:** 새 스캔이 도는 동안 마지막 전체 스캔 결과로 첫 화면을 미리 채웁니다.

### 수정
- **macOS「지금 업데이트 설치」** 가 종종 멈추거나 실패 후 다시 트리거되던 문제를 방지하는 가드를 추가하고 깨끗하게 복구합니다.
- **OpenCode** 다른 작업 공간의 창이 잘못된 계정에 붙는 문제를 수정했습니다.
- **Reasonix / DSH 사용량 경계:** 합성 세션이 집계 및 업로드에 더 이상 유출되지 않으며, DSH 다중 프레임 zstd 세션 파일이 올바르게 디코딩됩니다.
- **구독 바인딩:** 계정이 다른 키로 인식되어도 구독이 올바른 계정을 따릅니다.
- **자격 증명 저장소:** 비정상적으로 큰 파일을 거부하여 메모리 과부하를 방지합니다.
<!-- app-update-notes:ko:end -->

## 다운로드

- **macOS Apple Silicon** — [ZT-Monitor-__VERSION__-arm64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-arm64.dmg)
- **macOS Intel** — [ZT-Monitor-__VERSION__-x64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-x64.dmg)
- **Windows 설치 버전** — [ZT-Monitor-Setup-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-Setup-__VERSION__.exe) (권장)
- **Windows 포터블 버전** — [ZT-Monitor-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.exe) (설치 필요 없음)
- **Linux x64** — [ZT-Monitor-__VERSION__.AppImage](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.AppImage)

</details>

<details>
<summary><strong>日本語</strong></summary>

## 日本語

## 更新内容

<!-- app-update-notes:ja:start -->
### 追加
- **新しい AI ツールのサポート：** Reasonix、DeepSeek Harness（dsh）、Hunyuan の追跡を追加し、合計 30+ ツールに対応しました。Reasonix は prompt/completion/reasoning/cache の内訳、プロバイダー要求回数、Reasonix 報告コストを含むネイティブセッション表示を提供します（このデバイスでのみ表示）。
- **固定期間レンジ：** Home 上部に「今週 / 直近7日 / 直近30日」の3つの期間を追加しました。履歴から導出され、設定で既定の統計レンジを選べます。フローティングバブルの URL も `week`/`last7`/`last30` に対応します。
- **Hub ビルドステータス：** 同期設定ページで、接続中の Hub（Node または Cloudflare Worker）が最新か、更新があるか、より新しいバージョンでデプロイされているかを表示します。
- **未分類の使用量：** デバイス内訳とチャートのツールチップで、特定のクライアント/モデルに帰属できないトークンを「未分類」として別に表示し、黙って欠落したり水増しされたりしなくなりました。
- **トレイエディター：** コストの表示形式（省略 / 完全な数値 + 小数0〜4桁）と、トレイに表示する使用量のソース（全ツール / 最近アクティブなツール）を指定できます。
- **OpenCode ローカル DB フォールバック：** 「ローカル DB で予測」スイッチを追加しました（既定オフ）。Web の上限が使えないときにローカルデータベースで代替します。

### 改善
- **OpenCode 上限の集約を書き直し：** 同じアカウントを Web アカウントキーとエイリアスでデバイス間マージし、ウィンドウをソース別（Web > ローカル）に調整します。複数デバイス同期で残高が重複したり失われたりしません。
- **Codex と Z.ai の上限：** Codex の月次割当を「Monthly」請求ウィンドウとして分類します（5分ウィンドウは session）。Z.ai GLM プランの `CREDIT_LIMIT` 割当が失われなくなりました。
- **カスタム価格で 0 をサポート：** 0 を明示的な「無料」として扱います。
- **パッケージング：** Windows インストーラーがインストール先を選べるウィザード方式（per-user）に変わりました。macOS の最低システムバージョンが 12.0 に引き上げられ、同梱の tokscale も更新されました。
- **コールドスタートを高速化：** 新しいスキャン中に、前回の完全スキャン結果で最初の画面を先に表示します。

### 修正
- **macOS「今すぐ更新をインストール」** が失敗後に止まったり再トリガーされたりする問題を防ぐガードを追加し、きれいに復帰します。
- **OpenCode** 別のワークスペースのウィンドウが誤ったアカウントに付く問題を修正しました。
- **Reasonix / DSH の使用量エッジケース：** 合成セッションが集計やアップロードに漏れなくなり、DSH の複数フレーム zstd セッションファイルが正しくデコードされます。
- **サブスクリプションのバインド：** アカウントが別のキーで認識されても、正しいアカウントに追従します。
- **資格情報ストア：** 異常に大きいファイルを拒否し、メモリの過負荷を防ぎます。
<!-- app-update-notes:ja:end -->

## ダウンロード

- **macOS Apple Silicon** — [ZT-Monitor-__VERSION__-arm64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-arm64.dmg)
- **macOS Intel** — [ZT-Monitor-__VERSION__-x64.dmg](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__-x64.dmg)
- **Windows インストーラー** — [ZT-Monitor-Setup-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-Setup-__VERSION__.exe)（推奨）
- **Windows ポータブル版** — [ZT-Monitor-__VERSION__.exe](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.exe)（インストール不要）
- **Linux x64** — [ZT-Monitor-__VERSION__.AppImage](https://github.com/zneoxlab/ztoken-monitor/releases/download/v__VERSION__/ZT-Monitor-__VERSION__.AppImage)

</details>

</details>
