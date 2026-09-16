import 'dart:math';
import 'dart:ui';

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase config is not yet added in this local project.
    // The app will still run with local demo data until the project is connected.
  }

  runApp(const JBLogisticsApp());
}

class ShippingIdGenerator {
  static const int _length = 20;
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final Random _random = Random();
  static final Set<String> _usedIds = <String>{};

  static String generate() {
    String id;
    do {
      final buffer = StringBuffer();
      for (var i = 0; i < _length; i++) {
        buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
      }
      id = buffer.toString();
    } while (_usedIds.contains(id));

    _usedIds.add(id);
    return id;
  }

  static bool isValid(String value) {
    if (value.isEmpty) return false;
    final normalized = value.trim().toUpperCase();
    return normalized.length == _length &&
        RegExp(r'^[A-Z0-9]{20}$').hasMatch(normalized);
  }

  static String buildQrPayload(String shippingId) {
    final normalized = shippingId.trim().toUpperCase();
    return 'JBLOGISTICS|$normalized|VERIFIED';
  }
}

class JBLogisticsApp extends StatelessWidget {
  const JBLogisticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JB Logistics',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFFF59E0B),
          surface: const Color(0xFFF8FAFC),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum AppRole { admin, staff, customer }

class DemoAccount {
  const DemoAccount({
    required this.email,
    required this.password,
    required this.role,
    required this.name,
  });

  final String email;
  final String password;
  final AppRole role;
  final String name;
}

enum StaffAccountStatus { active, restricted, revoked }

class StaffAccount {
  const StaffAccount({
    required this.name,
    required this.email,
    required this.password,
    this.status = StaffAccountStatus.active,
  });

  final String name;
  final String email;
  final String password;
  final StaffAccountStatus status;
}

class StaffAccountRegistry {
  static final List<StaffAccount> _accounts = [
    const StaffAccount(
      name: 'Operations Staff',
      email: 'staff@jblogistics.app',
      password: 'staff123',
      status: StaffAccountStatus.active,
    ),
  ];

  static List<StaffAccount> get all => List.unmodifiable(_accounts);

  static StaffAccount? findByEmail(String email) {
    final lookup = email.trim().toLowerCase();
    for (final account in _accounts) {
      if (account.email.toLowerCase() == lookup) {
        return account;
      }
    }
    return null;
  }

  static bool authenticate(String email, String password) {
    final account = findByEmail(email);
    return account != null &&
        account.status == StaffAccountStatus.active &&
        account.password == password.trim();
  }

  static StaffAccount? createAccount({
    required String name,
    required String email,
    required String password,
  }) {
    final safeName = name.trim();
    final safeEmail = email.trim();
    final safePassword = password.trim();

    if (safeName.isEmpty || safeEmail.isEmpty || safePassword.isEmpty) {
      return null;
    }

    if (findByEmail(safeEmail) != null) {
      return null;
    }

    final account = StaffAccount(
      name: safeName,
      email: safeEmail,
      password: safePassword,
      status: StaffAccountStatus.active,
    );

    _accounts.add(account);
    return account;
  }

  static bool restrict(String email) {
    final index = _accounts.indexWhere(
      (account) => account.email.toLowerCase() == email.trim().toLowerCase(),
    );

    if (index == -1) return false;

    final current = _accounts[index];
    _accounts[index] = StaffAccount(
      name: current.name,
      email: current.email,
      password: current.password,
      status: StaffAccountStatus.restricted,
    );
    return true;
  }

  static bool revoke(String email) {
    final initialLength = _accounts.length;
    _accounts.removeWhere(
      (account) => account.email.toLowerCase() == email.trim().toLowerCase(),
    );
    return _accounts.length < initialLength;
  }
}

class ServiceOffering {
  ServiceOffering({
    required this.name,
    required this.price,
    required this.status,
    required this.icon,
  });

  String name;
  String price;
  String status;
  IconData icon;
}

enum CarrierType { bike, van, airplane }

extension CarrierTypeLabel on CarrierType {
  String get label => switch (this) {
    CarrierType.bike => 'Bike',
    CarrierType.van => 'Van',
    CarrierType.airplane => 'Airplane',
  };

  IconData get icon => switch (this) {
    CarrierType.bike => Icons.pedal_bike_rounded,
    CarrierType.van => Icons.local_shipping_rounded,
    CarrierType.airplane => Icons.flight_rounded,
  };
}

CarrierType chooseCarrier({
  required String origin,
  required String destination,
  required String weight,
  required String service,
}) {
  final weightNumber =
      double.tryParse(
        RegExp(r'\d+(?:\.\d+)?').firstMatch(weight)?.group(0) ?? '0',
      ) ??
      0;
  final route = '$origin $destination'.toLowerCase();
  final isAirRoute =
      route.contains('airport') ||
      route.contains('kumasi') ||
      service == 'Cold Chain';

  if (isAirRoute || weightNumber >= 100) return CarrierType.airplane;
  if (weightNumber <= 10 && service == 'Express Courier') {
    return CarrierType.bike;
  }
  return CarrierType.van;
}

class ServiceCatalog {
  static final List<ServiceOffering> offerings = [
    ServiceOffering(
      name: 'Local Freight',
      price: 'GHS 240',
      status: 'Active',
      icon: Icons.local_shipping_rounded,
    ),
    ServiceOffering(
      name: 'Express Courier',
      price: 'GHS 420',
      status: 'Featured',
      icon: Icons.flash_on_rounded,
    ),
    ServiceOffering(
      name: 'Cold Chain',
      price: 'GHS 610',
      status: 'Active',
      icon: Icons.ac_unit_rounded,
    ),
    ServiceOffering(
      name: 'Warehousing',
      price: 'GHS 180',
      status: 'Paused',
      icon: Icons.warehouse_rounded,
    ),
  ];

  static void add({
    required String name,
    required String price,
    required String status,
  }) {
    offerings.add(
      ServiceOffering(
        name: name,
        price: price,
        status: status,
        icon: Icons.local_shipping_rounded,
      ),
    );
  }
}

class TrackingResult {
  const TrackingResult({
    required this.trackingId,
    required this.status,
    required this.location,
    required this.eta,
    required this.route,
    required this.customer,
    required this.service,
    required this.websiteUrl,
    required this.origin,
    required this.destination,
    this.isPickup = false,
  });

  final String trackingId;
  final String status;
  final String location;
  final String eta;
  final String route;
  final String customer;
  final String service;
  final String websiteUrl;
  final String origin;
  final String destination;
  final bool isPickup;

  static const Map<String, TrackingResult> _demoData = {
    'JB-2048': TrackingResult(
      trackingId: 'JB-2048',
      status: 'In transit',
      location: 'East Legon',
      eta: '2:30 PM',
      route: 'Tema Port → Accra Central',
      customer: 'Mawuli Doe',
      service: 'Local Freight',
      websiteUrl: 'https://www.jblogistics.app/track?ref=JB-2048',
      origin: 'Tema Port',
      destination: 'Accra Central',
    ),
    'XK7T2M9B4P6Q8R1L5C3D': TrackingResult(
      trackingId: 'XK7T2M9B4P6Q8R1L5C3D',
      status: 'Awaiting pickup',
      location: 'Tema Harbour',
      eta: '9:00 AM',
      route: 'Tema Harbour → Accra Central',
      customer: 'Grace Asare',
      service: 'Express Courier',
      websiteUrl: 'https://www.jblogistics.app/track?ref=XK7T2M9B4P6Q8R1L5C3D',
      origin: 'Tema Harbour',
      destination: 'Accra Central',
      isPickup: true,
    ),
    'JB-2091': TrackingResult(
      trackingId: 'JB-2091',
      status: 'Scheduled',
      location: 'Airport Hub',
      eta: '4:00 PM',
      route: 'Kotoka → Kumasi',
      customer: 'Kwame Boateng',
      service: 'Cold Chain',
      websiteUrl: 'https://www.jblogistics.app/track?ref=JB-2091',
      origin: 'Kotoka',
      destination: 'Kumasi',
    ),
  };

