// unit tests for google play update flow selection
// keeps native update checks deterministic without opening platform ui

import 'package:echoproof/core/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';

void main() {
  group('app update flow selection', () {
    test('returns none when google play reports no update', () {
      final info = _info();

      expect(AppUpdateService.selectFlow(info), AppUpdateFlow.none);
    });

    test('completes a downloaded flexible update before native flows', () {
      final info = _info(
        availability: UpdateAvailability.updateAvailable,
        installStatus: InstallStatus.downloaded,
        immediateAllowed: true,
        flexibleAllowed: true,
      );

      expect(
        AppUpdateService.selectFlow(info),
        AppUpdateFlow.completeDownloaded,
      );
    });

    test('resumes developer triggered immediate updates', () {
      final info = _info(
        availability: UpdateAvailability.developerTriggeredUpdateInProgress,
      );

      expect(AppUpdateService.selectFlow(info), AppUpdateFlow.immediate);
    });

    test('uses immediate flow when google play allows it', () {
      final info = _info(
        availability: UpdateAvailability.updateAvailable,
        immediateAllowed: true,
      );

      expect(AppUpdateService.selectFlow(info), AppUpdateFlow.immediate);
    });

    test('uses required sheet for flexible or store fallback flows', () {
      final flexibleInfo = _info(
        availability: UpdateAvailability.updateAvailable,
        flexibleAllowed: true,
      );
      final fallbackInfo = _info(
        availability: UpdateAvailability.updateAvailable,
      );

      expect(
        AppUpdateService.selectFlow(flexibleInfo),
        AppUpdateFlow.requiredSheet,
      );
      expect(
        AppUpdateService.selectFlow(fallbackInfo),
        AppUpdateFlow.requiredSheet,
      );
    });
  });
}

AppUpdateInfo _info({
  UpdateAvailability availability = UpdateAvailability.updateNotAvailable,
  InstallStatus installStatus = InstallStatus.unknown,
  bool immediateAllowed = false,
  bool flexibleAllowed = false,
}) {
  return AppUpdateInfo(
    updateAvailability: availability,
    immediateUpdateAllowed: immediateAllowed,
    immediateAllowedPreconditions: const <int>[],
    flexibleUpdateAllowed: flexibleAllowed,
    flexibleAllowedPreconditions: const <int>[],
    availableVersionCode: availability == UpdateAvailability.updateNotAvailable
        ? null
        : 38,
    installStatus: installStatus,
    packageName: 'com.echoproof.app',
    clientVersionStalenessDays: null,
    updatePriority: 0,
  );
}
