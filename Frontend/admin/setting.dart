// admin_files/setting.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_drawer.dart';
import 'settings_provider.dart';
import 'security_limits.dart';
import 'profile.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _truckIdController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _truckIdController.dispose();
    super.dispose();
  }

  void _showTruckIdDialog(BuildContext context, bool isDark) {
    _truckIdController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.security, color: Colors.orangeAccent),
                const SizedBox(width: 10),
                Text(
                  "التحقق من الشاحنة",
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1B4332),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "الرجاء إدخال رقم الشحنة",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _truckIdController,
                  keyboardType: TextInputType.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B4332),
                  ),
                  decoration: InputDecoration(
                    hintText: "مثال: SHP-5-0001",
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey,
                    ),
                    prefixIcon: Icon(
                      Icons.receipt_long,
                      color: isDark
                          ? Colors.greenAccent
                          : const Color(0xFF1B4332),
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _truckIdController.clear();
                  Navigator.pop(context);
                },
                child: const Text(
                  "إلغاء",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        if (_truckIdController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("الرجاء إدخال رقم الشحنة"),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        setDialogState(() => _isLoading = true);
                        await Future.delayed(const Duration(milliseconds: 500));
                        setDialogState(() => _isLoading = false);
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SecurityLimitsSettings(
                              shipmentNumber: _truckIdController.text.trim(),
                            ),
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4332),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("دخول", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _onWillPop() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("تأكيد الخروج"),
            content: const Text("هل تريد الخروج من التطبيق؟"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("لا"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("نعم", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
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
        final Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final Color textColor = isDark ? Colors.white : Colors.black87;

        return WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
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
              actions: [
                IconButton(
                  icon: Icon(Icons.info_outline, color: textColor),
                  onPressed: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'نظام مراقبة الشاحنات',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '© 2024 جميع الحقوق محفوظة',
                      children: const [Text('تطبيق لإدارة ومراقبة الشاحنات')],
                    );
                  },
                ),
              ],
              title: Text(
                "الإعدادات",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: 18,
                ),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 20,
                ),
                // ✅ تم إضافة SingleChildScrollView لضمان ظهور المحتوى كاملاً دون تمدد زائد
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSettingsOption(
                        title: "حدود الأمان",
                        icon: Icons.security_outlined,
                        color: Colors.orangeAccent,
                        isDark: isDark,
                        cardColor: cardColor,
                        onTap: () => _showTruckIdDialog(context, isDark),
                      ),
                      const SizedBox(height: 20),

                      _buildSettingsOption(
                        title: "الملف الشخصي",
                        icon: Icons.person_outline,
                        color: Colors.blueAccent,
                        isDark: isDark,
                        cardColor: cardColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfilePage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // ✅ إضافة بطاقة إدارة المستخدمين الجديدة
                      _buildSettingsOption(
                        title: "إدارة المستخدمين",
                        icon: Icons.admin_panel_settings_outlined,
                        color: Colors.deepPurpleAccent,
                        isDark: isDark,
                        cardColor: cardColor,
                        onTap: () {
                          Navigator.pushNamed(context, '/admin_users');
                        },
                      ),
                      const SizedBox(height: 30),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? Colors.black45 : Colors.black12,
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: SwitchListTile(
                          title: Text(
                            "الوضع الداكن",
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          secondary: Icon(
                            isDark ? Icons.nightlight_round : Icons.wb_sunny,
                            color: isDark ? Colors.amber : Colors.orange,
                            size: 28,
                          ),
                          value: isDark,
                          onChanged: (value) {
                            settingsProvider.toggleTheme(value);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  value
                                      ? "تم تفعيل الوضع الداكن"
                                      : "تم تفعيل الوضع النهاري",
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          activeThumbColor: const Color(0xFF1B4332),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsOption({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDark,
    required Color cardColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black45 : Colors.black12,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1B4332),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
