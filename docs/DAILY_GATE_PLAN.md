# 1日1試合制約（時間ゲート）実装計画

> 2026-05-27 策定。SPEC.md §未決定事項「シーズン頭の N 試合は連続プレイ可」と
> 「現実時間 1日1試合」の実装計画。
>
> PROGRESS.md 上は「Phase 6 収益化への入口」相当（次の磨き込みフェーズ）。

## 目的（何を解決するか）

- **無料プレイの基本ループを「現実時間 1日1試合」に縛り、放置系として成立させる**。
  時間スキップを課金で解放する設計（SPEC §5）の土台。
- ただし**シーズン頭の足場作り**として、自チームの最初の 10 試合は連続消化可。
  パラメータ非表示の推測ゲームで「誰が誰だかわからない」まま待たされて飽きるのを防ぐ。
- 端末時刻の改変で完全に防ぐことはしない。「変更 → 確認 → 変更 →…」を毎日繰り返す
  手間がかかれば 99% のユーザーには時間ゲートとして機能する、というスタンス。

## 確定仕様

### 結果確認時刻の設定

- ユーザー設定: **結果確認時刻**（時単位、デフォルト 21:00）
- 設定画面から変更可能。範囲 00:00〜23:00（時のみ、分は常に 0）
- 設定変更しても `lastUnlockAt` は触らない（12h 制約に自然反映）

### onboarding 期間

- **自チームの消化試合数 < 10** の間は常に解禁状態（時間制約 / 広告ともなし）
- 自チームの 10 試合目を消化した瞬間に onboarding 終了
- `selfTeamGamesPlayed` は SeasonController から派生で取得可（既存集計）

### 通常時の解禁判定

```
isViewable(now) =
  isInOnboarding         → true
  hasTimeSkipSub         → true（将来の課金で解放）
  lastUnlockAt == null   → now >= nextUnlockHourOccurrence(now)
  else                   → now >= nextUnlockAt(lastUnlockAt)
```

- `lastUnlockAt` が null の状態（onboarding 直後の 11 試合目）は、次の設定時刻が来たら解禁
- `nextUnlockAt(lastUnlockAt)` = `lastUnlockAt + 12h` 以降で最初に来る「設定時刻ジャスト」

### nextUnlockAt の計算

```dart
DateTime nextUnlockAt(DateTime lastUnlockAt, int unlockHour) {
  final minNext = lastUnlockAt.add(const Duration(hours: 12));
  var candidate = DateTime(minNext.year, minNext.month, minNext.day, unlockHour);
  if (candidate.isBefore(minNext)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}
```

例:
- 解禁 2026-05-27 21:00 → 12h 後 2026-05-28 09:00 → 当日 21:00 を取って 2026-05-28 21:00
- 解禁 2026-05-27 21:00、設定変更で 22:00 に → 12h 後 2026-05-28 09:00 →
  当日 22:00 を取って 2026-05-28 22:00（同日 22:00 で見れる「ズル」が防げる）
- 解禁 2026-05-27 21:00、設定変更で 09:00 に → 12h 後 2026-05-28 09:00 →
  当日 09:00 ジャスト → 2026-05-28 09:00（早朝設定でも翌朝以降）

### 解禁イベントと lastUnlockAt の更新

- isViewable の判定で「Locked → Unlocked」へ遷移した瞬間を「解禁イベント」とする
- 解禁イベントで `lastUnlockAt = nextUnlockAt(...)` を記録（**実際に見た時刻ではなく、解禁時刻ジャスト**）
- onboarding 終了直後の最初の解禁は `lastUnlockAt = 次の設定時刻オカレンス`
- 試合視聴後は state が再び Locked に戻り、次の nextUnlockAt 計算が走る

### 長期放置時の挙動

- 1 週間ログインしなかった場合でも、ログイン時に「1 試合分だけ解禁」
- 貯まった試合をまとめて解禁にはしない（端末時刻改変での全回避を抑止）

### 試合開始ボタンの挙動

