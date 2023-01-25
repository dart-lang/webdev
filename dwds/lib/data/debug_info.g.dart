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
    value = object.appUrl;
    if (value != null) {
      result
        ..add('appUrl')
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
    value = object.extensionUrl;
    if (value != null) {
      result
        ..add('extensionUrl')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.authUrl;
    if (value != null) {
      result
        ..add('authUrl')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.isInternalBuild;
    if (value != null) {
      result
        ..add('isInternalBuild')
        ..add(
            serializers.serialize(value, specifiedType: const FullType(bool)));
    }
    value = object.isFlutterApp;
    if (value != null) {
      result
        ..add('isFlutterApp')
        ..add(
            serializers.serialize(value, specifiedType: const FullType(bool)));
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
        case 'appUrl':
          result.appUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'dwdsVersion':
          result.dwdsVersion = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'extensionUrl':
          result.extensionUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'authUrl':
          result.authUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'isInternalBuild':
          result.isInternalBuild = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool?;
          break;
        case 'isFlutterApp':
          result.isFlutterApp = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool?;
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
  final String? appUrl;
  @override
  final String? dwdsVersion;
  @override
  final String? extensionUrl;
  @override
  final String? authUrl;
  @override
  final bool? isInternalBuild;
  @override
  final bool? isFlutterApp;

  factory _$DebugInfo([void Function(DebugInfoBuilder)? updates]) =>
      (new DebugInfoBuilder()..update(updates))._build();

  _$DebugInfo._(
      {this.appEntrypointPath,
      this.appId,
      this.appInstanceId,
      this.appOrigin,
      this.appUrl,
      this.dwdsVersion,
      this.extensionUrl,
      this.authUrl,
      this.isInternalBuild,
      this.isFlutterApp})
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
        appUrl == other.appUrl &&
        dwdsVersion == other.dwdsVersion &&
        extensionUrl == other.extensionUrl &&
        authUrl == other.authUrl &&
        isInternalBuild == other.isInternalBuild &&
        isFlutterApp == other.isFlutterApp;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appEntrypointPath.hashCode);
    _$hash = $jc(_$hash, appId.hashCode);
    _$hash = $jc(_$hash, appInstanceId.hashCode);
    _$hash = $jc(_$hash, appOrigin.hashCode);
    _$hash = $jc(_$hash, appUrl.hashCode);
    _$hash = $jc(_$hash, dwdsVersion.hashCode);
    _$hash = $jc(_$hash, extensionUrl.hashCode);
    _$hash = $jc(_$hash, authUrl.hashCode);
    _$hash = $jc(_$hash, isInternalBuild.hashCode);
    _$hash = $jc(_$hash, isFlutterApp.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DebugInfo')
          ..add('appEntrypointPath', appEntrypointPath)
          ..add('appId', appId)
          ..add('appInstanceId', appInstanceId)
          ..add('appOrigin', appOrigin)
          ..add('appUrl', appUrl)
          ..add('dwdsVersion', dwdsVersion)
          ..add('extensionUrl', extensionUrl)
          ..add('authUrl', authUrl)
          ..add('isInternalBuild', isInternalBuild)
          ..add('isFlutterApp', isFlutterApp))
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

  String? _appUrl;
  String? get appUrl => _$this._appUrl;
  set appUrl(String? appUrl) => _$this._appUrl = appUrl;

  String? _dwdsVersion;
  String? get dwdsVersion => _$this._dwdsVersion;
  set dwdsVersion(String? dwdsVersion) => _$this._dwdsVersion = dwdsVersion;

  String? _extensionUrl;
  String? get extensionUrl => _$this._extensionUrl;
  set extensionUrl(String? extensionUrl) => _$this._extensionUrl = extensionUrl;

  String? _authUrl;
  String? get authUrl => _$this._authUrl;
  set authUrl(String? authUrl) => _$this._authUrl = authUrl;

  bool? _isInternalBuild;
  bool? get isInternalBuild => _$this._isInternalBuild;
  set isInternalBuild(bool? isInternalBuild) =>
      _$this._isInternalBuild = isInternalBuild;

  bool? _isFlutterApp;
  bool? get isFlutterApp => _$this._isFlutterApp;
  set isFlutterApp(bool? isFlutterApp) => _$this._isFlutterApp = isFlutterApp;

  DebugInfoBuilder();

  DebugInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appEntrypointPath = $v.appEntrypointPath;
      _appId = $v.appId;
      _appInstanceId = $v.appInstanceId;
      _appOrigin = $v.appOrigin;
      _appUrl = $v.appUrl;
      _dwdsVersion = $v.dwdsVersion;
      _extensionUrl = $v.extensionUrl;
      _authUrl = $v.authUrl;
      _isInternalBuild = $v.isInternalBuild;
      _isFlutterApp = $v.isFlutterApp;
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
            appUrl: appUrl,
            dwdsVersion: dwdsVersion,
            extensionUrl: extensionUrl,
            authUrl: authUrl,
            isInternalBuild: isInternalBuild,
            isFlutterApp: isFlutterApp);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
