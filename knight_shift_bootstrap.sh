#!/bin/bash

echo "🧱 Building Knight Shift missing structure..."

mkdir -p lib/features/dashboard
mkdir -p lib/features/reports
mkdir -p lib/features/settings
mkdir -p lib/features/time_clock/widgets
mkdir -p lib/features/payroll/widgets
mkdir -p lib/features/scheduling/widgets

# -------------------------
# DASHBOARD (EMPLOYEE HOME)
# -------------------------
cat << 'EOT' > lib/features/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text("Employee Dashboard - TODO"),
      ),
    );
  }
}
EOT

# -------------------------
# REPORTS SCREEN (PLACEHOLDER)
# -------------------------
cat << 'EOT' > lib/features/reports/reports_screen.dart
import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text("Reports - TODO"),
      ),
    );
  }
}
EOT

# -------------------------
# SETTINGS SCREEN
# -------------------------
cat << 'EOT' > lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text("Settings - TODO"),
      ),
    );
  }
}
EOT

# -------------------------
# TIME CLOCK WIDGETS PLACEHOLDER
# -------------------------
cat << 'EOT' > lib/features/time_clock/widgets/time_clock_card.dart
import 'package:flutter/material.dart';

class TimeClockCard extends StatelessWidget {
  const TimeClockCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text("Time Clock Widget"),
      ),
    );
  }
}
EOT

# -------------------------
# PAYROLL WIDGETS PLACEHOLDER
# -------------------------
cat << 'EOT' > lib/features/payroll/widgets/payroll_summary_card.dart
import 'package:flutter/material.dart';

class PayrollSummaryCard extends StatelessWidget {
  const PayrollSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text("Payroll Summary"),
      ),
    );
  }
}
EOT

echo "✅ Structure created successfully."
