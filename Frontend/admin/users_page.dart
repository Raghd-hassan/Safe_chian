import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'assign_trucks_page.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List users = [];
  bool isLoading = true;
  String search = "";

  // ✅ عنوان السيرفر
  final String baseUrl = 'http://127.0.0.1:8000';

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  // ✅ دالة تسجيل الخروج عند انتهاء الجلسة
  Future<void> handleSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('token');
    await prefs.remove('user_role');
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'انتهت صلاحية الجلسة، سجل دخولك مجدداً',
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> loadUsers() async {
    setState(() => isLoading = true);

    final token = await getToken();

    try {
      final response = await http
          .get(
            Uri.parse("$baseUrl/admin/users?search=$search"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          users = data["data"] ?? [];
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        handleSessionExpired(); // ✅ طرد المستخدم إذا انتهت الجلسة
      } else {
        setState(() => isLoading = false);
        _showSnackBar("فشل في تحميل المستخدمين", Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showSnackBar("فشل الاتصال بالسيرفر", Colors.red);
    }
  }

  // ✅ تأكيد الحذف قبل التنفيذ
  Future<void> confirmDeleteUser(int id, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          "تأكيد الحذف",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "هل أنت متأكد من حذف المستخدم '$name'؟ لا يمكن التراجع عن هذا الإجراء.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await deleteUser(id);
    }
  }

  Future<void> deleteUser(int id) async {
    final token = await getToken();

    try {
      final response = await http
          .delete(
            Uri.parse("$baseUrl/admin/users/$id"),
            headers: {"Authorization": "Bearer $token"},
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showSnackBar("تم حذف المستخدم بنجاح", Colors.green);
        loadUsers();
      } else if (response.statusCode == 401) {
        handleSessionExpired();
      } else if (response.statusCode == 400) {
        final error = jsonDecode(response.body);
        _showSnackBar(
          error["detail"] ?? "لا يمكنك حذف هذا المستخدم",
          Colors.red,
        );
      } else {
        _showSnackBar("فشل في حذف المستخدم", Colors.red);
      }
    } catch (e) {
      _showSnackBar("فشل الاتصال بالسيرفر", Colors.red);
    }
  }

  Future<void> changeRole(int id, String currentRole) async {
    final token = await getToken();
    String newRole = currentRole == "admin" ? "user" : "admin";

    try {
      final response = await http
          .put(
            Uri.parse("$baseUrl/admin/users/$id/role"),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
            body: jsonEncode({"role": newRole}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showSnackBar("تم تحديث الصلاحية إلى $newRole", Colors.green);
        loadUsers();
      } else if (response.statusCode == 401) {
        handleSessionExpired();
      } else {
        _showSnackBar("فشل في تحديث الصلاحية", Colors.red);
      }
    } catch (e) {
      _showSnackBar("فشل الاتصال بالسيرفر", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: color,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "إدارة المستخدمين",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1B392A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 🔍 البحث
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              onChanged: (value) {
                search = value;
                loadUsers();
              },
              decoration: InputDecoration(
                hintText: "ابحث بالاسم أو الإيميل...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),

          // 📋 القائمة
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1B392A)),
                  )
                : users.isEmpty
                ? const Center(
                    child: Text(
                      "لا يوجد مستخدمين",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: loadUsers,
                    child: ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        bool isAdmin = user["role"] == "admin";

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListTile(
                              title: Text(
                                user["full_name"] ?? user["name"] ?? "",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(user["email"] ?? ""),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 🏷 شارة الدور
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isAdmin
                                          ? Colors.green.shade100
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isAdmin ? "أدمن" : "مستخدم",
                                      style: TextStyle(
                                        color: isAdmin
                                            ? Colors.green.shade800
                                            : Colors.grey.shade800,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  // 🔁 تغيير role
                                  IconButton(
                                    icon: const Icon(
                                      Icons.admin_panel_settings,
                                      color: Color(0xFF1B392A),
                                    ),
                                    tooltip: "تغيير الصلاحية",
                                    onPressed: () =>
                                        changeRole(user["id"], user["role"]),
                                  ),

                                  // 🗑 حذف
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    tooltip: "حذف المستخدم",
                                    onPressed: () => confirmDeleteUser(
                                      user["id"],
                                      user["name"],
                                    ),
                                  ),
                                  // 🚛 إسناد الشاحنات
                                                                       // 🚛 إسناد الشاحنات (only for non-admin users)
                                      if (!isAdmin)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.local_shipping,
                                            color: Color(0xFF1B4332),
                                          ),
                                          tooltip: "إسناد الشاحنات",
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => AssignTrucksPage(
                                                  userId: user["id"],
                                                  userName: user["full_name"] ?? user["name"] ?? 'User',
                                                  userEmail: user["email"] ?? '',
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
