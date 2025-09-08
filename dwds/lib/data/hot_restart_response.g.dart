// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hot_restart_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<HotRestartResponse> _$hotRestartResponseSerializer =
    _$HotRestartResponseSerializer();

class _$HotRestartResponseSerializer
    implements StructuredSerializer<HotRestartResponse> {
  @override
  final Iterable<Type> types = const [HotRestartResponse, _$HotRestartResponse];
  @override
  final String wireName = 'HotRestartResponse';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    HotRestartResponse object, {
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
  HotRestartResponse deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HotRestartResponseBuilder();

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

class _$HotRestartResponse extends HotRestartResponse {
  @override
  final String id;
  @override
  final bool success;
  @override
  final String? errorMessage;

  factory _$HotRestartResponse([
    void Function(HotRestartResponseBuilder)? updates,
  ]) => (HotRestartResponseBuilder()..update(updates))._build();

  _$HotRestartResponse._({
    required this.id,
    required this.success,
    this.errorMessage,
  }) : super._();
  @override
  HotRestartResponse rebuild(
    void Function(HotRestartResponseBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  HotRestartResponseBuilder toBuilder() =>
      HotRestartResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HotRestartResponse &&
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
    return (newBuiltValueToStringHelper(r'HotRestartResponse')
          ..add('id', id)
          ..add('success', success)
          ..add('errorMessage', errorMessage))
        .toString();
  }
}

class HotRestartResponseBuilder
    implements Builder<HotRestartResponse, HotRestartResponseBuilder> {
  _$HotRestartResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  bool? _success;
  bool? get success => _$this._success;
  set success(bool? success) => _$this._success = success;

  String? _errorMessage;
  String? get errorMessage => _$this._errorMessage;
  set errorMessage(String? errorMessage) => _$this._errorMessage = errorMessage;

  HotRestartResponseBuilder();

  HotRestartResponseBuilder get _$this {
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
  void replace(HotRestartResponse other) {
    _$v = other as _$HotRestartResponse;
  }

  @override
  void update(void Function(HotRestartResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HotRestartResponse build() => _build();

  _$HotRestartResponse _build() {
    final _$result =
        _$v ??
        _$HotRestartResponse._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'HotRestartResponse',
            'id',
          ),
          success: BuiltValueNullFieldError.checkNotNull(
            success,
            r'HotRestartResponse',
            'success',
          ),
          errorMessage: errorMessage,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
