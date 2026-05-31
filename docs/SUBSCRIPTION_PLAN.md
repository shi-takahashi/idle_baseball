# サブスク課金（RevenueCat / Android 先行）実装計画

> 2026-05-29 策定。一気にやらず、本計画書のチェックリストを見ながら数回に分けて進める。
> ロードマップ上は PROGRESS.md「RevenueCat 連携」、SPEC §5「収益化モデル」に相当。
>
> **対象**: まず **Android 版のみ**リリースする前提。iOS（App Store Connect）は後フェーズ。

## 現状（2026-05-29 時点で出来ていること / いないこと）

- ✅ サブスク 3 種類の **UI ゲートは完成**（`DebugFlags` の 3 フラグで機能を出し分け）
- ✅ ショップ画面（`lib/screens/shop_screen.dart`）に 3 種類のカードを静的表示
- ✅ デバッグメニューで各フラグを手動 ON/OFF して動作確認できる
- ❌ **実際の購入処理はゼロ**（`purchases_flutter` / `in_app_purchase` とも pubspec に未追加）
- ❌ Google Play Console での商品定義・決済まわり未着手
- ❌ RevenueCat プロジェクト未作成

→ つまり「機能の出し分け（下流）」は出来ていて、「購入してフラグを立てる（上流）」が丸ごと残っている。

## アプリ名・ストア掲載文言（2026-05-29 確定。文言はいつでも変更可）

**アプリ名（表示名）: `眼力ベースボール 〜放置シミュレーション〜`**

`applicationId`（パッケージ名）は別途固定。**表示名は公開後も変更可**なので、
launch 後に実データを見て調整してよい。

| 項目 | 文言 | 上限 |
|---|---|---|
| アプリ名 | 眼力ベースボール 〜放置シミュレーション〜 | 30字 |
| サブタイトル（iOS） / 短い説明（Android） | 選手の能力は数字で見えない。試合結果から実力を見抜く采配ゲーム | iOS 30 / Android 80 |
| iOSキーワード欄 / Android説明文に散らす | 野球,プロ野球,監督,GM,采配,ドラフト,ペナント,球団経営,シミュレーション,放置 | iOS 100 |

**ネーミングの決定理由（後から迷わないための記録）:**
- `プロ野球` を表示タイトルから外した。実在 NPB（巨人・阪神等）を期待した人が
  架空球団を見てミスマッチ → 星1 → ランキング低下 → 獲得減、の悪循環を避けるため。
  `プロ野球`/`野球` の検索流入はキーワード欄・説明文で拾うので失わない
- `ベースボール` はジャンル語で実在を約束しない安全な表示語
- `シミュレーション` を明記＝**アクションゲームではない**ことを伝える（期待値調整）。
  検索キーワードとしても有効
- `育成` は不採用。本作は選手を鍛える要素がなく（年齢で自動的に成長・衰え）、
  「自分で育てる」を期待した層を呼ぶとミスマッチになる。本質は「育てる」ではなく
  **変動する能力を見抜き続ける**こと（SPEC 設計の柱④）
- `眼力(がんりき)` はユニークなブランド語（同名・類似の野球アプリは不在を確認済み）。
  検索語ではなく、検索結果で振り向かせるフックとして機能

**“裏の顔”（説明文の奥に置く深みの話。表には出さない）:**
- 能力編集サブスク（課金）で選手を自由に作り込めば、自分だけの球団・リーグを
  じっくり再現できる本格シミュレーション、という上級者向けの伸びしろ
- ⚠️ タイトル/サブタイトル/1枚目スクショには出さない。実在球団・実名は書かない
  （法的グレー回避＋「実在プロ野球が出る」期待の再燃を避ける）

**ストア掲載時の注意（フェーズ6で効いてくる）:**
- 1枚目スクショで自軍（フェニックス等）＝「あなただけのオリジナル球団」を明示し、
  実在球団は出ないことを視覚で伝える（ミスマッチ防止の最大レバー）

## 全体像：作業は 3 つの場所に分かれる

| 場所 | 役割 | ひとこと |
|---|---|---|
| **Google Play Console** | サブスク商品の定義・価格・決済・テスター・ビルド配信 | お金のレジ。**必須**（RevenueCat 使っても回避不可） |
| **RevenueCat（管理画面）** | 「この人は今この権利を持っているか」を管理 | 会員名簿の管理人。自前サーバー不要にするための外部サービス |
| **Flutter コード** | 購入処理 + 権利状態を `DebugFlags` の 3 フラグに流し込む | アプリは「会員？」と聞くだけ |

