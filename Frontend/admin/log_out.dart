import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'settings_provider.dart';

class LogOutPage extends StatefulWidget {
  const LogOutPage({super.key});

  @override
  State<LogOutPage> createState() => _LogOutPageState();
}

class _LogOutPageState extends State<LogOutPage> {
  bool _isLoggingOut = false;

  Future<void> _performLogout() async {
    if (_isLoggingOut) return;
    
    setState(() => _isLoggingOut = true);

    try {
      // حذف التوكن والبيانات المحفوظة
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('auth_token');
      await prefs.remove('user_role');
      await prefs.remove('user_data');
      await prefs.remove('user_name');
      await prefs.remove('user_id');
      await prefs.remove('active_shipment'); // ✅ إضافة: مسح رقم الشحنة النشط
      await prefs.remove('truck_id'); // ✅ إضافة: مسح رقم الشاحنة

      if (!mounted) return;

      // ✅ إضافة: إظهار رسالة نجاح
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم تسجيل الخروج بنجاح"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // ✅ تحسين: تأخير بسيط قبل الانتقال
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // التنقل للشاشة الرئيسية (اللي فيها تسجيل الدخول) وإزالة كل الصفحات السابقة
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/',
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      debugPrint("Logout error: $e");
      if (!mounted) return;
      
      setState(() => _isLoggingOut = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("حدث خطأ أثناء تسجيل الخروج"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLogoutDialog() {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final bool isDark = settingsProvider.isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: false, // ✅ إضافة: منع إغلاق النافذة بالضغط خارجها
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.logout,
              color: Colors.red[700],
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              "تسجيل الخروج",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: Text(
          "هل أنت متأكد من تسجيل الخروج؟",
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              "إلغاء",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // إغلاق الـ Dialog
              _performLogout(); // تنفيذ تسجيل الخروج
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              "خروج",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bool isDark = settingsProvider.isDarkMode;

    final Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFC8D6CA);
    final Color cardBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0);
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color greenColor = isDark ? const Color(0xFF1B4332) : const Color(0xFF1E452F);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFB9E4D1),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "تسجيل الخروج",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
            fontSize: 18,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // أيقونة الخروج
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B4332) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    size: 60,
                    color: isDark ? Colors.greenAccent : greenColor,
                  ),
                ),
                const SizedBox(height: 30),

                // النص التوضيحي
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "هل تريد تسجيل الخروج من حسابك؟",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "يمكنك تسجيل الدخول مرة أخرى في أي وقت باستخدام بيانات حسابك",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 35),

                // زر تسجيل الخروج
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoggingOut ? null : _showLogoutDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 4,
                    ),
                    child: _isLoggingOut
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout, color: Colors.white, size: 22),
                              SizedBox(width: 10),
                              Text(
                                "تسجيل الخروج",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 15),

                // زر الإلغاء
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton(
                    onPressed: _isLoggingOut
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      "رجوع",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}