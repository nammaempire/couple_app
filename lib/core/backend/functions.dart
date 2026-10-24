// Server functions (were Firebase callable functions):
// POST /v1/fn/<name> with {"data": ...} → {"result": ...}.

import 'package:couple_app/core/backend/remote.dart';
import 'package:couple_app/core/backend/values.dart';

/// An error from a server function. [code] is e.g. 'failed-precondition'.
class FunctionsException extends DbException {
  FunctionsException(super.code, [super.message, super.details]);
}

class Functions {
  Functions(this.api);

  final ApiClient api;

  static Functions? _instance;
  static Functions get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Functions.instance used before initBackend() ran.');
    }
    return i;
  }

  static set instance(Functions f) => _instance = f;

  /// Calls [name] and returns its result (JSON).
  Future<Object?> call(String name, [Object? data]) async {
    try {
      final res = await api.post('/v1/fn/$name', {'data': encodeValue(data)});
      return res['result'];
    } on DbException catch (e) {
      throw FunctionsException(e.code, e.message, e.details);
    }
  }
}
