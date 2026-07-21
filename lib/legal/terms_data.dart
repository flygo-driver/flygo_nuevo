const String kTermsVersion = '1.1';
const String kTaxistaContractVersion = '1.0';

/// Contrato digital módulo RAI Corporativo (empresa / encargado).
const String kCorporativoContractVersion = '1.0';

/// Base pública en Firebase Hosting (Play Console y enlaces in-app).
const String kLegalPublicBaseUrl = 'https://flygo-rd.web.app';

/// URL para Google Play Console → Política de privacidad.
const String kPrivacyPolicyPublicUrl = '$kLegalPublicBaseUrl/legal/privacidad';

/// Términos y condiciones (web).
const String kTermsPublicUrl = '$kLegalPublicBaseUrl/legal/terminos';

/// Eliminación de cuenta (requisito Google Play).
const String kAccountDeletionPublicUrl =
    '$kLegalPublicBaseUrl/legal/eliminar-cuenta';

/// Contrato digital conductor (web).
const String kTaxistaContractPdfUrl =
    '$kLegalPublicBaseUrl/legal/contrato-taxista';

/// Contrato servicio corporativo (web).
const String kCorporativoContractPublicUrl =
    '$kLegalPublicBaseUrl/legal/contrato-corporativo';

const String kTermsLastUpdate = '24/06/2026';
const String kTermsContactEmail = 'ventasopenask@gmail.com';
const String kTermsContactPhone = '18094201481';

const String kTermsFullText = '''
POLITICA DE PRIVACIDAD Y TERMINOS DE USO - RAI DRIVER
Ultima actualizacion: 24/06/2026
Version: 1.1

Empresa: Open ASK Service SRL
RNC: 1320-11767
Nombre comercial: RAI DRIVER (Rai Drive)
Contacto: ventasopenask@gmail.com
Telefono: 18094201481

1. INTRODUCCION
RAI DRIVER es una plataforma tecnologica de intermediacion que conecta pasajeros y conductores independientes. Al registrarte, declaras que has leido y aceptado estos terminos y la politica de privacidad.

2. NATURALEZA DEL SERVICIO
RAI DRIVER no es empresa de transporte, no posee vehiculos y no emplea conductores. Los conductores son independientes y responsables del servicio prestado.

3. REGISTRO DE USUARIOS
Debes proporcionar datos reales, ser mayor de 18 anos, resguardar tus credenciales y aceptar estos terminos para usar la plataforma.

4. INFORMACION RECOPILADA
Se recopilan datos personales, datos de ubicacion, datos tecnicos y, en conductores, documentacion legal y del vehiculo.

5. FINALIDAD DEL TRATAMIENTO
Usamos los datos para operar viajes, seguridad, prevencion de fraude, notificaciones, cumplimiento legal y mejora de la experiencia.

6. COMPARTICION DE INFORMACION
Compartimos datos entre pasajero y conductor durante el servicio, con proveedores tecnologicos (ej. Firebase) y por requerimientos legales o de seguridad. No vendemos datos.

7. SEGURIDAD DE LA INFORMACION
Aplicamos medidas tecnicas y organizativas de seguridad, incluyendo cifrado y control de acceso. No existe seguridad digital absoluta.

8. RETENCION DE DATOS
Conservamos datos mientras la cuenta este activa, por necesidades operativas y por obligaciones legales/fiscales.

9. DERECHOS DEL USUARIO
Puedes solicitar acceso, rectificacion, actualizacion, eliminacion, oposicion y retiro de consentimiento, sujeto a la normativa aplicable.

10. UBICACION EN SEGUNDO PLANO
Puede usarse ubicacion en segundo plano para asignacion, navegacion y seguridad durante los viajes.

11. RESPONSABILIDAD DE CONDUCTORES
Los conductores son responsables de licencia, seguro, estado del vehiculo, cumplimiento legal y obligaciones fiscales.

12. LIMITACION DE RESPONSABILIDAD
Open ASK Service SRL no responde por actos de terceros, accidentes, robos, danos o interrupciones fuera del alcance tecnologico de la app.

13. VERIFICACION DE CONDUCTORES
La plataforma realiza validaciones administrativas de documentos, sin garantizar conducta futura o desempeno del conductor.

14. SEGUROS
El conductor debe mantener seguro obligatorio vigente. Seguros adicionales de plataforma no implican relacion laboral ni responsabilidad directa del servicio de transporte.

15. PAGOS Y COMISIONES
Actualmente: efectivo y transferencia. Proximamente: tarjeta y medios digitales. Las comisiones y tarifas se muestran antes de confirmar.

16. CANCELACIONES
Puede haber cargos o penalizaciones por cancelaciones injustificadas. La plataforma puede cancelar por seguridad o incumplimiento.

17. SUSPENSION O TERMINACION DE CUENTAS
Se pueden suspender o cerrar cuentas por fraude, violencia, informacion falsa, incumplimiento de terminos o actividades ilegales.

18. MODIFICACIONES
Estos terminos pueden actualizarse. La continuidad de uso posterior a la notificacion implica aceptacion de cambios.

19. JURISDICCION
Se rige por leyes de Republica Dominicana y tribunales competentes de ese pais.

20. CONTACTO
Correo de soporte: ventasopenask@gmail.com. Telefono: 18094201481. Tiempo estimado de respuesta: 48 horas habiles.

21. SERVICIOS ESPECIALES PARA TURISMO
RAI DRIVER puede aplicar validaciones adicionales y criterios especiales para servicios de turismo, manteniendo el modelo de intermediacion.

22. SERVICIOS DISPONIBLES
Viaje ahora, viaje programado, motores, paradas multiples y modalidades de turismo, segun disponibilidad y condiciones del servicio.

23. CODIGO DE CONDUCTA
Queda prohibido acoso, discriminacion, violencia, suplantacion y actividades ilegales. El incumplimiento puede causar suspension permanente.

24. PROPIEDAD INTELECTUAL
Marca, logo, software y contenidos de RAI DRIVER pertenecen a Open ASK Service SRL. Se prohibe copia, ingenieria inversa o uso no autorizado.

25. RESOLUCION DE CONFLICTOS Y SOPORTE
Las reclamaciones deben presentarse dentro del plazo indicado en la plataforma, con evidencia suficiente para su evaluacion.

26. FUERZA MAYOR
No hay responsabilidad por incumplimientos causados por desastres, conflictos, fallas masivas de infraestructura, emergencias sanitarias o medidas gubernamentales.

27. INDEMNIZACION
El usuario acepta mantener indemne a Open ASK Service SRL por reclamos derivados de uso indebido, incumplimiento o violacion de leyes.

28. DISPOSICIONES FINALES
Estos terminos constituyen el acuerdo completo. Si una clausula es invalida, el resto mantiene vigencia. La falta de ejercicio de un derecho no implica renuncia.

DECLARACION DE ACEPTACION
Al aceptar, declaras que has leido, comprendido y aceptado la Politica de Privacidad y Terminos de Uso de RAI DRIVER, que eres mayor de 18 anos y que tus datos son veraces.
''';

