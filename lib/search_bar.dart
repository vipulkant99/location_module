// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
// import 'package:http/http.dart' as http;

// class LocationSearchBar extends StatefulWidget {
//   final MapController controller;

//   const LocationSearchBar({super.key, required this.controller});

//   @override
//   State<LocationSearchBar> createState() => _LocationSearchBarState();
// }

// class _LocationSearchBarState extends State<LocationSearchBar> {
//   final TextEditingController _searchController = TextEditingController();
//   bool _isSearching = false;

//   Future<GeoPoint?> searchPlace(String query) async {
//     const apiKey = "a28bf28dab4744959fda5fd6d7b88e98"; // 🔥 put your key here

//     final url = Uri.parse(
//       "https://api.opencagedata.com/geocode/v1/json"
//       "?q=${Uri.encodeComponent(query)}"
//       "&key=$apiKey"
//       "&limit=3"
//       "&countrycode=in",
//     );

//     final response = await http.get(url);

//     if (response.statusCode == 200) {
//       final data = json.decode(response.body);

//       if (data["results"].isNotEmpty) {
//         final r = data["results"][0]["geometry"];
//         return GeoPoint(latitude: r["lat"], longitude: r["lng"]);
//       }
//     }

//     return null;
//   }

//   Future<void> _searchLocation(String query) async {
//     if (query.trim().isEmpty) return;

//     setState(() => _isSearching = true);

//     final point = await searchPlace(query);

//     if (point == null) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text("No results found")));
//     } else {
//       await widget.controller.moveTo(point);
//       await widget.controller.addMarker(point);
//     }

//     setState(() => _isSearching = false);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       elevation: 4,
//       borderRadius: BorderRadius.circular(12),
//       child: TextField(
//         controller: _searchController,
//         textInputAction: TextInputAction.search,
//         onSubmitted: _searchLocation,
//         decoration: InputDecoration(
//           hintText: "Search place, city, address...",
//           contentPadding: const EdgeInsets.symmetric(
//             horizontal: 16,
//             vertical: 12,
//           ),
//           border: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide.none,
//           ),
//           filled: true,
//           suffixIcon: _isSearching
//               ? const Padding(
//                   padding: EdgeInsets.all(10.0),
//                   child: SizedBox(
//                     width: 18,
//                     height: 18,
//                     child: CircularProgressIndicator(strokeWidth: 2),
//                   ),
//                 )
//               : IconButton(
//                   icon: const Icon(Icons.search),
//                   onPressed: () => _searchLocation(_searchController.text),
//                 ),
//         ),
//       ),
//     );
//   }
// }

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';

class LocationSearchBar extends StatefulWidget {
  final void Function(GeoPoint) onLocationSelected;

  const LocationSearchBar({Key? key, required this.onLocationSelected})
    : super(key: key);

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  bool _isLoading = false;

  List<_PlaceSuggestion> _suggestions = [];

  static const String _openCageApiKey = 'a28bf28dab4744959fda5fd6d7b88e98';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged(String value) {
    // Clear if too short
    if (value.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    // Debounce API calls
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _autocompleteSearch(value);
    });
  }

  Future<void> _autocompleteSearch(String query) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse(
        'https://api.opencagedata.com/geocode/v1/json'
        '?key=$_openCageApiKey'
        '&q=$query'
        '&limit=5',
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final results = data['results'] as List<dynamic>;

        final List<_PlaceSuggestion> places = results.map((item) {
          final geometry = item['geometry'];
          final formatted = item['formatted'] ?? '';

          return _PlaceSuggestion(
            displayName: formatted,
            point: GeoPoint(
              latitude: geometry['lat'] as double,
              longitude: geometry['lng'] as double,
            ),
          );
        }).toList();

        setState(() {
          _suggestions = places;
        });
      } else {
        // 400 or others – bad input / error from API
        debugPrint('OpenCage error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSuggestionTap(_PlaceSuggestion suggestion) {
    // send back to parent (map screen)
    widget.onLocationSelected(suggestion.point);

    // close suggestions + keyboard
    setState(() {
      _suggestions = [];
      _controller.text = suggestion.displayName;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // important for width constraints
      children: [
        // The search TextField
        SizedBox(
          width: double.infinity, // avoids "unbounded width" error
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: "Search location",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _controller.clear();
                                _suggestions = [];
                              });
                            },
                          )
                        : null),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            onChanged: _onTextChanged,
          ),
        ),

        // Suggestions list
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(0, 2))],
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    suggestion.displayName,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () => _onSuggestionTap(suggestion),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PlaceSuggestion {
  final String displayName;
  final GeoPoint point;

  _PlaceSuggestion({required this.displayName, required this.point});
}
