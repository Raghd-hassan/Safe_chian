import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../admin_files/settings_provider.dart';
import 'app_drawer.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isTripLoading = false;
  String? _activeShipment;
  String _userName = "مستخدم";

  // ✅ Store all trucks and products for multi-step flow
  final List<dynamic> _trucks = [];
  final List<dynamic> _products = [];

  static const String _baseUrl = "http://127.0.0.1:8000";

  // ─────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadTruckData();
    _loadProducts();
    _loadActiveShipment();
    _checkActiveTrip(); // Check backend for active trip
  }

  // ─────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  void _goTo(String route) => Navigator.pushNamed(context, route);

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color,
      ),
    );
  }

  // ─────────────────────────────────────────
  // Data Loading
  // ─────────────────────────────────────────

  /// تحميل اسم المستخدم المحفوظ عند تسجيل الدخول
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    if (name.isNotEmpty && mounted) {
      setState(() => _userName = name);
    }
  }

  /// Check for active trip from backend
  Future<void> _checkActiveTrip() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final response = await http
          .get(
            Uri.parse("$_baseUrl/user/active-trip"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shipmentNumber = data['shipment_number'] as String?;

        if (shipmentNumber != null && shipmentNumber.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_shipment', shipmentNumber);
          if (mounted) {
            setState(() => _activeShipment = shipmentNumber);
          }
        }
      }
    } catch (e) {
      debugPrint("Check active trip error: $e");
    }
  }

  /// جلب أول شاحنة تخص المستخدم من الباك اند
  Future<void> _loadTruckData() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final response = await http
          .get(
            Uri.parse("$_baseUrl/trucks"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          setState(() {
            _trucks.clear();
            _trucks.addAll(data);
          });
        }
      } else if (response.statusCode == 401) {
        _redirectToLogin();
      }
    } catch (e) {
      debugPrint("Load trucks error: $e");
    }
  }

  /// جلب جميع المنتجات المتاحة
  Future<void> _loadProducts() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final response = await http
          .get(
            Uri.parse("$_baseUrl/products"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          setState(() {
            _products.clear();
            _products.addAll(data);
          });
        }
      }
    } catch (e) {
      debugPrint("Load products error: $e");
    }
  }

  /// تحميل رقم الشحنة النشطة من الذاكرة المحلية
  Future<void> _loadActiveShipment() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _activeShipment = prefs.getString('active_shipment'));
    }
  }

  void _redirectToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // ─────────────────────────────────────────
  // Trip Logic
  // ─────────────────────────────────────────

  /// Step 1: User clicks "Start Trip" → Check for active trip first
  Future<void> _startTrip() async {
    if (_isTripLoading) return;

    // Check if there's already an active trip
    if (_activeShipment != null && _activeShipment!.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
              SizedBox(width: 12),
              Expanded(child: Text("رحلة نشطة موجودة")),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "لديك رحلة نشطة حالياً:",
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _activeShipment!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "يجب إنهاء الرحلة الحالية قبل بدء رحلة جديدة",
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("حسناً"),
            ),
          ],
        ),
      );
      return;
    }

    // Load products if not loaded yet
    if (_products.isEmpty) {
      _showSnack("جاري تحميل المنتجات...", Colors.orange);
      await _loadProducts();
      if (_products.isEmpty) {
        _showSnack("لا توجد منتجات متاحة", Colors.red);
        return;
      }
    }

    // Step 2: Show products dialog with multi-select
    final selectedProductIds = await _showProductsDialog();
    if (selectedProductIds == null || selectedProductIds.isEmpty) {
      return; // User cancelled or didn't select any products
    }

    // Step 3: If more than 1 truck → show truck selection dialog
    int? selectedTruckId;
    if (_trucks.length > 1) {
      selectedTruckId = await _showTruckSelectionDialog();
      if (selectedTruckId == null) {
        return; // User cancelled
      }
    } else if (_trucks.length == 1) {
      selectedTruckId = _trucks[0]["id"] as int;
    } else {
      _showSnack("لم يتم العثور على شاحنة مسجلة", Colors.red);
      return;
    }

    // Step 4: API call with truck_id + product_ids[]
    await _performStartTrip(selectedTruckId, selectedProductIds);
  }

  /// Step 2: Show products dialog with multi-select checkboxes
  Future<List<int>?> _showProductsDialog() async {
    final selectedIds = <int>{};

    return showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.inventory_2, color: Color(0xFF1B4332)),
                  SizedBox(width: 10),
                  Text("اختر المنتجات"),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: _products.isEmpty
                    ? const Center(child: Text("لا توجد منتجات"))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final productId = product["id"] as int;
                          final productName = product["product_name"] as String;

                          return CheckboxListTile(
                            title: Text(productName),
                            value: selectedIds.contains(productId),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selectedIds.add(productId);
                                } else {
                                  selectedIds.remove(productId);
                                }
                              });
                            },
                            activeColor: const Color(0xFF1B4332),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.pop(ctx, selectedIds.toList()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4332),
                    disabledBackgroundColor: Colors.grey,
                  ),
                  child: Text(
                    "التالي (${selectedIds.length})",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Step 3: Show truck selection dialog (if > 1 truck)
  Future<int?> _showTruckSelectionDialog() async {
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.local_shipping, color: Color(0xFF1B4332)),
              SizedBox(width: 10),
              Text("اختر الشاحنة"),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _trucks.length,
              itemBuilder: (context, index) {
                final truck = _trucks[index];
                final truckId = truck["id"] as int;
                final truckName = truck["name"] as String;

                return ListTile(
                  leading: const Icon(
                    Icons.local_shipping,
                    color: Color(0xFF1B4332),
                  ),
                  title: Text(truckName),
                  onTap: () => Navigator.pop(ctx, truckId),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("إلغاء"),
            ),
          ],
        );
      },
    );
  }

  /// Step 4: Perform the actual API call to start trip
  Future<void> _performStartTrip(int truckId, List<int> productIds) async {
    setState(() => _isTripLoading = true);

    final token = await _getToken();
    if (token == null) {
      _showSnack("يرجى تسجيل الدخول أولاً", Colors.red);
      setState(() => _isTripLoading = false);
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse("$_baseUrl/start-trip"),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
            body: jsonEncode({"truck_id": truckId, "product_ids": productIds}),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shipmentNumber = data["shipment_number"] ?? "";

        if (shipmentNumber.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_shipment', shipmentNumber);
          setState(() => _activeShipment = shipmentNumber);

          // Step 5: Success dialog shows shipment number
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 32),
                    SizedBox(width: 12),
                    Expanded(child: Text("تم بدء الرحلة بنجاح")),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      color: Color(0xFF1B4332),
                      size: 60,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "رقم الشحنة:",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        shipmentNumber,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B4332),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4332),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      "حسناً",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            );
          }
        } else {
          _showSnack("فشل بدء الرحلة: رقم الشحنة غير موجود", Colors.red);
        }
      } else {
        final errorData = jsonDecode(response.body);
        _showSnack(
          "فشل بدء الرحلة: ${errorData['detail'] ?? errorData['message'] ?? response.statusCode}",
          Colors.red,
        );
      }
    } catch (e) {
      debugPrint("Start trip error: $e");
      if (mounted) _showSnack("حدث خطأ أثناء بدء الرحلة", Colors.red);
    } finally {
      if (mounted) setState(() => _isTripLoading = false);
    }
  }

  Future<void> _endTrip() async {
    if (_isTripLoading) return;

    if (_activeShipment == null) {
      _showSnack("لا توجد رحلة نشطة حالياً", Colors.orange);
      return;
    }

    // تأكيد قبل إنهاء الرحلة
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("إنهاء الرحلة"),
        content: Text("هل تريد إنهاء الرحلة:\n$_activeShipment ؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("إنهاء", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isTripLoading = true);

    final token = await _getToken();
    if (token == null) {
      _showSnack("يرجى تسجيل الدخول أولاً", Colors.red);
      setState(() => _isTripLoading = false);
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse(
              "$_baseUrl/end-trip?shipment_number=${Uri.encodeComponent(_activeShipment!)}",
            ),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_shipment');
        setState(() => _activeShipment = null);
        _showSnack("تم إنهاء الرحلة بنجاح ✅", Colors.green);
      } else {
        final errorData = jsonDecode(response.body);
        _showSnack(
          "فشل إنهاء الرحلة: ${errorData['detail'] ?? errorData['message'] ?? response.statusCode}",
          Colors.red,
        );
      }
    } catch (e) {
      debugPrint("End trip error: $e");
      if (mounted) _showSnack("حدث خطأ أثناء إنهاء الرحلة", Colors.red);
    } finally {
      if (mounted) setState(() => _isTripLoading = false);
    }
  }

  // ─────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bool isDark = settingsProvider.isDarkMode;

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
          builder: (ctx) => IconButton(
            icon: Icon(
              Icons.menu,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          "Safe Chain - الرئيسية",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              radius: 20,
              child: ClipOval(
                child: Image.asset(
                  'assets/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) =>
                      const Icon(Icons.eco, color: Colors.green),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
              child: Column(
                children: [
                  _buildWelcomeCard(isDark),
                  const SizedBox(height: 25),
                  _buildTripButtons(isDark),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 30,
                    runSpacing: 30,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildNavCard(
                        title: "حالة الشاحنات",
                        icon: Icons.local_shipping_outlined,
                        route: '/user_truck_status',
                        isDark: isDark,
                      ),
                      _buildNavCard(
                        title: "التقارير",
                        icon: Icons.description_outlined,
                        route: '/user_reports',
                        isDark: isDark,
                      ),
                      _buildNavCard(
                        title: "سجل التنبيهات",
                        icon: Icons.warning_amber_rounded,
                        route: '/user_alerts',
                        isDark: isDark,
                        accentColor: Colors.red[700],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // Widgets
  // ─────────────────────────────────────────

  Widget _buildWelcomeCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFF1B4332),
            child: Icon(Icons.person, color: Colors.white, size: 45),
          ),
          const SizedBox(height: 15),
          Text(
            "مرحباً، $_userName",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          if (_activeShipment != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_shipping,
                    color: Colors.green,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "رحلة نشطة: $_activeShipment",
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripButtons(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── زر بدء الرحلة ──
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isTripLoading ? null : _startTrip,
            icon: _isTripLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.play_arrow, color: Colors.white),
            label: const Text(
              "بدء الرحلة",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              disabledBackgroundColor: Colors.green.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 15),
        // ── زر إنهاء الرحلة ──
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isTripLoading ? null : _endTrip,
            icon: _isTripLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.stop, color: Colors.white),
            label: const Text(
              "إنهاء الرحلة",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _activeShipment != null
                  ? Colors.red
                  : Colors.grey,
              disabledBackgroundColor: Colors.red.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavCard({
    required String title,
    required IconData icon,
    required String route,
    required bool isDark,
    Color? accentColor,
  }) {
    final color = accentColor ?? const Color(0xFF1B4332);

    return GestureDetector(
      onTap: () => _goTo(route),
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              blurRadius: 15,
              offset: const Offset(0, 8),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 45, color: color),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1B4332),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
