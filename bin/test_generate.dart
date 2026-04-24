import 'dart:math';

import 'package:idle_baseball/engine/engine.dart';

/// 6チーム×25人の自動生成 動作確認
/// - 全150人の名前の重複チェック
/// - 能力値の分布確認
/// - 各チームのラインナップ表示
void main() {
  final generator = TeamGenerator(random: Random(42)); // 再現性のためseed固定
  final teams = generator.generateLeague();

  print('=== 生成結果 ===');
  print('チーム数: ${teams.length}');
  final totalPlayers = teams.fold<int>(
      0, (sum, t) => sum + t.players.length + t.bullpen.length + t.bench.length);
  print('総選手数: $totalPlayers');
  print('');

  // ---- 名前の重複チェック ----
  final allNames = <String>[];
  for (final t in teams) {
    for (final p in t.players) allNames.add(p.name);
    for (final p in t.bullpen) allNames.add(p.name);
    for (final p in t.bench) allNames.add(p.name);
  }
  final uniqueNames = allNames.toSet();
  print('名前の重複: ${allNames.length - uniqueNames.length}件');
  if (allNames.length != uniqueNames.length) {
    final counts = <String, int>{};
    for (final n in allNames) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    for (final entry in counts.entries.where((e) => e.value > 1)) {
      print('  重複: ${entry.key} (${entry.value}回)');
    }
  }
  print('');

  // ---- 能力値の分布 ----
  final meetValues = <int>[];
  final powerValues = <int>[];
  final speedValues = <int>[];
  final controlValues = <int>[];
  final fastballValues = <int>[];
  final avgSpeedValues = <int>[];

  for (final t in teams) {
    for (final p in [...t.players, ...t.bullpen, ...t.bench]) {
      if (p.meet != null) meetValues.add(p.meet!);
      if (p.power != null) powerValues.add(p.power!);
      if (p.speed != null) speedValues.add(p.speed!);
      if (p.control != null) controlValues.add(p.control!);
      if (p.fastball != null) fastballValues.add(p.fastball!);
      if (p.averageSpeed != null) avgSpeedValues.add(p.averageSpeed!);
    }
  }

  print('=== 能力値分布 ===');
  _printStats('ミート', meetValues);
  _printStats('長打力', powerValues);
  _printStats('走力', speedValues);
  _printStats('制球', controlValues);
  _printStats('ストレート質', fastballValues);
  _printStats('平均球速', avgSpeedValues);
  print('');

  // ---- 各チームのラインナップ表示 ----
  for (final team in teams) {
    print('=== ${team.name} (${team.id}) ===');
    print('-- スタメン --');
    for (int i = 0; i < team.players.length; i++) {
      final p = team.players[i];
      print('  ${i + 1}. ${_playerSummary(p)}');
    }
    print('-- 救援投手 --');
    for (final p in team.bullpen) {
      print('     ${_playerSummary(p)}');
    }
    print('-- 控え野手 --');
    for (final p in team.bench) {
      print('     ${_playerSummary(p)}');
    }
    print('');
  }
}

void _printStats(String label, List<int> values) {
  if (values.isEmpty) return;
  final sorted = [...values]..sort();
  final mean = values.reduce((a, b) => a + b) / values.length;
  final median = sorted[sorted.length ~/ 2];
  final min = sorted.first;
  final max = sorted.last;
  // ヒストグラム（1〜10）
  final histo = List<int>.filled(11, 0);
  for (final v in values) {
    if (v >= 1 && v <= 10) histo[v]++;
  }
  final histStr = [
    for (int i = 1; i <= 10; i++) '$i:${histo[i]}'
  ].join(' ');
  print('  $label: 平均${mean.toStringAsFixed(1)} 中央値$median '
      '最小$min 最大$max  [$histStr]');
}

String _playerSummary(Player p) {
  final buf = StringBuffer('#${p.number} ${p.name}');
  if (p.isPitcher) {
    buf.write(' [投${p.effectiveThrows.displayName}]');
    buf.write(' 球速${p.averageSpeed}km');
    buf.write(' 質${p.fastball}');
    buf.write(' 制${p.control}');
    buf.write(' 体${p.stamina}');
    final types = <String>[];
    if (p.slider != null) types.add('スラ${p.slider}');
    if (p.curve != null) types.add('カー${p.curve}');
    if (p.splitter != null) types.add('スプ${p.splitter}');
    if (p.changeup != null) types.add('チェ${p.changeup}');
    buf.write(' (${types.join(',')})');
  } else {
    buf.write(' [${p.effectiveBatsBase.displayName}打]');
    buf.write(' ミ${p.meet}');
    buf.write(' 長${p.power}');
    buf.write(' 走${p.speed}');
    buf.write(' 眼${p.eye}');
    buf.write(' 肩${p.arm}');
    if (p.lead != null) buf.write(' 捕${p.lead}');
    if (p.fielding != null) {
      final fields = p.fielding!.entries
          .map((e) => '${e.key.shortName}${e.value}')
          .join(',');
      buf.write(' 守[$fields]');
    }
  }
  return buf.toString();
}
