/// Catálogo local de lugares frecuentes en República Dominicana.
/// Complementa Google Places para aeropuertos, plazas, sectores, malls, etc.
class LugarRdPoi {
  const LugarRdPoi({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
    this.aliases = const [],
    this.tags = const [],
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lon;
  final List<String> aliases;
  final List<String> tags;
}

/// Aeropuertos comerciales y principales aeródromos RD.
const List<LugarRdPoi> lugaresRdAeropuertos = [
  LugarRdPoi(
    id: 'SDQ',
    name: 'Aeropuerto Internacional Las Américas (SDQ)',
    address: 'Boca Chica, Santo Domingo',
    lat: 18.4297,
    lon: -69.6689,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto', 'las americas', 'las américas', 'sdq', 'aeropuerto santo domingo'],
  ),
  LugarRdPoi(
    id: 'PUJ',
    name: 'Aeropuerto Internacional de Punta Cana (PUJ)',
    address: 'Punta Cana, La Altagracia',
    lat: 18.5674,
    lon: -68.3634,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto punta cana', 'puj', 'aeropuerto'],
  ),
  LugarRdPoi(
    id: 'STI',
    name: 'Aeropuerto Internacional del Cibao (STI)',
    address: 'Santiago de los Caballeros',
    lat: 19.4061,
    lon: -70.6047,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto santiago', 'cibao', 'sti', 'aeropuerto'],
  ),
  LugarRdPoi(
    id: 'POP',
    name: 'Aeropuerto Internacional Gregorio Luperón (POP)',
    address: 'Puerto Plata',
    lat: 19.7579,
    lon: -70.5697,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto puerto plata', 'pop', 'aeropuerto'],
  ),
  LugarRdPoi(
    id: 'JBQ',
    name: 'Aeropuerto Internacional La Isabela (JBQ)',
    address: 'Santo Domingo (Higüero)',
    lat: 18.5725,
    lon: -69.9856,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto higuero', 'la isabela', 'jbq', 'aeropuerto'],
  ),
  LugarRdPoi(
    id: 'LRM',
    name: 'Aeropuerto Internacional La Romana (LRM)',
    address: 'La Romana',
    lat: 18.4510,
    lon: -68.9117,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto la romana', 'lrm', 'aeropuerto'],
  ),
  LugarRdPoi(
    id: 'AZS',
    name: 'Aeropuerto Internacional El Catey (AZS)',
    address: 'Samaná',
    lat: 19.2690,
    lon: -69.7370,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto samana', 'catey', 'azs', 'aeropuerto'],
  ),
  LugarRdPoi(
    id: 'COZ',
    name: 'Aeropuerto Constanza (COZ)',
    address: 'Constanza, La Vega',
    lat: 18.9076,
    lon: -70.7200,
    tags: ['aeropuerto'],
    aliases: ['aeropuerto constanza', 'coz', 'aeropuerto'],
  ),
];

/// Plazas, parques y puntos de referencia cívicos.
const List<LugarRdPoi> lugaresRdPlazas = [
  LugarRdPoi(
    id: 'PLZ_CULT',
    name: 'Plaza de la Cultura Juan Pablo Duarte',
    address: 'Gazcue, Santo Domingo',
    lat: 18.4712,
    lon: -69.9143,
    tags: ['plaza'],
    aliases: ['plaza cultura', 'plaza de la cultura'],
  ),
  LugarRdPoi(
    id: 'PLZ_BAND',
    name: 'Plaza de la Bandera',
    address: 'Los Prados, Santo Domingo',
    lat: 18.4789,
    lon: -69.9556,
    tags: ['plaza'],
    aliases: ['plaza bandera', 'plaza de la bandera'],
  ),
  LugarRdPoi(
    id: 'PLZ_ESP',
    name: 'Plaza de la Cultura Española',
    address: 'Gazcue, Santo Domingo',
    lat: 18.4698,
    lon: -69.9125,
    tags: ['plaza'],
    aliases: ['plaza española', 'plaza espanola'],
  ),
  LugarRdPoi(
    id: 'PLZ_SD',
    name: 'Parque Independencia (Plaza de la Independencia)',
    address: 'Zona Colonial, Santo Domingo',
    lat: 18.4718,
    lon: -69.8833,
    tags: ['plaza'],
    aliases: ['parque independencia', 'plaza independencia'],
  ),
  LugarRdPoi(
    id: 'PLZ_STI',
    name: 'Parque Central Santiago',
    address: 'Santiago de los Caballeros',
    lat: 19.4517,
    lon: -70.6970,
    tags: ['plaza'],
    aliases: ['plaza santiago', 'parque central santiago', 'plaza'],
  ),
  LugarRdPoi(
    id: 'PLZ_LVEGA',
    name: 'Parque Central de La Vega',
    address: 'La Vega',
    lat: 19.2242,
    lon: -70.5290,
    tags: ['plaza'],
    aliases: ['plaza la vega', 'parque central la vega'],
  ),
  LugarRdPoi(
    id: 'PLZ_SANCR',
    name: 'Plaza Central San Cristóbal',
    address: 'San Cristóbal',
    lat: 18.4167,
    lon: -70.1000,
    tags: ['plaza'],
    aliases: ['plaza san cristobal', 'plaza san cristóbal'],
  ),
  LugarRdPoi(
    id: 'PLZ_BANI',
    name: 'Parque Central Baní',
    address: 'Baní, Peravia',
    lat: 18.2796,
    lon: -70.3319,
    tags: ['plaza'],
    aliases: ['plaza bani', 'parque bani'],
  ),
  LugarRdPoi(
    id: 'PLZ_HIG',
    name: 'Parque Central Higüey',
    address: 'Higüey, La Altagracia',
    lat: 18.6150,
    lon: -68.7080,
    tags: ['plaza'],
    aliases: ['plaza higuey', 'parque higuey'],
  ),
  LugarRdPoi(
    id: 'PLZ_MAO',
    name: 'Parque Central Mao',
    address: 'Mao, Valverde',
    lat: 19.5519,
    lon: -71.0781,
    tags: ['plaza'],
    aliases: ['plaza mao', 'parque mao'],
  ),
];

/// Sectores, ensanches y urbanizaciones frecuentes.
const List<LugarRdPoi> lugaresRdSectores = [
  LugarRdPoi(id: 'SEC_PIANT', name: 'Piantini', address: 'Santo Domingo', lat: 18.4720, lon: -69.9410, tags: ['sector'], aliases: ['piantini']),
  LugarRdPoi(id: 'SEC_NACO', name: 'Naco', address: 'Santo Domingo', lat: 18.4750, lon: -69.9340, tags: ['sector'], aliases: ['naco']),
  LugarRdPoi(id: 'SEC_BV', name: 'Bella Vista', address: 'Santo Domingo', lat: 18.4680, lon: -69.9480, tags: ['sector'], aliases: ['bella vista']),
  LugarRdPoi(id: 'SEC_GAZ', name: 'Gazcue', address: 'Santo Domingo', lat: 18.4685, lon: -69.9090, tags: ['sector'], aliases: ['gazcue']),
  LugarRdPoi(id: 'SEC_LP', name: 'Los Prados', address: 'Santo Domingo', lat: 18.4810, lon: -69.9580, tags: ['sector'], aliases: ['los prados', 'prados']),
  LugarRdPoi(id: 'SEC_AH', name: 'Arroyo Hondo', address: 'Santo Domingo', lat: 18.4940, lon: -69.9580, tags: ['sector'], aliases: ['arroyo hondo']),
  LugarRdPoi(id: 'SEC_MN', name: 'Mirador Norte', address: 'Santo Domingo', lat: 18.5050, lon: -69.9450, tags: ['sector'], aliases: ['mirador norte']),
  LugarRdPoi(id: 'SEC_EJUL', name: 'Ensanche Julieta', address: 'Santo Domingo', lat: 18.4880, lon: -69.9180, tags: ['sector', 'ensanche'], aliases: ['ensanche julieta', 'julieta']),
  LugarRdPoi(id: 'SEC_ELAC', name: 'Ensanche La Fe', address: 'Santo Domingo', lat: 18.4920, lon: -69.9120, tags: ['sector', 'ensanche'], aliases: ['ensanche la fe', 'la fe']),
  LugarRdPoi(id: 'SEC_ELUZ', name: 'Ensanche Luperón', address: 'Santo Domingo', lat: 18.4860, lon: -69.9050, tags: ['sector', 'ensanche'], aliases: ['ensanche luperon', 'luperon']),
  LugarRdPoi(id: 'SEC_VM', name: 'Villa Mella', address: 'Santo Domingo Norte', lat: 18.5120, lon: -69.8980, tags: ['sector'], aliases: ['villa mella']),
  LugarRdPoi(id: 'SEC_VJ', name: 'Villa Juana', address: 'Santo Domingo', lat: 18.4780, lon: -69.9280, tags: ['sector'], aliases: ['villa juana']),
  LugarRdPoi(id: 'SEC_VMAR', name: 'Villa María', address: 'Santo Domingo', lat: 18.4900, lon: -69.9200, tags: ['sector'], aliases: ['villa maria', 'villa maría']),
  LugarRdPoi(id: 'SEC_GUA', name: 'Gualey', address: 'Santo Domingo', lat: 18.4780, lon: -69.9020, tags: ['sector', 'barrio'], aliases: ['gualey']),
  LugarRdPoi(id: 'SEC_GCH', name: 'Guachupita', address: 'Santo Domingo', lat: 18.4810, lon: -69.8980, tags: ['sector', 'barrio'], aliases: ['guachupita']),
  LugarRdPoi(id: 'SEC_VCON', name: 'Villa Consuelo', address: 'Santo Domingo', lat: 18.4840, lon: -69.8950, tags: ['sector', 'barrio'], aliases: ['villa consuelo']),
  LugarRdPoi(id: 'SEC_CAPOT', name: 'Capotillo', address: 'Santo Domingo', lat: 18.4880, lon: -69.8900, tags: ['sector', 'barrio'], aliases: ['capotillo']),
  LugarRdPoi(id: 'SEC_LMIN', name: 'Los Mina', address: 'Santo Domingo Este', lat: 18.4750, lon: -69.8650, tags: ['sector', 'barrio'], aliases: ['los mina']),
  LugarRdPoi(
    id: 'SEC_LCAN',
    name: 'Barrio Las Cañitas',
    address: 'Santo Domingo Este',
    lat: 18.4906,
    lon: -69.8495,
    tags: ['sector', 'barrio'],
    aliases: [
      'las cañitas',
      'las canitas',
      'barrio las cañitas',
      'barrio las canitas',
      'cañitas',
      'canitas',
    ],
  ),
  LugarRdPoi(id: 'SEC_CR', name: 'Cristo Rey', address: 'Santo Domingo', lat: 18.4720, lon: -69.9280, tags: ['sector', 'barrio'], aliases: ['cristo rey']),
  LugarRdPoi(id: 'SEC_INV', name: 'Invi', address: 'Santo Domingo', lat: 18.4760, lon: -69.9150, tags: ['sector', 'barrio'], aliases: ['invi']),
  LugarRdPoi(id: 'SEC_SAV', name: 'Savica', address: 'Los Alcarrizos, Santo Domingo Oeste', lat: 18.5050, lon: -70.0200, tags: ['sector', 'barrio'], aliases: ['savica']),
  LugarRdPoi(id: 'SEC_RES_CDN', name: 'Residencial Ciudad Real I', address: 'Santo Domingo Oeste', lat: 18.4550, lon: -70.0050, tags: ['sector', 'residencial'], aliases: ['ciudad real', 'residencial ciudad real']),
  LugarRdPoi(id: 'SEC_RES_LAS', name: 'Residencial Las Palmas', address: 'Santo Domingo Este', lat: 18.4650, lon: -69.8450, tags: ['sector', 'residencial'], aliases: ['las palmas', 'residencial las palmas']),
  LugarRdPoi(id: 'SEC_STI_CENT', name: 'Centro Santiago', address: 'Santiago de los Caballeros', lat: 19.4517, lon: -70.6970, tags: ['sector'], aliases: ['centro santiago', 'santiago centro']),
  LugarRdPoi(id: 'SEC_BAV', name: 'Bávaro', address: 'Punta Cana, La Altagracia', lat: 18.7170, lon: -68.4500, tags: ['sector'], aliases: ['bavaro', 'bávaro']),
  LugarRdPoi(id: 'SEC_CAP', name: 'Cap Cana', address: 'Punta Cana', lat: 18.5050, lon: -68.3720, tags: ['sector'], aliases: ['cap cana']),
  LugarRdPoi(id: 'SEC_VER', name: 'Verón', address: 'Punta Cana', lat: 18.6400, lon: -68.4200, tags: ['sector'], aliases: ['veron', 'verón']),
];

/// Centros comerciales, hoteles y POI turísticos.
const List<LugarRdPoi> lugaresRdPois = [
  LugarRdPoi(id: 'MALL_BM', name: 'BlueMall Santo Domingo', address: 'Piantini, Santo Domingo', lat: 18.4724, lon: -69.9402, tags: ['mall'], aliases: ['bluemall', 'blue mall']),
  LugarRdPoi(id: 'MALL_AG', name: 'Ágora Mall', address: 'Serrallés, Santo Domingo', lat: 18.4878, lon: -69.9365, tags: ['mall'], aliases: ['agora', 'ágora']),
  LugarRdPoi(id: 'MALL_SA', name: 'Sambil Santo Domingo', address: 'Los Jardines, Santo Domingo', lat: 18.4870, lon: -69.9218, tags: ['mall'], aliases: ['sambil']),
  LugarRdPoi(id: 'MALL_G360', name: 'Galería 360', address: 'Piantini, Santo Domingo', lat: 18.4740, lon: -69.9380, tags: ['mall'], aliases: ['galeria 360', 'galería 360']),
  LugarRdPoi(id: 'MALL_ACR', name: 'Acropolis Center', address: 'Piantini, Santo Domingo', lat: 18.4735, lon: -69.9395, tags: ['mall'], aliases: ['acropolis']),
  LugarRdPoi(id: 'MALL_MC', name: 'Mega Centro', address: 'Santo Domingo Este', lat: 18.4880, lon: -69.8550, tags: ['mall'], aliases: ['mega centro']),
  LugarRdPoi(id: 'MALL_BMPC', name: 'BlueMall Punta Cana', address: 'Punta Cana', lat: 18.5670, lon: -68.4033, tags: ['mall'], aliases: ['bluemall punta cana']),
  LugarRdPoi(id: 'MALL_PAL', name: 'Palícaro Shopping', address: 'Santiago', lat: 19.4620, lon: -70.6850, tags: ['mall'], aliases: ['palicaro']),
  LugarRdPoi(id: 'ZN_COL', name: 'Zona Colonial', address: 'Santo Domingo', lat: 18.4764, lon: -69.8833, tags: ['turismo'], aliases: ['zona colonial', 'colonial']),
  LugarRdPoi(id: 'MLC_SD', name: 'Malecón de Santo Domingo', address: 'Santo Domingo', lat: 18.4605, lon: -69.9048, tags: ['turismo'], aliases: ['malecon', 'malecón']),
  LugarRdPoi(id: 'HTL_EMB', name: 'Hotel El Embajador', address: 'Piantini, Santo Domingo', lat: 18.4641, lon: -69.9428, tags: ['hotel'], aliases: ['embajador', 'hotel embajador']),
  LugarRdPoi(id: 'HTL_JWM', name: 'JW Marriott Santo Domingo', address: 'BlueMall, Piantini', lat: 18.4727, lon: -69.9407, tags: ['hotel'], aliases: ['jw marriott', 'marriott']),
  LugarRdPoi(id: 'HTL_BBV', name: 'Barceló Bávaro Palace', address: 'Bávaro, Punta Cana', lat: 18.6576, lon: -68.4015, tags: ['hotel'], aliases: ['barcelo bavaro', 'barceló']),
  LugarRdPoi(id: 'HTL_HRH', name: 'Hard Rock Hotel & Casino Punta Cana', address: 'Macao, Punta Cana', lat: 18.7282, lon: -68.4687, tags: ['hotel'], aliases: ['hard rock']),
  LugarRdPoi(id: 'UNI_UASD', name: 'UASD - Universidad Autónoma de Santo Domingo', address: 'Gazcue, Santo Domingo', lat: 18.4632, lon: -69.9110, tags: ['universidad'], aliases: ['uasd']),
  LugarRdPoi(id: 'UNI_PUCMM', name: 'PUCMM - Universidad Católica Madre y Maestra', address: 'Santiago', lat: 19.4510, lon: -70.6940, tags: ['universidad'], aliases: ['pucmm', 'catolica santiago']),
  LugarRdPoi(id: 'UNI_UNIBE', name: 'UNIBE', address: 'Santo Domingo', lat: 18.4580, lon: -69.9420, tags: ['universidad'], aliases: ['unibe']),
  LugarRdPoi(id: 'HSP_CED', name: 'Centro de Diagnóstico CEDIMAT', address: 'Paseo de la Salud, Santo Domingo', lat: 18.4707, lon: -69.9537, tags: ['hospital'], aliases: ['cedimat']),
  LugarRdPoi(id: 'HSP_PDS', name: 'Plaza de la Salud', address: 'Gazcue, Santo Domingo', lat: 18.4680, lon: -69.9160, tags: ['hospital'], aliases: ['plaza de la salud', 'hospital plaza salud']),
  LugarRdPoi(id: 'HSP_HG', name: 'Hospital General de la Plaza de la Salud', address: 'Gazcue, Santo Domingo', lat: 18.4675, lon: -69.9155, tags: ['hospital'], aliases: ['hospital general']),
];

/// Ciudades principales (centro urbano aproximado).
const List<LugarRdPoi> lugaresRdCiudades = [
  LugarRdPoi(id: 'CIU_SD', name: 'Santo Domingo', address: 'Distrito Nacional', lat: 18.4861, lon: -69.9312, tags: ['ciudad'], aliases: ['santo domingo', 'sd', 'sdq ciudad']),
  LugarRdPoi(id: 'CIU_STI', name: 'Santiago de los Caballeros', address: 'Santiago', lat: 19.4517, lon: -70.6970, tags: ['ciudad'], aliases: ['santiago', 'santiago de los caballeros']),
  LugarRdPoi(id: 'CIU_LVEGA', name: 'La Vega', address: 'La Vega', lat: 19.2242, lon: -70.5290, tags: ['ciudad'], aliases: ['la vega']),
  LugarRdPoi(id: 'CIU_SANCR', name: 'San Cristóbal', address: 'San Cristóbal', lat: 18.4167, lon: -70.1000, tags: ['ciudad'], aliases: ['san cristobal', 'san cristóbal']),
  LugarRdPoi(id: 'CIU_PP', name: 'Puerto Plata', address: 'Puerto Plata', lat: 19.7934, lon: -70.6884, tags: ['ciudad'], aliases: ['puerto plata']),
  LugarRdPoi(id: 'CIU_LROM', name: 'La Romana', address: 'La Romana', lat: 18.4273, lon: -68.9728, tags: ['ciudad'], aliases: ['la romana']),
  LugarRdPoi(id: 'CIU_SAM', name: 'Samaná', address: 'Samaná', lat: 19.2058, lon: -69.3364, tags: ['ciudad'], aliases: ['samana', 'samaná']),
  LugarRdPoi(id: 'CIU_HIG', name: 'Higüey', address: 'La Altagracia', lat: 18.6150, lon: -68.7080, tags: ['ciudad'], aliases: ['higuey', 'higüey']),
  LugarRdPoi(id: 'CIU_BANI', name: 'Baní', address: 'Peravia', lat: 18.2796, lon: -70.3319, tags: ['ciudad'], aliases: ['bani', 'baní']),
  LugarRdPoi(id: 'CIU_MAO', name: 'Mao', address: 'Valverde', lat: 19.5519, lon: -71.0781, tags: ['ciudad'], aliases: ['mao']),
  LugarRdPoi(id: 'CIU_SFM', name: 'San Francisco de Macorís', address: 'Duarte', lat: 19.3008, lon: -70.2526, tags: ['ciudad'], aliases: ['san francisco de macoris', 'sfm']),
  LugarRdPoi(id: 'CIU_SDOE', name: 'Santo Domingo Este', address: 'Santo Domingo Este', lat: 18.4885, lon: -69.8572, tags: ['ciudad'], aliases: ['santo domingo este', 'sde']),
  LugarRdPoi(id: 'CIU_SDN', name: 'Santo Domingo Norte', address: 'Santo Domingo Norte', lat: 18.5700, lon: -69.9000, tags: ['ciudad'], aliases: ['santo domingo norte', 'sdn']),
  LugarRdPoi(id: 'CIU_SDO', name: 'Santo Domingo Oeste', address: 'Santo Domingo Oeste', lat: 18.5000, lon: -70.0000, tags: ['ciudad'], aliases: ['santo domingo oeste', 'sdo']),
];

List<LugarRdPoi> get lugaresRdCatalogoCompleto => [
  ...lugaresRdAeropuertos,
  ...lugaresRdPlazas,
  ...lugaresRdSectores,
  ...lugaresRdPois,
  ...lugaresRdCiudades,
];
