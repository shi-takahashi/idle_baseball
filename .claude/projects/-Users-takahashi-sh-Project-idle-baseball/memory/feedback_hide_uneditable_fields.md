---
name: feedback-hide-uneditable-fields
description: 編集できないフィールドは disabled で表示せず、レイアウトから完全に非表示にする
metadata:
  type: feedback
---

編集できない（無効化されている）フィールドは、UI からも消す。disabled 表示で残すとノイズになる。

**Why:** 2026-05-27 の選手編集画面で、能力非開示サブスク未購入時に「年齢・利き腕・打席」を
`enabled: false` の disabled 表示で残していたところ「邪魔。編集できないものは表示したく
ない」と指摘された。disabled なフィールドが並ぶと意図がぼやけて、画面の縦スペースも無駄。

**How to apply:**
- 「無効化して残す」のではなく**セクションごと出し分ける**
- 例外: 名前など「誰の画面か」が分からなくなる識別情報だけは、編集不可の **表示専用**
  （TextField でなく Text）で残す
- 編集可能なものは独立したセクションにまとめ、画面の意図を明快にする
- 「ヒントカード」で「ここから先はサブスクで解放される」等のガイダンスは出してよい
  （フィールド自体ではなく、別ブロックとして表示する）

関連: [[project_hidden_parameters]]（能力非表示の方針自体）、
[[feedback_design_decisions_conversational]]（UI 設計は会話で詰める）
