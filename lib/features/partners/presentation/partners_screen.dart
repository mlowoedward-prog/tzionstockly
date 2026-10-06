import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/providers.dart';

class PartnersScreen extends ConsumerStatefulWidget {
  const PartnersScreen({super.key});

  @override
  ConsumerState<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends ConsumerState<PartnersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddPartnerDialog(String type) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Add New ${type == "supplier" ? "Supplier" : "Customer"}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F3864), foregroundColor: Colors.white),
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final dbService = ref.read(databaseServiceProvider);
              final bizId = ref.read(currentBusinessIdProvider);

              await dbService.createPartner(
                businessId: bizId,
                name: nameCtrl.text.trim(),
                type: type,
                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
              );

              if (mounted) {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${type == "supplier" ? "Supplier" : "Customer"} saved offline.')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers & Customers'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade300,
          indicatorColor: const Color(0xFF14B8A6),
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping), text: 'Suppliers'),
            Tab(icon: Icon(Icons.people), text: 'Customers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PartnerListView(type: 'supplier', onAdd: () => _showAddPartnerDialog('supplier')),
          _PartnerListView(type: 'customer', onAdd: () => _showAddPartnerDialog('customer')),
        ],
      ),
    );
  }
}

class _PartnerListView extends ConsumerWidget {
  final String type;
  final VoidCallback onAdd;

  const _PartnerListView({required this.type, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(partnersStreamProvider(type));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text('Add New ${type == "supplier" ? "Supplier" : "Customer"}'),
            ),
          ),
        ),
        Expanded(
          child: partnersAsync.when(
            data: (partners) {
              if (partners.isEmpty) {
                return Center(
                  child: Text('No ${type}s added yet.'),
                );
              }
              return ListView.separated(
                itemCount: partners.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = partners[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1F3864).withValues(alpha: 0.1),
                      child: Icon(type == 'supplier' ? Icons.store : Icons.person, color: const Color(0xFF1F3864)),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${p.phone ?? "No phone"} • ${p.email ?? "No email"}'),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}