  static TrackingResult fromInput(String rawId) {
    final normalized = rawId.trim().toUpperCase();
    final match =
        _demoData[normalized] ??
        _demoData[normalized.replaceAll('-', '')] ??
        _demoData[normalized.replaceAll(' ', '')];

    if (match != null) {
      return match;
    }

    return TrackingResult(
      trackingId: normalized.isEmpty ? 'ENTER-ID' : normalized,
      status: 'Pending review',
      location: 'Verification required',
      eta: 'Confirmed after scan',
      route: 'Pending route assignment',
      customer: 'Customer account',
      service: 'Requested service',
      websiteUrl: 'https://www.jblogistics.app/track?ref=$normalized',
      origin: 'Pickup point',
      destination: 'Destination pending',
    );
  }
}

class _LoginScreenState extends State<LoginScreen> {
  AppRole selectedRole = AppRole.admin;
  final emailController = TextEditingController(text: 'admin@jblogistics.app');
  final passwordController = TextEditingController(text: 'admin123');
  bool hidePassword = true;

  static const Map<AppRole, DemoAccount> demoAccounts = {
    AppRole.admin: DemoAccount(
      email: 'admin@jblogistics.app',
      password: 'admin123',
      role: AppRole.admin,
      name: 'System Admin',
    ),
    AppRole.staff: DemoAccount(
      email: 'staff@jblogistics.app',
      password: 'staff123',
      role: AppRole.staff,
      name: 'Operations Staff',
    ),
    AppRole.customer: DemoAccount(
      email: 'customer@jblogistics.app',
      password: 'customer123',
      role: AppRole.customer,
      name: 'Customer Portal',
    ),
  };

  void _applyRoleCredentials(AppRole role) {
    final account = demoAccounts[role]!;
    emailController.text = account.email;
    passwordController.text = account.password;
  }

  Future<void> _signIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final account = demoAccounts[selectedRole];

    if (account == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid role selected')));
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password')),
      );
      return;
    }

    final bool validRoleCredentials;
    if (selectedRole == AppRole.staff) {
      validRoleCredentials = StaffAccountRegistry.authenticate(email, password);
    } else {
      validRoleCredentials =
          email == account.email && password == account.password;
    }

    if (!validRoleCredentials) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid credentials for the selected role'),
        ),
      );
      return;
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } catch (_) {
      // Demo mode fallback allows the app to work without Firebase configuration.
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RoleShell(role: selectedRole)),
    );
  }

  Future<void> _signUp() async {
    final nameController = TextEditingController();
    final emailControllerForSignUp = TextEditingController();
    final passwordControllerForSignUp = TextEditingController();

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create account'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailControllerForSignUp,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordControllerForSignUp,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final email = emailControllerForSignUp.text.trim();
              final password = passwordControllerForSignUp.text.trim();

              if (name.isEmpty || email.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please complete all sign up fields'),
                  ),
                );
                return;
              }

              selectedRole = AppRole.customer;
              emailController.text = email;
              passwordController.text = password;
              Navigator.of(context).pop(true);
            },
            child: const Text('Create account'),
          ),
        ],
      ),
    );

    if (shouldCreate != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account created. You can now sign in.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: Color(0xFFF59E0B),
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'JB Logistics',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fleet control center',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in to manage routes, drivers, and delivery operations.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 22),
                        DropdownButtonFormField<AppRole>(
                          initialValue: selectedRole,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Select role',
                          ),
                          items: AppRole.values
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(
                                    role.name[0].toUpperCase() +
                                        role.name.substring(1),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              selectedRole = value;
                              _applyRoleCredentials(value);
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: hidePassword,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() {
                                hidePassword = !hidePassword;
                              }),
                              icon: Icon(
                                hidePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _signUp,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0F172A)),
                              foregroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Sign up',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Demo credentials',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 6),
                              Text('Admin: admin@jblogistics.app / admin123'),
                              Text('Staff: staff@jblogistics.app / staff123'),
                              Text(
                                'Customer: customer@jblogistics.app / customer123',
                              ),
                            ],
                          ),
                        ),
                      ],
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

class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.role});

  final AppRole role;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int selectedIndex = 0;

  List<NavigationDestination> get destinations {
    switch (widget.role) {
      case AppRole.admin:
        return const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_rounded),
            label: 'Tracking',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_rounded),
            label: 'Drivers',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_rounded),
            label: 'Admin',
          ),
        ];
      case AppRole.staff:
        return const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.route_rounded),
            label: 'Dispatch',
          ),
          NavigationDestination(icon: Icon(Icons.map_rounded), label: 'Routes'),
          NavigationDestination(icon: Icon(Icons.qr_code_rounded), label: 'QR'),
        ];
      case AppRole.customer:
        return const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_rounded),
            label: 'Track',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_rounded),
            label: 'Support',
          ),
        ];
    }
  }

  List<Widget> get screens {
    switch (widget.role) {
      case AppRole.admin:
        return const [
          DashboardScreen(),
          TrackingMapScreen(),
          DriverManagementScreen(),
          OrdersScreen(),
          AdminDashboardScreen(),
        ];
      case AppRole.staff:
        return const [
          StaffDashboardScreen(),
          StaffDispatchScreen(),
          StaffRoutesScreen(),
          DriverQrScreen(),
        ];
      case AppRole.customer:
        return const [
          CustomerHomeScreen(),
          CustomerOrdersScreen(),
          CustomerTrackingScreen(),
          CustomerSupportScreen(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: destinations,
      ),
    );
  }
}

class StaffDashboardScreen extends StatelessWidget {
  const StaffDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quickActions = [
      (
        title: 'Scan QR',
        icon: Icons.qr_code_scanner_rounded,
        screen: const StaffQrScannerScreen(),
      ),
      (
        title: 'Track by ID',
        icon: Icons.search_rounded,
        screen: const TrackByIdScreen(),
      ),
      (
        title: 'Dispatch board',
        icon: Icons.route_rounded,
        screen: const StaffDispatchScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff dashboard'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: Badge(
              isLabelVisible: AppNotificationCenter.unreadCount > 0,
              label: Text('${AppNotificationCenter.unreadCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Assigned jobs',
                    value: '12',
                    icon: Icons.assignment_rounded,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    label: 'Completed',
                    value: '8',
                    icon: Icons.check_circle_rounded,
                    color: Color(0xFF166534),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick actions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(quickActions.length, (index) {
                      final action = quickActions[index];
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: index < quickActions.length - 1 ? 12 : 0,
                          ),
                          child: Material(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => action.screen,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Icon(
                                      action.icon,
                                      color: const Color(0xFF0F172A),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      action.title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _AlertTile(
              title: 'Route 7 dispatch',
              description: 'Pickup scheduled for 9:30 AM. Confirm driver and route details.',
            ),
            const _AlertTile(
              title: 'Driver check-in',
              description:
                  'Confirm all ETAs before noon and close remaining tasks.',
            ),
          ],
        ),
      ),
    );
  }
}

class TrackByIdScreen extends StatefulWidget {
  const TrackByIdScreen({super.key});

  @override
  State<TrackByIdScreen> createState() => _TrackByIdScreenState();
}

class _TrackByIdScreenState extends State<TrackByIdScreen> {
  final controller = TextEditingController(text: 'JB-2048');
  TrackingResult? result;

