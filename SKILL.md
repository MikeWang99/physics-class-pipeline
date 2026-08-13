---
name: physics-class-pipeline
description: 物理教学课前/课中/课后全链路自动化。课前定时扫描苹果日历生成备课笔记；课中自动录制会议音频；课后基于转写文字稿生成家长反馈、更新学生档案、给出作业建议。触发词：备课、课前、上课、下课、课后、全链路、class pipeline。
---

# Physics Class Pipeline · 物理教学全链路

把「课前备课 → 课中录音 → 课后反馈/档案/作业」串成一条自动化流水线。所有产出写入 Obsidian Vault 的「上课记录」分区。

## 0. 通用约定

- **配置文件**：`config.json`（位于本 skill 目录），由 `setup.sh` 生成。字段：
  - `vault_path`：Obsidian Vault 根目录
  - `recordings_dir`：录音/文字稿工作目录（默认 `~/physics-class-pipeline-data`）
  - `calendar_keyword`：日历事件识别关键词（默认 `Class`）
  - `scan_hour` / `scan_minute`：每日课前扫描时间（默认 10:00）
- **笔记根目录**：`{vault_path}/上课记录/`，下设四个子分区：
  - `备课内容/`、`课堂文字稿/`、`课后反馈/`、`学生档案/`
- **文件命名**：`YYYY-MM-DD {体系} Class-{学生}.md`（学生档案固定为 `{学生}.md`，累积更新）
- **日历事件格式**：`{体系} Class-{学生名}`，如 `CIE Class-Sujal`、`AP Class-Eden`。体系取 `Class` 前文本，学生取连字符后文本。
- 读取配置后再干活；`config.json` 不存在时提示用户先运行 `setup.sh`。
- 所有脚本在 `scripts/` 下，用绝对路径调用。

## 1. 首次安装（闭环）

用户说「安装/设置 physics-class-pipeline」时：

```bash
bash {skill_dir}/setup.sh
```

setup.sh 会自动完成：依赖检查（brew/ffmpeg 缺则自动装/python3/swift）→ 安装 BlackHole 虚拟声卡（需重启一次，重启后重跑 setup.sh）→ 尝试创建多输出音频设备（新系统可能失败，会提示手动替代方案，不阻塞安装）→ 探测 Obsidian Vault → 读取 GROQ_API_KEY → 创建后台应用 PhysicsClassWatcher/PhysicsClassScanner 并注册两个 launchd 任务（每日 10:00 课前扫描 + 常驻会议监听）→ 自动弹出系统麦克 风授权窗口并等待用户点一次「允许」→ 安装 skill 到 `~/.qoder/skills` 与 `~/.codex/skills`。全程打印每一步结果。卸载用 `uninstall.sh`。

## 2. 课前：备课内容生成

**自动部分（launchd 每天 10:00）**：`preclass_scan.py` 扫描明天日历，找出所有含 `Class` 关键词的事件，为每节课在 `{vault}/上课记录/备课内容/` 生成带上下文的备课笔记骨架（已自动填入学生档案摘要、最近一次课后反馈、上次课内容回顾），并发送 macOS 通知提醒补全。

**AI 补全部分**：用户说「备课」「补全备课」「生成备课内容」时：

1. 读 `config.json` 拿 `vault_path`。
2. 列出 `{vault}/上课记录/备课内容/` 中明天日期开头的笔记（若无，先手动运行 `python3 {skill_dir}/scripts/preclass_scan.py` 生成）。
3. 对每份骨架笔记：
   - 结合**该体系的官方 syllabus**（CIE IGCSE 0625 / AP Physics 1/2/C 等，依据学生档案中的体系字段；本地工作区如有 syllabus 资料优先引用）
   - 结合 `{vault}/上课记录/学生档案/{学生}.md` 的当前进度、薄弱项
   - 结合骨架中已嵌入的上节课回顾
   - 补全「本次课教学目标」「教学流程与时间分配」「关键题目/演示」「预判学生卡点」等章节
