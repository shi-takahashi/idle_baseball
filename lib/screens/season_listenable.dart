import 'package:flutter/foundation.dart';

import '../engine/engine.dart';

/// [SeasonController] の進行通知を Flutter の [Listenable] へ変換するアダプタ。
///
/// engine 層に Flutter 依存を持ち込まないため、SeasonController は独自の
/// `addListener`/`removeListener` API を提供している。UI 側でリビルドさせるには
/// [Listenable] が必要なので、この薄いラッパで橋渡しする。
class SeasonListenable extends ChangeNotifier {
  final SeasonController controller;

  SeasonListenable(this.controller) {
    controller.addListener(_handle);
  }

  void _handle() => notifyListeners();

  @override
  void dispose() {
    controller.removeListener(_handle);
    super.dispose();
  }
}
