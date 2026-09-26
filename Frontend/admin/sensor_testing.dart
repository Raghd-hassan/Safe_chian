// admin_files/sensor_testing.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_drawer.dart';
import 'settings_provider.dart';
import 'file_saver.dart';

class SensorsCheckPage extends StatefulWidget {
  final String? truckId;
  const SensorsCheckPage({super.key, this.truckId});

  @override
  State<SensorsCheckPage> createState() => _SensorsCheckPageState();
}

class _SensorsCheckPageState extends State<SensorsCheckPage> {
  List<Map<String, dynamic>> _sensors = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isExporting = false;
  String _authToken = '';
  String? _errorMessage;
  int _consecutiveFailures = 0;

  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'الكل';
  Timer? _autoRefreshTimer;

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
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _authToken.isNotEmpty) {
        _fetchSensors(refresh: true);
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
      await _fetchSensors();
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = 'الرجاء تسجيل الدخول أولاً';
        });
      }
    }
  }

  Future<void> _fetchSensors({bool refresh = false}) async {
    if (_authToken.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('غير مسجل دخول')));
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
      final Map<String, String> queryParams = {};
      if (widget.truckId != null && widget.truckId!.isNotEmpty) {
        queryParams['truck_id'] = widget.truckId!;
      }

      String queryString = '';
      if (queryParams.isNotEmpty) {
        queryString =
            '?' +
            queryParams.entries
                .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
                .join('&');
      }

      final response = await http
          .get(
            Uri.parse('http://127.0.0.1:8000/admin/sensors$queryString'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _sensors = List<Map<String, dynamic>>.from(data);
          _consecutiveFailures = 0;
        });

        // Auto-record sensor check if viewing specific truck
        if (widget.truckId != null && widget.truckId!.isNotEmpty && !refresh) {
          _recordSensorCheck();
        }

        if (refresh && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تحديث البيانات'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        await prefs.remove('auth_token');
        if (mounted)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      } else {
        setState(() {
          _errorMessage = 'خطأ في تحميل البيانات: ${response.statusCode}';
          _consecutiveFailures++;
          if (_consecutiveFailures >= 3) _stopAutoRefresh();
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ في الاتصال بالخادم';
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

  Future<void> _onRefresh() async {
    await _fetchSensors(refresh: true);
  }

  Future<void> _recordSensorCheck() async {
    if (_authToken.isEmpty ||
        widget.truckId == null ||
        widget.truckId!.isEmpty) {
      return;
    }

    try {
      final truckId = int.parse(widget.truckId!);
      final sensorCount = _sensors.length;

      await http
          .post(
            Uri.parse(
              'http://127.0.0.1:8000/admin/sensors/record-check?truck_id=$truckId&sensor_count=$sensorCount',
            ),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 5));

      // Silent success - no need to show message to user
    } catch (e) {
      debugPrint('Failed to record sensor check: $e');
      // Silent failure - don't interrupt user experience
    }
  }

  // تصدير Excel محلياً
  Future<void> _exportToExcel() async {
    final filteredSensors = _getFilteredSensors();
    if (filteredSensors.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد بيانات للتصدير'),
            backgroundColor: Colors.orange,
          ),
        );
      return;
    }
    setState(() => _isExporting = true);
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['الحساسات'];
      excel.setDefaultSheet('الحساسات');

      final headers = [
        'رقم الشاحنة',
        'اسم الشاحنة',
        'اسم الحساس',
        'الرقم التسلسلي',
        'الحالة',
      ];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = xl.TextCellValue(headers[i]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString('#1B4332'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        );
      }

      for (var i = 0; i < filteredSensors.length; i++) {
        final s = filteredSensors[i];
        final row = i + 1;
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = xl.TextCellValue(
          s['truck_id']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = xl.TextCellValue(
          s['truck_name']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = xl.TextCellValue(
          s['name']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = xl.TextCellValue(
          s['serial_number']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = xl.TextCellValue(
          s['status']?.toString() ?? '-',
        );
      }

      final bytes = excel.save()!;
      final fileName = 'sensors_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      await saveFile(Uint8List.fromList(bytes), fileName, mimeType);

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير Excel بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // تصدير PDF محلياً
  Future<void> _exportToPdf() async {
    final filteredSensors = _getFilteredSensors();
    if (filteredSensors.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد بيانات للتصدير'),
            backgroundColor: Colors.orange,
          ),
        );
      return;
    }
    setState(() => _isExporting = true);
    try {
      final font = await PdfGoogleFonts.cairoRegular();
      final fontBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => [
            pw.Text(
              'حالة الحساسات',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 18,
                color: PdfColor.fromHex('#1B4332'),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                'رقم الشاحنة',
                'اسم الشاحنة',
                'اسم الحساس',
                'الرقم التسلسلي',
                'الحالة',
              ],
              data: filteredSensors
                  .map(
                    (s) => [
                      s['truck_id']?.toString() ?? '-',
                      s['truck_name']?.toString() ?? '-',
                      s['name']?.toString() ?? '-',
                      s['serial_number']?.toString() ?? '-',
                      s['status']?.toString() ?? '-',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1B4332),
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 10),
              oddRowDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5F5'),
              ),
              cellAlignment: pw.Alignment.center,
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final fileName = 'sensors_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final mimeType = 'application/pdf';

      await saveFile(bytes, fileName, mimeType);

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير PDF بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<Map<String, dynamic>> _getFilteredSensors() {
    var filtered = List<Map<String, dynamic>>.from(_sensors);

    if (_searchController.text.isNotEmpty) {
      filtered = filtered.where((sensor) {
        return sensor['name']?.toString().toLowerCase().contains(
                  _searchController.text.toLowerCase(),
                ) ==
                true ||
            sensor['serial_number']?.toString().toLowerCase().contains(
                  _searchController.text.toLowerCase(),
                ) ==
                true;
      }).toList();
    }

    if (_statusFilter != 'الكل') {
      filtered = filtered
          .where((sensor) => sensor['status']?.toString() == _statusFilter)
          .toList();
    }

    return filtered;
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
        final Color textColor = isDark ? Colors.white : Colors.black87;
        final Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

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
            actions: [
              IconButton(
                icon: Icon(
                  _isRefreshing ? Icons.hourglass_empty : Icons.refresh,
                  color: textColor,
                ),
                onPressed: _isRefreshing ? null : _onRefresh,
                tooltip: 'تحديث البيانات',
              ),
              _buildTopLogo(isDark),
            ],
            title: Text(
              'فحص الحساسات',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          body: Column(
            children: [
              _buildSearchAndFilter(isDark, cardColor, textColor),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _onRefresh,
                  color: const Color(0xFF1B4332),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: _buildSensorsTable(isDark),
                  ),
                ),
              ),
              _buildExportSection(isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFilter(bool isDark, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black12,
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              textAlign: TextAlign.right,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'بحث باسم أو رقم الحساس...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1B4332)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark ? Colors.black26 : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: _statusFilter,
              underline: const SizedBox(),
              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              items: const [
                DropdownMenuItem(value: 'الكل', child: Text('الكل')),
                DropdownMenuItem(value: 'شغال', child: Text('شغال')),
                DropdownMenuItem(value: 'تنبيه', child: Text('تنبيه')),
                DropdownMenuItem(value: 'خطأ', child: Text('خطأ')),
                DropdownMenuItem(value: 'غير معروف', child: Text('غير معروف')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _statusFilter = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsTable(bool isDark) {
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
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _onRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
              ),
              child: const Text(
                'إعادة المحاولة',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    final filteredSensors = _getFilteredSensors();

    if (filteredSensors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sensors_off,
              size: 64,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد بيانات حساسات',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(90),
            1: FixedColumnWidth(110),
            2: FixedColumnWidth(120),
            3: FixedColumnWidth(150),
            4: FixedColumnWidth(100),
          },
          children: [
            _tableHeader([
              'رقم الشاحنة',
              'اسم الشاحنة',
              'اسم الحساس',
              'الرقم التسلسلي',
              'الحالة',
            ], isDark),
            ...List.generate(filteredSensors.length, (index) {
              final sensor = filteredSensors[index];
              return _tableRow(
                [
                  sensor['truck_id']?.toString() ?? '-',
                  sensor['truck_name']?.toString() ?? '-',
                  sensor['name']?.toString() ?? '-',
                  sensor['serial_number']?.toString() ?? '-',
                  sensor['status']?.toString() ?? '-',
                ],
                index % 2 == 0
                    ? (isDark
                          ? const Color(0xFF252525)
                          : const Color(0xFFF5F5F5))
                    : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                isDark,
              );
            }),
          ],
        ),
      ),
    );
  }

  TableRow _tableHeader(List<String> titles, bool isDark) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFF1B4332)),
      children: titles
          .map(
            (t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                t,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  TableRow _tableRow(List<String> cells, Color color, bool isDark) {
    return TableRow(
      decoration: BoxDecoration(color: color),
      children: cells.map((c) {
        Color cellTextColor = isDark ? Colors.white70 : Colors.black87;
        if (c == 'شغال') cellTextColor = Colors.green;
        if (c == 'تنبيه') cellTextColor = Colors.orange;
        if (c == 'خطأ' || c == 'غير معروف') cellTextColor = Colors.red;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            c,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cellTextColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExportSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportToExcel,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.table_chart, color: Colors.white),
              label: const Text(
                'تصدير Excel',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportToPdf,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text(
                'تصدير PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
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
          radius: 18,
          backgroundImage: const AssetImage('assets/logo.png'),
        ),
      ),
    );
  }
}
