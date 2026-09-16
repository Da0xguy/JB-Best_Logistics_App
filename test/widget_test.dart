import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_first_app/main.dart';

void main() {
  testWidgets('App starts on login screen with role-based demo accounts', (
    tester,
  ) async {
    await tester.pumpWidget(const JBLogisticsApp());

    expect(find.text('JB Logistics'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Fleet control center'), findsOneWidget);
  });

  test(
    'Shipping IDs are unique, are 20 characters, and QR payload matches',
    () {
      final first = ShippingIdGenerator.generate();
      final second = ShippingIdGenerator.generate();

      expect(first.length, 20);
      expect(second.length, 20);
      expect(RegExp(r'^[A-Z0-9]{20}$').hasMatch(first), isTrue);
      expect(RegExp(r'^[A-Z0-9]{20}$').hasMatch(second), isTrue);
      expect(first == second, isFalse);
      expect(ShippingIdGenerator.isValid(first), isTrue);
      expect(ShippingIdGenerator.isValid('INVALID-SHIP-ID'), isFalse);
      expect(ShippingIdGenerator.buildQrPayload(first), contains(first));
    },
  );

  test('Admin can create staff accounts for the staff login flow', () {
    final before = StaffAccountRegistry.all.length;

    StaffAccountRegistry.createAccount(
      name: 'Grace Staff',
      email: 'grace.staff@jblogistics.app',
      password: 'grace123',
    );

    expect(StaffAccountRegistry.all.length, before + 1);
    expect(
      StaffAccountRegistry.all.any(
        (account) => account.email == 'grace.staff@jblogistics.app',
      ),
      isTrue,
    );
  });

  testWidgets('Customer tracking screen shows shipment overview and status', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CustomerTrackingScreen()));

    expect(find.text('Track shipment'), findsOneWidget);

    await tester.tap(find.text('Track order'));
    await tester.pump();

    expect(find.text('Shipment overview'), findsOneWidget);
    expect(find.text('Current status'), findsOneWidget);
    expect(find.textContaining('In transit'), findsWidgets);
  });

  testWidgets('Customer profile settings and payment flow are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CustomerProfileSettingsScreen()),
    );

    expect(find.text('Profile settings'), findsOneWidget);
    expect(find.text('Notification preferences'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: PaymentGatewayScreen()));

    expect(find.text('Payment gateway'), findsOneWidget);
    expect(find.text('Pay now'), findsOneWidget);
  });

  test('Admin can revoke and restrict staff accounts', () {
    final account = StaffAccountRegistry.createAccount(
      name: 'Nadia Staff',
      email: 'nadia.staff@jblogistics.app',
      password: 'nadia123',
    );

    expect(account, isNotNull);
    expect(
      StaffAccountRegistry.restrict('nadia.staff@jblogistics.app'),
      isTrue,
    );
    expect(StaffAccountRegistry.revoke('nadia.staff@jblogistics.app'), isTrue);
    expect(
      StaffAccountRegistry.findByEmail('nadia.staff@jblogistics.app'),
      isNull,
    );
  });

  test('Pickup carrier selection matches route, weight, and service', () {
    expect(
      chooseCarrier(
        origin: 'West Hills Estate',
        destination: 'Accra Central',
        weight: '4 kg',
        service: 'Express Courier',
      ),
      CarrierType.bike,
    );
    expect(
      chooseCarrier(
        origin: 'Tema Harbour',
        destination: 'Accra Central',
        weight: '18 kg',
        service: 'Local Freight',
      ),
      CarrierType.van,
    );
    expect(
      chooseCarrier(
        origin: 'Airport Hub',
        destination: 'Kumasi',
        weight: '18 kg',
        service: 'Local Freight',
      ),
      CarrierType.airplane,
    );
  });

  testWidgets('Admin service management exposes working add and edit actions', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ServiceManagementScreen()));

    expect(find.text('Manage services'), findsNothing);
    expect(find.text('Local Freight'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Local Freight'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
