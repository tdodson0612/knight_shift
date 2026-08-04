// lib/features/legal/legal_reference_screen.dart
//
// Manager-only reference screen for state employment law facts
// relevant to running payroll/scheduling in Knight Shift.
//
// THIS IS INFORMATIONAL ONLY. Nothing on this screen is enforced or
// calculated automatically anywhere else in the app (payroll,
// overtime, etc. all remain exactly as configured in Settings by
// the manager). This screen exists so a manager has the facts in
// front of them and can make their own compliant decisions — it is
// NOT a substitute for an employment attorney or accountant, and
// Knight Shift makes no guarantee of accuracy or completeness.
//
// Currently covers Oregon only. Sourced from Oregon BOLI and
// several employer-law reference sites, cross-checked against each
// other, current as of the "last verified" date below. Employment
// law — especially minimum wage, which adjusts every July 1 in
// Oregon — changes; always confirm current figures at
// oregon.gov/boli before relying on this for a real payroll or
// termination decision.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> _checklistItems = [
  "Post required labor law posters where employees can see them",
  "Confirm minimum wage rate is correct for each work location",
  "Review meal/rest break policy with staff",
  "Confirm final paycheck process matches required timing",
  "Confirm paid sick time accrual/usage policy is set correctly",
];

class LegalReferenceScreen extends StatefulWidget {
  const LegalReferenceScreen({super.key});

  static const String lastVerified = "July 30, 2026";

  @override
  State<LegalReferenceScreen> createState() => _LegalReferenceScreenState();
}

class _LegalReferenceScreenState extends State<LegalReferenceScreen> {
  Set<int> checked = {};
  bool loadingChecklist = true;

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  String get _prefsKey => 'legal_checklist_oregon';

  Future<void> _loadChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey) ?? [];
    if (mounted) {
      setState(() {
        checked = saved.map(int.parse).toSet();
        loadingChecklist = false;
      });
    }
  }

  Future<void> _toggle(int index, bool value) async {
    setState(() {
      if (value) {
        checked.add(index);
      } else {
        checked.remove(index);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      checked.map((i) => i.toString()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Legal Reference — Oregon")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _disclaimer(),
          const SizedBox(height: 20),
          _checklistSection(),
          const SizedBox(height: 20),
          _section(
            title: "Minimum Wage",
            source: "Oregon BOLI, ORS 653.025",
            body: const [
              "Oregon uses three regional rates, adjusted every July 1 "
                  "based on inflation (CPI). No tip credit is allowed — "
                  "tipped employees get the full rate before tips.",
              "",
              "• Portland Metro (parts of Multnomah, Washington, Clackamas "
                  "counties inside the urban growth boundary): \$16.80/hr",
              "• Standard (most of the state): \$15.55/hr",
              "• Non-Urban (18 rural counties): \$14.55/hr",
              "",
              "Pay is based on where the employee physically works, not "
                  "where the business is based. An employee working across "
                  "regions in one week can be owed more than one rate.",
            ],
          ),
          _section(
            title: "Overtime",
            source: "ORS 653.261 / FLSA",
            body: const [
              "Non-exempt employees: 1.5× regular rate for hours over 40 "
                  "in a workweek. Oregon does not have a general daily "
                  "overtime requirement.",
              "",
              "Exception: manufacturing/mill establishments have a "
                  "separate daily overtime rule (over 10 hrs/day) under "
                  "ORS 652.020 — only relevant if that describes your "
                  "business.",
            ],
          ),
          _section(
            title: "Meal & Rest Breaks",
            source: "ORS 653.261, OAR 839-020-0050 / Oregon BOLI",
            body: const [
              "Required for non-exempt employees:",
              "",
              "• Meal break: unpaid, at least 30 minutes, for any shift of "
                  "6+ hours. Must be taken between hours 2 and 5 if the "
                  "shift is 7 hours or less. Employee must be fully "
                  "relieved of duties — if not, the break must be paid.",
              "• Rest break: paid, at least 10 minutes, for every 4-hour "
                  "segment (or major portion of one — 2hr01m to 4hrs) "
                  "worked. Separate from meal breaks, can't be combined "
                  "with them or used to shorten the shift.",
              "",
              "BOLI can fine up to \$1,000 per violation.",
            ],
          ),
          _section(
            title: "Final Paycheck Timing",
            source: "ORS 652.140 / Oregon BOLI",
            body: const [
              "• Terminated or laid off: by the end of the next business "
                  "day.",
              "• Quit with 48+ hours notice: on their last day (next "
                  "business day if it falls on a weekend/holiday).",
              "• Quit with less than 48 hours notice: within 5 business "
                  "days, or the next regular payday — whichever comes "
                  "first.",
              "",
              "Missing these deadlines risks a penalty wage of up to 8× "
                  "the employee's daily rate for every day late (capped at "
                  "30 days) — this is a real, commonly-enforced penalty, "
                  "not a formality.",
            ],
          ),
          _section(
            title: "Paid Sick Time",
            source: "ORS 653.601–653.661 / Oregon BOLI",
            body: const [
              "Applies to every employer with at least one employee in "
                  "Oregon. Whether it must be PAID depends on your size:",
              "",
              "• 10+ employees statewide (6+ in Portland): paid sick time",
              "• Fewer than that: unpaid sick time still required",
              "",
              "Accrual: 1 hour per 30 hours worked, from day one. Usable "
                  "after 90 days. Employers may cap usage at 40 hrs/year "
                  "and total accrual at 80 hrs. Frontloading 40 hrs at the "
                  "start of the year is allowed as an alternative to "
                  "accrual tracking.",
            ],
          ),
          _section(
            title: "Also Worth Knowing",
            source: null,
            body: const [
              "• Paid Leave Oregon — a separate, state-run paid family/"
                  "medical leave insurance program (not the same as sick "
                  "time above). Funded by a payroll contribution split "
                  "between employer and employee; the app does not "
                  "calculate this.",
              "• Oregon Fair Workweek Act (predictive scheduling) — only "
                  "applies to retail, hospitality, or food service "
                  "employers with 500+ employees. Almost certainly "
                  "doesn't apply to a small business, but worth a check "
                  "if you're part of a larger chain.",
            ],
          ),
        ],
      ),
    );
  }

  Widget _checklistSection() {
    if (loadingChecklist) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Your Compliance Checklist",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(
                  "${checked.length}/${_checklistItems.length}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Self-tracked reminders, not verification — checking a box "
              "here doesn't confirm compliance, it's just for you.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Divider(),
            ...List.generate(_checklistItems.length, (i) {
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_checklistItems[i], style: const TextStyle(fontSize: 13)),
                value: checked.contains(i),
                onChanged: (v) => _toggle(i, v ?? false),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Not legal advice",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "This is a plain-language summary for reference, last "
            "verified ${LegalReferenceScreen.lastVerified}. Nothing here is applied "
            "automatically anywhere in the app — payroll and overtime "
            "run exactly as you've configured them in Settings. Laws "
            "change (Oregon's minimum wage in particular, every July "
            "1) — confirm current requirements at oregon.gov/boli or "
            "with an employment attorney before relying on this for a "
            "real decision.",
            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String? source,
    required List<String> body,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (source != null) ...[
              const SizedBox(height: 2),
              Text(
                source,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            const Divider(height: 20),
            ...body.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(line, style: const TextStyle(fontSize: 14)),
                )),
          ],
        ),
      ),
    );
  }
}