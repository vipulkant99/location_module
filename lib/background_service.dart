import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      autoStartOnBoot: false,
      notificationChannelId: "location_channel",
      initialNotificationTitle: "Live Location Tracking",
      initialNotificationContent: "App is tracking location in background",
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: null,
    ),
  );
  // Ensure the service is started (safe to call even if autoStart is true)
  try {
    await service.startService();
  } catch (_) {
    // ignore if startService is not supported or already started
  }
}

//
// BACKGROUND TASK
//
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // REQUIRED: register plugins for this background isolate
  DartPluginRegistrant.ensureInitialized();

  // LISTEN FOR STOP EVENT
  if (service is AndroidServiceInstance) {
    service.on("stopService").listen((event) {
      service.stopSelf();
    });

    // Make service foreground immediately
    // service.setAsForegroundService();
  }

  // ❗ DO NOT request permission here — it will CRASH the isolate
  // Permissions should already be granted in the foreground UI

  const settings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 1,
  );

  // Background GPS stream
  Geolocator.getPositionStream(locationSettings: settings).listen((pos) async {
    final lat = pos.latitude;
    final lng = pos.longitude;

    print("BG LOCATION → $lat , $lng");

    geoFencing(lat, lng);

    // Update foreground notification
    // if (service is AndroidServiceInstance) {
    //   await service.setForegroundNotificationInfo(
    //     title: "Live Location Tracking",
    //     content: "Current: $lat , $lng",
    //   );
    // }

    // TODO: Firebase or API update here
  });
}

bool wasInsideFence = false;

void geoFencing(double lat, double lang) {
  double fixLat = 28.4594886;
  double fixLang = 77.0266304;
  int radius = 200;

  double distance = Geolocator.distanceBetween(lat, lang, fixLat, fixLang);

  bool insideFence = distance <= radius;
  print("🔴 $distance $insideFence && $wasInsideFence");

  // ENTERED
  if (insideFence && !wasInsideFence) {
    wasInsideFence = true;
    print("🟢 ENTERED the geofence!");
  } else {
    print("🟢");
  }

  // EXITED
  if (!insideFence && wasInsideFence) {
    wasInsideFence = false;
    print("🔴 EXITED the geofence!");
  } else {
    print("🟢🔴");
  }
}
