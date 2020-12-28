/// {@template mocktail_failure}
/// An exception thrown from the mocktail library.
/// {@endtemplate}
class MocktailFailure implements Exception {
  /// {@macro mocktail_failure}
  const MocktailFailure(this.message);

  /// The failure message
  final String message;
}

/// {@template mock}
/// Extend this class to mark an implementation as a [Mock].
///
/// A mocked class implements all fields and methods with a default
/// implementation that does not throw a [NoSuchMethodError], and may be further
/// customized at runtime to define how it may behave using [when].
/// ````dart
/// // Real class.
/// class Cat {
///   String getSound(String suffix) => 'Meow$suffix';
/// }
///
/// // Mock class.
/// class MockCat extends Mock implements Cat {}
///
/// void main() {
///   // Create a mock Cat at runtime.
///   final cat = MockCat();
///
///   // When 'getSound' is called, return 'Woof'
///   when(cat).calls('getSound').thenReturn('Woof');
///
///   // Try making a Cat sound...
///   print(cat.getSound('foo')); // Prints 'Woof'
/// }
/// ```
///
/// A class which `extends Mock` should not have any directly implemented
/// overridden fields or methods. These fields would not be usable as a [Mock]
/// with [verify] or [when].
/// {@endtemplate}
class Mock {
  final _stubs = <_Invocation, _Stub>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final _invocationStrict = _Invocation(
      memberName: invocation.memberName,
      positionalArgs: List.of(invocation.positionalArguments),
      namedArgs: Map.of(invocation.namedArguments),
    );
    final _invocationLax = _Invocation(memberName: invocation.memberName);

    if (_stubs.containsKey(_invocationStrict)) {
      return _stubs[_invocationStrict]!.result();
    }
    if (_stubs.containsKey(_invocationLax)) {
      return _stubs[_invocationLax]!.result();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Create a stub method response.
///
/// Call a method on a mock object within the call to `when`, and call a
/// canned response method on the result. For example:
///
/// ```dart
/// when(cat).calls('eatFood').withArgs(positional: ["fish"]).thenReturn(true);
/// ```
///
/// Mocktail will store the stub for `cat.eatFood`, and pair the exact
/// arguments given with the response. When `cat.eatFood` is called,
/// Mocktail will respond with the stubbed response
/// if it can match the mock method parameters.
///
/// The response generators include `thenReturn`, `thenAnswer`, and `thenThrow`.
_WhenCall when(Object object) {
  if (object is! Mock) {
    throw StateError('when called on a real object.');
  }
  return _WhenCall(object);
}

/// Verify that a method on a mock object was called with the given arguments.
///
/// Call a method on a mock object within the call to `verify`.
///
/// ```dart
/// cat.eatFood("chicken");
/// verify(cat).calls("eatFood").withArgs(positional: ["chicken"]).times(1);
/// ```
///
/// Mocktail will fail the current test case if `cat.eatFood`
/// has not been called with `"chicken"`.
_VerifyCall verify(Object object) {
  if (object is! Mock) {
    throw StateError('verify called on a real object.');
  }
  return _VerifyCall(object);
}

/// Verifies that all stubs were used.
/// It is generally recommended to call `verifyMocks`
/// in the `tearDown` in order to ensure that all stubs
/// were invoked.
void verifyMocks(Object object) {
  if (object is! Mock) {
    throw StateError('verifyMocks called on a real object.');
  }
  for (final entry in object._stubs.entries) {
    if (entry.value.callCount == 0) {
      throw MocktailFailure(
        '''${object.runtimeType}.${entry.key.memberName} => ${entry.value._result()} was stubbed but never invoked''',
      );
    }
  }
}

/// Reset the state of the mock, typically for use between tests.
void reset(Object object) {
  if (object is! Mock) {
    throw StateError('reset called on a real object.');
  }
  object._stubs.clear();
}

class _Invocation {
  const _Invocation({
    required this.memberName,
    this.positionalArgs = const [],
    this.namedArgs = const {},
  });

  final Symbol memberName;
  final Iterable<Object?> positionalArgs;
  final Map<Symbol, Object?> namedArgs;

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is _Invocation &&
        o.memberName == memberName &&
        _listEquals(o.positionalArgs.toList(), positionalArgs.toList()) &&
        _mapEquals(o.namedArgs, namedArgs);
  }

  @override
  int get hashCode {
    final positionalArgsHash = positionalArgs.fold<int>(
        0, (previous, element) => previous ^ element.hashCode);
    final namedArgsHash = namedArgs.entries.fold<int>(0, (previous, element) {
      return previous ^ element.key.hashCode ^ element.value.hashCode;
    });
    return memberName.hashCode ^ positionalArgsHash ^ namedArgsHash;
  }
}

class _Stub {
  _Stub(this._result);

