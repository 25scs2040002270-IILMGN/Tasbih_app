import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/database_helper.dart';
import '../models/dhikr.dart';
import '../services/counter_service.dart';

/// Bottom sheet that allows the user to select, add, edit, or delete a Dhikr.
class DhikrSelectorSheet extends StatefulWidget {
  const DhikrSelectorSheet({super.key});

  @override
  State<DhikrSelectorSheet> createState() => _DhikrSelectorSheetState();
}

class _DhikrSelectorSheetState extends State<DhikrSelectorSheet> {
  List<Dhikr> _dhikrList = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<DatabaseHelper>();
    final list = await db.getAllDhikr();
    if (mounted) {
      setState(() {
        _dhikrList = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final counter = context.watch<CounterService>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Select Dhikr',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add custom Dhikr',
                      onPressed: () => _showAddEditDialog(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _dhikrList.length,
                    itemBuilder: (context, index) {
                      final dhikr = _dhikrList[index];
                      final isSelected =
                          counter.selectedDhikr?.id == dhikr.id;

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor:
                            colorScheme.primaryContainer.withAlpha(80),
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          child: Icon(
                            isSelected
                                ? Icons.check
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          dhikr.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: dhikr.arabic.isNotEmpty
                            ? Text(
                                dhikr.arabic,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'serif',
                                ),
                                textDirection: TextDirection.rtl,
                              )
                            : null,
                        trailing: dhikr.isCustom
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showAddEditDialog(context,
                                        existing: dhikr);
                                  } else if (value == 'delete') {
                                    _confirmDelete(context, dhikr);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Edit'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('Delete'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        onTap: () async {
                          await counter.selectDhikr(dhikr);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddEditDialog(
    BuildContext context, {
    Dhikr? existing,
  }) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    final arabicController =
        TextEditingController(text: existing?.arabic ?? '');
    final formKey = GlobalKey<FormState>();

    // Capture db before any async gap.
    final db = context.read<DatabaseHelper>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Dhikr' : 'Edit Dhikr'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g. SubhanAllah',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: arabicController,
                decoration: const InputDecoration(
                  labelText: 'Arabic (optional)',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Capture context-dependent objects before async gap.
    if (existing == null) {
      await db.insertDhikr(Dhikr(
        name: nameController.text.trim(),
        arabic: arabicController.text.trim(),
        isCustom: true,
        createdAt: DateTime.now().toIso8601String(),
      ));
    } else {
      await db.updateDhikr(existing.copyWith(
        name: nameController.text.trim(),
        arabic: arabicController.text.trim(),
      ));
    }
    if (mounted) await _load();
  }

  Future<void> _confirmDelete(BuildContext context, Dhikr dhikr) async {
    // Capture context-dependent objects before any async gap.
    final db = context.read<DatabaseHelper>();
    final counter = context.read<CounterService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Dhikr'),
        content: Text(
          'Delete "${dhikr.name}"? This will not remove past sessions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await db.deleteDhikr(dhikr.id!);

    // If the deleted dhikr was selected, switch to first available
    if (counter.selectedDhikr?.id == dhikr.id) {
      final remaining = await db.getAllDhikr();
      if (remaining.isNotEmpty && mounted) {
        await counter.selectDhikr(remaining.first);
      }
    }

    if (mounted) await _load();
  }
}
