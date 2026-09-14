# MoonBit CausalKit 项目申报书

- 项目仓库：https://github.com/cauchyQ/moonbit-causalkit
- 项目性质：原创、AI 辅助开发的纯 MoonBit 分布式因果关系基础库，不移植或复制现有代码库。
- 项目简介：为多副本系统提供因果时钟、并发冲突识别、确定性仿真、乱序缓冲与安全日志压缩能力。
- 适用场景：离线优先应用、协同编辑、消息同步、事件溯源、CRDT 调试和复制协议测试。
- 核心功能：HLC、Version Vector、Dot/DotSet、确定性模拟器、MV/LWW Register、OR-Set、PN-Counter、因果 Map、因果图分析、成员视图、时钟诊断、反熵同步、稳定前沿、乱序缓冲、检查点与日志重放。
- 实施计划：完善因果基础类型和仿真，打通乱序接收、确认、稳定点及日志压缩闭环，并持续补齐测试、示例、CI 和发布资料。
- 预期交付：可发布的 MoonBit 库、CLI 示例、公开 API、自动测试、README、Apache-2.0 许可证及跨平台 CI。
- 技术边界：调用方负责网络、持久化、认证、物理时钟读取和业务策略；本项目提供确定性的因果算法、CRDT 基础组件与测试工具。
