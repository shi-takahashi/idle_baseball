import 'package:flutter/foundation.dart';

/// 開発時のみ利用するデバッグフラグ。**永続化されず**、アプリ再起動で全てリセット。
///
/// `kDebugMode` 限定の設定画面セクションからトグルする。本番ビルドでは設定画面の
/// 該当セクション自体が非表示なので、フラグは常に初期値（全 false）のまま。
///
/// 「実際に課金していないが各サブスクを購入した状態の動きを確認したい」用途に
/// 限定して 2 つのフラグだけ持つ。仕様詳細は docs/DAILY_GATE_PLAN.md 参照。
class DebugFlags extends ChangeNotifier {
  DebugFlags._();

  /// プロセス内のシングルトン。`DebugFlags.instance.hasTimeSkipSub = true` のように使う。
  static final DebugFlags instance = DebugFlags._();

  /// 時間スキップサブスク購入済みとしてふるまう。
  /// ON で 1日1試合制約が外れ、何度でも試合結果を確認できる扱いになる。
  /// 本物の RevenueCat 連携が入る前のプレースホルダ。
  bool _hasTimeSkipSub = false;
  bool get hasTimeSkipSub => _hasTimeSkipSub;
  set hasTimeSkipSub(bool value) {
    if (_hasTimeSkipSub == value) return;
    _hasTimeSkipSub = value;
    notifyListeners();
  }

  /// 広告消しサブスク購入済みとしてふるまう。
  /// ON で試合結果確認前の全画面広告が表示されなくなる扱いになる。
  /// 時間スキップサブスクとは独立した別商品。
  bool _hasAdRemovalSub = false;
  bool get hasAdRemovalSub => _hasAdRemovalSub;
  set hasAdRemovalSub(bool value) {
    if (_hasAdRemovalSub == value) return;
    _hasAdRemovalSub = value;
    notifyListeners();
  }

  /// 能力開示＆編集サブスク購入済みとしてふるまう。
  /// ON で選手の 1-10 能力値・球速・各球種が表示され、能力編集も可能になる。
  /// OFF（未購入）状態では能力値は非表示で、編集できるのは背番号と投手ロールのみ。
  /// 仕様詳細は SPEC.md §コンセプト「パラメータは見せない」/ §5「収益化モデル」参照。
  bool _hasAbilityDisclosureSub = false;
  bool get hasAbilityDisclosureSub => _hasAbilityDisclosureSub;
  set hasAbilityDisclosureSub(bool value) {
    if (_hasAbilityDisclosureSub == value) return;
    _hasAbilityDisclosureSub = value;
    notifyListeners();
  }
}
