import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location_module/background_service.dart';
import 'package:location_module/search_bar.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service before running the app
  await initializeBackgroundService();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Module',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const OsmPOC(),
    );
  }
}

class OsmPOC extends StatefulWidget {
  const OsmPOC({super.key});

  @override
  State<OsmPOC> createState() => _OsmPOCState();
}

StreamSubscription<Position>? _posStream;
GeoPoint? _liveMarkerPoint;

class _OsmPOCState extends State<OsmPOC> {
  late MapController controller;
  GeoPoint? _searchMarkerPoint;
  int i = 0;
  bool _mapReady = false;

  Future<void> _updateLiveLocation(GeoPoint point) async {
    // remove old marker
    if (_liveMarkerPoint != null) {
      await controller.removeMarker(_liveMarkerPoint!);
    }

    _liveMarkerPoint = point;

    // add new marker
    await controller.addMarker(
      point,
      markerIcon: const MarkerIcon(
        icon: Icon(Icons.navigation, color: Colors.red, size: 100),
      ),
    );

    // follow camera smoothly
    try {
      await controller.moveTo(point);
    } catch (_) {}
  }

  void _startHighAccuracyTracking() async {
    await Geolocator.requestPermission();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // update every 1 meter
    );

    _posStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
          print("person moved ${++i}");
          final point = GeoPoint(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
          _updateLiveLocation(point);
        });
  }

  Future<bool> ensureLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      // show a dialog / snackbar
      debugPrint("Location permission not granted");
      return false;
    }
    return true;
  }

  Future<void> _init() async {
    await ensureLocationPermission();

    controller = MapController(
      initMapWithUserPosition: UserTrackingOption(enableTracking: false),
    );

    _startHighAccuracyTracking();

    setState(() => _mapReady = true);
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _posStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mapReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Live Location with OSM")),
      body: Stack(
        children: [
          OSMFlutter(
            controller: controller,
            osmOption: OSMOption(
              zoomOption: const ZoomOption(
                initZoom: 16,
                minZoomLevel: 3,
                maxZoomLevel: 18,
              ),
            ),
            onGeoPointClicked: (GeoPoint point) {
              _onMarkerTap(point, context);
              print("we clicked $point");
            },
          ),

          // SafeArea(
          //   child: Padding(
          //     padding: const EdgeInsets.all(12.0),
          //     child: SizedBox(
          //       width: MediaQuery.of(
          //         context,
          //       ).size.width, // 👈 full width constraint
          //       child: LocationSearchBar(controller: controller),
          //     ),
          //   ),
          // ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: LocationSearchBar(
              onLocationSelected: (GeoPoint point) async {
                if (_searchMarkerPoint != null) {
                  try {
                    await controller.removeMarker(_searchMarkerPoint!);
                  } catch (_) {}
                }

                _searchMarkerPoint = point;

                // Add the red marker (your custom one)
                await controller.addMarker(
                  point,
                  markerIcon: const MarkerIcon(
                    icon: Icon(
                      Icons.location_on,
                      color: Colors.purple,
                      size: 70,
                    ),
                  ),
                );

                // Move camera WITHOUT auto-marker
                try {
                  await controller.moveTo(point);
                } catch (e) {
                  print("moveToPosition failed, fallback to changeLocation");
                  await controller.changeLocation(point);
                }
              },
            ),
          ),

          // ⭐ Zoom buttons + My Location button (stacked)
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ➕ ZOOM IN
                FloatingActionButton(
                  heroTag: "zoom_in",
                  mini: true,
                  child: const Icon(Icons.add),
                  onPressed: () async {
                    await controller.zoomIn();
                  },
                ),
                const SizedBox(height: 10),

                // ➖ ZOOM OUT
                FloatingActionButton(
                  heroTag: "zoom_out",
                  mini: true,
                  child: const Icon(Icons.remove),
                  onPressed: () async {
                    await controller.zoomOut();
                  },
                ),
                const SizedBox(height: 15),

                // 📍 MY LOCATION
                FloatingActionButton(
                  heroTag: "my_loc",
                  child: const Icon(Icons.my_location),
                  onPressed: () async {
                    if (_liveMarkerPoint != null) {
                      await controller.moveTo(_liveMarkerPoint!);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _onMarkerTap(GeoPoint point, BuildContext context) async {
  final details = await reverseGeocode(point);

  String title = "Unknown Location";
  String address = "No address found";

  if (details != null) {
    title = details["formatted"] ?? "Unknown Location";
    address = details["formatted"] ?? "";
  }

  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Text(address, style: const TextStyle(fontSize: 14)),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _bookmarkPlace(point);
              },
              icon: const Icon(Icons.bookmark),
              label: const Text("Bookmark this place"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      );
    },
  );
}

void _bookmarkPlace(GeoPoint point) {
  print("BOOKMARK: ${point.latitude}, ${point.longitude}");
}

Future<Map<String, dynamic>?> reverseGeocode(GeoPoint point) async {
  const apiKey = "a28bf28dab4744959fda5fd6d7b88e98";

  final url = Uri.parse(
    "https://api.opencagedata.com/geocode/v1/json"
    "?key=$apiKey"
    "&q=${point.latitude}+${point.longitude}"
    "&pretty=1",
  );

  final response = await http.get(url);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);

    if (data["results"].isNotEmpty) {
      log("full data is $data");
      return data["results"][0]; // Full details of the location
    }
  }

  return null;
}
