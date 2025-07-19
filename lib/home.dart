import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:tahadi/travelmap.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MaterialApp(
    title: 'طرق السفر في مصر',
    theme: ThemeData(
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: Color(0xFFF5F7FA),
      textTheme: GoogleFonts.tajawalTextTheme(),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.tajawal(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
    home: LocationSwapperPage(),
    debugShowCheckedModeBanner: false,
  ));
}

class LocationSwapperPage extends StatefulWidget {
  @override
  _LocationSwapperPageState createState() => _LocationSwapperPageState();
}

class _LocationSwapperPageState extends State<LocationSwapperPage> {
  final List<String> egyptGovernorates = [
    'القاهرة', 'الإسكندرية', 'الجيزة', 'الدقهلية', 'البحر الأحمر',
    'البحيرة', 'الفيوم', 'الغربية', 'الإسماعيلية', 'المنوفية',
    'المنيا', 'القليوبية', 'الوادي الجديد', 'السويس', 'أسوان',
    'أسيوط', 'بني سويف', 'بورسعيد', 'دمياط', 'الشرقية',
    'جنوب سيناء', 'كفر الشيخ', 'مطروح', 'الأقصر', 'قنا',
    'شمال سيناء', 'سوهاج'
  ];

  String fromCity = '';
  String fromGovernorate = '';
  String toCity = '';
  String toGovernorate = '';
  
  final fromCityController = TextEditingController();
  final toCityController = TextEditingController();

  List<dynamic> _routes = [];
  String _bestOption = '';
  String _fromLocation = '';
  String _toLocation = '';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> fetchTravelRoutes(String from, String to) async {
    final apiKey = 'AIzaSyCLjpVBwXb7UQpGuODXUNEiosLkVmdrmuE';
    final endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key=$apiKey';

    final prompt = '''
أريد ملف JSON يحتوي على 3 طرق دقيقة للسفر من "$from" إلى "$to" داخل مصر.

🔹 لكل طريقة، يجب أن توضح:
- وسيلة المواصلات (ميكروباص، قطار، حافلة، Uber، الخ).
- من أين تبدأ الوسيلة بالضبط (مثلاً: "موقف سنورس").
- متى تنطلق (ساعة الانطلاق بدقة، مثال: "10:45 صباحًا").
- كم تستغرق (مدة الرحلة).
- كم تكلفة كل جزء.
- إذا كان الطريق يحتوي على مراحل (مثلاً ميكروباص + قطار)، اذكر كل مرحلة بالتفصيل.
- عدد التحويلات.
- نصائح، وهل هناك زحام يؤثر على المدة.

🛑 أرجو أن يكون الرد عبارة عن JSON خام فقط، بدون علامات Markdown أو ```.

صيغة الإخراج:

{
 "from": "$from",
 "to": "$to",
 "routes": [
  {
   "method": "ميكروباص + قطار",
   "details": "من موقف سنورس إلى محطة قطار الفيوم، ثم القطار إلى المنصورة.",
   "duration": "3 ساعات",
   "price": "95 جنيه",
   "transfers": "2",
   "tips": "تأكد من الوصول للموقف قبل الموعد بـ 10 دقائق",
   "timeline": [
     {
       "step": "ميكروباص من موقف سنورس إلى الفيوم",
       "start_time": "10:10 صباحًا",
       "duration": "20 دقيقة"
     },
     {
       "step": "قطار من الفيوم إلى المنصورة",
       "start_time": "10:45 صباحًا",
       "duration": "2.5 ساعة"
     }
   ]
  }
 ],
 "best_option": "القطار لأن مواعيده دقيقة وتكلفته مناسبة"
}
''';

    try {
      print('⏳ جار إرسال الطلب إلى Gemini API...');
      print('📍 من: $from');
      print('📍 إلى: $to');
      
      final response = await http.post(
        Uri.parse(endpoint),
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

      print('✅ تم استلام الرد - حالة HTTP: ${response.statusCode}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        
        final rawText = decoded['candidates'][0]['content']['parts'][0]['text'];
        print('📝 النص المستخرج:\n$rawText');
        
        final cleanJson = rawText
            .replaceAll("```json", "")
            .replaceAll("```", "")
            .trim();
        print('🧹 النص بعد التنظيف:\n$cleanJson');
        
        final jsonResponse = jsonDecode(cleanJson);
        print('🎯 JSON النهائي:\n$jsonResponse');
        
        return jsonResponse;
      } else {
        print('❌ خطأ في الاستجابة: ${response.body}');
        throw Exception("فشل الاتصال بـ Gemini API: ${response.statusCode}");
      }
    } on http.ClientException catch (e) {
      print('❌ خطأ في العميل: ${e.message}');
      throw Exception('مشكلة في الاتصال بالإنترنت');
    } on TimeoutException {
      print('⏱ انتهى الوقت المحدد للطلب');
      throw Exception('الطلب استغرق وقتًا طويلاً');
    } on FormatException catch (e) {
      print('❌ خطأ في تنسيق JSON: $e');
      throw Exception('مشكلة في تحليل البيانات');
    } catch (e) {
      print('❌ خطأ غير متوقع: $e');
      throw Exception('حدث خطأ غير متوقع: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Header with decorative elements
              Container(
                padding: EdgeInsets.only(top: 50, bottom: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  )),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.directions, size: 50, color: Colors.white),
                      SizedBox(height: 10),
                      Text(
                        'طرق السفر في مصر',
                        style: GoogleFonts.tajawal(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 5,
                              color: Colors.black26,
                              offset: Offset(1, 1),
                          )],
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'اكتشف أفضل الطرق بين المدن المصرية',
                        style: GoogleFonts.tajawal(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Location Cards with Neumorphism design
              _buildLocationCard(
                title: 'نقطة الانطلاق',
                cityController: fromCityController,
                onCityChanged: (value) => setState(() => fromCity = value),
                governorateValue: fromGovernorate,
                onGovernorateChanged: (value) => setState(() => fromGovernorate = value ?? ''),
                icon: Icons.location_on,
              ),
              
              // Swap button with animation
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.2),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(Icons.swap_vert, size: 32),
                    color: Colors.blue[700],
                    onPressed: swapLocations,
                  ),
                ),
              ),
              
