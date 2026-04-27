import 'package:flutter/material.dart';
import '../engine/engine.dart';

/// イニング詳細ダイアログ（次へ/前へで移動可能）
class _InningDetailDialog extends StatefulWidget {
  final GameResult gameResult;
  final HalfInningResult initialHalfInning;
  // 通常打席の表示（番号付き）
  final Widget Function(int displayNumber, AtBatResult atBat) buildAtBatRow;
  // 未完了打席の表示（盗塁死でイニング終了）
  final Widget Function(AtBatResult atBat) buildIncompleteAtBatRow;

  const _InningDetailDialog({
    required this.gameResult,
    required this.initialHalfInning,
    required this.buildAtBatRow,
    required this.buildIncompleteAtBatRow,
  });

  @override
  State<_InningDetailDialog> createState() => _InningDetailDialogState();
}

class _InningDetailDialogState extends State<_InningDetailDialog> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    // 初期位置を探す
    _currentIndex = widget.gameResult.halfInnings.indexWhere(
      (h) =>
          h.inning == widget.initialHalfInning.inning &&
          h.isTop == widget.initialHalfInning.isTop,
    );
    if (_currentIndex < 0) _currentIndex = 0;
  }

  HalfInningResult get _currentHalfInning =>
      widget.gameResult.halfInnings[_currentIndex];

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < widget.gameResult.halfInnings.length - 1;

  void _goToPrevious() {
    if (_hasPrevious) {
      setState(() {
        _currentIndex--;
      });
    }
  }

  void _goToNext() {
    if (_hasNext) {
      setState(() {
        _currentIndex++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final halfInning = _currentHalfInning;
    final topBottom = halfInning.isTop ? '表' : '裏';

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text('${halfInning.inning}回$topBottom (${halfInning.runs}点)'),
          ),
          Text(
            '${_currentIndex + 1}/${widget.gameResult.halfInnings.length}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          // +1 は先頭の守備配置バナー用スロット（表示対象がなければ空）
          itemCount: halfInning.atBats.length + 1,
          itemBuilder: (context, index) {
            // index=0 は守備配置バナー（あれば）
            if (index == 0) {
              if (halfInning.defensiveChangesAtStart.isEmpty) {
                return const SizedBox.shrink();
              }
              return _DefensiveChangesBanner(
                changes: halfInning.defensiveChangesAtStart,
              );
            }
            final atBatIndex = index - 1;
            final atBat = halfInning.atBats[atBatIndex];
            // この打席の前に発生した投手交代・野手交代イベント
            final pitcherChangesBefore = halfInning.pitcherChanges
                .where((c) => c.atBatIndex == atBatIndex)
                .toList();
            final fielderChangesBefore = halfInning.fielderChanges
                .where((c) => c.atBatIndex == atBatIndex)
                .toList();
            // 通常打席の表示番号（未完了打席は除外した番号付け）
            final displayNumber = halfInning.atBats
                    .take(atBatIndex)
                    .where((a) => !a.isIncomplete)
                    .length +
                1;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 野手交代（代打等）は打席直前に表示
                for (final change in fielderChangesBefore)
                  _FielderChangeBanner(event: change),
                // 投手交代
                for (final change in pitcherChangesBefore)
                  _PitcherChangeBanner(event: change),
                if (atBat.isIncomplete)
                  widget.buildIncompleteAtBatRow(atBat)
                else
                  widget.buildAtBatRow(displayNumber, atBat),
              ],
            );
          },
        ),
      ),
      actions: [
        // 前へボタン
        TextButton(
          onPressed: _hasPrevious ? _goToPrevious : null,
          child: const Text('← 前へ'),
        ),
        // 次へボタン
        TextButton(
          onPressed: _hasNext ? _goToNext : null,
          child: const Text('次へ →'),
        ),
        // 閉じるボタン
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

/// 野手交代（代打/代走/守備固め）を示すバナー（攻撃面のみ）
/// 守備配置の変更は別途、次の守備ハーフの冒頭に DefensiveChangesBanner で表示される
class _FielderChangeBanner extends StatelessWidget {
  final FielderChangeEvent event;

  const _FielderChangeBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.lightBlue.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.lightBlue.shade700, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1,
              size: 16, color: Colors.lightBlue.shade900),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style:
                    TextStyle(fontSize: 12, color: Colors.lightBlue.shade900),
                children: [
                  TextSpan(
                    text: '${event.type.displayName}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: event.outgoing.name),
                  const TextSpan(text: ' → '),
                  TextSpan(
                    text: event.incoming.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 守備ハーフ開始時の守備配置変更をまとめて表示するバナー
/// 前の攻撃ハーフで代打・代走が入った結果、このハーフから適用される守備配置を示す
class _DefensiveChangesBanner extends StatelessWidget {
  final List<DefensiveChange> changes;

  const _DefensiveChangesBanner({required this.changes});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.teal.shade600, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, size: 16, color: Colors.teal.shade800),
              const SizedBox(width: 6),
              Text(
                '守備配置',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.teal.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: changes.map((c) {
                final label = c.fromPosition == null
                    // 新規出場
                    ? '${c.player.name} は ${c.toPosition.displayName}'
                    // 移動
                    : '${c.player.name} は ${c.fromPosition!.displayName} → ${c.toPosition.displayName}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    label,
                    style:
                        TextStyle(fontSize: 11, color: Colors.teal.shade900),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 投手交代を示すバナー（イニング詳細の打席間に表示）
class _PitcherChangeBanner extends StatelessWidget {
  final PitcherChangeEvent event;

  const _PitcherChangeBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade700, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, size: 16, color: Colors.amber.shade900),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                children: [
                  const TextSpan(
                    text: '投手交代: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: event.oldPitcher.name),
                  const TextSpan(text: ' → '),
                  TextSpan(
                    text: event.newPitcher.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// スコアボードウィジェット
class ScoreBoard extends StatelessWidget {
  final GameResult gameResult;

  const ScoreBoard({super.key, required this.gameResult});

  // 延長戦も含めた全イニングを表示（通常は9、延長時は10〜12）
  // 9回が収まる範囲では単一テーブルで描画し、収まらない場合は
  // 左:チーム略称 / 中央:イニング(横スクロール) / 右:合計 の3分割レイアウトに切り替える。
  static const double _teamColWidth = 36;
  static const double _inningColWidth = 30;
  static const double _totalColWidth = 40;

  @override
  Widget build(BuildContext context) {
    final inningCount = gameResult.inningScores.length;
    final fullWidth =
        _teamColWidth + _inningColWidth * inningCount + _totalColWidth;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 親から有限の幅が渡らない場合は単一テーブルで描画
            // （延長戦の幅超過は LayoutBuilder で初めて判定できる）。
            final fits = !constraints.hasBoundedWidth ||
                fullWidth <= constraints.maxWidth;
            if (fits) {
              return _buildFullTable(context, inningCount);
            }
            return _buildSplitTable(context, inningCount);
          },
        ),
      ),
    );
  }

  /// 9回までで横幅に収まるケース：1枚のテーブルにまとめて描画
  Widget _buildFullTable(BuildContext context, int inningCount) {
    final awayShort = _displayShortName(gameResult.awayTeam);
    final homeShort = _displayShortName(gameResult.homeTeam);
    return Table(
      border: TableBorder.all(color: Colors.grey.shade300),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(_teamColWidth),
        for (int i = 1; i <= inningCount; i++)
          i: const FixedColumnWidth(_inningColWidth),
        inningCount + 1: const FixedColumnWidth(_totalColWidth),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            _cell(context, '', null),
            for (int i = 1; i <= inningCount; i++) _cell(context, '$i', null),
            _cell(context, '計', null),
          ],
        ),
        TableRow(
          children: [
            _cell(context, awayShort, null, isTeamName: true),
            for (int i = 0; i < inningCount; i++)
              _cell(
                context,
                '${gameResult.inningScores[i].top ?? "-"}',
                _getHalfInning(i + 1, true),
                isClickable: true,
              ),
            _cell(context, '${gameResult.awayScore}', null, isBold: true),
          ],
        ),
        TableRow(
          children: [
            _cell(context, homeShort, null, isTeamName: true),
            for (int i = 0; i < inningCount; i++)
              _cell(
                context,
                gameResult.inningScores[i].bottom != null
                    ? '${gameResult.inningScores[i].bottom}'
                    : 'X',
                _getHalfInning(i + 1, false),
                isClickable: gameResult.inningScores[i].bottom != null,
              ),
            _cell(context, '${gameResult.homeScore}', null, isBold: true),
          ],
        ),
      ],
    );
  }

  /// 横幅に収まらないケース（延長戦など）：2分割レイアウト
  /// - 左：チーム略称（固定）
  /// - 右：各イニング＋合計（横スクロール）
  /// 右側テーブルは左の縦罫線を持たず、隣接する固定列の罫線と重ならないようにしている。
  Widget _buildSplitTable(BuildContext context, int inningCount) {
    final borderColor = Colors.grey.shade300;
    final headerBg = BoxDecoration(color: Colors.grey.shade200);
    final awayShort = _displayShortName(gameResult.awayTeam);
    final homeShort = _displayShortName(gameResult.homeTeam);

    final leftTable = Table(
      border: TableBorder.all(color: borderColor),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {0: FixedColumnWidth(_teamColWidth)},
      children: [
        TableRow(decoration: headerBg, children: [_cell(context, '', null)]),
        TableRow(children: [
          _cell(context, awayShort, null, isTeamName: true),
        ]),
        TableRow(children: [
          _cell(context, homeShort, null, isTeamName: true),
        ]),
      ],
    );

    // 右側＝イニング＋合計をまとめて横スクロールさせる
    final scrollTable = Table(
      // 左の外枠を描かない（左の固定テーブル側の罫線と重ねるため）
      border: TableBorder(
        top: BorderSide(color: borderColor),
        right: BorderSide(color: borderColor),
        bottom: BorderSide(color: borderColor),
        horizontalInside: BorderSide(color: borderColor),
        verticalInside: BorderSide(color: borderColor),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (int i = 0; i < inningCount; i++)
          i: const FixedColumnWidth(_inningColWidth),
        inningCount: const FixedColumnWidth(_totalColWidth),
      },
      children: [
        TableRow(
          decoration: headerBg,
          children: [
            for (int i = 1; i <= inningCount; i++) _cell(context, '$i', null),
            _cell(context, '計', null),
          ],
        ),
        TableRow(
          children: [
            for (int i = 0; i < inningCount; i++)
              _cell(
                context,
                '${gameResult.inningScores[i].top ?? "-"}',
                _getHalfInning(i + 1, true),
                isClickable: true,
              ),
            _cell(context, '${gameResult.awayScore}', null, isBold: true),
          ],
        ),
        TableRow(
          children: [
            for (int i = 0; i < inningCount; i++)
              _cell(
                context,
                gameResult.inningScores[i].bottom != null
                    ? '${gameResult.inningScores[i].bottom}'
                    : 'X',
                _getHalfInning(i + 1, false),
                isClickable: gameResult.inningScores[i].bottom != null,
              ),
            _cell(context, '${gameResult.homeScore}', null, isBold: true),
          ],
        ),
      ],
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          leftTable,
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: scrollTable,
            ),
          ),
        ],
      ),
    );
  }

  /// チーム略称（未設定なら名前先頭1文字を fallback として使用）
  String _displayShortName(Team team) {
    if (team.shortName.isNotEmpty) return team.shortName;
    return team.name.isNotEmpty ? team.name.substring(0, 1) : '';
  }

  HalfInningResult? _getHalfInning(int inning, bool isTop) {
    try {
      return gameResult.halfInnings.firstWhere(
        (h) => h.inning == inning && h.isTop == isTop,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _cell(
    BuildContext context,
    String text,
    HalfInningResult? halfInning, {
    bool isTeamName = false,
    bool isBold = false,
    bool isClickable = false,
  }) {
    final cellContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: isTeamName ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: isTeamName ? 12 : 14,
          color: isClickable ? Colors.blue.shade700 : null,
          decoration: isClickable ? TextDecoration.underline : null,
        ),
      ),
    );

    if (isClickable && halfInning != null) {
      return GestureDetector(
        onTap: () => _showInningDetail(context, halfInning),
        child: cellContent,
      );
    }
    return cellContent;
  }

  void _showInningDetail(BuildContext context, HalfInningResult halfInning) {
    showDialog(
      context: context,
      builder: (context) => _InningDetailDialog(
        gameResult: gameResult,
        initialHalfInning: halfInning,
        buildAtBatRow: _buildAtBatRow,
        buildIncompleteAtBatRow: _buildIncompleteAtBatRow,
      ),
    );
  }

  /// 未完了打席の行（盗塁死でイニング終了した打席）
  Widget _buildIncompleteAtBatRow(AtBatResult atBat) {
    final pitchWidgets = <Widget>[];
    for (int i = 0; i < atBat.pitches.length; i++) {
      final p = atBat.pitches[i];
      if (i > 0) {
        pitchWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('→',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ),
        );
      }
      pitchWidgets.add(_buildPitchChip(p));
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text(
                  '${atBat.batter.name} (打席途中)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                Text(
                  'P: ${atBat.pitcher.name}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '盗塁死でイニング終了',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (pitchWidgets.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 2,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: pitchWidgets,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAtBatRow(int displayNumber, AtBatResult atBat) {
    // 投球経過をウィジェットリストに
    final pitchWidgets = <Widget>[];
    for (int i = 0; i < atBat.pitches.length; i++) {
      final p = atBat.pitches[i];
      if (i > 0) {
        pitchWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('→', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ),
        );
      }
      pitchWidgets.add(_buildPitchChip(p));
    }

    // ランナー状況を文字列に
    final runners = atBat.runnersBefore;
    String runnerStatus;
    if (!runners.hasRunners) {
      runnerStatus = 'ランナーなし';
    } else {
      final bases = <String>[];
      if (runners.first != null) bases.add('一塁');
      if (runners.second != null) bases.add('二塁');
      if (runners.third != null) bases.add('三塁');
      runnerStatus = bases.join('・');
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$displayNumber. ${atBat.batter.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: atBat.result.isHit
                        ? Colors.green.shade100
                        : atBat.result == AtBatResultType.walk
                            ? Colors.blue.shade100
                            : atBat.result == AtBatResultType.reachedOnError
                                ? Colors.red.shade100
                                : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getResultDisplayName(atBat),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: atBat.result.isHit
                          ? Colors.green.shade800
                          : atBat.result == AtBatResultType.walk
                              ? Colors.blue.shade800
                              : atBat.result == AtBatResultType.reachedOnError
                                  ? Colors.red.shade800
                                  : Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // アウトカウント・ランナー・対戦投手
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${atBat.outsBefore}アウト $runnerStatus',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.brown.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'P: ${atBat.pitcher.name}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 投球経過（複数行対応）
            Wrap(
              spacing: 2,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: pitchWidgets,
            ),
            if (atBat.rbiCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '打点: ${atBat.rbiCount}',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                ),
              ),
            // タッチアップ情報
            if (atBat.hasTagUp)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _buildTagUpInfo(atBat.tagUps!),
              ),
            // フィールディングエラー情報
            if (atBat.fieldingError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _buildFieldingErrorInfo(atBat.fieldingError!),
              ),
          ],
        ),
      ),
    );
  }

  /// フィールディングエラー情報を表示
  Widget _buildFieldingErrorInfo(FieldingError error) {
    final posName = error.position.displayName;
    final typeName = error.type.displayName;
    final label = error.runsScored > 0
        ? '$posName$typeName(${error.runsScored}点)'
        : '$posName$typeName';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: Colors.red.shade800,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// タッチアップ情報を表示
  Widget _buildTagUpInfo(List<TagUpAttempt> tagUps) {
    return Wrap(
      spacing: 8,
      children: tagUps.map((tagUp) {
        final target = tagUp.toBase == Base.home ? 'ホーム' : '3塁';
        final isSuccess = tagUp.success;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSuccess ? Colors.purple.shade100 : Colors.red.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${tagUp.runner.name} タッチアップ$target${isSuccess ? '成功' : '失敗(アウト)'}',
            style: TextStyle(
              fontSize: 10,
              color: isSuccess ? Colors.purple.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 打席結果の表示名を取得（打球方向を含む）
  String _getResultDisplayName(AtBatResult atBat) {
    final fieldPos = atBat.fieldPosition;

    // 打球方向がある場合（インプレー結果）
    if (fieldPos != null) {
      final posName = fieldPos.shortName; // 「遊」「右」「中」など

      switch (atBat.result) {
        case AtBatResultType.groundOut:
          return '$posNameゴロ';
        case AtBatResultType.flyOut:
          return '$posNameフライ';
        case AtBatResultType.lineOut:
          return '$posNameライナー';
        case AtBatResultType.single:
          return '${fieldPos.displayName}安'; // 「遊撃安」「右翼安」
        case AtBatResultType.double_:
          return '${fieldPos.displayName}二';
        case AtBatResultType.triple:
          return '${fieldPos.displayName}三';
        case AtBatResultType.homeRun:
          return '本塁打';
        case AtBatResultType.reachedOnError:
          return '$posNameエラー'; // 「遊エラー」「三エラー」
        default:
          return atBat.result.displayName;
      }
    }

    // 打球方向がない場合（三振、四球など）
    return atBat.result.displayName;
  }

  /// 1球の表示チップ（盗塁情報・バッテリーエラー情報を含む）
  Widget _buildPitchChip(PitchResult pitch) {
    Color bgColor;
    Color textColor;

    switch (pitch.type) {
      case PitchResultType.ball:
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case PitchResultType.strikeLooking:
      case PitchResultType.strikeSwinging:
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        break;
      case PitchResultType.foul:
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case PitchResultType.inPlay:
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
        break;
    }

    // 付加情報（盗塁、バッテリーエラー）
    final additionalWidgets = <Widget>[];

    // 盗塁情報がある場合
    if (pitch.steals != null && pitch.steals!.isNotEmpty) {
      additionalWidgets.add(const SizedBox(width: 2));
      additionalWidgets.add(_buildStealChip(pitch.steals!));
    }

    // バッテリーエラー情報がある場合
    if (pitch.batteryError != null) {
      additionalWidgets.add(const SizedBox(width: 2));
      additionalWidgets.add(_buildBatteryErrorChip(pitch.batteryError!));
    }

    if (additionalWidgets.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${pitch.pitchType.shortName}${pitch.speed} ${pitch.type.shortName}',
              style: TextStyle(
                fontSize: 11,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ...additionalWidgets,
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${pitch.pitchType.shortName}${pitch.speed} ${pitch.type.shortName}',
        style: TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// バッテリーエラー情報チップ
  Widget _buildBatteryErrorChip(BatteryError error) {
    final label = error.runsScored > 0
        ? '${error.type.displayName}(${error.runsScored}点)'
        : error.type.displayName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.red.shade600,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: Colors.red.shade900,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 盗塁情報チップ
  Widget _buildStealChip(List<StealAttempt> steals) {
    // 成功と失敗を分類
    final successful = steals.where((s) => s.success).toList();
    final failed = steals.where((s) => s.isOut).toList();

    final labels = <String>[];

    for (final steal in successful) {
      labels.add('${steal.runner.name}盗塁成功');
    }
    for (final steal in failed) {
      labels.add('${steal.runner.name}盗塁失敗');
    }

    if (labels.isEmpty) return const SizedBox.shrink();

    final isSuccess = successful.isNotEmpty && failed.isEmpty;
    final isFailed = failed.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.purple.shade100
            : isFailed
                ? Colors.grey.shade300
                : Colors.purple.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSuccess ? Colors.purple.shade400 : Colors.grey.shade500,
          width: 1,
        ),
      ),
      child: Text(
        labels.join(', '),
        style: TextStyle(
          fontSize: 10,
          color: isSuccess ? Colors.purple.shade800 : Colors.grey.shade800,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
