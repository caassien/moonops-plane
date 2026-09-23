# OrbitOps Plane

OrbitOps Plane 是一个使用 MoonBit 构建的、可嵌入的智能运维控制面核心。调用方提供期望状态、观测状态、资源依赖和安全策略，控制面生成确定性的变更计划、审批要求与审计事件。

项目将规划与执行解耦：核心负责差异识别、依赖排序、风险分级、变更预算和状态保护，SSH、Kubernetes、云 API 等真实副作用由宿主适配器执行。

## 核心目标

- 相同输入产生相同计划，重复调和不生成多余动作。
- 依赖资源先于其消费者变更，循环依赖在执行前被拒绝。
- 删除、批量重启等高风险动作必须通过安全策略和审批。
- 过期观测状态或失效计划不能进入执行阶段。
- 每次允许、拒绝、审批和执行反馈都形成可追溯审计事件。

## 使用场景

1. 根据服务版本、实例数和依赖关系规划发布与扩缩容。
2. 识别配置漂移，并区分自动修复、人工审批和拒绝操作。
3. 在故障处置中生成受预算约束的隔离、重启或替换计划。

## 项目边界

首个版本专注无副作用的控制面内核和模拟执行器，不实现监控平台、远程 Agent、SSH/Kubernetes 客户端、Web 管理后台或大模型自动执行。真实凭据、网络隔离和平台级回滚由宿主负责。

## 依赖感知发布演示

在仓库根目录运行：

```bash
moon run cmd/demo -- rollout
moon run cmd/demo -- drift
moon run cmd/demo -- incident
```

`rollout` 按“数据库迁移 → API 更新 → Worker 扩容”的依赖顺序生成计划，使用单资源批次和内存执行器完成一次无副作用调和；`drift` 展示自动允许的配置修复以及过期观测拒绝；`incident` 展示高风险审批和指定动作失败后的停止。三个场景都会打印策略决定、执行反馈和审计事件，并使用固定计划标识和固定时钟保持输出可重复。

## 本地质量检查

CI 会在推送到 `main`、针对 `main` 创建或更新 Pull Request 时执行以下门禁；提交前可在仓库根目录复现：

```bash
moon fmt --check
moon info
git diff --exit-code
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

## 项目信息

- MoonBit 模块：`caassien/orbitops_plane`
- GitHub：<https://github.com/caassien/orbitops-plane>
- 许可证：Apache-2.0
