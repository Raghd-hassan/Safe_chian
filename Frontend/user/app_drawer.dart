import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../admin_files/settings_provider.dart';

class SafeChainUserDrawer extends StatelessWidget {
  const SafeChainUserDrawer({super.key});

  // ✅ دالة تسجيل الخروج محسنة للمستخدم
  Future<void> _logout(BuildContext context) async {
    // عرض مربع حوار للتأكيد
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
      // ✅ مسح جميع بيانات الجلسة
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('auth_token');
      await prefs.remove('user_role');
      await prefs.remove('user_data');
      await prefs.remove('user_name');
      await prefs.remove('user_id');
      await prefs.remove('active_shipment');
      
      // ✅ إظهار رسالة للمستخدم
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم تسجيل الخروج بنجاح"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // ✅ الانتقال لشاشة تسجيل الدخول وإزالة جميع الصفحات السابقة
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
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

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
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
                  "لوحة المستخدم",
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
          _buildUserItem(
            context,
            Icons.dashboard_outlined,
            "الصفحة الرئيسية",
            '/user_dash',
            isDark,
          ),
          _buildUserItem(
            context,
            Icons.local_shipping_outlined,
            "حالة الشاحنات",
            '/user_truck_status',
            isDark,
          ),
          _buildUserItem(
            context,
            Icons.receipt_long_outlined,
            "سجل التقارير",
            '/user_reports',
            isDark,
          ),
          _buildUserItem(
            context,
            Icons.notifications_active_outlined,
            "سجل التنبيهات",
            '/user_alerts',
            isDark,
          ),
          _buildUserItem(
            context,
            Icons.settings_outlined,
            "الإعدادات",
            '/user_settings',
            isDark,
          ),
          const Spacer(),
          // ✅ زر تسجيل الخروج المعدل للمستخدم
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "تسجيل الخروج",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () => _logout(context),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildUserItem(
    BuildContext context,
    IconData icon,
    String title,
    String route,
    bool isDark,
  ) {
    final Color itemColor = isDark ? Colors.white : Colors.black87;
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
      tileColor: currentRoute == route ? const Color(0xFF1B4332).withOpacity(0.1) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () {
        Navigator.pop(context);
        if (currentRoute != route) {
          Navigator.pushNamed(context, route);
        }
      },
    );
  }
}