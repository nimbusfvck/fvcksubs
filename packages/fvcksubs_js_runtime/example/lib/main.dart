import 'package:flutter/material.dart';

import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final JsEngine _engine;
  late final String _evalResult;
  late final String _hostCallResult;

  @override
  void initState() {
    super.initState();
    _engine = JsEngine();
    _engine.setHostFunction((name, argsJson) {
      return '{"name":"$name","echo":$argsJson}';
    });
    _evalResult = _engine.eval('1 + 2 * 3');
    _hostCallResult = _engine.eval(
      '__host_call("greet", JSON.stringify({who: "device"}))',
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('QuickJS runtime PoC')),
        body: SingleChildScrollView(
          child: Container(
            padding: const .all(10),
            child: Column(
              children: [
                const Text(
                  'A vendored, build-owned QuickJS-ng engine, compiled for '
                  'this platform by a native_toolchain_c build hook and '
                  'called through dart:ffi.',
                  style: textStyle,
                  textAlign: .center,
                ),
                spacerSmall,
                Text(
                  'eval("1 + 2 * 3") = $_evalResult',
                  style: textStyle,
                  textAlign: .center,
                ),
                spacerSmall,
                Text(
                  'JS → Dart → JS host call = $_hostCallResult',
                  style: textStyle,
                  textAlign: .center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
