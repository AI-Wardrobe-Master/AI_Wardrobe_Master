import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../root_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSubmitting = false;

  Future<void> _openApp() async {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const RootShell()),
    );
  }

  Future<void> _enterWithBackend() async {
    if (_isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await AuthService.ensureDemoSession();
      await _openApp();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to start the demo session. Please make sure the backend is running.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _enterOfflineDemo() async {
    if (_isSubmitting) {
      return;
    }

    AuthService.enterGuestMode();
    await _openApp();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.appTitle,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: textP,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.loginSubtitle,
                style: TextStyle(fontSize: 13, color: textS),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          size: 64,
                          color: AppColors.accentBlue,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        s.loginDemoHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: textS),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Offline demo is available without the backend.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _isSubmitting ? null : _enterOfflineDemo,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      s.skipForNow,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : _enterWithBackend,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textP,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    child: Text(
                      _isSubmitting ? 'Connecting...' : 'Continue with Backend',
                      style: TextStyle(fontSize: 13, color: textS),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
