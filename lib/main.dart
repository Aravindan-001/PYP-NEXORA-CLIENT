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
const String supabaseAnonKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

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

/// Authentication state router
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

/// 1. Authentication Screen: Branded, elegant sign-in / sign-up screen
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
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registration successful! Please sign in with your credentials.',
              ),
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
              constraints: const BoxConstraints(maxWidth: 440),
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
                            _isSignUp ? 'Create Account' : 'Welcome Back',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warmIvory,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isSignUp
                                ? 'Sign up to discover and book elite photographers.'
                                : 'Sign in to manage your bookings and portfolio.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.mutedSilver,
                            ),
                          ),
                          const SizedBox(height: 24),

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

/// 7. Navigation & Responsive Layout Shell
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Set<String> _userRoles = {'customer'};
  bool _isLoadingRoles = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRoles();
  }

  Future<void> _fetchUserRoles() async {
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
    } catch (_) {}
    if (mounted) setState(() => _isLoadingRoles = false);
  }

  bool get isAdmin => _userRoles.contains('admin');

  @override
  Widget build(BuildContext context) {
    final userEmail = supabase.auth.currentUser?.email ?? 'User';
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 720;

    final screens = <Widget>[
      const PhotographerListScreen(),
      const BookingsScreen(),
      PhotographerProfileScreen(onProfileUpdated: _fetchUserRoles),
      if (isAdmin) const AdminModerationScreen(),
    ];

    // Ensure selected index is within range
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
          // User Badge Dropdown / Summary
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle,
                  size: 20,
                  color: AppColors.mutedSilver,
                ),
                const SizedBox(width: 6),
                Text(
                  userEmail.split('@').first,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.warmIvory,
                  ),
                ),
                const SizedBox(width: 8),
                if (!_isLoadingRoles)
                  Wrap(
                    spacing: 4,
                    children: _userRoles.map((role) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.darkSurfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.champagneGold,
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
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.search),
                      selectedIcon: Icon(
                        Icons.search,
                        color: AppColors.champagneGold,
                      ),
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
                      selectedIcon: Icon(
                        Icons.person,
                        color: AppColors.champagneGold,
                      ),
                      label: Text('Profile'),
                    ),
                    if (isAdmin)
                      const NavigationRailDestination(
                        icon: Icon(Icons.admin_panel_settings_outlined),
                        selectedIcon: Icon(
                          Icons.admin_panel_settings,
                          color: AppColors.champagneGold,
                        ),
                        label: Text('Moderation'),
                      ),
                  ],
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
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  activeIcon: Icon(
                    Icons.search,
                    color: AppColors.champagneGold,
                  ),
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
                  activeIcon: Icon(
                    Icons.person,
                    color: AppColors.champagneGold,
                  ),
                  label: 'Profile',
                ),
                if (isAdmin)
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    activeIcon: Icon(
                      Icons.admin_panel_settings,
                      color: AppColors.champagneGold,
                    ),
                    label: 'Moderation',
                  ),
              ],
            ),
    );
  }
}

/// 2. Discover Screen: Editorial hero, search, category filters, photographer grid
class PhotographerListScreen extends StatefulWidget {
  const PhotographerListScreen({super.key});

  @override
  State<PhotographerListScreen> createState() => _PhotographerListScreenState();
}

class _PhotographerListScreenState extends State<PhotographerListScreen> {
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

