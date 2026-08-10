// lib/features/company/company_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/session_service.dart';
import 'company_gate.dart';

class CompanySelectionScreen extends StatefulWidget {
  const CompanySelectionScreen({super.key});

  @override
  State<CompanySelectionScreen> createState() =>
      _CompanySelectionScreenState();
}

class _CompanySelectionScreenState extends State<CompanySelectionScreen> {
  bool loading = true;
  List<Map<String, dynamic>> companies = [];

  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await SessionService.getMyCompanies();

    if (!mounted) return;

    setState(() {
      companies = res;
      loading = false;
    });
  }

  Future<void> _createCompany() async {
    final user = Supabase.instance.client.auth.currentUser;
    final name = controller.text.trim();

    if (user == null || name.isEmpty) return;

    final company = await Supabase.instance.client
        .from('companies')
        .insert({
          'name': name,
        })
        .select()
        .single();

    await Supabase.instance.client.from('company_members').insert({
      'company_id': company['id'],
      'user_id': user.id,
      'role': 'manager',
    });

    controller.clear();
    await _load();
  }

  Future<void> _enter(Map<String, dynamic> c) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    final companyId = c['company_id']?.toString();
    final companyName = c['companies']?['name']?.toString() ?? 'Unknown';
    final role = c['role']?.toString() ?? 'employee';

    if (companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open company. Missing company ID.'),
        ),
      );
      return;
    }

    // SessionService.setActiveCompany() is synchronous (returns void),
    // so do NOT await it.
    SessionService.setActiveCompany(
      companyId: companyId,
      companyName: companyName,
      role: role,
      userId: user.id,
    );

    if (!mounted) return;

    // Return control to CompanyGate rather than jumping straight to
    // HomeScreen — CompanyGate owns all post-selection routing
    // (role sync, manager vs. employee branching).
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const CompanyGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Company"),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(
                  child: companies.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(Icons.business_outlined, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text(
                                  "No companies yet",
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Create your first company below to get started",
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: companies.length,
                          itemBuilder: (_, i) {
                            final c = companies[i];
                            final name =
                                c['companies']?['name']?.toString() ?? 'Unnamed';
                            final role =
                                c['role']?.toString() ?? 'employee';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.business_outlined, size: 24),
                                title: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  "Role: $role",
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () => _enter(c),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: "New Company",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.add_business_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _createCompany,
                          child: const Text("Create Company"),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}