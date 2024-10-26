import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:mockito/annotations.dart';
import 'package:spinify/spinify.dart';
import 'package:test/test.dart';

import 'web_socket_fake.dart';

@GenerateNiceMocks([MockSpec<WebSocket>(as: #MockWebSocket)])
void main() {
  group('Spinify', () {
    final buffer = SpinifyLogBuffer(size: 10);

    Spinify createFakeClient([Future<WebSocket> Function(String)? transport]) =>
        Spinify(
          config: SpinifyConfig(
            transportBuilder: ({required url, headers, protocols}) =>
                transport?.call(url) ?? Future.value(WebSocket$Fake()),
            logger: buffer.add,
          ),
        );

    test('Create_and_close_client', () async {
      final client = createFakeClient();
      expect(client.isClosed, isFalse);
      expect(client.state, isA<SpinifyState$Disconnected>());
      await client.close();
      expect(client.state, isA<SpinifyState$Closed>());
      expect(client.isClosed, isTrue);
    });

    test('Create_and_close_multiple_clients', () async {
      final clients = List.generate(10, (_) => createFakeClient());
      expect(clients.every((client) => !client.isClosed), isTrue);
      await Future.wait(clients.map((client) => client.close()));
      expect(clients.every((client) => client.isClosed), isTrue);
    });

    test('Change_client_state', () async {
      final transport = WebSocket$Fake(); // ignore: close_sinks
      final client = createFakeClient((_) async => transport..reset());
      expect(transport.isClosed, isFalse);
      expect(client.state, isA<SpinifyState$Disconnected>());
      await client.connect('ws://localhost:8000/connection/websocket');
      expect(client.state, isA<SpinifyState$Connected>());
      await client.disconnect();
      expect(
        client.state,
        isA<SpinifyState$Disconnected>().having(
          (s) => s.temporary,
          'temporary',
          isFalse,
        ),
      );
      await client.connect('ws://localhost:8000/connection/websocket');
      expect(client.state, isA<SpinifyState$Connected>());
      await client.close();
      expect(client.state, isA<SpinifyState$Closed>());
      expect(client.isClosed, isTrue);
      expect(transport.isClosed, isTrue);
      expect(transport.closeCode, equals(1000));
    });

    test('Change_client_states', () {
      final transport = WebSocket$Fake(); // ignore: close_sinks
      final client = createFakeClient((_) async => transport..reset());
      Stream.fromIterable([
        () => client.connect('ws://localhost:8000/connection/websocket'),
        client.disconnect,
        () => client.connect('ws://localhost:8000/connection/websocket'),
        client.disconnect,
        client.close,
      ]).asyncMap(Future.new).drain<void>();
      expect(client.state, isA<SpinifyState$Disconnected>());
      expectLater(
          client.states,
          emitsInOrder([
            isA<SpinifyState$Connecting>(),
            isA<SpinifyState$Connected>(),
            isA<SpinifyState$Disconnected>(),
            isA<SpinifyState$Connecting>(),
            isA<SpinifyState$Connected>(),
            isA<SpinifyState$Disconnected>(),
            isA<SpinifyState$Closed>()
          ]));
    });

    test(
      'Reconnect_after_disconnected_transport',
      () => fakeAsync(
        (async) {
          final transport = WebSocket$Fake();
          final client = createFakeClient((_) async => transport..reset());
          const url = 'ws://localhost:8000/connection/websocket';
          unawaited(client.connect(url));
          expect(
            client.state,
            isA<SpinifyState$Connecting>().having(
              (s) => s.url,
              'url',
              equals(url),
            ),
          );
          async.elapse(client.config.timeout);
          expect(
            client.state,
            isA<SpinifyState$Connected>().having(
              (s) => s.url,
              'url',
              equals(url),
            ),
          );
          expect(transport, isNotNull);
          expect(transport, isA<WebSocket$Fake>());
          transport.close();
          async.elapse(const Duration(milliseconds: 50));
          expect(
            client.state,
            isA<SpinifyState$Disconnected>().having(
              (s) => s.temporary,
              'temporary',
              isTrue,
            ),
          );
          async.elapse(Duration(
              milliseconds:
                  client.config.connectionRetryInterval.min.inMilliseconds ~/
                      2));
          expect(
            client.state,
            isA<SpinifyState$Disconnected>().having(
              (s) => s.temporary,
              'temporary',
              isTrue,
            ),
          );
          async.elapse(client.config.connectionRetryInterval.max);
          expect(
            client.state,
            isA<SpinifyState$Connected>().having(
              (s) => s.url,
              'url',
              equals(url),
            ),
          );
          expectLater(
            client.states,
            emitsInOrder(
              [
                isA<SpinifyState$Disconnected>().having(
                  (s) => s.temporary,
                  'temporary',
                  isFalse,
                ),
                isA<SpinifyState$Closed>(),
                emitsDone,
              ],
            ),
          );
          client.close();
          async.elapse(client.config.connectionRetryInterval.max);
          expect(client.state, isA<SpinifyState$Closed>());
        },
      ),
    );

    test(
        'Rpc_requests',
        () => fakeAsync((async) {
              final client = createFakeClient()
                ..connect('ws://localhost:8000/connection/websocket');
              expect(client.state, isA<SpinifyState$Connecting>());
              async.elapse(client.config.timeout);
              expect(client.state, isA<SpinifyState$Connected>());

              // Send a request
              expect(
                client.rpc('echo', utf8.encode('Hello, World!')),
                completion(isA<List<int>>().having(
                  (data) => utf8.decode(data),
                  'data',
                  equals('Hello, World!'),
                )),
              );
              async.elapse(client.config.timeout);
              expect(client.state, isA<SpinifyState$Connected>());

              // Send 1000 requests
              for (var i = 0; i < 1000; i++) {
                expect(
                  client.rpc('echo', utf8.encode(i.toString())),
                  completion(isA<List<int>>().having(
                    (data) => utf8.decode(data),
                    'data',
                    equals(i.toString()),
                  )),
                );
              }

              async.elapse(client.config.timeout);
              expect(client.state, isA<SpinifyState$Connected>());
              client.disconnect();
              async.elapse(client.config.timeout);
              expect(client.state, isA<SpinifyState$Disconnected>());
              client.connect('ws://localhost:8000/connection/websocket');
              async.elapse(client.config.timeout);
              expect(client.state, isA<SpinifyState$Connected>());

              // Another request
              expect(
                client.rpc('getCurrentYear', <int>[]),
                completion(isA<List<int>>().having(
                  (data) => jsonDecode(utf8.decode(data))['year'],
                  'year',
                  DateTime.now().year,
                )),
              );
              async.elapse(client.config.timeout);

              expect(client.state, isA<SpinifyState$Connected>());
              client.close();
              async.elapse(client.config.timeout);
              expect(client.state, isA<SpinifyState$Closed>());
            }));

    test(
        'Metrics',
        () => fakeAsync((async) {
              final client = createFakeClient();
              expect(() => client.metrics, returnsNormally);
              expect(
                  client.metrics,
                  allOf([
                    isA<SpinifyMetrics>().having(
                      (m) => m.state.isConnected,
                      'isConnected',
                      isFalse,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.state,
                      'state',
                      equals(client.state),
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.connects,
                      'connects',
                      0,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.disconnects,
                      'disconnects',
                      0,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.chunksReceived,
                      'messagesReceived',
                      equals(Int64.ZERO),
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.chunksSent,
                      'chunksSent',
                      equals(Int64.ZERO),
                    ),
                  ]));
              client.connect('ws://localhost:8000/connection/websocket');
              async.elapse(client.config.timeout);
              expect(
                  client.metrics,
                  allOf([
                    isA<SpinifyMetrics>().having(
                      (m) => m.state.isConnected,
                      'isConnected',
                      isTrue,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.state,
                      'state',
                      equals(client.state),
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.connects,
                      'connects',
                      1,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.disconnects,
                      'disconnects',
                      0,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.chunksReceived,
                      'messagesReceived',
                      greaterThan(Int64.ZERO),
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.chunksSent,
                      'chunksSent',
                      greaterThan(Int64.ZERO),
                    ),
                  ]));
              client
                ..newSubscription('channel')
                ..close();
              async.elapse(client.config.timeout);
              expect(
                  client.metrics,
                  allOf([
                    isA<SpinifyMetrics>().having(
                      (m) => m.state.isConnected,
                      'isConnected',
                      isFalse,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.state,
                      'state',
                      equals(client.state),
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.connects,
                      'connects',
                      1,
                    ),
                    isA<SpinifyMetrics>().having(
                      (m) => m.disconnects,
                      'disconnects',
                      1,
                    ),
                  ]));
              expect(() => client.metrics.toString(), returnsNormally);
              expect(client.metrics.toString(), equals('SpinifyMetrics{}'));
              expect(() => client.metrics.toJson(), returnsNormally);
              expect(client.metrics.toJson(), isA<Map<String, Object?>>());
              expect(client.metrics.channels, hasLength(2));
              expect(
                  client.metrics.channels['channel'],
                  isA<SpinifyMetrics$Channel>().having((c) => c.toString(),
                      'subscriptions', equals(r'SpinifyMetrics$Channel{}')));
            }));
  });
}
