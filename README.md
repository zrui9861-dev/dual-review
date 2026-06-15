# Dual Review — Claude Code Skill

让两个 AI 协作审查代码。一个写，一个审，反复辩论直到达成一致。

## 安装

一行命令，安装过程会引导你选择模型和输入 API key。

### macOS / Linux

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-review@main/install.sh | bash
```

### Windows (PowerShell)

```powershell
Invoke-WebRequest -Uri https://cdn.jsdelivr.net/gh/zrui9861-dev/dual-review@main/install.ps1 | Invoke-Expression
```

## 使用

```
/dr 你要做的事
```

Claude 自动选择模式：

| 模式 | 触发条件 | 需要 |
|------|---------|------|
| 自审查 | 跳过选择 / 没配 key | 无 |
| 双模型 | 选了审查模型（默认） | API key |
| 多轮辩论 | 复杂问题自动 | API key |

> 💡 `/dr` 启动时**现场选模型**，不用 skill 时一切照旧 — 不影响默认大模型。

### 🎯 灵活角色分配（NEW）

用户可以自由决定哪个模型写代码、哪个模型审查：

| 命令 | 生成者 | 审查者 | 说明 |
|------|--------|--------|------|
| `/dr 写代码` | Claude | config 审查模型 | 默认模式 |
| `/dr --critic gpt-4o 写代码` | Claude | gpt-4o | 指定谁来审 |
| `/dr --review "```py\ncode\n```"` | 用户提供 | Claude | Claude 当审查 |
| `/dr --gen deepseek 写代码` | deepseek | Claude | 外部生成，Claude把关 |
| `/dr --gen qwen --critic deepseek 写代码` | qwen-max | deepseek | 全外部，Claude编排 |

## 效果

```
/dr 设计 API 限流方案

R1: Claude 方案 → DeepSeek 审查 → 2 个争议, Score 0.55
R2: 辩论 → 达成共识
R3: 辩论 → 解决

完成 — 一致性 0.40 → 0.85
```

## 支持的审查 Agent

deepseek-chat / deepseek-reasoner / qwen-max / qwen-plus / moonshot-v1 / glm-4 / gpt-4o / codex-* / claude-sonnet-4-6 / gemini-* / trae-* / workbuddy-* / 任何 OpenAI 兼容 API

## 怎么工作的

生成 → 审查 → 收敛（6层检查防无限循环）→ 解决

详见 [CONVERGENCE.md](skills/dual-review/CONVERGENCE.md)

## License

MIT
