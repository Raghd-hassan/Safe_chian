// admin_files/security_limits.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_drawer.dart';
import 'settings_provider.dart';

class SecurityLimitsSettings extends StatefulWidget {
  final String? shipmentNumber;
  const SecurityLimitsSettings({super.key, this.shipmentNumber});

  @override
  State<SecurityLimitsSettings> createState() => _SecurityLimitsSettingsState();
}

class _SecurityLimitsSettingsState extends State<SecurityLimitsSettings> {
  final TextEditingController shipmentController = TextEditingController();
  final TextEditingController minTempController = TextEditingController();
  final TextEditingController maxTempController = TextEditingController();
  final TextEditingController minHumidityController = TextEditingController();
  final TextEditingController maxHumidityController = TextEditingController();
  final TextEditingController doorDurationController = TextEditingController();
  final TextEditingController doorOpenCountController = TextEditingController();

  bool _isLoadingShipment = false;
  bool _isSaving = false;
  String _authToken = '';

  Map<String, dynamic>? _shipmentInfo;
  bool _shipmentLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.shipmentNumber != null && widget.shipmentNumber!.isNotEmpty) {
      shipmentController.text = widget.shipmentNumber!;
    }

    // Set default door values
    doorDurationController.text = '60';
    doorOpenCountController.text = '5';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadToken();
      // After token is loaded, if shipment number was provided, load its info
      if (widget.shipmentNumber != null &&
          widget.shipmentNumber!.isNotEmpty &&
          _authToken.isNotEmpty) {
        _loadShipmentInfo();
      }
    });
  }

  @override
  void dispose() {
    shipmentController.dispose();
    minTempController.dispose();
    maxTempController.dispose();
    minHumidityController.dispose();
    maxHumidityController.dispose();
    doorDurationController.dispose();
    doorOpenCountController.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken =
        prefs.getString('token') ?? prefs.getString('auth_token') ?? '';

    if (_authToken.isEmpty) {
      _showSnackBar('الرجاء تسجيل الدخول أولاً', Colors.red);
    }
  }

  Future<void> _loadShipmentInfo() async {
    final shipmentNumber = shipmentController.text.trim();

    if (shipmentNumber.isEmpty) {
      _showSnackBar('الرجاء إدخال رقم الشحنة', Colors.orange);
      return;
    }

    if (_authToken.isEmpty) {
      _showSnackBar('غير مسجل دخول', Colors.red);
      return;
    }

    setState(() {
      _isLoadingShipment = true;
      _shipmentLoaded = false;
      _shipmentInfo = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse(
              'http://127.0.0.1:8000/admin/shipment-info/$shipmentNumber',
            ),
            headers: {
              'Authorization': 'Bearer $_authToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _shipmentInfo = data;
          _shipmentLoaded = true;
        });

        // Auto-fill fields with calculated or existing limits
        final existingLimits = data['existing_limits'];
        final autoLimits = data['auto_calculated_limits'];

        if (existingLimits != null) {
          // Use existing limits if available
          minTempController.text =
              existingLimits['min_temperature']?.toString() ?? '';
          maxTempController.text =
              existingLimits['max_temperature']?.toString() ?? '';
          minHumidityController.text =
              existingLimits['min_humidity']?.toString() ?? '';
          maxHumidityController.text =
              existingLimits['max_humidity']?.toString() ?? '';
          doorDurationController.text =
              existingLimits['door_open_duration']?.toString() ?? '60';
          doorOpenCountController.text =
              existingLimits['door_open_count']?.toString() ?? '5';

          _showSnackBar('تم تحميل الحدود الموجودة', Colors.blue);
        } else if (autoLimits != null) {
          // Use auto-calculated limits
          minTempController.text =
              autoLimits['min_temperature']?.toString() ?? '';
          maxTempController.text =
              autoLimits['max_temperature']?.toString() ?? '';
          minHumidityController.text =
              autoLimits['min_humidity']?.toString() ?? '';
          maxHumidityController.text =
              autoLimits['max_humidity']?.toString() ?? '';

          _showSnackBar('تم حساب الحدود تلقائياً من المنتجات', Colors.green);
        } else {
          _showSnackBar('لا توجد منتجات لحساب الحدود تلقائياً', Colors.orange);
        }
      } else if (response.statusCode == 401) {
        if (mounted)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      } else if (response.statusCode == 404) {
        _showSnackBar('رقم الشحنة غير موجود', Colors.red);
      } else {
        _showSnackBar(
          'خطأ في تحميل بيانات الشحنة: ${response.statusCode}',
          Colors.red,
        );
      }
    } catch (e) {
      _showSnackBar('خطأ في الاتصال: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoadingShipment = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _saveSettings() async {
    if (_authToken.isEmpty) {
      _showSnackBar('غير مسجل دخول', Colors.red);
      return;
    }

    final shipmentNumber = shipmentController.text.trim();

    if (shipmentNumber.isEmpty) {
      _showSnackBar('الرجاء إدخال رقم الشحنة', Colors.orange);
      return;
    }

    if (!_shipmentLoaded) {
      _showSnackBar('الرجاء البحث عن الشحنة أولاً', Colors.orange);
      return;
    }

    final double? minTemp = double.tryParse(minTempController.text);
    final double? maxTemp = double.tryParse(maxTempController.text);
    final int? minHum = int.tryParse(minHumidityController.text);
    final int? maxHum = int.tryParse(maxHumidityController.text);

    if (minTemp == null ||
        maxTemp == null ||
        minHum == null ||
        maxHum == null) {
      _showSnackBar('الرجاء إدخال جميع القيم بشكل صحيح', Colors.orange);
      return;
    }

    if (minTemp >= maxTemp) {
      _showSnackBar('الحرارة الدنيا يجب أن تكون أقل من العليا', Colors.orange);
      return;
    }

    if (minHum >= maxHum) {
      _showSnackBar('الرطوبة الدنيا يجب أن تكون أقل من العليا', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    final Map<String, dynamic> requestData = {
      'shipment_number': shipmentNumber,
      'min_temperature': minTemp,
      'max_temperature': maxTemp,
      'min_humidity': minHum,
      'max_humidity': maxHum,
      'door_open_duration': int.tryParse(doorDurationController.text) ?? 60,
      'door_open_count': int.tryParse(doorOpenCountController.text) ?? 5,
    };

    try {
      final response = await http
          .post(
            Uri.parse('http://127.0.0.1:8000/admin/save-security-limits'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
            body: jsonEncode(requestData),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _showSnackBar('تم حفظ حدود الأمان بنجاح ✅', Colors.green);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) Navigator.pop(context, true);
        });
      } else {
        String errorMessage = 'فشل حفظ الإعدادات';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage =
              errorData['detail'] ?? errorData['message'] ?? errorMessage;
        } catch (_) {}
        _showSnackBar(errorMessage, Colors.red);
      }
    } catch (e) {
      _showSnackBar('حدث خطأ أثناء الحفظ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final bool isDark = settingsProvider.isDarkMode;

        final Color scaffoldBg = isDark
            ? const Color(0xFF121212)
            : const Color(0xFFC8D6CA);
        final Color appBarBg = isDark ? Colors.black : const Color(0xFFB9E4D1);
        final Color containerColor = isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFE0E0E0);
        final Color textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: scaffoldBg,
          drawer: const SafeChainDrawer(),
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: 0,
            centerTitle: true,
            leading: Builder(
              builder: (context) => IconButton(
                icon: Icon(Icons.menu, color: textColor),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [_buildTopLogo(isDark)],
            title: Text(
              'حدود الأمان',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 18,
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 25,
                        horizontal: 15,
                      ),
                      decoration: BoxDecoration(
                        color: containerColor,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? Colors.black45 : Colors.black12,
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildShipmentSearch(isDark),
                          if (_shipmentLoaded && _shipmentInfo != null) ...[
                            const SizedBox(height: 20),
                            _buildShipmentDetails(isDark),
                            const SizedBox(height: 20),
                            _buildLimitsRows(isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_shipmentLoaded) _buildSaveButton(isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShipmentSearch(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'رقم الشحنة :',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isDark ? Colors.greenAccent : const Color(0xFF1B4332),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: shipmentController,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'مثال: SHP-5-0001',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _loadShipmentInfo(),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _isLoadingShipment ? null : _loadShipmentInfo,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _isLoadingShipment
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.search, color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShipmentDetails(bool isDark) {
    final shipmentInfo = _shipmentInfo!;
    final products = shipmentInfo['products'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF1B4332), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildInfoRow(
            'رقم الشحنة:',
            shipmentInfo['shipment_number'] ?? '',
            isDark,
          ),
          _buildInfoRow(
            'رقم الشاحنة:',
            shipmentInfo['truck_id']?.toString() ?? '',
            isDark,
          ),
          _buildInfoRow(
            'اسم الشاحنة:',
            shipmentInfo['truck_name'] ?? '',
            isDark,
          ),
          _buildInfoRow(
            'الحالة:',
            shipmentInfo['status'] == 'active' ? 'نشط' : 'منتهي',
            isDark,
          ),
          const Divider(height: 20),
          Text(
            'المنتجات المحملة:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.greenAccent : const Color(0xFF1B4332),
            ),
          ),
          const SizedBox(height: 8),
          if (products.isEmpty)
            Text(
              'لا توجد منتجات',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            )
          else
            ...products.map(
              (p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '• ${p['name']}',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.greenAccent : const Color(0xFF1B4332),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitsRows(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSmallInputField(
                'درجة الحرارة العليا (C°) :',
                maxTempController,
                isDark,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildSmallInputField(
                'درجة الحرارة الدنيا (C°) :',
                minTempController,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSmallInputField(
                'الرطوبة العليا (%) :',
                maxHumidityController,
                isDark,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildSmallInputField(
                'الرطوبة الدنيا (%) :',
                minHumidityController,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSmallInputField(
                'مدة فتح الباب (ثانية) :',
                doorDurationController,
                isDark,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildSmallInputField(
                'عدد مرات فتح الباب :',
                doorOpenCountController,
                isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallInputField(
    String label,
    TextEditingController controller,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: isDark ? Colors.white70 : const Color(0xFF1B4332),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSaveButton(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveSettings,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.save, color: Colors.white),
        label: Text(
          _isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1B4332),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 5,
        ),
      ),
    );
  }

  Widget _buildTopLogo(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Center(
        child: CircleAvatar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          radius: 18,
          backgroundImage: const AssetImage('assets/logo.png'),
        ),
      ),
    );
  }
}
