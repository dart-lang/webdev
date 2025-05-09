// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fetch_libraries_for_hot_reload_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<FetchLibrariesForHotReloadResponse>
_$fetchLibrariesForHotReloadResponseSerializer =
    new _$FetchLibrariesForHotReloadResponseSerializer();

class _$FetchLibrariesForHotReloadResponseSerializer
    implements StructuredSerializer<FetchLibrariesForHotReloadResponse> {
  @override
  final Iterable<Type> types = const [
    FetchLibrariesForHotReloadResponse,
    _$FetchLibrariesForHotReloadResponse,
  ];
  @override
  final String wireName = 'FetchLibrariesForHotReloadResponse';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    FetchLibrariesForHotReloadResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
      'success',
      serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      ),
    ];
    Object? value;
    value = object.errorMessage;
    if (value != null) {
      result
        ..add('error')
        ..add(
          serializers.serialize(value, specifiedType: const FullType(String)),
        );
    }
    return result;
  }

  @override
  FetchLibrariesForHotReloadResponse deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = new FetchLibrariesForHotReloadResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'id':
          result.id =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )!
                  as String;
          break;
        case 'success':
          result.success =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(bool),
                  )!
                  as bool;
          break;
        case 'error':
          result.errorMessage =
              serializers.deserialize(
                    value,
                    specifiedType: const FullType(String),
                  )
                  as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$FetchLibrariesForHotReloadResponse
    extends FetchLibrariesForHotReloadResponse {
  @override
  final String id;
  @override
  final bool success;
  @override
  final String? errorMessage;

  factory _$FetchLibrariesForHotReloadResponse([
    void Function(FetchLibrariesForHotReloadResponseBuilder)? updates,
  ]) =>
      (new FetchLibrariesForHotReloadResponseBuilder()..update(updates))
          ._build();

  _$FetchLibrariesForHotReloadResponse._({
    required this.id,
    required this.success,
    this.errorMessage,
  }) : super._() {
    BuiltValueNullFieldError.checkNotNull(
      id,
      r'FetchLibrariesForHotReloadResponse',
      'id',
    );
    BuiltValueNullFieldError.checkNotNull(
      success,
      r'FetchLibrariesForHotReloadResponse',
      'success',
    );
  }

  @override
  FetchLibrariesForHotReloadResponse rebuild(
    void Function(FetchLibrariesForHotReloadResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  FetchLibrariesForHotReloadResponseBuilder toBuilder() =>
      new FetchLibrariesForHotReloadResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FetchLibrariesForHotReloadResponse &&
        id == other.id &&
        success == other.success &&
        errorMessage == other.errorMessage;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, success.hashCode);
    _$hash = $jc(_$hash, errorMessage.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FetchLibrariesForHotReloadResponse')
          ..add('id', id)
          ..add('success', success)
          ..add('errorMessage', errorMessage))
        .toString();
  }
}

class FetchLibrariesForHotReloadResponseBuilder
    implements
        Builder<
          FetchLibrariesForHotReloadResponse,
          FetchLibrariesForHotReloadResponseBuilder
        > {
  _$FetchLibrariesForHotReloadResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  String? _errorMessage;
  String? get errorMessage => _$this._errorMessage;
  set errorMessage(String? errorMessage) => _$this._errorMessage = errorMessage;

  FetchLibrariesForHotReloadResponseBuilder();

  FetchLibrariesForHotReloadResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _success = $v.success;
      _errorMessage = $v.errorMessage;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FetchLibrariesForHotReloadResponse other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$FetchLibrariesForHotReloadResponse;
  }

  @override
  void update(
    void Function(FetchLibrariesForHotReloadResponseBuilder)? updates,
  ) {
    if (updates != null) updates(this);
  }

  @override
  FetchLibrariesForHotReloadResponse build() => _build();

  _$FetchLibrariesForHotReloadResponse _build() {
    final _$result =
        _$v ??
        new _$FetchLibrariesForHotReloadResponse._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'FetchLibrariesForHotReloadResponse',
            'id',
          ),
          success: BuiltValueNullFieldError.checkNotNull(
            success,
            r'FetchLibrariesForHotReloadResponse',
            'success',
          ),
          errorMessage: errorMessage,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
