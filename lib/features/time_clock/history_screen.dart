// lib/features/time_clock/history_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool loading = true;
  List<Map<String, dynamic>> shifts = [];

  @override
  void initState() {
    super.initState();
    loadShifts();
  }

  Future<void> loadShifts() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final data = await Supabase.instance.client
        .from('time_entries')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    if (!mounted) return;

    setState(() {
      shifts = List<Map<String, dynamic>>.from(data);
      loading = false;
    });
  }

  String formatTime(String? iso) {
    if (iso == null) return "--";

    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return "--";

    return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String calculateDuration(String? inTime, String? outTime) {
    if (inTime == null || outTime == null) return "Active";

    final start = DateTime.tryParse(inTime);
    final end = DateTime.tryParse(outTime);

    if (start == null || end == null) return "Invalid";

    final diff = end.difference(start);

    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    return "${hours}h ${minutes}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Shift History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadShifts,
          )
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : shifts.isEmpty
              ? const Center(child: Text("No shifts yet"))
              : ListView.builder(
                  itemCount: shifts.length,
                  itemBuilder: (context, index) {
                    final s = shifts[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(
                          "${formatTime(s['clock_in'])} → ${formatTime(s['clock_out'])}",
                        ),
                        subtitle: Text(
                          "Duration: ${calculateDuration(s['clock_in'], s['clock_out'])}",
                        ),
                        trailing: Icon(
                          s['clock_out'] == null
                              ? Icons.play_circle
                              : Icons.check_circle,
                          color: s['clock_out'] == null
                              ? Colors.orange
                              : Colors.green,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}