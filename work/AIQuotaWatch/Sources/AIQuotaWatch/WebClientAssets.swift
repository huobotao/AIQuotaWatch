import Foundation

enum WebClientAssets {
    static let html = #"""
<!doctype html>
<html lang="zh-Hans">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#111317">
  <title>AI 额度观察</title>
  <link rel="manifest" href="/manifest.webmanifest">
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <link rel="stylesheet" href="/styles.css">
</head>
<body>
  <main class="app-shell">
    <header class="topbar">
      <div>
        <p class="eyebrow">Mac 实时快照</p>
        <h1>AI 额度观察</h1>
        <p id="summary" class="summary">正在连接 Mac...</p>
      </div>
      <button id="refreshButton" class="refresh" type="button" aria-label="刷新">
        <span class="refresh-icon">↻</span>
        <span>刷新</span>
      </button>
    </header>

    <section class="meter-strip" aria-label="余额摘要">
      <div>
        <span>Codex</span>
        <strong id="codexRemaining">--</strong>
      </div>
      <div>
        <span>Claude</span>
        <strong id="claudeRemaining">--</strong>
      </div>
      <div id="fableTile">
        <span>Fable</span>
        <strong id="fableRemaining">--</strong>
      </div>
      <div>
        <span>扫描</span>
        <strong id="scanTime">--</strong>
      </div>
    </section>

    <section id="providers" class="providers"></section>

    <section class="token-panel">
      <div class="section-title">
        <div>
          <p class="eyebrow">Token 消耗</p>
          <h2>随时间变化</h2>
        </div>
        <span id="tokenTotal" class="pill">--</span>
      </div>
      <div id="tokenChart" class="token-chart" aria-label="Token 消耗图"></div>
      <div id="conversationList" class="conversation-list"></div>
    </section>

    <footer>
      <span>由 Codex（GPT-5）为 Richard 制作</span>
      <span id="apiState">--</span>
    </footer>
  </main>
  <script src="/app.js"></script>
</body>
</html>
"""#

    static let css = #"""
:root {
  color-scheme: dark;
  --bg: #111317;
  --panel: #1a1d22;
  --panel-2: #20242a;
  --border: #333942;
  --text: #f4f5f6;
  --muted: #a1a7af;
  --soft: #737b86;
  --codex: #2f80e7;
  --claude: #cc6231;
  --time: #4f95c5;
  --good: #3aa667;
  --warn: #e6a23c;
  --danger: #dd4b5a;
  --shadow: 0 18px 48px rgba(0, 0, 0, .28);
}

* {
  box-sizing: border-box;
}

html,
body {
  min-height: 100%;
}

body {
  margin: 0;
  background:
    linear-gradient(180deg, rgba(79, 149, 197, .12), transparent 330px),
    radial-gradient(circle at top right, rgba(204, 98, 49, .14), transparent 260px),
    var(--bg);
  color: var(--text);
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
  letter-spacing: 0;
}

button,
input {
  font: inherit;
}

.app-shell {
  width: min(1120px, 100%);
  margin: 0 auto;
  padding: max(18px, env(safe-area-inset-top)) 16px max(24px, env(safe-area-inset-bottom));
}

.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  padding: 12px 0 18px;
}

.eyebrow {
  margin: 0 0 5px;
  color: var(--muted);
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
}

h1,
h2,
h3,
p {
  margin: 0;
}

h1 {
  font-size: clamp(30px, 8vw, 54px);
  line-height: .98;
}

h2 {
  font-size: 20px;
}

.summary {
  margin-top: 10px;
  color: var(--muted);
  font-weight: 650;
}

.refresh {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  min-height: 42px;
  padding: 0 15px;
  border: 1px solid rgba(47, 128, 231, .45);
  border-radius: 8px;
  background: #0f72e9;
  color: white;
  font-weight: 800;
  box-shadow: 0 10px 28px rgba(47, 128, 231, .25);
}

.refresh:active {
  transform: translateY(1px);
}

.refresh-icon {
  font-size: 20px;
  line-height: 1;
}

.meter-strip {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 10px;
  margin-bottom: 14px;
}

.meter-strip > div,
.provider-card,
.window-card,
.token-panel {
  border: 1px solid var(--border);
  border-radius: 8px;
  background: rgba(26, 29, 34, .92);
  box-shadow: var(--shadow);
}

.meter-strip > div {
  min-width: 0;
  padding: 13px 14px;
}

