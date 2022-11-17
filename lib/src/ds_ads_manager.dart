import 'dart:async';

import 'package:ds_ads/src/ds_ads_interstitial.dart';
import 'package:ds_ads/src/ds_ads_native_loader_mixin.dart';
import 'package:ds_ads/src/yandex_ads/export.dart';
import 'package:fimber/fimber.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ds_ads_types.dart';

class DSAdsManager {
  static DSAdsManager? _instance;
  static DSAdsManager get instance {
    assert(_instance != null, 'Call AdsManager(...) to initialize ads');
    return _instance!;
  }

  final _nextMediationWait = const Duration(minutes: 1);

  final _adsInterstitialCubit = DSAdsInterstitial(type: DSAdsInterstitialType.def);
  DSAdsInterstitial? _splashInterstitial;

  static bool get isInitialized => _instance != null;

  static DSAdsInterstitial get interstitial => instance._adsInterstitialCubit;
  static DSAdsInterstitial get splashInterstitial {
    if (instance._splashInterstitial == null) {
      Fimber.i('splash interstitial created');
      instance._splashInterstitial = DSAdsInterstitial(type: DSAdsInterstitialType.splash);
    }
    return instance._splashInterstitial!;
  }

  void disposeSplashInterstitial() {
    _splashInterstitial?.dispose();
    _splashInterstitial = null;
    Fimber.i('splash interstitial disposed');
  }

  var _isAdAvailable = false;
  DSAdMediation? _currentMediation;
  final _mediationInitialized = <DSAdMediation>{};
  /// Was the ad successfully loaded at least once in this session
  bool get isAdAvailable => _isAdAvailable;
  DSAdMediation? get currentMediation => _currentMediation;

  final _eventController = StreamController<DSAdsEvent>.broadcast();

  Stream<DSAdsEvent> get eventStream => _eventController.stream;
  
  final List<DSAdMediation> mediationPriorities;
  final OnPaidEvent onPaidEvent;
  final DSAppAdsState appState;
  final OnReportEvent? onReportEvent;
  final Set<DSAdLocation>? locations;
  final String? interstitialGoogleUnitId;
  final String? interstitialSplashGoogleUnitId;
  final String? nativeGoogleUnitId;
  final String? interstitialYandexUnitId;
  final String? interstitialSplashYandexUnitId;
  final Duration defaultFetchAdDelay;
  final DSNativeAdBannerStyle nativeAdBannerStyle;
  final DSIsAdAllowedCallback? isAdAllowedCallback;

  /// Initializes ads in the app
  /// [onPaidEvent] allows you to know/handle the onPaidEvent event in google_mobile_ads
  /// In [appState] you should pass the [DSAppAdsState] interface implementation, so the ad manager can know the current 
  /// state of the app (whether the subscription is paid, whether the app is in the foreground, etc.).
  /// [nativeAdBannerStyle] defines the appearance of the native ad unit.
  /// If this [locations] set is defined, the nativeAdLocation method and the location parameter can return only one 
  /// of the values listed in [locations].
  /// [onLoadAdError] ToDo: TBD
  /// [onReportEvent] is an event handler for the ability to send events to analytics.
  /// [interstitialUnitId] is the default unitId for the interstitial.
  /// [nativeUnitId] unitId for native block.
  /// [isAdAllowedCallback] allows you to dynamically determine whether an ad can be displayed.
  DSAdsManager({
    required this.mediationPriorities,
    required this.onPaidEvent,
    required this.appState,
    required this.nativeAdBannerStyle,
    this.locations,
    this.onReportEvent,
    this.interstitialGoogleUnitId,
    this.interstitialSplashGoogleUnitId,
    this.nativeGoogleUnitId,
    this.interstitialYandexUnitId,
    this.interstitialSplashYandexUnitId,
    this.isAdAllowedCallback,

    @Deprecated('looks as useless parameter')
    this.defaultFetchAdDelay = const Duration(),
  }) :
        assert(_instance == null, 'dismiss previous Ads instance before init new'),
        assert(mediationPriorities.isNotEmpty, 'mediationPriorities should not be empty'),
        assert(!mediationPriorities.contains(DSAdMediation.google) || interstitialGoogleUnitId?.isNotEmpty == true,
        'setup interstitialGoogleUnitId or remove DSAdMediation.google from mediationPriorities'),
        assert(!mediationPriorities.contains(DSAdMediation.yandex) || interstitialYandexUnitId?.isNotEmpty == true,
        'setup interstitialYandexUnitId or remove DSAdMediation.yandex from mediationPriorities'),
        assert(interstitialYandexUnitId == null || interstitialYandexUnitId.startsWith('R-M-'),
        'interstitialYandexUnitId must begin with R-M-')
  {
    _instance = this;
    unawaited(_tryNextMediation());

    unawaited(() async {
      await for (final event in eventStream) {
        if (event is DSAdsInterstitialLoadedEvent || event is DSAdsNativeLoadedEvent) {
          _isAdAvailable = true;
        }
      }
    }());
  }

  Future<void> dismiss() async {
    _instance = null;
    await DSAdsNativeLoaderMixin.disposeClass();
  }

  @internal
  void emitEvent(DSAdsEvent event) {
    _eventController.sink.add(event);
  }
  
  var _lockMediationTill = DateTime(0);
  
  Future<void> _tryNextMediation() async {
    final DSAdMediation next;
    if (_currentMediation == null) {
      if (_lockMediationTill.isAfter(DateTime.now())) return;
      next = mediationPriorities.first;
    } else {
      if (_currentMediation == mediationPriorities.last) {
        _lockMediationTill = DateTime.now().add(_nextMediationWait);
        _currentMediation = null;
        onReportEvent?.call('ads_manager: no next mediation, waiting ${_nextMediationWait.inSeconds}s', {});
        return;
      }
      final curr = mediationPriorities.indexOf(_currentMediation!);
      next = mediationPriorities[curr + 1];
    }
    
    onReportEvent?.call('ads_manager: select mediation', {
      'mediation': '$next',
    });
    _currentMediation = next;
    if (!_mediationInitialized.contains(next)) {
      _mediationInitialized.add(next);
      switch (next) {
        case DSAdMediation.google:
          await MobileAds.instance.initialize();
          break;
        case DSAdMediation.yandex:
          await YandexAds.instance.initialize();
          break;
      }
      onReportEvent?.call('ads_manager: mediation initialized', {
        'mediation': '$next',
      });
    }
  }
  
  @internal
  Future<void> onLoadAdError(int errCode, String errText, DSAdSource source) async {
    if (errCode == 3) {
      await _tryNextMediation();
    }
  }
  
}
