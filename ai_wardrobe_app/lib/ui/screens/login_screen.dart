import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../services/auth_api_service.dart';
import '../../theme/app_theme.dart';
import '../root_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'demo');
  final _emailController = TextEditingController(text: 'demo@example.com');
  final _passwordController = TextEditingController(text: 'demo123456');

  bool _isSigningIn = false;
  bool _isRegisterMode = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSigningIn) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSigningIn = true;
      _error = null;
    });
    try {
      if (_isRegisterMode) {
        await AuthApiService.register(
          username: _usernameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await AuthApiService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const RootShell()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_error!)));
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _continueWithDemo() async {
    setState(() {
      _isRegisterMode = false;
      _emailController.text = 'demo@example.com';
      _passwordController.text = 'demo123456';
    });
    await _submit();
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
                _isRegisterMode
                    ? 'Create an account to get your own wardrobe and card packs.'
                    : 'Sign in to load your wardrobe, discover packs, and outfit canvas data.',
                style: TextStyle(fontSize: 13, color: textS),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text('Sign In'),
                    selected: !_isRegisterMode,
                    onSelected: (_) => setState(() => _isRegisterMode = false),
                  ),
                  ChoiceChip(
                    label: const Text('Register'),
                    selected: _isRegisterMode,
                    onSelected: (_) => setState(() => _isRegisterMode = true),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      if (_isRegisterMode) ...[
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (!_isRegisterMode) return null;
                            if (value == null || value.trim().length < 3) {
                              return 'Username must be at least 3 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty ||
                              !text.contains('@') ||
                              !text.contains('.')) {
                            return 'Please enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                        validator: (value) {
                          if ((value ?? '').length < 8) {
                            return 'Password must be at least 8 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade400,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: _isSigningIn ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSigningIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                _isRegisterMode ? 'Create Account' : 'Sign In',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _isSigningIn ? null : _continueWithDemo,
                        child: const Text('Use Demo Account'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => const RootShell(),
                            ),
                          );
                        },
                        child: Text(
                          s.skipForNow,
                          style: TextStyle(fontSize: 13, color: textS),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
