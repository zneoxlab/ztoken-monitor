# Android 4×2 桌面小组件 Design QA

## 对照目标

- source visual truth: `/Users/xiaozhou/.codex/generated_images/019fe76c-3440-7c62-a62c-921558798f35/exec-ccd2d5da-a868-4db0-94bc-9226a00cc32f.png`
- implementation screenshot: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-ready-revised.png`
- component crop: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-ready-crop.png`
- full-view comparison: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-design-comparison.png`
- enlarged-text evidence: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-font-130.png`
- disconnected-state evidence: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-disconnected-fixed.png`

## 视口与归一化

- Android 视口：1080 × 2424 px，420 dpi，约 411 × 923 dp；Pixel Launcher 上的实际 4×2 区域为 979 × 534 px。
- 源图：1777 × 887 px；源图中的概念卡片比 Android 启动器实际 4×2 单元更宽。
- 实现全屏截图：1080 × 2424 px；实现组件裁切：979 × 534 px。
- 对照图中源图保持原始长宽比缩放为 979 × 489 px，实现裁切保持原生 979 × 534 px。没有强行拉伸为相同长宽比，避免把启动器尺寸约束误判为设计偏差。
- 这是原生 `RemoteViews`，没有 CSS 尺寸或浏览器 `deviceScaleFactor`。
- 对照状态：星空蓝主题；内容来自明确标注“测试数据”的隔离视觉快照。验证结束后运行环境已恢复真实未连接状态。

## 必查表面

- 字体与排版：系统中文无衬线字体、粗细层级和数字等宽表现清楚；主数字、额度值、辅助文本没有截断。130% 系统字体下仍无重叠、裁切或错误换行。
- 间距与布局：左侧月用量、中央分隔线、右侧两条额度保持参考图的信息层级。Android 实际 4×2 比概念图更高，因此右侧两行采用更宽松的垂直间距，这是启动器单元约束下的适配。
- 色彩与令牌：深蓝渐变、冷灰辅助文字、蓝色费用、琥珀预警和细描边与视觉方向一致。Codex 47% 的进度条使用琥珀色，遵循已确认的 20–49% 预警规则；参考图中的蓝条不作为状态语义来源。
- 图片与资源：Codex、Cursor 使用项目真实厂商 PNG 资源，没有 emoji、文字替代、手绘 SVG 或占位图。图标清晰，无裁切、压缩块或透明边缘光晕。
- 文案与内容：生产态显示“本月”；QA 快照额外显示“· 测试数据”，防止把合成数据伪装为真实数据。额度行补充周期标签和“重置”前缀，使真实多窗口额度可区分。
- 图标与交互：左侧用量区域打开首页，右侧额度区域打开额度页；未登录时由现有鉴权逻辑跳转登录页。未连接态点击也能打开配套 App。
- 可访问性：文本对比度、可点击区域、130% 字体缩放均通过实机视口检查。小组件的两大区域本身就是大触控目标。

## 全视图与局部证据

全视图使用 `android-widget-design-comparison.png`，把源图和实现放在同一张对照图中检查构图、层级、字体、颜色、图标和两条额度。所有重要文字、图标与进度条在 1998 × 584 px 对照图中均可直接辨认，因此不需要额外局部放大图；实现的 979 × 534 px 原生裁切已充当可读的组件级局部证据。

## Findings

没有剩余可执行的 P0、P1 或 P2 问题。

可接受差异：

- Android 启动器真实 4×2 比概念图更高，右侧行距随之增加；信息结构和视觉重心未改变。
- 实现增加额度周期标签，并让预警进度条和数值统一使用琥珀色，属于已确认的产品语义，不是无意设计漂移。

P3 后续验证项：尚未在小米、OPPO、vivo、三星的实体启动器上逐台截图；当前通过的是 Android 16 Pixel Launcher、默认字体和 130% 字体。

## 比较历史

1. 初次真实桌面验证发现 P0：小组件显示 “Can't load widget”。Android 日志定位到 `RemoteViews` 不允许加载基础 `android.view.View`。将装饰性 View 替换为受支持的 TextView 后，未连接态成功显示，证据为 `android-widget-disconnected-fixed.png`。
2. 首次数据态发现 P2：左侧 `Tokens` 在水平排列中显示成 `Tok`。将单位改为主数字下方的独立一行后，证据为 `android-widget-ready-revised.png`。
3. 修订后把源图和实现放入同一对照图复查；未发现新的 P0/P1/P2。130% 字体截图也无截断。最终 Android 日志中 `AppWidgetHostView` 和 `AndroidRuntime` 均无错误。

## 实现检查清单

- [x] 源图与实现同图对照
- [x] 默认字体真实桌面截图
- [x] 130% 字体缩放
- [x] 未连接态
- [x] 数据态与两条额度
- [x] 左右区域点击打开配套 App
- [x] Android 远程布局/崩溃日志检查
- [x] 隔离测试数据在运行环境中清理并恢复真实状态

final result: passed

---

# 2026-08-10 字体层级修订

## 最新对照目标

- source visual truth: `/Users/xiaozhou/.codex/generated_images/019fe76c-3440-7c62-a62c-921558798f35/exec-ccd2d5da-a868-4db0-94bc-9226a00cc32f.png`
- user-reported before capture: `/var/folders/b5/0rb524mj7l9f_90cwg53n0340000gn/T/codex-clipboard-31fa56fc-4a3d-49d3-81c6-8eac87bf5f43.png`
- latest implementation screenshot: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-typography-v3-ready.png`
- latest implementation crop: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-typography-v3-crop.png`
- 130% font evidence: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-typography-v3-font-130.png`
- combined comparison: `/Users/xiaozhou/hub/vibecoding/ztoken-monitor/app/screenshots/android-widget-typography-comparison.png`

