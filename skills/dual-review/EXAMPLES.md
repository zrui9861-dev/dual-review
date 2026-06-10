# Dual-Review Examples

## Example 1: Dual-Model Review (compact)

**User**: `/dual-review --dual --discuss "设计高并发 API 限流方案"`

```
## 🔨 R1 Generate

采用令牌桶 + Redis Lua 脚本。每节点独立限流，Redis 近实时同步。
[完整方案...]

## 🔍 Critique [DeepSeek]

Score: 0.55 | Blocking: yes | 2 disputes + 3 issues

## 💬 R2 Discuss
| # | Dispute | Claude | Critic | → |
|----|---------|--------|--------|---|
| 1 | 令牌桶vs滑动窗口 | 令牌桶O(1)内存+突发 | 滑动窗口更精确 | 🤝 各让一步 |
| 2 | 分布式一致性 | 独立限流+Redis同步 | 多节点超限 | 🔴 still active |

Agreement: 0.55→0.70 | New: 1 major

## 💬 R3 Discuss
| 1 | 分布式一致性 | 接受10%超限+告警+熔断 | 可接受,需监控 | ✅ resolved |

Agreement: 0.70→0.88 | **Converged** ✅

## ✅ Final

[令牌桶 + Redis + 10%超限容忍方案, 附 Critic 同意的监控指标]
```

## Example 2: Self-Review (single round)

**User**: `/dual-review "这个 SQL 查询有问题吗？SELECT * FROM orders WHERE ..."`

Claude 分析 + 自审 → Score 0.92, no blocking → L2 触发，一轮结束。

## Example 3: Escalation (deadlock)

**User**: `/dual-review --dual --discuss "微服务间通信用 gRPC 还是消息队列？"`

```
## 💬 R1-R3 Discuss
| # | Dispute | Claude | Critic | → |
|----|---------|--------|--------|---|
| 1 | gRPC vs MQ | gRPC(低延迟同步) | MQ(解耦+削峰) | 🔴 2 rounds no progress |

## ⚖️ Escalation (L5)
Claude: 核心链路用 gRPC(低延迟), 非关键用 MQ(解耦)
Critic dissent: "如果调用链 >3 层,gRPC 超时级联风险大,建议全 MQ"
→ 混合方案:[gRPC + MQ],附 dissent 供用户参考
```
