import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum BadgeStatus { active, inactive, pending, warning, error }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.status,
  });

  StatusBadge.fromString({
    super.key,
    required String value,
  })  : label = value,
        status = _fromString(value);

  final String label;
  final BadgeStatus status;

  static BadgeStatus _fromString(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return BadgeStatus.active;
      case 'inactive':
        return BadgeStatus.inactive;
      case 'pending':
        return BadgeStatus.pending;
      case 'warning':
        return BadgeStatus.warning;
      case 'error':
        return BadgeStatus.error;
      default:
        return BadgeStatus.inactive;
    }
  }

  Color get _bgColor {
    switch (status) {
      case BadgeStatus.active:
        return AppColors.success.withValues(alpha: 0.12);
      case BadgeStatus.inactive:
        return AppColors.neutralGray.withValues(alpha: 0.12);
      case BadgeStatus.pending:
        return AppColors.warning.withValues(alpha: 0.12);
      case BadgeStatus.warning:
        return AppColors.warning.withValues(alpha: 0.12);
      case BadgeStatus.error:
        return AppColors.error.withValues(alpha: 0.12);
    }
  }

  Color get _textColor {
    switch (status) {
      case BadgeStatus.active:
        return AppColors.success;
      case BadgeStatus.inactive:
        return AppColors.neutralGray;
      case BadgeStatus.pending:
        return AppColors.warning;
      case BadgeStatus.warning:
        return AppColors.warning;
      case BadgeStatus.error:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
