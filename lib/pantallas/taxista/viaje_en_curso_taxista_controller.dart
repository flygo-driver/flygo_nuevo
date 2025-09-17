import 'package:flutter/material.dart';

class ViajeEnCursoTaxistaController with ChangeNotifier {
  bool completando = false;

  void setCompletando(bool v) {
    completando = v;
    notifyListeners();
  }
}
