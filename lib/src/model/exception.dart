import 'package:meta/meta.dart';

/// {@template exception}
/// Spinify exception.
/// {@endtemplate}
/// {@category Exception}
@immutable
sealed class SpinifyException implements Exception {
  /// {@macro exception}
  const SpinifyException(
    this.code,
    this.message, [
    this.error,
  ]);

  /// Error code.
  final String code;

  /// Error message.
  final String message;

  /// Source error of exception if exists.
  final Object? error;

  /// Visitor pattern for nested exceptions.
  /// Callback for each nested exception, starting from the current one.
  void visitor(void Function(Object error) fn) {
    fn(this);
    switch (error) {
      case SpinifyException e:
        e.visitor(fn);
      case Object e:
        fn(e);
      case null:
        break;
    }
  }

  @override
  int get hashCode => Object.hash(code, message, error);

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  String toString() => message;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyConnectionException extends SpinifyException {
  /// {@macro exception}
  const SpinifyConnectionException({String? message, Object? error})
      : super(
          'spinify_connection_exception',
          message ?? 'Connection problem',
          error,
        );
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyReplyException extends SpinifyException {
  /// {@macro exception}
  const SpinifyReplyException({
    required this.replyCode,
    required String replyMessage,
    required this.temporary,
    Object? error,
  }) : super(
          'spinify_reply_exception',
          replyMessage,
          error,
        );

  /// Reply code.
  final int replyCode;

  /// Is reply error final.
  final bool temporary;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyPingException extends SpinifyException {
  /// {@macro exception}
  const SpinifyPingException({String? message, Object? error})
      : super(
          'spinify_ping_exception',
          message ?? 'Ping error',
          error,
        );
}

/// {@macro exception}
/// {@category Exception}
final class SpinifySubscriptionException extends SpinifyException {
  /// {@macro exception}
  const SpinifySubscriptionException({
    required this.channel,
    required String message,
    Object? error,
  }) : super(
          'spinify_subscription_exception',
          message,
          error,
        );

  /// Subscription channel.
  final String channel;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifySendException extends SpinifyException {
  /// {@macro exception}
  const SpinifySendException({
    String? message,
    Object? error,
  }) : super(
          'spinify_send_exception',
          message ?? 'Failed to send message',
          error,
        );
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyPublishException extends SpinifyException {
  /// {@macro exception}
  const SpinifyPublishException({
    required this.channel,
    String? message,
    Object? error,
  }) : super(
          'spinify_publish_exception',
          message ?? 'Failed to publish message to channel',
          error,
        );

  /// Publish channel.
  final String channel;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyPresenceException extends SpinifyException {
  /// {@macro exception}
  const SpinifyPresenceException({
    required this.channel,
    String? message,
    Object? error,
  }) : super(
          'spinify_presence_exception',
          message ?? 'Failed to get presence info for channel',
          error,
        );

  /// Presence channel.
  final String channel;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyPresenceStatsException extends SpinifyException {
  /// {@macro exception}
  const SpinifyPresenceStatsException({
    required this.channel,
    String? message,
    Object? error,
  }) : super(
          'spinify_presence_stats_exception',
          message ?? 'Failed to get presence stats for channel',
          error,
        );

  /// Presence channel.
  final String channel;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyHistoryException extends SpinifyException {
  /// {@macro exception}
  const SpinifyHistoryException({
    required this.channel,
    String? message,
    Object? error,
  }) : super(
          'spinify_history_exception',
          message ?? 'Failed to get history for channel',
          error,
        );

  /// Presence channel.
  final String channel;
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyRPCException extends SpinifyException {
  /// {@macro exception}
  const SpinifyRPCException({
    String? message,
    Object? error,
  }) : super(
          'spinify_rpc_exception',
          message ?? 'Failed to call remote procedure',
          error,
        );
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyFetchException extends SpinifyException {
  /// {@macro exception}
  const SpinifyFetchException({
    String? message,
    Object? error,
  }) : super(
          'spinify_fetch_exception',
          message ?? 'Failed to fetch data',
          error,
        );
}

/// {@macro exception}
/// {@category Exception}
final class SpinifyRefreshException extends SpinifyException {
  /// {@macro exception}
  const SpinifyRefreshException({
    String? message,
    Object? error,
  }) : super(
          'spinify_refresh_exception',
          message ?? 'Error while refreshing connection token',
          error,
        );
}

/// Problem relevant to transport layer, connection,
/// data transfer or encoding/decoding issues.
/// {@macro exception}
/// {@category Exception}
final class SpinifyTransportException extends SpinifyException {
  /// {@macro exception}
  const SpinifyTransportException({
    required String message,
    Object? error,
    this.data,
  }) : super(
          'spinify_transport_exception',
          message,
          error,
        );

  /// Additional data related to the exception.
  final Object? data;
}
