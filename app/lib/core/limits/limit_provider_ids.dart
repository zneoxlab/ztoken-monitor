// 与桌面端 src/shared/limitCollector.js LIMIT_PROVIDER_IDS 对齐。
const kLimitProviderIds = <String>[
  'claude',
  'codex',
  'opencode',
  'cursor',
  'antigravity',
  'kimi',
  'grok',
  'copilot',
  'mimo',
  'zai',
  'zaiteam',
  'kiro',
  'deepseek',
  'openrouter',
  'minimax',
  'volcengine',
  'qoder',
  'ollama',
  'thirdparty',
];

int limitProviderRank(String provider) {
  final id = provider.trim().toLowerCase();
  final idx = kLimitProviderIds.indexOf(id);
  return idx < 0 ? kLimitProviderIds.length : idx;
}
