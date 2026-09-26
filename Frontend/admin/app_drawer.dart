// admin_files/app_drawer.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_provider.dart';

class SafeChainDrawer extends StatelessWidget {
  const SafeChainDrawer({super.key});

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تسجيل الخروج"),
        content: const Text("هل أنت متأكد من رغبتك في تسجيل الخروج؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("خروج", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('auth_token');
      await prefs.remove('user_role');
      await prefs.remove('user_name');
      await prefs.remove('user_id');
      await prefs.remove('active_shipment');
      await prefs.remove('truck_id');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم تسجيل الخروج بنجاح"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint("Logout error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("حدث خطأ أثناء تسجيل الخروج"),
            backgroundColor: Colors.red,
          ),
        );
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
      builder: (dialogContext) => AlertDialog(
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
                final navigator = Navigator.of(dialogContext);
                navigator.pop();
                // Pass empty string or the entered text
                navigator.pushNamed(
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

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final bool isDark = settingsProvider.isDarkMode;

        return Drawer(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 50, right: 15, left: 10),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.transparent,
                      backgroundImage: AssetImage('assets/logo.png'),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "SAFE CHAIN",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1E452F),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        isDark ? Icons.light_mode : Icons.dark_mode,
                        color: isDark ? Colors.yellow : Colors.black87,
                      ),
                      onPressed: () {
                        settingsProvider.toggleTheme(!isDark);
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(color: isDark ? Colors.white24 : Colors.grey),
              _buildItem(
                context,
                Icons.home_outlined,
                "الصفحة الرئيسية",
                '/admin_home',
                isDark,
                useDialog: false,
              ),
              _buildItem(
                context,
                Icons.local_shipping_outlined,
                "حالة الشاحنات",
                '/control',
                isDark,
                useDialog: false,
              ),
              _buildItem(
                context,
                Icons.description_outlined,
                "التقارير",
                '/reports',
                isDark,
                useDialog: true,
              ),
              _buildItem(
                context,
                Icons.sensors_outlined,
                "فحص الحساسات",
                '/sensors_check',
                isDark,
                useDialog: true,
              ),
              _buildItem(
                context,
                Icons.warning_amber_rounded,
                "سجل التنبيهات",
                '/alerts',
                isDark,
                color: Colors.red,
                useDialog: false,
              ),
              _buildItem(
                context,
                Icons.lock_outline,
                "تحديثات الأمان",
                '/updates',
                isDark,
                useDialog: false,
              ),

              _buildItem(
                context,
                Icons.admin_panel_settings_outlined,
                "إدارة المستخدمين",
                '/admin_users',
                isDark,
                useDialog: false,
              ),

              _buildItem(
                context,
                Icons.settings_outlined,
                "الإعدادات",
                '/setting',
                isDark,
                useDialog: false,
              ),

              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  "تسجيل الخروج",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () => _logout(context),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(
    BuildContext context,
    IconData icon,
    String title,
    String route,
    bool isDark, {
    Color? color,
    required bool useDialog,
  }) {
    final Color itemColor = color ?? (isDark ? Colors.white : Colors.black87);
    final String? currentRoute = ModalRoute.of(context)?.settings.name;

    return ListTile(
      leading: Icon(
        icon,
        color: currentRoute == route ? const Color(0xFF1B4332) : itemColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: currentRoute == route ? const Color(0xFF1B4332) : itemColor,
          fontWeight: currentRoute == route ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      tileColor: currentRoute == route
          ? const Color(0xFF1B4332).withOpacity(0.1)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {
        Navigator.pop(context); // إغلاق الـ Drawer أولاً
        if (currentRoute != route) {
          if (useDialog) {
            _showTruckInputDialog(context, title, route, isDark);
          } else {
            Navigator.pushNamed(context, route);
          }
        }
      },
    );
  }
}
