import 'dart:async';

import 'package:dwds/src/debugging/remote_debugger.dart';

class EvaluationContext {
  final RemoteDebugger _remoteDebugger;
  final _contexts = <int>[];

  int _id;
  Future<int> get currentId async {
    if (_id != null) return _id;
    for (var context in _contexts) {
      var result =
          await _remoteDebugger.sendCommand('Runtime.evaluate', params: {
        'expression': r'window["$dartAppInstanceId"];',
        'contextId': context,
      });
      if (result.result['result']['value'] != null) {
        _id = context;
        break;
      }
    }
    return _id;
  }

  EvaluationContext(this._id, this._remoteDebugger) {
    _remoteDebugger
        .eventStream('Runtime.executionContextsCleared', (e) => e)
        .listen((_) {
      _contexts.clear();
      _id = null;
    });
    _remoteDebugger
        .eventStream('Runtime.executionContextCreated',
            (e) => int.parse(e.params['context']['id'].toString()))
        .listen(_contexts.add);
  }
}
