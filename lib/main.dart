import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'widgets/portfolio_manager_widget.dart';
import 'widgets/portfolio_viewer_widget.dart';

// Safe Local Supabase Configuration
const String supabaseUrl = 'http://127.0.0.1:54321';
const String supabaseAnonKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );
  runApp(const PYPApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class PYPApp extends StatelessWidget {
  const PYPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PYP - Pick Your Photographer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

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

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email and password are required')),
      );
      return;
    }

    if (_isSignUp && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name is required for sign up')),
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
            const SnackBar(content: Text('Sign up successful! Please sign in.')),
          );
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
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? 'PYP - Create Account' : 'PYP - Sign In'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt, size: 48, color: Colors.deepPurple),
                  const SizedBox(height: 8),
                  Text(
                    'Pick Your Photographer',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  if (_isSignUp) ...[
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 20),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submit,
                            child: Text(_isSignUp ? 'Create Account' : 'Sign In'),
                          ),
                        ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp
                        ? 'Already have an account? Sign In'
                        : 'New to PYP? Create Account'),
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

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Browse'),
      const BottomNavigationBarItem(icon: Icon(Icons.book_online), label: 'My Bookings'),
      const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Photographer Profile'),
      if (isAdmin)
        const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admin Moderation'),
    ];

    final screens = <Widget>[
      const PhotographerListScreen(),
      const BookingsScreen(),
      PhotographerProfileScreen(onProfileUpdated: _fetchUserRoles),
      if (isAdmin) const AdminModerationScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Your Photographer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.account_circle, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userEmail, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (!_isLoadingRoles)
                        Wrap(
                          spacing: 4,
                          children: _userRoles.map((role) {
                            return Chip(
                              label: Text(role.toUpperCase(), style: const TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex < screens.length ? _currentIndex : 0,
              children: screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex < navItems.length ? _currentIndex : 0,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: navItems,
      ),
    );
  }
}

class PhotographerListScreen extends StatefulWidget {
  const PhotographerListScreen({super.key});

  @override
  State<PhotographerListScreen> createState() => _PhotographerListScreenState();
}

class _PhotographerListScreenState extends State<PhotographerListScreen> {
  late Future<List<Map<String, dynamic>>> _photographersFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchPhotographers();
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
        onRefresh: () async => _fetchPhotographers(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search by city or category',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _photographersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading photographers: ${snapshot.error}'));
                  }
                  final allPhotographers = snapshot.data ?? [];
                  final photographers = allPhotographers.where((p) {
                    if (_searchQuery.isEmpty) return true;
                    final city = (p['city'] ?? '').toString().toLowerCase();
                    final cat = (p['category'] ?? '').toString().toLowerCase();
                    final name = (p['display_name'] ?? '').toString().toLowerCase();
                    return city.contains(_searchQuery) || cat.contains(_searchQuery) || name.contains(_searchQuery);
                  }).toList();

                  if (photographers.isEmpty) {
                    return const Center(child: Text('No published photographers found.'));
                  }
                  return ListView.builder(
                    itemCount: photographers.length,
                    itemBuilder: (context, index) {
                      final photo = photographers[index];
                      final startingPriceINR = (photo['starting_price_paise'] as int) / 100.0;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.camera_alt)),
                              title: Text(photo['display_name'] ?? 'Unnamed Photographer'),
                              subtitle: Text('${photo['category']} • ${photo['city']}\n${photo['bio'] ?? ''}'),
                              isThreeLine: photo['bio'] != null && photo['bio'].toString().isNotEmpty,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '₹${startingPriceINR.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const Text('Starting', style: TextStyle(fontSize: 10)),
                                ],
                              ),
                              onTap: () => _showBookingDialog(context, photo),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 12.0),
                              child: PortfolioViewerWidget(
                                portfolioUrls: List<String>.from(photo['portfolio_urls'] ?? []),
                                photographerName: photo['display_name'] ?? 'Photographer',
                              ),
                            ),
                          ],
                        ),
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

  void _showBookingDialog(BuildContext context, Map<String, dynamic> photo) {
    final cityController = TextEditingController(text: photo['city']);
    final typeController = TextEditingController(text: photo['category']);
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Book ${photo['display_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cityController,
                  decoration: const InputDecoration(labelText: 'Event City'),
                ),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(labelText: 'Event Type'),
                ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Customer Note'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Date: ${selectedDate.toIso8601String().split('T')[0]}'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: const Text('Change Date'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await supabase.rpc('create_booking_request', params: {
                    'p_photographer_id': photo['id'],
                    'p_event_date': selectedDate.toIso8601String().split('T')[0],
                    'p_event_city': cityController.text.trim(),
                    'p_event_type': typeController.text.trim(),
                    'p_customer_note': noteController.text.trim(),
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Booking request submitted!')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Booking failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}

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
      await supabase.rpc('photographer_respond_booking', params: {
        'p_booking_id': bookingId,
        'p_accept': accept,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? 'Booking Accepted!' : 'Booking Rejected.')),
        );
      }
      _fetchBookings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    }
  }

  void _showRazorpayNotice(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Razorpay Payment Mode'),
        content: Text(
          'Booking deposit amount: ₹${((booking['total_amount_paise'] as int) / 100.0).toStringAsFixed(0)}\n\n'
          'Razorpay integration is configured and ready in Edge Functions. To proceed with test/live payment, connect to your environment Razorpay API keys.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchBookings),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetchBookings(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _bookingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error loading bookings: ${snapshot.error}'));
            }
            final bookings = snapshot.data ?? [];
            if (bookings.isEmpty) {
              return const Center(child: Text('No bookings yet.'));
            }
            return ListView.builder(
              itemCount: bookings.length,
              itemBuilder: (context, index) {
                final b = bookings[index];
                final totalINR = (b['total_amount_paise'] as int) / 100.0;
                final status = b['status'].toString();
                final isCustomer = b['customer_id'] == currentUserId;
                final photographerInfo = b['photographer_profiles'] as Map<String, dynamic>?;
                final photoName = photographerInfo?['display_name'] ?? 'Photographer';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Event: ${b['event_type']}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Chip(
                              label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11)),
                              backgroundColor: _getStatusColor(status).withAlpha(38),
                            ),
                          ],
                        ),
                        Text('Photographer: $photoName'),
                        Text('City: ${b['event_city']} • Date: ${b['event_date']}'),
                        Text('Total Fee: ₹${totalINR.toStringAsFixed(0)}'),
                        if (b['customer_note'] != null && b['customer_note'].toString().isNotEmpty)
                          Text('Note: ${b['customer_note']}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            // Customer Actions
                            if (isCustomer && (status == 'accepted' || status == 'awaiting_payment'))
                              ElevatedButton.icon(
                                icon: const Icon(Icons.payment),
                                label: const Text('Pay Deposit'),
                                onPressed: () => _showRazorpayNotice(b),
                              ),
                            if (isCustomer && (status == 'requested' || status == 'accepted' || status == 'awaiting_payment'))
                              OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await supabase.rpc('customer_cancel_booking', params: {
                                      'p_booking_id': b['id'],
                                    });
                                    _fetchBookings();
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Cancellation failed: $e')),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Cancel Request'),
                              ),
                            if (status == 'confirmed' || status == 'completed')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.contact_phone),
                                label: const Text('View Contact Info'),
                                onPressed: () => _showContactInfo(b['id']),
                              ),

                            // Photographer Actions
                            if (!isCustomer && status == 'requested') ...[
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                icon: const Icon(Icons.check),
                                label: const Text('Accept Booking'),
                                onPressed: () => _respondToBooking(b['id'], true),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.close),
                                label: const Text('Reject Booking'),
                                onPressed: () => _respondToBooking(b['id'], false),
                              ),
                            ],
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'requested':
        return Colors.orange;
      case 'accepted':
      case 'awaiting_payment':
        return Colors.blue;
      case 'confirmed':
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showContactInfo(String bookingId) async {
    try {
      final res = await supabase.rpc('get_booking_photographer_contact', params: {
        'p_booking_id': bookingId,
      });

      if (res != null && res is List && res.isNotEmpty) {
        final contact = res[0];
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Photographer Contact Info'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone),
                    title: Text(contact['phone'] ?? 'N/A'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.email),
                    title: Text(contact['email'] ?? 'N/A'),
                  ),
                ],
              ),
              actions: [
                TextButton(
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
          SnackBar(content: Text('Failed to load contact info: $e')),
        );
      }
    }
  }
}

class PhotographerProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const PhotographerProfileScreen({super.key, this.onProfileUpdated});

  @override
  State<PhotographerProfileScreen> createState() => _PhotographerProfileScreenState();
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
        final priceINR = (profileRes['starting_price_paise'] as int) / 100.0;
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
        const SnackBar(content: Text('Display Name, City, and Category are required')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.rpc('register_as_photographer', params: {
        'p_display_name': name,
        'p_bio': _bioController.text.trim(),
        'p_city': city,
        'p_category': category,
        'p_starting_price_paise': pricePaise,
        'p_phone': _phoneController.text.trim(),
        'p_email': _emailController.text.trim(),
        'p_portfolio_urls': _portfolioUrls,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile submitted! Awaiting admin moderation.')),
        );
      }
      widget.onProfileUpdated?.call();
      await _loadProfileData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetching) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Photographer Profile Onboarding')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: _isPublished ? Colors.green.shade50 : Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      _isPublished ? Icons.verified : Icons.pending_actions,
                      color: _isPublished ? Colors.green : Colors.amber.shade800,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isPublished
                            ? 'Status: Published & Active on Browse List'
                            : _hasExistingProfile
                                ? 'Status: Pending Admin Moderation / Publishing'
                                : 'Status: Not Registered as Photographer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isPublished ? Colors.green.shade900 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _bioController, decoration: const InputDecoration(labelText: 'Bio / Experience', border: OutlineInputBorder()), maxLines: 2),
            const SizedBox(height: 12),
            TextField(controller: _cityController, decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _categoryController, decoration: const InputDecoration(labelText: 'Category (e.g. Wedding, Portrait)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _priceController, decoration: const InputDecoration(labelText: 'Starting Price (INR)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number (Private)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Contact Email (Private)', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            PortfolioManagerWidget(
              initialPortfolioUrls: _portfolioUrls,
              onPortfolioUpdated: (updatedUrls) {
                setState(() => _portfolioUrls = updatedUrls);
              },
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _registerPhotographer,
                      child: Text(_hasExistingProfile ? 'Update Photographer Profile' : 'Register as Photographer'),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

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

  Future<void> _moderatePhotographer(String photographerId, String name, bool approve) async {
    try {
      await supabase.rpc('admin_moderate_photographer', params: {
        'p_photographer_id': photographerId,
        'p_approve': approve,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? 'Photographer "$name" approved & published!'
                : 'Photographer "$name" rejected / kept unpublished.'),
            backgroundColor: approve ? Colors.green : Colors.orange,
          ),
        );
      }
      _fetchPending();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moderation action failed: $e'), backgroundColor: Colors.red),
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
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPending,
            tooltip: 'Refresh Pending List',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetchPending(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _pendingFuture,
          builder: (context, snapshot) {
            // Loading State
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading pending applications...'),
                  ],
                ),
              );
            }

            // Error State
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load pending list: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        onPressed: _fetchPending,
                      ),
                    ],
                  ),
                ),
              );
            }

            final pendingList = snapshot.data ?? [];

            // Empty State
            if (pendingList.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_outlined, size: 64, color: Colors.green.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No Pending Applications',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'All photographer profiles have been moderated.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Success State with Pending Profiles List
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: pendingList.length,
              itemBuilder: (context, index) {
                final photo = pendingList[index];
                final photoId = (photo['out_id'] ?? photo['id']).toString();
                final displayName = (photo['out_display_name'] ?? photo['display_name'] ?? 'Unnamed').toString();
                final city = (photo['out_city'] ?? photo['city'] ?? 'N/A').toString();
                final category = (photo['out_category'] ?? photo['category'] ?? 'N/A').toString();
                final bio = (photo['out_bio'] ?? photo['bio'] ?? '').toString();
                final pricePaise = (photo['out_starting_price_paise'] ?? photo['starting_price_paise'] ?? 0) as int;
                final priceINR = pricePaise / 100.0;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                            const Chip(
                              label: Text('PENDING', style: TextStyle(fontSize: 10, color: Colors.amber)),
                              backgroundColor: Colors.amber,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$category • $city', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.deepPurple)),
                        const SizedBox(height: 4),
                        Text('Starting Price: ₹${priceINR.toStringAsFixed(0)}'),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Bio: $bio', style: const TextStyle(fontStyle: FontStyle.italic)),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.check_circle),
                                label: const Text('Approve & Publish'),
                                onPressed: () => _moderatePhotographer(photoId, displayName, true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.cancel),
                                label: const Text('Reject'),
                                onPressed: () => _moderatePhotographer(photoId, displayName, false),
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
