# Changelog

## [1.1.0] - 2026-06-15

### Added — Two-Phase Workflow（先讨论再写代码）

- **Phase 1: 🧭 Design Discussion** — 先讨论方案达成共识，再进入实现
- **Phase 2: 🔨 Implementation** — 基于共识的方案写代码
- 紧凑可视化格式：emoji 状态图标 + 表格，一眼看清讨论进展
- Token 节省：只显示变更，不重复展示完整设计/代码
- 设计回合上限 2 轮，实现回合上限 3 轮

### Added — Role Flexibility（灵活角色分配）

用户可以自由决定哪个模型写代码、哪个模型审查：

- `--critic <model>`: 指定审查模型，Claude 生成
- `--review`: 角色互换，用户提供代码，Claude 当审查
- `--gen <model>`: 外部模型生成，Claude 审查把关
- `--gen <model> --critic <model>`: 全外部双模型，Claude 编排
- 新增 `generate.sh` / `generate.ps1` 脚本，支持调用任意模型生成代码

### Added — Multi-Agent Adapter Support

- **OpenAI Codex** (`codex-*`): Codex CLI agent as critic, via OpenAI API
- **Google Gemini** (`gemini-*`): Gemini 2.5 Pro/Flash via AI Studio OpenAI-compatible endpoint
- **Trae Work** (`trae-*`): ByteDance Trae AI coding agent, configurable endpoint
- **Workbuddy** (`workbuddy-*`): Local/remote Workbuddy agent, defaults to localhost:11434
- All new agents work with critique + generate + discuss modes
- Each provider supports `*_BASE_URL` env var override for custom endpoints

### Changed

- Updated install wizard with 4 new agent options + generate scripts
- Expanded error messages with full agent list
- 抽取共享 `lib/provider_router.sh`，critique/discuss/generate 统一路由
- generate.sh 改用 `GENERATOR_MODEL` 独立变量名 + 重试/降级机制
- SKILL.md 完全重写：参数冲突检测矩阵 + Claude审查JSON模板 + 同模型警告 + 外部生成fallback
- 向后兼容：默认模式行为不变，旧 config.env 无需修改
- EXAMPLES.md 新增 3 个角色灵活分配示例
- README.md 新增角色分配速查表

### Verification

Run these checks before releasing:
```bash
# 1. Verify provider routing parses correctly
for m in codex-mini gemini-2.5-pro trae-work workbuddy-local; do
  echo "test" | CRITIC_MODEL=$m bash skills/dual-review/scripts/critique.sh 2>&1 | head -1
done
# Expected: API key errors (routing works), NOT "Unknown model"

# 2. Verify install script syntax
bash -n install.sh && echo "install.sh OK"

# 3. Verify PowerShell syntax
pwsh -NoProfile -Command "Get-Command .\install.ps1" 2>/dev/null || echo "Skip PS check (no pwsh)"
```

## [1.0.0] - 2026-06-12

- One-command install with model setup wizard
- Free-text model input, auto-detect provider
- `/dr` shortcut command
- Support: DeepSeek, Qwen, Moonshot, GLM, OpenAI, Anthropic, custom API
- macOS/Linux (bash) + Windows (PowerShell) installers
- Self-review, dual-model, and multi-turn debate modes
