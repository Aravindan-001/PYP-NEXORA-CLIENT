import 'dart:async';
import 'package:flutter/foundation.dart'
    show
        kIsWeb,
        defaultTargetPlatform,
        TargetPlatform,
        PlatformDispatcher,
        kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'widgets/booking_card.dart';
import 'widgets/booking_chat_screen.dart';
import 'widgets/booking_dialog.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/photographer_card.dart';
import 'widgets/portfolio_manager_widget.dart';
import 'widgets/pyp_header.dart';

// Safe Local Supabase Configuration
const String rawSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);

/// Dynamically resolves the Supabase URL:
/// Replaces 127.0.0.1 or localhost with 10.0.2.2 when running on Android emulator.
String get supabaseUrl {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (rawSupabaseUrl.contains('127.0.0.1')) {
      return rawSupabaseUrl.replaceAll('127.0.0.1', '10.0.2.2');
    }
    if (rawSupabaseUrl.contains('localhost')) {
      return rawSupabaseUrl.replaceAll('localhost', '10.0.2.2');
    }
  }
  return rawSupabaseUrl;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Core
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Pass Flutter framework errors to Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  // Pass uncaught asynchronous errors to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Initialize Supabase
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);

  runApp(const PYPApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class PYPApp extends StatelessWidget {
  const PYPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PYP — Pick Your Photographer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

/// Authentication State Router
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isResettingPassword = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (mounted) {
          setState(() {
            _isResettingPassword = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isResettingPassword) {
      return ResetPasswordScreen(
        onPasswordResetComplete: () {
          if (mounted) {
            setState(() {
              _isResettingPassword = false;
            });
          }
        },
      );
    }

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session != null) {
          return const HomeScreen();
        }
        return const AuthScreen();
      },
    );
  }
}

