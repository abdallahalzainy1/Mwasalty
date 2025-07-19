import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TravelMapPage extends StatefulWidget {
  final String routeId;

  const TravelMapPage({Key? key, required this.routeId}) : super(key: key);

  @override
  _TravelMapPageState createState() => _TravelMapPageState();
}

class _TravelMapPageState extends State<TravelMapPage> {
  late List<LatLng> routePoints = [];
  late List<Map<String, dynamic>> steps = [];
  final MapController _mapController = MapController();
  Map<String, dynamic> travelData = {};
  bool isLoading = true;
  String errorMessage = '';
  bool isGeocoding = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _geminiApiKey = 'AIzaSyCLjpVBwXb7UQpGuODXUNEiosLkVmdrmuE';

  @override
  void initState() {
    super.initState();
    _fetchRouteData();
  }

  Future<void> _fetchRouteData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('يجب تسجيل الدخول أولاً');

      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('roads')
          .doc(widget.routeId)
          .get();

      if (!doc.exists) throw Exception('الطريق المطلوب غير موجود');

      final data = doc.data() as Map<String, dynamic>;
      setState(() => travelData = data);

      await _processRouteData(data);
    } catch (e) {
      setState(() {
        errorMessage = 'خطأ في تحميل البيانات: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _processRouteData(Map<String, dynamic> data) async {
    try {
      final timeline = data['timeline'] as List<dynamic>? ?? [];
      List<Map<String, dynamic>> processedSteps = [];
      List<LatLng> processedRoutePoints = [];

      // Get coordinates for start location
      final fromLocation = data['from'] as String? ?? '';
      final startCoords = await _geocodeLocation(fromLocation);
      processedRoutePoints.add(startCoords);

      // Process each step in the timeline
      for (var step in timeline) {
        final stepText = step['step'] as String? ?? '';
        final transport = _determineTransportType(stepText);
        
        // Extract location names from step description
        final locations = _extractLocationsFromStep(stepText);
        if (locations.length < 2) continue;

        // Geocode the "to" location
        final toLocation = locations[1];
        final toCoords = await _geocodeLocation(toLocation);

        processedSteps.add({
          'from': processedRoutePoints.last,
          'to': toCoords,
          'transport': transport,
          'step': stepText,
          'duration': step['duration'] ?? 'غير معروف',
          'price': step['price'] ?? 'غير معروف',
          'start_time': step['start_time'] ?? 'غير معروف',
        });

        processedRoutePoints.add(toCoords);
      }

      setState(() {
        steps = processedSteps;
        routePoints = processedRoutePoints;
        isLoading = false;
      });

      _zoomToFitRoute();
    } catch (e) {
      setState(() {
        errorMessage = 'خطأ في معالجة البيانات: $e';
        isLoading = false;
      });
    }
  }

  Future<LatLng> _geocodeLocation(String location) async {
    setState(() => isGeocoding = true);
    
    try {
      print('📍 جارٍ جلب الإحداثيات للموقع: $location');
      
      final prompt = '''
أريد إحداثيات GPS دقيقة للموقع التالي في مصر:
"$location"

الرجاء الرد بصيغة JSON تحتوي على خط الطول والعرض فقط، مثل:
{
  "latitude": 30.0444,
  "longitude": 31.2357
}
''';

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ]
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final rawText = decoded['candidates'][0]['content']['parts'][0]['text'];
        final cleanJson = rawText.replaceAll("```json", "").replaceAll("```", "").trim();
        final coords = jsonDecode(cleanJson);
        
        print('✅ إحداثيات $location: ${coords['latitude']}, ${coords['longitude']}');
        return LatLng(coords['latitude'], coords['longitude']);
      } else {
        throw Exception('فشل في جلب الإحداثيات: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ خطأ في جلب إحداثيات $location: $e');
      // Fallback to Cairo coordinates if geocoding fails
      return  LatLng(30.0444, 31.2357);
    } finally {
      setState(() => isGeocoding = false);
    }
  }

  List<String> _extractLocationsFromStep(String stepText) {
    // This regex extracts locations from step descriptions like:
    // "ميكروباص من موقف سنورس إلى الفيوم"
    final regex = RegExp(r'من\s(.+?)\sإلى\s(.+)$');
    final match = regex.firstMatch(stepText);
    
    if (match != null && match.groupCount >= 2) {
      return [match.group(1)!, match.group(2)!];
    }
    
    // Fallback for other patterns
    if (stepText.contains('إلى')) {
      final parts = stepText.split('إلى');
      if (parts.length >= 2) {
        return [parts[0].replaceAll('من', '').trim(), parts[1].trim()];
      }
    }
    
    return ['', ''];
  }

  String _determineTransportType(String stepText) {
    if (stepText.contains('قطار') || stepText.contains('سكة حديد')) return 'train';
    if (stepText.contains('ميكروباص') || stepText.contains('ميكرو')) return 'microbus';
    if (stepText.contains('حافلة') || stepText.contains('أتوبيس')) return 'bus';
    if (stepText.contains('تاكسي') || stepText.contains('Uber')) return 'taxi';
    return 'bus';
  }

  void _zoomToFitRoute() {
    if (routePoints.isEmpty) return;

    double minLat = routePoints[0].latitude;
    double maxLat = routePoints[0].latitude;
    double minLng = routePoints[0].longitude;
    double maxLng = routePoints[0].longitude;

    for (final point in routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final zoom = 11 - (latDiff + lngDiff) * 2;

    _mapController.move(center, zoom.clamp(7.0, 15.0));
  }

  String _formatTimestamp(Timestamp timestamp) {
    return DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || isGeocoding) {
      return Scaffold(
        appBar: AppBar(title: const Text('مسار الرحلة')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (isGeocoding) ...[
                const SizedBox(height: 20),
                const Text('جارٍ تحديد مواقع المحطات...'),
                const SizedBox(height: 10),
                Text(
                  'قد يستغرق هذا بضع لحظات',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('خطأ')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('مسار الرحلة'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                isLoading = true;
                errorMessage = '';
              });
              _fetchRouteData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: routePoints.isNotEmpty ? routePoints[0] :  LatLng(29.3085, 30.8421),
                zoom: 7.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: ['a', 'b', 'c'],
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      color: Colors.blue.withOpacity(0.7),
                      strokeWidth: 4,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (routePoints.isNotEmpty)
                      Marker(
                        point: routePoints.first,
                        builder: (ctx) => const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    if (routePoints.length > 1)
                      Marker(
                        point: routePoints.last,
                        builder: (ctx) => const Icon(
                          Icons.location_on,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                    ...steps.map((step) {
                      IconData icon;
                      Color color;
                      
                      switch (step['transport']) {
                        case 'train':
                          icon = FontAwesomeIcons.train;
                          color = Colors.blue;
                          break;
                        case 'microbus':
                          icon = FontAwesomeIcons.bus;
                          color = Colors.orange;
                          break;
                        case 'bus':
                          icon = FontAwesomeIcons.busAlt;
                          color = Colors.purple;
                          break;
                        case 'taxi':
                          icon = FontAwesomeIcons.taxi;
                          color = Colors.teal;
                          break;
                        default:
                          icon = FontAwesomeIcons.questionCircle;
                          color = Colors.grey;
                      }
                      
                      return Marker(
                        point: step['from'],
                        width: 40,
                        height: 40,
                        builder: (ctx) => Icon(
                          icon,
                          color: color,
                          size: 24,
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (travelData['from'] != null && travelData['to'] != null)
                  Text(
                    '${travelData['from']} → ${travelData['to']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 8),
                if (travelData['createdAt'] != null)
                  Text(
                    'تم الإنشاء: ${_formatTimestamp(travelData['createdAt'] as Timestamp)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                if (travelData['duration'] != null)
                  Text(
                    'المدة: ${travelData['duration']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                if (travelData['price'] != null)
                  Text(
                    'التكلفة: ${travelData['price']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                if (travelData['method'] != null)
                  Text(
                    'المواصلات: ${travelData['method']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 16),
                ...steps.map((step) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        step['transport'] == 'train' 
                            ? FontAwesomeIcons.train 
                            : step['transport'] == 'microbus'
                              ? FontAwesomeIcons.bus
                              : FontAwesomeIcons.questionCircle,
                        color: step['transport'] == 'train' 
                            ? Colors.blue 
                            : step['transport'] == 'microbus'
                              ? Colors.orange
                              : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step['step'],
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text('${step['duration']} - ${step['price']}'),
                            Text('يبدأ في: ${step['start_time']}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                )).toList(),
                if (travelData['tips'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'نصائح: ${travelData['tips']}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}