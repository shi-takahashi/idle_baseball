import 'package:flutter/material.dart';

import 'onboarding_screen.dart';

/// ヘルプ画面（遊び方）。
///
/// このゲームは「能力値非表示・アニメなし・放置系」という独特な設計のため、
/// 初回オンボーディングだけでは伝わりにくい点を補う。構成は 2 段:
///   1. オンボーディング（ゲームの特徴 6 枚）の再閲覧
///   2. よくある疑問（[_faqs]）を折りたたみで個別に解説
///
/// 入口はホーム画面と作戦タブの AppBar の `?` アイコン。設定とは独立。
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  /// 各タブの AppBar `actions` に置く共通のヘルプボタン。
  /// タップで [HelpScreen] を push する。
  static Widget appBarAction(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: '遊び方',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('遊び方'), backgroundColor: theme.colorScheme.inversePrimary),
      body: ListView(
        children: [
          // ── ゲームの特徴をもう一度（オンボーディング再閲覧） ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.auto_stories, color: theme.colorScheme.primary),
                title: const Text('ゲームの特徴をもう一度見る'),
                subtitle: const Text('最初に表示された説明をいつでも読み返せます。'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // 既読フラグ（markSeen）には触れず表示するだけ。
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                },
              ),
            ),
          ),
          const _SectionHeader(title: 'よくある疑問'),
          for (final faq in _faqs) _FaqTile(faq: faq),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Faq {
  final IconData icon;
  final String question;
  final String answer;
  const _Faq({required this.icon, required this.question, required this.answer});
}

/// よくある疑問のたたき台。文言はゲームの設計（能力非表示・推測・放置）に沿う。
const List<_Faq> _faqs = [
  _Faq(
    icon: Icons.visibility_off,
    question: 'なぜ選手の能力値が見えないの？',
    answer:
        'このゲームでは、選手の「打力」「走力」「守備力」といった能力が'
        '数字で表示されません。これはバグや未完成ではなく、一番の特徴です。\n\n'
        '現実の監督・GMも、選手の実力を数字で見ているわけではありません。'
        '練習や試合の結果を見て「この選手は打てる」「この投手は終盤に崩れる」と'
        '判断しています。このゲームも同じで、試合結果から実力を推測して采配する'
        'こと自体を楽しむ作りになっています。\n\n'
        '※ 守れるポジション・利き腕／打席・年齢は、采配の前提になるので表示されます。',
  ),
  _Faq(
    icon: Icons.insights,
    question: 'どうやって選手の実力を見極めるの？',
    answer:
        'いろいろな選手を実際に起用し、試合結果を積み重ねて推測します。\n\n'
        '・本塁打が多い → 長打力が高そう\n'
        '・四球が多い → 選球眼が良さそう\n'
        '・盗塁や内野安打が多い → 走力が高そう\n'
        '・先発させると中盤で崩れて早く降板する → スタミナ不足。リリーフ向きかも\n\n'
        'シーズン頭の最初の10試合は待たずに連続で進められます。'
        'まずはこの期間で、自分の選手たちをじっくり観察してみてください。',
  ),
  _Faq(
    icon: Icons.newspaper,
    question: '試合結果はどこを見ればいい？',
    answer:
        '試合は毎日決まった時刻（初期は21:00）に1試合だけ自動で進みます。'
        'やることは、出た結果をスポーツ新聞を読む感覚で確認するだけです。\n\n'
        '・スコアボード … 各イニングの得点\n'
        '・個人成績 … 打率・本塁打・防御率などの打撃／投手成績\n'
        '・打席ごとの詳細 … どの投手 vs どの打者で、何が起きたか\n\n'
        'この積み重ねが、選手の実力を見極める手がかりになります。',
  ),
  _Faq(
    icon: Icons.sports_baseball,
    question: '自分は何を操作するの？',
    answer:
        '試合前の采配を決めるのがあなたの役割です。\n\n'
        '・スタメンと打順\n'
        '・守備配置（守れないポジションに置くと失策が増えます）\n'
        '・ベンチ入りメンバー\n'
        '・先発投手と、各投手の「ロール」\n\n'
        '代打・継投など試合中の細かい采配は自動で進みます。'
        '気になったときだけ、翌日の作戦を変えればOKです。',
  ),
  _Faq(
    icon: Icons.shield_moon,
    question: '投手の「ロール」って何？ ベンチ入りはどう決める？',
    answer:
        '投手には先発／中継ぎ／セットアッパー／抑えなどのロールを設定できます。'
        '「この投手は球が速いから抑え」というように、試合結果から推測して'
        '起用を決めるのも采配の楽しみです。開幕時は中立な初期ロールから始まります。\n\n'
        '先発／中継ぎの区分は固定ではなく、全20投手から自由に選べます。'
        '先発させたい投手はベンチ入りさせずに休ませておきましょう。\n\n'
        'ただし先発は中4日以上（前回登板から5日以上）あけないと先発できません。'
        '連投や疲れの残った状態での先発はできないので、ローテーションを意識して'
        '起用しましょう。',
  ),
  _Faq(
    icon: Icons.ac_unit,
    question: 'オフシーズンでは何が起きる？',
    answer:
        'シーズンが終わると、新人・助っ人外国人選手の獲得で'
        '選手が入れ替わります。引退する選手、伸びてくる若手、当たり外れのある'
        '助っ人外国人 ―― 毎年、戦力を見直す必要があります。\n\n'
        '助っ人外国人は、シーズン終了時に強制的に離脱することがあります。'
        'その場合は、新しい外国人選手を補充してから次シーズンに進みましょう。\n\n'
        '※ 設定で「オフシーズン進行」をOFFにすると、加齢・引退・新人加入をスキップし、'
        '同じ選手のまま次シーズンを始められます。',
  ),
  _Faq(
    icon: Icons.event_note,
    question: '1シーズンの試合数は選べる？',
    answer:
        '新しくシーズンを開始するときに、1シーズンの試合数を'
        '30・90・150試合から選べます（初期は30試合）。\n\n'
        '試合数が多いほど、選手の成績が実力どおりに近づき、'
        'じっくり見極めやすくなります。短く気軽に1シーズンを回したいときは'
        '30試合がおすすめです。',
  ),
  _Faq(
    icon: Icons.storefront,
    question: 'ショップのサブスクで何が変わる？',
    answer:
        '・時間スキップ … 1日1試合を待たず、続けて結果を確認できます。\n'
        '・広告非表示 … 結果確認前の全画面広告を非表示にします。\n'
        '・能力開示＆編集 … 選手の能力値を表示し、自由に編集できます。'
        '数字を見て最適な打順を組みたい人や、自由にデータを書き換えてシミュレーションを楽しみたい人向け。\n'
        '(チームの選手一覧から各選手を選ぶと、その選手の能力が表示されます。'
        'さらに右上の鉛筆マークを押すと、能力を編集できます)\n\n'
        '3つは独立して購入でき、組み合わせるほど自由に遊べます。',
  ),
];

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      leading: Icon(faq.icon, color: theme.colorScheme.primary),
      title: Text(faq.question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(faq.answer, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6))],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