/// 1. Role-Aware Authentication Screen
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Selected portal & role: 'customer' or 'photographer' (Admin role strictly disallowed)
  String _selectedRolePortal = 'customer';

  bool _isResendingConfirmation = false;
  DateTime? _lastResendAt;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _getFriendlyErrorMessage(dynamic error) {
    if (error == null) return 'Authentication failed. Please try again.';
    final errorStr = error.toString();
    final lowerErrorStr = errorStr.toLowerCase();

    if (lowerErrorStr.contains('socketexception') ||
        lowerErrorStr.contains('connection refused') ||
        lowerErrorStr.contains('failed host lookup') ||
        lowerErrorStr.contains('clientexception') ||
        lowerErrorStr.contains('httpexception') ||
        lowerErrorStr.contains('network') ||
        lowerErrorStr.contains('127.0.0.1') ||
        lowerErrorStr.contains('10.0.2.2') ||
        lowerErrorStr.contains('port = 54321')) {
      return 'Unable to connect to the authentication server. Please check your network connection or local Supabase server.';
    }

    if (error is AuthException) {
      final statusCode = error.statusCode;
      final code = error.code?.toLowerCase() ?? '';
      final msg = error.message;
      final lowerMsg = msg.toLowerCase();

      if (statusCode == '429' ||
          code.contains('rate_limit') ||
          code.contains('429') ||
          code.contains('over_email_send_rate_limit') ||
          lowerMsg.contains('rate limit') ||
          lowerMsg.contains('rate_limit') ||
          lowerMsg.contains('429') ||
          lowerMsg.contains('over_email_send_rate_limit')) {
        return 'Email or sign-up rate limit reached. Please wait a few minutes before trying again or requesting another confirmation email.';
      }

      if (code.contains('one_time_token_not_found') ||
          code.contains('otp_expired') ||
          code.contains('invalid_grant') ||
          lowerMsg.contains('one-time token not found') ||
          lowerMsg.contains('token has expired') ||
          lowerMsg.contains('otp_expired')) {
        return 'This verification link is invalid, expired, or has already been used. Please sign in or request a new link.';
      }

      if (lowerMsg.contains('invalid login credentials') ||
          lowerMsg.contains('invalid_credentials') ||
          lowerMsg.contains('invalid grant')) {
        return 'Invalid email or password. Please check your credentials and try again.';
      }
      if (lowerMsg.contains('email not confirmed') ||
          lowerMsg.contains('email_not_confirmed')) {
        return 'Your email address has not been confirmed yet. Please check your inbox or click "Resend Confirmation?".';
      }
      if (lowerMsg.contains('user already registered') ||
          lowerMsg.contains('already exists')) {
        return 'An account with this email address already exists. Please sign in instead.';
      }
      if (lowerMsg.contains('password should be at least') ||
          lowerMsg.contains('password must be')) {
        return 'Password must be at least 6 characters long.';
      }
      return msg;
    }

    if (lowerErrorStr.contains('rate limit') ||
        lowerErrorStr.contains('rate_limit') ||
        lowerErrorStr.contains('429')) {
      return 'Email or sign-up rate limit reached. Please wait a few minutes before trying again or requesting another confirmation email.';
    }

    if (lowerErrorStr.contains('one-time token not found') ||
        lowerErrorStr.contains('token has expired') ||
        lowerErrorStr.contains('otp_expired')) {
      return 'This verification link is invalid, expired, or has already been used. Please sign in or request a new link.';
    }

    return 'Authentication failed. Please try again.';
  }

  Future<void> _handleResendConfirmation() async {
    if (_isLoading || _isResendingConfirmation) return;
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your email address to resend confirmation email.',
          ),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    if (_lastResendAt != null) {
      final elapsed = DateTime.now().difference(_lastResendAt!).inSeconds;
      if (elapsed < 60) {
        final remaining = 60 - elapsed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please wait $remaining seconds before requesting another confirmation email.',
            ),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
        return;
      }
    }

    setState(() => _isResendingConfirmation = true);

    try {
      const redirectUrl = kIsWeb ? null : 'io.supabase.pyp://reset-password';

      await supabase.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: redirectUrl,
      );

      _lastResendAt = DateTime.now();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Confirmation email sent! Please check your inbox for the link.',
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getFriendlyErrorMessage(e)),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResendingConfirmation = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter your email address to reset your password.',
          ),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      const redirectUrl = kIsWeb ? null : 'io.supabase.pyp://reset-password';

      await supabase.auth.resetPasswordForEmail(email, redirectTo: redirectUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password reset email sent! Please check your inbox for instructions.',
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getFriendlyErrorMessage(e)),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email and password are required.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    if (_isSignUp && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full name is required for registration.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        final safeRole = _selectedRolePortal == 'photographer'
            ? 'photographer'
            : 'customer';

        final res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name, 'requested_role': safeRole},
        );

        if (mounted) {
          final isConfirmed =
              res.session != null || res.user?.emailConfirmedAt != null;

          final String message;
          if (safeRole == 'photographer') {
            message = isConfirmed
                ? 'Photographer account registered! Application pending admin approval.'
                : 'Photographer registration submitted! Please check your email to confirm your account before signing in.';
          } else {
            message = isConfirmed
                ? 'Account created! Please sign in with your credentials.'
                : 'Account created! Please check your email to confirm your account before signing in.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.statusConfirmed,
            ),
          );
          setState(() => _isSignUp = false);
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getFriendlyErrorMessage(e)),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPhotographerPortal = _selectedRolePortal == 'photographer';

    final String cardTitle = _isSignUp
        ? (isPhotographerPortal
              ? 'Apply as Photographer'
              : 'Create Client Account')
        : (isPhotographerPortal ? 'Photographer Sign In' : 'Client Sign In');

    final String cardSubtitle = _isSignUp
        ? (isPhotographerPortal
              ? 'Register as a photographer and submit your portfolio for review.'
              : 'Create a client account to discover, search, and book photographers.')
        : (isPhotographerPortal
              ? 'Sign in as a photographer to manage requests, profile, and bookings.'
              : 'Sign in as a client to discover photographers and manage your bookings.');

    final String submitButtonText = _isSignUp
        ? (isPhotographerPortal
              ? 'Create Photographer Account'
              : 'Create Client Account')
        : (isPhotographerPortal
              ? 'Sign In as Photographer'
              : 'Sign In as Client');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Brand Logo Header (BoxFit.contain to preserve 1:1 original logo artwork)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 90,
                      height: 90,
                      color: AppColors.darkSurfaceVariant,
                      child: Image.asset(
                        'assets/images/pyp_logo.jpeg',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.camera_alt,
                              size: 44,
                              color: AppColors.champagneGold,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PYP',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3.0,
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'PICK YOUR PHOTOGRAPHER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.0,
                      color: AppColors.mutedSilver,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Auth Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dedicated Portal Selector (Client vs Photographer Entry)
                          const Text(
                            'PORTAL TYPE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.champagneGold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('Client Portal'),
                                  ),
                                  selected: _selectedRolePortal == 'customer',
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedRolePortal = 'customer';
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(
                                    child: Text('Photographer Portal'),
                                  ),
                                  selected:
                                      _selectedRolePortal == 'photographer',
                                  onSelected: (selected) {
                                    if (selected) {
                                      setState(() {
                                        _selectedRolePortal = 'photographer';
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Text(
                            cardTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warmIvory,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cardSubtitle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.mutedSilver,
                            ),
                          ),
                          const SizedBox(height: 20),

                          if (_isSignUp) ...[
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: Icon(
                                  Icons.person_outline,
                                  color: AppColors.mutedSilver,
                                ),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                          ],

                          TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(
                                Icons.email_outlined,
                                color: AppColors.mutedSilver,
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 16),

                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: AppColors.mutedSilver,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.mutedSilver,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            onSubmitted: (_) => _submit(),
                          ),
                          if (!_isSignUp) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed:
                                        (_isLoading || _isResendingConfirmation)
                                        ? null
                                        : _handleResendConfirmation,
                                    child: const Text(
                                      'Resend Confirmation?',
                                      style: TextStyle(
                                        color: AppColors.mutedSilver,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: _isLoading
                                        ? null
                                        : _handleForgotPassword,
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: AppColors.champagneGold,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 24),

                          _isLoading
                              ? const EditorialLoadingWidget(
                                  label: 'Authenticating...',
                                )
                              : SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _submit,
                                    child: Text(submitButtonText),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() {
                      _isSignUp = !_isSignUp;
                    }),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign In'
                          : "Don't have an account? Create Account",
                      style: const TextStyle(color: AppColors.champagneGold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reset Password Screen
class ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onPasswordResetComplete;

  const ResetPasswordScreen({super.key, required this.onPasswordResetComplete});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final password = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter and confirm your new password.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters long.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.auth.updateUser(UserAttributes(password: password));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password updated successfully! Please sign in with your new password.',
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
        await supabase.auth.signOut();
        widget.onPasswordResetComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reset password. Please try again.'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Set New Password',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warmIvory,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter a new password to secure your account.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.mutedSilver,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: AppColors.mutedSilver,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.mutedSilver,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Confirm New Password',
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: AppColors.mutedSilver,
                          ),
                        ),
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _updatePassword(),
                      ),
                      const SizedBox(height: 24),
                      _isLoading
                          ? const EditorialLoadingWidget(
                              label: 'Updating password...',
                            )
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _updatePassword,
                                child: const Text('Update Password'),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 2. Navigation Shell & Role-Based Access Controller
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Set<String> _userRoles = {'customer'};
  bool _isLoadingRoles = true;
  String? _rolesError;

  @override
  void initState() {
    super.initState();
    _fetchUserRoles();
  }

  Future<void> _fetchUserRoles() async {
    setState(() {
      _isLoadingRoles = true;
      _rolesError = null;
    });

    try {
      final res = await supabase.rpc('get_my_roles');
      if (res != null && res is List) {
        final roles = res.map((r) => r['role'].toString()).toSet();
        if (roles.isNotEmpty) {
          setState(() {
            _userRoles = roles;
            _isLoadingRoles = false;
          });
          return;
        }
      }
      setState(() {
        _userRoles = {'customer'};
        _isLoadingRoles = false;
      });
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      // Handle deleted user / stale JWT session safely by clearing local state
      if (errStr.contains('user from sub claim in jwt does not exist') ||
          errStr.contains('does not exist') ||
          errStr.contains('invalid_grant') ||
          errStr.contains('pgrst301') ||
          errStr.contains('jwt expired')) {
        await supabase.auth.signOut();
        return;
      }
      if (mounted) {
        setState(() {
          _rolesError = e.toString();
          _userRoles = {'customer'};
          _isLoadingRoles = false;
        });
      }
    }
  }

  bool get isAdmin => _userRoles.contains('admin');
  bool get isPhotographer => _userRoles.contains('photographer');

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRoles) {
      return const Scaffold(
        body: EditorialLoadingWidget(
          label: 'Verifying permissions & loading dashboard...',
        ),
      );
    }

    if (_rolesError != null && _userRoles.isEmpty) {
      return Scaffold(
        body: EditorialErrorWidget(
          errorMessage: 'Failed to verify account roles: $_rolesError',
          onRetry: _fetchUserRoles,
        ),
      );
    }

    final userEmail = supabase.auth.currentUser?.email ?? 'User';
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 720;

    // Distinct screens, screen titles, and navigation items based on user role
    final List<Widget> screens;
    final List<String> screenTitles;
    final List<NavigationRailDestination> destinations;
    final List<BottomNavigationBarItem> bottomNavItems;

    if (isPhotographer) {
      // PHOTOGRAPHER EXPERIENCE
      screens = [
        const PhotographerDashboardScreen(showAppBar: false),
        PhotographerProfileScreen(
          onProfileUpdated: _fetchUserRoles,
          showAppBar: false,
        ),
        const DiscoverScreen(),
        const BookingsScreen(showAppBar: false),
        if (isAdmin) const AdminDashboardScreen(showAppBar: false),
      ];

      screenTitles = [
        'Requests',
        'Profile',
        'Marketplace',
        'History',
        if (isAdmin) 'Governance',
      ];

      destinations = [
        const NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard, color: AppColors.champagneGold),
          label: Text('Requests'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.camera_alt_outlined),
          selectedIcon: Icon(Icons.camera_alt, color: AppColors.champagneGold),
          label: Text('Profile'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore, color: AppColors.champagneGold),
          label: Text('Marketplace'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(
            Icons.calendar_month,
            color: AppColors.champagneGold,
          ),
          label: Text('History'),
        ),
        if (isAdmin)
          const NavigationRailDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(
              Icons.admin_panel_settings,
              color: AppColors.champagneGold,
            ),
            label: Text('Admin'),
          ),
      ];

      bottomNavItems = [
        const BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard, color: AppColors.champagneGold),
          label: 'Requests',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.camera_alt_outlined),
          activeIcon: Icon(Icons.camera_alt, color: AppColors.champagneGold),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.explore_outlined),
          activeIcon: Icon(Icons.explore, color: AppColors.champagneGold),
          label: 'Marketplace',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month_outlined),
          activeIcon: Icon(
            Icons.calendar_month,
            color: AppColors.champagneGold,
          ),
          label: 'History',
        ),
        if (isAdmin)
          const BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings_outlined),
            activeIcon: Icon(
              Icons.admin_panel_settings,
              color: AppColors.champagneGold,
            ),
            label: 'Admin',
          ),
      ];
    } else {
      // CLIENT / CUSTOMER EXPERIENCE
      screens = [
        const DiscoverScreen(),
        const BookingsScreen(showAppBar: false),
        ClientProfileScreen(onRoleChanged: _fetchUserRoles, showAppBar: false),
        if (isAdmin) const AdminDashboardScreen(showAppBar: false),
      ];

      screenTitles = [
        'Marketplace',
        'Bookings',
        'Profile',
        if (isAdmin) 'Governance',
      ];

      destinations = [
        const NavigationRailDestination(
          icon: Icon(Icons.search),
          selectedIcon: Icon(Icons.search, color: AppColors.champagneGold),
          label: Text('Discover'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(
            Icons.calendar_month,
            color: AppColors.champagneGold,
          ),
          label: Text('Bookings'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person, color: AppColors.champagneGold),
          label: Text('Profile'),
        ),
        if (isAdmin)
          const NavigationRailDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(
              Icons.admin_panel_settings,
              color: AppColors.champagneGold,
            ),
            label: Text('Admin'),
          ),
      ];

      bottomNavItems = [
        const BottomNavigationBarItem(
          icon: Icon(Icons.search),
          activeIcon: Icon(Icons.search, color: AppColors.champagneGold),
          label: 'Discover',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month_outlined),
          activeIcon: Icon(
            Icons.calendar_month,
            color: AppColors.champagneGold,
          ),
          label: 'Bookings',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person, color: AppColors.champagneGold),
          label: 'Profile',
        ),
        if (isAdmin)
          const BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings_outlined),
            activeIcon: Icon(
              Icons.admin_panel_settings,
              color: AppColors.champagneGold,
            ),
            label: 'Admin',
          ),
      ];
    }

    final activeIndex = _currentIndex < screens.length ? _currentIndex : 0;
    final activeTitle = activeIndex < screenTitles.length
        ? screenTitles[activeIndex]
        : '';

    return Scaffold(
      appBar: PYPAppHeader(
        title: activeTitle,
        userRoles: _userRoles,
        userEmail: userEmail,
        onSignOut: () => supabase.auth.signOut(),
      ),
      body: isWideScreen
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: activeIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _currentIndex = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations,
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.borderDark,
                ),
                Expanded(child: screens[activeIndex]),
              ],
            )
          : IndexedStack(index: activeIndex, children: screens),
      bottomNavigationBar: isWideScreen
          ? null
          : BottomNavigationBar(
              currentIndex: activeIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              items: bottomNavItems,
            ),
    );
  }
}

