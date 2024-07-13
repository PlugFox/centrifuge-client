part of 'spinify_impl.dart';

@internal
abstract base class SpinifySubscriptionBase implements SpinifySubscription {
  SpinifySubscriptionBase({
    required SpinifySubscriptionMixin client,
    required this.channel,
    required this.recoverable,
    required this.epoch,
    required this.offset,
  })  : _clientWR = WeakReference<SpinifySubscriptionMixin>(client),
        _clientConfig = client.config;

  @override
  final String channel;

  /// Spinify client weak reference.
  final WeakReference<SpinifySubscriptionMixin> _clientWR;

  /// Spinify client
  SpinifySubscriptionMixin get _client {
    final target = _clientWR.target;
    if (target == null) {
      throw SpinifySubscriptionException(
        channel: channel,
        message: 'Spinify client is do not exist anymore',
      );
    }
    return target;
  }

  /// Spinify client configuration.
  final SpinifyConfig _clientConfig;

  /// Spinify logger.
  SpinifyLogger? get _logger => _clientConfig.logger;

  /// Current subscription state.
  SpinifySubscriptionState _state = SpinifySubscriptionState.unsubscribed();

  final StreamController<SpinifySubscriptionState> _stateController =
      StreamController<SpinifySubscriptionState>.broadcast();

  final StreamController<SpinifyChannelEvent> _eventController =
      StreamController<SpinifyChannelEvent>.broadcast();

  Future<T> _sendCommand<T extends SpinifyReply>(
    SpinifyCommand Function(int nextId) builder,
  ) =>
      _client._doOnReady(
        () => _client._sendCommand<T>(
          builder(_client._getNextCommandId()),
        ),
      );

  @override
  bool recoverable;

  @override
  String epoch;

  @override
  fixnum.Int64 offset;

  @override
  SpinifySubscriptionState get state => _state;

  @override
  SpinifySubscriptionStates get states =>
      SpinifySubscriptionStates(_stateController.stream);

  @override
  SpinifyChannelEvents<SpinifyChannelEvent> get stream =>
      SpinifyChannelEvents(_eventController.stream);

  @sideEffect
  @mustCallSuper
  void onEvent(SpinifyChannelEvent event) {
    assert(
      event.channel == channel,
      'Subscription "$channel" received event for another channel',
    );
    _eventController.add(event);
    _logger?.call(
      const SpinifyLogLevel.debug(),
      'subscription_event_received',
      'Subscription "$channel" received ${event.type} event',
      <String, Object?>{
        'channel': channel,
        'subscription': this,
        'event': event,
        if (event is SpinifyPublication) 'publication': event,
      },
    );
  }

  @internal
  @mustCallSuper
  void setState(SpinifySubscriptionState state) {
    if (_state == state) return;
    _stateController.add(_state = state);
    _logger?.call(
      const SpinifyLogLevel.config(),
      'subscription_state_changed',
      'Subscription "$channel" state changed to ${state.type}',
      <String, Object?>{
        'channel': channel,
        'subscription': this,
        'state': _state,
      },
    );
  }

  @mustCallSuper
  @interactive
  void close() {
    _stateController.close().ignore();
    _eventController.close().ignore();
    assert(_state.isUnsubscribed,
        'Subscription "$channel" is not unsubscribed before closing');
  }

  @override
  @interactive
  Future<void> ready() async {
    if (_client.isClosed)
      throw SpinifySubscriptionException(
        channel: channel,
        message: 'Client is closed',
      );
    if (_state.isSubscribed) return;
    if (_stateController.isClosed)
      throw SpinifySubscriptionException(
        channel: channel,
        message: 'Subscription is closed permanently',
      );
    final state = await _stateController.stream
        .firstWhere((state) => !state.isSubscribing);
    if (!state.isSubscribed)
      throw SpinifySubscriptionException(
        channel: channel,
        message: 'Subscription failed to subscribe',
      );
  }

  @override
  @interactive
  Future<SpinifyHistory> history({
    int? limit,
    SpinifyStreamPosition? since,
    bool? reverse,
  }) =>
      _sendCommand<SpinifyHistoryResult>(
        (id) => SpinifyHistoryRequest(
          id: id,
          channel: channel,
          timestamp: DateTime.now(),
          limit: limit,
          since: since,
          reverse: reverse,
        ),
      ).then<SpinifyHistory>(
        (reply) => SpinifyHistory(
          publications: List<SpinifyPublication>.unmodifiable(
              reply.publications.map((pub) => pub.copyWith(channel: channel))),
          since: reply.since,
        ),
      );

  @override
  @interactive
  Future<Map<String, SpinifyClientInfo>> presence() =>
      _sendCommand<SpinifyPresenceResult>(
        (id) => SpinifyPresenceRequest(
          id: id,
          channel: channel,
          timestamp: DateTime.now(),
        ),
      ).then<Map<String, SpinifyClientInfo>>((reply) => reply.presence);

  @override
  @interactive
  Future<SpinifyPresenceStats> presenceStats() =>
      _sendCommand<SpinifyPresenceStatsResult>(
        (id) => SpinifyPresenceStatsRequest(
          id: id,
          channel: channel,
          timestamp: DateTime.now(),
        ),
      ).then<SpinifyPresenceStats>(
        (reply) => SpinifyPresenceStats(
          channel: channel,
          clients: reply.numClients,
          users: reply.numUsers,
        ),
      );

  @override
  @interactive
  Future<void> publish(List<int> data) => _sendCommand<SpinifyPublishResult>(
        (id) => SpinifyPublishRequest(
          id: id,
          channel: channel,
          timestamp: DateTime.now(),
          data: data,
        ),
      );
}

