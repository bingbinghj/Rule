/**
 * 更新日期：2025-10-08
 * 适配：Sub-Store 后端 >= 2.14.88
 * 功能：批量修改节点 server 与 port
 * 示例参数：
 *   #server=new.example.com&port=443
 *   #server=new.example.com&port=8443&filter=dmit
 */

const inArg = $arguments;
const NEW_SERVER = inArg.server || 'example.com';
const NEW_PORT = Number(inArg.port || 443);
const FILTER_KEY = inArg.filter || '';  // 可选，仅修改含指定关键词的节点名
const DEBUG = inArg.debug === 'true';

// 主操作逻辑
function operator(proxies, targetPlatform, context) {
  let modified = 0;

  proxies = proxies.map(proxy => {
    const shouldModify =
      !FILTER_KEY ||
      (proxy.name && proxy.name.includes(FILTER_KEY)) ||
      (proxy._subName && proxy._subName.includes(FILTER_KEY));

    if (shouldModify) {
      proxy.server = NEW_SERVER;
      proxy.port = NEW_PORT;
      proxy.name = `${proxy.name} [${NEW_SERVER}:${NEW_PORT}]`;
      modified++;
    }
    return proxy;
  });

  if (DEBUG) {
    console.log(`✅ 已修改 ${modified} 个节点 (server=${NEW_SERVER}, port=${NEW_PORT})`);
  }

  return proxies;
}
