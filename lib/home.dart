import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
      scaffoldBackgroundColor: Colors.white,
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
        return docRef.id; // إرجاع معرف الوثيقة
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 40.0, bottom: 30),
                child: Text(
                  'طرق السفر في مصر',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
              ),
              
              _buildLocationCard(
                title: 'من',
                cityController: fromCityController,
                onCityChanged: (value) => setState(() => fromCity = value),
                governorateValue: fromGovernorate,
                onGovernorateChanged: (value) => setState(() => fromGovernorate = value ?? ''),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: IconButton(
                  icon: Icon(Icons.swap_vert, size: 32, color: Colors.blue[700]),
                  onPressed: swapLocations,
                ),
              ),
              
              _buildLocationCard(
                title: 'إلى',
                cityController: toCityController,
                onCityChanged: (value) => setState(() => toCity = value),
                governorateValue: toGovernorate,
                onGovernorateChanged: (value) => setState(() => toGovernorate = value ?? ''),
              ),
              
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  if (fromCity.isEmpty || fromGovernorate.isEmpty || 
                      toCity.isEmpty || toGovernorate.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('الرجاء ملء جميع الحقول')),
                    );
                    return;
                  }

                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => AlertDialog(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('جارٍ البحث عن أفضل الطرق...'),
                          ],
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
                      SnackBar(content: Text('خطأ: ${e.toString()}')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'ابحث عن أفضل طريق',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              
              if (_routes.isNotEmpty) ...[
                SizedBox(height: 24),
                Text(
                  'خيارات السفر من $_fromLocation إلى $_toLocation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _routes.length,
                    itemBuilder: (context, index) {
                      final route = _routes[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RouteDetailsPage(
                                route: route,
                                onSelect: () async {
                                  try {
                                    final routeId = await saveSelectedRoute(route);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('تم اختيار الطريق بنجاح'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    Navigator.pop(context);
                                    return routeId;
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('خطأ في حفظ الطريق: $e'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    return null;
                                  }
                                },
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 220,
                          margin: EdgeInsets.symmetric(horizontal: 8),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey[300]!,
                                blurRadius: 5,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${route['price']} جنيه',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'المدة: ${route['duration']}',
                                style: TextStyle(fontSize: 14),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '${route['transfers']} تحويلات',
                                style: TextStyle(fontSize: 14),
                              ),
                              Spacer(),
                              Text(
                                route['method'],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Text(
                    'أفضل خيار: $_bestOption',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                      fontSize: 16,
                    ),
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
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[600],
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: cityController,
              decoration: InputDecoration(
                labelText: 'المدينة',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.location_city),
              ),
              onChanged: onCityChanged,
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'المحافظة',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.map),
              ),
              items: egyptGovernorates
                  .map((gov) => DropdownMenuItem(
                        value: gov,
                        child: Text(gov),
                      ))
                  .toList(),
              onChanged: onGovernorateChanged,
              value: governorateValue.isEmpty ? null : governorateValue,
            ),
          ],
        ),
      ),
    );
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
        title: Text('تفاصيل الرحلة'),
        backgroundColor: Colors.blue[800],
        actions: [
          IconButton(
            icon: Icon(Icons.map, color: Colors.blue),
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
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                final routeId = await onSelect();
                if (routeId != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم اختيار الطريق بنجاح'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              child: Text(
                'اختر هذا الطريق',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route['method'],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.grey),
                        SizedBox(width: 5),
                        Text('المدة: ${route['duration']}'),
                      ],
                    ),
                    SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.attach_money, size: 16, color: Colors.grey),
                        SizedBox(width: 5),
                        Text('السعر: ${route['price']} جنيه'),
                      ],
                    ),
                    SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.swap_horiz, size: 16, color: Colors.grey),
                        SizedBox(width: 5),
                        Text('${route['transfers']} تحويلات'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            Text(
              'تفاصيل الرحلة:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(route['details']),
            
            SizedBox(height: 16),
            
            if (timeline != null && timeline.isNotEmpty) ...[
              Text(
                'خطوات الرحلة:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              ...timeline.map((step) => Card(
                margin: EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step['step'],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey),
                          SizedBox(width: 4),
                          Text('الانطلاق: ${step['start_time']}'),
                        ],
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.timer, size: 14, color: Colors.grey),
                          SizedBox(width: 4),
                          Text('المدة: ${step['duration']}'),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
            ],
            
            SizedBox(height: 16),
            
            if (route['tips'] != null && route['tips'].isNotEmpty) ...[
              Text(
                'نصائح للسفر:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(route['tips']),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