@internal
final class SpinifyClientSubscriptionImpl extends SpinifySubscriptionBase
    implements SpinifyClientSubscription {
  SpinifyClientSubscriptionImpl({
    required super.client,
    required super.channel,
    required this.config,
  }) : super(
          recoverable: config.recoverable,
          epoch: config.since?.epoch ?? '',
          offset: config.since?.offset ?? fixnum.Int64.ZERO,
        );

  @override
  final SpinifySubscriptionConfig config;

  /// Whether the subscription should recover.
  bool _recover = false;

  /// Interactively subscribes to the channel.
  @override
  @interactive
  Future<void> subscribe() async {
    // Check if the client is connected
    switch (_client.state) {
      case SpinifyState$Connected _:
        break;
      case SpinifyState$Connecting _:
      case SpinifyState$Disconnected _:
        await _client.ready();
      case SpinifyState$Closed _:
        throw SpinifySubscriptionException(
          channel: channel,
          message: 'Client is closed',
        );
    }

    // Check if the subscription is already subscribed
    switch (state) {
      case SpinifySubscriptionState$Subscribed _:
        return;
      case SpinifySubscriptionState$Subscribing _:
        await ready();
      case SpinifySubscriptionState$Unsubscribed _:
        await _resubscribe();
    }
  }

  @override
  @interactive
  Future<void> unsubscribe([
    int code = 0,
    String reason = 'unsubscribe called',
  ]) async {
    if (_state.isUnsubscribed) return;
    //await ready().timeout(_client.config.timeout);
    throw UnimplementedError();
    // TODO(plugfox): implement unsubscribe, remove resubscribe timer
  }

  /// `SubscriptionImpl{}._resubscribe()` from `centrifuge` package
  Future<void> _resubscribe() async {
    if (!_state.isUnsubscribed) return;
    try {
      setState(SpinifySubscriptionState$Subscribing());

      final token = await config.getToken?.call();
      if (token == null || token.isEmpty) {
        throw SpinifySubscriptionException(
          channel: channel,
          message: 'Token is empty',
        );
      }

      final data = await config.getPayload?.call();

      final recover =
          _recover && offset > fixnum.Int64.ZERO && epoch.isNotEmpty;

      final result = await _sendCommand<SpinifySubscribeResult>(
        (id) => SpinifySubscribeRequest(
          id: id,
          channel: channel,
          timestamp: DateTime.now(),
          token: token,
          recoverable: recoverable,
          recover: recover,
          offset: recover ? offset : null,
          epoch: recover ? epoch : null,
          positioned: config.positioned,
          joinLeave: config.joinLeave,
          data: data,
        ),
      );

      if (result.recoverable) {
        _recover = true;
        epoch = result.since.epoch;
        offset = result.since.offset;
      }

      setState(SpinifySubscriptionState$Subscribed(data: result.data));

      if (result.expires) {
        // TODO(plugfox): implement resubscribe timer
        //_setUpRefreshConnection();
      }

      // Handle received publications and update offset.
      for (final pub in result.publications) {
        _client._eventController.add(pub);
        onEvent(pub);
        if (pub.offset case fixnum.Int64 value when value > offset) {
          offset = value;
        }
      }

      // TODO(plugfox): tear down reconnect timer
      //await _onSubscribed();

      _logger?.call(
        const SpinifyLogLevel.config(),
        'subscription_subscribed',
        'Subscription "$channel" subscribed',
        <String, Object?>{
          'channel': channel,
          'subscription': this,
        },
      );
    } on Object catch (error, stackTrace) {
      _logger?.call(
        const SpinifyLogLevel.error(),
        'subscription_resubscribe_error',
        'Subscription "$channel" failed to resubscribe',
        <String, Object?>{
          'channel': channel,
          'subscription': this,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      void scheduleResubscribe() {
        // TODO(plugfox): implement resubscribe timer
        //_setUpReconnectTimer();
      }
      switch (error) {
        case SpinifyErrorResult result:
          if (result.code == 109) {
            // Token expired error.
            scheduleResubscribe(); // Retry resubscribe
          } else if (result.temporary) {
            // Temporary error.
            scheduleResubscribe(); // Retry resubscribe
          } else {
            // Disable resubscribe timer
            //moveToUnsubscribed(result.code, result.message, false);
            setState(SpinifySubscriptionState$Unsubscribed());
          }
        case SpinifySubscriptionException _:
          scheduleResubscribe(); // Some spinify exception - retry resubscribe
          rethrow;
        default:
          scheduleResubscribe(); // Unknown error - retry resubscribe
      }
      Error.throwWithStackTrace(
        SpinifySubscriptionException(
          channel: channel,
          message: 'Failed to resubscribe to "$channel"',
          error: error,
        ),
        stackTrace,
      );
    }
  }
}

@internal
final class SpinifyServerSubscriptionImpl extends SpinifySubscriptionBase
    implements SpinifyServerSubscription {
  SpinifyServerSubscriptionImpl({
    required super.client,
    required super.channel,
    required super.recoverable,
    required super.epoch,
    required super.offset,
  });

  @override
  SpinifyChannelEvents<SpinifyChannelEvent> get stream =>
      _client.stream.filter(channel: channel);
}
