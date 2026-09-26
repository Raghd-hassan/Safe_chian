// admin_files/assign_trucks_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_provider.dart';

class AssignTrucksPage extends StatefulWidget {
  final int userId;
  final String userName;
  final String userEmail;

  const AssignTrucksPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<AssignTrucksPage> createState() => _AssignTrucksPageState();
}

class _AssignTrucksPageState extends State<AssignTrucksPage> {
  final String baseUrl = 'http://127.0.0.1:8000';
  String _authToken = '';
  bool _isLoading = true;

  List<Map<String, dynamic>> _allTrucks = [];
  List<int> _assignedTruckIds = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _authToken =
        prefs.getString('token') ?? prefs.getString('auth_token') ?? '';

    if (_authToken.isEmpty) {
      _showSnackBar('غير مسجل دخول', Colors.red);
      return;
    }

    await Future.wait([_loadAllTrucks(), _loadUserTrucks()]);

    setState(() => _isLoading = false);
  }

  Future<void> _loadAllTrucks() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/admin/trucks'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _allTrucks = List<Map<String, dynamic>>.from(data['data'] ?? []);
        });
      } else if (response.statusCode == 401) {
        if (mounted)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      }
    } catch (e) {
      _showSnackBar('خطأ في تحميل الشاحنات: $e', Colors.red);
    }
  }

  Future<void> _loadUserTrucks() async {
    try {
      // Get user's assigned trucks via /admin/users endpoint or a dedicated endpoint
      final response = await http
          .get(
            Uri.parse('$baseUrl/admin/user-trucks/${widget.userId}'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _assignedTruckIds = List<int>.from(data['truck_ids'] ?? []);
        });
      } else if (response.statusCode == 404) {
        // No trucks assigned yet, that's okay
        setState(() => _assignedTruckIds = []);
      }
    } catch (e) {
      _showSnackBar('خطأ في تحميل شاحنات المستخدم: $e', Colors.red);
    }
  }

  Future<void> _assignTruck(int truckId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/assign-truck'),
            headers: {
              'Authorization': 'Bearer $_authToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'user_id': widget.userId, 'truck_id': truckId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _assignedTruckIds.add(truckId);
        });
        _showSnackBar('تم إسناد الشاحنة بنجاح', Colors.green);
      } else {
        final errorData = jsonDecode(response.body);
        _showSnackBar(errorData['detail'] ?? 'فشل إسناد الشاحنة', Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ في الإسناد: $e', Colors.red);
    }
  }

  Future<void> _unassignTruck(int truckId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/unassign-truck'),
            headers: {
              'Authorization': 'Bearer $_authToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'user_id': widget.userId, 'truck_id': truckId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _assignedTruckIds.remove(truckId);
        });
        _showSnackBar('تم إلغاء إسناد الشاحنة', Colors.orange);
      } else {
        final errorData = jsonDecode(response.body);
        _showSnackBar(errorData['detail'] ?? 'فشل إلغاء الإسناد', Colors.red);
      }
    } catch (e) {
      _showSnackBar('خطأ في إلغاء الإسناد: $e', Colors.red);
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

  List<Map<String, dynamic>> get _filteredTrucks {
    if (_searchQuery.isEmpty) return _allTrucks;

    return _allTrucks.where((truck) {
      final truckId = truck['id'].toString();
      final truckName = (truck['name'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return truckId.contains(query) || truckName.contains(query);
    }).toList();
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
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'إسناد الشاحنات',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 18,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: CircleAvatar(
                  backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                  radius: 18,
                  backgroundImage: const AssetImage('assets/logo.png'),
                ),
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildUserInfo(isDark, containerColor, textColor),
                      const SizedBox(height: 20),
                      _buildAssignedTrucks(isDark, containerColor, textColor),
                      const SizedBox(height: 20),
                      _buildSearchField(isDark, containerColor, textColor),
                      const SizedBox(height: 10),
                      _buildAvailableTrucks(isDark, containerColor, textColor),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildUserInfo(bool isDark, Color containerColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF1B4332),
            child: Text(
              widget.userName.isNotEmpty
                  ? widget.userName[0].toUpperCase()
                  : 'U',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.userName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userEmail,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedTrucks(
    bool isDark,
    Color containerColor,
    Color textColor,
  ) {
    final assignedTrucks = _allTrucks
        .where((t) => _assignedTruckIds.contains(t['id']))
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 22),
              const SizedBox(width: 8),
              Text(
                'الشاحنات المسندة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${assignedTrucks.length}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (assignedTrucks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'لم يتم إسناد أي شاحنة بعد',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          else
            ...assignedTrucks.map(
              (truck) => _buildTruckCard(
                truck,
                isDark,
                containerColor,
                textColor,
                isAssigned: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark, Color containerColor, Color textColor) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      textAlign: TextAlign.right,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        hintText: 'بحث عن شاحنة...',
        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
        prefixIcon: Icon(
          Icons.search,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ),
      ),
    );
  }

  Widget _buildAvailableTrucks(
    bool isDark,
    Color containerColor,
    Color textColor,
  ) {
    final availableTrucks = _filteredTrucks
        .where((t) => !_assignedTruckIds.contains(t['id']))
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, color: Colors.blue, size: 22),
              const SizedBox(width: 8),
              Text(
                'الشاحنات المتاحة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${availableTrucks.length}',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (availableTrucks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _searchQuery.isEmpty
                      ? 'جميع الشاحنات مسندة بالفعل'
                      : 'لا توجد نتائج للبحث',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          else
            ...availableTrucks.map(
              (truck) => _buildTruckCard(
                truck,
                isDark,
                containerColor,
                textColor,
                isAssigned: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTruckCard(
    Map<String, dynamic> truck,
    bool isDark,
    Color containerColor,
    Color textColor, {
    required bool isAssigned,
  }) {
    final truckId = truck['id'];
    final truckName = truck['name'] ?? 'Truck #$truckId';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAssigned
              ? Colors.green.withOpacity(0.5)
              : Colors.blue.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isAssigned
                  ? Colors.green.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.local_shipping,
              color: isAssigned ? Colors.green : Colors.blue,
              size: 28,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  truckName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'رقم: $truckId',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              if (isAssigned) {
                _showUnassignDialog(truckId, truckName, isDark);
              } else {
                _assignTruck(truckId);
              }
            },
            icon: Icon(
              isAssigned ? Icons.remove_circle : Icons.add_circle,
              color: isAssigned ? Colors.red : Colors.green,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  void _showUnassignDialog(int truckId, String truckName, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          'تأكيد الإلغاء',
          textAlign: TextAlign.right,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'هل أنت متأكد من إلغاء إسناد "$truckName" من هذا المستخدم؟',
          textAlign: TextAlign.right,
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _unassignTruck(truckId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
