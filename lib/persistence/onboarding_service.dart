import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// オンボーディング（初回説明）の既読状態を永続化するサービス。
///
/// セーブデータ（save.json）とは独立した小さなフラグファイルで管理する。
/// 「最初から始める」でセーブを消しても既読状態は保持される
/// （一度説明を見たユーザーに毎回出さない）。
class OnboardingService {
  static const String _fileName = 'onboarding_seen';

  Future<File> _flagFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// オンボーディングを既に見たか
  Future<bool> hasSeen() async {
    final file = await _flagFile();
    return file.exists();
  }

  /// 既読としてマークする
  Future<void> markSeen() async {
    final file = await _flagFile();
    if (!await file.exists()) {
      await file.writeAsString('1', flush: true);
    }
  }
}
