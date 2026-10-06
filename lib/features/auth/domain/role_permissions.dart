enum UserRole {
  owner,
  manager,
  staff;

  factory UserRole.fromString(String? roleStr) {
    switch (roleStr?.toLowerCase()) {
      case 'owner':
        return UserRole.owner;
      case 'manager':
        return UserRole.manager;
      case 'staff':
      default:
        return UserRole.staff;
    }
  }

  String toFormattedString() {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
      case UserRole.staff:
        return 'Staff';
    }
  }
}

class RolePermissions {
  /// Staff cannot see cost prices, COGS, or cost valuation
  static bool canViewCostPrices(UserRole role) {
    return role == UserRole.owner || role == UserRole.manager;
  }

  /// Staff cannot access financial reports or gross profit calculations
  static bool canViewFinancialReports(UserRole role) {
    return role == UserRole.owner || role == UserRole.manager;
  }

  /// Staff have limited editing capabilities (cannot edit cost price or delete products)
  static bool canEditProducts(UserRole role) {
    return role == UserRole.owner || role == UserRole.manager;
  }

  /// Staff cannot archive or soft delete records
  static bool canArchiveRecords(UserRole role) {
    return role == UserRole.owner || role == UserRole.manager;
  }

  /// Only Owners can invite team members and assign roles
  static bool canManageUsers(UserRole role) {
    return role == UserRole.owner;
  }

  /// All roles can record stock movements (sales, purchases, stock taking)
  static bool canRecordStockMovements(UserRole role) {
    return true;
  }
}