4. 直接编辑该笔记文件（保持 front matter 与已填上下文不动）。

## 3. 课中：自动录音（全自动，无需 AI 参与）

launchd 常驻任务 `meeting_watcher.sh` 每 15 秒检测一次会议进程：

- **覆盖平台**：Zoom（zoom.us）、腾讯会议（wemeetapp/xmeet）、钉钉、飞书、Google Meet（Chrome/Safari 打开 meet.google.com 标签页）
- **检测到开课**：自动用 ffmpeg 录制 BlackHole（会议双方声音）+ 麦克风（双保险），存入 `{recordings_dir}/sessions/{YYYY-MM-DD_HHMM}/audio.wav`
- **检测到散会**（连续 45 秒无会议进程）：停止录音 → 自动调用 Groq Whisper 转写 → 文字稿存 `transcript.txt` → macOS 通知「转写完成，请说『下课』生成课后产出」

用户无需任何手动操作。若用户说「开始上课/手动录音」，可直接运行 `bash {skill_dir}/scripts/meeting_watcher.sh once` 强制走一轮录音+转写。

## 4. 课后：反馈 + 档案 + 作业

用户说「下课」「课后」「生成课后反馈」时：

1. 读 `config.json`。找 `{recordings_dir}/sessions/` 中**最新一个**含 `transcript.txt` 的会话目录；读入全文。
   - 同时对照日历（当天/最近含 `Class` 的事件）确定本节课的体系与学生；多个候选时问用户。
2. **生成课后反馈**：调用已有的 `parent-lesson-feedback` skill（遵守其 400–600 字、问题台账、两段式计划规范），将结果存为
   `{vault}/上课记录/课后反馈/{YYYY-MM-DD} {体系} Class-{学生}.md`。
3. **更新学生档案**：读 `{vault}/上课记录/学生档案/{学生}.md`（不存在则新建），按以下固定结构更新（保留历史章节，追加/修订最新状态）：
   ```markdown
   # 学生档案 · {学生}
   ## 基本信息
   - 姓名：
   - 所在地：
   - 所属体系：（如 CIE IGCSE 0625 / AP Physics C）
   ## 当前进度
   （最近一次更新：YYYY-MM-DD）正在学的章节/单元、syllabus 覆盖进度
   ## 主要问题
   带状态标记：新增 / 好转中 / 稳定 / 已解决
   ## 薄弱项
   ## 优势项
   ## 课次记录
   | 日期 | 课题 | 一句话总结 |
   ```
   只依据文字稿中的可观察证据更新，不臆测。
4. **家庭作业建议**：不写入文件，直接在聊天框发给用户，包含：作业内容、对应 syllabus 知识点、预计用时、提交方式建议。
5. **归档文字稿**：把 `transcript.txt` 复制到 `{vault}/上课记录/课堂文字稿/{YYYY-MM-DD} {体系} Class-{学生}.md`（加 front matter 注明时长与来源）。

## 5. 故障排查

| 现象 | 处理 |
|---|---|
| 录音文件无声/只有单方 | 确认系统输出设备是 `PhysicsClass Multi-Output`（setup 创建）；运行 `scripts/setup_audio.sh check` |
| 没检测到开会 | 运行 `bash scripts/meeting_watcher.sh once` 看检测日志；浏览器开 Meet 需在 Chrome/Safari 且标签页可见 |
| 日志报 `MIC PERMISSION: missing` | 麦克风未授权：打开 系统设置→隐私与安全性→麦克风，把 PhysicsClassWatcher 打开（或重跑 setup.sh 触发弹窗） |
| 转写失败 | 检查 `GROQ_API_KEY`（`~/.zshrc`），看 `{recordings_dir}/logs/watcher.log` |
| 转写报 Forbidden | 国内网络被 Groq 区域封锁；脚本会自动读取 macOS 系统代理（如 Clash），确保代理软件开启且系统代理已启用 |
| 定时任务没跑 | `launchctl list \| grep physicsclass` 确认任务在；plist 在 `~/Library/LaunchAgents/` |
