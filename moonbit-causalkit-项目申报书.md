# MoonBit CausalKit 项目申报书

## 基本信息

- 项目名称：MoonBit CausalKit
- 参赛者：cauchyQ
- 联系方式：13009453635
- GitHub：https://github.com/cauchyQ/moonbit-causalkit
- Gitlink：https://gitlink.org.cn/cauchyQ/moonbit-causalkit
- 项目方向：MoonBit 分布式系统基础库与确定性仿真工具。

## 项目简介与适用场景

MoonBit CausalKit 是纯 MoonBit 实现的分布式因果关系基础库，回答多节点事件的先后、并发冲突和日志何时可安全压缩等问题。它适用于离线优先应用、协同编辑、消息同步、事件溯源、CRDT 调试、分布式缓存和复制协议测试。

## 核心功能与实施路径

- 以 Hybrid Logical Clock、Version Vector、Dot/DotSet 表示和比较事件因果关系；
- 提供延迟、乱序、离线与恢复场景下的多节点确定性模拟器；
- 提供 MV/LWW Register、OR-Set、PN-Counter 与因果 Map 等 CRDT 基础组件；
- 通过因果缓冲器、反熵同步、成员视图、稳定前沿、检查点和操作日志，完成乱序接收、确认、重放与安全压缩闭环；
- 提供因果图分析、时钟诊断、CLI 示例、自动测试和跨平台 CI，持续验证公共 API 与核心路径。

## 原创与交付说明

本项目为原创的 AI 辅助开发成果，不移植、复制或包含第三方代码库；采用 Apache-2.0 许可证。最终交付可发布的 MoonBit 库、README 与最小运行示例、公开 API、自动化测试、跨平台 CI，以及 mooncakes.io 软件包。调用方负责网络、持久化、认证、物理时钟读取和业务策略；本项目专注提供确定性的因果算法、CRDT 基础组件与测试工具。
