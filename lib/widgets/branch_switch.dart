import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// AppBar button for the owner: pick "All branches" or one branch.
/// The choice is shared by every screen (orders, reports, staff, expenses, delivery, stock…).
class BranchSwitch extends StatelessWidget {
  const BranchSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.data;
    if (d == null || !app.isOwner || d.branches.length < 2) return const SizedBox.shrink();
    final cur = d.branches.where((b) => b.id == app.branchFilter).firstOrNull;
    return PopupMenuButton<String>(
      tooltip: app.t('allBranches'),
      onSelected: (v) => app.setBranchFilter(v == '*' ? null : v),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: '*', checked: cur == null, child: Text('${app.t('allBranches')} (${d.branches.length})')),
        for (final b in d.branches) CheckedPopupMenuItem(value: b.id, checked: cur?.id == b.id, child: Text(b.name)),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cur == null ? Colors.transparent : const Color(0xFFE6EEFC),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: LD.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.store_mall_directory_outlined, size: 16, color: LD.primary),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(cur?.name ?? app.t('allBranches'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: LD.navy)),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: LD.navy),
        ]),
      ),
    );
  }
}
