// lib/servicios/turismo_catalogo_rd.dart
// ✅ Catálogo TURISMO RD (tap-to-select, sin escribir)
// ✅ Actualizado con descripcion, imagen y popularidad para el buscador

class TurismoLugar {
  final String id; // único (para UI)
  final String nombre; // lo que ve el cliente
  final String ciudad; // Santo Domingo / Punta Cana / etc.
  final String subtipo; // AEROPUERTO, PLAYA, ZONA_COLONIAL, MUELLE, TOUR, etc.
  final double lat;
  final double lon;

  // ✅ NUEVOS CAMPOS (opcionales pero necesarios para el selector)
  final String? descripcion;
  final String? imagen;
  final int popularidad;

  const TurismoLugar({
    required this.id,
    required this.nombre,
    required this.ciudad,
    required this.subtipo,
    required this.lat,
    required this.lon,
    this.descripcion, // ✅ Agregado
    this.imagen, // ✅ Agregado
    this.popularidad = 0, // ✅ Agregado con valor por defecto
  });

  String get label => '$nombre • $ciudad';
}

class TurismoCatalogoRD {
  // ==========================
  // ✅ SUBTIPOS soportados
  // ==========================
  static const String aeropuerto = 'AEROPUERTO';
  static const String muelle = 'MUELLE';
  static const String zonaColonial = 'ZONA_COLONIAL';
  static const String ciudad = 'CIUDAD';
  static const String playa = 'PLAYA';
  static const String resort = 'RESORT';
  static const String hotel = 'HOTEL';
  static const String tour = 'TOUR';
  static const String parque = 'PARQUE';
  static const String montana = 'MONTANA';
  static const String cascada = 'CASCADA';
  static const String lago = 'LAGO';
  static const String museo = 'MUSEO';
  static const String atraccion = 'ATRACCION';