              _buildLocationCard(
                title: 'الوجهة',
                cityController: toCityController,
                onCityChanged: (value) => setState(() => toCity = value),
                governorateValue: toGovernorate,
                onGovernorateChanged: (value) => setState(() => toGovernorate = value ?? ''),
                icon: Icons.flag,
              ),
              
              SizedBox(height: 24),
              
              // Search button with gradient
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () async {
                    if (fromCity.isEmpty || fromGovernorate.isEmpty || 
                        toCity.isEmpty || toGovernorate.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('الرجاء ملء جميع الحقول'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => Dialog(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'جارٍ البحث عن أفضل الطرق...',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );

                      final fullFrom = '$fromCity, $fromGovernorate';
                      final fullTo = '$toCity, $toGovernorate';
                      
                      final result = await fetchTravelRoutes(fullFrom, fullTo);

                      Navigator.of(context).pop();

                      setState(() {
                        _routes = result['routes'];
                        _bestOption = result['best_option'] ?? '';
                        _fromLocation = result['from'];
                        _toLocation = result['to'];
                      });
                    } catch (e) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ: ${e.toString()}'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                    minimumSize: Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    'ابحث عن أفضل طريق',
                    style: GoogleFonts.tajawal(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              if (_routes.isNotEmpty) ...[
                SizedBox(height: 30),
                Text(
                  'خيارات السفر من $_fromLocation إلى $_toLocation',
                  style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                SizedBox(height: 20),
                
                // Modified routes list view
                Container(
                  height: 220, // Fixed height for the horizontal list
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _routes.length,
                    itemBuilder: (context, index) {
                      final route = _routes[index];
                      return Container(
                        width: MediaQuery.of(context).size.width * 0.85, // 85% of screen width
                        margin: EdgeInsets.symmetric(horizontal: 8),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _getTransportIcon(route['method']),
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        route['method'],
                                        style: GoogleFonts.tajawal(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  '${route['price']} جنيه',
                                  style: GoogleFonts.tajawal(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                SizedBox(height: 16),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.access_time, size: 18, color: Colors.grey),
                                          SizedBox(width: 8),
                                          Text(
                                            'المدة: ${route['duration']}',
                                            style: GoogleFonts.tajawal(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Icon(Icons.swap_horiz, size: 18, color: Colors.grey),
                                          SizedBox(width: 8),
                                          Text(
                                            '${route['transfers']} تحويلات',
                                            style: GoogleFonts.tajawal(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'عرض التفاصيل',
                                      style: GoogleFonts.tajawal(
                                        fontSize: 14,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.1),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.green[800]),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'أفضل خيار: $_bestOption',
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationCard({
    required String title,
    required TextEditingController cityController,
    required ValueChanged<String> onCityChanged,
    required String governorateValue,
    required ValueChanged<String?> onGovernorateChanged,
    required IconData icon,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      shadowColor: Colors.blue.withOpacity(0.2),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue[600]),
                SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: cityController,
              decoration: InputDecoration(
                labelText: 'المدينة',
                labelStyle: GoogleFonts.tajawal(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.blue),
                ),
                prefixIcon: Icon(Icons.location_city),
                contentPadding: EdgeInsets.symmetric(vertical: 15, horizontal: 15),
              ),
              style: GoogleFonts.tajawal(),
              onChanged: onCityChanged,
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'المحافظة',
                labelStyle: GoogleFonts.tajawal(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.blue),
                ),
                prefixIcon: Icon(Icons.map),
                contentPadding: EdgeInsets.symmetric(vertical: 5, horizontal: 15),
              ),
              items: egyptGovernorates
                  .map((gov) => DropdownMenuItem(
                        value: gov,
                        child: Text(
                          gov,
                          style: GoogleFonts.tajawal(
                            color: Colors.black,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: onGovernorateChanged,
              value: governorateValue.isEmpty ? null : governorateValue,
              style: GoogleFonts.tajawal(
                color: Colors.black,
              ),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(10),
              icon: Icon(Icons.arrow_drop_down),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTransportIcon(String method) {
    if (method.contains('قطار')) return Icons.train;
    if (method.contains('حافلة')) return Icons.directions_bus;
    if (method.contains('ميكروباص')) return Icons.airport_shuttle;
    if (method.contains('Uber') || method.contains('تاكسي')) return Icons.local_taxi;
    return Icons.directions;
  }

  Future<String> saveSelectedRoute(Map<String, dynamic> route) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final docRef = await _firestore.collection('users').doc(user.uid)
          .collection('roads').add({
            ...route,
            'from': _fromLocation,
            'to': _toLocation,
            'createdAt': FieldValue.serverTimestamp(),
            'status': 'planned',
          });
        print('✅ تم حفظ الطريق بنجاح في Firebase');
        return docRef.id;
      } else {
        print('⚠️ لم يتم العثور على مستخدم مسجل');
        throw Exception('يجب تسجيل الدخول أولاً');
      }
    } catch (e) {
      print('❌ خطأ في حفظ الطريق: $e');
      throw Exception('فشل في حفظ الطريق: $e');
    }
  }

  void swapLocations() {
    print('🔄 تبديل المواقع');
    setState(() {
      final tempCity = fromCity;
      final tempGovernorate = fromGovernorate;
      
      fromCity = toCity;
      fromGovernorate = toGovernorate;
      
      toCity = tempCity;
      toGovernorate = tempGovernorate;
      
      fromCityController.text = fromCity;
      toCityController.text = toCity;
    });
  }

  @override
  void dispose() {
    fromCityController.dispose();
    toCityController.dispose();
    super.dispose();
  }
}

class RouteDetailsPage extends StatelessWidget {
  final Map<String, dynamic> route;
  final Future<String?> Function() onSelect;

  const RouteDetailsPage({
    required this.route,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final timeline = route['timeline'] as List<dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل الرحلة', style: GoogleFonts.tajawal()),
        backgroundColor: Colors.blue[800],
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.map, color: Colors.white),
            onPressed: () async {
              final routeId = await onSelect();
              if (routeId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TravelMapPage(routeId: routeId),
                  ),
                );
              }
            },
            tooltip: 'عرض الخريطة',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: TextButton(
                onPressed: () async {
                  final routeId = await onSelect();
                  if (routeId != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم اختيار الطريق بنجاح'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                    Navigator.pop(context);
                  }
                },
                child: Text(
                  'اختر هذا الطريق',
                  style: GoogleFonts.tajawal(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route Summary Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getTransportIcon(route['method']),
                            size: 30,
                            color: Colors.blue,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              route['method'],
                              style: GoogleFonts.tajawal(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDetailItem(
                              icon: Icons.access_time,
                              title: 'المدة',
                              value: route['duration'],
                            ),
                          ),
                          Expanded(
                            child: _buildDetailItem(
                              icon: Icons.attach_money,
                              title: 'التكلفة',
                              value: route['price'],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDetailItem(
                              icon: Icons.swap_horiz,
                              title: 'التحويلات',
                              value: '${route['transfers']}',
                            ),
                          ),
                          Expanded(
                            child: Container(), // Empty for alignment
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Route Details
              Text(
                'تفاصيل الرحلة:',
                style: GoogleFonts.tajawal(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
              SizedBox(height: 10),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  route['details'],
                  style: GoogleFonts.tajawal(fontSize: 16),
                  textAlign: TextAlign.right,
                ),
              ),
              
              SizedBox(height: 20),
              
              // Timeline
              if (timeline != null && timeline.isNotEmpty) ...[
                Text(
                  'خطوات الرحلة:',
                  style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                SizedBox(height: 10),
                ListView.separated(
                  physics: NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: timeline.length,
                  separatorBuilder: (context, index) => SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final step = timeline[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: GoogleFonts.tajawal(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    step['step'],
                                    style: GoogleFonts.tajawal(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                _buildTimelineDetail(
                                  icon: Icons.access_time,
                                  value: step['start_time'],
                                ),
                                SizedBox(width: 20),
                                _buildTimelineDetail(
                                  icon: Icons.timer,
                                  value: step['duration'],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              
              SizedBox(height: 20),
              
              // Tips Section
              if (route['tips'] != null && route['tips'].isNotEmpty) ...[
                Text(
                  'نصائح للسفر:',
                  style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[100]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.orange[800]),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          route['tips'],
                          style: GoogleFonts.tajawal(fontSize: 16),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              SizedBox(height: 20),
              
              // Select Button
              Center(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      final routeId = await onSelect();
                      if (routeId != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم اختيار الطريق بنجاح'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'اختيار هذا الطريق',
                      style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem({required IconData icon, required String title, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            SizedBox(width: 5),
            Text(
              title,
              style: GoogleFonts.tajawal(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        SizedBox(height: 5),
        Text(
          value,
          style: GoogleFonts.tajawal(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineDetail({required IconData icon, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        SizedBox(width: 5),
        Text(
          value,
          style: GoogleFonts.tajawal(fontSize: 14),
        ),
      ],
    );
  }

  IconData _getTransportIcon(String method) {
    if (method.contains('قطار')) return Icons.train;
    if (method.contains('حافلة')) return Icons.directions_bus;
    if (method.contains('ميكروباص')) return Icons.airport_shuttle;
    if (method.contains('Uber') || method.contains('تاكسي')) return Icons.local_taxi;
    return Icons.directions;
  }
}