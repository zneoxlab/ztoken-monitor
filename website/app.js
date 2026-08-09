/* global document, IntersectionObserver */

const GITHUB_REPO = 'https://github.com/zneoxlab/ztoken-monitor';
const LATEST_RELEASE_PAGE = `${GITHUB_REPO}/releases/latest`;
const LATEST_RELEASE_API = 'https://api.github.com/repos/zneoxlab/ztoken-monitor/releases/latest';
const ANDROID_APK_PATH = './downloads/ZT-Monitor-Android.apk';
const COMMUNITY_QR_PATH = './assets/contact-community.png';
const ANDROID_APK_FILENAME = 'ZT-Monitor-Android.apk';

const copy = {
  zh: {
    loading: '正在识别当前设备',
    latest: '最新稳定版',
    latestMeta: '来自 GitHub Releases',
    unknownLabel: '查看所有版本',
    unknownMeta: 'macOS · Windows · Linux',
    macLabel: '下载 macOS 版',
    macChoose: '选择 macOS 版本',
    macMeta: 'Apple Silicon / Intel',
    windowsLabel: '下载 Windows 版',
    windowsMeta: 'Windows 10+ · x64',
    linuxLabel: '下载 Linux 版',
    linuxMeta: 'AppImage · x64',
    androidLabel: '下载 Android 内测版',
    androidMeta: 'APK · 直接下载安装',
    harmonyLabel: '参与 HarmonyOS 内测',
    harmonyMeta: '扫码联系加入社群',
    desktopTitle: '电脑端 · 实时采集与分析',
    mobileTitle: '手机端 · 随时查看与预警',
    languageAria: '切换为英文'
  },
  en: {
    loading: 'Detecting this device',
    latest: 'Latest stable release',
    latestMeta: 'From GitHub Releases',
    unknownLabel: 'View all versions',
    unknownMeta: 'macOS · Windows · Linux',
    macLabel: 'Download for macOS',
    macChoose: 'Choose a macOS build',
    macMeta: 'Apple Silicon / Intel',
    windowsLabel: 'Download for Windows',
    windowsMeta: 'Windows 10+ · x64',
    linuxLabel: 'Download for Linux',
    linuxMeta: 'AppImage · x64',
    androidLabel: 'Download Android beta',
    androidMeta: 'APK · direct download',
    harmonyLabel: 'Join HarmonyOS beta',
    harmonyMeta: 'Scan to join the community',
    desktopTitle: 'Desktop · Live collection and analysis',
    mobileTitle: 'Mobile · Live overview and alerts',
    languageAria: '切换为中文'
  }
};

let language = 'zh';
let activeSlide = 0;
let carouselTimer = null;
let mobileCaptureIndex = 0;
let mobileCaptureTimer = null;
let detectedDevice = { key: 'unknown', arch: null };
let releaseAssets = null;
let keyboardNavigation = false;
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

function deterministicLevel(index) {
  const wave = (index * 17 + Math.floor(index / 7) * 11 + 5) % 23;
  if (wave > 19) return 4;
  if (wave > 15) return 3;
  if (wave > 10) return 2;
  if (wave > 6) return 1;
  return 0;
}

function buildHeatmap() {
  const heatmap = document.getElementById('miniHeatmap');
  if (!heatmap || heatmap.children.length) return;
  const fragment = document.createDocumentFragment();
  for (let index = 0; index < 126; index += 1) {
    const cell = document.createElement('i');
    cell.dataset.level = String(deterministicLevel(index));
    cell.style.setProperty('--d', `${index * 4}ms`); // 级联入场延迟
    fragment.appendChild(cell);
  }
  heatmap.appendChild(fragment);
}

function updateLanguage(nextLanguage) {
  language = nextLanguage;
  document.documentElement.lang = nextLanguage === 'zh' ? 'zh-CN' : 'en';
  document.querySelectorAll('[data-zh][data-en]').forEach((element) => {
    element.textContent = element.dataset[nextLanguage];
  });
  const languageButton = document.getElementById('languageButton');
  languageButton.textContent = nextLanguage === 'zh' ? 'EN' : '中';
  languageButton.setAttribute('aria-label', copy[nextLanguage].languageAria);
  updateShowcaseTitle();
  updateSmartDownloads();
}

