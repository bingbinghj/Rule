/**
 * 更新日期：2026-04-16
 * 功能：批量修改节点 Server 与 Port，并允许自动更新新后端的流量/天数信息
 * 参数示例：#server=cloudcone.chihui.de&port=48314&filter=Bage%20US&newname=CloudCone%20US
 */

const inArg = $arguments;
const NEW_SERVER = inArg.server || 'example.com';
const NEW_PORT = Number(inArg.port || 443);
const FILTER_KEY = inArg.filter || '';      // 匹配旧节点的关键词
const NEW_NAME_PREFIX = inArg.newname || ''; // 替换后的新名字前缀
const DEBUG = inArg.debug === 'true';

function operator(proxies, targetPlatform, context) {
  let modified = 0;

  proxies = proxies.map(proxy => {
    // 1. 判定是否需要修改（基于原始名称）
    const shouldModify =
      !FILTER_KEY ||
      (proxy.name && proxy.name.includes(FILTER_KEY)) ||
      (proxy._subName && proxy._subName.includes(FILTER_KEY));

    if (shouldModify) {
      // 2. 替换核心连接参数
      proxy.server = NEW_SERVER;
      proxy.port = NEW_PORT;

      // 3. 处理显示名称
      // 如果提供了 newname 参数，则使用新名字；否则尝试清除旧名字里的流量后缀
      let baseName = NEW_NAME_PREFIX || (proxy.name ? proxy.name.split('-')[0] : 'Node');
      
      // 重要：直接修改 proxy.name 而不使用 _subDisplayName
      // 这样 Sub-Store 发现没有 _subDisplayName 时，会自动把新后端的流量标签挂在 proxy.name 后面
      proxy.name = baseName.trim();
      
      // 清除可能存在的旧显示名称缓存，强制 Sub-Store 重新生成
      if (proxy._subDisplayName) {
        delete proxy._subDisplayName;
      }

      modified++;
    }

    return proxy;
  });

  if (DEBUG) {
    console.log(`✅ 修改完成: ${modified} 个节点。新地址: ${NEW_SERVER}:${NEW_PORT}`);
  }

  return proxies;
}