**いいニュース**: アプリの全画面は既に「3 フラグだけ」を見て機能を出し分けている。
よって最後の仕上げは「フラグの供給元を `DebugFlags`（デバッグ用に残す）から RevenueCat の
権利状態に切り替える」だけで、下流の画面ロジックは触らずに済む。

## 3 サブスクと、対応する権利・コード消費箇所

実装時に「どの権利がどの画面を解放するか」を見失わないための対応表。
（Entitlement ID / Product ID は提案。あとで変更可）

| サブスク | Entitlement ID（案） | Play 商品 ID | 既存フラグ | 主な消費箇所 |
|---|---|---|---|---|
| 時間スキップ | `time_skip` | `sub_time_skip` | `DebugFlags.hasTimeSkipSub` | `unlock_gate.dart`（解禁判定）/ 通知 `reevaluate` / 広告判定 |
| 広告非表示 | `ad_removal` | `sub_ad_hidden` | `DebugFlags.hasAdRemovalSub` | `main_season_screen._runNextGame`（広告スキップ） |
| 能力開示＆編集 | `ability_disclosure` | `sub_ability_disclosure` | `DebugFlags.hasAbilityDisclosureSub` | `player_detail_screen` / `player_edit_screen` |

価格はいずれも月額 ¥100 程度（SPEC §5）。自動更新サブスク。

> 2026-05-30: Play Console で 3 商品を作成・有効化済み（フェーズ2 完了）。
> ユーザー表示名「広告削除」→**「広告非表示」**、商品 ID `sub_ad_removal`→**`sub_ad_hidden`** に変更。
> Entitlement ID（RevenueCat 側、フェーズ3 で作成）は `ad_removal` のまま据え置き。
> 内部のフラグ名 `hasAdRemovalSub` も変更しない（Play 商品 ID だけが `sub_ad_hidden`）。

---

## つまずきポイントの予告

迷子になりやすいのは次の 2 つだけ。ここを意識しておく。

1. **フェーズ 3 の「Google Cloud サービスアカウント連携」** — RevenueCat が Play の購入を
   読むための認証設定。手順が長く、権限付与の反映に最大 24〜36 時間かかることがある。
2. **「商品をテストするには、課金ライブラリ入りのビルドがトラックにアップ済みである」必要**
   があること。だからコード下準備（フェーズ 1）を商品作成より先に置いている。

---

## フェーズ分割（各フェーズはセッションをまたいでOK）

### フェーズ 0: お膳立て（事務作業・コードなし）✅ 2026-05-29 完了

Play での販売を始めるための一回限りの登録。コードは触らない。

- [x] Google Play Developer アカウント登録（$25 一回払い）← 2026-05-29 済
- [x] Play Console で**アプリを新規作成**（2026-05-29 済。アプリ名「眼力ベースボール 〜放置シミュレーション〜」/ 無料）
- [x] **決済プロファイル（販売者アカウント）**を作成（2026-05-29 済）。公開ビジネス情報は
      事業者名 `takapps` / サポート `takapps.dev@gmail.com` / 明細名 `TAKAPPS` で登録。
      住所は必須だったため入力済（電話番号は任意のため空欄）
- [x] パッケージ名（applicationId）を確定 = **`com.tak_labs.eye_baseball`**
      （2026-05-29 設定済。`build.gradle.kts` の namespace/applicationId・MainActivity の
      package・ディレクトリまで変更済）。所有ドメイン `tak-labs.com` 由来（ハイフンは
      package 名で不可のため `-`→`_` の正規変換）。RevenueCat / Play 双方で使う。**公開後は変更不可**

**完了の目安**: Play Console に空のアプリ枠があり、販売者プロファイルが「有効」。

---

### フェーズ 1: コード下準備 + 署名付きビルドを内部テストへ ✅ 2026-05-30 完了

商品テストの前提となる「課金ライブラリ入り AAB がトラックに乗っている」状態を作る。