function updateShowcaseTitle() {
  const title = document.getElementById('showcaseTitle');
  title.textContent = activeSlide === 0 ? copy[language].desktopTitle : copy[language].mobileTitle;
}

/* 手机端幻灯激活时的入场编排:热力图级联重播 + 大数字滚动计数 */
function playMobileIntro(panel) {
  const heatmap = panel.querySelector('.mini-heatmap');
  if (heatmap) {
    heatmap.classList.remove('is-played');
    void heatmap.offsetWidth; // 强制重排,让级联动画可以重播
    heatmap.classList.add('is-played');
  }
  const total = panel.querySelector('.mobile-total-card strong');
  const cost = panel.querySelector('.mobile-total-card b');
  if (!total || !cost || !total.firstChild) return;
  if (reduceMotion.matches) {
    total.firstChild.nodeValue = '12.4M ';
    cost.textContent = '$8.36';
    return;
  }
  const duration = 900;
  const start = performance.now();
  const frame = (now) => {
    const progress = Math.min(1, (now - start) / duration);
    const eased = 1 - Math.pow(1 - progress, 3);
    total.firstChild.nodeValue = `${(12.4 * eased).toFixed(1)}M `;
    cost.textContent = `$${(8.36 * eased).toFixed(2)}`;
    if (progress < 1) window.requestAnimationFrame(frame);
  };
  window.requestAnimationFrame(frame);
}

/* ========== 手机端功能页:可操作 + 停留时自动轮播 ========== */
const MOBILE_ROTATION = [0, 1, 2, 3]; // 总览/明细/配额/设备参与轮播,「我的」仅手动
let mobilePage = 0;
let mobilePageTimer = null;

function showMobilePage(index, { restart = true } = {}) {
  const pages = [...document.querySelectorAll('.mobile-page')];
  if (!pages.length) return;
  mobilePage = Math.max(0, Math.min(pages.length - 1, Number(index) || 0));
  pages.forEach((page, pageIndex) => {
    page.classList.toggle('is-active', pageIndex === mobilePage);
  });
  document.querySelectorAll('.mobile-tabs [data-page]').forEach((tab) => {
    tab.classList.toggle('active', Number(tab.dataset.page) === mobilePage);
  });
  // 轮播回到总览时重播计数与热力图级联
  if (pages[mobilePage].dataset.page === 'overview') {
    playMobileIntro(document.querySelector('.mobile-slide'));
  }
  if (restart) startMobilePageCarousel();
}

function stopMobilePageCarousel() {
  if (mobilePageTimer) window.clearInterval(mobilePageTimer);
  mobilePageTimer = null;
}

function startMobilePageCarousel() {
  stopMobilePageCarousel();
  if (reduceMotion.matches || document.hidden) return;
  mobilePageTimer = window.setInterval(() => {
    const position = MOBILE_ROTATION.indexOf(mobilePage);
    const next = position === -1 ? 0 : MOBILE_ROTATION[(position + 1) % MOBILE_ROTATION.length];
    showMobilePage(next, { restart: false });
  }, 3800);
}

