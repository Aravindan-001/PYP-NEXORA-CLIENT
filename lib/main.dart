import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'theme/app_theme.dart';
import 'widgets/booking_card.dart';
import 'widgets/booking_dialog.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/photographer_card.dart';
import 'widgets/portfolio_manager_widget.dart';

// Safe Local Supabase Configuration
const String supabaseUrl = 'http://127.0.0.1:54321';
const String supabaseAnonKey =
    'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
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

  // Selected signup role: 'customer' or 'photographer' (Admin role strictly disallowed)
  String _selectedSignUpRole = 'customer';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
        // Enforce safe role selection (admin is strictly forbidden via client signup)
        final safeRole =
            _selectedSignUpRole == 'photographer' ? 'photographer' : 'customer';

        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name, 'requested_role': safeRole},
        );

        if (mounted) {
          final message = safeRole == 'photographer'
              ? 'Photographer account registered! Application pending admin approval.'
              : 'Account created! Please sign in with your credentials.';

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
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication error: $e'),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Brand Logo Header
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/pyp_logo.jpeg',
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppColors.darkSurfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: const Icon(
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
                          Text(
                            _isSignUp ? 'Create PYP Account' : 'Welcome Back',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warmIvory,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isSignUp
                                ? 'Select your account type to join the PYP platform.'
                                : 'Sign in to access your dashboard, bookings, and profile.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.mutedSilver,
                            ),
                          ),
                          const SizedBox(height: 20),

                          if (_isSignUp) ...[
                            // Role Selector Segment
                            const Text(
                              'ACCOUNT TYPE',
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
                                      child: Text('Client / Customer'),
                                    ),
                                    selected:
                                        _selectedSignUpRole == 'customer',
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(
                                          () => _selectedSignUpRole =
                                              'customer',
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Center(
                                      child: Text('Photographer'),
                                    ),
                                    selected:
                                        _selectedSignUpRole == 'photographer',
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(
                                          () => _selectedSignUpRole =
                                              'photographer',
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _selectedSignUpRole == 'photographer'
                                  ? 'Photographer accounts submit a portfolio for admin review.'
                                  : 'Client accounts can discover, search, and book photographers.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.mutedSilver,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 16),

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
                          const SizedBox(height: 24),

                          _isLoading
                              ? const EditorialLoadingWidget(
                                  label: 'Authenticating...',
                                )
                              : SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _submit,
                                    child: Text(
                                      _isSignUp ? 'Create Account' : 'Sign In',
                                    ),
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
      // Fallback role if empty
      setState(() {
        _userRoles = {'customer'};
        _isLoadingRoles = false;
      });
    } catch (e) {
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

    // Define navigation screens according to user role permissions
    final screens = <Widget>[
      const DiscoverScreen(),
      const BookingsScreen(),
      PhotographerProfileScreen(onProfileUpdated: _fetchUserRoles),
      if (isAdmin) const AdminDashboardScreen(),
    ];

    final destinations = <NavigationRailDestination>[
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
      NavigationRailDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person, color: AppColors.champagneGold),
        label: Text(isPhotographer ? 'Photographer' : 'Profile'),
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

    final bottomNavItems = <BottomNavigationBarItem>[
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
      BottomNavigationBarItem(
        icon: const Icon(Icons.person_outline),
        activeIcon: const Icon(Icons.person, color: AppColors.champagneGold),
        label: isPhotographer ? 'Photographer' : 'Profile',
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

    final activeIndex = _currentIndex < screens.length ? _currentIndex : 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/pyp_logo.jpeg',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.camera_alt,
                  color: AppColors.champagneGold,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'PYP',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: AppColors.champagneGold,
              ),
            ),
          ],
        ),
        actions: [
          // Role Badges Display
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                Text(
                  userEmail.split('@').first,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.warmIvory,
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 4,
                  children: _userRoles.map((role) {
                    final isRoleAdmin = role == 'admin';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isRoleAdmin
                            ? AppColors.champagneGold.withValues(alpha: 0.2)
                            : AppColors.darkSurfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isRoleAdmin
                              ? AppColors.champagneGold
                              : AppColors.borderDark,
                        ),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          color: isRoleAdmin
                              ? AppColors.champagneGold
                              : AppColors.mutedSilver,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.mutedSilver),
            tooltip: 'Sign Out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
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

/// 3. Discover Screen (Public Discovery for Published Photographers)
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
            // Hero Search Section
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
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warmIvory,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search Input Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search by city, category, or photographer name...',
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
                    const SizedBox(height: 16),

                    // Category Filter Chips
                    SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: categoryFilters.length,
                        itemBuilder: (context, index) {
                          final cat = categoryFilters[index];
                          final isSelected = _selectedCategoryFilter == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(cat),
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

                    final matchesSearch =
                        _searchQuery.isEmpty ||
                        city.contains(_searchQuery) ||
                        cat.contains(_searchQuery) ||
                        name.contains(_searchQuery);

                    final matchesCategory =
                        _selectedCategoryFilter == 'All' ||
                        cat.contains(_selectedCategoryFilter.toLowerCase());

                    return matchesSearch && matchesCategory;
                  }).toList();

                  if (filteredList.isEmpty) {
                    return EmptyStateWidget(
                      icon: Icons.camera_alt_outlined,
                      title: 'No Published Photographers',
                      message:
                          _searchQuery.isNotEmpty ||
                              _selectedCategoryFilter != 'All'
                          ? 'No published photographers match your search query or category filter.'
                          : 'There are currently no approved photographers available in the marketplace.',
                      actionLabel:
                          _searchQuery.isNotEmpty ||
                              _selectedCategoryFilter != 'All'
                          ? 'Reset Filters'
                          : null,
                      onAction: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _selectedCategoryFilter = 'All';
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

/// 4. Bookings Screen (Customer & Photographer Authorized Views)
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late Future<List<Map<String, dynamic>>> _bookingsFuture;
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _fetchBookings();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
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

  void _showRazorpayNotice(Map<String, dynamic> booking) {
    final totalPaise = (booking['total_amount_paise'] as int?) ?? 100000;
    final totalINR = totalPaise / 100.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Razorpay Payment Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deposit Amount: ₹${totalINR.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.champagneGold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Razorpay integration is configured in Edge Functions. Payment order verification will process deposit and advance booking to confirmed.',
              style: TextStyle(
                color: AppColors.mutedSilver,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
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
      appBar: AppBar(
        title: const Text('My Bookings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.mutedSilver),
            onPressed: _fetchBookings,
            tooltip: 'Refresh Bookings',
          ),
        ],
      ),
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
                  onPayDeposit: _showRazorpayNotice,
                  onViewContactInfo: _showContactInfo,
                  onPhotographerRespond: _respondToBooking,
                  onCustomerCancel: _cancelBooking,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 5. Photographer Profile & Portfolio Management Screen
class PhotographerProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const PhotographerProfileScreen({super.key, this.onProfileUpdated});

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
      appBar: AppBar(title: const Text('Photographer Portal & Profile')),
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
                    decoration: const InputDecoration(labelText: 'City'),
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
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Starting Price (INR ₹)',
                prefixText: '₹ ',
              ),
              keyboardType: TextInputType.number,
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

/// 6. Admin Dashboard Screen (Full Platform Governance & Moderation)
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

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
      appBar: AppBar(
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
      ),
      body: Column(
        children: [
          // Platform Statistics Summary Bar
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
                      _buildStatBadge(
                        'Clients',
                        '$totalClients',
                        Icons.people,
                      ),
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

          // Tabbed Content Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. Photographers Management & Moderation Tab
                _buildPhotographersTab(),

                // 2. All Bookings Monitor Tab
                _buildBookingsTab(),

                // 3. Registered Clients Directory Tab
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
          color: highlight
              ? AppColors.statusRequested
              : AppColors.borderDark,
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
              // Filter Chips
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
                          final isPublished =
                              photo['out_is_published'] == true;
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
            final photoName =
                b['out_photographer_name'] ?? 'Photographer';
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
