import 'package:flutter_test/flutter_test.dart';
import 'package:move/utils/connection_manager.dart';

/// Exercises the SMP arbitration lock in isolation. These only touch
/// acquire/release/runSmp, which never reach the BLE plugin.
void main() {
  // A singleton, so every test must hand its token back or the next one fails.
  final conn = ConnectionManager.instance;

  test('acquire grants the wire and reports the owner', () {
    final token = conn.acquireSmp('dfu');
    expect(conn.isSmpBusy, isTrue);
    expect(conn.smpOwner, 'dfu');
    conn.releaseSmp(token);
    expect(conn.isSmpBusy, isFalse);
    expect(conn.smpOwner, isNull);
  });

  test('a second acquire is refused while the wire is held', () {
    final token = conn.acquireSmp('dfu');
    expect(
      () => conn.acquireSmp('background-sync'),
      throwsA(isA<SmpBusyException>()
          .having((e) => e.currentOwner, 'currentOwner', 'dfu')
          .having((e) => e.requestedBy, 'requestedBy', 'background-sync')),
    );
    // The refused attempt must not have disturbed the incumbent.
    expect(conn.smpOwner, 'dfu');
    conn.releaseSmp(token);
  });

  test('releasing with a stale token cannot free somebody else\'s lock', () {
    final first = conn.acquireSmp('background-sync');
    conn.releaseSmp(first);

    final second = conn.acquireSmp('dfu');
    // A late teardown from the finished sync must be a no-op.
    conn.releaseSmp(first);
    expect(conn.isSmpBusy, isTrue, reason: 'stale token freed the DFU lock');
    expect(conn.smpOwner, 'dfu');

    conn.releaseSmp(second);
    expect(conn.isSmpBusy, isFalse);
  });

  test('releasing null and double-releasing are no-ops', () {
    conn.releaseSmp(null);
    final token = conn.acquireSmp('records');
    conn.releaseSmp(token);
    conn.releaseSmp(token);
    expect(conn.isSmpBusy, isFalse);
  });

  test('runSmp releases the wire even when the body throws', () async {
    await expectLater(
      conn.runSmp('records', () async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
    expect(conn.isSmpBusy, isFalse, reason: 'lock stranded after a throw');

    // ...and the wire is reusable afterwards.
    final value = await conn.runSmp('dfu', () async => 42);
    expect(value, 42);
    expect(conn.isSmpBusy, isFalse);
  });

  test('runSmp is refused while another flow holds the wire', () async {
    final token = conn.acquireSmp('dfu');
    await expectLater(
      conn.runSmp('background-sync', () async => 1),
      throwsA(isA<SmpBusyException>()),
    );
    expect(conn.smpOwner, 'dfu');
    conn.releaseSmp(token);
  });
}