.meter-strip span {
  display: block;
  color: var(--muted);
  font-size: 12px;
  font-weight: 700;
}

.meter-strip strong {
  display: block;
  margin-top: 4px;
  font-size: clamp(20px, 6vw, 32px);
  line-height: 1;
}

.providers {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 330px), 1fr));
  gap: 14px;
  align-items: start;
}

.provider-stack {
  display: grid;
  gap: 14px;
  align-content: start;
  min-width: 0;
}

.provider-card {
  padding: 16px;
}

.provider-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 15px;
}

.provider-name {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.rail {
  width: 10px;
  height: 44px;
  border-radius: 4px;
  background: var(--codex);
}

.provider-card.claude .rail {
  background: var(--claude);
}

.provider-name h2 {
  overflow-wrap: anywhere;
}

.mode {
  margin-top: 3px;
  color: var(--muted);
  font-size: 13px;
  font-weight: 650;
}

.big-percent {
  font: 800 36px/1 ui-monospace, SFMono-Regular, Menlo, monospace;
}

.window-list {
  display: grid;
  gap: 11px;
}

.window-card {
  box-shadow: none;
  background: var(--panel-2);
  padding: 13px;
}

.window-top,
.bar-label,
.source-row,
.section-title,
footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.window-top {
  margin-bottom: 10px;
}

.window-title {
  font-size: 18px;
  font-weight: 850;
}

.countdown {
  color: var(--text);
  font: 750 14px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace;
}

.pace {
  display: inline-flex;
  align-items: center;
  min-height: 30px;
  margin: 4px 0 10px;
  padding: 0 10px;
  border-radius: 8px;
  background: rgba(58, 166, 103, .14);
  color: var(--good);
  font-size: 13px;
  font-weight: 800;
}

.pace.warn {
  background: rgba(230, 162, 60, .14);
  color: var(--warn);
}

.pace.muted {
  background: rgba(161, 167, 175, .11);
  color: var(--muted);
}

.bar-block {
  display: grid;
  gap: 7px;
  margin-top: 8px;
}

.bar-label {
  color: var(--muted);
  font-size: 13px;
  font-weight: 750;
}

.bar-label strong {
  color: var(--text);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.bar {
  position: relative;
  height: 12px;
  overflow: visible;
  border-radius: 999px;
  background: rgba(255, 255, 255, .07);
}

.fill {
  position: absolute;
  inset: 0 auto 0 0;
  width: 0;
  border-radius: inherit;
  background: var(--codex);
}

.provider-card.claude .fill {
  background: linear-gradient(90deg, var(--claude), #e14555);
}

.fill.time {
  background: var(--time);
}

.marker {
  position: absolute;
  top: -7px;
  width: 4px;
  height: 26px;
  margin-left: -2px;
  border-radius: 3px;
  background: var(--time);
}

.marker::before {
  content: "";
  position: absolute;
  left: 50%;
  top: -5px;
  width: 16px;
  height: 16px;
  transform: translateX(-50%);
  border: 2px solid #fff;
  border-radius: 999px;
  background: var(--panel-2);
}

.source-row {
  margin-top: 13px;
  padding-top: 10px;
  border-top: 1px solid rgba(255, 255, 255, .08);
  color: var(--muted);
  font-size: 12px;
  font-weight: 650;
}

.source-row span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.empty-state {
  padding: 18px;
  border: 1px dashed var(--border);
  border-radius: 8px;
  color: var(--muted);
  font-weight: 700;
}

.token-panel {
  margin-top: 14px;
  padding: 16px;
}

.pill {
  flex: 0 0 auto;
  padding: 7px 10px;
  border-radius: 8px;
  background: rgba(79, 149, 197, .15);
  color: #9bd0ef;
  font: 800 13px/1 ui-monospace, SFMono-Regular, Menlo, monospace;
}

.token-chart {
  display: flex;
  align-items: end;
  gap: 3px;
  height: 150px;
  margin-top: 15px;
  padding: 10px;
  border: 1px solid rgba(255, 255, 255, .08);
  border-radius: 8px;
  background: rgba(0, 0, 0, .16);
}

.token-bar {
  flex: 1 1 0;
  min-width: 3px;
  border-radius: 3px 3px 0 0;
  background: linear-gradient(180deg, #9bd0ef, #2f80e7);
}

.conversation-list {
  display: grid;
  gap: 8px;
  margin-top: 12px;
}

.conversation {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 10px;
  padding: 10px 0;
  border-top: 1px solid rgba(255, 255, 255, .08);
}

.conversation strong {
  overflow-wrap: anywhere;
}

.conversation span,
footer {
  color: var(--muted);
  font-size: 12px;
  font-weight: 650;
}

footer {
  padding: 18px 0 4px;
}

@media (max-width: 680px) {
  .app-shell {
    padding-left: 12px;
    padding-right: 12px;
  }

  .topbar {
    align-items: flex-start;
  }

  .refresh span:last-child {
    display: none;
  }

  .meter-strip {
    grid-template-columns: 1fr;
  }

  .provider-card,
  .token-panel {
    padding: 13px;
  }

  .big-percent {
    font-size: 32px;
  }
}
"""#

    static let javascript = #"""
const state = {
  timer: null,
  lastData: null,
};

const els = {
  summary: document.getElementById('summary'),
  codexRemaining: document.getElementById('codexRemaining'),
  claudeRemaining: document.getElementById('claudeRemaining'),
  fableRemaining: document.getElementById('fableRemaining'),
  fableTile: document.getElementById('fableTile'),
  scanTime: document.getElementById('scanTime'),
  providers: document.getElementById('providers'),
  tokenTotal: document.getElementById('tokenTotal'),
  tokenChart: document.getElementById('tokenChart'),
  conversationList: document.getElementById('conversationList'),
  apiState: document.getElementById('apiState'),
  refreshButton: document.getElementById('refreshButton'),
};

els.refreshButton.addEventListener('click', () => loadStatus(true));

async function loadStatus(manual = false) {
  try {
    if (manual) els.apiState.textContent = '正在刷新';
    const response = await fetch('/api/status', { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    state.lastData = data;
    render(data);
    els.apiState.textContent = `API ${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}`;
  } catch (error) {
    els.summary.textContent = '连接不到 Mac 端 API';
    els.apiState.textContent = error.message;
  }
}

function render(data) {
  els.summary.textContent = data.summary || '--';
  els.codexRemaining.textContent = data.codexRemaining || '--';
  els.claudeRemaining.textContent = data.claudeRemaining || '--';
  els.fableRemaining.textContent = data.fableRemaining || '--';
  els.fableTile.style.display = data.fableRemaining && data.fableRemaining !== '--' ? '' : 'none';
  els.scanTime.textContent = data.scannedAtEpoch ? timeText(data.scannedAtEpoch) : timeText(data.scannedAt);
  els.providers.innerHTML = providerGroups(data.providers || []);
  renderTokens(data.tokenReport || {});
}

function providerGroups(providers) {
  const codex = providers.filter(provider => /codex/i.test(provider.name || ''));
  const claudeAccounts = providers.filter(provider => /claude code/i.test(provider.name || ''));
  const fableWallets = providers.filter(provider => /fable/i.test(provider.name || ''));
  const grouped = new Set([...codex, ...claudeAccounts, ...fableWallets]);
  const other = providers.filter(provider => !grouped.has(provider));
  return [codex, claudeAccounts, fableWallets, other]
    .filter(group => group.length)
    .map(group => `<div class="provider-stack">${group.map(providerCard).join('')}</div>`)
    .join('');
}

function providerCard(provider) {
  const isClaude = /claude/i.test(provider.name || '');
  const windows = provider.windows || [];
  return `
    <article class="provider-card ${isClaude ? 'claude' : 'codex'}">
      <div class="provider-head">
        <div class="provider-name">
          <span class="rail"></span>
          <div>
            <h2>${escapeHTML(provider.name || '--')}</h2>
            <p class="mode">${escapeHTML(provider.mode || '--')}</p>
          </div>
        </div>
        <div class="big-percent">${escapeHTML(provider.remaining || '--')}</div>
      </div>
      <div class="window-list">
        ${windows.length ? windows.map(windowCard).join('') : '<div class="empty-state">等待官方额度窗口</div>'}
      </div>
      <div class="source-row">
        <span>${escapeHTML(provider.source || '--')}</span>
        <span>${provider.latestAtEpoch ? relative(provider.latestAtEpoch) : '--'}</span>
      </div>
    </article>
  `;
}

function windowCard(window) {
  const used = clamp(window.usedPercent);
  const remaining = clamp(window.remainingPercent);
  const time = clamp(window.timePercent);
  const paceClass = paceClassName(window.pace);
  return `
    <section class="window-card">
      <div class="window-top">
        <div>
          <div class="window-title">${escapeHTML(window.title || '--')}</div>
          <p class="mode">${escapeHTML(window.subtitle || '')}</p>
        </div>
        <div class="countdown">${escapeHTML(window.countdown || '--')}</div>
      </div>
      <div class="pace ${paceClass}">${escapeHTML(window.pace || '暂无判断')}</div>
      <div class="bar-block">
        <div class="bar-label"><span>额度</span><strong>${pct(used)} · 剩 ${pct(remaining)}</strong></div>
        <div class="bar">
          <span class="fill" style="width:${used ?? 0}%"></span>
          <span class="marker" style="left:${time ?? 0}%"></span>
        </div>
      </div>
      <div class="bar-block">
        <div class="bar-label"><span>时间</span><strong>${pct(time)}</strong></div>
        <div class="bar">
          <span class="fill time" style="width:${time ?? 0}%"></span>
        </div>
      </div>
      <div class="source-row">
        <span>${escapeHTML(window.basis || '--')}</span>
        <span>${escapeHTML(window.resetText || '--')}</span>
      </div>
    </section>
  `;
}

function renderTokens(report) {
  const total = Number(report.totalTokens || 0);
  els.tokenTotal.textContent = total ? `${compact(total)} tokens` : '--';

  const events = (report.events || []).slice(-48);
  if (!events.length) {
    els.tokenChart.innerHTML = '<div class="empty-state">暂无 token 事件</div>';
  } else {
    const max = Math.max(...events.map(event => Number(event.tokens || 0)), 1);
    els.tokenChart.innerHTML = events.map(event => {
      const height = Math.max(4, Number(event.tokens || 0) / max * 100);
      const title = `${timeText(event.timestampEpoch)} · ${compact(event.tokens || 0)} tokens`;
      return `<div class="token-bar" title="${escapeHTML(title)}" style="height:${height}%"></div>`;
    }).join('');
  }

  const conversations = (report.conversations || []).slice(0, 8);
  els.conversationList.innerHTML = conversations.map(item => `
    <div class="conversation">
      <div>
        <strong>${escapeHTML(item.title || '未命名对话')}</strong>
        <span>${escapeHTML(relative(item.latestAtEpoch))}</span>
      </div>
      <strong>${compact(item.tokens || 0)}</strong>
    </div>
  `).join('');
}

function pct(value) {
  return Number.isFinite(value) ? `${Math.round(value)}%` : '--';
}

function clamp(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Math.max(0, Math.min(100, number));
}

function compact(value) {
  const number = Number(value || 0);
  if (Math.abs(number) >= 1000000) return `${(number / 1000000).toFixed(1)}M`;
  if (Math.abs(number) >= 1000) return `${(number / 1000).toFixed(1)}K`;
  return `${Math.round(number)}`;
}

function timeText(epoch) {
  if (!epoch) return '--';
  const date = new Date(Number(epoch) * 1000);
  if (Number.isNaN(date.getTime())) return '--';
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function relative(epoch) {
  if (!epoch) return '--';
  const seconds = Math.max(0, Math.floor(Date.now() / 1000 - Number(epoch)));
  if (seconds < 60) return '刚刚';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小时前`;
  return `${Math.floor(seconds / 86400)} 天前`;
}

function paceClassName(text = '') {
  if (text.includes('额度')) return 'warn';
  if (text.includes('暂无') || text.includes('等')) return 'muted';
  return '';
}

function escapeHTML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

loadStatus();
state.timer = setInterval(loadStatus, 10000);
"""#

    static let manifest = #"""
{
  "name": "AI 额度观察",
  "short_name": "AI额度",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#111317",
  "theme_color": "#111317",
  "icons": [
    {
      "src": "/favicon.svg",
      "sizes": "any",
      "type": "image/svg+xml"
    }
  ]
}
"""#

    static let favicon = #"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#111317"/>
  <path d="M12 44h40" stroke="#333942" stroke-width="6" stroke-linecap="round"/>
  <path d="M12 44h25" stroke="#2f80e7" stroke-width="6" stroke-linecap="round"/>
  <path d="M12 25h40" stroke="#333942" stroke-width="6" stroke-linecap="round"/>
  <path d="M12 25h34" stroke="#cc6231" stroke-width="6" stroke-linecap="round"/>
  <circle cx="40" cy="44" r="6" fill="#f4f5f6"/>
  <circle cx="49" cy="25" r="6" fill="#f4f5f6"/>
</svg>
"""#
}
