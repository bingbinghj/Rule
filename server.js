/**
 * 更新日期：2026-04-16
 * 功能：批量修改节点 Server 与 Port，并允许自动更新新后端的流量/天数信息
 * 参数示例：#server=cloudcone.chihui.de&port=48314&filter=Bage%20US&newname=CloudCone%20US
 */

const inArg = $arguments;
const NEW_SERVER = inArg.server || 'example.com';
const NEW_PORT = Number(inArg.port || 443);
const FILTER_KEY = inArg.filter || '';      
const NEW_NAME_PREFIX = inArg.newname || ''; 
const DEBUG = inArg.debug === 'true';

function operator(proxies, targetPlatform, context) {
  let modified = 0;

  proxies = proxies.map(proxy => {
    // 1. 判定是否需要修改
    const shouldModify =
      !FILTER_KEY ||
      (proxy.name && proxy.name.includes(FILTER_KEY)) ||
      (proxy._subName && proxy._subName.includes(FILTER_KEY));

    if (shouldModify) {
      // 2. 替换连接参数
      proxy.server = NEW_SERVER;
      proxy.port = NEW_PORT;

      // 3. 处理显示名称
      // 提取前缀：如果 originalName 是 "Bage US-dwp6yd5m-4.00TB📊..."
      // split('-')[0] 会得到 "Bage US"
      let originalName = proxy.name || '';
      let baseName = NEW_NAME_PREFIX || originalName.split('-')[0];
      
      // 核心改动：统一 proxy.name 和 _subDisplayName
      // 去掉所有可能干扰的旧后缀
      proxy.name = baseName.trim();
      proxy._subDisplayName = baseName.trim();

      modified++;
    }

    return proxy;
  });

  if (DEBUG) {
    console.log(`✅ 已修改 ${modified} 个节点。`);
  }

  return proxies;
}
