import 'package:flutter_test/flutter_test.dart';
import 'package:knight_shift/core/services/role_service.dart';
import 'package:knight_shift/core/services/session_service.dart';

void main() {
  group('RoleService', () {
    setUp(() {
      SessionService.activeRole = null;
      SessionService.activeCompanyId = null;
      SessionService.activeUserId = null;
    });

    tearDown(() {
      SessionService.activeRole = null;
      SessionService.activeCompanyId = null;
      SessionService.activeUserId = null;
    });

    group('isManager', () {
      test('manager returns true', () {
        SessionService.activeRole = 'manager';
        expect(RoleService.isManager(), isTrue);
      });

      test('admin returns true', () {
        SessionService.activeRole = 'admin';
        expect(RoleService.isManager(), isTrue);
      });

      test('employee returns false', () {
        SessionService.activeRole = 'employee';
        expect(RoleService.isManager(), isFalse);
      });

      test('accountant returns false', () {
        SessionService.activeRole = 'accountant';
        expect(RoleService.isManager(), isFalse);
      });

      test('null role returns false', () {
        expect(RoleService.isManager(), isFalse);
      });
    });

    group('isAdmin', () {
      test('admin returns true', () {
        SessionService.activeRole = 'admin';
        expect(RoleService.isAdmin(), isTrue);
      });

      test('manager returns false', () {
        SessionService.activeRole = 'manager';
        expect(RoleService.isAdmin(), isFalse);
      });
    });

    group('isEmployee', () {
      test('employee returns true', () {
        SessionService.activeRole = 'employee';
        expect(RoleService.isEmployee(), isTrue);
      });

      test('manager returns false', () {
        SessionService.activeRole = 'manager';
        expect(RoleService.isEmployee(), isFalse);
      });
    });

    group('isAccountant', () {
      test('accountant returns true', () {
        SessionService.activeRole = 'accountant';
        expect(RoleService.isAccountant(), isTrue);
      });

      test('manager returns false', () {
        SessionService.activeRole = 'manager';
        expect(RoleService.isAccountant(), isFalse);
      });
    });

    group('permissions', () {
      test('manager can manage employees', () {
        SessionService.activeRole = 'manager';
        expect(RoleService.canManageEmployees(), isTrue);
      });

      test('admin can manage employees', () {
        SessionService.activeRole = 'admin';
        expect(RoleService.canManageEmployees(), isTrue);
      });

      test('employee cannot manage employees', () {
        SessionService.activeRole = 'employee';
        expect(RoleService.canManageEmployees(), isFalse);
      });

      test('accountant cannot manage employees', () {
        SessionService.activeRole = 'accountant';
        expect(RoleService.canManageEmployees(), isFalse);
      });

      test('manager can edit schedule', () {
        SessionService.activeRole = 'manager';
        expect(RoleService.canEditSchedule(), isTrue);
      });

      test('employee cannot edit schedule', () {
        SessionService.activeRole = 'employee';
        expect(RoleService.canEditSchedule(), isFalse);
      });

      test('anyone with company can view dashboard', () {
        SessionService.activeRole = 'employee';
        SessionService.activeCompanyId = 'company-1';
        expect(RoleService.canViewDashboard(), isTrue);
      });

      test('no company cannot view dashboard', () {
        SessionService.activeRole = 'employee';
        SessionService.activeCompanyId = null;
        expect(RoleService.canViewDashboard(), isFalse);
      });
    });
  });
}
