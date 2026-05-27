import 'package:idle_baseball/engine/engine.dart';

/// UnlockGate のシナリオ検証。
///
/// 試合内シミュレートは走らせず、純粋に時間ロジックだけを確認する。
void main() {
  int passed = 0;
  int failed = 0;

  void check(String label, bool cond, {String? detail}) {
    if (cond) {
      passed++;
      print('OK  $label');
    } else {
      failed++;
      print('NG  $label${detail != null ? "  (" + detail + ")" : ""}');
    }
  }

  DateTime t(int y, int m, int d, int h, [int min = 0]) =>
      DateTime(y, m, d, h, min);

  // ---- 1. onboarding 中はいつでも viewable、lastUnlockAt は更新されない ----
  {
    final gate = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: null,
      isInOnboarding: true,
      hasTimeSkipSub: false,
    );
    check('onboarding: 朝でも viewable', gate.isViewable(t(2026, 5, 28, 9)));
    check('onboarding: 深夜でも viewable', gate.isViewable(t(2026, 5, 28, 3)));
    check('onboarding: 視聴時 lastUnlockAt は null のまま',
        gate.newLastUnlockAtOnView(t(2026, 5, 28, 10)) == null);
  }

  // ---- 2. サブスク中はいつでも viewable ----
  {
    final gate = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: t(2026, 5, 28, 21),
      isInOnboarding: false,
      hasTimeSkipSub: true,
    );
    check('サブスク: 解禁直後でも viewable',
        gate.isViewable(t(2026, 5, 28, 21, 30)));
    check('サブスク: 12h 未満でも viewable',
        gate.isViewable(t(2026, 5, 29, 5)));
  }

  // ---- 3. post-onboarding 未ブートストラップ（lastUnlockAt = null）---
  //   現実フローでは onboarding 最終戦（game 10）視聴で lastUnlockAt が設定される
  //   ので、この状態は旧セーブ読込等の特殊ケース。null = 即 viewable とする。
  {
    final gate = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: null,
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    check('post-onboarding null: いつでも viewable (未ブートストラップ)',
        gate.isViewable(t(2026, 5, 28, 14)));
    check('post-onboarding 14:00 視聴: lastUnlockAt = 前日 21:00',
        gate.newLastUnlockAtOnView(t(2026, 5, 28, 14)) ==
            t(2026, 5, 27, 21),
        detail: gate.newLastUnlockAtOnView(t(2026, 5, 28, 14)).toString());
  }

  // ---- 3b. onboarding 最終戦を 14:00 に視聴 → ゲーム11 の解禁は当日 21:00 ---
  {
    // game 10 視聴で markGameViewed が走り lastUnlockAt = 前日 21:00 にセット
    final bootstrapped = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: t(2026, 5, 27, 21),
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    check('onboarding 14:00 終了後の 14:00: not viewable (当日 21:00 まで)',
        !bootstrapped.isViewable(t(2026, 5, 28, 14)));
    check('onboarding 14:00 終了後の 21:00: viewable',
        bootstrapped.isViewable(t(2026, 5, 28, 21)));
    check('nextUnlockAt = 当日 21:00',
        bootstrapped.nextUnlockAt(t(2026, 5, 28, 14)) ==
            t(2026, 5, 28, 21));
  }

  // ---- 3c. onboarding 最終戦を 22:30 に視聴 → ゲーム11 は翌日 21:00 ---
  {
    // game 10 視聴で lastUnlockAt = 今日 21:00 にセット
    final bootstrapped = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: t(2026, 5, 28, 21),
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    check('onboarding 22:30 終了後の同日 22:30: not viewable',
        !bootstrapped.isViewable(t(2026, 5, 28, 22, 30)));
    check('onboarding 22:30 終了後の翌日 21:00: viewable',
        bootstrapped.isViewable(t(2026, 5, 29, 21)));
  }

  // ---- 4. 通常時: 直近解禁 21:00 → 翌日 21:00 まで待つ ----
  {
    final gate = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: t(2026, 5, 28, 21),
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    // 21:30: ロック
    check('視聴直後 21:30: not viewable',
        !gate.isViewable(t(2026, 5, 28, 21, 30)));
    // 翌朝 09:00: 12h 経過したが unlockHour まだ未到達 → ロック
    check('翌朝 09:00: not viewable (unlockHour 未到達)',
        !gate.isViewable(t(2026, 5, 29, 9)));
    // 翌 21:00: 解禁
    check('翌 21:00: viewable',
        gate.isViewable(t(2026, 5, 29, 21)));
    check('翌 21:00: nextUnlockAt 一致',
        gate.nextUnlockAt(t(2026, 5, 28, 21, 30)) == t(2026, 5, 29, 21));
  }

  // ---- 5. 設定変更で同日中の再解禁を防ぐ（21:00 → 22:00）----
  {
    // 21:00 で視聴済み、その後設定を 22:00 に変更
    final gate = UnlockGate(
      unlockHour: 22,
      lastUnlockAt: t(2026, 5, 28, 21), // 21時に解禁したまま
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    // 同日 22:00 でも viewable にならない（12h 制約）
    check('21:00 解禁後、設定 22:00 に変更: 同日 22:00 は NG',
        !gate.isViewable(t(2026, 5, 28, 22)));
    // 翌日 22:00 で解禁（min next = 翌日 09:00、設定 22:00 → 翌日 22:00）
    check('21:00 解禁後、設定 22:00 に変更: 翌日 22:00 で OK',
        gate.isViewable(t(2026, 5, 29, 22)));
    check('21:00 解禁後、設定 22:00 に変更: nextUnlockAt = 翌日 22:00',
        gate.nextUnlockAt(t(2026, 5, 28, 22)) == t(2026, 5, 29, 22));
  }

  // ---- 6. 設定変更で早朝にする（21:00 → 09:00）----
  {
    final gate = UnlockGate(
      unlockHour: 9,
      lastUnlockAt: t(2026, 5, 28, 21),
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    // 翌日 09:00 = 12h 経過ジャスト → 解禁
    check('21:00 解禁後、設定 09:00 に変更: 翌日 09:00 で OK',
        gate.isViewable(t(2026, 5, 29, 9)));
    check('21:00 解禁後、設定 09:00 に変更: 翌日 08:00 はまだ NG',
        !gate.isViewable(t(2026, 5, 29, 8)));
  }

  // ---- 7. 長期放置: 1試合分だけ解禁（貯まらない） ----
  {
    final gate = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: t(2026, 5, 25, 21), // 3日前に解禁
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    // 5/28 14:00 にログイン: 既に viewable
    final now = t(2026, 5, 28, 14);
    check('3日放置 → 5/28 14:00 ログイン時 viewable', gate.isViewable(now));
    // 視聴時の lastUnlockAt = now 以前の最も近い 21:00 = 5/27 21:00（前日の 21:00）
    final newLast = gate.newLastUnlockAtOnView(now);
    check('3日放置視聴: 新 lastUnlockAt = 5/27 21:00',
        newLast == t(2026, 5, 27, 21),
        detail: newLast.toString());

    // 視聴後の状態で次のゲートを作る
    final nextGate = UnlockGate(
      unlockHour: 21,
      lastUnlockAt: newLast,
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    // 5/27 21:00 + 12h = 5/28 09:00 → 当日 21:00 で次解禁
    check('1試合視聴後: 次は 5/28 21:00',
        nextGate.nextUnlockAt(now) == t(2026, 5, 28, 21));
    // つまり今日もう1試合は見れない（21:00 まで待つ）
    check('1試合視聴後: 同日内 (5/28 14:00) はもう viewable じゃない',
        !nextGate.isViewable(t(2026, 5, 28, 14)));
  }

  // ---- 8. 設定 00:00 (深夜帯) 動作確認 ----
  {
    final gate = UnlockGate(
      unlockHour: 0,
      lastUnlockAt: t(2026, 5, 28, 0),
      isInOnboarding: false,
      hasTimeSkipSub: false,
    );
    // 5/28 00:00 + 12h = 5/28 12:00 → 次の 00:00 オカレンス = 5/29 00:00
    check('設定 00:00: nextUnlockAt = 翌日 00:00',
        gate.nextUnlockAt(t(2026, 5, 28, 6)) == t(2026, 5, 29, 0));
    check('設定 00:00: 5/28 23:59 はまだ NG',
        !gate.isViewable(t(2026, 5, 28, 23, 59)));
    check('設定 00:00: 5/29 00:00 ジャストで OK',
        gate.isViewable(t(2026, 5, 29, 0)));
  }

  print('');
  print('===== UnlockGate テスト結果 =====');
  print('PASS: $passed / FAIL: $failed');
  if (failed > 0) {
    // exit code 1
    throw StateError('$failed 件 FAIL');
  }
}
