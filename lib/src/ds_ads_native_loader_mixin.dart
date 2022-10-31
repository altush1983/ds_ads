import 'dart:async';

import 'package:ds_ads/ds_ads.dart';
import 'package:ds_ads/src/ds_ads_manager.dart';
import 'package:fimber/fimber.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

typedef NativeAdBuilder = Widget Function(BuildContext context, bool isLoaded, Widget child);

class DSAdNativeLoadedEvent extends DSAdsEvent {
  final Ad ad;

  const DSAdNativeLoadedEvent._({
    required this.ad,
  });
}

class DSAdNativeLoadFailed extends DSAdsEvent {
  const DSAdNativeLoadFailed._();
}

mixin DSAdsNativeLoaderMixin<T extends StatefulWidget> on State<T> {
  final _adKey = GlobalKey();
  bool get isLoaded => _loadedAds[this] != null;

  String? get nativeAdLocation;

  static final _loadedAds = <DSAdsNativeLoaderMixin?, NativeAd>{};

  static double get nativeAdHeight {
    // the same as in res/layout/native_ad_X_light.xml and res/layout/native_ad_X_dark.xml
    switch (DSAdsManager.instance.nativeAdBannerStyle) {
      case NativeAdBannerStyle.style1:
        return 260;
      case NativeAdBannerStyle.style2:
        return 280;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      await for (final event in DSAdsManager.instance.eventStream) {
        if (!mounted) return;
        if (event is DSAdNativeLoadedEvent) {
          final res = _assignAdToMe();
          if (res) {
            setState(() {});
          }
        }
      }
    } ());
    unawaited(fetchAd());
    _assignAdToMe();
  }

  @override
  void dispose() {
    _report(this, 'ads_native: dispose (isLoaded: $isLoaded)');
    _loadedAds[this]?.dispose();
    _loadedAds.remove(this);
    unawaited(fetchAd());
    super.dispose();
  }

  @internal
  static Future<void> disposeClass() async {
    while (_loadedAds.isNotEmpty) {
      await _loadedAds.remove(_loadedAds.keys.first).dispose();
    }
  }

  static void _report(DSAdsNativeLoaderMixin? obj, String eventName, {String? customAdId}) {
    final location = obj?.nativeAdLocation;
    DSAdsManager.instance.onReportEvent?.call(eventName, {
      if (location != null)
        'location': location,
      'adUnitId': customAdId ?? DSAdsManager.instance.nativeUnitId!,
    });
  }

  static void _reportByAd(Ad ad, String eventName) {
    final obj = _loadedAds.entries.firstWhere((e) => e.value == ad).key;
    _report(obj, eventName, customAdId: ad.adUnitId);
  }

  static String _getFactoryId() {
    final String group;
    switch (DSAdsManager.instance.nativeAdBannerStyle) {
      case NativeAdBannerStyle.style1:
        group = 'adFactory1';
        break;
      case NativeAdBannerStyle.style2:
        group = 'adFactory2';
        break;
    }
    switch (DSAdsManager.instance.appState.brightness) {
      case Brightness.light:
        return '${group}Light';
      case Brightness.dark:
        return '${group}Dark';
    }
  }

  static var _isBannerLoading = false;

  static Future<void> fetchAd() async {
    final adUnitId = DSAdsManager.instance.nativeUnitId;
    assert(adUnitId != null, 'Pass nativeUnitId to DSAdsManager(...) on app start');
    if (_loadedAds[null] != null) {
      Fimber.i('ads_native: banner already loaded');
      return;
    }
    if (_isBannerLoading) {
      Fimber.i('ads_native: banner already loading');
      return;
    }
    _report(null, 'ads_native: start loading');
    _isBannerLoading = true;
      await NativeAd(
        factoryId: _getFactoryId(),
        adUnitId: adUnitId!,
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            try {
              _isBannerLoading = false;
              _loadedAds[null] = ad as NativeAd;
              _reportByAd(ad, 'ads_native: loaded');
              DSAdsManager.instance.emitEvent(DSAdNativeLoadedEvent._(ad: ad));
            } catch (e, stack) {
              Fimber.e('$e', stacktrace: stack);
            }
          },
          onAdFailedToLoad: (ad, err) {
            try {
              _isBannerLoading = false;
              _report(null, 'ads_native: failed to load', customAdId: ad.adUnitId);
              DSAdsManager.instance.emitEvent(const DSAdNativeLoadFailed._());
              ad.dispose();
            } catch (e, stack) {
              Fimber.e('$e', stacktrace: stack);
            }
          },
          onPaidEvent: (ad, valueMicros, precision, currencyCode) {
            try {
              DSAdsManager.instance.onPaidEvent(ad, valueMicros, precision, currencyCode, 'nativeAd');
            } catch (e, stack) {
              Fimber.e('$e', stacktrace: stack);
            }
          },
          onAdOpened: (ad) {
            try {
              _reportByAd(ad, 'ads_native: ad opened');
            } catch (e, stack) {
              Fimber.e('$e', stacktrace: stack);
            }
          },
          onAdClicked: (ad) {
            try {
              _reportByAd(ad, 'ads_native: ad clicked');
            } catch (e, stack) {
              Fimber.e('$e', stacktrace: stack);
            }
          },
        ),
        request: const AdRequest(),
      ).load();
  }

  bool _assignAdToMe() {
    final readyAd = _loadedAds[null];
    if (readyAd == null) return false; // No ads ready
    if (isLoaded) return false; // Already assigned
    _loadedAds[this] = readyAd;
    _loadedAds.remove(null);
    return true;
  }

  Widget nativeAdWidget({
    final NativeAdBuilder? builder,
    final bool? showProgress,
  }) {
    if (!DSAdsManager.instance.isAdAvailable) return const SizedBox();
    if (DSAdsManager.instance.appState.isPremium) return const SizedBox();
    final child = SizedBox(
      height: nativeAdHeight,
      child: isLoaded
          ? AdWidget(key: _adKey, ad: _loadedAds[this]!)
          : (showProgress ?? DSAdsManager.instance.defaultShowNativeAdProgress) ? const Center(child: CircularProgressIndicator()) : const SizedBox(),
    );
    if (builder != null) {
      return builder(context, isLoaded, child);
    } else {
      return child;
    }
  }

}