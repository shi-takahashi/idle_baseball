# 開発進捗

## 最終更新: 2026-04-30

## 目標
- 2〜3ヶ月でファーストリリース

> 日付別の詳細実装ログは [CHANGELOG.md](CHANGELOG.md) を参照。
> このファイルはロードマップ・現状サマリ・次の予定に集中させる。

---

## 完了した項目

### Phase 1a: 野球ルールエンジン（基本）
- [x] Flutterプロジェクト作成
- [x] データモデル定義（Player, Team, GameResult等）
- [x] 1球ごとのシミュレーション
- [x] 1打席のシミュレーション
- [x] 走塁処理（単純化版）
- [x] 1イニング・1試合のシミュレーション
- [x] 9イニング固定（投手交代なし、代打なし） → 後に拡張

### Phase 1b: 能力パラメータ
- [x] 投手: 球速 / 制球 / ストレートの質 / スタミナ / 5球種（ストレート・スライダー・カーブ・スプリット・チェンジアップ）
- [x] 投手: 試合ごとのコンディション（±2 ランダム補正）と疲労システム
- [x] 野手: ミート / 長打 / 走力 / 選球眼 / 肩 / 守備力（ポジション別）
- [x] 捕手: リード（被打率にわずかに効く）
- [x] 走力関連: 盗塁・追加進塁・内野安打・併殺回避・タッチアップ
- [x] 守備エラー: ワイルドピッチ・パスボール・フィールディングエラー（ポジション別補正）
- [x] 利き手・打席（プラトーン補正、左打者の一塁近さ、引っ張り傾向）

### Phase 1c: 選手交代
- [x] 投手交代（先発・中継ぎ・抑えの自動運用、ロール別構成）
- [x] 野手交代（代打・代走、守備配置の自動再編）
- [x] 攻撃面（PH/PR）と守備面（DefensiveChange）の分離
- [x] 投手の9番打順化（`Team.players[8]` = 投手の規約）

### Phase 1d: 延長戦・終了判定
- [x] 9回以降の表終了で勝っていれば裏スキップ（X 表示）
- [x] サヨナラ判定
- [x] 12回までの延長 + 引き分け

### Phase 2: シーズン基盤
- [x] チーム・選手の自動生成（6チーム × 29人、ロール別）
- [x] 試合日程生成（3連戦方式、6チーム総当たり、30日90試合）
- [x] シーズン進行（`SeasonController.advanceDay` / `advanceAll`）
- [x] 順位表 / 個人成績 / 試合結果の集計（勝敗投手・セーブ・ホールド・自責点）
- [x] 失点の責任投手追跡（インヘリット走者対応）

### Phase 3: 1シーズンの磨き込み（進行中）

**シミュレート精度:**
- [x] 先発ローテーション（中4日縛り + エースバイアス）
- [x] リリーフ運用（球数・イニング境界での交代、ロール別優先度）
- [x] セーブ・ホールド判定 + 抑えの起用法
- [x] 失点 / 自責点の区別（エラー由来は不自責）
- [x] 防御率を自責点ベースに修正
- [x] 投手の打撃成績集計バグ修正（投手も BatterSeasonStats に登録）
- [x] 投手の打撃過剰バグ修正（HR 確率の正規化）
- [x] 盗塁過多バグ修正 + NPB 水準への調整
- [x] スタメンの日々変動（伝統的日本式打順 + 調子による組み替え + ベンチ入れ替え）
- [x] 野手の調子（隠しパラメータ、Markov 遷移で複数日持続）
- [x] 送りバントの実装（投手・弱打者中心、`sacrificeBunt` / `fieldersChoice`）

**UI:**
- [x] スコアボード（チーム英字略称、9回まで1画面、延長は2分割）
- [x] 打撃成績・投手成績の選手列固定 + 横スクロール
- [x] 順位表の固定列 + 指標追加（打率・本塁打・盗塁・防御率・失策）
- [x] 下部ナビバー（試合 / 順位表 / 個人成績 / チーム の4タブ）
- [x] 「翌日へ」バー常駐
- [x] チームカラー導入（バナー・タブ・チップに反映）
- [x] スコアタブの試合サマリー（勝敗投手・セーブ・本塁打第N号）
- [x] 個人成績ランキングのタイ対応（同値同順位 + 全員表示）
- [x] チーム別成績画面（チーム一覧 → 全選手成績、左固定列に打率/防御率併記）
- [x] 選手能力詳細画面（チーム → 選手一覧 → 選手詳細、メーター可視化）
- [x] 選手能力編集画面（スライダー＋トグル、`SeasonController.updatePlayer` で全参照差し替え）
- [x] チーム基本情報の表示・編集画面（チーム名 / 略称 / カラー、`SeasonController.updateTeam` で in-place 更新）

