// admin_files/profile.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_drawer.dart';
import 'settings_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? prefs.getString('auth_token');
  }

  Future<void> loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _getToken();

      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "غير مسجل دخول، يرجى تسجيل الدخول أولاً";
          });
        }
        return;
      }

      final response = await http.get(
        Uri.parse("http://127.0.0.1:8000/profile"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _nameController.text = data["full_name"] ?? "";
            _emailController.text = data["email"] ?? "";
            _phoneController.text = data["phone"] ?? "";
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "فشل تحميل البيانات (${response.statusCode})";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "خطأ في الاتصال بالخادم";
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> updateProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال الاسم"), backgroundColor: Colors.orange));
      return;
    }

    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال البريد الإلكتروني"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى تسجيل الدخول أولاً"), backgroundColor: Colors.red));
        }
        return;
      }

      Map<String, dynamic> bodyData = {
        "full_name": _nameController.text.trim(),
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
      };

      if (_passwordController.text.isNotEmpty) {
        bodyData["password"] = _passwordController.text;
      }

      final response = await http.put(
        Uri.parse("http://127.0.0.1:8000/profile"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer $token"},
        body: jsonEncode(bodyData),
      );

      if (mounted) {
        setState(() => _isSaving = false);

        if (response.statusCode == 200) {
          _passwordController.clear();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حفظ التعديلات بنجاح"), backgroundColor: Colors.green));
        } else {
          String errorMsg = "فشل التحديث";
          try {
            final errorData = jsonDecode(response.body);
            errorMsg = errorData["detail"] ?? errorMsg;
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ في الاتصال"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final bool isDark = settingsProvider.isDarkMode;

        final Color currentBg = isDark ? const Color(0xFF121212) : const Color(0xFFC8D6CA);
        final Color currentAppBar = isDark ? Colors.black : const Color(0xFFB9E4D1);
        final Color textColor = isDark ? Colors.white : Colors.black87;

        return Scaffold(
          backgroundColor: currentBg,
          drawer: const SafeChainDrawer(),
          appBar: AppBar(
            backgroundColor: currentAppBar,
            elevation: 0,
            centerTitle: true,
            leading: Builder(builder: (context) => IconButton(icon: Icon(Icons.menu, color: textColor), onPressed: () => Scaffold.of(context).openDrawer())),
            title: Text("الحساب الشخصي", style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 18)),
          ),
          body: _isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B4332))) : _errorMessage != null ? _buildErrorView(isDark, textColor) : _buildProfileForm(isDark, textColor),
        );
      },
    );
  }

  Widget _buildErrorView(bool isDark, Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 60, color: Colors.red[400]),
          const SizedBox(height: 20),
          Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: textColor)),
          const SizedBox(height: 25),
          ElevatedButton.icon(onPressed: loadProfile, icon: const Icon(Icons.refresh, color: Colors.white), label: const Text("إعادة المحاولة", style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: isDark ? const Color(0xFF1B4332) : const Color(0xFF1E452F), padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
      ),
    );
  }

  Widget _buildProfileForm(bool isDark, Color textColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(children: [
        Center(child: Stack(children: [CircleAvatar(radius: 50, backgroundColor: isDark ? const Color(0xFF1B4332) : const Color(0xFF1E452F), child: const Icon(Icons.person, size: 60, color: Colors.white))])),
        const SizedBox(height: 40),
        _buildProfileField("الاسم", _nameController, Icons.person_outline, isDark),
        _buildProfileField("البريد الإلكتروني", _emailController, Icons.email_outlined, isDark),
        _buildProfileField("رقم الجوال", _phoneController, Icons.phone_android_outlined, isDark),
        _buildProfileField("كلمة المرور الجديدة (اختياري)", _passwordController, Icons.lock_outline, isDark, isPassword: true, hint: "اتركه فارغاً إذا لا تريد التغيير"),
        Padding(padding: const EdgeInsets.only(bottom: 20), child: Align(alignment: Alignment.centerRight, child: Text("كلمة المرور يجب أن تحتوي على 8 أحرف على الأقل، حرف كبير، حرف صغير، رقم، ورمز خاص", style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black45)))),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _isSaving ? null : updateProfile, style: ElevatedButton.styleFrom(backgroundColor: isDark ? const Color(0xFF1B4332) : const Color(0xFF1E452F), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 4), child: _isSaving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)) : const Text("حفظ التعديلات", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
      ]),
    );
  }

  Widget _buildProfileField(String label, TextEditingController controller, IconData icon, bool isDark, {bool isPassword = false, bool enabled = true, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : const Color(0xFF1E452F), fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(15), border: isDark ? Border.all(color: Colors.white10) : null),
            child: TextField(
              controller: controller,
              obscureText: isPassword,
              enabled: enabled,
              textAlign: TextAlign.right,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.edit, size: 18, color: isDark ? Colors.white38 : const Color(0xFF1E452F).withAlpha(128)),
                suffixIcon: Icon(icon, color: isDark ? Colors.greenAccent : const Color(0xFF1E452F)),
                hintText: hint,
                hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white24 : Colors.black38),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}