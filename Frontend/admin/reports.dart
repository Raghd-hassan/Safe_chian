// admin_files/reports.dart
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

class ReportsPage extends StatefulWidget {
  final String? truckId;
  const ReportsPage({super.key, this.truckId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final TextEditingController _truckController = TextEditingController();

  String _dateFrom = '';
  String _dateTo = '';
  int? _selectedUserId;

  // Pagination
  int _currentPage = 1;
  int _totalReports = 0;
  int _pageSize = 20;

  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  bool _isExporting = false;
  String _authToken = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokenAndFetch();
    });
  }

  @override
  void dispose() {
    _truckController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? prefs.getString('auth_token');
  }

  Future<void> _loadTokenAndFetch() async {
    _authToken = await _getToken() ?? '';
    if (_authToken.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('غير مسجل دخول، يرجى تسجيل الدخول أولاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    await _fetchUsers();
    await _fetchReports();
  }

  Future<void> _fetchUsers() async {
    if (_authToken.isEmpty) return;
    debugPrint('📥 Fetching users from API...');
    try {
      final response = await http
          .get(
            Uri.parse('http://127.0.0.1:8000/admin/users?limit=100'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('📡 Users API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        debugPrint('📦 Users data: ${responseData['data']}');
        debugPrint(
          '👥 Total users found: ${(responseData['data'] as List).length}',
        );

        if (mounted) {
          // Filter to only show non-admin users (drivers)
          final allUsers = List<Map<String, dynamic>>.from(
            responseData['data'] ?? [],
          );
          final filteredUsers = allUsers
              .where((user) => user['role'] != 'admin')
              .toList();

          setState(() {
            _users = filteredUsers;
          });
          debugPrint(
            '✅ Users loaded successfully: ${_users.length} drivers (admins filtered out)',
          );
        }
      } else {
        debugPrint(
          '❌ Users API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error fetching users: $e');
    }
  }

  Future<void> _fetchReports() async {
    if (_authToken.isEmpty) return;
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final Map<String, String> queryParams = {
        'page': _currentPage.toString(),
        'limit': _pageSize.toString(),
      };
      if (_truckController.text.isNotEmpty) {
        queryParams['truck_id'] = _truckController.text;
      }

      if (_dateFrom.isNotEmpty) queryParams['start_date'] = _dateFrom;
      if (_dateTo.isNotEmpty) queryParams['end_date'] = _dateTo;
      if (_selectedUserId != null) {
        queryParams['user_id'] = _selectedUserId.toString();
      }

      final queryString =
          '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';

      final response = await http
          .get(
            Uri.parse('http://127.0.0.1:8000/admin/reports$queryString'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        setState(() {
          _reports = List<Map<String, dynamic>>.from(
            responseData['data'] ?? [],
          );
          _totalReports = responseData['total'] ?? 0;
          _currentPage = responseData['page'] ?? 1;
        });
      } else if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        await prefs.remove('auth_token');
        if (mounted)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الاتصال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportToExcel() async {
    if (_reports.isEmpty) {
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
      final sheet = excel['التقارير'];
      excel.setDefaultSheet('التقارير');

      final headers = [
        'التاريخ',
        'الحرارة',
        'الرطوبة',
        'حساس MQ9',
        'حساس MQ135',
        'الباب',
        'رقم الشاحنة',
        'رقم الشحنة',
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

      for (var i = 0; i < _reports.length; i++) {
        final r = _reports[i];
        final row = i + 1;
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = xl.TextCellValue(
          r['full_date']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = xl.TextCellValue(
          r['temperature'] != null ? '${r['temperature']}°C' : '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = xl.TextCellValue(
          r['humidity']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = xl.TextCellValue(
          r['mq9_gas']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = xl.TextCellValue(
          r['mq135_gas']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .value = xl.TextCellValue(
          r['door_condition']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
            .value = xl.TextCellValue(
          r['truck_id']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
            .value = xl.TextCellValue(
          r['shipment_number']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
            .value = xl.TextCellValue(
          r['latitude']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row))
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير Excel بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPdf() async {
    if (_reports.isEmpty) {
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
                'الحرارة',
                'الرطوبة',
                'حساس MQ9',
                'حساس MQ135',
                'الباب',
                'رقم الشاحنة',
                'رقم الشحنة',
                'خط العرض',
                'خط الطول',
              ],
              data: _reports
                  .map(
                    (r) => [
                      r['full_date']?.toString() ?? '-',
                      r['temperature'] != null ? '${r['temperature']}°C' : '-',
                      r['humidity']?.toString() ?? '-',
                      r['mq9_gas']?.toString() ?? '-',
                      r['mq135_gas']?.toString() ?? '-',
                      r['door_condition']?.toString() ?? '-',
                      r['truck_id']?.toString() ?? '-',
                      r['shipment_number']?.toString() ?? '-',
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير PDF بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final bool isDark = Provider.of<SettingsProvider>(context).isDarkMode;
        return Theme(
          data: isDark ? ThemeData.dark() : ThemeData.light(),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        if (isFrom) {
          _dateFrom = formatted;
        } else {
          _dateTo = formatted;
        }
      });
      _fetchReports();
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
        final Color textColor = isDark ? Colors.white : Colors.black87;
        final Color containerColor = isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFC5D1C5);

        return Scaffold(
          backgroundColor: scaffoldBg,
          drawer: const SafeChainDrawer(),
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: 0,
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                  backgroundImage: const AssetImage('assets/logo.png'),
                ),
              ),
            ],
            title: Text(
              'سجل التقارير',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            iconTheme: IconThemeData(color: textColor),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 20, left: 15, right: 15),
                  height: 20,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2C2C)
                        : const Color(0xFFE0E0E0),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 15),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: containerColor,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildTruckField(isDark),
                          const SizedBox(height: 15),
                          _buildUserDropdown(isDark),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              _buildApplyButton(),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDateField(
                                  _dateFrom.isEmpty ? 'من' : _dateFrom,
                                  'من',
                                  isDark,
                                  () => _pickDate(context, true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDateField(
                                  _dateTo.isEmpty ? 'إلى' : _dateTo,
                                  'إلى',
                                  isDark,
                                  () => _pickDate(context, false),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Text(
                                  'مدة الرحلة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 25),
                          _buildReportsTable(isDark),
                          const SizedBox(height: 15),
                          _buildPaginationControls(isDark),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildExportButton(
                                'تصدير Excel',
                                Icons.table_chart,
                                _exportToExcel,
                                isDark,
                              ),
                              _buildExportButton(
                                'تصدير PDF',
                                Icons.picture_as_pdf,
                                _exportToPdf,
                                isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTruckField(bool isDark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white.withAlpha(128),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _truckController,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white : Colors.black,
        ),
        onSubmitted: (value) {
          // Trigger search when user presses Enter
          _currentPage = 1; // Reset to first page
          _fetchReports();
        },
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.local_shipping,
            size: 16,
            color: isDark ? Colors.white54 : Colors.grey,
          ),
          hintText: 'رقم الشاحنة',
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildUserDropdown(bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white.withAlpha(128),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedUserId,
          hint: Text(
            'جميع السائقين',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.grey,
            ),
          ),
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            color: isDark ? Colors.white54 : Colors.grey,
          ),
          dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : Colors.black,
          ),
          items: [
            DropdownMenuItem<int>(value: null, child: Text('جميع السائقين')),
            ..._users.map((user) {
              return DropdownMenuItem<int>(
                value: user['id'],
                child: Text('${user['full_name']} (${user['role']})'),
              );
            }).toList(),
          ],
          onChanged: (value) {
            setState(() {
              _selectedUserId = value;
              _currentPage = 1;
            });
            _fetchReports();
          },
        ),
      ),
    );
  }

  Widget _buildDateField(
    String date,
    String label,
    bool isDark,
    VoidCallback onTap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
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
        ),
      ],
    );
  }

  Widget _buildApplyButton() {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      child: ElevatedButton(
        onPressed: () {
          _currentPage = 1; // Reset to first page when applying filters
          _fetchReports();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1B4332),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(50, 30),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'تطبيق',
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildReportsTable(bool isDark) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF1B4332)),
        ),
      );
    }

    if (_reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'لا توجد تقارير، ابحث برقم الشاحنة أو التاريخ',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
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
            0: FixedColumnWidth(120),
            1: FixedColumnWidth(80),
            2: FixedColumnWidth(100),
            3: FixedColumnWidth(70),
            4: FixedColumnWidth(80),
            5: FixedColumnWidth(80),
            6: FixedColumnWidth(80),
            7: FixedColumnWidth(80),
            8: FixedColumnWidth(120),
          },
          children: [
            _tableHeader([
              'الموقع',
              'الشاحنة',
              'الشحنة',
              'الباب',
              'حساس MQ9',
              'حساس MQ135',
              'الرطوبة',
              'الحرارة',
              'التاريخ',
            ], isDark),
            ...List.generate(_reports.length, (index) {
              final report = _reports[index];
              final location =
                  'Lat: ${report['latitude'] ?? '-'}, Lon: ${report['longitude'] ?? '-'}';
              return _tableRow(
                [
                  location,
                  report['truck_id']?.toString() ?? '-',
                  report['shipment_number']?.toString() ?? '-',
                  report['door_condition']?.toString() ?? '-',
                  report['mq9_gas']?.toString() ?? '-',
                  report['mq135_gas']?.toString() ?? '-',
                  report['humidity']?.toString() ?? '-',
                  report['temperature'] != null
                      ? '${report['temperature']}°C'
                      : '-',
                  report['full_date']?.toString() ?? '-',
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
        Color statusColor = isDark ? Colors.white70 : Colors.black87;
        if (c == 'طبيعي') statusColor = Colors.green;
        if (c == 'غير طبيعي') statusColor = Colors.red;
        if (c == 'مفتوح') statusColor = Colors.orange;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Text(
            c,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExportButton(
    String title,
    IconData icon,
    VoidCallback onPressed,
    bool isDark,
  ) {
    return ElevatedButton.icon(
      onPressed: _isExporting ? null : onPressed,
      icon: _isExporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 16, color: Colors.white),
      label: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1B4332),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildPaginationControls(bool isDark) {
    final int totalPages = (_totalReports / _pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _fetchReports();
                  }
                : null,
            icon: const Icon(Icons.arrow_back_ios),
            color: isDark ? Colors.white : const Color(0xFF1B4332),
            iconSize: 18,
          ),
          const SizedBox(width: 10),
          Text(
            'صفحة $_currentPage من $totalPages (إجمالي: $_totalReports)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () {
                    setState(() => _currentPage++);
                    _fetchReports();
                  }
                : null,
            icon: const Icon(Icons.arrow_forward_ios),
            color: isDark ? Colors.white : const Color(0xFF1B4332),
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}
