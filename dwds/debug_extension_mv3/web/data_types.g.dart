// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_types.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializer<DevToolsOpener> _$devToolsOpenerSerializer =
    new _$DevToolsOpenerSerializer();

class _$DevToolsOpenerSerializer
    implements StructuredSerializer<DevToolsOpener> {
  @override
  final Iterable<Type> types = const [DevToolsOpener, _$DevToolsOpener];
  @override
  final String wireName = 'DevToolsOpener';

  @override
  Iterable<Object?> serialize(Serializers serializers, DevToolsOpener object,
      {FullType specifiedType = FullType.unspecified}) {
    final result = <Object?>[
      'newWindow',
      serializers.serialize(object.newWindow,
          specifiedType: const FullType(bool)),
    ];

    return result;
  }

  @override
  DevToolsOpener deserialize(
      Serializers serializers, Iterable<Object?> serialized,
      {FullType specifiedType = FullType.unspecified}) {
    final result = new DevToolsOpenerBuilder();

    final iterator = serialized.iterator;
    while (iterator.moveNext()) {
      final key = iterator.current! as String;
      iterator.moveNext();
      final Object? value = iterator.current;
      switch (key) {
        case 'newWindow':
          result.newWindow = serializers.deserialize(value,
              specifiedType: const FullType(bool))! as bool;
          break;
      }
    }

    return result.build();
  }
}

class _$DevToolsOpener extends DevToolsOpener {
  @override
  final bool newWindow;

  factory _$DevToolsOpener([void Function(DevToolsOpenerBuilder)? updates]) =>
      (new DevToolsOpenerBuilder()..update(updates))._build();

  _$DevToolsOpener._({required this.newWindow}) : super._() {
    BuiltValueNullFieldError.checkNotNull(
        newWindow, r'DevToolsOpener', 'newWindow');
  }

  @override
  DevToolsOpener rebuild(void Function(DevToolsOpenerBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DevToolsOpenerBuilder toBuilder() =>
      new DevToolsOpenerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DevToolsOpener && newWindow == other.newWindow;
  }

  @override
  int get hashCode {
    return $jf($jc(0, newWindow.hashCode));
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DevToolsOpener')
          ..add('newWindow', newWindow))
        .toString();
  }
}

class DevToolsOpenerBuilder
    implements Builder<DevToolsOpener, DevToolsOpenerBuilder> {
  _$DevToolsOpener? _$v;

  bool? _newWindow;
  bool? get newWindow => _$this._newWindow;
  set newWindow(bool? newWindow) => _$this._newWindow = newWindow;

  DevToolsOpenerBuilder();

  DevToolsOpenerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _newWindow = $v.newWindow;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DevToolsOpener other) {
    ArgumentError.checkNotNull(other, 'other');
    _$v = other as _$DevToolsOpener;
  }

  @override
  void update(void Function(DevToolsOpenerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DevToolsOpener build() => _build();

  _$DevToolsOpener _build() {
    final _$result = _$v ??
        new _$DevToolsOpener._(
            newWindow: BuiltValueNullFieldError.checkNotNull(
                newWindow, r'DevToolsOpener', 'newWindow'));
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: always_put_control_body_on_new_line,always_specify_types,annotate_overrides,avoid_annotating_with_dynamic,avoid_as,avoid_catches_without_on_clauses,avoid_returning_this,deprecated_member_use_from_same_package,lines_longer_than_80_chars,no_leading_underscores_for_local_identifiers,omit_local_variable_types,prefer_expression_function_bodies,sort_constructors_first,test_types_in_equals,unnecessary_const,unnecessary_new,unnecessary_lambdas
