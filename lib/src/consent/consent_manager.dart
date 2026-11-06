import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:gma_mediation_applovin/applovin_sdk_api.g.dart';
import 'package:gma_mediation_ironsource/gma_mediation_ironsource.dart';
import 'package:gma_mediation_liftoffmonetize/gma_mediation_liftoffmonetize.dart';
import 'package:gma_mediation_unity/unity_privacy_api.g.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads_logger.dart';

/// Wraps Google UMP (GDPR consent), iOS App Tracking Transparency and the
/// US-privacy signals of the mediation adapters. Every method is safe: errors
/// are logged, never thrown.
class ConsentManager {
  /// Creates a consent manager that logs to [log].
  ConsentManager(this._log);

  final AdsLogger _log;

  /// Requests the latest consent information and shows the UMP consent form
  /// if the user must answer it (EEA/UK users, or US states if configured in
  /// AdMob > Privacy & messaging).
  Future<void> gatherConsent({
    bool? tagForUnderAgeOfConsent,
    bool debugAsEea = false,
    List<String> testDeviceIds = const [],
  }) async {
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
      consentDebugSettings: (debugAsEea && !kReleaseMode)
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: testDeviceIds,
            )
          : null,
    );

    final updated = await _requestConsentInfoUpdate(params);
    if (!updated) {
      // Offline or UMP error: we keep the consent from a previous session
      // (canRequestAds() reads it), which is what Google recommends.
      return;
    }

    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (error != null) {
          _log.error('UMP form error ${error.errorCode}', error.message);
        }
      });
      _log.info('UMP: consent step finished');
    } catch (e, st) {
      _log.error('UMP form failed', e, st);
    }
  }

  Future<bool> _requestConsentInfoUpdate(ConsentRequestParameters params) {
    final completer = Completer<bool>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          if (!completer.isCompleted) completer.complete(true);
        },
        (FormError error) {
          _log.error(
            'UMP consent info update failed ${error.errorCode}',
            error.message,
          );
          if (!completer.isCompleted) completer.complete(false);
        },
      );
    } catch (e, st) {
      _log.error('UMP consent info update threw', e, st);
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _log.error('UMP consent info update timed out');
        return false;
      },
    );
  }

  /// Whether ads may be requested (consent obtained or not required).
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (e, st) {
      _log.error('canRequestAds failed', e, st);
      return false;
    }
  }

  /// Whether a "Privacy settings" entry point must be shown in the game.
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (e, st) {
      _log.error('getPrivacyOptionsRequirementStatus failed', e, st);
      return false;
    }
  }

  /// Shows the UMP privacy options form so the user can change consent.
  Future<void> showPrivacyOptionsForm() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) {
          _log.error(
            'Privacy options form error ${error.errorCode}',
            error.message,
          );
        }
      });
    } catch (e, st) {
      _log.error('Privacy options form failed', e, st);
    }
  }

  /// Shows the iOS App Tracking Transparency prompt if it was never answered.
  Future<void> requestTrackingAuthorization(Duration delay) async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status != TrackingStatus.notDetermined) {
        _log.info('ATT: already answered (${status.name})');
        return;
      }
      // Let the UMP form finish closing / the launch screen finish.
      await Future<void>.delayed(delay);
      final result =
          await AppTrackingTransparency.requestTrackingAuthorization();
      _log.info('ATT: ${result.name}');
    } catch (e, st) {
      _log.error('ATT request failed', e, st);
    }
  }

  /// Forwards the US state privacy ("do not sell") choice to the adapters
  /// that expose a Dart API for it. Must run before `MobileAds.initialize()`.
  ///
  /// GDPR consent is intentionally NOT forwarded: per Google's mediation
  /// guides, every adapter reads it from UMP (TCF / Additional Consent)
  /// automatically, and a hard-coded "true" would be wrong when the user
  /// declined.
  Future<void> forwardUsPrivacy({required bool optOut}) async {
    final consentToSale = !optOut;
    await _safe(
      'ironSource doNotSell',
      () => GmaMediationIronsource().setDoNotSell(optOut),
    );
    await _safe(
      'AppLovin doNotSell',
      () => AppLovinSDKApi().setDoNotSell(optOut),
    );
    await _safe(
      'Unity CCPA consent',
      () => UnityPrivacyApi().setCCPAConsent(consentToSale),
    );
    await _safe(
      'Liftoff CCPA status',
      () => GmaMediationLiftoffmonetize().setCCPAStatus(consentToSale),
    );
    _log.info('US privacy forwarded (optOut=$optOut)');
  }

  Future<void> _safe(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e, st) {
      _log.error('$label failed', e, st);
    }
  }
}
