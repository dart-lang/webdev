// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hot_reload_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<HotReloadRequest> _$hotReloadRequestSerializer =
    _$HotReloadRequestSerializer();

class _$HotReloadRequestSerializer
    implements StructuredSerializer<HotReloadRequest> {
  @override
  final Iterable<Type> types = const [HotReloadRequest, _$HotReloadRequest];
  @override
  final String wireName = 'HotReloadRequest';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    HotReloadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  HotReloadRequest deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HotReloadRequestBuilder();

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

class _$HotReloadRequest extends HotReloadRequest {
  @override
  final String id;

  factory _$HotReloadRequest([
    void Function(HotReloadRequestBuilder)? updates,
  ]) => (HotReloadRequestBuilder()..update(updates))._build();

  _$HotReloadRequest._({required this.id}) : super._();
  @override
  HotReloadRequest rebuild(void Function(HotReloadRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HotReloadRequestBuilder toBuilder() =>
      HotReloadRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HotReloadRequest && id == other.id;
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
    return (newBuiltValueToStringHelper(r'HotReloadRequest')
      ..add('id', id)).toString();
  }
}

class HotReloadRequestBuilder
    implements Builder<HotReloadRequest, HotReloadRequestBuilder> {
  _$HotReloadRequest? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  HotReloadRequestBuilder();

  HotReloadRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HotReloadRequest other) {
    _$v = other as _$HotReloadRequest;
  }

  @override
  void update(void Function(HotReloadRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HotReloadRequest build() => _build();

  _$HotReloadRequest _build() {
    final _$result =
        _$v ??
        _$HotReloadRequest._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'HotReloadRequest',
            'id',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
