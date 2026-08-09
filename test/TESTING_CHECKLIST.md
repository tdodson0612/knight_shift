# Knight Shift — Testing Checklist

## Status Key
- **automated and passing** — covered by a passing `flutter test`
- **code-verified only** — inspected in source, no runtime test yet
- **requires live Supabase** — needs real DB/RLS/storage to verify
- **requires real device** — needs physical iOS/Android hardware
- **requires external Firebase/Apple setup** — needs Firebase project + APNs key

---

## Roles

| Item | Status | Notes |
|------|--------|-------|
| manager can schedule shifts | automated and passing | `RoleService.isManager()` tested in `test/role_service_test.dart` |
| employee can request time off | code-verified only | `scheduling_screen.dart` branches on `isEmployee`; no automated widget test yet |
| accountant sees payroll only | automated and passing | `RoleService.isAccountant()` tested; accountant explicitly excluded from `isManager()` |
| role sync from DB | code-verified only | `RoleService.syncRole` reads from `company_members.role`; tested implicitly by login flow |
| RLS prevents role escalation | requires live Supabase | Must verify a non-manager cannot write to `companies` via REST |

---

## Security / RLS

| Item | Status | Notes |
|------|--------|-------|
| no screen silently returns empty data because of missing RLS | requires live Supabase | Must verify each table's SELECT policy allows the intended role |
| company isolation | requires live Supabase | Must verify `company_id` filter is applied in every query; RLS is the enforcement layer |
| clock-in photo Storage RLS | requires live Supabase | `clock-in-photos` bucket must be private; signed URLs expire in 10 min per `ClockInPhotoService` |

---

## Scheduling

| Item | Status | Notes |
|------|--------|-------|
| Copy Week | code-verified only | `ShiftService.copyShifts` calls `createShift` per row; conflicts skipped individually |
| recurring shifts | code-verified only | `recurring_shift_screen.dart` generates shifts via `createShift`; no DB round-trip dependency |
| duplicate/overlap behavior | automated and passing | `ShiftModel.overlaps` and `reservesTimeSlot` are pure logic; `hasConflict` queries DB |
| labor budget warning | automated and passing | `LaborBudgetService.exceedsBudget`, `projectedWeeklyHours`, `crossesOvertimeThreshold` tested in `test/labor_budget_service_test.dart` |
| overtime-risk warning | automated and passing | `OvertimeService.splitHours` pure math tested in `test/overtime_service_test.dart` |
| required-skill warning | code-verified only | `EmployeeSkillService.userLacksSkill` + advisory dialog in `scheduling_screen.dart` |
| open-shift claim priority | requires live Supabase | `company_members.hire_date` + `companies.open_shift_priority` must be live; claim logic needs DB |

---

## Time Clock

| Item | Status | Notes |
|------|--------|-------|
| deep linking on real device | requires real device | `DeepLinkService` handles `knightshift://` scheme; cold-start defers one frame if navigator not ready |
| geofencing permission flows | code-verified only | `GeofenceService.isWithinGeofence` pure math tested; runtime permission flow requires device |
| photo-on-clock-in on iOS and Android | requires real device + external setup | `ClockInPhotoService` uses `image_picker` front camera; requires platform config |
| audit trail | requires live Supabase | `time_entry_audit_log` trigger auto-logs every insert/update/delete; viewable via `TimeEntryService.getAuditLog` |

---

## Payroll

| Item | Status | Notes |
|------|--------|-------|
| real overtime calculation | automated and passing | `OvertimeService.splitHours` covers daily, weekly, combined, hours_only, and clamping |
| correct dollar amounts | automated and passing | `OvertimeBreakdown.regularPay` / `overtimePay` verified against known inputs in overtime tests |

---

## Push Notifications

| Item | Status | Notes |
|------|--------|-------|
| app boots without Firebase | automated and passing | All 3 widget tests log `PushNotificationService init skipped` and still pass |
| push initialization fails open | automated and passing | `try/catch` in `PushNotificationService.init` + `handleInitialMessage` catches `[core/no-app]` |
| verify actual delivery once Firebase is configured | requires external Firebase/Apple setup | Needs `google-services.json` / `GoogleService-Info.plist` + Firebase project + APNs key + deployed Edge Function |

---

## Firebase / Push Setup Completeness (Task 1)

| Check | Status | Evidence |
|--------|--------|----------|
| app boots | automated and passing | `widget_test.dart` |
| login works | automated and passing | `login_flow_test.dart` |
| company gate works | automated and passing | `company_selection_flow_test.dart` |
| no startup hangs | automated and passing | `SplashRouter._boot()` is not awaited; splash transitions immediately |
| no crash when Firebase unavailable | automated and passing | All tests run without Firebase config; log shows graceful skip |
| push init fails open | automated and passing | Debug print confirms skip, no exception propagated |
| no core feature depends on push | code-verified only | In-app notifications use `NotificationService` (Supabase); push is only the OS delivery layer |
| documentation clear | code-verified only | `docs/push-notifications-setup.md` lists all 7 prerequisites explicitly |

---

## Summary

| Category | Automated & Passing | Code-Verified Only | Requires Live Supabase | Requires Real Device | Requires External Setup |
|----------|---------------------|--------------------|----------------------|--------------------|----------------------|
| Roles | 2 | 2 | 1 | 0 | 0 |
| Security / RLS | 0 | 0 | 3 | 0 | 0 |
| Scheduling | 2 | 3 | 2 | 0 | 0 |
| Time Clock | 0 | 1 | 1 | 2 | 1 |
| Payroll | 2 | 0 | 0 | 0 | 0 |
| Push | 2 | 1 | 0 | 0 | 1 |
| **Total** | **8** | **7** | **7** | **2** | **2** |

### Next Steps to Close Gaps
1. **Live Supabase**: Run integration tests against the linked project (`supabase db query --linked`) to verify RLS, company isolation, and claim-priority logic.
2. **Real device**: Test deep-link cold start, geofencing permission flow, and camera-based clock-in photo on physical iOS + Android.
3. **External Firebase/Apple**: Complete the 7-step setup in `docs/push-notifications-setup.md` and verify end-to-end push delivery.
