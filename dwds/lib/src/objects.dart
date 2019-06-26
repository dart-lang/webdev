import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class Property {
  final Map<String, dynamic> _map;

  Property(this._map);

  Map<String, dynamic> get rawData => _map;

  /// Remote object value in case of primitive values or JSON values (if it was
  /// requested). (optional)
  RemoteObject get value => RemoteObject(_map['value'] as Map<String, dynamic>);

  /// Name of the property
  String get name => _map['name'] as String;
  
  @override
  String toString() => '$name $value';
}
