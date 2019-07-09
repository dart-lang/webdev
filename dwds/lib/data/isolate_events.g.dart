// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'isolate_events.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<IsolateExit> _$isolateExitSerializer = new _$IsolateExitSerializer();
Serializer<IsolateStart> _$isolateStartSerializer =
    new _$IsolateStartSerializer();

class _$IsolateExitSerializer implements StructuredSerializer<IsolateExit> {
  @override
  final Iterable<Type> types = const [IsolateExit, _$IsolateExit];
  @override
  final String wireName = 'IsolateExit';

  @override
  Iterable serialize(Serializers serializers, IsolateExit object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'appId',
      serializers.serialize(object.appId,
          specifiedType: const FullType(String)),
      'instanceId',
      serializers.serialize(object.instanceId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  IsolateExit deserialize(Serializers serializers, Iterable serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new IsolateExitBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'appId':
          result.appId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'instanceId':
          result.instanceId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$IsolateStartSerializer implements StructuredSerializer<IsolateStart> {
  @override
  final Iterable<Type> types = const [IsolateStart, _$IsolateStart];
  @override
  final String wireName = 'IsolateStart';

  @override
  Iterable serialize(Serializers serializers, IsolateStart object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'appId',
      serializers.serialize(object.appId,
          specifiedType: const FullType(String)),
      'instanceId',
      serializers.serialize(object.instanceId,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  IsolateStart deserialize(Serializers serializers, Iterable serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new IsolateStartBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'appId':
          result.appId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'instanceId':
          result.instanceId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$IsolateExit extends IsolateExit {
  @override
  final String appId;
  @override
  final String instanceId;

  factory _$IsolateExit([void Function(IsolateExitBuilder) updates]) =>
      (new IsolateExitBuilder()..update(updates)).build();

  _$IsolateExit._({this.appId, this.instanceId}) : super._() {
    if (appId == null) {
      throw new BuiltValueNullFieldError('IsolateExit', 'appId');
    }
    if (instanceId == null) {
      throw new BuiltValueNullFieldError('IsolateExit', 'instanceId');
    }
  }

  @override
  IsolateExit rebuild(void Function(IsolateExitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  IsolateExitBuilder toBuilder() => new IsolateExitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is IsolateExit &&
        appId == other.appId &&
        instanceId == other.instanceId;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, appId.hashCode), instanceId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('IsolateExit')
          ..add('appId', appId)
          ..add('instanceId', instanceId))
        .toString();
  }
}

class IsolateExitBuilder implements Builder<IsolateExit, IsolateExitBuilder> {
  _$IsolateExit _$v;

  String _appId;
  String get appId => _$this._appId;
  set appId(String appId) => _$this._appId = appId;

  String _instanceId;
  String get instanceId => _$this._instanceId;
  set instanceId(String instanceId) => _$this._instanceId = instanceId;

  IsolateExitBuilder();

  IsolateExitBuilder get _$this {
    if (_$v != null) {
      _appId = _$v.appId;
      _instanceId = _$v.instanceId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(IsolateExit other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$IsolateExit;
  }

  @override
  void update(void Function(IsolateExitBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$IsolateExit build() {
    final _$result =
        _$v ?? new _$IsolateExit._(appId: appId, instanceId: instanceId);
    replace(_$result);
    return _$result;
  }
}

class _$IsolateStart extends IsolateStart {
  @override
  final String appId;
  @override
  final String instanceId;

  factory _$IsolateStart([void Function(IsolateStartBuilder) updates]) =>
      (new IsolateStartBuilder()..update(updates)).build();

  _$IsolateStart._({this.appId, this.instanceId}) : super._() {
    if (appId == null) {
      throw new BuiltValueNullFieldError('IsolateStart', 'appId');
    }
    if (instanceId == null) {
      throw new BuiltValueNullFieldError('IsolateStart', 'instanceId');
    }
  }

  @override
  IsolateStart rebuild(void Function(IsolateStartBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  IsolateStartBuilder toBuilder() => new IsolateStartBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is IsolateStart &&
        appId == other.appId &&
        instanceId == other.instanceId;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, appId.hashCode), instanceId.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('IsolateStart')
          ..add('appId', appId)
          ..add('instanceId', instanceId))
        .toString();
  }
}

class IsolateStartBuilder
    implements Builder<IsolateStart, IsolateStartBuilder> {
  _$IsolateStart _$v;

  String _appId;
  String get appId => _$this._appId;
  set appId(String appId) => _$this._appId = appId;

  String _instanceId;
  String get instanceId => _$this._instanceId;
  set instanceId(String instanceId) => _$this._instanceId = instanceId;

  IsolateStartBuilder();

  IsolateStartBuilder get _$this {
    if (_$v != null) {
      _appId = _$v.appId;
      _instanceId = _$v.instanceId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(IsolateStart other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$IsolateStart;
  }

  @override
  void update(void Function(IsolateStartBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$IsolateStart build() {
    final _$result =
        _$v ?? new _$IsolateStart._(appId: appId, instanceId: instanceId);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
