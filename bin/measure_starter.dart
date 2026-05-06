import 'dart:math';
import 'package:idle_baseball/engine/engine.dart';

/// 先発投手の登板内容を測定:
/// - 平均IP / 完投率
/// - IP 分布（イニング単位）
/// - 降板イニング・理由分布
void main() {
  const numSeasons = 3;
  final ipBuckets = <String, int>{
    '<3IP': 0,
    '3-4IP': 0,
    '4-5IP': 0,
    '5-6IP': 0,
    '6-7IP': 0,
    '7+IP': 0,
  };
  final reasons = <String, int>{};
  final pullInning = <int, int>{};
  int starterStarts = 0;
  int starterCompleteOrLate = 0;
  int totalStarterOuts = 0;
  int firstInningPulls = 0;
  int earlyPulls = 0; // ≤ 3 innings

  for (int s = 0; s < numSeasons; s++) {
    final teams = TeamGenerator(random: Random(100 + s)).generateLeague();
    final schedule = const ScheduleGenerator().generate(teams);
    final controller = SeasonController(
      teams: teams,
      schedule: schedule,
      myTeamId: teams.first.id,
      random: Random(100 + s),
    );
    controller.advanceAll();

    for (final sg in schedule.games) {
      final result = controller.resultFor(sg.gameNumber);
      if (result == null) continue;

      for (final isTop in [true, false]) {
        final defendingTeam = isTop ? result.homeTeam : result.awayTeam;
        final starterId = defendingTeam.pitcher.id;
        starterStarts++;

        // この先発が登板した半イニングを順に走査して outs を加算
        int outs = 0;
        bool pulled = false;
        int? pullAtInning;
        String? pullReason;
        for (final half in result.halfInnings) {
          if (half.isTop != isTop) continue;

          // この半イニング中の交代位置（先発から別投手へ）
          final change = half.pitcherChanges
              .where((c) => c.oldPitcher.id == starterId)
              .toList();

          // この半イニングの先頭通し番号（atBatIndex の基準）
          int baseIdx = 0;
          for (final h in result.halfInnings) {
            if (identical(h, half)) break;
            baseIdx += h.atBats.length;
          }

          if (change.isEmpty) {
            // 投げ切り。次の半イニングへ
            for (final ab in half.atBats) {
              outs += _outsOf(ab);
            }
          } else {
            final ev = change.first;
            final endLocal = ev.atBatIndex - baseIdx;
            for (int i = 0; i < endLocal; i++) {
              outs += _outsOf(half.atBats[i]);
            }
            pulled = true;
            pullAtInning = half.inning;
            pullReason = ev.reason;
            break;
          }
        }

        totalStarterOuts += outs;
        final ip = outs / 3.0;
        if (ip < 3) {
          ipBuckets['<3IP'] = ipBuckets['<3IP']! + 1;
        } else if (ip < 4) {
          ipBuckets['3-4IP'] = ipBuckets['3-4IP']! + 1;
        } else if (ip < 5) {
          ipBuckets['4-5IP'] = ipBuckets['4-5IP']! + 1;
        } else if (ip < 6) {
          ipBuckets['5-6IP'] = ipBuckets['5-6IP']! + 1;
        } else if (ip < 7) {
          ipBuckets['6-7IP'] = ipBuckets['6-7IP']! + 1;
        } else {
          ipBuckets['7+IP'] = ipBuckets['7+IP']! + 1;
        }

        if (!pulled) {
          starterCompleteOrLate++;
        } else {
          reasons[pullReason!] = (reasons[pullReason] ?? 0) + 1;
          pullInning[pullAtInning!] = (pullInning[pullAtInning] ?? 0) + 1;
          if (pullAtInning == 1) firstInningPulls++;
          if (pullAtInning <= 3) earlyPulls++;
        }
      }
    }
  }

  print('===== 先発投手の登板内容（${numSeasons}シーズン） =====');
  print('総先発登板数: $starterStarts');
  print('平均IP: ${(totalStarterOuts / 3.0 / starterStarts).toStringAsFixed(2)}');
  print('降板せずに完投: $starterCompleteOrLate '
      '(${(100.0 * starterCompleteOrLate / starterStarts).toStringAsFixed(1)}%)');
  print('');
  print('IP分布:');
  for (final entry in ipBuckets.entries) {
    final pct = (100.0 * entry.value / starterStarts).toStringAsFixed(1);
    print('  ${entry.key}: ${entry.value} (${pct}%)');
  }
  print('');
  print('初回降板: $firstInningPulls '
      '(${(100.0 * firstInningPulls / starterStarts).toStringAsFixed(1)}%)');
  print('3回までの早期降板: $earlyPulls '
      '(${(100.0 * earlyPulls / starterStarts).toStringAsFixed(1)}%)');
  print('');
  print('降板イニング分布:');
  final sortedInnings = pullInning.keys.toList()..sort();
  for (final inn in sortedInnings) {
    print('  ${inn}回: ${pullInning[inn]}');
  }
  print('');
  print('降板理由分布:');
  final sortedReasons = reasons.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedReasons) {
    print('  ${e.key}: ${e.value}');
  }
}

/// 1 打席で発生したアウト数を概算する
int _outsOf(AtBatResult ab) {
  if (ab.isIncomplete) return 1; // 盗塁死などで打席途中終了
  if (ab.result == AtBatResultType.doublePlay) return 2;
  return ab.result.isOut ? 1 : 0;
}
