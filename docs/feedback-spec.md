# 课后反馈写作规范（原 parent-lesson-feedback skill，已融合进本 pipeline）

> 本文档是 physics-class-pipeline 的课后反馈写作规范（单一事实来源）。
> `scripts/postclass_generate.sh` 生成自动反馈草稿、AI 精修反馈时都必须遵循本规范。

---

## Core principle

Treat after-class feedback as a way to give parents justified certainty, not as a class recap. Help the parent understand:

1. what this lesson focused on and why;
2. what the student can do better after the lesson;
3. what problems still remain and what they mean;
4. what I will do next.

Build trust through accurate judgment, concrete evidence, and a clear next step. Never exaggerate problems, promise outcomes, manufacture urgency, or write empty praise.

Lessons happen frequently, so the student's focus problems are tracked as a slow-evolving fixed list, not re-diagnosed from scratch every lesson. Parents should see continuity and progress across lessons, not a different diagnosis each time.

## Evidence-first workflow

1. Read the supplied lesson transcript, meeting notes, or teacher notes before drafting.
2. Load the student ledger（本 pipeline 中即 `{vault_path}/上课记录/学生档案/<student-name>.md`）. If it exists, “孩子本节课暴露问题” and “下一步计划” must keep continuity with it; if not, this is the student's first feedback — diagnose from the lesson record and create the ledger after drafting (see “Student focus-issue ledger” below).
3. Extract observable evidence:
   - what the student could do independently;
   - what required my prompt or demonstration;
   - whether the student corrected an error after guidance;
   - whether the student could apply the idea when the question changed;
   - representative wording, answers, calculations, hesitation, correction, or study behavior.
4. Separate facts from interpretation:
   - Fact: what the student actually said or did.
   - Interpretation: what that behavior suggests about understanding, expression, habits, or independence.
5. Select only the most important evidence. Prefer details that reveal the student's learning stage over a list of isolated mistakes.
6. Support each statement about improvement or difficulty with a short, objective example from the lesson record.

### Insufficient-information rule

Do not invent classroom details or present generic examples as facts.

If the lesson record does not contain enough evidence to identify improvement or remaining problems, stop before drafting and ask one concise question, such as:

> 老师，这次课里有没有一个最能代表孩子进步或当前困难的具体片段？比如他在哪道题、哪句话或哪一步出现了变化，经过提示后是否能够改正？

If only one required section lacks evidence, ask only for that missing information. Ask no more than three short questions at once. Continue drafting only after the teacher replies.

## Student focus-issue ledger

Maintain one ledger per student. In this pipeline the ledger is the student profile at `{vault_path}/上课记录/学生档案/<student-name>.md` (its 「主要问题」 section serves as the focus-issue ledger). Read it before drafting; update it after the feedback is finalized. The legacy path `students/<student-name>_focus_issues.md` is equivalent if it exists.

Ledger format:

```markdown
# <学生名>重点问题台账

最后更新：YYYY-MM-DD（对应课次日期）

## 进行中问题

### 1. <问题名>
- 阶段：新增 / 好转中 / 稳定
- 首次出现：YYYY-MM-DD
- 描述：一句话概括该学习问题
- 最近证据：最近一节课的可观察证据
- 下一步：当前的针对性安排

## 已解决问题

### <问题名>（解决于 YYYY-MM-DD）
- 一句话概括解决过程与证据
```

Ledger update rules:

- Advance a stage only when the lesson record provides supporting evidence (`新增 → 好转中 → 解决`); if a problem recurs, regress `好转中` back to `稳定` and note why.
- Move solved issues from “进行中问题” to “已解决问题” with the resolution date.
- Do not guess the student's name; if no ledger exists, ask the user for the student's name before creating one.
- After updating the ledger, report the key ledger changes to the user in one short line.

## Required output structure

Begin every finished message with the exact line `本节课反馈：`.

Use exactly the following four headings unless the user explicitly requests another structure:

- `「1. 本节课内容」`
- `「2. 本节课进步」`
- `「3. 孩子本节课暴露问题」`
- `「4. 下一步计划」`

Use both Chinese corner brackets `「」` around every major heading to make it visually prominent. Do not render major headings as Markdown headings or bold text. Insert one blank line after `本节课反馈：` and one blank line between every major section so the message remains easy to scan in WeChat. Write as a direct WeChat message from the teacher, using “我”, not “老师” or “经过老师”.

Follow this plain-text skeleton:

```text
本节课反馈：

「1. 本节课内容」
...

「2. 本节课进步」
提升表现：
...
具体例子：
...
阶段判断：
...

「3. 孩子本节课暴露问题」
一：...（新增）
本节课表现：
...
我的判断：
...

二：...（好转中）
本节课表现：
...
我的判断：
...

「4. 下一步计划」
过去的问题：
...

下节课安排：
...

其他安排：
...
```

### 1. 本节课内容

Explain the lesson focus with moderate detail:

- state the main topic;
- explain the purpose of the lesson;
- mention two to four important abilities or connections covered;
- connect the lesson with prior or future learning when relevant.

Do not turn this section into a chronological recap or a detailed syllabus. Avoid listing every formula, question, or teaching step. Use plain language that a parent with no subject knowledge can understand.

### 2. 本节课进步

State what changed as a result of the lesson, not merely what the student completed.

For each meaningful improvement, use this internal structure:

- `提升表现：` Describe what the student can now recognize, explain, correct, or complete better than before.
- `具体例子：` Give one brief classroom example showing the change, including the level of prompting when relevant.
- `阶段判断：` Clarify whether the improvement is independent, achieved with light prompting, or still emerging.

