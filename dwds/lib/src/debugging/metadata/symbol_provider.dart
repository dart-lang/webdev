// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

// @dart = 2.9

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart' as vm;

import '../../readers/asset_reader.dart';
import 'module_metadata.dart';
import 'module_symbols.dart';

class SymbolTableProvider {
  final AssetReader _assetReader;
  final _logger = Logger('SymbolTableProvider');
  final _symbolTableMemoizer = AsyncMemoizer();
  final SymbolTable _symbolTable = SymbolTable();
  final String entrypoint;

  SymbolTableProvider(this.entrypoint, this._assetReader);

  Future<SymbolTable> get symbolTable async {
    await _symbolTableMemoizer.future;
    return _symbolTable;
  }

  Future<void> initialize(Map<String, ModuleInfo> modules) async {
    await _symbolTableMemoizer.runOnce(() async {
      _logger.info('Loading debug symbols...');
      _logger.info('modules: $modules');

      for (var module in modules.keys) {
        var symbolsPath = modules[module].symbolsPath;
        var symbols = await _assetReader.symbolsContents(symbolsPath);
        if (symbols != null) {
          try {
            var symbolsJson = json.decode(symbols) as Map<String, dynamic>;
            var moduleSymbols = ModuleSymbols.fromJson(symbolsJson);
            _symbolTable._addSymbols(moduleSymbols);
            _logger.fine('Loaded debug symbols for module: $module');
          } catch (e, s) {
            _logger.severe('Failed to read symbols for $module: $e:$s');
            rethrow;
          }
        } else {
          _logger.severe('Cannot find symbols file for $module');
        }
      }
      _symbolTable._validate();
      _logger.info('Loaded debug symbols.');
    });
  }
}

/// A provider of debug symbols read from symbols information stored by DDC.
class SymbolTable {
  final _logger = Logger('SymbolTable');

  final Map<String, LibrarySymbol> libraries = {};
  final Map<String, Script> scripts = {};
  final Map<String, ClassSymbol> classes = {};
  final Map<String, FunctionTypeSymbol> functionTypes = {};
  final Map<String, TypeSymbol> types = {};
  final Map<String, FunctionSymbol> functions = {};
  final Map<String, ScopeSymbol> scopes = {};
  final Map<String, VariableSymbol> variables = {};
  final Map<String, FunctionSymbol> globalFunctions = {};

  static LibrarySymbol _makeBuiltInLibrarySymbol(String uri) => LibrarySymbol(
        name: uri,
        uri: uri,
        dependencies: [],
        scopeIds: [],
        scriptIds: [],
        variableIds: [],
      );

  static ClassSymbol _makeBuiltInClassSymbol(
          String name, String localId, String libraryId) =>
      ClassSymbol(
        name: name,
        localId: localId,
        scopeId: libraryId,
        scopeIds: [],
        variableIds: [],
        interfaceIds: [],
        typeParameters: {},
      );

  static FunctionTypeSymbol _makeBuiltInFunctionTypeSymbol(
          String localId, String libraryId) =>
      FunctionTypeSymbol(
        localId: localId,
        scopeId: libraryId,
        typeParameters: {},
        parameterTypeIds: [],
        namedParameterTypeIds: {},
        optionalParameterTypeIds: [],
      );

  static LibrarySymbol runtimeLibrarySymbol =
      _makeBuiltInLibrarySymbol('dart:_runtime');
  static ClassSymbol typeType =
      _makeBuiltInClassSymbol('Type', '_Type', runtimeLibrarySymbol.id);

  static LibrarySymbol coreLibrarySymbol =
      _makeBuiltInLibrarySymbol('dart:core');
  static ClassSymbol _makeCoreClassSymbol(String name) =>
      _makeBuiltInClassSymbol(name, name, coreLibrarySymbol.id);

  static ClassSymbol doubleType = _makeCoreClassSymbol(vm.InstanceKind.kDouble);
  static ClassSymbol stringType = _makeCoreClassSymbol(vm.InstanceKind.kString);
  static ClassSymbol boolType = _makeCoreClassSymbol(vm.InstanceKind.kBool);
  static ClassSymbol nullType = _makeCoreClassSymbol(vm.InstanceKind.kNull);

