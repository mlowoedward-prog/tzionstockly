import 'package:flutter_test/flutter_test.dart';
import 'package:tzion_stockly/features/auth/domain/auth_models.dart';
import 'package:tzion_stockly/features/auth/domain/role_permissions.dart';

void main() {
  group('Prompt 4 Roles & Permission Unit Tests', () {
    test('Staff permissions matrix restricts cost viewing and admin actions', () {
      const staffRole = UserRole.staff;

      expect(RolePermissions.canViewCostPrices(staffRole), isFalse);
      expect(RolePermissions.canViewFinancialReports(staffRole), isFalse);
      expect(RolePermissions.canEditProducts(staffRole), isFalse);
      expect(RolePermissions.canArchiveRecords(staffRole), isFalse);
      expect(RolePermissions.canManageUsers(staffRole), isFalse);
      expect(RolePermissions.canRecordStockMovements(staffRole), isTrue);
    });

    test('Manager permissions matrix allows cost viewing and product management but blocks user management', () {
      const managerRole = UserRole.manager;

      expect(RolePermissions.canViewCostPrices(managerRole), isTrue);
      expect(RolePermissions.canViewFinancialReports(managerRole), isTrue);
      expect(RolePermissions.canEditProducts(managerRole), isTrue);
      expect(RolePermissions.canArchiveRecords(managerRole), isTrue);
      expect(RolePermissions.canManageUsers(managerRole), isFalse);
      expect(RolePermissions.canRecordStockMovements(managerRole), isTrue);
    });

    test('Owner permissions matrix allows all capabilities including user management', () {
      const ownerRole = UserRole.owner;

      expect(RolePermissions.canViewCostPrices(ownerRole), isTrue);
      expect(RolePermissions.canViewFinancialReports(ownerRole), isTrue);
      expect(RolePermissions.canEditProducts(ownerRole), isTrue);
      expect(RolePermissions.canArchiveRecords(ownerRole), isTrue);
      expect(RolePermissions.canManageUsers(ownerRole), isTrue);
      expect(RolePermissions.canRecordStockMovements(ownerRole), isTrue);
    });

    test('UserProfile roleEnum parsing and AuthState role fallback', () {
      const userProfile = UserProfile(
        id: 'u1',
        email: 'staff@shop.tz',
        businessId: 'b1',
        role: 'staff',
      );

      expect(userProfile.roleEnum, equals(UserRole.staff));

      const authState = AuthState(userProfile: userProfile);
      expect(authState.userRole, equals(UserRole.staff));

      const defaultAuthState = AuthState();
      expect(defaultAuthState.userRole, equals(UserRole.owner));
    });
  });
}
