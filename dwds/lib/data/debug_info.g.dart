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
    value = object.authUrl;
    if (value != null) {
      result
        ..add('authUrl')
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
    value = object.workspaceName;
    if (value != null) {
      result
        ..add('workspaceName')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.tabUrl;
    if (value != null) {
      result
        ..add('tabUrl')
        ..add(serializers.serialize(value,
            specifiedType: const FullType(String)));
    }
    value = object.tabId;
    if (value != null) {
      result
        ..add('tabId')
        ..add(serializers.serialize(value, specifiedType: const FullType(int)));
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
        case 'authUrl':
          result.authUrl = serializers.deserialize(value,
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
        case 'isInternalBuild':
          result.isInternalBuild = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool?;
          break;
        case 'isFlutterApp':
          result.isFlutterApp = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool?;
          break;
        case 'workspaceName':
          result.workspaceName = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'tabUrl':
          result.tabUrl = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String?;
          break;
        case 'tabId':
          result.tabId = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int?;
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
  final String? authUrl;
  @override
  final String? dwdsVersion;
  @override
  final String? extensionUrl;
  @override
  final bool? isInternalBuild;
  @override
  final bool? isFlutterApp;
  @override
  final String? workspaceName;
  @override
  final String? tabUrl;
  @override
  final int? tabId;

  factory _$DebugInfo([void Function(DebugInfoBuilder)? updates]) =>
      (new DebugInfoBuilder()..update(updates))._build();

  _$DebugInfo._(
      {this.appEntrypointPath,
      this.appId,
      this.appInstanceId,
      this.appOrigin,
      this.appUrl,
      this.authUrl,
      this.dwdsVersion,
      this.extensionUrl,
      this.isInternalBuild,
      this.isFlutterApp,
      this.workspaceName,
      this.tabUrl,
      this.tabId})
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
        authUrl == other.authUrl &&
        dwdsVersion == other.dwdsVersion &&
        extensionUrl == other.extensionUrl &&
        isInternalBuild == other.isInternalBuild &&
        isFlutterApp == other.isFlutterApp &&
        workspaceName == other.workspaceName &&
        tabUrl == other.tabUrl &&
        tabId == other.tabId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appEntrypointPath.hashCode);
    _$hash = $jc(_$hash, appId.hashCode);
    _$hash = $jc(_$hash, appInstanceId.hashCode);
    _$hash = $jc(_$hash, appOrigin.hashCode);
    _$hash = $jc(_$hash, appUrl.hashCode);
    _$hash = $jc(_$hash, authUrl.hashCode);
    _$hash = $jc(_$hash, dwdsVersion.hashCode);
    _$hash = $jc(_$hash, extensionUrl.hashCode);
    _$hash = $jc(_$hash, isInternalBuild.hashCode);
    _$hash = $jc(_$hash, isFlutterApp.hashCode);
    _$hash = $jc(_$hash, workspaceName.hashCode);
    _$hash = $jc(_$hash, tabUrl.hashCode);
    _$hash = $jc(_$hash, tabId.hashCode);
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
          ..add('authUrl', authUrl)
          ..add('dwdsVersion', dwdsVersion)
          ..add('extensionUrl', extensionUrl)
          ..add('isInternalBuild', isInternalBuild)
          ..add('isFlutterApp', isFlutterApp)
          ..add('workspaceName', workspaceName)
          ..add('tabUrl', tabUrl)
          ..add('tabId', tabId))
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

  String? _authUrl;
  String? get authUrl => _$this._authUrl;
  set authUrl(String? authUrl) => _$this._authUrl = authUrl;

  String? _dwdsVersion;
  String? get dwdsVersion => _$this._dwdsVersion;
  set dwdsVersion(String? dwdsVersion) => _$this._dwdsVersion = dwdsVersion;

  String? _extensionUrl;
  String? get extensionUrl => _$this._extensionUrl;
  set extensionUrl(String? extensionUrl) => _$this._extensionUrl = extensionUrl;

  bool? _isInternalBuild;
  bool? get isInternalBuild => _$this._isInternalBuild;
  set isInternalBuild(bool? isInternalBuild) =>
      _$this._isInternalBuild = isInternalBuild;

  bool? _isFlutterApp;
  bool? get isFlutterApp => _$this._isFlutterApp;
  set isFlutterApp(bool? isFlutterApp) => _$this._isFlutterApp = isFlutterApp;

  String? _workspaceName;
  String? get workspaceName => _$this._workspaceName;
  set workspaceName(String? workspaceName) =>
      _$this._workspaceName = workspaceName;

  String? _tabUrl;
  String? get tabUrl => _$this._tabUrl;
  set tabUrl(String? tabUrl) => _$this._tabUrl = tabUrl;

  int? _tabId;
  int? get tabId => _$this._tabId;
  set tabId(int? tabId) => _$this._tabId = tabId;

  DebugInfoBuilder();

  DebugInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appEntrypointPath = $v.appEntrypointPath;
      _appId = $v.appId;
      _appInstanceId = $v.appInstanceId;
      _appOrigin = $v.appOrigin;
      _appUrl = $v.appUrl;
      _authUrl = $v.authUrl;
      _dwdsVersion = $v.dwdsVersion;
      _extensionUrl = $v.extensionUrl;
      _isInternalBuild = $v.isInternalBuild;
      _isFlutterApp = $v.isFlutterApp;
      _workspaceName = $v.workspaceName;
      _tabUrl = $v.tabUrl;
      _tabId = $v.tabId;
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
            authUrl: authUrl,
            dwdsVersion: dwdsVersion,
            extensionUrl: extensionUrl,
            isInternalBuild: isInternalBuild,
            isFlutterApp: isFlutterApp,
            workspaceName: workspaceName,
            tabUrl: tabUrl,
            tabId: tabId);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