  void _submit() {
    setState(() {
      result = TrackingResult.fromInput(controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeResult = result ?? TrackingResult.fromInput(controller.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Track shipment')),
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Tracking ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.confirmation_number_rounded),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Lookup shipment'),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeResult.trackingId,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Status: ${activeResult.status}',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Customer', value: activeResult.customer),
                      _InfoRow(label: 'Service', value: activeResult.service),
                      _InfoRow(label: 'Origin', value: activeResult.origin),
                      _InfoRow(
                        label: 'Destination',
                        value: activeResult.destination,
                      ),
                      _InfoRow(label: 'Route', value: activeResult.route),
                      _InfoRow(
                        label: 'Current location',
                        value: activeResult.location,
                      ),
                      _InfoRow(label: 'ETA', value: activeResult.eta),
                      const SizedBox(height: 12),
                      const Text(
                        'Website tracking link',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(activeResult.websiteUrl),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(activeResult.websiteUrl);
                          if (!await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          )) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not open the website link',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open website tracking page'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PackageLabelScreen(result: activeResult),
                          ),
                        ),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Print package label'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StaffQrScannerScreen extends StatefulWidget {
  const StaffQrScannerScreen({super.key});

  @override
  State<StaffQrScannerScreen> createState() => _StaffQrScannerScreenState();
}

class _StaffQrScannerScreenState extends State<StaffQrScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  String? scannedId;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: controller,
                onDetect: (capture) {
                  final rawValue = capture.barcodes.first.rawValue;
                  if (rawValue == null || scannedId == rawValue) return;

                  setState(() => scannedId = rawValue);

                  final result = TrackingResult.fromInput(rawValue);
                  if (!mounted) return;

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PackageLabelScreen(result: result),
                    ),
                  );
                },
              ),
            ),
            if (scannedId != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Text(
                  'Scanned: $scannedId',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PackageLabelScreen extends StatelessWidget {
  const PackageLabelScreen({super.key, required this.result});

  final TrackingResult result;

  @override
  Widget build(BuildContext context) {
    final qrData = result.trackingId;

    return Scaffold(
      appBar: AppBar(title: const Text('Package label')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text(
                      'JB Logistics',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 18),
                    bw.BarcodeWidget(
                      barcode: bw.Barcode.qrCode(),
                      data: ShippingIdGenerator.buildQrPayload(qrData),
                      width: 180,
                      height: 180,
                      drawText: false,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      result.trackingId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shipment information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(label: 'Customer', value: result.customer),
                    _InfoRow(label: 'Service', value: result.service),
                    _InfoRow(label: 'Route', value: result.route),
                    _InfoRow(label: 'Current location', value: result.location),
                    _InfoRow(label: 'Status', value: result.status),
                    _InfoRow(label: 'Website', value: result.websiteUrl),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Print tracking ID + QR'),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Print-ready package label for the shipment. ',
                              ),
                              const SizedBox(height: 14),
                              bw.BarcodeWidget(
                                barcode: bw.Barcode.qrCode(),
                                data: ShippingIdGenerator.buildQrPayload(
                                  result.trackingId,
                                ),
                                width: 180,
                                height: 180,
                                drawText: false,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                result.trackingId,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text('Customer: ${result.customer}'),
                              Text('Route: ${result.route}'),
                              Text('Status: ${result.status}'),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Tracking label sent to the print queue',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Print'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Print tracking ID + QR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StaffDispatchScreen extends StatelessWidget {
  const StaffDispatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final jobs = [
      {
        'task': 'Route 7 pickup',
        'driver': 'Kwaku Mensah',
        'time': '09:30',
        'status': 'Assigned',
        'trackingId': 'JB-2048',
      },
      {
        'task': 'Warehouse dispatch',
        'driver': 'Naa Adjei',
        'time': '11:00',
        'status': 'Ready',
        'trackingId': 'JB-2091',
      },
      {
        'task': 'Airport transfer',
        'driver': 'Kojo Boateng',
        'time': '14:10',
        'status': 'In progress',
        'trackingId': 'XK7T2M9B4P6Q8R1L5C3D',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Dispatch board')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: jobs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final job = jobs[index];
            final status = job['status'] as String;
            final statusColor = status == 'Ready'
                ? const Color(0xFF166534)
                : status == 'Assigned'
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFF59E0B);

            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final result = TrackingResult.fromInput(
                    job['trackingId'] as String,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PackageLabelScreen(result: result),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.route_rounded, color: Color(0xFF0F172A)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job['task'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              job['driver'] as String,
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Package ID: ${job['trackingId']}',
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            job['time'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class StaffRoutesScreen extends StatelessWidget {
  const StaffRoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final routes = [
      {
        'name': 'Route 7',
        'status': 'On time',
        'eta': '09:30 AM',
        'color': Color(0xFF0F172A),
      },
      {
        'name': 'Route 12',
        'status': 'Delay 12 mins',
        'eta': '10:15 AM',
        'color': Color(0xFFF59E0B),
      },
      {
        'name': 'Route 15',
        'status': 'Ready',
        'eta': '12:40 PM',
        'color': Color(0xFF166534),
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Route planner')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: routes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final route = routes[index];
            final color = route['color'] as Color;
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${route['name']} • ${route['status']}'),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.map_rounded, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              route['status'] as String,
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            route['eta'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              route['status'] as String,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class DriverQrScreen extends StatefulWidget {
  const DriverQrScreen({super.key});

  @override
  State<DriverQrScreen> createState() => _DriverQrScreenState();
}

class _DriverQrScreenState extends State<DriverQrScreen> {
  final shippingIdController = TextEditingController(
    text: 'XK7T2M9B4P6Q8R1L5C3D',
  );

  String generatedShippingId = 'XK7T2M9B4P6Q8R1L5C3D';

  void _generateNewCode() {
    final newId = ShippingIdGenerator.generate();
    setState(() {
      generatedShippingId = newId;
      shippingIdController.text = newId;
    });
  }

  void _validateCode() {
    final value = shippingIdController.text.trim();
    if (!ShippingIdGenerator.isValid(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid shipping ID. Use exactly 20 letters and numbers.',
          ),
        ),
      );
      return;
    }

    final payload = ShippingIdGenerator.buildQrPayload(value);
    final isVerified = payload.contains(value) && value.length == 20;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isVerified
              ? 'QR verified for $value'
              : 'QR payload mismatch for $value',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = ShippingIdGenerator.buildQrPayload(generatedShippingId);

    return Scaffold(
      appBar: AppBar(title: const Text('Driver QR')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Shipment QR',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: bw.BarcodeWidget(
                        barcode: bw.Barcode.qrCode(),
                        data: payload,
                        width: 180,
                        height: 180,
                        drawText: false,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      generatedShippingId,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _generateNewCode,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Generate'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _validateCode,
                            icon: const Icon(Icons.verified_rounded),
                            label: const Text('Validate'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scan / verify shipping ID',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: shippingIdController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Shipping ID',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _validateCode,
                        child: const Text('Check QR match'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.type,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String message;
  final String time;
  final String type;
  final bool isRead;
}

class AppNotificationCenter {
  static final List<AppNotificationItem> _items = [
    const AppNotificationItem(
      id: 'n1',
      title: 'Route 7 delay alert',
      message: 'Traffic congestion is affecting the 9:30 AM pickup window.',
      time: '2 mins ago',
      type: 'Alert',
    ),
    const AppNotificationItem(
      id: 'n2',
      title: 'Driver check-in pending',
      message: 'Kwaku Mensah has not checked in for the latest dispatch run.',
      time: '18 mins ago',
      type: 'Action needed',
    ),
    const AppNotificationItem(
      id: 'n3',
      title: 'New service request',
      message:
          'A priority quote request has been submitted for a cold-chain route.',
      time: '1 hour ago',
      type: 'Request',
      isRead: true,
    ),
    const AppNotificationItem(
      id: 'n4',
      title: 'Warehouse update',
      message: 'Tema hub capacity is now at 82% and needs reassignment review.',
      time: '3 hours ago',
      type: 'Update',
      isRead: true,
    ),
  ];

  static List<AppNotificationItem> get items => List.unmodifiable(_items);

  static int get unreadCount => _items.where((item) => !item.isRead).length;

  static void markRead(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _items[index] = AppNotificationItem(
      id: _items[index].id,
      title: _items[index].title,
      message: _items[index].message,
      time: _items[index].time,
      type: _items[index].type,
      isRead: true,
    );
  }

  static void dismiss(String id) {
    _items.removeWhere((item) => item.id == id);
  }

  static void add({
    required String title,
    required String message,
    required String type,
  }) {
    _items.insert(
      0,
      AppNotificationItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        message: message,
        time: 'Just now',
        type: type,
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = AppNotificationCenter.items;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No notifications right now.'),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        AppNotificationCenter.markRead(item.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Marked as read: ${item.title}'),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: item.isRead
                                    ? const Color(0xFFCBD5E1)
                                    : const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        item.type,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.message,
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      item.time,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                AppNotificationCenter.dismiss(item.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Notification dismissed'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class ServicePackage {
  const ServicePackage({
    required this.name,
    required this.price,
    required this.description,
    required this.icon,
  });

  final String name;
  final String price;
  final String description;
  final IconData icon;

  static const List<ServicePackage> catalog = [
    ServicePackage(
      name: 'Local Freight',
      price: 'GHS 240',
      description: 'Same-day local dispatch and scheduled deliveries.',
      icon: Icons.local_shipping_rounded,
    ),
    ServicePackage(
      name: 'Express Courier',
      price: 'GHS 420',
      description: 'Priority door-to-door service for urgent consignments.',
      icon: Icons.flash_on_rounded,
    ),
    ServicePackage(
      name: 'Cold Chain',
      price: 'GHS 610',
      description: 'Temperature-controlled logistics and medical handling.',
      icon: Icons.ac_unit_rounded,
    ),
    ServicePackage(
      name: 'Warehousing',
      price: 'GHS 180',
      description: 'Short-term storage, inventory handling, and dispatch.',
      icon: Icons.warehouse_rounded,
    ),
  ];
}

class ServicePricingScreen extends StatelessWidget {
  const ServicePricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Services & pricing')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: ServicePackage.catalog.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final service = ServicePackage.catalog[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(service.icon, color: const Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          service.description,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    service.price,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer portal')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF0F172A)
                          .withValues(alpha: 0.08),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF0F172A),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mawuli Doe',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Customer profile',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts_rounded),
                  title: const Text('Profile settings'),
                  subtitle: const Text(
                    'Update your account, alerts, and security preferences.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomerProfileSettingsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Welcome back, Mawuli',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Active orders',
                      value: '04',
                      icon: Icons.inventory_2_rounded,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Deliveries',
                      value: '96%',
                      icon: Icons.check_circle_rounded,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next pickup',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tema to Accra Central',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'ETA: 2:30 PM',
                      style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Services & pricing',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ServicePricingScreen(),
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ServicePackage.catalog.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final service = ServicePackage.catalog[index];
                    return Container(
                      width: 220,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(service.icon, color: const Color(0xFF0F172A)),
                          const SizedBox(height: 12),
                          Text(
                            service.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            service.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            service.price,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Quick actions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ActionTile(
                      icon: Icons.calendar_today_rounded,
                      label: 'Book appt',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AppointmentBookingScreen(),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.local_shipping_rounded,
                      label: 'Pickup',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PickupBookingScreen(),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.request_quote_rounded,
                      label: 'Quote',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QuoteRequestScreen(),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.track_changes_rounded,
                      label: 'Track',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerTrackingScreen(),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.support_agent_rounded,
                      label: 'Support',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerSupportScreen(),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.payment_rounded,
                      label: 'Payments',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PaymentGatewayScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerProfileSettingsScreen extends StatelessWidget {
  const CustomerProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = [
      ('Full name', 'Mawuli Doe'),
      ('Phone', '+233 20 123 4567'),
      ('Email', 'mawuli.doe@example.com'),
      ('Address', 'Tema Community 2'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Profile settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF0F172A)
                        .withValues(alpha: 0.08),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF0F172A),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mawuli Doe',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Premium customer',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Account details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...preferences.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                    Expanded(
                      child: Text(
                        item.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Notification preferences',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const _PreferenceSwitch(title: 'Delivery updates', value: true),
            const _PreferenceSwitch(title: 'Pickup reminders', value: true),
            const _PreferenceSwitch(title: 'Special offers', value: false),
            const _PreferenceSwitch(title: 'Security alerts', value: true),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile settings saved')),
                  );
                },
                child: const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatefulWidget {
  const _PreferenceSwitch({required this.title, required this.value});

  final String title;
  final bool value;

  @override
  State<_PreferenceSwitch> createState() => _PreferenceSwitchState();
}

class _PreferenceSwitchState extends State<_PreferenceSwitch> {
  late bool _value = widget.value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Switch(
            value: _value,
            onChanged: (value) => setState(() => _value = value),
          ),
        ],
      ),
    );
  }
}

class PaymentGatewayScreen extends StatelessWidget {
  const PaymentGatewayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final methods = [
      ('Mobile money', 'MTN MoMo', Icons.phone_android_rounded),
      (
        'Bank transfer',
        'Access Bank • **** 4821',
        Icons.account_balance_rounded,
      ),
      ('Card', 'Visa ending 1349', Icons.credit_card_rounded),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Payment gateway')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: const BoxDecoration(
                          color: Color(0xFF111827),
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Outstanding balance',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'GHS 1,280.00',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Due in 2 days',
                              style: TextStyle(
                                color: Color(0xFFFBBF24),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Choose payment method',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...methods.map(
                        (method) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A)
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  method.$3,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      method.$1,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      method.$2,
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment initiated securely'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.lock_rounded),
                  label: const Text('Pay now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppointmentBookingScreen extends StatefulWidget {
  const AppointmentBookingScreen({super.key});

  @override
  State<AppointmentBookingScreen> createState() =>
      _AppointmentBookingScreenState();
}

class _AppointmentBookingScreenState extends State<AppointmentBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final customerNameController = TextEditingController(text: 'Mawuli Doe');
  final phoneController = TextEditingController(text: '+233 20 123 4567');
  final pickupLocationController = TextEditingController(text: 'Tema Harbour');
  final destinationController = TextEditingController(text: 'Accra Central');
  final loadTypeController = TextEditingController(text: 'General cargo');
  final quantityController = TextEditingController(text: '4 cartons');
  final notesController = TextEditingController();
  String serviceType = 'Local Freight';
  DateTime selectedDate = DateTime.now().add(const Duration(days: 2));

  String get estimatedCost {
    final prices = {
      'Local Freight': 240,
      'Express Courier': 420,
      'Cold Chain': 610,
      'Warehousing': 180,
    };
    return 'GHS ${prices[serviceType] ?? 240}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final shippingId = ShippingIdGenerator.generate();
    final qrPayload = ShippingIdGenerator.buildQrPayload(shippingId);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingConfirmationScreen(
          title: 'Appointment booked',
          shippingId: shippingId,
          qrPayload: qrPayload,
          summary:
              'Appointment for $serviceType from ${pickupLocationController.text} to ${destinationController.text} • Estimated $estimatedCost',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book appointment')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _BookingField(
                  controller: customerNameController,
                  label: 'Customer name',
                  icon: Icons.person_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a customer name'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: phoneController,
                  label: 'Phone number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a phone number'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: serviceType,
                  decoration: const InputDecoration(
                    labelText: 'Service type',
                    border: OutlineInputBorder(),
                  ),
                  items: ServicePackage.catalog
                      .map(
                        (service) => DropdownMenuItem(
                          value: service.name,
                          child: Text(service.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => serviceType = value ?? serviceType),
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: pickupLocationController,
                  label: 'Pickup location',
                  icon: Icons.location_on_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter pickup location'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: destinationController,
                  label: 'Destination',
                  icon: Icons.flag_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter destination'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: loadTypeController,
                  label: 'Load type / cargo category',
                  icon: Icons.inventory_2_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter cargo category'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: quantityController,
                  label: 'Quantity / package count',
                  icon: Icons.numbers_rounded,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter quantity' : null,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 180)),
                    );
                    if (picked != null) setState(() => selectedDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Preferred date',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        ),
                        const Icon(Icons.calendar_today_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes / delivery instructions',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated price',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        estimatedCost,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Submit appointment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PickupBookingScreen extends StatefulWidget {
  const PickupBookingScreen({super.key});

  @override
  State<PickupBookingScreen> createState() => _PickupBookingScreenState();
}

class _PickupBookingScreenState extends State<PickupBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final contactNameController = TextEditingController(text: 'Grace Asare');
  final contactPhoneController = TextEditingController(
    text: '+233 54 900 9988',
  );
  final pickupAddressController = TextEditingController(
    text: 'West Hills Estate',
  );
  final destinationController = TextEditingController(text: 'Accra Central');
  final cargoTypeController = TextEditingController(text: 'General cargo');
  final weightController = TextEditingController(text: '18 kg');
  final quantityController = TextEditingController(text: '3 boxes');
  final notesController = TextEditingController();
  String pickupTime = 'Morning';
  String selectedService = 'Local Freight';

  CarrierType get selectedCarrier => chooseCarrier(
    origin: pickupAddressController.text,
    destination: destinationController.text,
    weight: weightController.text,
    service: selectedService,
  );

  String get estimatedCost {
    final prices = {
      'Local Freight': 240,
      'Express Courier': 420,
      'Cold Chain': 610,
      'Warehousing': 180,
    };
    return 'GHS ${prices[selectedService] ?? 240}';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final shippingId = ShippingIdGenerator.generate();
    final qrPayload = ShippingIdGenerator.buildQrPayload(shippingId);
    final carrier = selectedCarrier;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingConfirmationScreen(
          title: 'Pickup scheduled',
          shippingId: shippingId,
          qrPayload: qrPayload,
          summary:
              'Pickup for ${cargoTypeController.text} from ${pickupAddressController.text} to ${destinationController.text} • $selectedService • ${carrier.label} • $estimatedCost',
          carrier: carrier,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pickup booking')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _BookingField(
                  controller: contactNameController,
                  label: 'Contact person',
                  icon: Icons.person_outline,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter contact name'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: contactPhoneController,
                  label: 'Phone',
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter contact phone'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedService,
                  decoration: const InputDecoration(
                    labelText: 'Service required',
                    border: OutlineInputBorder(),
                  ),
                  items: ServicePackage.catalog
                      .map(
                        (service) => DropdownMenuItem(
                          value: service.name,
                          child: Text(service.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => selectedService = value ?? selectedService,
                  ),
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: pickupAddressController,
                  label: 'Pickup address',
                  icon: Icons.home_work_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Add pickup address'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: destinationController,
                  label: 'Delivery destination',
                  icon: Icons.flag_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Add delivery destination'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: cargoTypeController,
                  label: 'Cargo type',
                  icon: Icons.inventory_2_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Tell us cargo type'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: weightController,
                  label: 'Approximate weight',
                  icon: Icons.scale_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter package weight'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: quantityController,
                  label: 'Quantity',
                  icon: Icons.numbers_rounded,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter quantity' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: pickupTime,
                  decoration: const InputDecoration(
                    labelText: 'Pickup window',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Morning', child: Text('Morning')),
                    DropdownMenuItem(
                      value: 'Afternoon',
                      child: Text('Afternoon'),
                    ),
                    DropdownMenuItem(value: 'Evening', child: Text('Evening')),
                  ],
                  onChanged: (value) =>
                      setState(() => pickupTime = value ?? pickupTime),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Special instructions',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selectedCarrier.icon,
                        color: const Color(0xFF1D4ED8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recommended carrier: ${selectedCarrier.label}',
                          style: const TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated price',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        estimatedCost,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Request pickup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookingConfirmationScreen extends StatelessWidget {
  const BookingConfirmationScreen({
    super.key,
    required this.title,
    required this.shippingId,
    required this.summary,
    required this.qrPayload,
    this.carrier,
  });

  final String title;
  final String shippingId;
  final String summary;
  final String qrPayload;
  final CarrierType? carrier;

  @override
  Widget build(BuildContext context) {
    final isValid = ShippingIdGenerator.isValid(shippingId);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: Color(0xFF166534),
              ),
              const SizedBox(height: 12),
              Text(
                isValid ? 'Shipment confirmed' : 'Review required',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                summary,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    bw.BarcodeWidget(
                      barcode: bw.Barcode.qrCode(),
                      data: qrPayload,
                      width: 180,
                      height: 180,
                      drawText: false,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Shipping ID',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shippingId,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (carrier != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(carrier!.icon, color: const Color(0xFF1D4ED8)),
                          const SizedBox(width: 8),
                          Text(
                            'Carrier: ${carrier!.label}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const RoleShell(role: AppRole.customer),
                  ),
                  (route) => false,
                ),
                child: const Text('Back to customer dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerOrdersScreen extends StatelessWidget {
  const CustomerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = [
      {'id': 'JB-2048', 'item': 'Downtown Delivery', 'status': 'In transit'},
      {'id': 'JB-2091', 'item': 'Cold Chain Cargo', 'status': 'Scheduled'},
      {'id': 'JB-2155', 'item': 'Bulk Supplies', 'status': 'Delivered'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My orders'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ShipmentHistoryScreen()),
            ),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_rounded,
                    color: Color(0xFF0F172A),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['item'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order['id'] as String,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    order['status'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ShipmentHistoryScreen extends StatelessWidget {
  const ShipmentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = [
      {
        'id': 'JB-1892',
        'route': 'Tema Port → Accra Central',
        'service': 'Local Freight',
        'status': 'Delivered',
        'date': '12 Aug 2026',
      },
      {
        'id': 'JB-2017',
        'route': 'Airport → East Legon',
        'service': 'Express Courier',
        'status': 'In transit',
        'date': '18 Aug 2026',
      },
      {
        'id': 'JB-2130',
        'route': 'Takoradi → Kumasi',
        'service': 'Warehousing',
        'status': 'Completed',
        'date': '29 Aug 2026',
      },
      {
        'id': 'JB-2198',
        'route': 'Tema → Koforidua',
        'service': 'Cold Chain',
        'status': 'Delayed',
        'date': '05 Sep 2026',
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Shipment history')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: history.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final shipment = history[index];
            final status = shipment['status'] as String;
            final color = switch (status) {
              'Delivered' => const Color(0xFF166534),
              'In transit' => const Color(0xFF1D4ED8),
              'Completed' => const Color(0xFF0F172A),
              _ => const Color(0xFFF59E0B),
            };

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        shipment['id'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    shipment['route'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Service: ${shipment['service']} • ${shipment['date']}',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class CustomerTrackingScreen extends StatefulWidget {
  const CustomerTrackingScreen({super.key});

  @override
  State<CustomerTrackingScreen> createState() => _CustomerTrackingScreenState();
}

class _CustomerTrackingScreenState extends State<CustomerTrackingScreen> {
  final trackingIdController = TextEditingController(text: 'JB-2048');
  TrackingResult? result;

  void _lookup() {
    setState(() {
      result = TrackingResult.fromInput(trackingIdController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeResult =
        result ?? TrackingResult.fromInput(trackingIdController.text);
    final isPickup =
        activeResult.isPickup ||
        activeResult.status.toLowerCase().contains('pickup');
    final statusColor = isPickup
        ? const Color(0xFF1D4ED8)
        : const Color(0xFF166534);
    final milestones = [
      _TrackingMilestone(
        title: 'Shipment created',
        subtitle: 'Order confirmed at ${activeResult.origin}',
        isDone: true,
      ),
      _TrackingMilestone(
        title: 'In transit',
        subtitle: 'Currently at ${activeResult.location}',
        isDone: true,
      ),
      _TrackingMilestone(
        title: 'Out for delivery',
        subtitle: 'Destination: ${activeResult.destination}',
        isDone: false,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Track shipment')),
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.95, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextField(
                  controller: trackingIdController,
                  decoration: const InputDecoration(
                    labelText: 'Paste tracking ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _lookup(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _lookup,
                    child: const Text('Track order'),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140F172A),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Shipment overview',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  activeResult.trackingId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isPickup)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Pickup route',
                                style: TextStyle(
                                  color: Color(0xFF1D4ED8),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isPickup
                                    ? Icons.local_shipping_rounded
                                    : Icons.check_circle_rounded,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Current status',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    activeResult.status,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _InfoRow(label: 'Origin', value: activeResult.origin),
                      _InfoRow(
                        label: 'Current location',
                        value: activeResult.location,
                      ),
                      _InfoRow(
                        label: 'Destination',
                        value: activeResult.destination,
                      ),
                      _InfoRow(label: 'ETA', value: activeResult.eta),
                      _InfoRow(label: 'Route', value: activeResult.route),
                      const SizedBox(height: 16),
                      const Text(
                        'Delivery progress',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      ...milestones.map(
                        (milestone) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _TrackingMilestoneRow(milestone: milestone),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Website tracking URL',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(activeResult.websiteUrl),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(activeResult.websiteUrl);
                          if (!await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          )) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Unable to open tracking website',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open website'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      _MapLegend(label: 'Pickup', color: Color(0xFF0F172A)),
                      _MapLegend(label: 'Current', color: Color(0xFF22C55E)),
                      _MapLegend(
                        label: 'Destination',
                        color: Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedShipmentMap(
                  origin: activeResult.origin,
                  currentLocation: activeResult.location,
                  destination: activeResult.destination,
                  isPickup: isPickup,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingMilestone {
  const _TrackingMilestone({
    required this.title,
    required this.subtitle,
    required this.isDone,
  });

  final String title;
  final String subtitle;
  final bool isDone;
}

class _TrackingMilestoneRow extends StatelessWidget {
  const _TrackingMilestoneRow({required this.milestone});

  final _TrackingMilestone milestone;

  @override
  Widget build(BuildContext context) {
    final color = milestone.isDone
        ? const Color(0xFF16A34A)
        : const Color(0xFFCBD5E1);

    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            Container(
              width: 2,
              height: 18,
              color: milestone.isDone
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFFCBD5E1),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                milestone.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: milestone.isDone
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                milestone.subtitle,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AnimatedShipmentMap extends StatefulWidget {
  const AnimatedShipmentMap({
    super.key,
    required this.origin,
    required this.currentLocation,
    required this.destination,
    required this.isPickup,
  });

  final String origin;
  final String currentLocation;
  final String destination;
  final bool isPickup;

  @override
  State<AnimatedShipmentMap> createState() => _AnimatedShipmentMapState();
}

class _AnimatedShipmentMapState extends State<AnimatedShipmentMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeInOutCubic.transform(_controller.value);
        final x = lerpDouble(40, 260, progress)!;
        final y = lerpDouble(210, 90, progress)!;

        return Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFFDCFCE7), Color(0xFFE0F2FE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              const _RoadPattern(),
              Positioned(
                top: 60,
                left: 50,
                child: _MapMarker(
                  label: widget.origin,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Positioned(
                bottom: 74,
                right: 84,
                child: _MapMarker(
                  label: widget.currentLocation,
                  color: const Color(0xFF22C55E),
                ),
              ),
              Positioned(
                top: 138,
                right: 56,
                child: _MapMarker(
                  label: widget.destination,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              if (widget.isPickup)
                Positioned(
                  left: x,
                  top: y,
                  child: Transform.rotate(
                    angle: 0.4,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x400F172A),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.pedal_bike_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  left: x,
                  top: y,
                  child: Transform.rotate(
                    angle: 0.3,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class CustomerSupportScreen extends StatelessWidget {
  const CustomerSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support center')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _InfoCard(
              title: 'Help desk',
              items: [
                _InfoRow(label: 'Phone', value: '+233 20 123 4567'),
                _InfoRow(label: 'Email', value: 'support@jblogistics.app'),
                _InfoRow(label: 'Live chat', value: 'Available 24/7'),
              ],
            ),
            const SizedBox(height: 18),
            _AlertTile(
              title: 'Delivery issue',
              description: 'We are reviewing route 7 and will update you soon.',
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: const EdgeInsets.all(18),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              leading: const Icon(Icons.request_quote_rounded),
              title: const Text('Request a quote'),
              subtitle: const Text('Get pricing for a service or shipment.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuoteRequestScreen()),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.all(18),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              leading: const Icon(Icons.mail_outline_rounded),
              title: const Text('Send inquiry'),
              subtitle: const Text(
                'Ask a question or submit a support request.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactInquiryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuoteRequestScreen extends StatefulWidget {
  const QuoteRequestScreen({super.key});

  @override
  State<QuoteRequestScreen> createState() => _QuoteRequestScreenState();
}

class _QuoteRequestScreenState extends State<QuoteRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: 'Mawuli Doe');
  final emailController = TextEditingController(text: 'mawuli@example.com');
  final phoneController = TextEditingController(text: '+233 20 556 8899');
  final routeController = TextEditingController(text: 'Tema → Accra Central');
  final cargoController = TextEditingController(text: 'General cargo');
  final notesController = TextEditingController();
  String selectedService = 'Local Freight';
  String urgency = 'Standard';

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final quoteId = 'Q-${ShippingIdGenerator.generate().substring(0, 8)}';
    final estimated = {
      'Local Freight': 'GHS 240',
      'Express Courier': 'GHS 420',
      'Cold Chain': 'GHS 610',
      'Warehousing': 'GHS 180',
    }[selectedService];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuoteRequestConfirmationScreen(
          quoteId: quoteId,
          service: selectedService,
          estimatedPrice: estimated ?? 'GHS 240',
          route: routeController.text,
          urgency: urgency,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request quote')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _BookingField(
                  controller: nameController,
                  label: 'Full name',
                  icon: Icons.person_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: emailController,
                  label: 'Email address',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: phoneController,
                  label: 'Phone number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a phone number'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedService,
                  decoration: const InputDecoration(
                    labelText: 'Service type',
                    border: OutlineInputBorder(),
                  ),
                  items: ServicePackage.catalog
                      .map(
                        (service) => DropdownMenuItem(
                          value: service.name,
                          child: Text(service.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => selectedService = value ?? selectedService,
                  ),
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: routeController,
                  label: 'Route / pickup to destination',
                  icon: Icons.map_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the route'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: cargoController,
                  label: 'Cargo details',
                  icon: Icons.inventory_2_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Describe the cargo'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: urgency,
                  decoration: const InputDecoration(
                    labelText: 'Urgency',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Standard',
                      child: Text('Standard'),
                    ),
                    DropdownMenuItem(
                      value: 'Priority',
                      child: Text('Priority'),
                    ),
                    DropdownMenuItem(
                      value: 'Emergency',
                      child: Text('Emergency'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => urgency = value ?? urgency),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Additional requirements',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated rate',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        {
                              'Local Freight': 'GHS 240',
                              'Express Courier': 'GHS 420',
                              'Cold Chain': 'GHS 610',
                              'Warehousing': 'GHS 180',
                            }[selectedService] ??
                            'GHS 240',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Submit quote request'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuoteRequestConfirmationScreen extends StatelessWidget {
  const QuoteRequestConfirmationScreen({
    super.key,
    required this.quoteId,
    required this.service,
    required this.estimatedPrice,
    required this.route,
    required this.urgency,
  });

  final String quoteId;
  final String service;
  final String estimatedPrice;
  final String route;
  final String urgency;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quote submitted')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 68,
                color: Color(0xFF166534),
              ),
              const SizedBox(height: 16),
              const Text(
                'Quote request received',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Reference: $quoteId',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Service: $service'),
                    const SizedBox(height: 8),
                    Text('Route: $route'),
                    const SizedBox(height: 8),
                    Text('Priority: $urgency'),
                    const SizedBox(height: 8),
                    Text('Estimated price: $estimatedPrice'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const RoleShell(role: AppRole.customer),
                  ),
                  (route) => false,
                ),
                child: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContactInquiryScreen extends StatefulWidget {
  const ContactInquiryScreen({super.key});

  @override
  State<ContactInquiryScreen> createState() => _ContactInquiryScreenState();
}

class _ContactInquiryScreenState extends State<ContactInquiryScreen> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: 'Mawuli Doe');
  final emailController = TextEditingController(text: 'mawuli@example.com');
  final titleController = TextEditingController(text: 'Shipment delay inquiry');
  final messageController = TextEditingController(
    text: 'I would like to know the latest update on my delayed shipment and expected ETA.',
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inquiry sent'),
        content: const Text(
          'Our support team will reply within 1 business hour.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact & inquiry')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _BookingField(
                  controller: nameController,
                  label: 'Name',
                  icon: Icons.person_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: emailController,
                  label: 'Email',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 12),
                _BookingField(
                  controller: titleController,
                  label: 'Subject',
                  icon: Icons.subject_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a subject'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: messageController,
                  maxLines: 7,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your message'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Send inquiry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key});

  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  void _editService(ServiceOffering service) {
    final priceController = TextEditingController(text: service.price);
    var status = service.status;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${service.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Featured', child: Text('Featured')),
                  DropdownMenuItem(value: 'Paused', child: Text('Paused')),
                ],
                onChanged: (value) =>
                    setDialogState(() => status = value ?? status),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  service.price = priceController.text.trim().isEmpty
                      ? service.price
                      : priceController.text.trim();
                  service.status = status;
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${service.name} updated')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _addService() {
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: 'GHS 250');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Service name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(
                labelText: 'Price',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              setState(() {
                ServiceCatalog.add(
                  name: name,
                  price: priceController.text.trim(),
                  status: 'Active',
                );
              });
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$name added to the catalog')),
              );
            },
            child: const Text('Add service'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = ServiceCatalog.offerings;

    return Scaffold(
      appBar: AppBar(title: const Text('Service management')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: services.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final service = services[index];
            final status = service.status;
            final color = status == 'Paused'
                ? const Color(0xFFF59E0B)
                : const Color(0xFF166534);

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(service.icon, color: const Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          service.price,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      IconButton(
                        tooltip: 'Edit service',
                        onPressed: () => _editService(service),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addService,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add service'),
      ),
    );
  }
}

class _BookingField extends StatelessWidget {
  const _BookingField({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 130,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF0F172A), size: 30),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: Badge(
              isLabelVisible: AppNotificationCenter.unreadCount > 0,
              label: Text('${AppNotificationCenter.unreadCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Search is available in the operations workspace.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Today\'s summary',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Expanded(
                    child: _MetricCard(
                      label: 'Active loads',
                      value: '128',
                      icon: Icons.local_shipping_rounded,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'On-time',
                      value: '96%',
                      icon: Icons.check_circle_rounded,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Fleet availability',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '12 vehicles',
                          style: TextStyle(
                            color: Color(0xFFFBBF24),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '87%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(
                        value: 0.87,
                        minHeight: 10,
                        backgroundColor: Color(0xFF334155),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Recent shipments',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              ...[
                _ShipmentCard(
                  title: 'Downtown Delivery',
                  route: 'Tema to Accra Central',
                  status: 'In transit',
                  amount: 'GHS 1,280',
                  accent: const Color(0xFF22C55E),
                ),
                _ShipmentCard(
                  title: 'Cold Chain Cargo',
                  route: 'Airport to Kumasi',
                  status: 'Loading',
                  amount: 'GHS 2,740',
                  accent: const Color(0xFF3B82F6),
                ),
                _ShipmentCard(
                  title: 'Bulk Supplies',
                  route: 'Takoradi to Tema',
                  status: 'Delayed',
                  amount: 'GHS 980',
                  accent: const Color(0xFFF59E0B),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TrackingMapScreen extends StatelessWidget {
  const TrackingMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shipment Tracking')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                height: 520,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFDCFCE7),
                      Color(0xFFDBEAFE),
                      Color(0xFFE2E8F0),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    _RoadPattern(),
                    Positioned(
                      top: 100,
                      left: 70,
                      child: _MapMarker(
                        label: 'Depot',
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Positioned(
                      top: 180,
                      right: 80,
                      child: _MapMarker(
                        label: 'Stop 2',
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                    Positioned(
                      bottom: 104,
                      left: 130,
                      child: _MapMarker(
                        label: 'Stop 3',
                        color: const Color(0xFF22C55E),
                      ),
                    ),
                    Positioned(
                      bottom: 136,
                      right: 110,
                      child: _MapMarker(
                        label: 'Driver',
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 20,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.directions_car_rounded,
                              color: Color(0xFF0F172A),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TRK-104',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '26 mins away • Tema Central',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Live',
                              style: TextStyle(
                                color: Color(0xFF22C55E),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverManagementScreen extends StatelessWidget {
  const DriverManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final drivers = [
      _DriverProfile(
        name: 'Kwaku Mensah',
        route: 'Accra • Tema',
        status: 'On route',
        score: '4.9',
      ),
      _DriverProfile(
        name: 'Naa Adjei',
        route: 'Kumasi • Takoradi',
        status: 'Break',
        score: '4.8',
      ),
      _DriverProfile(
        name: 'Kojo Boateng',
        route: 'Airport • East Legon',
        status: 'Available',
        score: '4.9',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Management'),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Add driver'),
                  content: const Text(
                    'This is a demo action. A new driver can be assigned from the operations backend.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: drivers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final driver = drivers[index];
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(driver.name),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Route: ${driver.route}'),
                          const SizedBox(height: 6),
                          Text('Status: ${driver.status}'),
                          const SizedBox(height: 6),
                          Text('Rating: ${driver.score}/5'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFF0F172A)
                            .withValues(alpha: 0.08),
                        child: Text(
                          driver.name.substring(0, 1),
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              driver.route,
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    driver.status,
                                    style: const TextStyle(
                                      color: Color(0xFF166534),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFFBBF24),
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(driver.score),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = [
      _OrderItem(
        orderId: 'JB-2048',
        name: 'Downtown Delivery',
        status: 'Ready',
        time: '2:30 PM',
      ),
      _OrderItem(
        orderId: 'JB-2091',
        name: 'Cold Chain Cargo',
        status: 'Assigned',
        time: '4:00 PM',
      ),
      _OrderItem(
        orderId: 'JB-2155',
        name: 'Bulk Supplies',
        status: 'Delayed',
        time: '6:15 PM',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = orders[index];
            return InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrderDetailScreen(order: order),
                ),
              ),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.orderId,
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          order.time,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            order.status,
                            style: const TextStyle(
                              color: Color(0xFF1D4ED8),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
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
        ),
      ),
    );
  }
}

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.order});

  final _OrderItem order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(order.orderId)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.name,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Status: ${order.status} • ${order.time}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
              ),
              const SizedBox(height: 20),
              _InfoCard(
                title: 'Shipment details',
                items: [
                  _InfoRow(label: 'Origin', value: 'Tema Port'),
                  _InfoRow(label: 'Destination', value: 'Accra Central'),
                  _InfoRow(label: 'Driver', value: 'Kwaku Mensah'),
                  _InfoRow(label: 'Load type', value: 'General cargo'),
                ],
              ),
              const SizedBox(height: 16),
              _InfoCard(
                title: 'Route progress',
                items: [
                  _InfoRow(label: 'Departure', value: '08:15 AM'),
                  _InfoRow(label: 'Current Stop', value: 'East Legon'),
                  _InfoRow(label: 'ETA', value: '2:30 PM'),
                  _InfoRow(label: 'Revenue', value: 'GHS 1,280'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StaffAccountManagementScreen extends StatefulWidget {
  const StaffAccountManagementScreen({super.key});

  @override
  State<StaffAccountManagementScreen> createState() =>
      _StaffAccountManagementScreenState();
}

class _StaffAccountManagementScreenState
    extends State<StaffAccountManagementScreen> {
  String _statusLabel(StaffAccountStatus status) => switch (status) {
    StaffAccountStatus.active => 'Active',
    StaffAccountStatus.restricted => 'Restricted',
    StaffAccountStatus.revoked => 'Revoked',
  };

  Color _statusColor(StaffAccountStatus status) => switch (status) {
    StaffAccountStatus.active => const Color(0xFF166534),
    StaffAccountStatus.restricted => const Color(0xFFF59E0B),
    StaffAccountStatus.revoked => const Color(0xFFB91C1C),
  };

  void _changeAccount(StaffAccount account, {required bool revoke}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${revoke ? 'Revoke' : 'Restrict'} staff account?'),
        content: Text(
          '${account.name} will ${revoke ? 'lose access permanently' : 'be unable to sign in'} until an admin restores access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final changed = revoke
                  ? StaffAccountRegistry.revoke(account.email)
                  : StaffAccountRegistry.restrict(account.email);
              Navigator.of(context).pop();
              if (!changed) return;
              setState(() {});
              final actionLabel = revoke ? 'revoked' : 'restricted';
              AppNotificationCenter.add(
                title: 'Staff account $actionLabel',
                message: '${account.name} no longer has active staff access.',
                type: 'Admin action',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${account.name} account $actionLabel')),
              );
            },
            child: Text(revoke ? 'Revoke account' : 'Restrict account'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = StaffAccountRegistry.all;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff accounts')),
      body: SafeArea(
        child: accounts.isEmpty
            ? const Center(child: Text('No active staff accounts'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: accounts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  final color = _statusColor(account.status);
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.12),
                              child: Text(
                                account.name.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    account.email,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _statusLabel(account.status),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (account.status == StaffAccountStatus.active) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _changeAccount(account, revoke: false),
                                icon: const Icon(
                                  Icons.pause_circle_outline_rounded,
                                ),
                                label: const Text('Restrict'),
                              ),
                              const SizedBox(width: 10),
                              TextButton.icon(
                                onPressed: () =>
                                    _changeAccount(account, revoke: true),
                                icon: const Icon(Icons.person_remove_rounded),
                                label: const Text('Revoke'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: Badge(
              isLabelVisible: AppNotificationCenter.unreadCount > 0,
              label: Text('${AppNotificationCenter.unreadCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Revenue',
                      value: 'GHS 64.2K',
                      icon: Icons.attach_money_rounded,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'Incidents',
                      value: '03',
                      icon: Icons.warning_amber_rounded,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoCard(
                title: 'Operations snapshot',
                items: [
                  _InfoRow(label: 'Fleet size', value: '12 active vehicles'),
                  _InfoRow(label: 'Driver attendance', value: '92%'),
                  _InfoRow(label: 'Average fuel cost', value: 'GHS 1,240/day'),
                  _InfoRow(label: 'Compliance', value: '98% complete'),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Operations tools',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.miscellaneous_services_rounded),
                      title: const Text('Manage services'),
                      subtitle: const Text(
                        'Update pricing, add packages, and control visibility.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ServiceManagementScreen(),
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: const Text('Create staff account'),
                      subtitle: const Text(
                        'Add a new staff user login for dispatch and scanning tasks.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        final nameController = TextEditingController();
                        final emailController = TextEditingController();
                        final passwordController = TextEditingController();

                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Create staff account'),
                            content: SizedBox(
                              width: 420,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Full name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: emailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: passwordController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  StaffAccountRegistry.createAccount(
                                    name: nameController.text,
                                    email: emailController.text,
                                    password: passwordController.text,
                                  );
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Staff account created successfully',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Save account'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.manage_accounts_rounded),
                      title: const Text('Manage staff accounts'),
                      subtitle: const Text(
                        'Review staff access and revoke terminated accounts.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StaffAccountManagementScreen(),
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.print_rounded),
                      title: const Text('Print shipment logs'),
                      subtitle: const Text(
                        'Review today’s active shipments and print a dispatch log.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        final logs = [
                          'OUT-1041 • Tema Harbour • In transit',
                          'OUT-1028 • Accra Central • Delivered',
                          'OUT-1092 • Kotoka • Scheduled',
                          'OUT-1110 • East Legon • Awaiting pickup',
                        ];

                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Shipment logs'),
                            content: SizedBox(
                              width: 360,
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: logs.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, index) => Row(
                                  children: [
                                    const Icon(
                                      Icons.local_shipping_rounded,
                                      size: 18,
                                      color: Color(0xFF0F172A),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(logs[index])),
                                  ],
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Shipment log sent to print queue',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('Print'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Management alerts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...[
                _AlertTile(
                  title: 'Route optimization needed',
                  description: 'Three routes exceed target fuel use.',
                ),
                _AlertTile(
                  title: 'Driver check-in',
                  description: 'Kwaku Mensah has not checked in yet.',
                ),
                _AlertTile(
                  title: 'Warehouse pressure',
                  description: 'Tema hub is at 82% capacity.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FirebaseLogisticsService {
  static Future<void> syncShipmentStatus() async {
    try {
      if (Firebase.apps.isEmpty) {
        return;
      }
      await FirebaseFirestore.instance.collection('shipments').limit(1).get();
    } catch (_) {
      // Firebase is configured externally; this local build keeps demo data until setup is complete.
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.title,
    required this.route,
    required this.status,
    required this.amount,
    required this.accent,
  });

  final String title;
  final String route;
  final String status;
  final String amount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.local_shipping_rounded, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(route, style: const TextStyle(color: Color(0xFF64748B))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoadPattern extends StatelessWidget {
  const _RoadPattern();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _RoadPainter(), child: Container());
  }
}

class _RoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.55)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final road = Path()
      ..moveTo(20, 100)
      ..lineTo(size.width * 0.38, 180)
      ..lineTo(size.width * 0.76, 120)
      ..lineTo(size.width - 30, 280)
      ..lineTo(size.width * 0.52, size.height - 80)
      ..lineTo(50, size.height - 70);

    canvas.drawPath(road, paint);

    final routePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    canvas.drawPath(road, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.items});

  final String title;
  final List<_InfoRow> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  Text(
                    item.value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverProfile {
  const _DriverProfile({
    required this.name,
    required this.route,
    required this.status,
    required this.score,
  });

  final String name;
  final String route;
  final String status;
  final String score;
}

class _OrderItem {
  const _OrderItem({
    required this.orderId,
    required this.name,
    required this.status,
    required this.time,
  });

  final String orderId;
  final String name;
  final String status;
  final String time;
}
