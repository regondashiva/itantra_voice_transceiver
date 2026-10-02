import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Standard mission-control scaffold for iTantra screens.
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? bottomNavigationBar;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? subtitleWidget;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomNavigationBar,
    this.actions,
    this.leading,
    this.showBack = false,
    this.onBack,
    this.subtitleWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.primaryText),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : leading,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.screenTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            ?subtitleWidget,
          ],
        ),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: AppColors.border,
            height: 1.0,
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: body,
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
