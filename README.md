# physics-class-pipeline

物理教学「课前 → 课中 → 课后」全链路自动化 skill（macOS）。

| 阶段 | 行为 | 触发方式 |
|---|---|---|
| 课前 | 扫描明天苹果日历，为每节课生成备课笔记骨架（含学生档案摘要、上次反馈），AI 补全教学目标与流程 | launchd 每日 10:00 自动 + 说「备课」 |
| 课中 | 检测到会议（Zoom/腾讯会议/钉钉/飞书/Google Meet）自动录音，散会后 Groq Whisper 转写全员文字稿 | 常驻后台，全自动 |
| 课后 | 基于文字稿：生成家长反馈（调用 parent-lesson-feedback skill）、更新学生档案、给出作业建议 | 说「下课」 |

所有产出写入 Obsidian Vault 的「上课记录」分区：`备课内容 / 课堂文字稿 / 课后反馈 / 学生档案`。

## 安装

```bash
git clone https://github.com/<you>/physics-class-pipeline.git
cd physics-class-pipeline
bash setup.sh
```

`setup.sh` 一键完成：依赖检查 → BlackHole 虚拟声卡 + 多输出设备 → 探测 Obsidian Vault → 写 config.json → 注册 launchd 任务 → 链接到 `~/.qoder/skills` 与 `~/.codex/skills`。重复运行安全。

卸载：`bash uninstall.sh`（保留录音数据与笔记）。

## 依赖

- macOS（日历 / launchd / AppleScript / osascript）
- brew、ffmpeg、python3、swift（setup 会检查）
- `GROQ_API_KEY` 环境变量（Groq Whisper 免费额度转写用，写入 `~/.zshrc`）
- 日历事件命名：`{体系} Class-{学生名}`，如 `CIE Class-Sujal`

## 目录结构

```
SKILL.md                  # AI 工作流指令（任何支持 skill 的 AI 可执行）
config.json               # 运行时配置（setup.sh 生成，勿手改录音目录外字段）
setup.sh / uninstall.sh   # 安装 / 卸载
scripts/
  preclass_scan.py        # 课前：日历扫描 → 备课骨架
  meeting_watcher.sh      # 课中：会议检测 + 录音 + 转写（launchd 常驻）
  setup_audio.sh          # BlackHole 安装/检查/激活/还原
  create_multi_output.swift  # 创建 CoreAudio 多输出设备
  transcribe_audio.py     # Groq Whisper 转写（自动分片，无 25MB 限制）
```

录音与文字稿存放在 `~/physics-class-pipeline-data/`，日志在其 `logs/` 子目录。
