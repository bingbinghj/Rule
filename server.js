/**
 * 更新日期：2026-04-16
 * 功能：批量修改 server/port，并将节点名完全替换为手动填写的 prefix
 * 示例参数：
 * #server=dmit.chihui.de&port=29368&prefix=DMIT US - Bage US&filter=Bage
 */

const inArg = $arguments;
const NEW_SERVER = inArg.server || 'example.com';
const NEW_PORT = Number(inArg.port || 443);
const NEW_PREFIX = inArg.prefix || ''; // 手动填写的名字
const FILTER_KEY = inArg.filter || ''; 
const DEBUG = inArg.debug === 'true';

function operator(proxies) {
  let modifiedCount = 0;

  return proxies.map((proxy) => {
    const originalName = proxy.name || "";
    
    // 检查是否符合过滤条件
    const shouldModify = !FILTER_KEY || originalName.includes(FILTER_KEY);

    if (shouldModify) {
      proxy.server = NEW_SERVER;
      proxy.port = NEW_PORT;

      // --- 简单的重命名逻辑 ---
      // 如果提供了 prefix，就直接使用 prefix
      // 如果 prefix 中包含 [index]，则自动加上序号
      let newName = NEW_PREFIX || originalName;
      
      if (NEW_PREFIX.includes("[index]")) {
        newName = NEW_PREFIX.replace("[index]", modifiedCount + 1);
      }

      proxy.name = newName;
      proxy._subDisplayName = newName;

      modifiedCount++;
    }

    return proxy;
  });
}