**残課題:**
- [ ] 犠飛の判定を厳密化（外野フライで打点ありを全て犠飛扱いにしている）
- [ ] 個人「得点」の集計（本塁を踏んだ選手を追跡）
- [ ] ラウンド順のシャッフル（前半・後半で対戦順を変える）
- [ ] リーグ全体の確率調整（K率・打率を NPB 水準に近づける）
- [ ] バント発生数のチューニング（現状やや多め）

---

## 次回の予定

### 主テーマ
- データ永続化（Hive または Isar）でシーズンの中断・再開
- 選手編集機能のサブスク連携（現状は誰でも編集可能、課金実装時にゲート）

### その他の優先項目（着手順は柔軟）
- スタメン / 投手起用のユーザー操作（翌日のラインナップ・先発を編集）
- 時間経過による試合進行（放置系の要）

### Phase 4 以降（将来）
- ドラフト、海外選手獲得、トレード、引退 → 複数シーズン化
- 広告（AdMob）と課金（RevenueCat: 広告削除・チームエディット・時間スキップ）
- Google Play 公開（後日 App Store）

---

## ファイル構成

```
lib/
├── main.dart                          # エントリーポイント
├── screens/
│   ├── home_screen.dart               # ホーム画面（[シーズン開始]）
│   ├── main_season_screen.dart        # シーズン中の親画面（NavigationBar + 翌日へ常駐）
│   ├── season_listenable.dart         # SeasonController を Flutter Listenable に変換
│   ├── daily_screen.dart              # 1日の試合結果（自チーム試合 + 他2試合サマリー）
│   ├── game_result_screen.dart        # 1試合詳細（外部から GameResult を受け取る）
│   ├── standings_screen.dart          # 順位表画面
│   ├── individual_stats_screen.dart   # 個人成績ランキング（タイ対応）
│   ├── team_list_screen.dart          # チーム一覧（チームタブのルート）
│   ├── team_stats_screen.dart         # チーム別の全選手成績
│   ├── player_list_screen.dart        # チーム所属選手一覧（先発/救援/野手/控え）
│   ├── player_detail_screen.dart      # 選手1人の能力パラメータ詳細
│   ├── player_edit_screen.dart        # 選手能力の編集（スライダー＋トグル）
│   ├── team_info_screen.dart          # チーム基本情報の表示
│   └── team_edit_screen.dart          # チーム名・略称・カラーの編集
├── widgets/
│   ├── score_board.dart               # スコアボード（9回時単一テーブル / 延長時 2分割固定）
│   ├── batting_stats.dart             # 打撃成績（左:選手固定 / 右:位置〜イニング横スクロール）
│   ├── pitching_stats.dart            # 投手成績（左:選手固定 / 右:成績横スクロール）
│   └── game_summary_view.dart         # 勝敗投手・セーブ・本塁打のサマリー表示
└── engine/
    ├── models/                        # データモデル
    │   ├── enums.dart                 # 列挙型（打球方向、守備位置、利き手、ReliefRole 等）
    │   ├── player.dart                # 選手（能力パラメータ・利き手・打席・reliefRole）
    │   ├── team.dart                  # チーム（players[0..7]=野手1〜8番、players[8]=投手9番）
    │   ├── pitcher_condition.dart     # 投手の調子（試合ごとのランダム補正）
    │   ├── base_runners.dart          # ランナー状態（盗塁含む）
    │   ├── error_models.dart          # エラーモデル
    │   ├── pitch_result.dart          # 投球結果
    │   ├── at_bat_result.dart         # 打席結果
    │   ├── pitcher_change.dart        # 投手交代イベント
    │   ├── fielder_change.dart        # 野手交代イベント + DefensiveChange
    │   ├── game_result.dart           # 試合結果
    │   └── models.dart                # エクスポート
    ├── simulation/                    # 試合ロジック
    │   ├── at_bat_simulator.dart      # 打席シミュレーション + simulateBuntAtBat
    │   ├── game_simulator.dart        # 試合シミュレーション
    │   ├── steal_simulator.dart       # 盗塁シミュレーション
    │   ├── error_simulator.dart       # エラーシミュレーション
    │   ├── bunt_decision_strategy.dart # 送りバントの試行判定
    │   ├── team_pitching_state.dart   # 投手運用状態
    │   ├── team_fielding_state.dart   # 野手運用状態（ラインナップ・守備配置）
    │   ├── pitcher_change_strategy.dart # 投手交代戦略
    │   ├── fielder_change_strategy.dart # 野手交代戦略（代打・代走）
    │   └── simulation.dart            # エクスポート
    ├── generators/                    # 選手・チーム自動生成
    │   ├── name_data.dart             # 苗字・名前リスト
    │   ├── random_utils.dart          # 正規分布ヘルパー
    │   ├── player_generator.dart      # 選手生成
    │   ├── team_generator.dart        # チーム生成（6チーム）
    │   └── generators.dart            # エクスポート
    ├── season/                        # シーズン（日程・集計・進行）
    │   ├── scheduled_game.dart        # 1試合の予定
    │   ├── schedule.dart              # 試合日程
    │   ├── schedule_generator.dart    # サークル法で3連戦スケジュール生成
    │   ├── standings.dart             # 順位表（TeamRecord, Standings）
    │   ├── player_season_stats.dart   # 選手シーズン成績（sacrificeBunts 等含む）
    │   ├── season_aggregator.dart     # 試合結果の集計
    │   ├── season_simulator.dart      # 一括シーズンシミュレート
    │   ├── season_controller.dart     # 1日ずつ進める可変状態コントローラ
    │   ├── season_result.dart         # シーズン結果のコンテナ
    │   ├── game_summary.dart          # 試合サマリー
    │   ├── recent_form.dart           # 直近30打席ローリング窓・OPS算出（打順決定用）
    │   ├── lineup_planner.dart        # 当日の打順 + 守備配置を決定
    │   ├── batter_condition.dart      # 野手の調子（隠しパラメータ、Markov）
    │   └── season.dart                # エクスポート
    └── engine.dart                    # エクスポート

bin/                                    # 動作確認用スクリプト（dart run）
├── test_game.dart                      # 1試合シミュレート
├── test_generate.dart                  # 選手・チーム生成の確認
├── test_schedule.dart                  # 試合日程生成の確認
├── test_season.dart                    # シーズン全試合のシミュレート
├── test_extra_innings.dart             # 延長戦動作確認
├── test_rotation.dart                  # 先発ローテ・登板間隔・ブルペン使用状況
├── test_save.dart / test_save_multi.dart # セーブ集計
├── test_roles.dart                     # ロール別の登板・成績集計
├── test_inherited_runs.dart            # インヘリット失点の検証
├── test_earned_runs.dart               # 自責点・防御率の検証
├── test_pitcher_batting.dart           # 投手の打撃成績検証
├── test_pitcher_stats.dart             # 投手の打撃ステータス個別表示
├── test_game_summary.dart              # GameSummary の出力確認
├── test_lineup.dart                    # 打順変動 + 野手調子の推移確認
├── test_bunt.dart                      # 送りバント発生数・統計整合の確認
└── （その他、機能ごとの検証スクリプト）

docs/
├── SPEC.md              # 仕様書
├── ARCHITECTURE.md      # 技術設計書
├── DEVELOPMENT_ORDER.md # 開発順序
├── PROGRESS.md          # 進捗（このファイル）
└── CHANGELOG.md         # 日付別の実装ログ
```

---

## 決定事項

| 項目 | 決定 |
|------|------|
| 技術スタック | Flutter |
| データ保存 | ローカルのみ（引き継ぎなし） |
| 課金基盤 | RevenueCat |
| 課金形態 | 月額サブスク（100〜500円） |
| 自前サーバー | 不要 |
| 投手の打順 | 9番固定（DH 非採用） |

---

## 短いメモ

- 打者一巡時はカンマ区切りで表示（例: `安打, 三振`）
- 2アウトでゴロアウト時は得点が入らないよう修正済み
- 球速は毎球±5kmの変動（中央寄りの分布）
- 野手の調子は隠しパラメータ（UIには出さない）。RecentForm（成績ベース）と役割分担済み
