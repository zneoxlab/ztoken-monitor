import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/provider_icon.dart';

// 模型厂商识别与配色,对齐桌面 usageCharts.js。

const _fallbackModelColors = <Color>[
  Color(0xFF6AB4F0),
  Color(0xFFCC7C5E),
  Color(0xFFA57DF0),
  Color(0xFF49A3B0),
  Color(0xFFF0D66A),
  Color(0xFFF06A7B),
];

const _extendedVendorColors = <String, Color>{
  ...vendorColors,
  'gemini': Color(0xFF4285F4),
  'xai': Color(0xFF000000),
  'grok': Color(0xFF000000),
  'meta': Color(0xFF1D65C1),
  'mistral': Color(0xFFFA520F),
  'moonshot': Color(0xFF16191E),
  'zai': Color(0xFF000000),
  'zaiteam': Color(0xFF000000),
  'cohere': Color(0xFF39594D),
  'xiaomi': Color(0xFFFF6700),
  'mimo': Color(0xFF000000),
  'minimax': Color(0xFFF23F5D),
  'doubao': Color(0xFF1E37FC),
  'volcengine': Color(0xFF006EFF),
  'qoder': Color(0xFF2ADB5C),
  'ollama': Color(0xFF888888),
  'thirdparty': Color(0xFFDD2E57),
  'hermes': Color(0xFFD4AF37),
  'cline': Color(0xFF323B43),
  'pi': Color(0xFF000000),
  'zed': Color(0xFF4173E7),
  'kilocode': Color(0xFFF8F676),
  'zcode': Color(0xFF000000),
  'kiro': Color(0xFF9046FF),
  'codebuddy': Color(0xFF6C4DFF),
  'workbuddy': Color(0xFF0DC8A5),
  'proma': Color(0xFF000000),
  'openclaw': Color(0xFFFF4D4D),
};

String? modelVendorFor(String model) {
  final name = model.toLowerCase();
  if (RegExp(r'^(cursor-)?auto$').hasMatch(name)) return 'cursor';
  if (RegExp(r'claude|anthropic|sonnet|opus|haiku').hasMatch(name)) return 'claude';
  if (RegExp(r'gpt|openai|codex|^o[134](?:-|$)|o[134]-(mini|pro|preview)|chatgpt').hasMatch(name)) {
    return 'codex';
  }
  if (RegExp(r'gemini|gemma|google').hasMatch(name)) return 'gemini';
  if (RegExp(r'grok|xai').hasMatch(name)) return 'xai';
  if (name.contains('deepseek')) return 'deepseek';
  if (RegExp(r'llama|meta').hasMatch(name)) return 'meta';
  if (RegExp(r'mistral|mixtral|codestral').hasMatch(name)) return 'mistral';
  if (RegExp(r'qwen|qwq|qvq').hasMatch(name)) return 'qwen';
  if (RegExp(r'kimi|moonshot').hasMatch(name)) return 'kimi';
  if (RegExp(r'chatglm|\bglm-|\bzai\b|z\.ai|zhipu').hasMatch(name)) return 'zai';
  if (RegExp(r'cohere|command-r').hasMatch(name)) return 'cohere';
  if (RegExp(r'mimo|xiaomi').hasMatch(name)) return 'xiaomi';
  if (RegExp(r'minimax|\babab').hasMatch(name)) return 'minimax';
  if (RegExp(r'doubao|\bseed(?:-|$)').hasMatch(name)) return 'doubao';
  if (name == 'big-pickle') return 'opencode';
  return null;
}

Color modelColor(String model) {
  final vendor = modelVendorFor(model);
  if (vendor != null) {
    final color = _extendedVendorColors[vendor];
    if (color != null) return color;
  }
  final hash = model.toLowerCase().hashCode;
  return _fallbackModelColors[hash.abs() % _fallbackModelColors.length];
}

String? modelIconAssetId(String model) {
  final vendor = modelVendorFor(model);
  if (vendor == null) return null;
  const aliases = <String, String>{
    'hermes': 'hermes-agent',
    'grok': 'xai',
    'xiaomi': 'mimo-code',
    'mimo': 'mimo-code',
    'micode': 'mimo-code',
    'zai': 'zcode',
    'zaiteam': 'zcode',
    'thirdparty': 'newapi',
  };
  final id = aliases[vendor] ?? vendor;
  return knownProviderIconIds.contains(id) ? id : null;
}
