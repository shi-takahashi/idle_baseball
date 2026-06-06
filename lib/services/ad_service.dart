import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob インタースティシャル広告の管理。
///
/// 試合結果確認前に 1 回表示する用途。タップに即応するため、起動時と
/// 表示後の双方で次回ぶんを先読みしておく。広告が間に合わなかった場合は
/// 黙ってスルーする（試合フローは止めない）。
///
/// 広告 ID:
/// - kDebugMode: Google 公式のテスト ID を使用（誤クリックでも課金されない）
/// - リリース: `_productionInterstitialAdUnitIdAndroid` を本番値に差し替える
///
/// iOS は現状未対応（SPEC: Android 優先）。`MobileAds.initialize` 自体は
/// クロスプラットフォームだが、本番 ID と AndroidManifest 設定は Android のみ。
class AdService {
  AdService._();

  static InterstitialAd? _interstitialAd;
  static bool _isLoading = false;
  static bool _initialized = false;

  // Google 公式のテスト用広告ユニット ID（誤タップしても課金されない）。
  // https://developers.google.com/admob/android/test-ads
  static const String _testInterstitialAdUnitIdAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialAdUnitIdIOS =
      'ca-app-pub-3940256099942544/4411468910';

  // 本番のインタースティシャル広告ユニット ID。release ビルドでのみ使用する
  // （kDebugMode 時は上のテスト ID を使うため、開発中に実広告は表示されない）。
  // Android は本番 ID へ差し替え済み（2026-06-06）。
  // iOS は本計画の対象外のため、暫定で Google 公式テスト ID のまま据え置き。
  static const String _productionInterstitialAdUnitIdAndroid =
      'ca-app-pub-4630894580841955/8688279466';
  static const String _productionInterstitialAdUnitIdIOS =
      'ca-app-pub-3940256099942544/4411468910';

  /// 現在のビルド・プラットフォームに応じたインタースティシャル広告 ID。
  /// kIsWeb と未サポートプラットフォームでは空文字を返す。
  static String get _interstitialAdUnitId {
    if (kIsWeb) return '';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return kDebugMode
            ? _testInterstitialAdUnitIdAndroid
            : _productionInterstitialAdUnitIdAndroid;
      case TargetPlatform.iOS:
        return kDebugMode
            ? _testInterstitialAdUnitIdIOS
            : _productionInterstitialAdUnitIdIOS;
      default:
        return '';
    }
  }

  /// AdMob を初期化し、最初のインタースティシャル広告を先読み。
  /// アプリ起動時に 1 度だけ呼ぶ。
  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    await MobileAds.instance.initialize();
    _initialized = true;
    _preloadInterstitial();
  }

  /// 次回表示用の広告をバックグラウンドで読み込む。
  /// 既に読み込み済み・読み込み中なら何もしない。
  static void _preloadInterstitial() {
    if (_interstitialAd != null || _isLoading) return;
    final unitId = _interstitialAdUnitId;
    if (unitId.isEmpty) return;

    _isLoading = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd load failed: ${error.code} ${error.message}');
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// 先読み済みのインタースティシャル広告を表示する。
  ///
  /// - 読み込み済みなら表示し、閉じられたら [onClosed] を呼んで次の広告を先読み
  /// - 未読込・ロード失敗中なら何もせず即 [onClosed] を呼ぶ（試合フローを止めない）
  ///
  /// 呼び出し側は「広告を出すべきかどうか」（onboarding / 広告消しサブスク等）の
  /// 判定を済ませてからこのメソッドを呼ぶ。
  static Future<void> showInterstitial({required VoidCallback onClosed}) async {
    final ad = _interstitialAd;
    if (ad == null) {
      // 未読込なら表示を諦めてフォールスルー。次回のために先読みだけ仕掛ける。
      _preloadInterstitial();
      onClosed();
      return;
    }

    _interstitialAd = null; // 同じ広告を 2 回表示するのは禁止
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
        onClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('InterstitialAd show failed: ${error.code} ${error.message}');
        ad.dispose();
        _preloadInterstitial();
        onClosed();
      },
    );
    await ad.show();
  }
}