const String kTaxistaContractText = '''
CONTRATO DIGITAL DE USO DE PLATAFORMA PARA CONDUCTORES - RAI DRIVER
Version: 1.0

1) Relacion comercial:
El conductor opera como independiente y usa la app para conectar con clientes.

2) Comision de plataforma:
Por cada viaje completado, el conductor reconoce y acepta la comision de la plataforma.

3) Metodo de cobro:
El cliente puede pagar en efectivo o transferencia al conductor, segun el viaje.

4) Obligacion de pago del conductor:
El conductor se compromete a liquidar su comision semanal dentro del plazo definido por la plataforma.

5) Mora y bloqueo:
Si existe deuda vencida, RAI puede limitar temporalmente la recepcion de viajes hasta regularizar.

6) Evidencia digital:
La aceptacion digital de este contrato queda registrada con usuario, fecha/hora y version.

7) Legislacion:
Este acuerdo se rige por las leyes de Republica Dominicana.
''';

const String kCorporativoContractText = '''
CONTRATO DE SERVICIO CORPORATIVO — RAI DRIVER
Version: 1.0 · Open ASK Service SRL (RNC 1320-11767)

1) NATURALEZA DEL SERVICIO
RAI DRIVER es plataforma tecnologica de intermediacion. No es empresa de transporte, no tiene flota ni emplea conductores. El transporte lo ejecutan conductores independientes registrados en RAI.

2) PARTES
Prestador: Open ASK Service SRL (RAI). Cliente: su empresa. Usted actua como encargado autorizado y declara tener facultad para aceptar este contrato en nombre de la empresa.

3) ACTIVACION
RAI debe activar el contrato comercial y tarifas antes de publicar viajes operativos. Puede configurar rutas mientras tanto; la operacion en calle inicia cuando RAI active el servicio.

4) RUTAS Y CONDUCTORES
La empresa define origen, pasajeros y horarios. RAI asigna el conductor fijo verificado. Los viajes son exclusivos (no pool publico) salvo contingencia gestionada por RAI. RAI puede sustituir conductores por seguridad, fuerza mayor o indisponibilidad.

5) CODIGO DEL PERIODO
PIN valido durante el ciclo de facturacion. Viajes completados en la plataforma con registro valido generan cargo segun tarifa acordada. Los registros digitales de RAI son evidencia primaria del servicio.

6) FACTURACION Y PAGO
Viajes completados se acumulan por periodo (ej. 15 o 30 dias). La empresa paga a RAI en el plazo acordado. Mora puede suspender el servicio. RAI emite e-CF conforme ley dominicana. La empresa paga a RAI; RAI liquida al conductor. No hay pago directo empresa-conductor salvo pacto escrito con RAI.

7) OBLIGACIONES DE LA EMPRESA
Informacion veraz; encargados autorizados; pago puntual; cumplimiento legal con pasajeros/empleados; puntos de recogida seguros; no uso ilicito del servicio.

8) LIMITES DE RAI
RAI provee plataforma con diligencia razonable. No garantiza ausencia de retrasos ni disponibilidad ininterrumpida (trafico, clima, fuerza mayor). En la maxima medida legal, RAI no responde por accidentes ni actos de conductores independientes. Responsabilidad total de RAI limitada a lo pagado por la empresa en los 3 meses anteriores al reclamo.

9) DISPUTAS DE FACTURACION
Reclamos por escrito a RAI dentro de 5 dias habiles del corte. Sin reclamacion fundada en plazo, el monto se considera aceptado.

10) DATOS PERSONALES
La empresa es responsable de la base legal para datos de pasajeros en plantillas. RAI trata datos segun Politica de Privacidad. La empresa indemniza a RAI por reclamos imputables a su manejo de datos.

11) INDEMNIZACION Y SUSPENSION
La empresa indemniza a Open ASK Service SRL por incumplimientos, informacion falsa o violaciones de ley. RAI puede suspender o terminar por mora, fraude, riesgo o abuso.

12) PROPIEDAD INTELECTUAL Y LEY
Marca y software son de Open ASK Service SRL. Licencia limitada para usar el modulo. Leyes de Republica Dominicana; tribunales del Distrito Nacional.

ACEPTACION DIGITAL
Al firmar, declara autorizacion para obligar a la empresa, acepta intermediacion de RAI, conductores independientes y facturacion por periodos.
''';
