import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../admin_files/settings_provider.dart';
import 'app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Color bgColor = const Color(0xFFC8D6CA);
  final Color appBarColor = const Color(0xFFB9E4D1);
  final Color darkGreen = const Color(0xFF1E452F);
  final Color cardGrey = const Color(0xFFE0E0E0);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  File? _selectedImage; // ✅ الصورة المختارة
  bool _isSaving = false; // ✅ منع الضغط المزدوج
  bool _isLoadingProfile = true; // ✅ حالة تحميل البيانات

  // ✅ إصلاح: داخل الكلاس بدل خارجه
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ✅ إصلاح: dispose لمنع memory leak
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  // ✅ إصلاح: إضافة try/catch ومعالجة الأخطاء
  Future<void> _fetchProfile() async {
    setState(() => _isLoadingProfile = true);

    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/profile'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _nameController.text = data['full_name'] ?? '';
            _emailController.text = data['email'] ?? '';
            _phoneController.text = data['phone'] ?? '';
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) _showSnack("انتهت الجلسة، يرجى تسجيل الدخول مجدداً", Colors.red);
      }
    } catch (e) {
      debugPrint("fetchProfile error: $e");
      if (mounted) _showSnack("تعذر الاتصال بالسيرفر", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  // ✅ أيقونة الكاميرا فعلية — تفتح خيار الكاميرا أو المعرض
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();

    // عرض خيارين للمستخدم
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isDark =
            Provider.of<SettingsProvider>(context, listen: false).isDarkMode;
        return Container(
          padding: const EdgeInsets.all(20),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "اختر مصدر الصورة",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // زر الكاميرا
                  GestureDetector(
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFF1B4332),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "الكاميرا",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // زر المعرض
                  GestureDetector(
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFF1B4332),
                          child: const Icon(Icons.photo_library, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "المعرض",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80, // ✅ ضغط الصورة لتوفير حجم
        maxWidth: 400,
      );

      if (image != null && mounted) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      debugPrint("Image picker error: $e");
      if (mounted) _showSnack("تعذر اختيار الصورة", Colors.red);
    }
  }

  // ✅ إصلاح: try/catch + معالجة أخطاء السيرفر + context.mounted
  Future<void> _saveProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final body = {
        "full_name": _nameController.text.trim(),
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
      };

      if (_passwordController.text.isNotEmpty) {
        body["password"] = _passwordController.text;
      }

      final response = await http.put(
        Uri.parse('http://127.0.0.1:8000/profile'),
        headers: await _getAuthHeaders(),
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        _passwordController.clear(); // ✅ مسح كلمة المرور بعد الحفظ
        _showSnack("تم حفظ التعديلات بنجاح ✅", Colors.green);
      } else {
        // ✅ إصلاح: عرض رسالة الخطأ من السيرفر
        final error = jsonDecode(response.body);
        _showSnack(error['detail'] ?? "فشل الحفظ: ${response.statusCode}", Colors.red);
      }
    } catch (e) {
      debugPrint("saveProfile error: $e");
      if (mounted) _showSnack("تعذر الاتصال بالسيرفر", Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bool isDark = settingsProvider.isDarkMode;

    final Color currentBg = isDark ? const Color(0xFF121212) : bgColor;
    final Color currentAppBar = isDark ? const Color(0xFF1A1A1A) : appBarColor;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: currentBg,
      drawer: const SafeChainUserDrawer(),
      appBar: AppBar(
        backgroundColor: currentAppBar,
        elevation: 0,
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          "الحساب الشخصي",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8),
            child: CircleAvatar(
              backgroundColor: isDark ? Colors.grey[800] : Colors.white,
              radius: 20,
              child: ClipOval(
                child: Image.asset(
                  'assets/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.person, color: Colors.green),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                children: [
                  // ✅ صورة الملف الشخصي مع كاميرا فعلية
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: isDark
                                ? const Color(0xFF1B4332)
                                : darkGreen,
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!) // ✅ عرض الصورة المختارة
                                : null,
                            child: _selectedImage == null
                                ? const Icon(Icons.person, size: 60, color: Colors.white)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey[800] : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? Colors.black : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                color: isDark ? Colors.greenAccent : darkGreen,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  _buildProfileField("الاسم", _nameController, Icons.person_outline, isDark),
                  _buildProfileField("البريد الإلكتروني", _emailController, Icons.email_outlined, isDark),
                  _buildProfileField("رقم الجوال", _phoneController, Icons.phone_android_outlined, isDark),
                  _buildProfileField("كلمة المرور الجديدة", _passwordController, Icons.lock_outline, isDark, isPassword: true),

                  const SizedBox(height: 25),

                  // تبديل الثيم
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isDark ? Icons.dark_mode : Icons.light_mode,
                              color: isDark ? Colors.yellow : Colors.orange,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isDark ? "الوضع الداكن" : "الوضع الفاتح",
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: isDark,
                          activeTrackColor: Colors.greenAccent,
                          onChanged: (_) => settingsProvider.toggleTheme(!isDark),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ✅ زر الحفظ مع حالة تحميل
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF1B4332) : darkGreen,
                      disabledBackgroundColor:
                          darkGreen.withOpacity(0.5),
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 4,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "حفظ التعديلات",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isDark, {
    bool isPassword = false,
  }) {
    final Color textLabelColor =
        isDark ? Colors.white70 : const Color(0xFF1E452F);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: textLabelColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : cardGrey,
              borderRadius: BorderRadius.circular(15),
              border: isDark ? Border.all(color: Colors.white10) : null,
            ),
            child: TextField(
              controller: controller,
              obscureText: isPassword,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.edit,
                  size: 18,
                  color: isDark
                      ? Colors.white38
                      : darkGreen.withOpacity(0.5),
                ),
                suffixIcon: Icon(
                  icon,
                  color: isDark ? Colors.greenAccent : darkGreen,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}