  static ClassSymbol getPrimitiveType(String kind) {
    switch (kind) {
      case vm.InstanceKind.kDouble:
        return doubleType;
      case vm.InstanceKind.kString:
        return stringType;
      case vm.InstanceKind.kBool:
        return boolType;
      case vm.InstanceKind.kNull:
        return nullType;
      default:
        throw ArgumentError('Unrecognized primitive instance kind: $kind');
    }
  }

  static ClassSymbol closureType =
      _makeCoreClassSymbol(vm.InstanceKind.kClosure);
  static ClassSymbol linkedMapType = _makeCoreClassSymbol('LinkedMap');
  static ClassSymbol identityMapType = _makeCoreClassSymbol('IdentityMap');
  static ClassSymbol jsArrayType = _makeCoreClassSymbol('JSArray');

  static LibrarySymbol unresolvedLibrary =
      _makeBuiltInLibrarySymbol('unresolved_library');
  static Script unresolvedScript = Script(localId: 'unresolved_script');
  static FunctionTypeSymbol unresolvedFunctionType =
      _makeBuiltInFunctionTypeSymbol('unresolved_function_type', null);
  static ClassSymbol unresolvedClass =
      _makeBuiltInClassSymbol('unresolved_class', 'unresolved_class', null);
  static VariableSymbol unresolvedVariable = VariableSymbol(
      localId: 'unresolved_variable', name: 'unresolved_variable');

  static ScopeSymbol unresolvedScope = unresolvedClass;
  static TypeSymbol unresolvedType = unresolvedClass;

  SymbolTable() {
    // Fake core and runtime types (until we store symbols for sdk)
    classes.addAll({
      typeType.id: typeType,
      doubleType.id: doubleType,
      stringType.id: stringType,
      nullType.id: nullType,
      closureType.id: closureType,
      jsArrayType.id: jsArrayType,
      identityMapType.id: identityMapType,
      linkedMapType.id: linkedMapType,
      unresolvedClass.id: unresolvedClass,
    });
    libraries.addAll({
      coreLibrarySymbol.id: coreLibrarySymbol,
      runtimeLibrarySymbol.id: runtimeLibrarySymbol,
      unresolvedLibrary.id: unresolvedLibrary,
    });
    scripts.addAll({
      unresolvedScript.id: unresolvedScript,
    });
    variables.addAll({
      unresolvedVariable.id: unresolvedVariable,
    });
    functionTypes.addAll({
      unresolvedFunctionType.id: unresolvedFunctionType,
    });
    types
      ..addAll(classes)
      ..addAll(functionTypes);
    scopes
      ..addAll(classes)
      ..addAll(libraries);
  }

  FunctionSymbol getGlobalFunction(String localId) {
    return globalFunctions[localId];
  }

  bool isLibrarySymbol(String id) => libraries.containsKey(id);
  LibrarySymbol getLibrarySymbol(String id) {
    if (isLibrarySymbol(id)) {
      return libraries[id];
    }
    _logger.warning('Unresolved library: $id');
    return unresolvedLibrary;
  }

  bool isScriptSymbol(String id) => scripts.containsKey(id);
  Script getScriptSymbol(String id) {
    if (isScriptSymbol(id)) {
      return scripts[id];
    }
    _logger.warning('Unresolved script: $id');
    return unresolvedScript;
  }

  bool isClassSymbol(String id) => classes.containsKey(id);
  ClassSymbol getClassSymbol(String id) {
    if (isClassSymbol(id)) {
      return classes[id];
    }
    _logger.warning('Unresolved class: $id');
    return unresolvedClass;
  }

  bool isFunctionTypeSymbol(String id) => functionTypes.containsKey(id);
  FunctionTypeSymbol getFunctionTypeSymbol(String id) {
    if (isFunctionTypeSymbol(id)) {
      return functionTypes[id];
    }
    _logger.warning('Unresolved function type: $id');
    return unresolvedFunctionType;
  }

  bool isFunctionSymbol(String id) => functions.containsKey(id);
  FunctionSymbol getFunctionSymbol(String id) {
    return functions.putIfAbsent(id, () {
      // Create symbol for a global function if not resolved.
      // TODO: add enough information to JS to get the scope information
      // of a global function.
      _logger.warning('Unresolved function: $id');
      var symbol = FunctionSymbol(
        localId: id,
        name: id,
        scopeId: unresolvedLibrary.id,
      );
      scopes[symbol.id] = symbol;
      unresolvedLibrary.scopeIds.add(symbol.id);
      return symbol;
    });
  }

