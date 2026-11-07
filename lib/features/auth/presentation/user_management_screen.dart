import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/database/providers.dart';
import '../domain/role_permissions.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final List<Map<String, String>> _mockMembers = [
    {'email': 'owner@duka.co.tz', 'role': 'owner'},
    {'email': 'manager@duka.co.tz', 'role': 'manager'},
    {'email': 'staff1@duka.co.tz', 'role': 'staff'},
  ];

  void _showInviteDialog() {
    final emailController = TextEditingController();
    UserRole selectedRole = UserRole.staff;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Invite Shop Member'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Member Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Assigned Role',
                      prefixIcon: Icon(Icons.security_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: UserRole.staff, child: Text('Staff')),
                      DropdownMenuItem(value: UserRole.manager, child: Text('Manager')),
                      DropdownMenuItem(value: UserRole.owner, child: Text('Owner')),
                    ],
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selectedRole = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final email = emailController.text.trim();
                    if (email.isNotEmpty && email.contains('@')) {
                      setState(() {
                        _mockMembers.add({
                          'email': email,
                          'role': selectedRole.name,
                        });
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Invitation sent to $email')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Send Invite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userRole = ref.watch(userRoleProvider);
    final canManage = RolePermissions.canManageUsers(userRole);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Team & Roles'),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _showInviteDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Invite Member'),
              backgroundColor: AppTheme.secondaryTeal,
            )
          : null,
      body: canManage
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Store Code Onboarding Card
                Card(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'STORE JOIN CODE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: AppTheme.primaryNavy,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'SaaS Multi-Store',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'TZ-MAIN',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                fontFamily: 'monospace',
                                color: AppTheme.primaryNavy,
                              ),
                            ),
                            const Spacer(),
                            IconButton.filledTonal(
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(text: 'TZ-MAIN'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Store Code copied! Share with your Cashiers & Staff.')),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              tooltip: 'Copy Store Code',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share this code with your staff so they can join this store directly.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'TEAM MEMBERS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ..._mockMembers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final member = entry.value;
                  final role = UserRole.fromString(member['role']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: role == UserRole.owner
                            ? AppTheme.primaryNavy
                            : role == UserRole.manager
                                ? AppTheme.secondaryTeal
                                : Colors.grey.shade400,
                        child: Icon(
                          role == UserRole.owner
                              ? Icons.shield_rounded
                              : role == UserRole.manager
                                  ? Icons.manage_accounts_rounded
                                  : Icons.person_rounded,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(member['email']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Role: ${role.toFormattedString()}'),
                      trailing: PopupMenuButton<UserRole>(
                        onSelected: (newRole) {
                          setState(() {
                            _mockMembers[index]['role'] = newRole.name;
                          });
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: UserRole.staff, child: Text('Staff')),
                          PopupMenuItem(value: UserRole.manager, child: Text('Manager')),
                          PopupMenuItem(value: UserRole.owner, child: Text('Owner')),
                        ],
                        child: const Icon(Icons.more_vert),
                      ),
                    ),
                  );
                }),
              ],
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Access Restricted',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Only the Business Owner can manage shop members and assigned permissions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
