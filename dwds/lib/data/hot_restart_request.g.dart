// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hot_restart_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<HotRestartRequest> _$hotRestartRequestSerializer =
    _$HotRestartRequestSerializer();

class _$HotRestartRequestSerializer
    implements StructuredSerializer<HotRestartRequest> {
  @override
  final Iterable<Type> types = const [HotRestartRequest, _$HotRestartRequest];
  @override
  final String wireName = 'HotRestartRequest';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    HotRestartRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  HotRestartRequest deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HotRestartRequestBuilder();

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
      }
    }

    return result.build();
  }
}

class _$HotRestartRequest extends HotRestartRequest {
  @override
  final String id;

  factory _$HotRestartRequest([
    void Function(HotRestartRequestBuilder)? updates,
  ]) => (HotRestartRequestBuilder()..update(updates))._build();

  _$HotRestartRequest._({required this.id}) : super._();
  @override
  HotRestartRequest rebuild(void Function(HotRestartRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HotRestartRequestBuilder toBuilder() =>
      HotRestartRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HotRestartRequest && id == other.id;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HotRestartRequest')
      ..add('id', id)).toString();
  }
}

class HotRestartRequestBuilder
    implements Builder<HotRestartRequest, HotRestartRequestBuilder> {
  _$HotRestartRequest? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  HotRestartRequestBuilder();

  HotRestartRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HotRestartRequest other) {
    _$v = other as _$HotRestartRequest;
  }

  @override
  void update(void Function(HotRestartRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HotRestartRequest build() => _build();

  _$HotRestartRequest _build() {
    final _$result =
        _$v ??
        _$HotRestartRequest._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'HotRestartRequest',
            'id',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
