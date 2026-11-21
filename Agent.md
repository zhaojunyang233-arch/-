# 项目工作说明

这是一个原生 Mac 剪贴板历史项目。按阶段交付，用简体中文向使用者说明本阶段能做什么、怎么体验和哪些项目还需要验证。

## 项目标准

| 文件 | 查阅时机 |
| --- | --- |
| [docs/requirements.md](docs/requirements.md) | 核对第一版范围和每项功能的验收条件 |
| [docs/technical-spec.md](docs/technical-spec.md) | 选择实现方式，处理剪贴板、存储和数据清理 |
| [docs/design-guidelines.md](docs/design-guidelines.md) | 设计或修改菜单栏入口、卡片、搜索和设置 |
| [docs/development-plan.md](docs/development-plan.md) | 选择当前阶段、执行测试和确认交付条件 |
| [development-logs/README.md](development-logs/README.md) | 查阅日志规则、定时任务和检查方法 |
| [development-logs/TODO.md](development-logs/TODO.md) | 查看和维护当前待办 |

## 开发流程

1. 从当前待办和最近一份日志确认进度，阅读需求和当前阶段涉及的标准。用户确认的要求优先。需求变更时，同步更新受影响的标准和验收条件。
2. 每次围绕当前阶段完成一个可运行、可验证的小目标。先验证这次改动的正常用法和相关边界，再进入依赖它的工作。涉及产品行为或数据删除规则的变化时，先和用户确认。
3. 只用虚构样例测试剪贴板。错误信息、开发日志和截图里只记录操作与结果，避免写入剪贴板原文、原图和秘密信息。
4. 结束前先更新 `development-logs/TODO.md`，再运行 `/bin/sh development-logs/create-daily-log.sh` 确保当天日志存在。将当次已完成事项、已做的验证和尚未验证的事项写入当天日志，并将当天的待办快照更新为最新内容。同一天继续补写，保留已有完成记录。定时任务启用后只负责创建缺失的日志。
5. 交付时告诉用户当前阶段的可用成果和验证结果。项目尚无可运行版本时，明确说明交付内容是文档或工具。
