import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// First step when starting a new weld — the operator picks the process type.
///
/// Butt-welding (termofusão) is fully implemented.
/// Electrofusion (eletrofusão) is scaffolded and will be enabled in a future
/// release.
class WeldTypeSelectorScreen extends StatelessWidget {
  const WeldTypeSelectorScreen({super.key, this.preselectedProjectId});

  /// When navigated from a project detail screen, the project is pre-selected
  /// in the subsequent setup form.
  final String? preselectedProjectId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(title: const Text('New Weld')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              const Text(
                'Select Welding Type',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose the fusion process to begin weld setup.',
                style: TextStyle(fontSize: 14, color: AppColors.neutralGray),
              ),
              const SizedBox(height: 32),

              // ── Butt-welding card ──────────────────────────────────────────
              _WeldTypeCard(
                icon: Icons.compress_rounded,
                title: 'Butt Welding',
                subtitle: 'Termofusão',
                description:
                    'Heat the pipe ends with a heating element and join them '
                    'under controlled pressure. Compatible with DVS 2207, '
                    'ISO 21307, and ASTM F2620.',
                standards: const ['DVS 2207', 'ISO 21307', 'ASTM F2620'],
                isAvailable: true,
                badge: null,
                color: AppColors.sertecRed,
                onTap: () {
                  final extra = preselectedProjectId != null
                      ? {'preselectedProjectId': preselectedProjectId}
                      : null;
                  context.push('/weld/setup/butt', extra: extra);
                },
              ),
              const SizedBox(height: 16),

              // ── Electrofusion card ─────────────────────────────────────────
              _WeldTypeCard(
                icon: Icons.electric_bolt_rounded,
                title: 'Electrofusion',
                subtitle: 'Eletrofusão',
                description:
                    'Use an electrofusion fitting with an embedded heating coil. '
                    'Electrical current melts the fitting from inside and fuses '
                    'it to the pipe.',
                standards: const ['ISO 11974', 'DVS 2207-2', 'ASTM F1055'],
                isAvailable: false,
                badge: 'Coming soon',
                color: const Color(0xFF1565C0),
                onTap: () {
                  _showComingSoon(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Electrofusion — Coming Soon'),
        content: const Text(
          'The electrofusion module is currently under development.\n\n'
          'It will support barcode scanning of fitting parameters, '
          'EF controller connectivity, and full ISO 11974 / DVS 2207-2 compliance.\n\n'
          'Please use butt-welding for now.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(backgroundColor: AppColors.sertecRed),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ── Card widget ────────────────────────────────────────────────────────────────

class _WeldTypeCard extends StatelessWidget {
  const _WeldTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.standards,
    required this.isAvailable,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final List<String> standards;
  final bool isAvailable;
  final String? badge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isAvailable ? color.withValues(alpha: 0.25) : const Color(0xFFE0E0E0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isAvailable
                  ? color.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Icon + title row ──────────────────────────────────────────
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: (isAvailable ? color : AppColors.neutralGray)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon,
                    color: isAvailable ? color : AppColors.neutralGray,
                    size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isAvailable ? const Color(0xFF1A1A1A) : AppColors.neutralGray,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.neutralGray.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.neutralGray),
                        ),
                      ),
                    ],
                  ]),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: isAvailable ? color : AppColors.neutralGray,
                        fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
              if (isAvailable)
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color)
              else
                Icon(Icons.lock_outline_rounded,
                    size: 16, color: AppColors.neutralGray),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // ── Description ───────────────────────────────────────────────
            Text(
              description,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.neutralGray, height: 1.5),
            ),
            const SizedBox(height: 12),

            // ── Standards chips ───────────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: standards
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isAvailable ? color : AppColors.neutralGray)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (isAvailable ? color : AppColors.neutralGray)
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isAvailable ? color : AppColors.neutralGray,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ]),
        ),
      ),
    );
  }
}
