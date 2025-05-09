// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fetch_libraries_for_hot_reload_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<FetchLibrariesForHotReloadRequest>
_$fetchLibrariesForHotReloadRequestSerializer =
    new _$FetchLibrariesForHotReloadRequestSerializer();

class _$FetchLibrariesForHotReloadRequestSerializer
    implements StructuredSerializer<FetchLibrariesForHotReloadRequest> {
  @override
  final Iterable<Type> types = const [
    FetchLibrariesForHotReloadRequest,
    _$FetchLibrariesForHotReloadRequest,
  ];
  @override
  final String wireName = 'FetchLibrariesForHotReloadRequest';

  @override
  Iterable<Object?> serialize(
    Serializers serializers,
    FetchLibrariesForHotReloadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = <Object?>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  FetchLibrariesForHotReloadRequest deserialize(
    Serializers serializers,
    Iterable<Object?> serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = new FetchLibrariesForHotReloadRequestBuilder();

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

class _$FetchLibrariesForHotReloadRequest
    extends FetchLibrariesForHotReloadRequest {
  @override
  final String id;

  factory _$FetchLibrariesForHotReloadRequest([
    void Function(FetchLibrariesForHotReloadRequestBuilder)? updates,
  ]) =>
      (new FetchLibrariesForHotReloadRequestBuilder()..update(updates))
          ._build();

  _$FetchLibrariesForHotReloadRequest._({required this.id}) : super._() {
    BuiltValueNullFieldError.checkNotNull(
      id,
      r'FetchLibrariesForHotReloadRequest',
      'id',
    );
  }

  @override
  FetchLibrariesForHotReloadRequest rebuild(
    void Function(FetchLibrariesForHotReloadRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  FetchLibrariesForHotReloadRequestBuilder toBuilder() =>
      new FetchLibrariesForHotReloadRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FetchLibrariesForHotReloadRequest && id == other.id;
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
    return (newBuiltValueToStringHelper(r'FetchLibrariesForHotReloadRequest')
      ..add('id', id)).toString();
  }
}

class FetchLibrariesForHotReloadRequestBuilder
    implements
        Builder<
          FetchLibrariesForHotReloadRequest,
          FetchLibrariesForHotReloadRequestBuilder
        > {
  _$FetchLibrariesForHotReloadRequest? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  FetchLibrariesForHotReloadRequestBuilder();

  FetchLibrariesForHotReloadRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FetchLibrariesForHotReloadRequest other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$FetchLibrariesForHotReloadRequest;
  }

  @override
  void update(
    void Function(FetchLibrariesForHotReloadRequestBuilder)? updates,
  ) {
    if (updates != null) updates(this);
  }

  @override
  FetchLibrariesForHotReloadRequest build() => _build();

  _$FetchLibrariesForHotReloadRequest _build() {
    final _$result =
        _$v ??
        new _$FetchLibrariesForHotReloadRequest._(
          id: BuiltValueNullFieldError.checkNotNull(
            id,
            r'FetchLibrariesForHotReloadRequest',
            'id',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
