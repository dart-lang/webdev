// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'extension_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<ExtensionRequest> _$extensionRequestSerializer =
    new _$ExtensionRequestSerializer();
Serializer<ExtensionResponse> _$extensionResponseSerializer =
    new _$ExtensionResponseSerializer();
Serializer<ExtensionEvent> _$extensionEventSerializer =
    new _$ExtensionEventSerializer();

class _$ExtensionRequestSerializer
    implements StructuredSerializer<ExtensionRequest> {
  @override
  final Iterable<Type> types = const [ExtensionRequest, _$ExtensionRequest];
  @override
  final String wireName = 'ExtensionRequest';

  @override
  Iterable<Object> serialize(Serializers serializers, ExtensionRequest object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(int)),
      'command',
      serializers.serialize(object.command,
          specifiedType: const FullType(String)),
    ];
    if (object.commandParams != null) {
      result
        ..add('commandParams')
        ..add(serializers.serialize(object.commandParams,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  ExtensionRequest deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExtensionRequestBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'command':
          result.command = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'commandParams':
          result.commandParams = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ExtensionResponseSerializer
    implements StructuredSerializer<ExtensionResponse> {
  @override
  final Iterable<Type> types = const [ExtensionResponse, _$ExtensionResponse];
  @override
  final String wireName = 'ExtensionResponse';

  @override
  Iterable<Object> serialize(Serializers serializers, ExtensionResponse object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'id',
      serializers.serialize(object.id, specifiedType: const FullType(int)),
      'success',
      serializers.serialize(object.success,
          specifiedType: const FullType(bool)),
      'result',
      serializers.serialize(object.result,
          specifiedType: const FullType(String)),
    ];
    if (object.error != null) {
      result
        ..add('error')
        ..add(serializers.serialize(object.error,
            specifiedType: const FullType(String)));
    }
    return result;
  }

  @override
  ExtensionResponse deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExtensionResponseBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'id':
          result.id = serializers.deserialize(value,
              specifiedType: const FullType(int)) as int;
          break;
        case 'success':
          result.success = serializers.deserialize(value,
              specifiedType: const FullType(bool)) as bool;
          break;
        case 'result':
          result.result = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'error':
          result.error = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ExtensionEventSerializer
    implements StructuredSerializer<ExtensionEvent> {
  @override
  final Iterable<Type> types = const [ExtensionEvent, _$ExtensionEvent];
  @override
  final String wireName = 'ExtensionEvent';

  @override
  Iterable<Object> serialize(Serializers serializers, ExtensionEvent object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object>[
      'params',
      serializers.serialize(object.params,
          specifiedType: const FullType(String)),
      'method',
      serializers.serialize(object.method,
          specifiedType: const FullType(String)),
    ];

    return result;
  }

  @override
  ExtensionEvent deserialize(
      Serializers serializers, Iterable<Object> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new ExtensionEventBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current as String;
      iterator.moveNext();
      final dynamic value = iterator.current;
      switch (key) {
        case 'params':
          result.params = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
        case 'method':
          result.method = serializers.deserialize(value,
              specifiedType: const FullType(String)) as String;
          break;
      }
    }

    return result.build();
  }
}

class _$ExtensionRequest extends ExtensionRequest {
  @override
  final int id;
  @override
  final String command;
  @override
  final String commandParams;

  factory _$ExtensionRequest(
          [void Function(ExtensionRequestBuilder) updates]) =>
      (new ExtensionRequestBuilder()..update(updates)).build();

  _$ExtensionRequest._({this.id, this.command, this.commandParams})
      : super._() {
    if (id == null) {
      throw new BuiltValueNullFieldError('ExtensionRequest', 'id');
    }
    if (command == null) {
      throw new BuiltValueNullFieldError('ExtensionRequest', 'command');
    }
  }

  @override
  ExtensionRequest rebuild(void Function(ExtensionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExtensionRequestBuilder toBuilder() =>
      new ExtensionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExtensionRequest &&
        id == other.id &&
        command == other.command &&
        commandParams == other.commandParams;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc(0, id.hashCode), command.hashCode), commandParams.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExtensionRequest')
          ..add('id', id)
          ..add('command', command)
          ..add('commandParams', commandParams))
        .toString();
  }
}

class ExtensionRequestBuilder
    implements Builder<ExtensionRequest, ExtensionRequestBuilder> {
  _$ExtensionRequest _$v;

  int _id;
  int get id => _$this._id;
  set id(int id) => _$this._id = id;

  String _command;
  String get command => _$this._command;
  set command(String command) => _$this._command = command;

  String _commandParams;
  String get commandParams => _$this._commandParams;
  set commandParams(String commandParams) =>
      _$this._commandParams = commandParams;

  ExtensionRequestBuilder();

  ExtensionRequestBuilder get _$this {
    if (_$v != null) {
      _id = _$v.id;
      _command = _$v.command;
      _commandParams = _$v.commandParams;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExtensionRequest other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExtensionRequest;
  }

  @override
  void update(void Function(ExtensionRequestBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExtensionRequest build() {
    final _$result = _$v ??
        new _$ExtensionRequest._(
            id: id, command: command, commandParams: commandParams);
    replace(_$result);
    return _$result;
  }
}

class _$ExtensionResponse extends ExtensionResponse {
  @override
  final int id;
  @override
  final bool success;
  @override
  final String result;
  @override
  final String error;

  factory _$ExtensionResponse(
          [void Function(ExtensionResponseBuilder) updates]) =>
      (new ExtensionResponseBuilder()..update(updates)).build();

  _$ExtensionResponse._({this.id, this.success, this.result, this.error})
      : super._() {
    if (id == null) {
      throw new BuiltValueNullFieldError('ExtensionResponse', 'id');
    }
    if (success == null) {
      throw new BuiltValueNullFieldError('ExtensionResponse', 'success');
    }
    if (result == null) {
      throw new BuiltValueNullFieldError('ExtensionResponse', 'result');
    }
  }

  @override
  ExtensionResponse rebuild(void Function(ExtensionResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExtensionResponseBuilder toBuilder() =>
      new ExtensionResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExtensionResponse &&
        id == other.id &&
        success == other.success &&
        result == other.result &&
        error == other.error;
  }

  @override
  int get hashCode {
    return $jf($jc(
        $jc($jc($jc(0, id.hashCode), success.hashCode), result.hashCode),
        error.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExtensionResponse')
          ..add('id', id)
          ..add('success', success)
          ..add('result', result)
          ..add('error', error))
        .toString();
  }
}

class ExtensionResponseBuilder
    implements Builder<ExtensionResponse, ExtensionResponseBuilder> {
  _$ExtensionResponse _$v;

  int _id;
  int get id => _$this._id;
  set id(int id) => _$this._id = id;

  bool _success;
  bool get success => _$this._success;
  set success(bool success) => _$this._success = success;

  String _result;
  String get result => _$this._result;
  set result(String result) => _$this._result = result;

  String _error;
  String get error => _$this._error;
  set error(String error) => _$this._error = error;

  ExtensionResponseBuilder();

  ExtensionResponseBuilder get _$this {
    if (_$v != null) {
      _id = _$v.id;
      _success = _$v.success;
      _result = _$v.result;
      _error = _$v.error;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExtensionResponse other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExtensionResponse;
  }

  @override
  void update(void Function(ExtensionResponseBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExtensionResponse build() {
    final _$result = _$v ??
        new _$ExtensionResponse._(
            id: id, success: success, result: result, error: error);
    replace(_$result);
    return _$result;
  }
}

class _$ExtensionEvent extends ExtensionEvent {
  @override
  final String params;
  @override
  final String method;

  factory _$ExtensionEvent([void Function(ExtensionEventBuilder) updates]) =>
      (new ExtensionEventBuilder()..update(updates)).build();

  _$ExtensionEvent._({this.params, this.method}) : super._() {
    if (params == null) {
      throw new BuiltValueNullFieldError('ExtensionEvent', 'params');
    }
    if (method == null) {
      throw new BuiltValueNullFieldError('ExtensionEvent', 'method');
    }
  }

  @override
  ExtensionEvent rebuild(void Function(ExtensionEventBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ExtensionEventBuilder toBuilder() =>
      new ExtensionEventBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ExtensionEvent &&
        params == other.params &&
        method == other.method;
  }

  @override
  int get hashCode {
    return $jf($jc($jc(0, params.hashCode), method.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper('ExtensionEvent')
          ..add('params', params)
          ..add('method', method))
        .toString();
  }
}

class ExtensionEventBuilder
    implements Builder<ExtensionEvent, ExtensionEventBuilder> {
  _$ExtensionEvent _$v;

  String _params;
  String get params => _$this._params;
  set params(String params) => _$this._params = params;

  String _method;
  String get method => _$this._method;
  set method(String method) => _$this._method = method;

  ExtensionEventBuilder();

  ExtensionEventBuilder get _$this {
    if (_$v != null) {
      _params = _$v.params;
      _method = _$v.method;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ExtensionEvent other) {
    if (other == null) {
      throw new ArgumentError.notNull('other');
    }
    _$v = other as _$ExtensionEvent;
  }

  @override
  void update(void Function(ExtensionEventBuilder) updates) {
    if (updates != null) updates(this);
  }

  @override
  _$ExtensionEvent build() {
    final _$result =
        _$v ?? new _$ExtensionEvent._(params: params, method: method);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,lines_longer_than_80_chars,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new
