// admin_files/home.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_drawer.dart';
import 'settings_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _userName = "جاري التحميل...";
  String _userEmail = "";
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? prefs.getString('auth_token');
  }

  Future<void> _loadUserInfo() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _userName = "المسؤول";
          _isLoadingUser = false;
        });
      }
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse("http://127.0.0.1:8000/profile"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _userName = data['full_name'] ?? "المسؤول";
          _userEmail = data['email'] ?? "";
          _isLoadingUser = false;
        });
      } else if (mounted) {
        setState(() {
          _userName = "المسؤول";
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
      if (mounted) {
        setState(() {
          _userName = "المسؤول";
          _isLoadingUser = false;
        });
      }
    }
  }

  void _showTruckInputDialog(
    BuildContext context,
    String title,
    String route,
    bool isDark,
  ) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark
            ? const Color(0xFF2C2C2C)
            : const Color(0xFFC8D6CA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "البحث عن شاحنة",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1B4332),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "لعرض $title، يرجى إدخال رقم الشاحنة",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: "مثال: 003",
                filled: true,
                fillColor: isDark ? Colors.black54 : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  route,
                  arguments: controller.text.isEmpty ? null : controller.text,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4332),
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "عرض البيانات",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white.withAlpha(128),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 35,
            backgroundColor: Color(0xFF1B4332),
            child: Icon(Icons.person, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 10),
          Text(
            _isLoadingUser ? "جاري التحميل..." : "مرحباً، $_userName",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            _userEmail,
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF1B4332),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassicCard(
    BuildContext context,
    String title,
    IconData icon,
    String route,
    bool isDark, {
    bool isAlert = false,
    required bool useDialog,
  }) {
    return GestureDetector(
      onTap: () {
        if (useDialog) {
          _showTruckInputDialog(context, title, route, isDark);
        } else {
          Navigator.pushNamed(context, route);
        }
      },
      child: SizedBox(
        width: 100,
        child: Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black45 : Colors.black12,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 38,
                color: isAlert
                    ? Colors.red[700]
                    : (isDark ? Colors.greenAccent : const Color(0xFF1B4332)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF1B4332),
              ),
            ),
          ],
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
              "الرئيسية - Safe Chain",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
                fontSize: 18,
              ),
            ),
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
              child: Column(
                children: [
                  _buildWelcomeCard(isDark),
                  const SizedBox(height: 50),
                  Wrap(
                    spacing: 40,
                    runSpacing: 40,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildClassicCard(
                        context,
                        "حالة الشاحنة",
                        Icons.local_shipping_outlined,
                        '/control',
                        isDark,
                        useDialog: false,
                      ),
                      _buildClassicCard(
                        context,
                        "التقارير",
                        Icons.description_outlined,
                        '/reports',
                        isDark,
                        useDialog: false,
                      ),
                      _buildClassicCard(
                        context,
                        "تحديثات الأمان",
                        Icons.lock_outline,
                        '/updates',
                        isDark,
                        useDialog: false,
                      ),
                      _buildClassicCard(
                        context,
                        "فحص الحساسات",
                        Icons.sensors_outlined,
                        '/sensors_check',
                        isDark,
                        useDialog: true,
                      ),
                      _buildClassicCard(
                        context,
                        "سجل التنبيهات",
                        Icons.warning_amber_rounded,
                        '/alerts',
                        isDark,
                        isAlert: true,
                        useDialog: false,
                      ),
                      _buildClassicCard(
                        context,
                        "إدارة المستخدمين",
                        Icons.admin_panel_settings_outlined,
                        '/admin_users',
                        isDark,
                        useDialog: false,
                      ),

                      _buildClassicCard(
                        context,
                        "الإعدادات",
                        Icons.settings_outlined,
                        '/setting',
                        isDark,
                        useDialog: false,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
