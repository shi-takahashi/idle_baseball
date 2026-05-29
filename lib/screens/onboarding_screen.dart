import 'package:flutter/material.dart';

/// オンボーディング1枚分の内容。
class OnboardingPageData {
  final IconData icon;
  final String title;
  final String body;

  const OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// 初回起動時に1度だけ表示するゲーム説明。
///
/// スワイプ式の5枚・スキップ可。ヘルプ画面からも再表示できるよう、
/// ページ内容（[pages]）と画面（[OnboardingScreen]）を分離してある。
const List<OnboardingPageData> onboardingPages = [
  OnboardingPageData(
    icon: Icons.local_fire_department,
    title: 'フェニックスGMへようこそ',
    body: 'あなたは球団フェニックスのオーナー兼GM。\n'
        '目標は、6球団の頂点 ―― リーグ優勝です。',
  ),
  OnboardingPageData(
    icon: Icons.visibility_off,
    title: '選手の「能力値」は表示されません',
    body: '多くの野球ゲームと違い、このゲームでは選手の能力が数字で見えません。\n'
        '現実の監督・GMと同じで、その選手がどれだけの実力かは数字としては'
        'わからない ―― それがこのゲームの一番の特徴です。',
  ),
  OnboardingPageData(
    icon: Icons.insights,
    title: '使って、見極める',
    body: 'では、どう戦うのか。\n'
        'いろいろな選手を実際に起用し、試合結果から「この選手はよく打つ」'
        '「この投手は終盤に崩れる」を見抜いていく。\n'
        'その見極めこそがGMの仕事です。',
  ),
  OnboardingPageData(
    icon: Icons.sports_baseball,
    title: '采配の前半まではあなた、試合中はベンチに任せる',
    body: 'スタメン・打順・守備・ベンチ入り・投手の起用を決めるのがあなたの役割。\n'
        '代打や継投など試合中の細かい采配は自動で進みます。',
  ),
  OnboardingPageData(
    icon: Icons.newspaper,
    title: '毎日やることは、新聞を読むだけ',
    body: 'このゲームに、派手な試合アニメーションはありません。\n'
        'あなたが毎日やるのは、決まった時刻（初期は21:00）に出る結果を、'
        'スポーツ新聞を読む感覚で確認するだけ。\n'
        'ほとんど放置で進むので、生活の時間を取られません。'
        '気になったときだけ、翌日の戦略を変えればOKです。',
  ),
  OnboardingPageData(
    icon: Icons.calendar_today,
    title: 'まずは10試合、じっくり見極めよう',
    body: '試合は1日1回ですが、最初の10試合だけは待たずに連続で'
        '進められます。\n'
        'まずはこの10試合で、自分の選手たちをじっくり観察してみてください。\n\n'
        '※ シーズン後のオフシーズンでは、引退・新人・助っ人で選手が'
        '入れ替わります。毎年戦力を見直しましょう。',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == onboardingPages.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // スキップ（最後のページでは非表示）
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _isLast ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: TextButton(
                  onPressed: _isLast ? null : () => Navigator.of(context).pop(),
                  child: const Text('スキップ'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: onboardingPages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final p = onboardingPages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(p.icon,
                            size: 88, color: theme.colorScheme.primary),
                        const SizedBox(height: 40),
                        Text(
                          p.title,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          p.body,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(height: 1.6),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // ページインジケータ
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < onboardingPages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _isLast ? 'はじめる' : '次へ',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
