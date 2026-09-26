import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fl_chart/fl_chart.dart';

import '../admin_files/settings_provider.dart';
import 'app_drawer.dart';

class TruckStatusScreen extends StatefulWidget {
  const TruckStatusScreen({super.key});

  @override
  State<TruckStatusScreen> createState() => _TruckStatusScreenState();
}

class _TruckStatusScreenState extends State<TruckStatusScreen>
    with SingleTickerProviderStateMixin {
  double? temp;
  double? humidity;
  String shipmentNumber = "";
  String gas1Status = "";
  String gas2Status = "";
  String doorStatus = "";
  String tripType = "";
  String lastUpdated = "";

  double _maxTemp = 100.0;
  double _minTemp = 0.0;
  int _maxHumidity = 100;
  int _minHumidity = 0;
  int _maxDoorOpenTime = 0;
  bool _isLoadingLimits = true;

  DateTime? _doorOpenedAt;
  Timer? _doorOpenTimer;

  late TabController _tabController;

  List<FlSpot> _tempData = [];
  List<FlSpot> _humidityData = [];
  bool _isLoadingChartData = false;
  String _chartTimeRange = '1h';

  double? _latitude;
  double? _longitude;
  String _locationName = "جاري تحديد الموقع...";
  bool _isLoadingLocation = false;

  List<dynamic> _pathPoints = [];
  final MapController _mapController = MapController();
  bool _isLoadingPath = false;

  Timer? _timer;
  Timer? _reportTimer;
  Timer? _gpsTimer;

  static bool isWarningShown = false;

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchGPSLocation();
    loadTruckData();
    _fetchTruckPath();
    _fetchChartData();
    _startAutoRefresh();
    _startReportTimer();
    _startGPSRefresh();
  }

  void _startAutoRefresh() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) loadTruckData();
    });
  }

  void _startReportTimer() {
    _reportTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (mounted && shipmentNumber.isNotEmpty) {
        saveReportToBackend(
          shipmentNumber,
          temp ?? 0.0,
          (humidity ?? 0).toInt(),
          gas1Status,
          gas2Status,
          doorStatus,
        );
      }
    });
  }

  void _startGPSRefresh() {
    _gpsTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _fetchGPSLocation();
    });
  }

  Future<void> _fetchChartData() async {
    if (_isLoadingChartData) return;
    setState(() => _isLoadingChartData = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http
          .get(
            Uri.parse(
              "http://127.0.0.1:8000/sensor-history?range=$_chartTimeRange",
            ),
            headers: token != null ? {"Authorization": "Bearer $token"} : {},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> history = data['history'] ?? [];

        List<FlSpot> tempSpots = [];
        List<FlSpot> humSpots = [];

        for (int i = 0; i < history.length; i++) {
          final point = history[i];
          final temp = point['temperature'];
          final hum = point['humidity'];
          if (temp != null) tempSpots.add(FlSpot(i.toDouble(), temp.toDouble()));
          if (hum != null) humSpots.add(FlSpot(i.toDouble(), hum.toDouble()));
        }

        setState(() {
          _tempData = tempSpots;
          _humidityData = humSpots;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching chart data: $e");
    } finally {
      if (mounted) setState(() => _isLoadingChartData = false);
    }
  }

  Future<void> _fetchTruckPath() async {
    if (_isLoadingPath) return;
    setState(() => _isLoadingPath = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http
          .get(
            Uri.parse("http://127.0.0.1:8000/user/truck-path"),
            headers: token != null ? {"Authorization": "Bearer $token"} : {},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _pathPoints = data['path'] ?? [];
          if (_pathPoints.isNotEmpty) {
            final lastPoint = _pathPoints.last;
            _latitude = (lastPoint['latitude'] as num?)?.toDouble();
            _longitude = (lastPoint['longitude'] as num?)?.toDouble();
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching truck path: $e");
    } finally {
      if (mounted) setState(() => _isLoadingPath = false);
    }
  }

  Future<void> _fetchGPSLocation() async {
    if (_isLoadingLocation) return;
    if (mounted) setState(() => _isLoadingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locationName = "تم رفض صلاحية الموقع";
              _isLoadingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationName = "الموقع محظور - افتح الإعدادات";
            _isLoadingLocation = false;
          });
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      String cityName = "موقع غير معروف";
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        cityName = [
          place.subLocality,
          place.locality,
          place.country,
        ].where((e) => e != null && e.isNotEmpty).join("، ");
      }

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationName = cityName;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      debugPrint("GPS Error: $e");
      if (mounted) {
        setState(() {
          _locationName = "خطأ في جلب الموقع";
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> loadTruckData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse("http://127.0.0.1:8000/truck-live-data"),
        headers: token != null ? {"Authorization": "Bearer $token"} : {},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          temp = data["temperature"] != null
              ? (data["temperature"]).toDouble()
              : null;
          humidity = data["humidity"] != null
              ? (data["humidity"]).toDouble()
              : null;
          shipmentNumber = data["shipment_number"] ?? "";
          gas1Status = data["gas1_status"] ?? "طبيعي";
          gas2Status = data["gas2_status"] ?? "طبيعي";
          doorStatus = data["door_status"] ?? "مغلق";
          tripType = data["trip_type"] ?? "";
          lastUpdated = data["last_updated"] ?? "";
          _minTemp = (data["min_temp"] ?? 0).toDouble();
          _maxTemp = (data["max_temp"] ?? 100).toDouble();
          _minHumidity = data["min_hum"] ?? 0;
          _maxHumidity = data["max_hum"] ?? 100;
          _maxDoorOpenTime = data["max_door_open_time"] ?? 0;
          _isLoadingLimits = false;

          if (_latitude == null &&
              _longitude == null &&
              data["latitude"] != null &&
              data["longitude"] != null) {
            _latitude = (data["latitude"]).toDouble();
            _longitude = (data["longitude"]).toDouble();
            _locationName = "موقع الشاحنة (من السيرفر)";
          }
        });

        bool isAlert = false;
        String reason = "";

        if (temp != null) {
          if (temp! > _maxTemp) {
            isAlert = true;
            reason = "درجة حرارة مرتفعة (${temp!.toStringAsFixed(1)}°C > $_maxTemp°C)";
          } else if (temp! < _minTemp) {
            isAlert = true;
            reason = "درجة حرارة منخفضة (${temp!.toStringAsFixed(1)}°C < $_minTemp°C)";
          }
        }

        if (!isAlert && humidity != null) {
          if (humidity! > _maxHumidity) {
            isAlert = true;
            reason = "رطوبة عالية (${humidity!.toStringAsFixed(0)}% > $_maxHumidity%)";
          } else if (humidity! < _minHumidity) {
            isAlert = true;
            reason = "رطوبة منخفضة (${humidity!.toStringAsFixed(0)}% < $_minHumidity%)";
          }
        }

        if (!isAlert && gas1Status == "غير طبيعي") {
          isAlert = true;
          reason = "حساس الغاز 1 غير طبيعي";
        }

        if (!isAlert && gas2Status == "غير طبيعي") {
          isAlert = true;
          reason = "حساس الغاز 2 غير طبيعي";
        }

        if (doorStatus == "مفتوح" || doorStatus == "OPEN") {
          if (_doorOpenedAt == null) {
            _doorOpenedAt = DateTime.now();
          } else if (_maxDoorOpenTime > 0) {
            final openDuration = DateTime.now().difference(_doorOpenedAt!);
            final openSeconds = openDuration.inSeconds;
            if (openSeconds >= _maxDoorOpenTime && !isAlert) {
              isAlert = true;
              reason = "الباب مفتوح لمدة طويلة ($openSeconds ثانية > $_maxDoorOpenTime ثانية)";
            }
          }
        } else {
          if (_doorOpenedAt != null) _doorOpenedAt = null;
        }

        if (isAlert && !isWarningShown) {
          isWarningShown = true;
          saveAlertToBackend(shipmentNumber, reason);
          if (mounted) {
            _showWarningDialog(context);
            await _audioPlayer.play(AssetSource('alarm.mp3'));
          }
        } else if (!isAlert) {
          isWarningShown = false;
        }
      } else if (response.statusCode == 401) {
        debugPrint("Unauthorized - token expired");
      }
    } catch (e) {
      debugPrint("Error loading truck data: $e");
    }
  }

  Future<void> saveAlertToBackend(String shipmentNum, String reason) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse("http://127.0.0.1:8000/save-alert"),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "shipment_number": shipmentNum,
          "reason": reason,
          "latitude": _latitude ?? 0.0,
          "longitude": _longitude ?? 0.0,
        }),
      );
      debugPrint("Alert Save Response: ${response.body}");
    } catch (e) {
      debugPrint("Error saving alert: $e");
    }
  }

  Future<void> saveReportToBackend(
    String shipmentNum,
    double t,
    int h,
    String g1,
    String g2,
    String d,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse("http://127.0.0.1:8000/save-report"),
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "shipment_number": shipmentNum,
          "temperature": t,
          "humidity": h,
          "gas_1": g1,
          "gas_2": g2,
          "door_condition": d,
          "latitude": _latitude,
          "longitude": _longitude,
        }),
      );
      debugPrint("Report Save Response: ${response.body}");
    } catch (e) {
      debugPrint("Error saving report: $e");
    }
  }

  void _showWarningDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            backgroundColor: const Color(0xFFD32F2F).withOpacity(0.9),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.yellow,
                  size: 60,
                ),
                const SizedBox(height: 15),
                const Text(
                  "تحذير! تم اكتشاف إنذار\nيرجى اتخاذ الإجراء المناسب",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 25),
                ElevatedButton(
                  onPressed: () {
                    _audioPlayer.stop();
                    isWarningShown = false;
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4332),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "تأكيد",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _reportTimer?.cancel();
    _gpsTimer?.cancel();
    _doorOpenTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bool isDark = settingsProvider.isDarkMode;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFC8D6CA),
      drawer: const SafeChainUserDrawer(),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFB9E4D1),
        elevation: 0,
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu, color: textColor),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          "حالة الشاحنات",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textColor),
            onPressed: () {
              loadTruckData();
              _fetchGPSLocation();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8),
            child: CircleAvatar(
              backgroundColor: isDark ? Colors.grey[800] : Colors.white,
              radius: 20,
              child: ClipOval(
                child: Image.asset(
                  'assets/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.eco, color: Colors.green),
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1B4332),
          labelColor: const Color(0xFF1B4332),
          unselectedLabelColor: textColor.withOpacity(0.6),
          tabs: const [
            Tab(icon: Icon(Icons.sensors), text: "الحساسات"),
            Tab(icon: Icon(Icons.show_chart), text: "تحليل البيانات"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSensorsTab(isDark, textColor),
          _buildGrafanaTab(isDark),
        ],
      ),
    );
  }

  Widget _buildSensorsTab(bool isDark, Color textColor) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 20, left: 15, right: 15),
            height: 22,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFFD9E3D9),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(25),
                  bottomRight: Radius.circular(25),
                ),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (shipmentNumber.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.white70,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                "رقم الشحنة: $shipmentNumber",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              if (tripType.isNotEmpty)
                                Text(
                                  "النوع: $tripType",
                                  style: TextStyle(fontSize: 10, color: textColor),
                                ),
                            ],
                          ),
                        ),

                      if (!_isLoadingLimits)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.white70,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                "الحرارة: ${_minTemp.toStringAsFixed(1)}°C - ${_maxTemp.toStringAsFixed(1)}°C",
                                style: TextStyle(fontSize: 10, color: textColor),
                              ),
                              Text(
                                "الرطوبة: $_minHumidity% - $_maxHumidity%",
                                style: TextStyle(fontSize: 10, color: textColor),
                              ),
                            ],
                          ),
                        ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSensorCard(
                            "حساس غاز 1\n$gas1Status",
                            gas1Status == "غير طبيعي" ? Colors.red : Colors.green,
                            gas1Status == "غير طبيعي",
                            isDark,
                          ),
                          _buildSensorCard(
                            "حساس غاز 2\n$gas2Status",
                            gas2Status == "غير طبيعي" ? Colors.red : Colors.green,
                            gas2Status == "غير طبيعي",
                            isDark,
                          ),
                          _buildSensorCard(
                            "حالة الباب\n$doorStatus",
                            doorStatus == "مفتوح" ? Colors.red : Colors.green,
                            doorStatus == "مفتوح",
                            isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121212) : Colors.white,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Icon(Icons.thermostat, size: 30, color: Colors.orange),
                                const SizedBox(height: 5),
                                Text(
                                  temp != null ? "${temp!.toStringAsFixed(1)}°C" : "--",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: temp != null && temp! > _maxTemp
                                        ? Colors.red
                                        : (temp != null && temp! < _minTemp
                                            ? Colors.blue
                                            : textColor),
                                  ),
                                ),
                                Text(
                                  "درجة الحرارة",
                                  style: TextStyle(fontSize: 12, color: textColor),
                                ),
                              ],
                            ),
                            Container(width: 1, height: 50, color: Colors.grey),
                            Column(
                              children: [
                                const Icon(Icons.water_drop, size: 30, color: Colors.blue),
                                const SizedBox(height: 5),
                                Text(
                                  humidity != null ? "${humidity!.toStringAsFixed(0)}%" : "--",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: humidity != null && humidity! > _maxHumidity
                                        ? Colors.red
                                        : (humidity != null && humidity! < _minHumidity
                                            ? Colors.blue
                                            : textColor),
                                  ),
                                ),
                                Text(
                                  "الرطوبة",
                                  style: TextStyle(fontSize: 12, color: textColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (lastUpdated.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            "آخر تحديث: $lastUpdated",
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),
                      Text(
                        "الموقع الحالي",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : const Color(0xFF2D4B3E),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildInteractiveGPSMap(isDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
        ],
      ),
    );
  }

  Widget _buildGrafanaTab(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.show_chart,
                      size: 16,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "تحليل درجة الحرارة والرطوبة عبر الزمن",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.access_time,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      onSelected: (value) {
                        setState(() => _chartTimeRange = value);
                        _fetchChartData();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: '1h', child: Text('آخر ساعة')),
                        const PopupMenuItem(value: '6h', child: Text('آخر 6 ساعات')),
                        const PopupMenuItem(value: '24h', child: Text('آخر 24 ساعة')),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      onPressed: _fetchChartData,
                      tooltip: "تحديث",
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingChartData
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildTemperatureChart(isDark),
                        const SizedBox(height: 30),
                        _buildHumidityChart(isDark),
                      ],
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                const SizedBox(width: 4),
                Text(
                  "اضغط على الرسم للحصول على تفاصيل القيم",
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureChart(bool isDark) {
    if (_tempData.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          "لا توجد بيانات درجة الحرارة",
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "درجة الحرارة (°C)",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}°',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() % 5 == 0) {
                        return Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 10,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: _tempData,
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  // ✅ تعديل: gradient بدل color
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withOpacity(0.3),
                        Colors.orange.withOpacity(0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                if (_maxTemp > 0)
                  LineChartBarData(
                    spots: [
                      FlSpot(0, _maxTemp),
                      FlSpot(_tempData.length.toDouble(), _maxTemp),
                    ],
                    isCurved: false,
                    color: Colors.red,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
                if (_minTemp < 100)
                  LineChartBarData(
                    spots: [
                      FlSpot(0, _minTemp),
                      FlSpot(_tempData.length.toDouble(), _minTemp),
                    ],
                    isCurved: false,
                    color: Colors.blue,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
              ],
              // ✅ تعديل: إضافة getTooltipColor
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => Colors.black87,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '${spot.y.toStringAsFixed(1)}°C',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem("الحد الأقصى", Colors.red, isDark),
            const SizedBox(width: 16),
            _buildLegendItem("القراءة الحالية", Colors.orange, isDark),
            const SizedBox(width: 16),
            _buildLegendItem("الحد الأدنى", Colors.blue, isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildHumidityChart(bool isDark) {
    if (_humidityData.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          "لا توجد بيانات الرطوبة",
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "الرطوبة (%)",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}%',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() % 5 == 0) {
                        return Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 10,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey[300]!,
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: _humidityData,
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  // ✅ تعديل: gradient بدل color
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.3),
                        Colors.blue.withOpacity(0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                if (_maxHumidity > 0 && _maxHumidity < 100)
                  LineChartBarData(
                    spots: [
                      FlSpot(0, _maxHumidity.toDouble()),
                      FlSpot(_humidityData.length.toDouble(), _maxHumidity.toDouble()),
                    ],
                    isCurved: false,
                    color: Colors.red,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
                if (_minHumidity > 0)
                  LineChartBarData(
                    spots: [
                      FlSpot(0, _minHumidity.toDouble()),
                      FlSpot(_humidityData.length.toDouble(), _minHumidity.toDouble()),
                    ],
                    isCurved: false,
                    color: Colors.cyan,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
              ],
              // ✅ تعديل: إضافة getTooltipColor
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => Colors.black87,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '${spot.y.toStringAsFixed(0)}%',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem("الحد الأقصى", Colors.red, isDark),
            const SizedBox(width: 16),
            _buildLegendItem("القراءة الحالية", Colors.blue, isDark),
            const SizedBox(width: 16),
            _buildLegendItem("الحد الأدنى", Colors.cyan, isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorCard(String title, Color color, bool isAlert, bool isDark) {
    return Container(
      width: 100,
      height: 110,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: 0.7,
                strokeWidth: 3,
                backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Icon(
                isAlert ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: color,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveGPSMap(bool isDark) {
    LatLng center = LatLng(24.7136, 46.6753);

    if (_pathPoints.isNotEmpty) {
      final lastPoint = _pathPoints.last;
      final lat = lastPoint['latitude'];
      final lng = lastPoint['longitude'];
      if (lat != null && lng != null) {
        center = LatLng(
          (lat is double) ? lat : (lat as num).toDouble(),
          (lng is double) ? lng : (lng as num).toDouble(),
        );
      }
    } else if (_latitude != null && _longitude != null) {
      center = LatLng(_latitude!, _longitude!);
    }

    return Container(
      height: 350,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.white,
          width: 4,
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _pathPoints.isEmpty ? 12.0 : 13.0,
                minZoom: 5.0,
                maxZoom: 18.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.safe_chain',
                ),
                if (_pathPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _pathPoints.map<LatLng>((point) {
                          final lat = point['latitude'];
                          final lng = point['longitude'];
                          return LatLng(
                            (lat is double) ? lat : (lat as num).toDouble(),
                            (lng is double) ? lng : (lng as num).toDouble(),
                          );
                        }).toList(),
                        strokeWidth: 4.0,
                        color: Colors.blue,
                        borderColor: Colors.white,
                        borderStrokeWidth: 1.0,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_latitude != null && _longitude != null)
                      Marker(
                        point: LatLng(_latitude!, _longitude!),
                        width: 80,
                        height: 80,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4),
                                ],
                              ),
                              child: const Text(
                                'موقعي',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.local_shipping,
                              color: Colors.blue,
                              size: 32,
                              shadows: [
                                Shadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () {
                    _fetchGPSLocation();
                    _fetchTruckPath();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.refresh,
                      size: 20,
                      color: _isLoadingLocation || _isLoadingPath
                          ? Colors.grey
                          : Colors.green,
                    ),
                  ),
                ),
              ),
            ),
            if (_locationName.isNotEmpty)
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _locationName,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoadingPath)
              const Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),
          ],
        ),
      ),
    );
  }
}