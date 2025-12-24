**Project Summary**: POC for continuous live location tracking (keeps running when app is minimized) and geofencing.

**Packages (required)**

- `flutter_background_service` : background service/isolate management
- `flutter_background_service_android` : Android foreground-service helper
- `geolocator` : location stream + permission helpers
- `flutter_osm_plugin` : map UI (optional for map display)
- `http` : network requests (optional)

**Android permissions (add to AndroidManifest.xml)**

- **Foreground & core**: `android.permission.FOREGROUND_SERVICE`
- **Location**: `android.permission.ACCESS_FINE_LOCATION` and `android.permission.ACCESS_COARSE_LOCATION`
- **Background location** (required for continuous tracking on Android 10+): `android.permission.ACCESS_BACKGROUND_LOCATION`
- `android.permission.FOREGROUND_SERVICE_LOCATION` for some OEMs/Android versions

**Service declaration (AndroidManifest.xml)**

- Add the service entry:
  - `android:foregroundServiceType="location"`
  - Example:

```xml
<service
  android:name="id.flutter.flutter_background_service.BackgroundService"
  android:exported="false"
  android:foregroundServiceType="location"
  tools:replace="android:exported"/>
```

**Notification channel & icon (native Android)**

- Create a notification channel in `MainActivity` (Android 8+). Must run before the service starts.
- Ensure a valid small icon exists (recommended: `res/drawable/ic_bg_service_small.xml` or PNG in `mipmap-*`).
- Without a valid small icon or channel you will get `Bad notification for startForeground`.

**Dart-side essentials**

- Configure and start service from the main isolate (before or in `main()`):
  - `AndroidConfiguration(isForegroundMode: true, notificationChannelId: "location_channel", ...)`
  - Call `await initializeBackgroundService();` in `main()` before `runApp()`.
  - Optionally call `await service.startService();` after `configure()` to ensure start.
- In background `onStart`:
  - Call `DartPluginRegistrant.ensureInitialized();`
  - Start the `Geolocator.getPositionStream(...)` to receive continuous location.
  - Do NOT call certain UI-only APIs from the background isolate (manage notification/channel from main isolate or native side).
- Use `service.on(...)` / `service.invoke(...)` to communicate between UI and background isolates.

**Runtime permission flow (UI/main isolate)**

- Request `ACCESS_FINE_LOCATION` first.
- Then request `ACCESS_BACKGROUND_LOCATION` (Android 10+); may require guiding user to settings.
- Confirm permissions granted before starting the service.

**Quick run checklist**

- Add permissions and service entry to AndroidManifest.xml.
- Add/verify `ic_bg_service_small` exists in drawable.
- Ensure `MainActivity` creates notification channel on startup.
- In Dart `main()`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await initializeBackgroundService(); // configure + start
runApp(const MyApp());
```

- Run:

```powershell
flutter clean
flutter pub get
flutter run
```

- Grant background location permission when prompted and check notification appears; minimize app and watch logs for `BG LOCATION → <lat,lng>`.

**Common pitfalls & fixes (one-line each)**

- Bad notification / startForeground crash → missing valid small icon or channel. Fix: add icon + create channel in `MainActivity`.
- Service killed after minimize → foreground-mode not enabled or permission missing. Fix: `isForegroundMode: true` + request `ACCESS_BACKGROUND_LOCATION`.
- Duplicate location streams / engine warnings → run location in single place (prefer background service only) and have UI subscribe to service updates.
