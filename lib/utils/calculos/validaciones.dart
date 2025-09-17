class Validaciones {
  static String? campoObligatorio(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Este campo es obligatorio';
    }
    return null;
  }

  static String? validarTelefono(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El teléfono es obligatorio';
    }
    if (!RegExp(r'^\d{10,12}$').hasMatch(valor)) {
      return 'Teléfono inválido';
    }
    return null;
  }

  static String? validarCorreo(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El correo es obligatorio';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(valor)) {
      return 'Correo inválido';
    }
    return null;
  }
}