  bool isScopeSymbol(String id) => scopes.containsKey(id);
  ScopeSymbol getScopeSymbol(String id) {
    if (isScopeSymbol(id)) {
      return scopes[id];
    }
    _logger.warning('Unresolved scope: $id');
    return unresolvedScope;
  }

  bool isVariableSymbol(String id) => variables.containsKey(id);
  VariableSymbol getVariableSymbol(String id) {
    if (isVariableSymbol(id)) {
      return variables[id];
    }
    _logger.warning('Unresolved variable: $id');
    return unresolvedVariable;
  }

  bool isTypeSymbol(String id) => types.containsKey(id);
  TypeSymbol getTypeSymbol(String id) {
    if (isTypeSymbol(id)) {
      return types[id];
    }
    _logger.warning('Unresolved type: $id');
    return unresolvedType;
  }

  ScopeSymbol getEnclosingScope(Symbol symbol) =>
      getScopeSymbol(symbol.scopeId);

  String displayType(String id) => displayTypeSymbol(getTypeSymbol(id));
  String displayClass(String id) => displayClassSymbol(getClassSymbol(id));
  String displayFunctionType(String id) =>
      displayFunctionTypeSymbol(getFunctionTypeSymbol(id));

  String displayTypeSymbol(TypeSymbol symbol) {
    if (symbol is ClassSymbol) return displayClassSymbol(symbol);
    if (symbol is FunctionTypeSymbol) return displayFunctionTypeSymbol(symbol);
    throw Exception('Unexpected type symbol $symbol');
  }

  String displayClassSymbol(ClassSymbol symbol) {
    var library = getLibrarySymbol(symbol.libraryId);
    var signature = StringBuffer();
    signature.write('${library.uri}|${symbol.name}');
    if (symbol.typeParameters.isNotEmpty) {
      var params = symbol.typeParameters.keys.join(', ');
      signature.write('<$params>');
    }
    return signature.toString();
  }

  String displayFunctionTypeSymbol(FunctionTypeSymbol symbol) {
    var signature = StringBuffer();

    if (symbol.typeParameters.isNotEmpty) {
      var params = symbol.typeParameters.keys.join(', ');
      signature.write('<$params>');
    }
    signature.write('(');
    if (symbol.parameterTypeIds.isNotEmpty) {
      var params = symbol.parameterTypeIds.map(displayType).join(', ');
      signature.write(params);
    }
    if (symbol.optionalParameterTypeIds.isNotEmpty) {
      var params = symbol.optionalParameterTypeIds.map(displayType).join(', ');
      signature.write('[$params]');
    }
    if (symbol.namedParameterTypeIds.isNotEmpty) {
      var map = symbol.namedParameterTypeIds
          .map((k, v) => MapEntry(k, displayType(v)));
      var params = map.keys.map((n) => '$n: ${map[n]}').join(', ');
      signature.write('{$params}');
    }
    var returnType = displayType(symbol.returnTypeId);
    signature.write(') => $returnType');
    return signature.toString();
  }

  // TODO: ideally we just use field.localId as js id
  // Need to replace use of symbols by strings in ddc for that.
  String getJsFieldId(VariableSymbol symbol) {
    if (symbol.name.startsWith('_')) {
      return 'Symbol(${symbol.name})';
    }
    var cls = getEnclosingScope(symbol) as ClassSymbol;
    return 'Symbol(${cls.name}.${symbol.name})';
  }

  /// Collect all dart variables in scope at the current position.
  ///
  /// Given the current scope represented by [symbol], and a location
  /// [tokenPos], walk the scope chain starting from the library
  /// and ending by the innermost scope, collecting all variables in
  /// scope (i.e. defined in the scope chain above the [tokenPos]).
  List<VariableSymbol> getVariablesInScope(ScopeSymbol symbol, int tokenPos) {
    bool isInScope(VariableSymbol variable, int tokenPos) {
      return (variable.kind != VariableSymbolKind.formal &&
              variable.kind != VariableSymbolKind.local) ||
          variable.location.endTokenPos < tokenPos;
    }

    var variables = <VariableSymbol>[];
    var scopeChain = <ScopeSymbol>[];
    for (var current = symbol;
        current != null;
        current = getEnclosingScope(current)) {
      scopeChain.add(current);
    }
    // Make the scope chain start from the outermost scope (library).
    scopeChain = scopeChain.reversed.toList();

    // Collect variables in scope above tokenPos,
    // starting from the outermost scope.
    for (var scope in scopeChain) {
      for (var id in scope.variableIds) {
        var variable = getVariableSymbol(id);
        if (isInScope(variable, tokenPos)) {
          variables.add(variable);
        }
      }
    }
    return variables;
  }