/* 明细页:三周期(今天/本月/累计)行数据,口径与总览页一致 */
const MOBILE_TOOLS = [
  { icon: 'claude', name: 'Claude Code', color: '#CC7C5E', share: 63,
    v: { today: ['7.8M', '$5.12'], month: ['117M', '$78.35'], all: ['806M', '$542.44'] } },
  { icon: 'codex', name: 'Codex', color: '#49A3B0', share: 24,
    v: { today: ['2.9M', '$1.87'], month: ['44.7M', '$30.05'], all: ['307M', '$206.31'] } },
  { icon: 'cursor', name: 'Cursor', color: '#8FA3BF', share: 9,
    v: { today: ['1.1M', '$0.94'], month: ['16.8M', '$10.55'], all: ['115M', '$73.14'] } },
  { icon: 'copilot', name: 'GitHub Copilot', color: '#9B8CF2', share: 3,
    v: { today: ['412K', '$0.21'], month: ['5.6M', '$2.82'], all: ['38.4M', '$25.01'] } },
  { icon: 'kimi', name: 'Kimi Code', color: '#5B6B85', share: 1.6,
    v: { today: ['198K', '$0.22'], month: ['2.98M', '$2.73'], all: ['20.5M', '$16.10'] } }
];
let mobilePeriod = 'today';

function renderMobileToolRows() {
  const box = document.getElementById('mobileToolRows');
  if (!box) return;
  box.innerHTML = MOBILE_TOOLS.map((tool) => `
    <div class="tool-row">
      <img src="../app-prototype/icons/${tool.icon}.png" alt="">
      <div><span>${tool.name}</span><i><b style="width:${tool.share}%;background:${tool.color}"></b></i></div>
      <strong>${tool.v[mobilePeriod][0]}<small>${tool.v[mobilePeriod][1]}</small></strong>
    </div>`).join('');
}

function initMobilePages() {
  document.querySelectorAll('.mobile-tabs [data-page]').forEach((tab) => {
    tab.addEventListener('click', () => showMobilePage(tab.dataset.page));
  });
  document.querySelectorAll('#mobilePeriodSeg span').forEach((seg) => {
    seg.addEventListener('click', () => {
      document.querySelectorAll('#mobilePeriodSeg span').forEach((item) => item.classList.toggle('on', item === seg));
      mobilePeriod = seg.dataset.period;
      renderMobileToolRows();
      startMobilePageCarousel(); // 用户正在操作,顺延自动轮播
    });
  });
  renderMobileToolRows();
}

function stopMobileCaptureCarousel() {
  if (mobileCaptureTimer) window.clearInterval(mobileCaptureTimer);
  mobileCaptureTimer = null;
}

function startMobileCaptureCarousel() {
  stopMobileCaptureCarousel();
  if (reduceMotion.matches || document.hidden || activeSlide !== 1) return;
  mobileCaptureTimer = window.setInterval(() => {
    showMobileCapture(mobileCaptureIndex + 1, { restart: false });
  }, 3200);
}

function showMobileCapture(index, { restart = true } = {}) {
  const shots = [...document.querySelectorAll('[data-mobile-shot]')];
  const buttons = [...document.querySelectorAll('[data-mobile-index]')];
  if (!shots.length) return;
  mobileCaptureIndex = ((Number(index) || 0) % shots.length + shots.length) % shots.length;
  shots.forEach((shot, shotIndex) => {
    const position = (shotIndex - mobileCaptureIndex + shots.length) % shots.length;
    const active = position === 0;
    shot.dataset.position = String(position);
    shot.classList.toggle('is-active', active);
    shot.setAttribute('aria-hidden', String(!active));
  });
  buttons.forEach((button, buttonIndex) => {
    const active = buttonIndex === mobileCaptureIndex;
    button.classList.toggle('is-active', active);
    button.setAttribute('aria-selected', String(active));
  });
  if (restart) startMobileCaptureCarousel();
}

function initMobileCapture() {
  document.querySelectorAll('[data-mobile-index]').forEach((button) => {
    button.addEventListener('click', () => showMobileCapture(button.dataset.mobileIndex));
  });
  showMobileCapture(0, { restart: false });
}

