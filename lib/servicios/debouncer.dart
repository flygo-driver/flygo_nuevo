import 'dart:async';

class Debouncer {
  Debouncer({this.ms = 350});
  final int ms;
  Timer? _t;
  void run(void Function() f) {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: ms), f);
  }

  void dispose() => _t?.cancel();
}