| 状態 | ボタン文言 | 押下時 |
|---|---|---|
| onboarding | 「試合結果を確認する」 | 即試合 → 結果画面 |
| 解禁中 | 「試合結果を確認する」 | 広告 → 試合 → 結果画面 |
| 未解禁 | 「試合結果を確認する」（無効化 + サブテキスト） | ダイアログ「N月N日 HH:00 までお待ちください」 |
| サブスク ON | 「試合結果を確認する」 | 広告なし → 試合 → 結果画面 |

未解禁時のダイアログにサブスク誘導を入れるかは要検討（しつこさで逆効果になり得る）。
**チャンク 5 で別途設計判断**。

### デバッグメニュー

- `kDebugMode` 限定で設定画面末尾に「開発者メニュー」セクション
- トグル（**すべてセッション限定、再起動でリセット**）:
  - 「時間制約をスキップ」
  - 「サブスク購入済み（仮）」
  - 「次の試合を強制解禁」
- 永続化しないことで、本番ビルドへの混入リスクを下げる

---

## チャンク分割（5 段階）

各チャンク終了時にゲームが動く状態を維持する。

### チャンク 1: コアロジック + 永続化（UI 動作は変えない）

**目的**: 「今 見れるか」「次はいつ」を計算するロジックと、その状態を永続化する基盤を作る。
ボタンの挙動は変えないので、リリースしても挙動変化なし。

1. **設定モデル拡張** — `unlockHour: int`（デフォルト 21）を追加
   - 永続化対象。JSON に `"unlockHour": 21` のような形で保存
2. **セーブデータ拡張** — `lastUnlockAt: DateTime?`（null = まだ解禁が発生していない）
   - `SeasonController.lastUnlockAt`（または別 holder）として保持
3. **`UnlockGate` 新規クラス** — `lib/engine/season/unlock_gate.dart`
   - `isViewable(now, isInOnboarding, hasTimeSkipSub, lastUnlockAt, unlockHour)`
   - `nextUnlockAt(lastUnlockAt, unlockHour)` — 上記の計算式
   - `nextUnlockHourOccurrence(now, unlockHour)` — onboarding 直後の初回解禁用
   - `tryConsumeUnlock(now, ...)` — Locked→Unlocked 遷移を検出して新しい `lastUnlockAt` を返す
4. **SeasonController 統合**
   - `isInOnboarding` getter（自チーム消化試合数 < 10）
   - `viewable(now)` getter
   - `markGameViewed()` — 試合視聴後の状態遷移
5. **検証**
   - `bin/test_unlock_gate.dart` 新規: 設定変更・12h 制約・放置・onboarding 終了の各シナリオ
   - `bin/test_persist.dart` 拡張: `unlockHour` / `lastUnlockAt` の往復

**成果物**: 既存ボタンは従来通り。`controller.viewable(DateTime.now())` がただしく true/false を返す。

---

### チャンク 2: 試合開始ボタンの挙動切り替え

**目的**: 解禁状態をユーザーから見える形にし、未解禁時は試合に進めなくする。

1. **`StrategyScreen` のボタン分岐**
   - `viewable == true`: 「試合結果を確認する」（既存挙動）
   - `viewable == false`: 「試合結果を確認する」を無効化、下にサブテキスト
     「N月N日 HH:00 までお待ちください」
     - タップでダイアログ表示（詳細メッセージ）
   - onboarding 中はそもそも常時 true なので分岐に乗らない
2. **試合実行後の状態遷移** — 試合が終わって結果画面から戻ったタイミングで `markGameViewed()`
3. **アプリ起動時の UnlockGate 同期** — 再起動時に `now` で再判定（ライフサイクルで `viewable` が更新される）
4. **既存テスト互換** — `test_season.dart` 系は時間制約をバイパス（テスト用フラグで）

**成果物**: 設定 21:00 で「今 21:00 前」だとボタン押せずダイアログが出る。試合視聴後は再ロック。

---

### チャンク 3: 設定画面に「結果確認時刻」追加

**目的**: ユーザーが時刻を変えられる UI。

1. **`SettingsScreen` に時刻ピッカー**
   - 時単位（0〜23）のドロップダウンで十分（30分単位案は不採用）
   - 「結果確認時刻」「毎日この時刻に試合結果が公開されます」程度の説明