function showSlide(index, { restart = true } = {}) {
  const tabs = [...document.querySelectorAll('.showcase-tab')];
  const dots = [...document.querySelectorAll('.carousel-dot')];
  const panels = [...document.querySelectorAll('.showcase-slide')];
  activeSlide = Number(index) || 0;

  // 电脑端 / 手机端是两张独立幻灯,只显示当前一张,不再同屏叠加
  panels.forEach((panel, panelIndex) => {
    panel.classList.toggle('is-active', panelIndex === activeSlide);
  });
  const activePanel = panels[activeSlide];
  if (activePanel && activePanel.classList.contains('mobile-slide')) {
    showMobilePage(mobilePage);
    showMobileCapture(mobileCaptureIndex);
  } else {
    stopMobilePageCarousel();
    stopMobileCaptureCarousel();
  }
  tabs.forEach((tab, tabIndex) => {
    const active = tabIndex === activeSlide;
    tab.classList.toggle('is-active', active);
    tab.setAttribute('aria-selected', String(active));
  });
  dots.forEach((dot, dotIndex) => {
    const active = dotIndex === activeSlide;
    dot.classList.toggle('is-active', active);
    dot.setAttribute('aria-current', String(active));
  });
  updateShowcaseTitle();
  if (restart) startCarousel();
}

function stopCarousel() {
  if (carouselTimer) window.clearInterval(carouselTimer);
  carouselTimer = null;
}

function startCarousel() {
  stopCarousel();
  if (reduceMotion.matches || document.hidden) return;
  carouselTimer = window.setInterval(() => showSlide(activeSlide === 0 ? 1 : 0, { restart: false }), 6200);
}

async function detectDevice() {
  const userAgent = navigator.userAgent || '';
  const platform = navigator.userAgentData?.platform || navigator.platform || '';

  if (/HarmonyOS|OpenHarmony|ArkWeb/i.test(userAgent)) return { key: 'harmony', arch: null };
  if (/Android/i.test(userAgent)) return { key: 'android', arch: null };
  if (/Windows/i.test(userAgent) || /Win/i.test(platform)) return { key: 'windows', arch: 'x64' };
  if (/Macintosh|Mac OS X/i.test(userAgent) || /Mac/i.test(platform)) {
    let arch = null;
    try {
      const hints = await navigator.userAgentData?.getHighEntropyValues?.(['architecture', 'bitness']);
      if (/arm/i.test(hints?.architecture || '')) arch = 'arm64';
      if (/x86/i.test(hints?.architecture || '') && hints?.bitness === '64') arch = 'x64';
    } catch {
      arch = null;
    }
    return { key: 'mac', arch };
  }
  if (/Linux/i.test(userAgent) || /Linux/i.test(platform)) return { key: 'linux', arch: 'x64' };
  return { key: 'unknown', arch: null };
}

function findAsset(assets, matcher) {
  return assets.find((asset) => matcher.test(asset.name))?.browser_download_url || LATEST_RELEASE_PAGE;
}

async function loadLatestRelease() {
  try {
    const response = await fetch(LATEST_RELEASE_API, {
      headers: { Accept: 'application/vnd.github+json' }
    });
    if (!response.ok) throw new Error(`GitHub release request failed: ${response.status}`);
    const release = await response.json();
    const assets = Array.isArray(release.assets) ? release.assets : [];
    releaseAssets = {
      macArm: findAsset(assets, /arm64\.dmg$/i),
      macIntel: findAsset(assets, /x64\.dmg$/i),
      windows: findAsset(assets, /^ZT-Monitor-Setup-.*\.exe$/i),
      windowsPortable: findAsset(assets, /^ZT-Monitor-(?!Setup-).*\.exe$/i),
      linux: findAsset(assets, /\.AppImage$/i)
    };
    document.getElementById('releaseStatus').textContent = release.tag_name || copy[language].latest;
    document.getElementById('macArmDownload').href = releaseAssets.macArm;
    document.getElementById('macIntelDownload').href = releaseAssets.macIntel;
    document.getElementById('windowsDownload').href = releaseAssets.windows;
    document.getElementById('windowsPortableDownload').href = releaseAssets.windowsPortable;
    document.getElementById('linuxDownload').href = releaseAssets.linux;
  } catch {
    releaseAssets = null;
    document.getElementById('releaseStatus').textContent = copy[language].latest;
  }
  updateSmartDownloads();
}