  void _fetchPhotographers() {
    setState(() {
      _photographersFuture = supabase
          .from('photographer_profiles')
          .select()
          .eq('is_published', true)
          .then((data) => List<Map<String, dynamic>>.from(data));
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
            // Editorial Hero Section
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

                    // Search Bar
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

                    // Event-Category Filters
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
                      label: 'Curating portfolio marketplace...',
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

                    // Search query filter
                    final matchesSearch =
                        _searchQuery.isEmpty ||
                        city.contains(_searchQuery) ||
                        cat.contains(_searchQuery) ||
                        name.contains(_searchQuery);

                    // Category chip filter
                    final matchesCategory =
                        _selectedCategoryFilter == 'All' ||
                        cat.contains(_selectedCategoryFilter.toLowerCase());

                    return matchesSearch && matchesCategory;
                  }).toList();

                  if (filteredList.isEmpty) {
                    return EmptyStateWidget(
                      icon: Icons.camera_alt_outlined,
                      title: 'No Photographers Found',
                      message:
                          _searchQuery.isNotEmpty ||
                              _selectedCategoryFilter != 'All'
                          ? 'No published photographers match your search query or category filter.'
                          : 'There are currently no published photographers available.',
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

/// 4. My Bookings Screen: Booking list, readable status badges, customer/photographer actions
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

  void _fetchBookings() {
    setState(() {
      _bookingsFuture = supabase
          .from('bookings')
          .select('*, photographer_profiles(display_name)')
          .order('created_at', ascending: false)
          .then((data) => List<Map<String, dynamic>>.from(data));
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
              'Razorpay integration is configured and ready in Edge Functions. To proceed with test/live payment, connect to your environment Razorpay API keys.',
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
                title: 'No Bookings Yet',
                message:
                    'Explore our curated marketplace to reserve your first photo session.',
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

/// 5. Photographer Profile Screen: Structured onboarding, portfolio management, publication status
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

        // Load private details if present
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
              'Profile saved successfully! Pending admin moderation/publishing.',
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
            content: Text('Registration failed: $e'),
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
      appBar: AppBar(title: const Text('Photographer Profile & Portfolio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
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
                              ? 'PUBLISHED & ACTIVE'
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
                              ? 'Your listing is published and visible on the Discover marketplace.'
                              : _hasExistingProfile
                              ? 'Your profile is submitted and awaiting admin moderation.'
                              : 'Complete and submit your profile details below to apply as a photographer.',
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

            // Form Title
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
                labelText: 'Bio / Experience & Style',
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

            // Private Details Title
            const Text(
              'PRIVATE CONTACT DETAILS (RESTRICTED)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.champagneGold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (For Confirmed Clients Only)',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Contact Email (For Confirmed Clients Only)',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 28),

            // Portfolio Showcase Management Section
            PortfolioManagerWidget(
              initialPortfolioUrls: _portfolioUrls,
              onPortfolioUpdated: (updatedUrls) {
                setState(() => _portfolioUrls = updatedUrls);
              },
            ),
            const SizedBox(height: 28),

            // Submit Button
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

/// 6. Admin Moderation Screen: Clean pending-application cards with approve/reject confirmation
class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  late Future<List<Map<String, dynamic>>> _pendingFuture;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  void _fetchPending() {
    setState(() {
      _pendingFuture = supabase
          .rpc('admin_get_pending_photographers')
          .then((data) => List<Map<String, dynamic>>.from(data ?? []));
    });
  }

  Future<void> _moderatePhotographer(
    String photographerId,
    String name,
    bool approve,
  ) async {
    try {
      await supabase.rpc(
        'admin_moderate_photographer',
        params: {'p_photographer_id': photographerId, 'p_approve': approve},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Photographer "$name" approved & published!'
                  : 'Photographer "$name" rejected / kept unpublished.',
            ),
            backgroundColor: approve
                ? AppColors.statusConfirmed
                : AppColors.statusRequested,
          ),
        );
      }
      _fetchPending();
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
        title: const Text('Admin Photographer Moderation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.mutedSilver),
            onPressed: _fetchPending,
            tooltip: 'Refresh Pending Applications',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.champagneGold,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async => _fetchPending(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _pendingFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const EditorialLoadingWidget(
                label: 'Fetching pending photographer applications...',
              );
            }

            if (snapshot.hasError) {
              return EditorialErrorWidget(
                errorMessage:
                    'Failed to load pending applications: ${snapshot.error}',
                onRetry: _fetchPending,
              );
            }

            final pendingList = snapshot.data ?? [];

            if (pendingList.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.verified_user_outlined,
                title: 'No Pending Applications',
                message:
                    'All photographer profile submissions have been moderated.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: pendingList.length,
              itemBuilder: (context, index) {
                final photo = pendingList[index];
                final photoId = (photo['out_id'] ?? photo['id']).toString();
                final displayName =
                    (photo['out_display_name'] ??
                            photo['display_name'] ??
                            'Unnamed')
                        .toString();
                final city = (photo['out_city'] ?? photo['city'] ?? 'N/A')
                    .toString();
                final category =
                    (photo['out_category'] ?? photo['category'] ?? 'N/A')
                        .toString();
                final bio = (photo['out_bio'] ?? photo['bio'] ?? '').toString();
                final pricePaise =
                    (photo['out_starting_price_paise'] ??
                            photo['starting_price_paise'] ??
                            0)
                        as int;
                final priceINR = pricePaise / 100.0;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
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
                                color: AppColors.statusRequested.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.statusRequested.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: const Text(
                                'PENDING',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusRequested,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$category • $city',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.champagneGold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Starting Price: ₹${priceINR.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.mutedSilver,
                            fontSize: 13,
                          ),
                        ),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Bio: $bio',
                            style: const TextStyle(
                              color: AppColors.warmIvory,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.statusConfirmed,
                                  foregroundColor: AppColors.warmIvory,
                                ),
                                icon: const Icon(Icons.check_circle, size: 16),
                                label: const Text('Approve & Publish'),
                                onPressed: () => _moderatePhotographer(
                                  photoId,
                                  displayName,
                                  true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.statusCancelled,
                                  side: const BorderSide(
                                    color: AppColors.statusCancelled,
                                  ),
                                ),
                                icon: const Icon(Icons.cancel, size: 16),
                                label: const Text('Reject'),
                                onPressed: () => _moderatePhotographer(
                                  photoId,
                                  displayName,
                                  false,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
