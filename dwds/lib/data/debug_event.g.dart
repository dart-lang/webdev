// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'debug_event.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<DebugEvent> _$debugEventSerializer = new _$DebugEventSerializer();
Serializer<BatchedDebugEvents> _$batchedDebugEventsSerializer =
    new _$BatchedDebugEventsSerializer();

class _$DebugEventSerializer implements StructuredSerializer<DebugEvent> {
  @override
  final Iterable<Type> types = const [DebugEvent, _$DebugEvent];
  @override
  final String wireName = 'DebugEvent';

  @override
  Iterable<Object?> serialize(Serializers serializers, DebugEvent object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'kind',
      serializers.serialize(object.kind, specifiedType: const FullType(String)),
      'eventData',
      serializers.serialize(object.eventData,
          specifiedType: const FullType(String)),
      'timestamp',
      serializers.serialize(object.timestamp,
          specifiedType: const FullType(int)),
    ];

    return result;
  }

  @override
  DebugEvent deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DebugEventBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'kind':
          result.kind = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'eventData':
          result.eventData = serializers.deserialize(value,
              specifiedType: const FullType(String))! as String;
          break;
        case 'timestamp':
          result.timestamp = serializers.deserialize(value,
              specifiedType: const FullType(int))! as int;
          break;
      }
    }

    return result.build();
  }
}

class _$BatchedDebugEventsSerializer
    implements StructuredSerializer<BatchedDebugEvents> {
  @override
  final Iterable<Type> types = const [BatchedDebugEvents, _$BatchedDebugEvents];
  @override
  final String wireName = 'BatchedDebugEvents';

  @override
  Iterable<Object?> serialize(
      Serializers serializers, BatchedDebugEvents object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'events',
      serializers.serialize(object.events,
          specifiedType:
              const FullType(BuiltList, const [const FullType(DebugEvent)])),
    ];

    return result;
  }

  @override
  BatchedDebugEvents deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new BatchedDebugEventsBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'events':
          result.events.replace(serializers.deserialize(value,
                  specifiedType: const FullType(
                      BuiltList, const [const FullType(DebugEvent)]))!
              as BuiltList<Object?>);
          break;
      }
    }

    return result.build();
  }
}

class _$DebugEvent extends DebugEvent {
  @override
  final String kind;
  @override
  final String eventData;
  @override
  final int timestamp;

  factory _$DebugEvent([void Function(DebugEventBuilder)? updates]) =>
      (new DebugEventBuilder()..update(updates))._build();

  _$DebugEvent._(
      {required this.kind, required this.eventData, required this.timestamp})
      : super._() {
    BuiltValueNullFieldError.checkNotNull(kind, r'DebugEvent', 'kind');
    BuiltValueNullFieldError.checkNotNull(
        eventData, r'DebugEvent', 'eventData');
    BuiltValueNullFieldError.checkNotNull(
        timestamp, r'DebugEvent', 'timestamp');
  }

  @override
  DebugEvent rebuild(void Function(DebugEventBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DebugEventBuilder toBuilder() => new DebugEventBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DebugEvent &&
        kind == other.kind &&
        eventData == other.eventData &&
        timestamp == other.timestamp;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, eventData.hashCode);
    _$hash = $jc(_$hash, timestamp.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DebugEvent')
          ..add('kind', kind)
          ..add('eventData', eventData)
          ..add('timestamp', timestamp))
        .toString();
  }
}

class DebugEventBuilder implements Builder<DebugEvent, DebugEventBuilder> {
  _$DebugEvent? _$v;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _eventData;
  String? get eventData => _$this._eventData;
  set eventData(String? eventData) => _$this._eventData = eventData;

  int? _timestamp;
  int? get timestamp => _$this._timestamp;
  set timestamp(int? timestamp) => _$this._timestamp = timestamp;

  DebugEventBuilder();

  DebugEventBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _eventData = $v.eventData;
      _timestamp = $v.timestamp;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DebugEvent other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DebugEvent;
  }

  @override
  void update(void Function(DebugEventBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DebugEvent build() => _build();

  _$DebugEvent _build() {
    final _$result = _$v ??
        new _$DebugEvent._(
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, r'DebugEvent', 'kind'),
            eventData: BuiltValueNullFieldError.checkNotNull(
                eventData, r'DebugEvent', 'eventData'),
            timestamp: BuiltValueNullFieldError.checkNotNull(
                timestamp, r'DebugEvent', 'timestamp'));
    replace(_$result);
    return _$result;
  }
}

class _$BatchedDebugEvents extends BatchedDebugEvents {
  @override
  final BuiltList<DebugEvent> events;

  factory _$BatchedDebugEvents(
          [void Function(BatchedDebugEventsBuilder)? updates]) =>
      (new BatchedDebugEventsBuilder()..update(updates))._build();

  _$BatchedDebugEvents._({required this.events}) : super._() {
    BuiltValueNullFieldError.checkNotNull(
        events, r'BatchedDebugEvents', 'events');
  }

  @override
  BatchedDebugEvents rebuild(
          void Function(BatchedDebugEventsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BatchedDebugEventsBuilder toBuilder() =>
      new BatchedDebugEventsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BatchedDebugEvents && events == other.events;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, events.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BatchedDebugEvents')
          ..add('events', events))
        .toString();
  }
}

class BatchedDebugEventsBuilder
    implements Builder<BatchedDebugEvents, BatchedDebugEventsBuilder> {
  _$BatchedDebugEvents? _$v;

  ListBuilder<DebugEvent>? _events;
  ListBuilder<DebugEvent> get events =>
      _$this._events ??= new ListBuilder<DebugEvent>();
  set events(ListBuilder<DebugEvent>? events) => _$this._events = events;

  BatchedDebugEventsBuilder();

  BatchedDebugEventsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _events = $v.events.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BatchedDebugEvents other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$BatchedDebugEvents;
  }

  @override
  void update(void Function(BatchedDebugEventsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BatchedDebugEvents build() => _build();

  _$BatchedDebugEvents _build() {
    _$BatchedDebugEvents _$result;
    try {
      _$result = _$v ?? new _$BatchedDebugEvents._(events: events.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'events';
        events.build();
      } catch (e) {
        throw new BuiltValueNestedFieldError(
            r'BatchedDebugEvents', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