function smartDownloadSpec() {
  const t = copy[language];
  if (detectedDevice.key === 'mac') {
    if (detectedDevice.arch === 'arm64') return { platform: 'mac', label: t.macLabel, meta: 'Apple Silicon · DMG', href: releaseAssets?.macArm || LATEST_RELEASE_PAGE };
    if (detectedDevice.arch === 'x64') return { platform: 'mac', label: t.macLabel, meta: 'Intel · DMG', href: releaseAssets?.macIntel || LATEST_RELEASE_PAGE };
    return { platform: 'mac', label: t.macChoose, meta: t.macMeta, href: '#mac-builds', chooseMac: true };
  }
  if (detectedDevice.key === 'windows') return { platform: 'windows', label: t.windowsLabel, meta: t.windowsMeta, href: releaseAssets?.windows || LATEST_RELEASE_PAGE };
  if (detectedDevice.key === 'linux') return { platform: 'linux', label: t.linuxLabel, meta: t.linuxMeta, href: releaseAssets?.linux || LATEST_RELEASE_PAGE };
  if (detectedDevice.key === 'android') return { platform: 'android', label: t.androidLabel, meta: t.androidMeta, href: new URL(ANDROID_APK_PATH, window.location.href).href, download: ANDROID_APK_FILENAME };
  if (detectedDevice.key === 'harmony') return { platform: 'harmony', label: t.harmonyLabel, meta: t.harmonyMeta, href: '#download' };
  return { platform: 'unknown', label: t.unknownLabel, meta: t.unknownMeta, href: LATEST_RELEASE_PAGE };
}

function updateSmartDownloads() {
  const spec = smartDownloadSpec();
  const targets = [
    {
      anchor: document.getElementById('heroDownload'),
      icon: document.getElementById('heroPlatformIcon'),
      label: document.getElementById('heroDownloadLabel'),
      meta: document.getElementById('heroDownloadMeta')
    },
    {
      anchor: document.getElementById('sectionDownload'),
      icon: document.getElementById('sectionPlatformIcon'),
      label: document.getElementById('sectionDownloadLabel'),
      meta: document.getElementById('sectionDownloadMeta')
    }
  ];

  targets.forEach(({ anchor, icon, label, meta }) => {
    anchor.href = spec.href;
    anchor.dataset.chooseMac = spec.chooseMac ? 'true' : 'false';
    if (spec.download) anchor.download = spec.download;
    else anchor.removeAttribute('download');
    if (spec.href.startsWith('#') || spec.download) {
      anchor.removeAttribute('target');
      anchor.removeAttribute('rel');
    } else {
      anchor.target = '_blank';
      anchor.rel = 'noopener';
    }
    icon.dataset.platform = spec.platform;
    label.textContent = spec.label;
    meta.textContent = spec.meta;
  });
}