  final Object? Function() _result;
  Object? result() {
    _callCount++;
    return _result();
  }

  int _callCount = 0;
  int get callCount => _callCount;
}

class _WhenCall {
  const _WhenCall(this._object);
  final Mock _object;

  _StubFunction calls(String memberName) => _StubFunction(_object, memberName);
}

class _VerifyCall {
  const _VerifyCall(this._object);
  final Mock _object;

  _VerifyArgsCall calls(String memberName) =>
      _VerifyArgsCall(_object, memberName);
}

class _VerifyArgsCall extends _CallCountCall {
  _VerifyArgsCall(
    Mock object,
    String memberName, {
    Iterable<Object?>? positionalArgs,
    Map<String, Object?>? namedArgs,
  }) : super(object, memberName,
            positionalArgs: positionalArgs, namedArgs: namedArgs);

  _CallCountCall withArgs({
    Iterable<Object?>? positional,
    Map<String, Object?>? named,
  }) {
    return _CallCountCall(
      _object,
      _memberName,
      positionalArgs: positional,
      namedArgs: named,
    );
  }
}

class _CallCountCall extends _MockInvocationCall {
  _CallCountCall(
    Mock object,
    String memberName, {
    Iterable<Object?>? positionalArgs,
    Map<String, Object?>? namedArgs,
  }) : super(object, memberName,
            positionalArgs: positionalArgs, namedArgs: namedArgs);

  void times(int callCount) {
    var actualCallCount = 0;

    // Lax Invocation Verification (any)
    if (_positionalArgs == null && _namedArgs == null) {
      for (final entry in _object._stubs.entries) {
        if (entry.key.memberName == Symbol(_memberName)) {
          actualCallCount += entry.value.callCount;
        }
      }
    }
    // Strict Invocation Verification
    else {
      final stub = _object._stubs[_invocation] ??
          _object._stubs[_Invocation(memberName: Symbol(_memberName))];
      actualCallCount = stub?.callCount ?? 0;
    }

    if (actualCallCount != callCount) {
      throw MocktailFailure(
        '''Expected ${_object.runtimeType}.$_memberName to be called $callCount time(s) but actual call count was $actualCallCount.''',
      );
    }
  }
}

class _StubFunction extends _MockInvocationCall {
  _StubFunction(
    Mock object,
    String memberName, {
    Iterable<Object?>? positionalArgs,
    Map<String, Object?>? namedArgs,
  }) : super(object, memberName,
            positionalArgs: positionalArgs, namedArgs: namedArgs);

  _StubFunction withArgs({
    Iterable<Object?>? positional,
    Map<String, Object?>? named,
  }) {
    return _StubFunction(
      _object,
      _memberName,
      positionalArgs: positional,
      namedArgs: named,
    );
  }

  void thenReturn(Object? result) {
    _object._stubs[_invocation] = _Stub(() => result);
  }

  void thenAnswer(Object? Function(_Invocation) callback) {
    _object._stubs[_invocation] = _Stub(() => callback(_invocation));
  }

  void thenThrow(Object throwable) {
    // ignore: only_throw_errors
    _object._stubs[_invocation] = _Stub(() => throw throwable);
  }
}

class _MockInvocationCall {
  _MockInvocationCall(
    this._object,
    this._memberName, {
    Iterable<Object?>? positionalArgs,
    Map<String, Object?>? namedArgs,
  })  : _positionalArgs = positionalArgs,
        _namedArgs = namedArgs;

  final Mock _object;
  final String _memberName;
  final Iterable<Object?>? _positionalArgs;
  final Map<String, Object?>? _namedArgs;

  _Invocation get _invocation {
    if (_positionalArgs == null && _namedArgs == null) {
      return _Invocation(memberName: Symbol(_memberName));
    }
    if (_positionalArgs != null && _namedArgs == null) {
      return _Invocation(
        memberName: Symbol(_memberName),
        positionalArgs: _positionalArgs!,
      );
    }
    if (_positionalArgs == null && _namedArgs != null) {
      return _Invocation(
        memberName: Symbol(_memberName),
        namedArgs: _namedArgs!.map<Symbol, Object?>(
          (key, value) => MapEntry(Symbol(key), value),
        ),
      );
    }
    return _Invocation(
      memberName: Symbol(_memberName),
      positionalArgs: _positionalArgs!,
      namedArgs: _namedArgs!.map<Symbol, Object?>(
        (key, value) => MapEntry(Symbol(key), value),
      ),
    );
  }
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _mapEquals<T, U>(Map<T, U>? a, Map<T, U>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) {
      return false;
    }
  }
  return true;
}
