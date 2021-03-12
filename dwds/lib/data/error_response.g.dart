// GENERATED CODE - DO NOT MODIFY BY HAND

// @dart = 2.9

part of 'error_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ErrorResponse> _$errorResponseSerializer =
    new _$ErrorResponseSerializer();

class _$ErrorResponseSerializer implements StructuredSerializer<ErrorResponse> {
  @override
  final Iterable<Type> types = const [ErrorResponse, _$ErrorResponse];
  @override
  final String wireName = 'ErrorResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, ErrorResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'error',
      serializers.serialize(object.error,
          specifiedType: const FullType(String)),
      'stackTrace',
      serializers.serialize(object.stackTrace,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  ErrorResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ErrorResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'error':
          result.error = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'stackTrace':
          result.stackTrace = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ErrorResponse extends ErrorResponse {
  @override
  final String error;
  @override
  final String stackTrace;

  factory _$ErrorResponse([void Function(ErrorResponseBuilder) updates]) =>
      (new ErrorResponseBuilder()..update(updates)).build();

  _$ErrorResponse._({this.error, this.stackTrace}) : super._() {
    if (error == null) {
      throw new BuiltValueNullFieldError('ErrorResponse', 'error');
    }
    if (stackTrace == null) {
      throw new BuiltValueNullFieldError('ErrorResponse', 'stackTrace');
    }
  }

  @override
  ErrorResponse rebuild(void Function(ErrorResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ErrorResponseBuilder toBuilder() => new ErrorResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ErrorResponse &&
        error == other.error &&
        stackTrace == other.stackTrace;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, error.hashCode), stackTrace.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ErrorResponse')
          ..add('error', error)
          ..add('stackTrace', stackTrace))
        .toString();
  }
}

class ErrorResponseBuilder
    implements Builder<ErrorResponse, ErrorResponseBuilder> {
  _$ErrorResponse _$v;

  String _error;
  String get error => _$this._error;
  set error(String error) => _$this._error = error;

  String _stackTrace;
  String get stackTrace => _$this._stackTrace;
  set stackTrace(String stackTrace) => _$this._stackTrace = stackTrace;

  ErrorResponseBuilder();

  ErrorResponseBuilder get _$this {
    if (_$v != null) {
      _error = _$v.error;
      _stackTrace = _$v.stackTrace;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ErrorResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ErrorResponse;
  }

  @override
  void update(void Function(ErrorResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ErrorResponse build() {
    final _$result =
        _$v ?? new _$ErrorResponse._(error: error, stackTrace: stackTrace);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