- [x] `pubspec.yaml` に `purchases_flutter` を追加（`^10.2.0`）。`flutter pub get`（2026-05-30 済。`equatable` も間接追加）
- [x] `android/app/build.gradle.kts` の `applicationId` を確定値に（2026-05-29 済）
- [x] **アップロード鍵（署名）** — keytool で新規作成せず、**shift_kobo と同じ keystore を使い回し**
      （`/Users/takahashi-sh/pdf_mate_key.jks`、エイリアス `pdf_mate`）。`key.properties` を
      shift_kobo からコピー、`build.gradle.kts`（Kotlin DSL）に signingConfig を配線
      （key.properties が無い環境では debug 署名にフォールバック）。2026-05-30 済
- [x] `flutter build appbundle --release` が通る（2026-05-30。release 署名を SHA-256 一致で確認:
      `FD:F4:1D:5D:5A:27:86:46:8C:66:E3:BE:05:A9:9E:2B:34:C6:3B:07:D1:8B:AC:5C:26:C3:32:FA:93:30:A3:BF`）
- [x] Play App Signing を有効化して AAB を **内部テスト（Internal testing）トラック**にアップロード
      （2026-05-30。AABアップロード時に自動有効化、公開済み）
- [~] アプリの最低限の必須項目（コンテンツのレーティング、データセーフティ、プライバシー
      ポリシー URL 等）→ **内部テストでは不要だったため未入力。製品版公開時にフェーズ6で対応**

**完了の目安**: 内部テストの招待リンクから実機にインストールできる（中身は現状のままでOK）。
→ 2026-05-30 実機インストール確認済み。

> メモ: ここで広告 SDK（AdMob 本番 ID）も同時に差し替えるかは別途判断。本計画はサブスクに集中。

---

### フェーズ 2: Play Console でサブスク商品を 3 つ作る ✅ 2026-05-30 完了

- [x] 収益化 → 商品 → 定期購入 で 3 商品を作成（上の対応表の Product ID）
  - [x] `sub_time_skip`（時間スキップ）
  - [x] `sub_ad_hidden`（広告非表示）← 当初案 `sub_ad_removal` から変更
  - [x] `sub_ability_disclosure`（能力開示＆編集）
- [x] 各商品に**基本プラン**を追加（自動更新 / 請求期間=毎月 / 価格 ¥100 程度）
- [x] 特典（無料トライアル等）は設定せず（最初は無し）
- [x] 各商品を**有効化**

**完了の目安**: 3 つの定期購入が「有効」。商品 ID を控える。
→ 2026-05-30 完了。確定した Play 商品 ID は上の対応表を参照（`sub_time_skip` /
  `sub_ad_hidden` / `sub_ability_disclosure`）。

---

### フェーズ 3: RevenueCat 設定（外部サービス・管理画面）

#### 背景：なぜ 3 者（RevenueCat / Play Console / Google Cloud）が出てくるのか

ユーザーがアプリでサブスクを買うと決済は Google（Play）が処理するが、アプリ側は
「本当に買ったか / まだ有効か / 解約していないか」を**検証**する必要がある。RevenueCat は
この検証と「誰が今どの権利を持つか」の管理を肩代わりする外部サービス。そのため RevenueCat は
Google に「この購入は有効か？」と**問い合わせる権限**を必要とする。

| 登場人物 | 役割（たとえ） | 持っているもの |
|---|---|---|
| **Play Console** | お店＋レジ | 商品（3 サブスク）・注文・売上 |
| **Google Cloud** | Google API の窓口＋「ロボット社員」の在籍場所 | API の仕組み・サービスアカウント |
| **RevenueCat** | 外部の会員名簿管理人 | ロボットの鍵を使い Google に購入の有効性を問い合わせ |

**なぜ Google Cloud？** Google の購入データ読み取り API は Google Cloud 経由で提供され、
人間でなく**プログラム（RevenueCat のサーバー）が自動で叩く**には「サービスアカウント」という
**ロボット用アカウント**が要る。これは Google Cloud で作る。その **JSON 鍵 = ロボットのパスワード**。
RevenueCat はこの鍵で「あなたの代理（ロボット）」として Google に問い合わせる。

繋ぐのに必要だった 4 つ:
```
① ロボットを作る（Google Cloud）— サービスアカウント作成 → JSON 鍵ダウンロード
② ロボットに権限を与える（Play Console）— 招待 + 売上データの表示 / 注文と定期購入の管理
③ ロボットが叩く API を開通（Google Cloud）— API を 2 つ有効化（下記）
④ RevenueCat に鍵を渡す（RevenueCat）— JSON アップロード
```

#### 実手順（2026-05-30 実施。当初計画からの差分を反映）