/// 3. Discover Screen (Search & Filtering for Published Photographers)
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late Future<List<Map<String, dynamic>>> _photographersFuture;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategoryFilter = 'All';
  String _selectedSpecializationFilter = 'All';
  String _maxBudgetFilter = 'Any';

  static const List<String> categoryFilters = [
    'All',
    'Wedding',
    'Portrait',
    'Fashion',
    'Event',
    'Pre-wedding',
    'Commercial',
    'Travel',
  ];

  static const List<String> specializationFilters = [
    'All',
    'Candid',
    'Studio',
    'Drone',
    'Cinematic',
    'Traditional',
    'Editorial',
  ];

  static const Map<String, String> budgetFilters = {
    'Any': 'Any Budget',
    '10000': 'Up to ₹10,000',
    '25000': 'Up to ₹25,000',
    '50000': 'Up to ₹50,000',
    '100000': 'Up to ₹1,00,000',
  };

  @override
  void initState() {
    super.initState();
    _fetchPhotographers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _getPublishedPhotographers() async {
    try {
      final data = await supabase
          .from('photographer_profiles')
          .select()
          .eq('is_published', true);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  void _fetchPhotographers() {
    setState(() {
      _photographersFuture = _getPublishedPhotographers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.champagneGold,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async => _fetchPhotographers(),
        child: CustomScrollView(
          slivers: [
            // Search & Multi-criteria Filtering Header
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(color: AppColors.obsidian),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EDITORIAL MARKETPLACE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.champagneGold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Find Extraordinary Photographers',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warmIvory,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search by city, specialization, category, or photographer name...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.mutedSilver,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: AppColors.mutedSilver,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => setState(
                        () => _searchQuery = val.trim().toLowerCase(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Filter Controls Row
                    Row(
                      children: [
                        // Budget Filter Dropdown
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.darkSurfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _maxBudgetFilter,
                                isExpanded: true,
                                dropdownColor: AppColors.darkSurface,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.warmIvory,
                                ),
                                items: budgetFilters.entries.map((e) {
                                  return DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text(e.value),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _maxBudgetFilter = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Specialization Filter Dropdown
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.darkSurfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedSpecializationFilter,
                                isExpanded: true,
                                dropdownColor: AppColors.darkSurface,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.warmIvory,
                                ),
                                items: specializationFilters.map((spec) {
                                  return DropdownMenuItem<String>(
                                    value: spec,
                                    child: Text(
                                      spec == 'All' ? 'All Styles' : spec,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(
                                      () => _selectedSpecializationFilter = val,
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Category Filter Chips
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: categoryFilters.length,
                        itemBuilder: (context, index) {
                          final cat = categoryFilters[index];
                          final isSelected = _selectedCategoryFilter == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(
                                cat,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedCategoryFilter = cat;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Photographers List
            SliverFillRemaining(
              hasScrollBody: true,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _photographersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const EditorialLoadingWidget(
                      label: 'Curating published photographers...',
                    );
                  }
                  if (snapshot.hasError) {
                    return EditorialErrorWidget(
                      errorMessage:
                          'Failed to load photographers: ${snapshot.error}',
                      onRetry: _fetchPhotographers,
                    );
                  }
                  final allPhotographers = snapshot.data ?? [];

                  final filteredList = allPhotographers.where((p) {
                    final city = (p['city'] ?? '').toString().toLowerCase();
                    final cat = (p['category'] ?? '').toString().toLowerCase();
                    final name = (p['display_name'] ?? '')
                        .toString()
                        .toLowerCase();
                    final bio = (p['bio'] ?? '').toString().toLowerCase();
                    final startingPriceINR =
                        ((p['starting_price_paise'] as int?) ?? 0) / 100.0;
                    final specs = List<String>.from(
                      p['specializations'] ?? [],
                    ).map((s) => s.toLowerCase()).toList();
                    final serviceLocs = List<String>.from(
                      p['service_locations'] ?? [],
                    ).map((l) => l.toLowerCase()).toList();
                    final availNote = (p['availability_note'] ?? '')
                        .toString()
                        .toLowerCase();

                    final matchesSearch =
                        _searchQuery.isEmpty ||
                        city.contains(_searchQuery) ||
                        cat.contains(_searchQuery) ||
                        name.contains(_searchQuery) ||
                        bio.contains(_searchQuery) ||
                        specs.any((s) => s.contains(_searchQuery)) ||
                        serviceLocs.any((l) => l.contains(_searchQuery)) ||
                        availNote.contains(_searchQuery);

                    final matchesCategory =
                        _selectedCategoryFilter == 'All' ||
                        cat.contains(_selectedCategoryFilter.toLowerCase());

                    final matchesSpecialization =
                        _selectedSpecializationFilter == 'All' ||
                        specs.contains(
                          _selectedSpecializationFilter.toLowerCase(),
                        );

                    bool matchesBudget = true;
                    if (_maxBudgetFilter != 'Any') {
                      final maxLimit =
                          double.tryParse(_maxBudgetFilter) ?? 999999;
                      matchesBudget = startingPriceINR <= maxLimit;
                    }

                    return matchesSearch &&
                        matchesCategory &&
                        matchesSpecialization &&
                        matchesBudget;
                  }).toList();

                  if (filteredList.isEmpty) {
                    return EmptyStateWidget(
                      icon: Icons.camera_alt_outlined,
                      title: 'No Photographers Found',
                      message:
                          _searchQuery.isNotEmpty ||
                              _selectedCategoryFilter != 'All' ||
                              _selectedSpecializationFilter != 'All' ||
                              _maxBudgetFilter != 'Any'
                          ? 'No published photographers match your active search filters or budget limit.'
                          : 'There are currently no approved photographers available in the marketplace.',
                      actionLabel:
                          _searchQuery.isNotEmpty ||
                              _selectedCategoryFilter != 'All' ||
                              _selectedSpecializationFilter != 'All' ||
                              _maxBudgetFilter != 'Any'
                          ? 'Reset All Filters'
                          : null,
                      onAction: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedCategoryFilter = 'All';
                          _selectedSpecializationFilter = 'All';
                          _maxBudgetFilter = 'Any';
                        });
                      },
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final photo = filteredList[index];
                      return PhotographerCard(
                        photographer: photo,
                        onBookPressed: () =>
                            BookingDialog.show(context, photographer: photo),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4. Dedicated Photographer Incoming Requests Dashboard
class PhotographerDashboardScreen extends StatefulWidget {
  final bool showAppBar;

  const PhotographerDashboardScreen({super.key, this.showAppBar = true});

  @override
  State<PhotographerDashboardScreen> createState() =>
      _PhotographerDashboardScreenState();
}

class _PhotographerDashboardScreenState
    extends State<PhotographerDashboardScreen> {
  late Future<List<Map<String, dynamic>>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<List<Map<String, dynamic>>> _getPhotographerRequests() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final profile = await supabase
          .from('photographer_profiles')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (profile == null) return [];
      final photoId = profile['id'];

      final data = await supabase
          .from('bookings')
          .select('*, photographer_profiles(display_name)')
          .eq('photographer_id', photoId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  void _fetchRequests() {
    setState(() {
      _requestsFuture = _getPhotographerRequests();
    });
  }

  Future<void> _respondToBooking(
    String bookingId,
    bool accept,
    String clientName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          accept ? 'Accept Booking Request?' : 'Decline Booking Request?',
        ),
        content: Text(
          accept
              ? 'Are you sure you want to accept $clientName\'s booking request?'
              : 'Are you sure you want to decline $clientName\'s booking request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accept
                  ? AppColors.statusConfirmed
                  : AppColors.statusCancelled,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accept ? 'Accept Request' : 'Decline Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.rpc(
        'photographer_respond_booking',
        params: {'p_booking_id': bookingId, 'p_accept': accept},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Booking request accepted!'
                  : 'Booking request declined.',
            ),
            backgroundColor: accept
                ? AppColors.statusConfirmed
                : AppColors.statusCancelled,
          ),
        );
      }
      _fetchRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Incoming Booking Requests'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.mutedSilver),
                  onPressed: _fetchRequests,
                  tooltip: 'Refresh Requests',
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.champagneGold,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async => _fetchRequests(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _requestsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const EditorialLoadingWidget(
                label: 'Loading incoming booking requests...',
              );
            }
            if (snapshot.hasError) {
              return EditorialErrorWidget(
                errorMessage: 'Error loading requests: ${snapshot.error}',
                onRetry: _fetchRequests,
              );
            }

            final requests = snapshot.data ?? [];
            if (requests.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.inbox_outlined,
                title: 'No Incoming Requests',
                message:
                    'You have no booking requests at this time. Ensure your profile is approved and published to receive bookings.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final b = requests[index];
                final custName = b['customer_name'] ?? 'Client';

                return BookingCard(
                  booking: b,
                  currentUserId: currentUserId,
                  onRefreshNeeded: _fetchRequests,
                  onPayDeposit: (_) {},
                  onViewContactInfo: (_) {},
                  onPhotographerRespond: (bId, accept) =>
                      _respondToBooking(bId, accept, custName),
                  onCustomerCancel: (_) {},
                  onOpenChat: (bookingMap) =>
                      BookingChatScreen.navigateTo(context, bookingMap),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 5. Bookings Screen (Customer & Photographer Views)
class BookingsScreen extends StatefulWidget {
  final bool showAppBar;

  const BookingsScreen({super.key, this.showAppBar = true});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late Future<List<Map<String, dynamic>>> _bookingsFuture;

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  Future<List<Map<String, dynamic>>> _getUserBookings() async {
    try {
      final data = await supabase
          .from('bookings')
          .select('*, photographer_profiles(display_name)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  void _fetchBookings() {
    setState(() {
      _bookingsFuture = _getUserBookings();
    });
  }

  Future<void> _respondToBooking(String bookingId, bool accept) async {
    try {
      await supabase.rpc(
        'photographer_respond_booking',
        params: {'p_booking_id': bookingId, 'p_accept': accept},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Booking Request Accepted!'
                  : 'Booking Request Rejected.',
            ),
            backgroundColor: accept
                ? AppColors.statusConfirmed
                : AppColors.statusCancelled,
          ),
        );
      }
      _fetchBookings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    try {
      await supabase.rpc(
        'customer_cancel_booking',
        params: {'p_booking_id': bookingId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking request cancelled.'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
      _fetchBookings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cancellation failed: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  Future<void> _handleAcceptanceAndPaymentPrompt(
    Map<String, dynamic> booking,
  ) async {
    final bookingId = booking['id'].toString();
    final photoInfo = booking['photographer_profiles'] as Map<String, dynamic>?;
    final photoName = photoInfo?['display_name'] ?? 'Photographer';
    final eventType = booking['event_type'] ?? 'Session';
    final totalPaise = (booking['total_amount_paise'] as int?) ?? 100000;
    final totalINR = totalPaise / 100.0;
    final photoFeeINR = totalINR / 1.05;
    final commissionINR = totalINR - photoFeeINR;

    // Stage 1: Acceptance Prompt Modal
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Accepted!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your photographer ($photoName) has accepted your request for $eventType.',
              style: const TextStyle(color: AppColors.warmIvory, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your photographer has accepted your request. Would you like to proceed with payment?',
              style: TextStyle(
                color: AppColors.champagneGold,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Proceed to Payment'),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    // Stage 2: Payment Summary & Confirmation Modal
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proceed to Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session: $eventType with $photoName',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.warmIvory,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.darkSurfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Photographer Fee',
                          style: TextStyle(
                            color: AppColors.mutedSilver,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '₹${photoFeeINR.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.warmIvory,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Platform Service (5%)',
                          style: TextStyle(
                            color: AppColors.mutedSilver,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '₹${commissionINR.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.mutedSilver,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.borderDark, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Deposit',
                          style: TextStyle(
                            color: AppColors.warmIvory,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '₹${totalINR.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.champagneGold,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Includes photographer session fee and 5% platform service charge. Server verified.',
                style: TextStyle(
                  color: AppColors.mutedSilver,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.payment, size: 16),
            label: Text('Pay ₹${totalINR.toStringAsFixed(0)} Now'),
            onPressed: () {
              Navigator.pop(ctx);
              _startRazorpayCheckout(bookingId, eventType, totalINR);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startRazorpayCheckout(
    String bookingId,
    String eventType,
    double totalINR,
  ) async {
    final userEmail = supabase.auth.currentUser?.email ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing secure payment session...'),
        backgroundColor: AppColors.champagneGold,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final res = await supabase.functions.invoke(
        'create-razorpay-order',
        body: {'booking_id': bookingId},
      );

      if (res.status != 200 || res.data == null) {
        final errMsg = (res.data is Map)
            ? (res.data['error'] ?? 'Failed to create payment order')
            : 'Failed to create payment order';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Error: $errMsg'),
              backgroundColor: AppColors.statusCancelled,
            ),
          );
        }
        return;
      }

      final data = res.data as Map<String, dynamic>;
      if (data['error'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment Error: ${data['error']}'),
              backgroundColor: AppColors.statusCancelled,
            ),
          );
        }
        return;
      }

      final String orderId = data['order_id'];
      final int amountPaise = data['amount_paise'];
      final String keyId = data['key_id'];

      final razorpay = Razorpay();

      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
        PaymentSuccessResponse response,
      ) async {
        razorpay.clear();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment completed. Verifying transaction with server...',
            ),
            backgroundColor: AppColors.champagneGold,
            duration: Duration(seconds: 3),
          ),
        );

        try {
          final verifyRes = await supabase.functions.invoke(
            'verify-razorpay-payment',
            body: {
              'booking_id': bookingId,
              'razorpay_order_id': response.orderId ?? orderId,
              'razorpay_payment_id': response.paymentId,
              'razorpay_signature': response.signature,
            },
          );

          if (verifyRes.status == 200 &&
              verifyRes.data is Map &&
              verifyRes.data['success'] == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Payment verified! Booking confirmed & chat unlocked.',
                  ),
                  backgroundColor: AppColors.statusConfirmed,
                ),
              );
            }
          } else {
            final err = (verifyRes.data is Map)
                ? (verifyRes.data['error'] ?? 'Verification failed')
                : 'Verification failed';
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Verification Failed: $err'),
                  backgroundColor: AppColors.statusCancelled,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment verification failed: $e'),
                backgroundColor: AppColors.statusCancelled,
              ),
            );
          }
        } finally {
          _fetchBookings();
        }
      });

      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
        PaymentFailureResponse response,
      ) {
        razorpay.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Payment cancelled or failed: ${response.message ?? 'Unknown error'}',
              ),
              backgroundColor: AppColors.statusCancelled,
            ),
          );
        }
        _fetchBookings();
      });

      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
        ExternalWalletResponse response,
      ) {
        razorpay.clear();
      });

      final options = {
        'key': keyId,
        'amount': amountPaise,
        'name': 'PYP — Pick Your Photographer',
        'description': '$eventType Session Booking Deposit',
        'order_id': orderId,
        'prefill': {'email': userEmail},
        'theme': {'color': '#C6A76A'},
      };

      try {
        razorpay.open(options);
      } catch (e) {
        razorpay.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to open checkout widget: $e'),
              backgroundColor: AppColors.statusCancelled,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate payment: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  Future<void> _showContactInfo(String bookingId) async {
    try {
      final res = await supabase.rpc(
        'get_booking_photographer_contact',
        params: {'p_booking_id': bookingId},
      );

      if (res != null && res is List && res.isNotEmpty) {
        final contact = res[0];
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Photographer Contact Information'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.phone,
                      color: AppColors.champagneGold,
                    ),
                    title: const Text(
                      'Phone Number',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedSilver,
                      ),
                    ),
                    subtitle: Text(
                      contact['phone'] ?? 'N/A',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.warmIvory,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.email,
                      color: AppColors.champagneGold,
                    ),
                    title: const Text(
                      'Email Address',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedSilver,
                      ),
                    ),
                    subtitle: Text(
                      contact['email'] ?? 'N/A',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.warmIvory,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load contact info: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('My Bookings'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.mutedSilver),
                  onPressed: _fetchBookings,
                  tooltip: 'Refresh Bookings',
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        color: AppColors.champagneGold,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async => _fetchBookings(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _bookingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const EditorialLoadingWidget(
                label: 'Retrieving your bookings...',
              );
            }
            if (snapshot.hasError) {
              return EditorialErrorWidget(
                errorMessage: 'Error loading bookings: ${snapshot.error}',
                onRetry: _fetchBookings,
              );
            }
            final bookings = snapshot.data ?? [];
            if (bookings.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.calendar_today_outlined,
                title: 'No Active Bookings',
                message:
                    'Explore our curated marketplace to reserve your photo sessions.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: bookings.length,
              itemBuilder: (context, index) {
                final b = bookings[index];
                return BookingCard(
                  booking: b,
                  currentUserId: currentUserId,
                  onRefreshNeeded: _fetchBookings,
                  onPayDeposit: _handleAcceptanceAndPaymentPrompt,
                  onViewContactInfo: _showContactInfo,
                  onPhotographerRespond: _respondToBooking,
                  onCustomerCancel: _cancelBooking,
                  onOpenChat: (bookingMap) =>
                      BookingChatScreen.navigateTo(context, bookingMap),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 6. Client Profile & Account View
class ClientProfileScreen extends StatelessWidget {
  final VoidCallback onRoleChanged;
  final bool showAppBar;

  const ClientProfileScreen({
    super.key,
    required this.onRoleChanged,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final email = user?.email ?? 'Client';

    return Scaffold(
      appBar: showAppBar
          ? AppBar(title: const Text('Client Account & Settings'))
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.champagneGold,
                      child: Icon(
                        Icons.person,
                        color: AppColors.obsidian,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CLIENT ACCOUNT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.champagneGold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warmIvory,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Authenticated Marketplace Client',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedSilver,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Become a Photographer CTA Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.camera_alt,
                        color: AppColors.champagneGold,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Are you a Professional Photographer?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warmIvory,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Join PYP marketplace to showcase your portfolio, set pricing, receive booking requests, and manage sessions.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.mutedSilver,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.verified, size: 18),
                    label: const Text('Apply as Photographer'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PhotographerProfileScreen(
                            onProfileUpdated: onRoleChanged,
                            showAppBar: true,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.statusCancelled,
                  side: const BorderSide(color: AppColors.statusCancelled),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                onPressed: () => supabase.auth.signOut(),
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('test_crashlytics_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.statusCancelled,
                    side: const BorderSide(color: AppColors.statusCancelled),
                  ),
                  icon: const Icon(Icons.bug_report),
                  label: const Text('Test Crashlytics Crash (Debug Only)'),
                  onPressed: () {
                    FirebaseCrashlytics.instance.crash();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 7. Photographer Profile & Portfolio Management Screen
class PhotographerProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;
  final bool showAppBar;

  const PhotographerProfileScreen({
    super.key,
    this.onProfileUpdated,
    this.showAppBar = true,
  });

  @override
  State<PhotographerProfileScreen> createState() =>
      _PhotographerProfileScreenState();
}

class _PhotographerProfileScreenState extends State<PhotographerProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController(text: '2000');
  final _experienceController = TextEditingController(text: '3');
  final _specializationsController = TextEditingController();
  final _locationsController = TextEditingController();
  final _availabilityController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  List<String> _portfolioUrls = [];
  bool _isLoading = false;
  bool _isFetching = true;
  bool _isPublished = false;
  bool _hasExistingProfile = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _experienceController.dispose();
    _specializationsController.dispose();
    _locationsController.dispose();
    _availabilityController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profileRes = await supabase
          .from('photographer_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (profileRes != null) {
        _hasExistingProfile = true;
        _nameController.text = profileRes['display_name'] ?? '';
        _bioController.text = profileRes['bio'] ?? '';
        _cityController.text = profileRes['city'] ?? '';
        _categoryController.text = profileRes['category'] ?? '';
        final priceINR =
            ((profileRes['starting_price_paise'] as int?) ?? 100000) / 100.0;
        _priceController.text = priceINR.toStringAsFixed(0);
        _experienceController.text = (profileRes['experience_years'] ?? 3)
            .toString();
        final specs = List<String>.from(profileRes['specializations'] ?? []);
        _specializationsController.text = specs.join(', ');
        final locs = List<String>.from(profileRes['service_locations'] ?? []);
        _locationsController.text = locs.join(', ');
        _availabilityController.text = profileRes['availability_note'] ?? '';
        _isPublished = profileRes['is_published'] == true;
        _portfolioUrls = List<String>.from(profileRes['portfolio_urls'] ?? []);

        final photoId = profileRes['id'];
        final privateRes = await supabase
            .from('photographer_private_details')
            .select()
            .eq('photographer_id', photoId)
            .maybeSingle();

        if (privateRes != null) {
          _phoneController.text = privateRes['phone'] ?? '';
          _emailController.text = privateRes['email'] ?? '';
        }
      } else {
        _emailController.text = supabase.auth.currentUser?.email ?? '';
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _registerPhotographer() async {
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();
    final category = _categoryController.text.trim();
    final priceINR = double.tryParse(_priceController.text) ?? 2000.0;
    final pricePaise = (priceINR * 100).toInt();
    final experienceYears =
        int.tryParse(_experienceController.text.trim()) ?? 0;
    final specializations = _specializationsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final serviceLocations = _locationsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final availabilityNote = _availabilityController.text.trim();

    if (name.isEmpty || city.isEmpty || category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Display Name, City, and Category are required.'),
          backgroundColor: AppColors.statusCancelled,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.rpc(
        'register_as_photographer',
        params: {
          'p_display_name': name,
          'p_bio': _bioController.text.trim(),
          'p_city': city,
          'p_category': category,
          'p_starting_price_paise': pricePaise,
          'p_phone': _phoneController.text.trim(),
          'p_email': _emailController.text.trim(),
          'p_portfolio_urls': _portfolioUrls,
          'p_experience_years': experienceYears,
          'p_specializations': specializations,
          'p_service_locations': serviceLocations,
          'p_availability_note': availabilityNote.isNotEmpty
              ? availabilityNote
              : null,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile updated successfully! Pending admin approval for public discovery.',
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
      }
      widget.onProfileUpdated?.call();
      await _loadProfileData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetching) {
      return const EditorialLoadingWidget(label: 'Loading profile details...');
    }

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: const Text('Photographer Portal & Profile'))
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card Banner
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: _isPublished
                    ? AppColors.statusConfirmed.withValues(alpha: 0.12)
                    : AppColors.statusRequested.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isPublished
                      ? AppColors.statusConfirmed.withValues(alpha: 0.4)
                      : AppColors.statusRequested.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPublished ? Icons.verified : Icons.pending_actions,
                    color: _isPublished
                        ? AppColors.statusConfirmed
                        : AppColors.statusRequested,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPublished
                              ? 'APPROVED & PUBLISHED'
                              : 'PENDING MODERATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: _isPublished
                                ? AppColors.statusConfirmed
                                : AppColors.statusRequested,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isPublished
                              ? 'Your listing is active and discoverable on the PYP marketplace.'
                              : _hasExistingProfile
                              ? 'Your application is submitted and awaiting admin moderation.'
                              : 'Complete your profile details below to apply as a photographer.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.warmIvory,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'PUBLIC PROFILE DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.champagneGold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name / Brand',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: 'Bio / Style & Portfolio Overview',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityController,
                    decoration: const InputDecoration(
                      labelText: 'Primary City',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Primary Category',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Starting Price (INR ₹)',
                      prefixText: '₹ ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _experienceController,
                    decoration: const InputDecoration(
                      labelText: 'Years of Experience',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _specializationsController,
              decoration: const InputDecoration(
                labelText:
                    'Specializations (Comma-separated, e.g. Candid, Drone, Studio)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationsController,
              decoration: const InputDecoration(
                labelText:
                    'Service Locations (Comma-separated, e.g. Mumbai, Pune, Goa)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _availabilityController,
              decoration: const InputDecoration(
                labelText:
                    'Availability Note (e.g. Available weekends & peak season)',
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'PRIVATE CONTACT DETAILS (RESTRICTED TO CONFIRMED CLIENTS)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.champagneGold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (For Confirmed Clients)',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Contact Email (For Confirmed Clients)',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 28),

            // Portfolio Showcase Manager
            PortfolioManagerWidget(
              initialPortfolioUrls: _portfolioUrls,
              onPortfolioUpdated: (updatedUrls) {
                setState(() => _portfolioUrls = updatedUrls);
              },
            ),
            const SizedBox(height: 28),

            _isLoading
                ? const EditorialLoadingWidget(
                    label: 'Saving photographer profile...',
                  )
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(
                        _hasExistingProfile
                            ? 'Update Photographer Profile'
                            : 'Register as Photographer',
                      ),
                      onPressed: _registerPhotographer,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// 8. Admin Dashboard Screen (Platform Governance & Moderation)
class AdminDashboardScreen extends StatefulWidget {
  final bool showAppBar;

  const AdminDashboardScreen({super.key, this.showAppBar = true});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late Future<Map<String, dynamic>> _statsFuture;
  late Future<List<Map<String, dynamic>>> _photographersFuture;
  late Future<List<Map<String, dynamic>>> _bookingsFuture;
  late Future<List<Map<String, dynamic>>> _clientsFuture;

  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchStats() async {
    try {
      final data = await supabase.rpc('admin_get_platform_stats');
      if (data != null && data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first);
      }
    } catch (_) {}
    return {};
  }

  Future<List<Map<String, dynamic>>> _fetchPhotographers() async {
    try {
      final data = await supabase.rpc('admin_get_all_photographers');
      if (data != null && data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchBookings() async {
    try {
      final data = await supabase.rpc('admin_get_all_bookings');
      if (data != null && data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchClients() async {
    try {
      final data = await supabase.rpc('admin_get_all_clients');
      if (data != null && data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {}
    return [];
  }

  void _refreshAll() {
    setState(() {
      _statsFuture = _fetchStats();
      _photographersFuture = _fetchPhotographers();
      _bookingsFuture = _fetchBookings();
      _clientsFuture = _fetchClients();
    });
  }

  Future<void> _moderatePhotographer(
    String photoId,
    String displayName,
    String action,
  ) async {
    try {
      await supabase.rpc(
        'admin_manage_photographer_status',
        params: {'p_photographer_id': photoId, 'p_action': action},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photographer "$displayName" action "$action" completed.',
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
      }
      _refreshAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moderation action failed: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Admin Platform Governance'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.mutedSilver),
                  onPressed: _refreshAll,
                  tooltip: 'Refresh Platform Data',
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.champagneGold,
                labelColor: AppColors.champagneGold,
                unselectedLabelColor: AppColors.mutedSilver,
                tabs: const [
                  Tab(icon: Icon(Icons.verified_user), text: 'Photographers'),
                  Tab(icon: Icon(Icons.receipt_long), text: 'All Bookings'),
                  Tab(icon: Icon(Icons.people), text: 'Clients'),
                ],
              ),
            )
          : null,
      body: Column(
        children: [
          if (!widget.showAppBar)
            Container(
              color: AppColors.darkSurface,
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.champagneGold,
                labelColor: AppColors.champagneGold,
                unselectedLabelColor: AppColors.mutedSilver,
                tabs: const [
                  Tab(icon: Icon(Icons.verified_user), text: 'Photographers'),
                  Tab(icon: Icon(Icons.receipt_long), text: 'All Bookings'),
                  Tab(icon: Icon(Icons.people), text: 'Clients'),
                ],
              ),
            ),
          FutureBuilder<Map<String, dynamic>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(
                  color: AppColors.champagneGold,
                  backgroundColor: AppColors.darkSurface,
                );
              }
              if (snapshot.hasError) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  color: AppColors.statusCancelled.withValues(alpha: 0.15),
                  child: Text(
                    'Stats Error: ${snapshot.error}',
                    style: const TextStyle(
                      color: AppColors.statusCancelled,
                      fontSize: 12,
                    ),
                  ),
                );
              }

              final stats = snapshot.data ?? {};
              final totalClients = stats['total_clients'] ?? 0;
              final totalPhotos = stats['total_photographers'] ?? 0;
              final pendingPhotos = stats['pending_photographers'] ?? 0;
              final approvedPhotos = stats['approved_photographers'] ?? 0;
              final totalBookings = stats['total_bookings'] ?? 0;
              final revenuePaise = (stats['total_revenue_paise'] ?? 0) as int;
              final revenueINR = revenuePaise / 100.0;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(color: AppColors.obsidian),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatBadge('Clients', '$totalClients', Icons.people),
                      const SizedBox(width: 8),
                      _buildStatBadge(
                        'Photographers',
                        '$totalPhotos',
                        Icons.camera_alt,
                      ),
                      const SizedBox(width: 8),
                      _buildStatBadge(
                        'Pending',
                        '$pendingPhotos',
                        Icons.pending,
                        highlight: pendingPhotos > 0,
                      ),
                      const SizedBox(width: 8),
                      _buildStatBadge(
                        'Approved',
                        '$approvedPhotos',
                        Icons.check_circle,
                      ),
                      const SizedBox(width: 8),
                      _buildStatBadge(
                        'Bookings',
                        '$totalBookings',
                        Icons.calendar_month,
                      ),
                      const SizedBox(width: 8),
                      _buildStatBadge(
                        'Revenue',
                        '₹${revenueINR.toStringAsFixed(0)}',
                        Icons.payments,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPhotographersTab(),
                _buildBookingsTab(),
                _buildClientsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(
    String label,
    String value,
    IconData icon, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.statusRequested.withValues(alpha: 0.2)
            : AppColors.darkSurfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? AppColors.statusRequested : AppColors.borderDark,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlight
                ? AppColors.statusRequested
                : AppColors.champagneGold,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.mutedSilver,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warmIvory,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotographersTab() {
    return RefreshIndicator(
      color: AppColors.champagneGold,
      backgroundColor: AppColors.darkSurface,
      onRefresh: () async => _refreshAll(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _photographersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const EditorialLoadingWidget(
              label: 'Loading platform photographers...',
            );
          }
          if (snapshot.hasError) {
            return EditorialErrorWidget(
              errorMessage: 'Failed to fetch photographers: ${snapshot.error}',
              onRetry: _refreshAll,
            );
          }

          final allList = snapshot.data ?? [];

          final filtered = allList.where((p) {
            final isPub = p['out_is_published'] == true;
            if (_statusFilter == 'Pending') return !isPub;
            if (_statusFilter == 'Approved') return isPub;
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Text(
                      'STATUS FILTER: ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.mutedSilver,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 8,
                      children: ['All', 'Pending', 'Approved'].map((f) {
                        final sel = _statusFilter == f;
                        return ChoiceChip(
                          label: Text(f),
                          selected: sel,
                          onSelected: (selected) {
                            if (selected) setState(() => _statusFilter = f);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: filtered.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.camera_alt_outlined,
                        title: 'No Photographers Found',
                        message: 'No photographers match the selected status.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final photo = filtered[index];
                          final photoId = photo['out_id'].toString();
                          final name = photo['out_display_name'] ?? 'Unnamed';
                          final city = photo['out_city'] ?? 'N/A';
                          final category = photo['out_category'] ?? 'N/A';
                          final bio = photo['out_bio'] ?? '';
                          final pricePaise =
                              (photo['out_starting_price_paise'] ?? 0) as int;
                          final priceINR = pricePaise / 100.0;
                          final isPublished = photo['out_is_published'] == true;
                          final phone = photo['out_phone'] ?? 'N/A';
                          final email = photo['out_email'] ?? 'N/A';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.warmIvory,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPublished
                                              ? AppColors.statusConfirmed
                                                    .withValues(alpha: 0.15)
                                              : AppColors.statusRequested
                                                    .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isPublished
                                                ? AppColors.statusConfirmed
                                                      .withValues(alpha: 0.4)
                                                : AppColors.statusRequested
                                                      .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          isPublished ? 'APPROVED' : 'PENDING',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isPublished
                                                ? AppColors.statusConfirmed
                                                : AppColors.statusRequested,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$category • $city • ₹${priceINR.toStringAsFixed(0)} starting',
                                    style: const TextStyle(
                                      color: AppColors.champagneGold,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Contact: $email | Phone: $phone',
                                    style: const TextStyle(
                                      color: AppColors.mutedSilver,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (bio.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Bio: $bio',
                                      style: const TextStyle(
                                        color: AppColors.warmIvory,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (!isPublished)
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.statusConfirmed,
                                            foregroundColor:
                                                AppColors.warmIvory,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.check_circle,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'Approve & Publish',
                                          ),
                                          onPressed: () =>
                                              _moderatePhotographer(
                                                photoId,
                                                name,
                                                'approve',
                                              ),
                                        ),
                                      if (isPublished)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.statusCancelled,
                                            side: const BorderSide(
                                              color: AppColors.statusCancelled,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 10,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.block,
                                            size: 16,
                                          ),
                                          label: const Text('Suspend'),
                                          onPressed: () =>
                                              _moderatePhotographer(
                                                photoId,
                                                name,
                                                'suspend',
                                              ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBookingsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _bookingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const EditorialLoadingWidget(
            label: 'Loading platform bookings...',
          );
        }
        if (snapshot.hasError) {
          return EditorialErrorWidget(
            errorMessage: 'Failed to fetch bookings: ${snapshot.error}',
            onRetry: _refreshAll,
          );
        }

        final bookings = snapshot.data ?? [];

        if (bookings.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.calendar_month,
            title: 'No Platform Bookings',
            message: 'There are currently no bookings recorded on PYP.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final b = bookings[index];
            final photoName = b['out_photographer_name'] ?? 'Photographer';
            final custName = b['out_customer_name'] ?? 'Customer';
            final eventType = b['out_event_type'] ?? 'Event';
            final city = b['out_event_city'] ?? 'City';
            final date = b['out_event_date'] ?? 'Date';
            final status = (b['out_status'] ?? 'requested').toString();
            final totalPaise = (b['out_total_amount_paise'] ?? 0) as int;
            final totalINR = totalPaise / 100.0;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$eventType • $city',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.champagneGold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Customer: $custName',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warmIvory,
                            ),
                          ),
                          Text(
                            'Photographer: $photoName',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.mutedSilver,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Date: $date | Status: ${status.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warmIvoryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${totalINR.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.champagneGold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClientsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _clientsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const EditorialLoadingWidget(
            label: 'Loading registered clients...',
          );
        }
        if (snapshot.hasError) {
          return EditorialErrorWidget(
            errorMessage: 'Failed to fetch clients: ${snapshot.error}',
            onRetry: _refreshAll,
          );
        }

        final clients = snapshot.data ?? [];

        if (clients.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.people_outline,
            title: 'No Clients Registered',
            message: 'There are currently no registered clients on PYP.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: clients.length,
          itemBuilder: (context, index) {
            final c = clients[index];
            final name = c['out_full_name'] ?? 'Customer';
            final email = c['out_email'] ?? 'N/A';
            final city = c['out_city'] ?? 'Not specified';
            final bookingsCount = c['out_total_bookings'] ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.darkSurfaceVariant,
                  child: Icon(Icons.person, color: AppColors.champagneGold),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.warmIvory,
                  ),
                ),
                subtitle: Text(
                  '$email • City: $city',
                  style: const TextStyle(
                    color: AppColors.mutedSilver,
                    fontSize: 12,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: Text(
                    '$bookingsCount Bookings',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.champagneGold,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
