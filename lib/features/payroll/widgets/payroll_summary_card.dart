// lib/features/time_clock/widgets/time_clock_card.dart

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
