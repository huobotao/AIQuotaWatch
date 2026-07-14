# 安全说明

## 不要提交的内容

以下内容可能包含账号凭据或个人用量数据，绝对不要加入 Git：

```text
~/Library/Application Support/AIQuotaWatch/
~/Library/Application Support/AIQuotaWatch/claude_token_*
~/Library/Application Support/AIQuotaWatch/status.json
~/.codex/sessions/
~/Library/Application Support/Claude/
任何 usage-*.jsonl、日志、截图或导出的浏览器数据
```

源码中的 `CLAUDE_CODE_OAUTH_TOKEN`、`claude_token_` 等文字是环境变量名和缓存文件名，不是实际令牌。

## 公开前检查

```bash
./scripts/check-public-safety.sh
git status --short
git diff --cached
```

如果真实令牌曾进入 Git 历史，仅删除当前文件不够。应立即撤销令牌，并在公开仓库前重写历史。

## 网络边界

主程序提供本地 HTTP 状态接口，供 Web/iPhone 客户端读取。它适合可信局域网，不应通过路由器端口转发、公共隧道或反向代理直接暴露到互联网。
