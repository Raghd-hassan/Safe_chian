import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../admin_files/settings_provider.dart';
import '../admin_files/file_saver.dart';
import 'app_drawer.dart';

class NotificationsRecordScreen extends StatefulWidget {
  const NotificationsRecordScreen({super.key});

  @override
  State<NotificationsRecordScreen> createState() =>
      _NotificationsRecordScreenState();
}

class _NotificationsRecordScreenState extends State<NotificationsRecordScreen> {
  List reports = [];
  bool isLoading = false;
  bool _isExporting = false; // Track export progress

  // Pagination
  int _currentPage = 1;
  int _totalCount = 0;
  static const int _pageSize = 20;

  // Filters
  String? truckId;
  String? search;
  String? startDate;
  String? endDate;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _truckIdController = TextEditingController();

  // ✅ إصلاح 1: تغيير localhost إلى IP الخادم
  static const String _baseUrl = "http://127.0.0.1:8000";

  // ─────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    fetchReports();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _truckIdController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  void _redirectToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.center),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────
  // Data Fetching
  // ─────────────────────────────────────────
  Future<void> fetchReports({int page = 1}) async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        _redirectToLogin();
        return;
      }

      final Map<String, String> queryParams = {
        'page': page.toString(),
        'limit': _pageSize.toString(),
      };
      if (truckId != null && truckId!.isNotEmpty)
        queryParams['truck_id'] = truckId!;
      if (search != null && search!.isNotEmpty) queryParams['search'] = search!;
      if (startDate != null) queryParams['start_date'] = startDate!;
      if (endDate != null) queryParams['end_date'] = endDate!;

      final queryString =
          "?" +
          queryParams.entries
              .map((e) => "${e.key}=${Uri.encodeComponent(e.value)}")
              .join("&");

      debugPrint("🔍 Fetching: $_baseUrl/reports$queryString");
      debugPrint("📊 Query Params: $queryParams");

      final response = await http
          .get(
            Uri.parse("$_baseUrl/reports$queryString"),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $token",
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        setState(() {
          reports = responseData['data'] as List? ?? [];
          _totalCount = responseData['total'] as int? ?? 0;
          _currentPage = page;
        });
        debugPrint("✅ Loaded ${reports.length} reports (total: $_totalCount)");
      } else if (response.statusCode == 401) {
        _redirectToLogin();
      } else {
        _showSnack("خطأ في جلب البيانات: ${response.statusCode}", Colors.red);
      }
    } catch (e) {
      debugPrint("❌ fetchReports error: $e");
      if (mounted) _showSnack("تعذر الاتصال بالخادم", Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _clearFilters() {
    _truckIdController.clear();
    _searchController.clear();
    setState(() {
      truckId = null;
      search = null;
      startDate = null;
      endDate = null;
    });
    fetchReports();
  }

  // ─────────────────────────────────────────
  // Date Picker
  // ─────────────────────────────────────────
  Future<void> pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1B4332),
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      final formatted =
          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      setState(() {
        if (isStart) {
          startDate = formatted;
        } else {
          endDate = formatted;
        }
      });
    }
  }

  // ─────────────────────────────────────────
  // ✅ تصدير الملفات (مُحسّن بالكامل)
  // ─────────────────────────────────────────
  // Export Functions (Client-Side Generation)
  // ─────────────────────────────────────────
  Future<void> _exportToExcel() async {
    if (reports.isEmpty) {
      if (mounted) {
        _showSnack('لا توجد بيانات للتصدير', Colors.orange);
      }
      return;
    }
    setState(() => _isExporting = true);
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['التقارير'];
      excel.setDefaultSheet('التقارير');

      final headers = [
        'التاريخ',
        'رقم الشحنة',
        'الحرارة',
        'الرطوبة',
        'حساس MQ9',
        'حساس MQ135',
        'حالة الباب',
        'خط العرض',
        'خط الطول',
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

      for (var i = 0; i < reports.length; i++) {
        final r = reports[i];
        final row = i + 1;
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = xl.TextCellValue(
          r['full_date']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = xl.TextCellValue(
          r['shipment_number']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = xl.TextCellValue(
          r['temperature'] != null ? '${r['temperature']}°C' : '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = xl.TextCellValue(
          r['humidity']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = xl.TextCellValue(
          r['mq9_gas']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .value = xl.TextCellValue(
          r['mq135_gas']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
            .value = xl.TextCellValue(
          r['door_condition']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
            .value = xl.TextCellValue(
          r['latitude']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
            .value = xl.TextCellValue(
          r['longitude']?.toString() ?? '-',
        );
      }

      final bytes = excel.save()!;
      final fileName = 'reports_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      await saveFile(Uint8List.fromList(bytes), fileName, mimeType);

      if (mounted) {
        _showSnack('تم تصدير Excel بنجاح ✅', Colors.green);
      }
    } catch (e) {
      debugPrint('❌ Export Excel error: $e');
      if (mounted) {
        _showSnack('خطأ في تصدير Excel: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPdf() async {
    if (reports.isEmpty) {
      if (mounted) {
        _showSnack('لا توجد بيانات للتصدير', Colors.orange);
      }
      return;
    }
    setState(() => _isExporting = true);
    try {
      final font = await PdfGoogleFonts.cairoRegular();
      final fontBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => [
            pw.Text(
              'تقارير الرحلات',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 18,
                color: PdfColor.fromHex('#1B4332'),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                'التاريخ',
                'رقم الشحنة',
                'الحرارة',
                'الرطوبة',
                'حساس MQ9',
                'حساس MQ135',
                'حالة الباب',
                'خط العرض',
                'خط الطول',
              ],
              data: reports
                  .map(
                    (r) => [
                      r['full_date']?.toString() ?? '-',
                      r['shipment_number']?.toString() ?? '-',
                      r['temperature'] != null ? '${r['temperature']}°C' : '-',
                      r['humidity']?.toString() ?? '-',
                      r['mq9_gas']?.toString() ?? '-',
                      r['mq135_gas']?.toString() ?? '-',
                      r['door_condition']?.toString() ?? '-',
                      r['latitude']?.toString() ?? '-',
                      r['longitude']?.toString() ?? '-',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(
                font: fontBold,
                color: PdfColors.white,
                fontSize: 8,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1B4332),
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 7),
              oddRowDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5F5'),
              ),
              cellAlignment: pw.Alignment.center,
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final fileName = 'reports_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final mimeType = 'application/pdf';

      await saveFile(bytes, fileName, mimeType);

      if (mounted) {
        _showSnack('تم تصدير PDF بنجاح ✅', Colors.green);
      }
    } catch (e) {
      debugPrint('❌ Export PDF error: $e');
      if (mounted) {
        _showSnack('خطأ في تصدير PDF: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────
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
            : const Color(0xFF1B4332),
        elevation: 0,
        centerTitle: true,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text(
          "سجل التقارير",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (truckId != null ||
              search != null ||
              startDate != null ||
              endDate != null)
            IconButton(
              icon: const Icon(Icons.clear_all, color: Colors.white),
              tooltip: "عرض الكل",
              onPressed: _clearFilters,
            ),
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
      body: Column(
        children: [
          // ── شريط الفلاتر ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark
                ? const Color(0xFF1A1A1A)
                : const Color(0xFF1B4332).withOpacity(0.05),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildSearchField(isDark)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTruckIdField(isDark)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => pickDate(true),
                        child: _buildDateField(
                          startDate ?? "من تاريخ",
                          "من",
                          isDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => pickDate(false),
                        child: _buildDateField(
                          endDate ?? "إلى تاريخ",
                          "إلى",
                          isDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Apply button - applies all filters
                SizedBox(width: double.infinity, child: _buildApplyButton()),
              ],
            ),
          ),

          // ── نتائج + pagination ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (!isLoading)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "إجمالي النتائج: $_totalCount",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          Text(
                            "صفحة $_currentPage من ${(_totalCount / _pageSize).ceil().clamp(1, 9999)}",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),

                  Expanded(child: _buildReportsTable(isDark, textColor)),

                  if (_totalCount > _pageSize && !isLoading)
                    _buildPaginationBar(isDark),

                  const SizedBox(height: 10),

                  // Export buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildExportButton(
                        "تصدير PDF",
                        Icons.picture_as_pdf,
                        _exportToPdf,
                      ),
                      _buildExportButton(
                        "تصدير Excel",
                        Icons.table_chart,
                        _exportToExcel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // Widgets
  // ─────────────────────────────────────────

  Widget _buildSearchField(bool isDark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => search = v.isEmpty ? null : v),
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: "بحث برقم الشحنة",
          hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
          suffixIcon: Icon(
            Icons.search,
            size: 18,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildTruckIdField(bool isDark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _truckIdController,
        keyboardType: TextInputType.number,
        onChanged: (v) => setState(() => truckId = v.isEmpty ? null : v),
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: "رقم الشاحنة",
          hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
          suffixIcon: Icon(
            Icons.local_shipping,
            size: 18,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildDateField(String date, String label, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF333333) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            date,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApplyButton() {
    return ElevatedButton.icon(
      onPressed: isLoading
          ? null
          : () {
              _currentPage = 1; // Reset to first page when applying filters
              fetchReports();
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1B4332),
        disabledBackgroundColor: const Color(0xFF1B4332).withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.filter_list, size: 18, color: Colors.white),
      label: Text(
        isLoading ? "جاري التطبيق..." : "تطبيق الفلاتر",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildReportsTable(bool isDark, Color textColor) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (reports.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: isDark ? const Color(0xFF252525) : Colors.white,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 50,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 10),
            Text(
              "لا توجد تقارير",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: isDark ? const Color(0xFF252525) : Colors.white,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(120),
              1: FixedColumnWidth(110),
              2: FixedColumnWidth(85),
              3: FixedColumnWidth(85),
              4: FixedColumnWidth(80),
              5: FixedColumnWidth(80),
              6: FixedColumnWidth(130),
            },
            children: [
              _tableHeader([
                "التاريخ",
                "الشحنة",
                "حساس MQ135",
                "حساس MQ9",
                "الرطوبة",
                "الحرارة",
                "الموقع",
              ]),
              ...reports.asMap().entries.map((entry) {
                final index = entry.key;
                final r = entry.value;

                final rowColor = index % 2 == 0
                    ? (isDark
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFF5F5F5))
                    : (isDark ? const Color(0xFF252525) : Colors.white);

                final lat = r['latitude'];
                final lng = r['longitude'];
                final locationText = (lat != null && lng != null)
                    ? "${double.tryParse(lat.toString())?.toStringAsFixed(3) ?? '-'}, ${double.tryParse(lng.toString())?.toStringAsFixed(3) ?? '-'}"
                    : "غير متوفر";

                final dateText = r['full_date']?.toString() ?? '-';

                return _tableRow(
                  [
                    dateText,
                    r['shipment_number']?.toString() ?? '-',
                    (r['mq135_gas'] ?? '-').toString(),
                    (r['mq9_gas'] ?? '-').toString(),
                    r['humidity'] != null ? "${r['humidity']}%" : '-',
                    r['temperature'] != null ? "${r['temperature']}°C" : '-',
                    locationText,
                  ],
                  rowColor,
                  isDark,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationBar(bool isDark) {
    final totalPages = (_totalCount / _pageSize).ceil().clamp(1, 9999);
    final Color btnColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color activeColor = const Color(0xFF1B4332);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: _currentPage > 1 ? activeColor : Colors.grey,
            ),
            onPressed: _currentPage > 1
                ? () => fetchReports(page: _currentPage - 1)
                : null,
          ),
          ...List.generate(totalPages.clamp(0, 5), (i) {
            final page = i + 1;
            final isActive = page == _currentPage;
            return GestureDetector(
              onTap: () => fetchReports(page: page),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isActive ? activeColor : btnColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? activeColor
                        : Colors.grey.withOpacity(0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  "$page",
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: _currentPage < totalPages ? activeColor : Colors.grey,
            ),
            onPressed: _currentPage < totalPages
                ? () => fetchReports(page: _currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }

  TableRow _tableHeader(List<String> titles) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFF1B4332)),
      children: titles
          .map(
            (t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Text(
                t,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9,
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
        Color cellColor = isDark ? Colors.white70 : Colors.black87;
        if (c == "طبيعي") cellColor = Colors.green;
        if (c == "غير طبيعي") cellColor = Colors.redAccent;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Text(
            c,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: cellColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  // Export button widget
  Widget _buildExportButton(
    String title,
    IconData icon,
    Future<void> Function() onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: _isExporting ? null : onPressed,
      icon: _isExporting
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(icon, size: 18, color: Colors.white),
      label: Text(
        _isExporting ? "جاري التصدير..." : title,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1B4332),
        disabledBackgroundColor: const Color(0xFF1B4332).withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