2. **保存 → SeasonController 反映 → AutoSaver 永続化**（既存のフローに乗る）
3. **設定変更時の lastUnlockAt は触らない**（nextUnlockAt が再計算されて自然に 12h 制約が効く）

**成果物**: 設定画面で時刻を変更できる。21:00 → 22:00 に変えると次の解禁が翌 22:00 になる。

---

### チャンク 4: デバッグメニュー

**目的**: チャンク 5 とその後の動作確認を楽にする。

1. **`SettingsScreen` 末尾に「開発者メニュー」セクション**
   - `kDebugMode` のときのみ表示
   - 区切り線 + 警告色（再起動でリセットされる旨を明示）
2. **トグル（セッション内 in-memory 状態）**
   - `_skipUnlockGate`: 常に viewable
   - `_pretendSubscribed`: hasTimeSkipSub を強制 true
   - `_forceUnlock`: 1 回だけ次の試合を強制解禁
3. **既存の UnlockGate 計算にフックを差し込む**
   - `UnlockGate(debugFlags: DebugFlags?)` のような形で受け取る
   - 本番ビルドでは DebugFlags は常に null

**成果物**: 開発時はトグル ON で時間制約を無視できる。

---

### チャンク 5: 広告スタブ + サブスクフラグ統合

**目的**: 解禁中の試合進行に広告フローを差し込む。実 SDK 連携は後フェーズだが、画面遷移と
サブスクバイパスは先に完成させる。

1. **広告スタブ画面** — `ad_placeholder_screen.dart`
   - 「広告（仮）」を 3 秒表示後に自動 pop
   - 実 SDK 連携時にここを置き換えるだけで済む構造
2. **解禁中の「試合結果を確認する」押下フロー**
   - onboarding: 直接試合 → 結果画面（広告なし）
   - 通常: 広告スタブ → 試合 → 結果画面
   - サブスク ON: 広告なし
3. **サブスクフラグ（プレースホルダー）**
   - `Settings.hasTimeSkipSub: bool`（デフォルト false）
   - デバッグメニュー（チャンク 4）からトグル可能
   - 実 RevenueCat 連携は将来チャンク
4. **未解禁時のダイアログ仕上げ**
   - サブスク誘導は最小限（「時間スキップで今すぐ見る」リンク 1 行程度）
   - しつこくしない。詳細は実装時に判断

**成果物**: 通常プレイで広告挟まる。サブスクフラグ ON で広告スキップ。実 SDK は未連携。

---

## 着手順 / 注意点

- **チャンク 1 → 2 → 3 が必須コア**。ここまでで「無料 1日1試合」体験が完成する
- **チャンク 4 は 2 の前に着手しても良い**（時間制約スキップが入っていると 2 のテストが楽）。
  実際の作業順としては「1 → 4 → 2 → 3 → 5」が動かしやすいかもしれない
- **チャンク 5 は実 SDK 連携の前提として**画面遷移と分岐ロジックだけ先に固める
- 既存の `bin/test_*` 系（test_season 等）は時間制約をバイパスするフラグを通す
  必要があるか確認（チャンク 2 着手時）
- **端末時刻の改変は対策しない** — そこまで踏み込むユーザーには「どうぞ」の方針

## 関連 SPEC.md セクション

- §コンセプト「パラメータは見せない」 — 推測ゲームの足場として onboarding 10 試合が必要
- §1.1「試合結果の時刻設定・通知」 — ローカルプッシュ通知は別チャンク（本計画外）
- §5「収益化モデル」 — 時間スキップサブスク（+ 広告削除）が将来課金として接続
- §未決定事項「シーズン頭の N 試合は連続プレイ可」 — 本計画で実装

## 関連 memory

- `project_phase_focus`: 「2026-05-03 以降は UI 改善 + リアリティ調整」フェーズ。
  本計画はリアリティ調整から「ゲームループの磨き込み」への移行点
- `feedback_design_decisions_conversational`: 設計判断は地の文で詰める（本計画書も）
