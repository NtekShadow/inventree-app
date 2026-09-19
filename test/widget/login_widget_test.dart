import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";
import "package:inventree/l10n/collected/app_localizations.dart";

import "package:inventree/settings/login.dart";
import "package:inventree/user_profile.dart";
import "../setup.dart";

void main() {
  setupTestEnv();

  testWidgets("InvenTreeLoginWidget renders SSO and manual token buttons", (
    WidgetTester tester,
  ) async {
    final profile = UserProfile(
      name: "Test Server",
      server: "https://inventree.example.com",
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          I18N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: I18N.supportedLocales,
        home: InvenTreeLoginWidget(profile),
      ),
    );
    await tester.pumpAndSettle();

    // Verify SSO button is present
    expect(find.byIcon(TablerIcons.shield_lock), findsOneWidget);
    expect(find.text("Single Sign-On (SSO / OIDC)"), findsOneWidget);

    // Verify manual token button is present
    expect(find.text("Enter API token directly"), findsOneWidget);

    // Verify standard form fields
    expect(find.byType(TextFormField), findsNWidgets(2));

    // Tap on manual token button and verify dialog opens
    await tester.tap(find.text("Enter API token directly"));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text("Paste your InvenTree API token"), findsOneWidget);
  });
}