- [x] RevenueCat アカウント作成 → **Project** 作成（2026-05-30）
  - クレカ入力は **Add it later でスキップ**（無料枠: 月間トラッキング収益 $2,500 まで無料、
    超過分のみ 1%。固定月額なし。無料開始にクレカ不要）
  - 初回ウィザードの「おすすめセットアップ」（Pro 1 Entitlement + Monthly/Yearly/Lifetime）は
    **我々の 3 独立サブスク設計と違う**ので採用せず、**Go to dashboard で抜けて手動構築**
- [x] Project に **Google Play アプリ**を追加（Apps & providers、パッケージ `com.tak_labs.eye_baseball`）
- [x] **Google Cloud サービスアカウント連携**（つまずきポイント①）← 2026-05-31 完了
  - [x] ① Google Cloud Console でサービスアカウント作成 → **JSON 鍵**をダウンロード
        （鍵は機密。**git 管理下に置かない**）
  - [x] ③-a **Google Play Android Developer API を有効化**（購入・サブスクを読むため）
  - [x] ② Play Console「ユーザーと権限」でサービスアカウントを招待 + 権限付与:
        **「売上データの表示」**（View financial data）+ **「注文と定期購入の管理」**（Manage orders）
        の 2 つ。「管理者（すべての権限）」は付けない（最小権限）
  - [x] ③-b **★当初計画に無かった: Cloud Pub/Sub API も有効化が必要**。RevenueCat の
        save 時に `Google Cloud Pub/Sub API must first be enabled` エラー → Google Cloud の
        「API とサービス → ライブラリ」で **Cloud Pub/Sub API** を有効化（リアルタイム購入通知用）
  - [x] ④ RevenueCat に JSON 鍵をアップロード → Save changes → `App updated successfully`
  - [x] **★3 チェックが全て通った（2026-05-31）。原因は反映ラグではなく権限スコープだった。**
        当初 `subscriptions API` のみ赤（`inappproducts` / `monetization` は青✓）の状態が 30h 続いた。
        真因: Play の権限を**アプリ単位でしか付けていなかった**こと。`inappproducts`/`monetization` は
        アプリ単位で閉じる（商品カタログ参照）ので app 権限で通るが、`subscriptions` は**注文・課金
        （財務）データ**へのアクセスを見ており、Google では財務・注文系の権限は**アカウント単位**での
        付与が前提。Play Console「ユーザーと権限」→ サービスアカウント →「**アカウントの権限**」タブで
        「財務データ・注文の表示」「注文と定期購入の管理」を付け、↻ 再チェックで 3 つとも青✓に。
        ※ 成功チェックはダーク UI で**青い丸✓**（緑ではない）。app 単位の権限は残してよい。
        ※ 次回 iOS / 別アプリでも同じハマりが起きるので、最初からアカウント権限で付けること。
- [x] **Entitlement** を 3 つ作成（`time_skip` / `ad_removal` / `ability_disclosure`）← 2026-05-31 完了。
      Entitlement ID は据え置き（広告非表示でも `ad_removal`。変わったのは Play 商品 ID `sub_ad_hidden` だけ）
- [x] **Product** を 3 つ取り込み（`sub_time_skip:monthly` / `sub_ad_hidden:monthly` /
      `sub_ability_disclosure:monthly`）、それぞれ対応する Entitlement に紐付け ← 2026-05-31 完了。
      3 つとも Published / 1 Entitlement。`:monthly` は Play の base plan ID（`商品ID:base plan` 形式）
- [x] **Offering** `default` を作り、3 つの custom package を載せた ← 2026-05-31 完了。
      package identifier は Entitlement と揃えた（`time_skip` / `ad_removal` / `ability_disclosure`）。
      各 package の Play Store 商品に `:monthly` を紐付け（Test Store 行は空のまま）
- [x] **Android 公開 API キー**を控えた（`goog_nLTktLlkztwXRpguZSSUMLDCsri`）← 2026-05-31。
      公開 SDK キーなのでコード同梱・git 管理 OK。Secret key (`sk_`) はアプリに入れない

**完了の目安**: RevenueCat 上で 3 商品が認識され、Offering にパッケージが並ぶ。

> 当初計画との主な差分:
> - **Cloud Pub/Sub API の有効化が追加で必要**だった（API は計 2 つ有効化）。当初は
>   「Pub/Sub はリアルタイム通知の任意設定」と書いていたが、現行 RevenueCat は credentials の
>   save 自体に Pub/Sub API 有効化を要求する
> - 初回ウィザードのおすすめ構成は不採用（3 独立サブスク設計に合わないため手動構築）
> - 広告非表示の Play 商品 ID は `sub_ad_hidden`（Entitlement ID は `ad_removal` のまま）

