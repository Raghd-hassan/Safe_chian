// admin_files/control.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'app_drawer.dart';
import 'settings_provider.dart';

class TruckControlPanelApp extends StatefulWidget {
  const TruckControlPanelApp({super.key});

  @override
  State<TruckControlPanelApp> createState() => _TruckControlPanelAppState();
}

class _TruckControlPanelAppState extends State<TruckControlPanelApp> {
  int _totalTrucks = 0;
  int _compliantTrucks = 0;
  int _nonCompliantTrucks = 0;
  int _totalUsers = 0;
  int _activeTrips = 0;
  int _totalReports = 0;
  int _totalAlerts = 0;
  String _compliantPercent = "0%";
  String _nonCompliantPercent = "0%";

  bool _isLoading = false;
  bool _isRefreshing = false;
  String _authToken = "";
  String? _errorMessage;
  int _consecutiveFailures = 0;

  List<dynamic> _truckLocations = [];
  final MapController _mapController = MapController();
  Timer? _autoRefreshTimer;

  static const String _baseUrl = "http://127.0.0.1:8000";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokenAndFetch();
    });
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _authToken.isNotEmpty) {
        _fetchDashboardData(refresh: true);
        _fetchTruckLocations();
      }
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? prefs.getString('auth_token');
  }

  Future<void> _loadTokenAndFetch() async {
    _authToken = await _getToken() ?? '';

    if (_authToken.isNotEmpty) {
      await _fetchDashboardData();
      await _fetchTruckLocations();
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = "الرجاء تسجيل الدخول أولاً";
        });
      }
    }
  }

  Future<void> _fetchDashboardData({bool refresh = false}) async {
    if (_authToken.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("غير مسجل دخول")));
      }
      return;
    }

    if (!mounted) return;

    if (refresh) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

    setState(() => _errorMessage = null);

    try {
      final response = await http
          .get(
            Uri.parse("$_baseUrl/admin/dashboard"),
            headers: {
              "Authorization": "Bearer $_authToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _totalTrucks = data['total_trucks'] ?? 0;
          _compliantTrucks = data['compliant_trucks'] ?? 0;
          _nonCompliantTrucks = data['non_compliant_trucks'] ?? 0;
          _totalUsers = data['total_users'] ?? 0;
          _activeTrips = data['active_trips'] ?? 0;
          _totalReports = data['total_reports'] ?? 0;
          _totalAlerts = data['total_alerts'] ?? 0;
          _consecutiveFailures = 0;

          if (_totalTrucks > 0) {
            _compliantPercent =
                "${((_compliantTrucks / _totalTrucks) * 100).toStringAsFixed(1)}%";
            _nonCompliantPercent =
                "${((_nonCompliantTrucks / _totalTrucks) * 100).toStringAsFixed(1)}%";
          } else {
            _compliantPercent = "0%";
            _nonCompliantPercent = "0%";
          }

          if (refresh && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("تم تحديث البيانات"),
                duration: Duration(seconds: 1),
              ),
            );
          }
        });
      } else if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        await prefs.remove('auth_token');
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } else {
        setState(() {
          _errorMessage = "خطأ في تحميل البيانات: ${response.statusCode}";
          _consecutiveFailures++;
          if (_consecutiveFailures >= 3) _stopAutoRefresh();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "خطأ في الاتصال بالخادم";
          _consecutiveFailures++;
          if (_consecutiveFailures >= 3) _stopAutoRefresh();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _fetchTruckLocations() async {
    if (_authToken.isEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse("$_baseUrl/admin/truck-locations"),
            headers: {
              "Authorization": "Bearer $_authToken",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("🚛 Truck locations response: ${data['truck_locations']}");

        setState(() {
          _truckLocations = data['truck_locations'] ?? [];
        });

        debugPrint("🗺️ Total trucks on map: ${_truckLocations.length}");

        if (_truckLocations.isEmpty) {
          debugPrint("⚠️ No truck locations found. Check if:");
          debugPrint("  1. There are active trips");
          debugPrint("  2. Reports have GPS data (latitude/longitude)");
          debugPrint("  3. Reports are recent");
        }
      } else {
        debugPrint("❌ Truck locations API error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Error fetching truck locations: $e");
    }
  }

  Future<void> _onRefresh() async {
    await _fetchDashboardData(refresh: true);
    await _fetchTruckLocations();
  }

  Widget _buildTruckMap(bool isDark, Color textColor) {
    LatLng center = LatLng(24.7136, 46.6753);

    if (_truckLocations.isNotEmpty) {
      final firstTruck = _truckLocations.first;
      final lat = firstTruck['current_latitude'];
      final lng = firstTruck['current_longitude'];

      if (lat != null && lng != null) {
        center = LatLng(
          (lat is double) ? lat : (lat as num).toDouble(),
          (lng is double) ? lng : (lng as num).toDouble(),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.refresh, color: textColor),
              onPressed: _fetchTruckLocations,
              tooltip: 'تحديث المواقع',
            ),
            Text(
              "مواقع الشاحنات الحالية :",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 400,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: isDark ? Colors.grey[800]! : Colors.white,
              width: 6,
            ),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _truckLocations.isEmpty ? 12.0 : 13.0,
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
                PolylineLayer(
                  polylines: _truckLocations.map<Polyline>((truck) {
                    final path = truck['path'] as List<dynamic>;
                    final tripStatus = truck['trip_status'] as String;
                    final pathColor =
                        tripStatus == 'completed' ? Colors.green : Colors.red;

                    final points = path.map<LatLng>((point) {
                      final lat = point['latitude'];
                      final lng = point['longitude'];
                      return LatLng(
                        (lat is double) ? lat : (lat as num).toDouble(),
                        (lng is double) ? lng : (lng as num).toDouble(),
                      );
                    }).toList();

                    return Polyline(
                      points: points,
                      strokeWidth: 4.0,
                      color: pathColor,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.0,
                    );
                  }).toList(),
                ),
                MarkerLayer(
                  markers: _truckLocations.map<Marker>((truck) {
                    final lat = truck['current_latitude'];
                    final lng = truck['current_longitude'];
                    final truckName = truck['truck_name'] as String;
                    final tripStatus = truck['trip_status'] as String;

                    if (lat == null || lng == null) {
                      return Marker(
                        point: LatLng(0, 0),
                        child: const SizedBox.shrink(),
                      );
                    }

                    final markerColor =
                        tripStatus == 'completed' ? Colors.green : Colors.red;
                    final latDouble =
                        (lat is double) ? lat : (lat as num).toDouble();
                    final lngDouble =
                        (lng is double) ? lng : (lng as num).toDouble();

                    return Marker(
                      point: LatLng(latDouble, lngDouble),
                      width: 80,
                      height: 80,
                      child: GestureDetector(
                        onTap: () => _showTruckInfo(truck),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Text(
                                truckName,
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.local_shipping,
                              color: markerColor,
                              size: 32,
                              shadows: const [
                                Shadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem(Colors.green, "مكتملة", isDark),
            const SizedBox(width: 20),
            _buildLegendItem(Colors.red, "نشطة", isDark),
          ],
        ),
        if (_truckLocations.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Text(
                "لا توجد شاحنات حالياً",
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label, bool isDark) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }

  void _showTruckInfo(dynamic truck) {
    final temp = truck['temperature'];
    final humidity = truck['humidity'];
    final tripStatus = truck['trip_status'] as String;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.local_shipping,
              color: tripStatus == 'completed' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                truck['truck_name'] as String,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              "الحالة",
              tripStatus == 'completed' ? "مكتملة" : "نشطة",
            ),
            _buildInfoRow("السائق", truck['driver_name'] as String),
            _buildInfoRow("رقم الشحنة", truck['shipment_number'] as String),
            _buildInfoRow("الحرارة", temp != null ? "${temp}°C" : "غير متوفر"),
            _buildInfoRow(
              "الرطوبة",
              humidity != null ? "${humidity}%" : "غير متوفر",
            ),
            _buildInfoRow(
              "حالة الباب",
              truck['door_condition'] as String? ?? "غير معروف",
            ),
            _buildInfoRow("آخر تحديث", truck['last_updated'] as String),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إغلاق"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildTopLogo(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Center(
        child: CircleAvatar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          radius: 20,
          backgroundImage: const AssetImage('assets/logo.png'),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String? perc,
    IconData icon,
    Color bg,
    Color txt,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: txt, size: 28),
              if (perc != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: txt.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    perc,
                    style: TextStyle(
                      color: txt,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: txt,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: txt,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final bool isDark = settingsProvider.isDarkMode;
        final Color scaffoldBg =
            isDark ? const Color(0xFF121212) : const Color(0xFFC8D6CA);
        final Color appBarBg =
            isDark ? Colors.black : const Color(0xFFB9E4D1);
        final Color textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: scaffoldBg,
          drawer: const SafeChainDrawer(),
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: 0,
            centerTitle: true,
            title: Text(
              "لوحة مراقبة الشاحنات",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 18,
              ),
            ),
            actions: [
              _buildTopLogo(isDark),
              IconButton(
                icon: Icon(
                  _isRefreshing ? Icons.hourglass_empty : Icons.refresh,
                  color: textColor,
                ),
                onPressed: _isRefreshing ? null : _onRefresh,
                tooltip: 'تحديث البيانات',
              ),
            ],
            iconTheme: IconThemeData(color: textColor),
          ),
          body: _buildBodyContent(isDark, textColor),
        );
      },
    );
  }

  Widget _buildBodyContent(bool isDark, Color textColor) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1B4332)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: isDark ? Colors.redAccent : Colors.red[700],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(fontSize: 16, color: textColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadTokenAndFetch,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF1B4332),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              _buildStatCard(
                "إجمالي الشاحنات",
                _totalTrucks.toString(),
                null,
                Icons.local_shipping,
                isDark ? const Color(0xFF1B4332) : const Color(0xFF1E452F),
                Colors.white,
              ),
              const SizedBox(height: 15),
              _buildStatCard(
                "رحلات نشطة",
                _activeTrips.toString(),
                null,
                Icons.directions_car,
                isDark ? const Color(0xFF2C2C2C) : Colors.orange[50]!,
                isDark ? Colors.orangeAccent : Colors.orange[800]!,
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      "شاحنات ملتزمة",
                      _compliantTrucks.toString(),
                      _compliantPercent,
                      Icons.check_circle,
                      isDark ? const Color(0xFF2C2C2C) : Colors.green[50]!,
                      isDark ? Colors.greenAccent : Colors.green[800]!,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildStatCard(
                      "شاحنات غير ملتزمة",
                      _nonCompliantTrucks.toString(),
                      _nonCompliantPercent,
                      Icons.warning_amber_rounded,
                      isDark ? const Color(0xFF2C2C2C) : Colors.red[50]!,
                      isDark ? Colors.redAccent : Colors.red[800]!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              _buildTruckMap(isDark, textColor),
              const SizedBox(height: 10),
              Text(
                "آخر تحديث: ${DateTime.now().toString().substring(0, 19)}",
                style: TextStyle(
                  fontSize: 10,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}