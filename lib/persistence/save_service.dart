import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engine/engine.dart';

/// セーブデータをローカルストレージに永続化するサービス。
///
/// アプリの ApplicationDocuments ディレクトリ配下に `save.json` を 1 ファイル置く。
/// 全状態を JSON でまとめて書き込む（whole-file write）。
/// 想定セーブ頻度（試合進行時・編集時）であれば I/O コストは問題にならない。
class SaveService {
  static const String _fileName = 'save.json';

  /// 保存先ファイルのパスを返す
  Future<File> _saveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 既存セーブが存在するか
  Future<bool> hasSave() async {
    final file = await _saveFile();
    return file.exists();
  }

  /// SeasonController を JSON 形式で保存する
  Future<void> save(SeasonController controller) async {
    final file = await _saveFile();
    final json = controller.toJson();
    final encoded = jsonEncode(json);
    // 中断時に空ファイルが残らないよう、temp に書いてから rename
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoded, flush: true);
    await temp.rename(file.path);
  }

  /// 既存セーブを読み込んで SeasonController を復元する。
  /// セーブがなければ null を返す。
  /// バージョン違いや破損時は [FormatException] を伝播させる（呼び出し側で削除判断）。
  Future<SeasonController?> load() async {
    final file = await _saveFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return SeasonController.fromJson(json);
  }

  /// セーブファイルを削除する
  Future<void> delete() async {
    final file = await _saveFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