Only claim improvement when the lesson record shows a before-and-after change or a stronger performance later in the lesson. Do not equate “followed my explanation” with “mastered independently.” When a previously tracked focus problem becomes solved, mention it here in one sentence.

### 3. 孩子本节课暴露问题

This section is a continuous tracking list, not a fresh per-lesson diagnosis. It combines problems newly exposed in this lesson with all past ongoing problems, so parents see both what surfaced today and that earlier problems are not forgotten. The issue list must stay continuous with the student ledger (or the previous feedback). Rules:

- Focus on the main issues: section 3 lists at most about two issues — the most important ongoing past problems plus the most notable newly exposed ones. Parents need the highlights, not an exhaustive list.
- Carry forward past problems: past problems must never silently disappear. The key ones being actively worked on belong in section 3; any tracked issue not listed there must still be mentioned in section 4 under `过去的问题：` or `其他安排：`, with a note that it keeps being worked on (e.g. “这是之前就在持续跟进的问题，接下来仍会重点抓”).
- Wording continuity: reuse the same issue summary wording as previous lessons; never rename or re-diagnose the same problem.
- Status tracking: append a stage label in round brackets to each issue — `（新增）`, `（好转中）`, or `（稳定）`. Solved issues are removed from this section and mentioned in one sentence under “本节课进步”.
- Add a new issue only when the lesson record shows clear, repeatable evidence; a one-off slip never creates a new entry.
- When no ledger exists (first feedback), diagnose from the lesson record, label every entry `（新增）`, and create the ledger after drafting.

Number each issue with Chinese numerals such as `一：`, `二：`. Put a blank line between issues. For each issue, use this internal structure:

- `一：<问题概括>（<阶段>）` State the learning issue in tactful, precise language, matching the ledger wording; do not add a separate `当前问题：` label.
- `本节课表现：` Cite real evidence from this lesson: an answer, wording, a step, hesitation, or a response to a prompt. If a carried-forward issue showed no new evidence this lesson, say so plainly (e.g. “本节课未出现新的明显表现，继续观察”) instead of inventing evidence.
- `我的判断：` Explain what the current stage means and why it matters for later learning.

Example:

> 一：物理描述不够严谨，常漏掉判分关键词（好转中）  
> 本节课表现：在描述运动状态的题目中，孩子主动写出了“匀加速”和“匀速”，仅“terminal velocity”一处需要我提醒。  
> 我的判断：表达正在向判分标准靠拢，但关键词全覆盖还不稳定，需要继续整句练习巩固。

Keep examples objective, specific, brief, and parent-readable. Use technical detail only when it helps prove the diagnosis. Do not overload the parent with formulas or solution steps.

### 4. 下一步计划

The plan uses a simple two-part structure instead of a per-issue checklist, so it stays short and parent-friendly:

- `过去的问题：` Name the past problems still being tracked and give the overall approach for how they will keep being addressed. This is where parents see earlier problems are not forgotten. Keep it to one short paragraph.
- `下节课安排：` State the concrete arrangement for the next lesson (topic or focus practice, and why it matters). Keep it to one short paragraph.
- `其他安排：` Optional. Homework format, schedule, or minor habit items (e.g. units) that do not deserve a full section-3 entry. One or two sentences.

Avoid empty phrases such as “继续加强”“多做练习” or “回家复习.” Even in the short format, each arrangement must say something concrete. Do not include family-cooperation advice unless the user specifically asks for it.

## Writing rules

- Write for a parent who may know nothing about the subject.
- Use first-person teacher language such as “我会”“我观察到”“经过我的提示”.
- Lead with judgments, evidence, and next actions; omit routine classroom chronology.
- Use calm, tactful, precise language. Describe the problem without labeling the child.
- Prefer “掌握尚不稳定”“在提示下可以完成，独立应用仍需巩固” over “基础很差”“脑子乱”“完全不会”.
- Preserve seriousness through stage descriptions and learning consequences, not alarming adjectives.
- Acknowledge genuine progress, but do not use praise as filler.
- Keep the default response compact enough to send directly through WeChat. Unless the user requests detail, target roughly 400–600 Chinese characters for the complete feedback, use one concise paragraph per label (one to three short sentences each), include only the strongest one or two improvements and at most about two focus issues, and avoid repeating the same stage judgment in multiple sections. Expand only when requested.
- Use the student's name or “孩子” according to the user's preference. Do not guess a name or gender.
- Combine the structure with the actual lesson content. Never reuse a previous lesson's topic, example, improvement, or diagnosis merely because the wording fits the template.
- Keep labels such as `提升表现：`, `具体例子：`, `阶段判断：`, `本节课表现：`, `我的判断：`, `过去的问题：`, `下节课安排：`, and `其他安排：` on their own lines when followed by a paragraph.

## Quality check

Before sending, verify:

1. Does the message begin with `本节课反馈：` and use the four exact corner-bracket headings?
2. Is there a blank line between every major section?
3. Does “本节课内容” provide enough context without becoming a detailed class recap?
4. Is every claimed improvement supported by a real classroom example?
5. Is every tracked ledger issue covered somewhere in the message (section 3 or section 4), with stage labels and wording consistent with the student ledger, and every issue listed in section 3 supported by real evidence from this lesson?
6. Are fact and inference clearly separated?
7. Can a non-specialist understand why each example matters?
8. Does “下一步计划” contain both `过去的问题：` (tracked past problems plus the overall approach) and `下节课安排：` (a concrete next-lesson arrangement)?
9. Are the arrangements concrete rather than vague?
10. Did the draft avoid invented details, stale examples from other lessons, vague praise, overpromising, fear-based language, and unnecessary family instructions?
11. Was the student ledger read before drafting and updated after drafting, and were the key ledger changes reported to the user in one line?