  // ==========================
  // ✅ LISTA GLOBAL (MUY COMPLETA) - AHORA CON DESCRIPCIÓN
  // ==========================
  static const List<TurismoLugar> lugares = [
    // ==========================
    // AEROPUERTOS RD (principales)
    // ==========================
    TurismoLugar(
      id: 'a_sdq',
      nombre: 'Aeropuerto Las Américas (SDQ)',
      ciudad: 'Santo Domingo',
      subtipo: aeropuerto,
      lat: 18.429664,
      lon: -69.668925,
      descripcion: 'Principal aeropuerto internacional de Santo Domingo',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'a_jbq',
      nombre: 'Aeropuerto La Isabela (JBQ)',
      ciudad: 'Santo Domingo',
      subtipo: aeropuerto,
      lat: 18.572476,
      lon: -69.985603,
      descripcion: 'Aeropuerto para vuelos domésticos y aviación general',
      popularidad: 80,
    ),
    TurismoLugar(
      id: 'a_puj',
      nombre: 'Aeropuerto Punta Cana (PUJ)',
      ciudad: 'Punta Cana',
      subtipo: aeropuerto,
      lat: 18.567367,
      lon: -68.363431,
      descripcion: 'El aeropuerto más transitado del Caribe',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'a_sti',
      nombre: 'Aeropuerto Cibao (STI)',
      ciudad: 'Santiago',
      subtipo: aeropuerto,
      lat: 19.406093,
      lon: -70.604687,
      descripcion: 'Principal aeropuerto de la región del Cibao',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'a_pop',
      nombre: 'Aeropuerto Puerto Plata (POP)',
      ciudad: 'Puerto Plata',
      subtipo: aeropuerto,
      lat: 19.757900,
      lon: -70.569900,
      descripcion: 'Aeropuerto internacional de Puerto Plata',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'a_azs',
      nombre: 'Aeropuerto Samaná El Catey (AZS)',
      ciudad: 'Samaná',
      subtipo: aeropuerto,
      lat: 19.270600,
      lon: -69.737900,
      descripcion: 'Aeropuerto que sirve a la península de Samaná',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'a_lrm',
      nombre: 'Aeropuerto La Romana (LRM)',
      ciudad: 'La Romana',
      subtipo: aeropuerto,
      lat: 18.450700,
      lon: -68.911800,
      descripcion: 'Aeropuerto internacional de La Romana',
      popularidad: 85,
    ),

    // ==========================
    // MUELLES / PUERTOS / CRUCEROS
    // ==========================
    TurismoLugar(
      id: 'm_amber_cove',
      nombre: 'Amber Cove (Cruceros)',
      ciudad: 'Puerto Plata',
      subtipo: muelle,
      lat: 19.827900,
      lon: -70.709200,
      descripcion: 'Puerto de cruceros con instalaciones turísticas',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'm_taino_bay',
      nombre: 'Taíno Bay (Cruceros)',
      ciudad: 'Puerto Plata',
      subtipo: muelle,
      lat: 19.789500,
      lon: -70.691900,
      descripcion: 'Nuevo puerto de cruceros en el centro de Puerto Plata',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'm_la_romana',
      nombre: 'Puerto de Cruceros',
      ciudad: 'La Romana',
      subtipo: muelle,
      lat: 18.427900,
      lon: -68.951200,
      descripcion: 'Puerto de cruceros en La Romana',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'm_samana',
      nombre: 'Muelle / Puerto',
      ciudad: 'Samaná',
      subtipo: muelle,
      lat: 19.205300,
      lon: -69.332300,
      descripcion: 'Puerto principal de Samaná para ferris y tours',
      popularidad: 80,
    ),
    TurismoLugar(
      id: 'm_santo_domingo',
      nombre: 'Puerto de Santo Domingo',
      ciudad: 'Santo Domingo',
      subtipo: muelle,
      lat: 18.467900,
      lon: -69.880900,
      descripcion: 'Puerto Don Diego en la Zona Colonial',
      popularidad: 85,
    ),

    // ==========================
    // ZONA COLONIAL (top puntos)
    // ==========================
    TurismoLugar(
      id: 'zc_zona_colonial',
      nombre: 'Zona Colonial',
      ciudad: 'Santo Domingo',
      subtipo: zonaColonial,
      lat: 18.471900,
      lon: -69.885600,
      descripcion:
          'Centro histórico de Santo Domingo, Patrimonio de la Humanidad',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'zc_parque_colon',
      nombre: 'Parque Colón',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.472300,
      lon: -69.883900,
      descripcion: 'Plaza principal de la Zona Colonial con estatua de Colón',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'zc_catedral',
      nombre: 'Catedral Primada de América',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.472000,
      lon: -69.883100,
      descripcion: 'Primera catedral construida en América',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'zc_alcazar',
      nombre: 'Alcázar de Colón',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.477000,
      lon: -69.881600,
      descripcion: 'Palacio de Diego Colón, hijo de Cristóbal Colón',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'zc_plaza_espana',
      nombre: 'Plaza España',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.477900,
      lon: -69.881100,
      descripcion: 'Plaza frente al Alcázar con restaurantes y bares',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'zc_las_damas',
      nombre: 'Calle Las Damas',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.476200,
      lon: -69.880700,
      descripcion: 'Calle más antigua del Nuevo Mundo',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'zc_fortaleza_ozama',
      nombre: 'Fortaleza Ozama',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.474900,
      lon: -69.881900,
      descripcion: 'Fortaleza militar más antigua de América',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'zc_panteon',
      nombre: 'Panteón Nacional',
      ciudad: 'Zona Colonial',
      subtipo: zonaColonial,
      lat: 18.475300,
      lon: -69.880400,
      descripcion: 'Mausoleo que alberga restos de héroes nacionales',
      popularidad: 85,
    ),

    // ==========================
    // SANTO DOMINGO (atracciones)
    // ==========================
    TurismoLugar(
      id: 'sd_tres_ojos',
      nombre: 'Los Tres Ojos',
      ciudad: 'Santo Domingo',
      subtipo: atraccion,
      lat: 18.445900,
      lon: -69.857200,
      descripcion: 'Parque nacional con lagunas subterráneas',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'sd_faro_colon',
      nombre: 'Faro a Colón',
      ciudad: 'Santo Domingo',
      subtipo: atraccion,
      lat: 18.481100,
      lon: -69.870800,
      descripcion: 'Monumento y museo en forma de cruz',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'sd_malecon',
      nombre: 'Malecón de Santo Domingo',
      ciudad: 'Santo Domingo',
      subtipo: ciudad,
      lat: 18.456000,
      lon: -69.931000,
      descripcion: 'Avenida costera con restaurantes y bares',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'sd_jardin_botanico',
      nombre: 'Jardín Botánico Nacional',
      ciudad: 'Santo Domingo',
      subtipo: parque,
      lat: 18.496100,
      lon: -69.951300,
      descripcion: 'Extenso jardín botánico con diversas especies',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'sd_acuario',
      nombre: 'Acuario Nacional',
      ciudad: 'Santo Domingo',
      subtipo: atraccion,
      lat: 18.460800,
      lon: -69.894200,
      descripcion: 'Acuario con especies marinas del Caribe',
      popularidad: 80,
    ),

    // ==========================
    // PLAYAS cerca de SD
    // ==========================
    TurismoLugar(
      id: 'p_boca_chica',
      nombre: 'Playa Boca Chica',
      ciudad: 'Boca Chica',
      subtipo: playa,
      lat: 18.451600,
      lon: -69.606300,
      descripcion: 'Playa popular cerca de Santo Domingo con aguas tranquilas',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'p_juan_dolio',
      nombre: 'Playa Juan Dolio',
      ciudad: 'Juan Dolio',
      subtipo: playa,
      lat: 18.427500,
      lon: -69.423600,
      descripcion: 'Zona playera con hoteles y restaurantes',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'p_guayacanes',
      nombre: 'Playa Guayacanes',
      ciudad: 'San Pedro de Macorís',
      subtipo: playa,
      lat: 18.418900,
      lon: -69.373700,
      descripcion: 'Playa tranquila al este de Juan Dolio',
      popularidad: 80,
    ),

    // =========================================================
    // PUNTA CANA / BÁVARO / CAP CANA / HIGÜEY / MICHES
    // =========================================================
    TurismoLugar(
      id: 'pc_z_punta_cana',
      nombre: 'Zona Punta Cana (Centro)',
      ciudad: 'Punta Cana',
      subtipo: resort,
      lat: 18.560000,
      lon: -68.370000,
      descripcion: 'Principal zona turística de Punta Cana',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'pc_z_bavaro',
      nombre: 'Zona Bávaro',
      ciudad: 'Bávaro',
      subtipo: resort,
      lat: 18.651300,
      lon: -68.445800,
      descripcion: 'Área de Bávaro con numerosos resorts',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'pc_z_cap_cana',
      nombre: 'Zona Cap Cana',
      ciudad: 'Cap Cana',
      subtipo: resort,
      lat: 18.512400,
      lon: -68.372500,
      descripcion: 'Exclusiva zona residencial y turística',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pc_z_uvero_alto',
      nombre: 'Zona Uvero Alto',
      ciudad: 'Uvero Alto',
      subtipo: resort,
      lat: 18.722600,
      lon: -68.400400,
      descripcion: 'Zona de resorts al norte de Bávaro',
      popularidad: 90,
    ),

    TurismoLugar(
      id: 'pc_playa_bavaro',
      nombre: 'Playa Bávaro',
      ciudad: 'Bávaro',
      subtipo: playa,
      lat: 18.661800,
      lon: -68.403800,
      descripcion: 'Una de las playas más hermosas del Caribe',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'pc_playa_macao',
      nombre: 'Playa Macao',
      ciudad: 'Macao',
      subtipo: playa,
      lat: 18.772900,
      lon: -68.569900,
      descripcion: 'Playa pública ideal para surf',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pc_playa_juanillo',
      nombre: 'Playa Juanillo',
      ciudad: 'Cap Cana',
      subtipo: playa,
      lat: 18.462900,
      lon: -68.377600,
      descripcion: 'Playa exclusiva en Cap Cana',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pc_playa_bibijagua',
      nombre: 'Playa Bibijagua',
      ciudad: 'Bávaro',
      subtipo: playa,
      lat: 18.653700,
      lon: -68.396700,
      descripcion: 'Playa con ambiente familiar',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'pc_playa_cortecito',
      nombre: 'Playa El Cortecito',
      ciudad: 'Bávaro',
      subtipo: playa,
      lat: 18.685400,
      lon: -68.412500,
      descripcion: 'Playa con restaurantes y tiendas',
      popularidad: 90,
    ),

    TurismoLugar(
      id: 'pc_hoyo_azul',
      nombre: 'Hoyo Azul',
      ciudad: 'Cap Cana',
      subtipo: tour,
      lat: 18.525700,
      lon: -68.410800,
      descripcion: 'Cenote de aguas turquesas en Scape Park',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pc_scape_park',
      nombre: 'Scape Park (Cap Cana)',
      ciudad: 'Cap Cana',
      subtipo: tour,
      lat: 18.524500,
      lon: -68.410100,
      descripcion: 'Parque ecológico con aventuras',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pc_dolphin_island',
      nombre: 'Dolphin Island (Zona Bávaro)',
      ciudad: 'Bávaro',
      subtipo: tour,
      lat: 18.664900,
      lon: -68.382600,
      descripcion: 'Experiencia de nado con delfines',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'pc_buggies',
      nombre: 'Buggies / ATV (Tour)',
      ciudad: 'Punta Cana',
      subtipo: tour,
      lat: 18.646400,
      lon: -68.505500,
      descripcion: 'Tours en buggies por campos y playas',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'pc_coco_bongo',
      nombre: 'Coco Bongo Punta Cana',
      ciudad: 'Punta Cana',
      subtipo: atraccion,
      lat: 18.679500,
      lon: -68.425300,
      descripcion: 'Famoso show y discoteca',
      popularidad: 95,
    ),

    TurismoLugar(
      id: 'hig_basilica',
      nombre: 'Basílica Nuestra Señora de la Altagracia',
      ciudad: 'Higüey',
      subtipo: ciudad,
      lat: 18.616400,
      lon: -68.708000,
      descripcion: 'Importante centro de peregrinación religiosa',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'hig_centro',
      nombre: 'Centro de Higüey',
      ciudad: 'Higüey',
      subtipo: ciudad,
      lat: 18.615300,
      lon: -68.707600,
      descripcion: 'Ciudad de Higüey, capital de La Altagracia',
      popularidad: 85,
    ),

    TurismoLugar(
      id: 'mic_miches',
      nombre: 'Centro de Miches',
      ciudad: 'Miches',
      subtipo: ciudad,
      lat: 18.989200,
      lon: -69.048800,
      descripcion: 'Pueblo costero emergente como destino turístico',
      popularidad: 80,
    ),
    TurismoLugar(
      id: 'mic_playa_esmeralda',
      nombre: 'Playa Esmeralda',
      ciudad: 'Miches',
      subtipo: playa,
      lat: 19.004700,
      lon: -68.988900,
      descripcion: 'Hermosa playa virgen en Miches',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'mic_montana_redonda',
      nombre: 'Montaña Redonda (Mirador)',
      ciudad: 'Miches',
      subtipo: montana,
      lat: 18.969800,
      lon: -68.985500,
      descripcion: 'Mirador con vistas espectaculares',
      popularidad: 90,
    ),

    // =========================================================
    // SAMANÁ / LAS TERRENAS / LAS GALERAS
    // =========================================================
    TurismoLugar(
      id: 'sam_centro',
      nombre: 'Centro de Santa Bárbara de Samaná',
      ciudad: 'Samaná',
      subtipo: ciudad,
      lat: 19.205900,
      lon: -69.336900,
      descripcion: 'Capital de la provincia Samaná',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'lt_centro',
      nombre: 'Centro de Las Terrenas',
      ciudad: 'Las Terrenas',
      subtipo: ciudad,
      lat: 19.312700,
      lon: -69.542800,
      descripcion: 'Pueblo turístico con influencia europea',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'lg_centro',
      nombre: 'Centro de Las Galeras',
      ciudad: 'Las Galeras',
      subtipo: ciudad,
      lat: 19.277500,
      lon: -69.199900,
      descripcion: 'Pequeño pueblo de pescadores',
      popularidad: 85,
    ),

    TurismoLugar(
      id: 'sam_cayo_levantado',
      nombre: 'Cayo Levantado (Isla Bacardí)',
      ciudad: 'Samaná',
      subtipo: playa,
      lat: 19.180400,
      lon: -69.271900,
      descripcion: 'Pequeña isla paradisíaca en la bahía de Samaná',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'sam_playa_rincon',
      nombre: 'Playa Rincón',
      ciudad: 'Las Galeras',
      subtipo: playa,
      lat: 19.308900,
      lon: -69.246200,
      descripcion: 'Considerada una de las playas más hermosas del mundo',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'sam_playa_fronton',
      nombre: 'Playa Frontón',
      ciudad: 'Las Galeras',
      subtipo: playa,
      lat: 19.263300,
      lon: -69.210400,
      descripcion: 'Playa remota accesible en bote',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'sam_playa_madama',
      nombre: 'Playa Madama',
      ciudad: 'Las Galeras',
      subtipo: playa,
      lat: 19.272400,
      lon: -69.214900,
      descripcion: 'Pequeña playa rodeada de acantilados',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'lt_playa_bonita',
      nombre: 'Playa Bonita',
      ciudad: 'Las Terrenas',
      subtipo: playa,
      lat: 19.333200,
      lon: -69.563800,
      descripcion: 'Playa popular con olas para surf',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'lt_playa_coson',
      nombre: 'Playa Cosón',
      ciudad: 'Las Terrenas',
      subtipo: playa,
      lat: 19.313000,
      lon: -69.592600,
      descripcion: 'Extensa playa virgen',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'lt_playa_popy',
      nombre: 'Playa Popy',
      ciudad: 'Las Terrenas',
      subtipo: playa,
      lat: 19.314900,
      lon: -69.545900,
      descripcion: 'Pequeña playa céntrica en Las Terrenas',
      popularidad: 85,
    ),

    TurismoLugar(
      id: 'sam_el_limon',
      nombre: 'Salto El Limón',
      ciudad: 'Samaná',
      subtipo: cascada,
      lat: 19.279100,
      lon: -69.478700,
      descripcion: 'Espectacular cascada de 50 metros',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'sam_haitises',
      nombre: 'Parque Nacional Los Haitises (Tour)',
      ciudad: 'Samaná',
      subtipo: tour,
      lat: 19.071700,
      lon: -69.606700,
      descripcion: 'Parque nacional con formaciones kársticas y cuevas',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'sam_ballenas',
      nombre: 'Avistamiento de Ballenas (Temporada)',
      ciudad: 'Samaná',
      subtipo: tour,
      lat: 19.205800,
      lon: -69.336700,
      descripcion: 'Avistamiento de ballenas jorobadas (enero-marzo)',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'sam_muelle_principal',
      nombre: 'Muelle Principal de Samaná (Botes/Tours)',
      ciudad: 'Samaná',
      subtipo: muelle,
      lat: 19.205300,
      lon: -69.332300,
      descripcion: 'Muelle para tours a Cayo Levantado y Los Haitises',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'lt_puerto',
      nombre: 'Embarcadero Las Terrenas (Botes)',
      ciudad: 'Las Terrenas',
      subtipo: muelle,
      lat: 19.309700,
      lon: -69.545900,
      descripcion: 'Pequeño puerto para tours de pesca y playas',
      popularidad: 80,
    ),

    // =========================================================
    // PUERTO PLATA / SOSÚA / CABARETE
    // =========================================================
    TurismoLugar(
      id: 'pp_centro',
      nombre: 'Centro de Puerto Plata',
      ciudad: 'Puerto Plata',
      subtipo: ciudad,
      lat: 19.793400,
      lon: -70.688400,
      descripcion: 'Centro histórico de la ciudad',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'sosua_centro',
      nombre: 'Centro de Sosúa',
      ciudad: 'Sosúa',
      subtipo: ciudad,
      lat: 19.752600,
      lon: -70.518100,
      descripcion: 'Pueblo turístico con playas y vida nocturna',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'cab_centro',
      nombre: 'Centro de Cabarete',
      ciudad: 'Cabarete',
      subtipo: ciudad,
      lat: 19.749700,
      lon: -70.408400,
      descripcion: 'Capital del surf y kitesurf en RD',
      popularidad: 95,
    ),

    TurismoLugar(
      id: 'pp_playa_dorada',
      nombre: 'Playa Dorada',
      ciudad: 'Puerto Plata',
      subtipo: playa,
      lat: 19.756900,
      lon: -70.684900,
      descripcion: 'Complejo turístico con hoteles y playa',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pp_playa_costambar',
      nombre: 'Playa Costambar',
      ciudad: 'Puerto Plata',
      subtipo: playa,
      lat: 19.815600,
      lon: -70.711600,
      descripcion: 'Comunidad playera al oeste de Puerto Plata',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'sosua_playa',
      nombre: 'Playa Sosúa',
      ciudad: 'Sosúa',
      subtipo: playa,
      lat: 19.764300,
      lon: -70.518900,
      descripcion: 'Playa principal de Sosúa con aguas tranquilas',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'cab_playa',
      nombre: 'Playa Cabarete',
      ciudad: 'Cabarete',
      subtipo: playa,
      lat: 19.748900,
      lon: -70.408700,
      descripcion: 'Playa principal de Cabarete, ideal para deportes acuáticos',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'cab_encuentro',
      nombre: 'Playa Encuentro',
      ciudad: 'Cabarete',
      subtipo: playa,
      lat: 19.778900,
      lon: -70.440700,
      descripcion: 'Playa conocida por sus olas para surf',
      popularidad: 90,
    ),

    TurismoLugar(
      id: 'pp_teleferico',
      nombre: 'Teleférico Puerto Plata',
      ciudad: 'Puerto Plata',
      subtipo: tour,
      lat: 19.808000,
      lon: -70.688300,
      descripcion: 'Teleférico que sube a la montaña Isabel de Torres',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'pp_isabel_torres',
      nombre: 'Montaña Isabel de Torres',
      ciudad: 'Puerto Plata',
      subtipo: montana,
      lat: 19.809400,
      lon: -70.688900,
      descripcion: 'Montaña con jardín botánico y réplica del Cristo Redentor',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'pp_27_charcos',
      nombre: '27 Charcos de Damajagua',
      ciudad: 'Imbert',
      subtipo: tour,
      lat: 19.689600,
      lon: -70.833000,
      descripcion: 'Cascadas y toboganes naturales',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'pp_ocean_world',
      nombre: 'Ocean World Adventure Park',
      ciudad: 'Cofresí',
      subtipo: atraccion,
      lat: 19.828600,
      lon: -70.723200,
      descripcion: 'Parque marino con shows de delfines y leones marinos',
      popularidad: 95,
    ),

    // =========================================================
    // LA ROMANA / BAYAHIBE / SAONA
    // =========================================================
    TurismoLugar(
      id: 'lr_centro',
      nombre: 'Centro de La Romana',
      ciudad: 'La Romana',
      subtipo: ciudad,
      lat: 18.427300,
      lon: -68.972800,
      descripcion: 'Ciudad industrial y turística',
      popularidad: 80,
    ),
    TurismoLugar(
      id: 'bay_centro',
      nombre: 'Bayahibe (Centro)',
      ciudad: 'Bayahibe',
      subtipo: playa,
      lat: 18.364800,
      lon: -68.837400,
      descripcion: 'Pueblo de pescadores convertido en destino turístico',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'bay_playa_dominicus',
      nombre: 'Playa Dominicus',
      ciudad: 'Bayahibe',
      subtipo: playa,
      lat: 18.349900,
      lon: -68.828200,
      descripcion: 'Playa con resorts todo incluido',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'bay_muelle_saona',
      nombre: 'Muelle Bayahibe (Salida Isla Saona)',
      ciudad: 'Bayahibe',
      subtipo: muelle,
      lat: 18.368700,
      lon: -68.837800,
      descripcion: 'Muelle para tours a Isla Saona',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'saona_principal',
      nombre: 'Isla Saona (Área Principal)',
      ciudad: 'Isla Saona',
      subtipo: tour,
      lat: 18.157000,
      lon: -68.731000,
      descripcion: 'Paraíso natural con playas de arena blanca',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'lr_casa_campo',
      nombre: 'Casa de Campo Resort',
      ciudad: 'La Romana',
      subtipo: resort,
      lat: 18.427800,
      lon: -68.905800,
      descripcion: 'Exclusivo resort con campo de golf y Altos de Chavón',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'lr_altos_chavon',
      nombre: 'Altos de Chavón',
      ciudad: 'La Romana',
      subtipo: atraccion,
      lat: 18.421600,
      lon: -68.883300,
      descripcion: 'Réplica de pueblo mediterráneo del siglo XVI',
      popularidad: 100,
    ),

    // =========================================================
    // JARABACOA / CONSTANZA
    // =========================================================
    TurismoLugar(
      id: 'jar_centro',
      nombre: 'Centro de Jarabacoa',
      ciudad: 'Jarabacoa',
      subtipo: ciudad,
      lat: 19.116700,
      lon: -70.633300,
      descripcion: 'Ciudad de la eterna primavera',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'jar_salto_jimenoa',
      nombre: 'Salto de Jimenoa',
      ciudad: 'Jarabacoa',
      subtipo: cascada,
      lat: 19.099500,
      lon: -70.651300,
      descripcion: 'Impresionante cascada de 60 metros',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'jar_salto_baiguate',
      nombre: 'Salto de Baiguate',
      ciudad: 'Jarabacoa',
      subtipo: cascada,
      lat: 19.111200,
      lon: -70.622200,
      descripcion: 'Cascada accesible y popular',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'con_centro',
      nombre: 'Centro de Constanza',
      ciudad: 'Constanza',
      subtipo: ciudad,
      lat: 18.909600,
      lon: -70.744300,
      descripcion: 'Valle con clima de montaña',
      popularidad: 85,
    ),
    TurismoLugar(
      id: 'con_valle_nuevo',
      nombre: 'Parque Nacional Valle Nuevo',
      ciudad: 'Constanza',
      subtipo: montana,
      lat: 18.817800,
      lon: -70.641000,
      descripcion: 'Parque nacional con paisajes de alta montaña',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'con_pirámide',
      nombre: 'Pirámide de Constanza',
      ciudad: 'Constanza',
      subtipo: atraccion,
      lat: 18.914100,
      lon: -70.745500,
      descripcion: 'Monumento emblemático de la ciudad',
      popularidad: 80,
    ),

    // =========================================================
    // BANÍ / DUNAS
    // =========================================================
    TurismoLugar(
      id: 'bani_centro',
      nombre: 'Centro de Baní',
      ciudad: 'Baní',
      subtipo: ciudad,
      lat: 18.279700,
      lon: -70.331100,
      descripcion: 'Ciudad conocida como la tierra de las dunas',
      popularidad: 80,
    ),
    TurismoLugar(
      id: 'bani_dunas',
      nombre: 'Dunas de Baní (Las Calderas)',
      ciudad: 'Baní',
      subtipo: tour,
      lat: 18.208200,
      lon: -70.516200,
      descripcion: 'Formaciones de arena únicas en el Caribe',
      popularidad: 95,
    ),
    TurismoLugar(
      id: 'bani_salinas',
      nombre: 'Salinas de Baní',
      ciudad: 'Baní',
      subtipo: tour,
      lat: 18.221500,
      lon: -70.535800,
      descripcion: 'Explotación de sal marina',
      popularidad: 80,
    ),

    // =========================================================
    // PEDERNALES / BAHÍA DE LAS ÁGUILAS / CABO ROJO
    // =========================================================
    TurismoLugar(
      id: 'ped_centro',
      nombre: 'Centro de Pedernales',
      ciudad: 'Pedernales',
      subtipo: ciudad,
      lat: 18.038200,
      lon: -71.743000,
      descripcion: 'Ciudad fronteriza en el suroeste',
      popularidad: 75,
    ),
    TurismoLugar(
      id: 'ped_bahia_aguilas',
      nombre: 'Bahía de las Águilas',
      ciudad: 'Pedernales',
      subtipo: playa,
      lat: 17.813900,
      lon: -71.645300,
      descripcion: 'Playa virgen considerada la más hermosa del Caribe',
      popularidad: 100,
    ),
    TurismoLugar(
      id: 'ped_cabo_rojo',
      nombre: 'Cabo Rojo (Pedernales)',
      ciudad: 'Pedernales',
      subtipo: playa,
      lat: 17.878800,
      lon: -71.620000,
      descripcion: 'Zona costera cercana a Bahía de las Águilas',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'ped_laguna_oviedo',
      nombre: 'Laguna de Oviedo',
      ciudad: 'Pedernales',
      subtipo: lago,
      lat: 17.794400,
      lon: -71.385800,
      descripcion: 'Laguna hipersalina con diversidad de aves',
      popularidad: 90,
    ),
    TurismoLugar(
      id: 'ped_isla_beata',
      nombre: 'Isla Beata',
      ciudad: 'Pedernales',
      subtipo: playa,
      lat: 17.577200,
      lon: -71.511100,
      descripcion: 'Isla remota al sur de Pedernales',
      popularidad: 85,
    ),
  ];

  // ==========================
  // ✅ Helper: filtra por subtipo
  // ==========================
  static List<TurismoLugar> porSubtipo(String subtipo) {
    return lugares.where((x) => x.subtipo == subtipo).toList();
  }

  // ==========================
  // ✅ Helper: busca por ID
  // ==========================
  static TurismoLugar? porId(String id) {
    try {
      return lugares.firstWhere((x) => x.id == id);
    } catch (e) {
      return null;
    }
  }

  // ==========================
  // ✅ Helper: busca por texto
  // ==========================
  static List<TurismoLugar> buscar(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    return lugares.where((lugar) {
      return lugar.nombre.toLowerCase().contains(q) ||
          lugar.ciudad.toLowerCase().contains(q) ||
          (lugar.descripcion?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
}
