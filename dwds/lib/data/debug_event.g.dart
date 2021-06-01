// GENERATED CODE - DO NOT MODIFY BY HAND
// @dart=2.9

part of 'debug_event.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<DebugEvent> _$debugEventSerializer = new _$DebugEventSerializer();

class _$DebugEventSerializer implements StructuredSerializer<DebugEvent> {
  @override
  final Iterable<Type> types = const [DebugEvent, _$DebugEvent];
  @override
  final String wireName = 'DebugEvent';

  @override
  Iterable<Object> serialize(Serializers serializers, DebugEvent object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
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
  DebugEvent deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DebugEventBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final Object value = iterator.current;
      switch (key) {
        case 'kind':
          result.kind = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'eventData':
          result.eventData = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'timestamp':
          result.timestamp = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
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

  factory _$DebugEvent([void Function(DebugEventBuilder) updates]) =>
      (new DebugEventBuilder()..update(updates)).build();

  _$DebugEvent._({this.kind, this.eventData, this.timestamp}) : super._() {
    BuiltValueNullFieldError.checkNotNull(kind, 'DebugEvent', 'kind');
    BuiltValueNullFieldError.checkNotNull(eventData, 'DebugEvent', 'eventData');
    BuiltValueNullFieldError.checkNotNull(timestamp, 'DebugEvent', 'timestamp');
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
    return $jf($jc(
        $jc($jc(0, kind.hashCode), eventData.hashCode), timestamp.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('DebugEvent')
          ..add('kind', kind)
          ..add('eventData', eventData)
          ..add('timestamp', timestamp))
        .toString();
  }
}

class DebugEventBuilder implements Builder<DebugEvent, DebugEventBuilder> {
  _$DebugEvent _$v;

  String _kind;
  String get kind => _$this._kind;
  set kind(String kind) => _$this._kind = kind;

  String _eventData;
  String get eventData => _$this._eventData;
  set eventData(String eventData) => _$this._eventData = eventData;

  int _timestamp;
  int get timestamp => _$this._timestamp;
  set timestamp(int timestamp) => _$this._timestamp = timestamp;

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
  void update(void Function(DebugEventBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$DebugEvent build() {
    final _$result = _$v ??
        new _$DebugEvent._(
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, 'DebugEvent', 'kind'),
            eventData: BuiltValueNullFieldError.checkNotNull(
                eventData, 'DebugEvent', 'eventData'),
            timestamp: BuiltValueNullFieldError.checkNotNull(
                timestamp, 'DebugEvent', 'timestamp'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
