// admin_files/updates.dart
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

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;
  bool _isExporting = false;
  String _authToken = '';

  final TextEditingController _truckIdController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _dateFrom = '';
  String _dateTo = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokenAndFetch();
    });
  }

  @override
  void dispose() {
    _truckIdController.dispose();
    _searchController.dispose();
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
            content: Text('يرجى تسجيل الدخول أولاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    _fetchUpdates();
  }

  Future<void> _fetchUpdates() async {
    if (_authToken.isEmpty) return;
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final Map<String, String> queryParams = {};
      if (_searchController.text.isNotEmpty)
        queryParams['search'] = _searchController.text;
      if (_dateFrom.isNotEmpty) queryParams['start_date'] = _dateFrom;
      if (_dateTo.isNotEmpty) queryParams['end_date'] = _dateTo;

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
            Uri.parse('http://127.0.0.1:8000/admin/updates$queryString'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _logs = List<Map<String, dynamic>>.from(data);
        });
      } else if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        await prefs.remove('auth_token');
        if (mounted)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      } else {
        _showSnack('خطأ: ${response.statusCode}', Colors.red);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) _showSnack('خطأ في الاتصال بالسيرفر', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تصدير Excel محلياً
  Future<void> _exportToExcel() async {
    if (_logs.isEmpty) {
      _showSnack('لا توجد بيانات للتصدير', Colors.orange);
      return;
    }
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['التحديثات'];
      excel.setDefaultSheet('التحديثات');

      final headers = [
        'التاريخ',
        'رقم الشاحنة',
        'اسم الشاحنة',
        'المسؤول',
        'العنصر',
        'الوصف',
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

      for (var i = 0; i < _logs.length; i++) {
        final log = _logs[i];
        final row = i + 1;
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = xl.TextCellValue(
          log['created_at']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = xl.TextCellValue(
          log['truck_id']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = xl.TextCellValue(
          log['truck_name']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = xl.TextCellValue(
          log['admin_name']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = xl.TextCellValue(
          log['item_name']?.toString() ?? '-',
        );
        sheet
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .value = xl.TextCellValue(
          log['description']?.toString() ?? '-',
        );
      }

      final bytes = excel.save()!;
      final fileName = 'updates_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      await saveFile(Uint8List.fromList(bytes), fileName, mimeType);

      if (mounted) _showSnack('تم تصدير Excel بنجاح ✅', Colors.green);
    } catch (e) {
      if (mounted) _showSnack('خطأ في تصدير Excel: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // تصدير PDF محلياً
  Future<void> _exportToPdf() async {
    if (_logs.isEmpty) {
      _showSnack('لا توجد بيانات للتصدير', Colors.orange);
      return;
    }
    if (_isExporting) return;
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
              'سجل التحديثات',
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
                'رقم الشاحنة',
                'اسم الشاحنة',
                'المسؤول',
                'العنصر',
                'الوصف',
              ],
              data: _logs
                  .map(
                    (log) => [
                      log['created_at']?.toString() ?? '-',
                      log['truck_id']?.toString() ?? '-',
                      log['truck_name']?.toString() ?? '-',
                      log['admin_name']?.toString() ?? '-',
                      log['item_name']?.toString() ?? '-',
                      log['description']?.toString() ?? '-',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1B4332),
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 9),
              oddRowDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5F5'),
              ),
              cellAlignment: pw.Alignment.center,
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final fileName = 'updates_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final mimeType = 'application/pdf';

      await saveFile(bytes, fileName, mimeType);

      if (mounted) _showSnack('تم تصدير PDF بنجاح ✅', Colors.green);
    } catch (e) {
      if (mounted) _showSnack('خطأ في تصدير PDF: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color,
      ),
    );
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
        if (isFrom)
          _dateFrom = formatted;
        else
          _dateTo = formatted;
      });
      _fetchUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final bool isDark = settingsProvider.isDarkMode;

        final Color bgColor = isDark
            ? const Color(0xFF121212)
            : const Color(0xFFC8D6CA);
        final Color appBarColor = isDark
            ? Colors.black
            : const Color(0xFFB9E4D1);
        final Color darkGreen = isDark
            ? Colors.greenAccent
            : const Color(0xFF1B4332);
        final Color cardColor = isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFE0E0E0);
        final Color textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: bgColor,
          drawer: const SafeChainDrawer(),
          appBar: AppBar(
            backgroundColor: appBarColor,
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
              'سجل التحديثات',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 18,
              ),
            ),
          ),
          body: Column(
            children: [
              _buildSearchAndFilters(isDark, darkGreen, textColor),
              Expanded(
                child: _buildLogList(isDark, cardColor, darkGreen, textColor),
              ),
              _buildExportSection(isDark),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddUpdateDialog(isDark),
            backgroundColor: const Color(0xFF1B4332),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'إضافة تحديث',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
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

  Widget _buildSearchAndFilters(bool isDark, Color darkGreen, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _truckIdController,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'رقم الشاحنة',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.local_shipping,
                      color: darkGreen,
                      size: 18,
                    ),
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 20,
                    ),
                  ),
                  onSubmitted: (_) => _fetchUpdates(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'البحث عن مستخدم أو إجراء',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(Icons.search, color: darkGreen),
                    fillColor: isDark ? Colors.white10 : Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 20,
                    ),
                  ),
                  onSubmitted: (_) => _fetchUpdates(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _buildDateBox(
                _dateFrom.isEmpty ? 'من' : _dateFrom,
                isDark,
                darkGreen,
                () => _pickDate(context, true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'من',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF1B4332),
                  ),
                ),
              ),
              _buildDateBox(
                _dateTo.isEmpty ? 'إلى' : _dateTo,
                isDark,
                darkGreen,
                () => _pickDate(context, false),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'إلى',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF1B4332),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _fetchUpdates,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4332),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  minimumSize: const Size(80, 48),
                ),
                child: const Text(
                  'تطبيق',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateBox(
    String date,
    bool isDark,
    Color darkGreen,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Text(
            date,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.greenAccent : darkGreen,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogList(
    bool isDark,
    Color cardColor,
    Color darkGreen,
    Color textColor,
  ) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1B4332)),
      );
    }

    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد تحديثات',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _logs.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) =>
          _buildLogCard(_logs[index], isDark, cardColor, darkGreen, textColor),
    );
  }

  Widget _buildLogCard(
    Map<String, dynamic> data,
    bool isDark,
    Color cardColor,
    Color darkGreen,
    Color textColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            data['created_at']?.toString() ?? '-',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data['truck_name']?.toString() ??
                        'شاحنة ${data['truck_id']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark
                          ? Colors.greenAccent
                          : const Color(0xFF1B4332),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.local_shipping,
                    color: isDark
                        ? Colors.greenAccent
                        : const Color(0xFF1B4332),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'العنصر: ${data['item_name']?.toString() ?? '-'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
              Text(
                'الوصف: ${data['description']?.toString() ?? '-'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                  : const Icon(Icons.grid_on, color: Colors.white, size: 20),
              label: const Text(
                'تصدير Excel',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 4,
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
                  : const Icon(
                      Icons.picture_as_pdf,
                      color: Colors.white,
                      size: 20,
                    ),
              label: const Text(
                'تصدير PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Dialog to add new update
  Future<void> _showAddUpdateDialog(bool isDark) async {
    final TextEditingController itemNameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();

    final Color bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color darkGreen = isDark
        ? Colors.greenAccent
        : const Color(0xFF1B4332);

    // Fetch trucks for dropdown
    List<Map<String, dynamic>> trucks = [];
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/admin/trucks?limit=500'),
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        trucks = List<Map<String, dynamic>>.from(data['data']);
      }
    } catch (e) {
      debugPrint('Error fetching trucks: $e');
    }

    int? selectedTruckId;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'إضافة تحديث جديد',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: darkGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Truck dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedTruckId,
                          isExpanded: true,
                          hint: Text(
                            'اختر الشاحنة',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          dropdownColor: bgColor,
                          items: trucks.map((truck) {
                            return DropdownMenuItem<int>(
                              value: truck['id'] as int,
                              alignment: Alignment.centerRight,
                              child: Text(
                                truck['name']?.toString() ??
                                    'شاحنة ${truck['id']}',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: textColor),
                              ),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            setDialogState(() {
                              selectedTruckId = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Item name field
                    TextField(
                      controller: itemNameController,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'اسم العنصر (مثال: حساس الحرارة)',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                        prefixIcon: Icon(Icons.build, color: darkGreen),
                        fillColor: isDark ? Colors.white10 : Colors.grey[200],
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Description field
                    TextField(
                      controller: descriptionController,
                      textAlign: TextAlign.right,
                      maxLines: 4,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'وصف التحديث (مثال: تمت معايرة الحساس)',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                        prefixIcon: Icon(Icons.description, color: darkGreen),
                        fillColor: isDark ? Colors.white10 : Colors.grey[200],
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedTruckId == null) {
                      _showSnack('يرجى اختيار الشاحنة', Colors.orange);
                      return;
                    }
                    if (itemNameController.text.trim().isEmpty) {
                      _showSnack('يرجى إدخال اسم العنصر', Colors.orange);
                      return;
                    }
                    if (descriptionController.text.trim().isEmpty) {
                      _showSnack('يرجى إدخال الوصف', Colors.orange);
                      return;
                    }

                    // Submit the update
                    try {
                      final response = await http
                          .post(
                            Uri.parse('http://127.0.0.1:8000/admin/updates'),
                            headers: {
                              'Authorization': 'Bearer $_authToken',
                              'Content-Type':
                                  'application/x-www-form-urlencoded',
                            },
                            body: {
                              'truck_id': selectedTruckId.toString(),
                              'item_name': itemNameController.text.trim(),
                              'description': descriptionController.text.trim(),
                            },
                          )
                          .timeout(const Duration(seconds: 15));

                      if (mounted) {
                        Navigator.of(context).pop();
                        if (response.statusCode == 200) {
                          _showSnack('تم إضافة التحديث بنجاح ✅', Colors.green);
                          _fetchUpdates(); // Refresh the list
                        } else {
                          _showSnack(
                            'خطأ في إضافة التحديث: ${response.statusCode}',
                            Colors.red,
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        Navigator.of(context).pop();
                        _showSnack('خطأ في الاتصال: $e', Colors.red);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4332),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'إضافة',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
