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
| 自审查 | 没配 key | 无 |
| 双模型 | 配了 key（默认） | API key |
| 多轮辩论 | 复杂问题自动 | API key |

## 效果

```
/dr 设计 API 限流方案

R1: Claude 方案 → DeepSeek 审查 → 2 个争议, Score 0.55
R2: 辩论 → 达成共识
R3: 辩论 → 解决

完成 — 一致性 0.40 → 0.85
```

## 支持的第二模型

deepseek-chat / deepseek-reasoner / qwen-max / qwen-plus / moonshot-v1 / glm-4 / gpt-4o / claude-sonnet-4-6 / 任何 OpenAI 兼容 API

## 怎么工作的

生成 → 审查 → 收敛（6层检查防无限循环）→ 解决

详见 [CONVERGENCE.md](skills/dual-review/CONVERGENCE.md)

## License

MIT