## 视口与归一化

- 设计稿：1777 × 887 px；卡片裁切约 1635 × 664 px。
- 用户反馈截图：700 × 378 px；卡片裁切约 640 × 298 px。
- Pixel Launcher 实现：1080 × 2424 px、420 dpi、约 411 × 923 dp；4×2 组件裁切为 980 × 535 px。
- 同图对照把三个卡片都保持各自长宽比缩放到 300 px 高。没有强制拉伸；因此可判断相对字号层级，但不把不同启动器的 4×2 长宽比差异当成设计缺陷。
- 状态：浅色瓷白主题、1.14B Token、OpenCode/Codex 临界额度。新版截图使用隔离的合成 QA 数据，并在同图对照中明确标注；验证后模拟器已恢复真实未连接状态。

## 必查表面

- 字体与排版：主数字由等宽粗体改为 Android 系统无衬线粗体，并按字符长度在 42/39/35/31sp 间自适应；标题、Tokens、费用、账户名、额度值、重置时间和刷新状态全部建立了更接近设计稿的字号阶梯。1.14B 在默认和 130% 字体下均完整显示。
- 间距与节奏：增加标题到主数字的间距、Tokens 到费用的间距、左右内容内边距和分隔线到额度内容的呼吸空间；进度条从 3dp 增至 4dp。左侧不再像一组松散的小标签。
- 色彩与令牌：继续使用既有瓷白主题和语义色；0%/3% 使用临界红色，费用保持品牌蓝。没有为修字体额外改变主题。
- 图片与资源：OpenCode、Codex 继续使用项目真实 PNG 图标，没有替代图、emoji、手绘 SVG 或压缩伪影。
- 文案与内容：保留“本月”“Tokens”“剩余”“重置”“已过期”等真实产品语义；测试数据未混入生产状态。
- 响应式与可访问性：默认字体和 130% 字体均无重叠、截断或错误换行。用户反馈设备和 Pixel Launcher 的 4×2 比例不同，布局通过权重和单行省略保持稳定。

## Findings

没有剩余可执行的 P0、P1 或 P2 问题。

P3 验证项：Pixel Launcher 的 4×2 比用户截图更高，因此同高归一化后右侧文字看起来相对更小；代码中的右侧字号已从 11/10/8/7.5sp 分别提升到 12/11/9/9sp。最终观感仍建议在用户当前启动器安装后再看一张同设备截图。

## 比较历史

1. 用户截图发现 P1：左侧主数字相对设计稿明显偏小，等宽字体带来工具面板感；标题、单位、费用与右侧辅助文字字号差距不足。
2. 第一轮把主数字提高到 48sp 后，在 Pixel Launcher 的 42% 左栏发生 P2 截断，显示成 `1.1…`。
3. 第二轮改为按字符长度自适应，五字符值使用 42sp；`1.14B` 在默认及 130% 字体下完整显示。右侧长名称 OpenCode、额度值和重置时间也保持单行。
4. 最新同图对照确认主数字重新成为第一视觉焦点，标题、单位、费用和账户信息形成清晰阶梯；Android 日志无 `AppWidgetHostView` 或应用崩溃错误。

## 实现检查清单

- [x] 设计稿、用户反馈截图、新版实现同图对照
- [x] 系统无衬线字体替换等宽显示字体
- [x] 长度自适应主数字字号
- [x] 左右两侧完整字号层级重排
- [x] 默认字体真实桌面截图
- [x] 130% 字体无截断验证
- [x] 完整 Flutter 测试与静态分析
- [x] Android 远程布局和崩溃日志检查
- [x] 合成 QA 数据清理

final result: passed