function configureBetaQr() {
  const androidUrl = new URL(ANDROID_APK_PATH, window.location.href).href;
  const androidQrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=184x184&format=png&margin=8&bgcolor=F4F7FB&color=0B1220&data=${encodeURIComponent(androidUrl)}`;

  ['androidQrImage', 'heroAndroidQrImage'].forEach((id) => {
    const qrImage = document.getElementById(id);
    if (qrImage) qrImage.src = androidQrUrl;
  });
  ['androidBetaLink', 'heroAndroidBetaLink'].forEach((id) => {
    const link = document.getElementById(id);
    if (!link) return;
    link.href = androidUrl;
    link.download = ANDROID_APK_FILENAME;
  });
  document.querySelectorAll('[data-community-qr]').forEach((image) => {
    image.src = COMMUNITY_QR_PATH;
  });
  ['harmonyBetaLink', 'heroHarmonyBetaLink'].forEach((id) => {
    const link = document.getElementById(id);
    if (!link) return;
    link.href = COMMUNITY_QR_PATH;
    link.download = 'zt-monitor-community-qr.png';
  });
}

function closeBetaCards(except = null) {
  document.querySelectorAll('.beta-card').forEach((card) => {
    if (card === except) return;
    card.classList.remove('is-open');
    card.querySelector('.beta-trigger')?.setAttribute('aria-expanded', 'false');
  });
}

function initInteractions() {
  document.getElementById('languageButton').addEventListener('click', () => updateLanguage(language === 'zh' ? 'en' : 'zh'));

  document.querySelectorAll('[data-slide]').forEach((control) => {
    control.addEventListener('click', () => showSlide(control.dataset.slide));
  });

  const showcase = document.querySelector('.showcase');
  showcase.addEventListener('mouseenter', stopCarousel);
  showcase.addEventListener('mouseleave', startCarousel);
  showcase.addEventListener('focusin', stopCarousel);
  showcase.addEventListener('focusout', (event) => {
    if (!showcase.contains(event.relatedTarget)) startCarousel();
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      stopCarousel();
      stopMobileCaptureCarousel();
      return;
    }
    startCarousel();
    startMobileCaptureCarousel();
  });
  reduceMotion.addEventListener?.('change', () => {
    startCarousel();
    startMobileCaptureCarousel();
  });

  document.querySelectorAll('.smart-download').forEach((anchor) => {
    anchor.addEventListener('click', (event) => {
      if (anchor.dataset.chooseMac !== 'true') return;
      event.preventDefault();
      const card = document.querySelector('[data-platform-card="mac"]');
      card.scrollIntoView({ behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'center' });
      window.setTimeout(() => document.getElementById('macArmDownload').focus(), reduceMotion.matches ? 0 : 450);
    });
  });

  document.querySelectorAll('.beta-trigger').forEach((button) => {
    button.addEventListener('click', (event) => {
      event.stopPropagation();
      const card = button.closest('.beta-card');
      const shouldOpen = !card.classList.contains('is-open');
      closeBetaCards(card);
      card.classList.toggle('is-open', shouldOpen);
      button.setAttribute('aria-expanded', String(shouldOpen));
    });
  });

  document.addEventListener('pointerdown', () => {
    keyboardNavigation = false;
  }, { capture: true });

  document.querySelectorAll('.beta-card').forEach((card) => {
    card.addEventListener('focusin', () => {
      if (!keyboardNavigation) return;
      closeBetaCards(card);
      card.classList.add('is-open');
      card.querySelector('.beta-trigger')?.setAttribute('aria-expanded', 'true');
    });
    card.addEventListener('focusout', (event) => {
      if (card.contains(event.relatedTarget)) return;
      card.classList.remove('is-open');
      card.querySelector('.beta-trigger')?.setAttribute('aria-expanded', 'false');
    });
  });

  document.addEventListener('click', (event) => {
    if (!event.target.closest('.beta-card')) closeBetaCards();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Tab') keyboardNavigation = true;
    if (event.key === 'Escape') closeBetaCards();
  });
}

function initMotion() {
  if (reduceMotion.matches || !('IntersectionObserver' in window)) return;
  const elements = document.querySelectorAll('.section-heading, .feature-lead-card, .feature-card, .tool-coverage, .workflow-line article, .platform-card');
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: .12, rootMargin: '0px 0px -36px' });
  elements.forEach((element, index) => {
    element.classList.add('motion-item');
    element.style.setProperty('--motion-delay', `${Math.min(index % 3, 2) * 70}ms`);
    observer.observe(element);
  });
}

function initHeader() {
  const header = document.querySelector('.site-header');
  const update = () => header.classList.toggle('is-scrolled', window.scrollY > 12);
  update();
  window.addEventListener('scroll', update, { passive: true });
}

async function init() {
  buildHeatmap();
  configureBetaQr();
  initInteractions();
  initHeader();
  initMotion();
  initMobilePages();
  initMobileCapture();
  showSlide(0);
  detectedDevice = await detectDevice();
  updateSmartDownloads();
  await loadLatestRelease();
}

init();
