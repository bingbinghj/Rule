/**
 * 更新日期：2025-10-08
 * 功能：批量修改 server/port，并根据参数手动设置节点名前缀
 * 示例参数：
 * #server=example.com&port=1145&prefixexample -&filter=example
 */

const inArg = $arguments;
const NEW_SERVER = inArg.server || 'example.com';
const NEW_PORT = Number(inArg.port || 443);
const NEW_PREFIX = inArg.prefix || ''; // 从参数获取前缀，例如 "example"
const FILTER_KEY = inArg.filter || ''; 
const DEBUG = inArg.debug === 'true';

function operator(proxies) {
  let modified = 0;

  return proxies.map(proxy => {
    const originalName = proxy.name || "";
    
    // 检查是否符合过滤条件
    const shouldModify = !FILTER_KEY || originalName.includes(FILTER_KEY);

    if (shouldModify) {
      proxy.server = NEW_SERVER;
      proxy.port = NEW_PORT;

      // --- 动态重命名逻辑 ---
      // 提取原名中的流量和时间信息：匹配从数字开始到结尾的部分
      const statsMatch = originalName.match(/(\d+(?:\.\d+)?(?:GB|TB|MB|KB)[\s\S]+)/i);
      const statsInfo = statsMatch ? statsMatch[1].trim() : originalName;

      // 拼接：[手动输入的前缀] + [提取的流量时间信息]
      // 如果没有传 prefix 参数，则保持原样
      const newName = NEW_PREFIX ? `${NEW_PREFIX} ${statsInfo}` : originalName;
      
      proxy.name = newName;
      proxy._subDisplayName = newName;

      modified++;
    }

    return proxy;
  });
}
