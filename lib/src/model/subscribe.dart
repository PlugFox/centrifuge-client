import 'package:centrifuge_dart/src/model/channel_push.dart';
import 'package:centrifuge_dart/src/model/stream_position.dart';

/// {@template subscribe}
/// Subscribe push from Centrifugo server.
/// {@endtemplate}
final class CentrifugeSubscribe extends CentrifugeChannelPush {
  /// {@macro subscribe}
  const CentrifugeSubscribe({
    required super.timestamp,
    required super.channel,
    required this.positioned,
    required this.recoverable,
    required this.data,
    required this.streamPosition,
  });

  @override
  String get type => 'subscribe';

  /// Whether subscription is positioned.
  final bool positioned;

  /// Whether subscription is recoverable.
  final bool recoverable;

  /// Data attached to subscription.
  final List<int> data;

  /// Stream position.
  final CentrifugeStreamPosition? streamPosition;
}