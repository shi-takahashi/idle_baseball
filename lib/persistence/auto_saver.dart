import 'dart:async';

import '../engine/engine.dart';
import 'save_service.dart';

/// SeasonController の通知を購読して、デバウンス付きで自動保存する。
///
/// `advanceAll` のような連続通知（短時間で大量の `_notify`）でも、
/// 一度の書き込みにまとめる（最後の通知から 500ms 後に書き込み）。
/// 通常の進行（1日進める・編集）では数百ms 後にセーブされるので、
/// アプリを閉じる前の操作はほぼ確実に永続化される。
class AutoSaver {
  final SeasonController controller;
  final SaveService service;
  Timer? _debounce;
  bool _disposed = false;

  AutoSaver(this.controller, this.service) {
    controller.addListener(_onChange);
  }

  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (_disposed) return;
    try {
      await service.save(controller);
    } catch (_) {
      // ベストエフォート。失敗は無視（次回保存で上書きされる前提）。
    }
  }

  /// 待機中のデバウンスを破棄して即座に保存する。
  /// シーズン終了時 / 画面を離れる前など、確実に書き込みたい場面で呼ぶ。
  Future<void> flush() async {
    _debounce?.cancel();
    await _save();
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_onChange);
    _debounce?.cancel();
  }
}
