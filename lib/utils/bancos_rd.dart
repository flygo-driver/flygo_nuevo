/// Bancos y asociaciones de ahorro y préstamo operativos en República Dominicana.
abstract final class BancosRd {
  BancosRd._();

  static const List<String> nombres = <String>[
    'Asociación Cibao',
    'Asociación La Nacional',
    'Asociación Mocana',
    'Asociación Peravia',
    'Asociación Popular (APAP)',
    'Asociación Romana',
    'Banco Ademi',
    'Banco Atlántico',
    'Banco BDI',
    'Banco BHD León',
    'Banco Banesco',
    'Banco Caribe',
    'Banco de Reservas',
    'Banco Empire',
    'Banco López de Haro',
    'Banco Múltiple Activo',
    'Banco Popular Dominicano',
    'Banco Promerica',
    'Banco Santa Cruz',
    'Banco Scotiabank',
    'Banco Unión',
    'Banco Vimenca',
    'Citibank',
    'Qik Banco Digital',
  ];

  static const List<String> tiposCuentaGira = <String>[
    'Ahorros',
    'Corriente',
  ];
}

/// Pueblos/ciudades para filtro y origen de giras (catálogo cliente).
abstract final class PoolGiraPueblosOrigen {
  PoolGiraPueblosOrigen._();

  static const List<String> opciones = <String>[
    'Santo Domingo',
    'Santiago',
    'La Romana',
    'Higüey',
    'San Pedro de Macorís',
    'San Cristóbal',
    'Puerto Plata',
    'La Vega',
    'Barahona',
    'Moca',
    'Bonao',
    'San Francisco de Macorís',
  ];
}
