// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<RunRequest> _$runRequestSerializer = new _$RunRequestSerializer();

class _$RunRequestSerializer implements StructuredSerializer<RunRequest> {
  @override
  final Iterable<Type> types = const [RunRequest, _$RunRequest];
  @override
  final String wireName = 'RunRequest';

  @override
  Iterable<Object?> serialize(Serializers serializers, RunRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    return <Object?>[];
  }

  @override
  RunRequest deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    return new RunRequestBuilder().build();
  }
}

class _$RunRequest extends RunRequest {
  factory _$RunRequest([void Function(RunRequestBuilder)? updates]) =>
      (new RunRequestBuilder()..update(updates))._build();

  _$RunRequest._() : super._();

  @override
  RunRequest rebuild(void Function(RunRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RunRequestBuilder toBuilder() => new RunRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RunRequest;
  }

  @override
  int get hashCode {
    return 248087772;
  }

  @override
  String toString() {
    return newBuiltValueToStringHelper(r'RunRequest').toString();
  }
}

class RunRequestBuilder implements Builder<RunRequest, RunRequestBuilder> {
  _$RunRequest? _$v;

  RunRequestBuilder();

  @override
  void replace(RunRequest other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$RunRequest;
  }

  @override
  void update(void Function(RunRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RunRequest build() => _build();

  _$RunRequest _build() {
    final _$result = _$v ?? new _$RunRequest._();
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
