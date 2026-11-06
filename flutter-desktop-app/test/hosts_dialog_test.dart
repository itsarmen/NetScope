/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netscope/hosts/hosts_file.dart';
import 'package:netscope/hosts/hosts_service.dart';
import 'package:netscope/ui/hosts_dialog.dart';

void main() {
  Future<HostsDocument> sampleDocument() async => HostsDocument.parse(
    '127.0.0.1 alpha.test # alpha\n# 0.0.0.0 beta.test\n',
    path: r'C:\Windows\System32\drivers\etc\hosts',
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    HostsDocumentLoader? load,
    HostsDocumentApplier? apply,
    HostsToast? toast,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HostsDialog(
            loadDocument: load ?? sampleDocument,
            applyDocument: apply,
            showToast: toast ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addEntry(WidgetTester tester, String host) async {
    await tester.enterText(find.byType(TextField).at(2), host);
    await tester.tap(find.text('Add'));
    await tester.pump();
  }

  testWidgets('loads entries and filters by search', (tester) async {
    await pumpDialog(tester);
    expect(find.text('alpha.test'), findsOneWidget);
    expect(find.text('beta.test'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'beta');
    await tester.pump();

    expect(find.text('beta.test'), findsOneWidget);
    expect(find.text('alpha.test'), findsNothing);
  });

  testWidgets('rejects an invalid IP address', (tester) async {
    await pumpDialog(tester);
    await tester.enterText(find.byType(TextField).at(1), 'not-an-ip');
    await tester.enterText(find.byType(TextField).at(2), 'bad.test');
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(
      find.text('Enter a valid IP address, for example 0.0.0.0.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('bad.test'),
      ),
      findsNothing,
    );
  });

  testWidgets('adds an entry and marks the document dirty', (tester) async {
    await pumpDialog(tester);
    await addEntry(tester, 'blocked.test');

    expect(find.text('blocked.test'), findsOneWidget);
    expect(find.textContaining('unsaved changes'), findsOneWidget);
    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply changes'),
    );
    expect(apply.onPressed, isNotNull);
  });

  testWidgets('remove asks for confirmation and deletes the entry', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.tap(find.byTooltip('Remove entry').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove entry'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('alpha.test'), findsNothing);
    expect(find.text('beta.test'), findsOneWidget);
  });

  testWidgets('successful apply reports the result and reloads', (
    tester,
  ) async {
    var calls = 0;
    final toasts = <String>[];
    await pumpDialog(
      tester,
      apply: (_) async {
        calls++;
        return const HostsApplyResult(true, 'Applied');
      },
      toast: toasts.add,
    );
    await addEntry(tester, 'blocked.test');

    await tester.tap(find.text('Apply changes'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(toasts, contains('Applied'));
    expect(find.textContaining('unsaved changes'), findsNothing);
  });

  testWidgets('failed apply keeps changes and shows the message', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      apply: (_) async =>
          const HostsApplyResult(false, 'Administrator approval was declined.'),
    );
    await addEntry(tester, 'blocked.test');

    await tester.tap(find.text('Apply changes'));
    await tester.pumpAndSettle();

    expect(find.text('Administrator approval was declined.'), findsOneWidget);
    expect(find.textContaining('unsaved changes'), findsOneWidget);
  });
}