  void _addSymbols(ModuleSymbols symbols) {
    // TODO: skip null ids in ddc during symbol generation
    for (var element in symbols.libraries) {
      if (element.localId != null) {
        if (libraries.containsKey(element.id)) {
          throw Exception('Library already added: ${element.id}');
        }
        libraries[element.id] = element;
        scopes[element.id] = element;
      }
    }
    for (var element in symbols.scripts) {
      if (element.localId != null) {
        if (scripts.containsKey(element.id)) {
          throw Exception('Script already added: ${element.id}');
        }
        scripts[element.id] = element;
      }
    }
    for (var element in symbols.classes) {
      if (element.localId != null) {
        if (classes.containsKey(element.id)) {
          throw Exception('Class already added: ${element.id}');
        }
        classes[element.id] = element;
        scopes[element.id] = element;
        types[element.id] = element;
      }
    }
    for (var element in symbols.functionTypes) {
      if (element.localId != null) {
        functionTypes[element.id] = element;
        types[element.id] = element;
      }
    }
    for (var element in symbols.functions) {
      if (element.localId != null) {
        if (functions.containsKey(element.id)) {
          throw Exception('Function already added: ${element.id}');
        }
        functions[element.id] = element;
        scopes[element.id] = element;

        if (isLibrarySymbol(element.scopeId)) {
          if (globalFunctions.containsKey(element.localId)) {
            var previous = globalFunctions[element.localId];
            _logger.warning(
                'Overriding ${previous.id} with ${element.id} for global function lookup.');
          }
          globalFunctions[element.localId] = element;
        }
      }
    }
    for (var element in symbols.scopes) {
      if (element.localId != null) {
        if (scopes.containsKey(element.id)) {
          throw Exception('Scope already added: ${element.id}');
        }
        scopes[element.id] = element;
      }
    }
    for (var element in symbols.variables) {
      if (element.localId != null) {
        if (variables.containsKey(element.id)) {
          throw Exception('Variable already added: ${element.id}');
        }
        variables[element.id] = element;
      }
    }
  }

  void _validate() {
    for (var e in scopes.values) {
      if (e.scopeId != null && !scopes.containsKey(e.scopeId)) {
        _logger.warning('Unresolved encosing scope reference ${e.scopeId}');
      }
      for (var id in e.scopeIds) {
        if (!scopes.containsKey(id)) {
          _logger.warning('Unresolved scope reference $id');
        }
      }
      for (var id in e.variableIds) {
        if (!variables.containsKey(id)) {
          _logger.warning('Unresolved variable reference $id');
        }
      }
    }
    for (var e in functionTypes.values) {
      if (e.scopeId != null && !scopes.containsKey(e.scopeId)) {
        _logger.warning('Unresolved encosing scope reference ${e.scopeId}');
      }
      for (var id in e.namedParameterTypeIds.values) {
        if (!types.containsKey(id)) {
          _logger.warning('Unresolved named parameter type reference $id');
        }
      }
      for (var id in e.parameterTypeIds) {
        if (!types.containsKey(id)) {
          _logger.warning('Unresolved parameter type reference $id');
        }
      }
      for (var id in e.optionalParameterTypeIds) {
        if (!types.containsKey(id)) {
          _logger.warning('Unresolved optional type reference $id');
        }
      }
    }
    for (var e in classes.values) {
      if (e.scopeId != null && !scopes.containsKey(e.scopeId)) {
        _logger.warning('Unresolved encosing scope reference ${e.scopeId}');
      }
      for (var id in e.interfaceIds) {
        if (!types.containsKey(id)) {
          _logger.warning('Unresolved interface reference $id');
        }
      }
      if (e.superClassId != null && !types.containsKey(e.superClassId)) {
        _logger.warning('Unresolved superclass reference ${e.superClassId}');
      }
    }
  }
}
