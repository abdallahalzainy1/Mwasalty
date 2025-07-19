import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

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
  int? selectedStepIndex;

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
        errorMessage = 'خطأ في تحميل البيانات: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  Future<void> _processRouteData(Map<String, dynamic> data) async {
    try {
      final timeline = data['timeline'] as List<dynamic>? ?? [];
      List<Map<String, dynamic>> processedSteps = [];
      List<LatLng> processedRoutePoints = [];

      final fromLocation = data['from'] as String? ?? '';
      if (fromLocation.isEmpty) {
        throw Exception('موقع البداية غير محدد');
      }

      final startCoords = await _getPreciseCoordinates(fromLocation);
      processedRoutePoints.add(startCoords);

      for (var step in timeline) {
        try {
          final stepText = step['step'] as String? ?? '';
          if (stepText.isEmpty) continue;

          final transport = _determineTransportType(stepText);
          final locations = _extractLocationsFromStep(stepText);
          
          if (locations.length < 2 || locations[0].isEmpty || locations[1].isEmpty) continue;

          final toLocation = locations[1];
          final toCoords = await _getPreciseCoordinates(toLocation);

          if (toCoords.latitude == 0.0 && toCoords.longitude == 0.0) continue;

          processedSteps.add({
            'from': processedRoutePoints.last,
            'to': toCoords,
            'transport': transport,
            'step': stepText,
            'duration': (step['duration'] ?? 'غير معروف').toString(),
            'price': (step['price'] ?? 'غير معروف').toString(),
            'start_time': (step['start_time'] ?? 'غير معروف').toString(),
          });

          processedRoutePoints.add(toCoords);
        } catch (e) {
          continue;
        }
      }

      if (processedSteps.isEmpty) throw Exception('لا توجد خطوات صالحة لعرضها');

      setState(() {
        steps = processedSteps;
        routePoints = processedRoutePoints;
        isLoading = false;
        errorMessage = '';
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _zoomToFitRoute();
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ في عرض البيانات: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  Future<LatLng> _getPreciseCoordinates(String location) async {
    if (location.isEmpty) throw Exception('اسم الموقع فارغ');
    setState(() => isGeocoding = true);
    
    try {
      final coords = await _geocodeLocation(location, precise: true);
      return coords;
    } catch (e) {
      return await _geocodeLocation(location, precise: false);
    } finally {
      setState(() => isGeocoding = false);
    }
  }

  Future<LatLng> _geocodeLocation(String location, {bool precise = true}) async {
    try {
      final prompt = precise ? '''
أريد إحداثيات GPS دقيقة للموقع التالي في مصر:
"$location"

الرجاء تحديد الموقع الدقيق بناءً على السياق التالي:
- إذا كان الموقع محطة قطار، حدد إحداثيات المحطة الرئيسية
- إذا كان الموقف موقف مواصلات، حدد الموقع الأكثر شهرة
- إذا كانت المنطقة كبيرة، حدد المركز الجغرافي أو الموقع الأكثر شهرة

الرجاء الرد بصيغة JSON تحتوي على خط الطول والعرض فقط، مثل:
{
  "latitude": 30.0444,
  "longitude": 31.2357
}
''' : '''
أريد إحداثيات GPS تقريبية للمنطقة التالية في مصر:
"$location"

حدد المركز الجغرافي للمنطقة أو الموقع الأكثر شهرة فيها.

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
        
        final jsonStart = cleanJson.indexOf('{');
        final jsonEnd = cleanJson.lastIndexOf('}');
        if (jsonStart == -1 || jsonEnd == -1) throw Exception('لا يمكن العثور على JSON في الرد');
        
        final jsonString = cleanJson.substring(jsonStart, jsonEnd + 1);
        final coords = jsonDecode(jsonString);
        
        if (coords['latitude'] == null || coords['longitude'] == null) throw Exception('إحداثيات غير صالحة');
        
        return LatLng(coords['latitude'].toDouble(), coords['longitude'].toDouble());
      } else {
        throw Exception('فشل في جلب الإحداثيات: ${response.statusCode}');
      }
    } catch (e) {
      return LatLng(30.0444, 31.2357);
    }
  }

  List<String> _extractLocationsFromStep(String stepText) {
    if (stepText.isEmpty) return ['', ''];
    final patterns = [
      RegExp(r'من\s(.+?)\sإلى\s(.+)$'),
      RegExp(r'بين\s(.+?)\sو\s(.+)$'),
      RegExp(r'من\s(.+?)\sل\s(.+)$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(stepText);
      if (match != null && match.groupCount >= 2) {
        return [match.group(1)!.trim(), match.group(2)!.trim()];
      }
    }

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
    _mapController.fitBounds(
      LatLngBounds.fromPoints(routePoints),
      options: const FitBoundsOptions(padding: EdgeInsets.all(30)),
    );
  }

  void _zoomToStep(int index) {
    if (index < 0 || index >= steps.length) return;
    final step = steps[index];
    _mapController.move(step['from'], 15.0);
    setState(() => selectedStepIndex = index);
  }

  String _formatTimestamp(Timestamp timestamp) {
    return DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate());
  }

  IconData _getTransportIcon(String transportType) {
    switch (transportType) {
      case 'train': return FontAwesomeIcons.train;
      case 'microbus': return FontAwesomeIcons.vanShuttle;
      case 'bus': return FontAwesomeIcons.bus;
      case 'taxi': return FontAwesomeIcons.taxi;
      default: return FontAwesomeIcons.questionCircle;
    }
  }

  Color _getTransportColor(String transportType) {
    switch (transportType) {
      case 'train': return const Color(0xFF4285F4);
      case 'microbus': return const Color(0xFFFBBC05);
      case 'bus': return const Color(0xFF34A853);
      case 'taxi': return const Color(0xFFEA4335);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    if (isLoading || isGeocoding) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                isGeocoding ? 'جارٍ تحديد مواقع المحطات...' : 'جارٍ التحميل...',
                style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              if (isGeocoding) ...[
                const SizedBox(height: 10),
                Text(
                  'قد يستغرق هذا بضع لحظات',
                  style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                const SizedBox(height: 20),
                Text(errorMessage, textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _fetchRouteData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('إعادة المحاولة',
                    style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'zoom_fit',
            mini: true,
            onPressed: _zoomToFitRoute,
            backgroundColor: const Color(0xFF4285F4),
            child: const Icon(Icons.zoom_out_map, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'my_location',
            onPressed: () {
              if (routePoints.isNotEmpty) _mapController.move(routePoints.first, 15.0);
            },
            backgroundColor: const Color(0xFF34A853),
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: routePoints.isNotEmpty ? routePoints[0] :  LatLng(29.3085, 30.8421),
                    zoom: 7.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: isDarkMode
                          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                          : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 6.5,
                          color: const Color(0xFF4285F4).withOpacity(0.8),
                        ),
                        if (selectedStepIndex != null && selectedStepIndex! < steps.length)
                          Polyline(
                            points: [steps[selectedStepIndex!]['from'], steps[selectedStepIndex!]['to']],
                            strokeWidth: 8,
                            color: const Color(0xFFFBBC05).withOpacity(0.6),
                          ),
                      ],
                    ),
                    MarkerLayer(markers: _buildMapMarkers()),
                  ],
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: FlutterMap(
                        options: MapOptions(
                          center: routePoints.isNotEmpty ? routePoints[0] :  LatLng(29.3085, 30.8421),
                          zoom: 5.0,
                          interactiveFlags: InteractiveFlag.none,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: routePoints,
                                color: const Color(0xFF4285F4),
                                strokeWidth: 2,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildTripDetailsPanel(isDarkMode),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text('مسار الرحلة',
        style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold)),
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
    );
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];
    if (routePoints.isEmpty) return markers;

    markers.add(Marker(
      point: routePoints.first,
      builder: (ctx) => const Icon(Icons.location_pin, color: Colors.red, size: 48),
    ));

    markers.add(Marker(
      point: routePoints.last,
      builder: (ctx) => const Icon(Icons.location_pin, color: Colors.green, size: 48),
    ));

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      markers.add(Marker(
        point: step['from'],
        width: 40,
        height: 40,
        builder: (ctx) => GestureDetector(
          onTap: () => _zoomToStep(i),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(
              _getTransportIcon(step['transport']),
              color: i == selectedStepIndex 
                  ? const Color(0xFFFBBC05)
                  : _getTransportColor(step['transport']),
              size: 24,
            ),
          ),
        ),
      ));
    }

    return markers;
  }

  Widget _buildTripDetailsPanel(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.35,
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (travelData['from'] != null && travelData['to'] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('${travelData['from']} → ${travelData['to']}',
                        style: GoogleFonts.tajawal(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  if (travelData['createdAt'] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'تم الإنشاء: ${_formatTimestamp(travelData['createdAt'] as Timestamp)}',
                        style: GoogleFonts.tajawal(
                          fontSize: 12,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildSummarySection(isDarkMode),
                  const SizedBox(height: 8),
                  ...steps.asMap().entries.map((entry) => 
                    _buildTimelineStep(entry.value, entry.key, isDarkMode)
                  ).toList(),
                  if (travelData['tips'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('نصائح مفيدة:',
                              style: GoogleFonts.tajawal(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.grey[800] : Colors.amber[50],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              travelData['tips'],
                              style: GoogleFonts.tajawal(
                                fontSize: 12,
                                color: isDarkMode ? Colors.amber[100] : Colors.amber[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            icon: Icons.access_time,
            label: 'المدة',
            value: travelData['duration'] ?? 'غير معروف',
            isDarkMode: isDarkMode,
          ),
          _buildSummaryItem(
            icon: Icons.attach_money,
            label: 'التكلفة',
            value: travelData['price'] ?? 'غير معروف',
            isDarkMode: isDarkMode,
          ),
          _buildSummaryItem(
            icon: Icons.directions_bus,
            label: 'المواصلات',
            value: travelData['method'] ?? 'غير معروف',
            isDarkMode: isDarkMode,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(maxWidth: 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(height: 2),
          Text(label,
            style: GoogleFonts.tajawal(fontSize: 10, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(value,
            style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep(Map<String, dynamic> step, int index, bool isDarkMode) {
    return GestureDetector(
      onTap: () => _zoomToStep(index),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: index == selectedStepIndex 
              ? (isDarkMode ? Colors.blue[900] : Colors.blue[50])
              : (isDarkMode ? Colors.grey[800] : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: index == selectedStepIndex ? const Color(0xFF4285F4) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _getTransportColor(step['transport']).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getTransportColor(step['transport']),
                  width: 1.5,
                ),
              ),
              child: Icon(
                _getTransportIcon(step['transport']),
                color: _getTransportColor(step['transport']),
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step['step'],
                    style: GoogleFonts.tajawal(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildStepDetail(
                          icon: Icons.access_time,
                          value: step['duration'],
                          isDarkMode: isDarkMode,
                        ),
                        const SizedBox(width: 8),
                        _buildStepDetail(
                          icon: Icons.schedule,
                          value: step['start_time'],
                          isDarkMode: isDarkMode,
                        ),
                        if (step['price'] != null) ...[
                          const SizedBox(width: 8),
                          _buildStepDetail(
                            icon: Icons.attach_money,
                            value: step['price'],
                            isDarkMode: isDarkMode,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepDetail({
    required IconData icon,
    required String value,
    required bool isDarkMode,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(width: 2),
          Text(value,
            style: GoogleFonts.tajawal(fontSize: 10, color: isDarkMode ? Colors.grey[300] : Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}