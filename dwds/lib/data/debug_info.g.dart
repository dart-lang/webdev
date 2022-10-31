// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'debug_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<DebugInfo> _$debugInfoSerializer = new _$DebugInfoSerializer();

class _$DebugInfoSerializer implements StructuredSerializer<DebugInfo> {
  @override
  final Iterable<Type> types = const [DebugInfo, _$DebugInfo];
  @override
  final String wireName = 'DebugInfo';

  @override
  Iterable<Object?> serialize(Serializers serializers, DebugInfo object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[];
    Object? value;
    value = object.appEntrypointPath;
    if (value != null) {
      result
        ..add('appEntrypointPath')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.appId;
    if (value != null) {
      result
        ..add('appId')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.appInstanceId;
    if (value != null) {
      result
        ..add('appInstanceId')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.appOrigin;
    if (value != null) {
      result
        ..add('appOrigin')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.appUri;
    if (value != null) {
      result
        ..add('appUri')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.dwdsVersion;
    if (value != null) {
      result
        ..add('dwdsVersion')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.extensionUri;
    if (value != null) {
      result
        ..add('extensionUri')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  DebugInfo deserialize(Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DebugInfoBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'appEntrypointPath':
          result.appEntrypointPath = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'appId':
          result.appId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'appInstanceId':
          result.appInstanceId = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'appOrigin':
          result.appOrigin = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'appUri':
          result.appUri = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'dwdsVersion':
          result.dwdsVersion = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'extensionUri':
          result.extensionUri = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
      }
    }

    return result.build();
  }
}

class _$DebugInfo extends DebugInfo {
  @override
  final String? appEntrypointPath;
  @override
  final String? appId;
  @override
  final String? appInstanceId;
  @override
  final String? appOrigin;
  @override
  final String? appUri;
  @override
  final String? dwdsVersion;
  @override
  final String? extensionUri;

  factory _$DebugInfo([void Function(DebugInfoBuilder)? updates]) =>
      (new DebugInfoBuilder()..update(updates))._build();

  _$DebugInfo._(
      {this.appEntrypointPath,
      this.appId,
      this.appInstanceId,
      this.appOrigin,
      this.appUri,
      this.dwdsVersion,
      this.extensionUri})
      : super._();

  @override
  DebugInfo rebuild(void Function(DebugInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DebugInfoBuilder toBuilder() => new DebugInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DebugInfo &&
        appEntrypointPath == other.appEntrypointPath &&
        appId == other.appId &&
        appInstanceId == other.appInstanceId &&
        appOrigin == other.appOrigin &&
        appUri == other.appUri &&
        dwdsVersion == other.dwdsVersion &&
        extensionUri == other.extensionUri;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc(
            $jc(
                $jc(
                    $jc($jc($jc(0, appEntrypointPath.hashCode), appId.hashCode),
                        appInstanceId.hashCode),
                    appOrigin.hashCode),
                appUri.hashCode),
            dwdsVersion.hashCode),
        extensionUri.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DebugInfo')
          ..add('appEntrypointPath', appEntrypointPath)
          ..add('appId', appId)
          ..add('appInstanceId', appInstanceId)
          ..add('appOrigin', appOrigin)
          ..add('appUri', appUri)
          ..add('dwdsVersion', dwdsVersion)
          ..add('extensionUri', extensionUri))
        .toString();
  }
}

class DebugInfoBuilder implements Builder<DebugInfo, DebugInfoBuilder> {
  _$DebugInfo? _$v;

  String? _appEntrypointPath;
  String? get appEntrypointPath => _$this._appEntrypointPath;
  set appEntrypointPath(String? appEntrypointPath) =>
      _$this._appEntrypointPath = appEntrypointPath;

  String? _appId;
  String? get appId => _$this._appId;
  set appId(String? appId) => _$this._appId = appId;

  String? _appInstanceId;
  String? get appInstanceId => _$this._appInstanceId;
  set appInstanceId(String? appInstanceId) =>
      _$this._appInstanceId = appInstanceId;

  String? _appOrigin;
  String? get appOrigin => _$this._appOrigin;
  set appOrigin(String? appOrigin) => _$this._appOrigin = appOrigin;

  String? _appUri;
  String? get appUri => _$this._appUri;
  set appUri(String? appUri) => _$this._appUri = appUri;

  String? _dwdsVersion;
  String? get dwdsVersion => _$this._dwdsVersion;
  set dwdsVersion(String? dwdsVersion) => _$this._dwdsVersion = dwdsVersion;

  String? _extensionUri;
  String? get extensionUri => _$this._extensionUri;
  set extensionUri(String? extensionUri) => _$this._extensionUri = extensionUri;

  DebugInfoBuilder();

  DebugInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appEntrypointPath = $v.appEntrypointPath;
      _appId = $v.appId;
      _appInstanceId = $v.appInstanceId;
      _appOrigin = $v.appOrigin;
      _appUri = $v.appUri;
      _dwdsVersion = $v.dwdsVersion;
      _extensionUri = $v.extensionUri;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DebugInfo other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DebugInfo;
  }

  @override
  void update(void Function(DebugInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DebugInfo build() => _build();

  _$DebugInfo _build() {
    final _$result = _$v ??
        new _$DebugInfo._(
            appEntrypointPath: appEntrypointPath,
            appId: appId,
            appInstanceId: appInstanceId,
            appOrigin: appOrigin,
            appUri: appUri,
            dwdsVersion: dwdsVersion,
            extensionUri: extensionUri);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new,unnecessary_lambdas
