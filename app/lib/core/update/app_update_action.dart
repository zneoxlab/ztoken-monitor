import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_action_factory_stub.dart'
    if (dart.library.io) 'app_update_action_factory_io.dart';
import 'app_update_action_types.dart';

export 'app_update_action_types.dart';

final appUpdateActionProvider = Provider<AppUpdateAction>((ref) {
  return createAppUpdateAction();
});

final appUpdateAvailabilityProvider = Provider<AppUpdateAvailability>((ref) {
  return createAppUpdateAvailability();
});
