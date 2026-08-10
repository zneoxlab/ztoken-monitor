// ============================================================
// 鉴权路径判定 —— 免鉴权端点清单。
// 拆成独立文件,供 dio_client(请求拦截)与 auth_interceptor(401 续期)
// 共用,避免私有符号跨文件不可见。
//
// 续期端点 /api/auth/refresh 自身 401 不触发续期(避免无限循环);
// 登录/注册/健康检查不带 Authorization。
// ============================================================

const _kNoAuthPaths = <String>[
  '/api/auth/login',
  '/api/auth/register',
  '/api/auth/refresh',
  '/api/health',
];

/// 路径是否免鉴权(不注入头,401 不续期)。
bool isNoAuthPath(String path) {
  // path 可能含 query,取 pathname 段比较
  final q = path.indexOf('?');
  final p = q >= 0 ? path.substring(0, q) : path;
  return _kNoAuthPaths.any((n) => p == n || p.startsWith('$n/'));
}
