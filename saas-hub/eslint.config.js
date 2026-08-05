'use strict';

// saas-hub 独立 ESLint 配置（flat config）
// 与主项目分离：saas-hub 是独立服务，有自己的依赖和工具链

const js = require('@eslint/js');
const globals = require('globals');

module.exports = [
  { ignores: ['node_modules/**'] },
  js.configs.recommended,
  {
    languageOptions: {
      sourceType: 'commonjs',
      globals: { ...globals.node }
    },
    rules: {
      // 与主项目风格一致：允许 console（服务端日志）
      'no-console': 'off',
      // 允许用 _ 前缀标记故意忽略的参数/解构
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      // 允许空 catch 块（连接断开等故意忽略的场景）
      'no-empty': ['error', { allowEmptyCatch: true }]
    }
  }
];