---

### フェーズ 4: Flutter コード（購入処理 + フラグ差し替え）

ここで初めて「実際に買えて、機能が解放される」状態になる。

- [ ] 起動時に `Purchases.configure(PurchasesConfiguration(<Android公開APIキー>))`
      （`lib/main.dart` 付近。API キーは公開鍵なのでコード同梱で可）
- [ ] **権利状態の供給源を作る** — RevenueCat の `customerInfo.entitlements.active` を購読し、
      3 フラグ（`time_skip` / `ad_removal` / `ability_disclosure`）を更新する薄い層。
      - 既存の `DebugFlags` は**デバッグ上書き用に残す**。本番では「実購入 OR デバッグ ON」で
        判定するか、本番ビルドでデバッグ層を無効化（`kDebugMode` ガード）
      - 下流（`unlock_gate` / `_runNextGame` / `player_detail` 等）が読む値が
        この供給源に切り替わるように配線
- [ ] ショップ画面（`shop_screen.dart`）を `getOfferings()` ベースに置き換え
      （静的カード → Offering のパッケージ。価格は RevenueCat から取得した表示価格を使う）
- [ ] 「購入する」ボタンで `purchasePackage(...)` → 成功/キャンセル/失敗のハンドリング
- [ ] **「購入を復元」**ボタン（`restorePurchases()`）を設置（再インストール・機種変更対応。
      ストア審査でも実質必須）
- [ ] `addCustomerInfoUpdateListener` で更新を受けて UI を再描画
- [ ] 購入直後・復元直後に通知やゲートを再評価
      （例: 時間スキップ購入で `NotificationScheduler.reevaluate(..., hasTimeSkipSub: true)`）

**完了の目安**: デバッグメニューに頼らず、ショップから購入 → 機能が解放される。

---

### フェーズ 5: テスト（実課金なし）

- [ ] Play Console に**ライセンステスター**を登録（Setup → License testing、テスターの Gmail）
- [ ] テスターを内部テストトラックの**テスター一覧**にも追加
- [ ] テスト購入で確認:
  - [ ] 3 サブスクそれぞれ購入 → 対応機能が解放される
  - [ ] 解約 → 期限後に機能が戻る（テストでは更新間隔が短縮される）
  - [ ] 再インストール後に「購入を復元」で戻る
  - [ ] 時間スキップ購入中は**解禁通知が予約されない**（2026-05-29(2) の修正と整合）
  - [ ] 広告削除購入中は試合前広告が出ない

**完了の目安**: 課金導線が一通り破綻なく回る。

---

### フェーズ 6: 本番公開準備（サブスク以外の必須項目も含む）

- [ ] ストア掲載情報（説明・スクショ・アイコン・フィーチャーグラフィック）
- [ ] データセーフティ / コンテンツレーティング / 対象年齢 / プライバシーポリシー
- [ ] 製品版（Production）トラックへ昇格、段階的公開
- [ ] AdMob 本番 ID 差し替え（未了なら）

**完了の目安**: 製品版として審査提出できる。

---

## 着手順 / 進め方のメモ

- **0 → 1 → 2 → 3 → 4 → 5 → 6 の順が素直**。特に 1（ビルドをトラックへ）を 2 より先に。
- **フェーズ 3 の権限反映待ち**があるので、3 を始めたら反映待ちの間に 4 のコードを書き進めると効率的。
- 1 セッションで 1 フェーズが目安。各フェーズ末で「ゲームは動く / リリースを壊さない」状態を保つ。
- iOS は本計画の対象外。RevenueCat は後から App Store を足せる構造なので、Android 完了後に拡張。

## 関連ドキュメント

- SPEC.md §5「収益化モデル」 — 3 サブスクの狙いと価格方針
- ARCHITECTURE.md §6「広告・課金」 — RevenueCat 採用理由（自前サーバー不要）
- DAILY_GATE_PLAN.md — 時間ゲート / サブスクゲートの**ロジック・UI**（本計画はその「実購入」部分）
- CHANGELOG.md 2026-05-27 — 3 サブスクの UI ゲート実装、2026-05-29(2) — 通知の時間スキップ対応
