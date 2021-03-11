// GENERATED CODE - DO NOT MODIFY BY HAND

// @dart = 2.9

part of 'build_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BuildStatus _$started = const BuildStatus._('started');
const BuildStatus _$succeeded = const BuildStatus._('succeeded');
const BuildStatus _$failed = const BuildStatus._('failed');

BuildStatus _$valueOf(String name) {
  switch (name) {
    case 'started':
      return _$started;
    case 'succeeded':
      return _$succeeded;
    case 'failed':
      return _$failed;
    default:
      throw new ArgumentError(name);
  }
}

final BuiltSet<BuildStatus> _$values =
    new BuiltSet<BuildStatus>(const <BuildStatus>[
  _$started,
  _$succeeded,
  _$failed,
]);

Serializer<BuildStatus> _$buildStatusSerializer = new _$BuildStatusSerializer();
Serializer<BuildResult> _$buildResultSerializer = new _$BuildResultSerializer();

class _$BuildStatusSerializer implements PrimitiveSerializer<BuildStatus> {
  @override
  final Iterable<Type> types = const <Type>[BuildStatus];
  @override
  final String wireName = 'BuildStatus';

  @override
  Object serialize(Serializers serializers, BuildStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      object.name;

  @override
  BuildStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BuildStatus.valueOf(serialized as String);
}

class _$BuildResultSerializer implements StructuredSerializer<BuildResult> {
  @override
  final Iterable<Type> types = const [BuildResult, _$BuildResult];
  @override
  final String wireName = 'BuildResult';

  @override
  Iterable<Object> serialize(Serializers serializers, BuildResult object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'status',
      serializers.serialize(object.status,
          specifiedType: const FullType(BuildStatus)),
    ];

    return result;
  }

  @override
  BuildResult deserialize(Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new BuildResultBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'status':
          result.status = serializers.deserialize(value,
              specifiedType: const FullType(BuildStatus)) as BuildStatus;
          break;
      }
    }

    return result.build();
  }
}

class _$BuildResult extends BuildResult {
  @override
  final BuildStatus status;

  factory _$BuildResult([void Function(BuildResultBuilder) updates]) =>
      (new BuildResultBuilder()..update(updates)).build();

  _$BuildResult._({this.status}) : super._() {
    if (status == null) {
      throw new BuiltValueNullFieldError('BuildResult', 'status');
    }
  }

  @override
  BuildResult rebuild(void Function(BuildResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BuildResultBuilder toBuilder() => new BuildResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BuildResult && status == other.status;
  }

  @override
  int get hashCode {
    return $jf($jc(0, status.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('BuildResult')..add('status', status))
        .toString();
  }
}

class BuildResultBuilder implements Builder<BuildResult, BuildResultBuilder> {
  _$BuildResult _$v;

  BuildStatus _status;
  BuildStatus get status => _$this._status;
  set status(BuildStatus status) => _$this._status = status;

  BuildResultBuilder();

  BuildResultBuilder get _$this {
    if (_$v != null) {
      _status = _$v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BuildResult other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$BuildResult;
  }

  @override
  void update(void Function(BuildResultBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$BuildResult build() {
    final _$result = _$v ?? new _$BuildResult._(status: status);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
