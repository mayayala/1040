# Registro de validación posterior a la defensa privada

Versión de origen: [a10b35f4](https://github.com/mayayala/1040/commit/a10b35f44b5269b473116ecd72752d5e3862cc61). Esta revisión conserva las funciones principales del proyecto. El documento defendido, sus objetivos, sus tablas históricas y los resultados originales no se sustituyen por pruebas nuevas. El código y las mediciones de esta revisión deben identificarse con el commit que los contenga.

| Objetivo específico | Evidencia disponible en esta revisión | Qué falta comprobar |
| --- | --- | --- |
| Arquitectura Android y comunicación entre roles | Flujo de vínculo con aceptación del objetivo; cola cifrada local, escritura idempotente por ID, reintentos y envío FCM desde Functions. El SOS se muestra como guardado hasta que se sincronice. | Ejecutar registro, vínculo, revocación, mapa, SOS y reconexión en dos Android con un Firebase de prueba. Medir latencia desde la acción hasta la recepción. |
| Geocercas adaptativas comparadas con estáticas | El radio depende de precisión GNSS, velocidad, horario y riesgo; el estado previo determina los umbrales de entrada y salida. Los polígonos se evalúan por su contorno. Comparación nueva de 6.000 trayectorias circulares simuladas. | Comprobar cruces en teléfonos, perfiles de ruido de campo y polígonos. Las cifras de simulación sólo corresponden a círculos y al protocolo reproducible. |
| Árbol de decisión local y rendimiento | Artefacto común a Dart y Python; árbol de profundidad máxima 3, interfaz de 18 características, reglas de prioridad y ruta de inferencia. La versión posterior alcanza el criterio de sensibilidad en dos pruebas sintéticas. | Medir tiempos de inferencia y confirmar la sensibilidad y los falsos avisos con casos etiquetados en campo. |

## Resultados ejecutados

La [figura archivada en el repositorio original](https://github.com/mayayala/1040/blob/a10b35f44b5269b473116ecd72752d5e3862cc61/training/plots/02_confusion_matrix_test.png) contiene 1.800 muestras, incluidas 204 críticas. No coincide con las matrices históricas del documento, de 1.213 y 1.208 muestras, ni con la nueva evaluación del árbol congelado, que también tiene 1.800 muestras pero sólo 156 críticas. No se establece equivalencia entre esas matrices.

### Clasificador de referencia de la revisión anterior

El CSV del repositorio tiene 12.000 ventanas de 200 usuarios sintéticos. Se reprodujo la división por usuario con semilla 42: 140 usuarios para entrenamiento, 30 para validación y 30 para prueba. Esta ejecución **no reentrena** ni ajusta el umbral mirando la prueba. Evalúa el árbol y el preprocesamiento que se distribuyen con Android; no certifica el origen de las matrices de la defensa ni mide la latencia en Android.

| Clase real | Predicho normal | Predicho anómalo | Predicho crítico |
| --- | ---: | ---: | ---: |
| Normal | 1.301 | 97 | 0 |
| Anómalo | 8 | 194 | 44 |
| Crítico | 0 | 37 | 119 |

Exactitud: 89,67 %. Sensibilidad crítica: 76,28 % (119/156). Precisión crítica: 73,01 % (119/163). F1 crítico: 74,61 %. La sensibilidad crítica queda 3,72 puntos porcentuales por debajo del criterio del 80 %. Los hashes del CSV y los archivos del modelo están en [android_tree_evaluation.json](../training/results/android_tree_evaluation.json).

Las mismas características, normalización y umbrales recorren las mismas ramas. Las estimaciones de clase de la hoja son salidas del árbol, no un paso aleatorio ni una red neuronal. Las reglas del motor pueden alterar la severidad final de la alerta; la matriz anterior sólo evalúa la clasificación del árbol con sus umbrales.

El [análisis de umbrales](../training/results/critical_threshold_validation.json) usa sólo las 1.800 ventanas de validación, con 126 casos críticos. Mantener el umbral 0,40 dio 92 aciertos críticos y 38 falsos positivos críticos (sensibilidad 73,02 %; precisión 70,77 %). Reducirlo a 0,391 dio 102 aciertos y 98 falsos positivos (sensibilidad 80,95 %; precisión 51,00 %; F1 crítico 62,58 % frente a 71,88 %). Ese ajuste aislado no se adoptó. Estas cifras no reemplazan las de prueba.

### Árbol revisado para el criterio de sensibilidad crítica

El árbol se ajustó con la partición de entrenamiento. Se compararon configuraciones de profundidad máxima tres y se seleccionaron el árbol y los umbrales con usuarios de validación, exigiendo al menos 82 % de sensibilidad en esa partición y priorizando F1 crítico. La configuración seleccionada ajusta las ramas para separar casos críticos del resto y conserva las frecuencias de las tres clases en cada hoja. El conjunto sintético nuevo se generó después de fijar la configuración, con 200 usuarios nuevos y semilla 104081. Ambas versiones se comparan en las mismas muestras de cada prueba.

| Conjunto | Sensibilidad crítica anterior → revisada | Precisión crítica anterior → revisada | Falsos positivos críticos anterior → revisada |
| --- | --- | --- | --- |
| 1.800 ventanas, comparación con la prueba de referencia | 76,28 % (119/156) → 91,03 % (142/156) | 73,01 % → 60,43 % | 44 → 93 |
| 12.000 ventanas, prueba sintética nueva | 78,32 % (860/1.098) → 89,44 % (982/1.098) | 76,72 % → 61,49 % | 261 → 615 |

El mínimo de 80 % se cumple en ambas pruebas sintéticas. El F1 crítico baja de 74,61 % a 72,63 % en la comparación de referencia y de 77,51 % a 72,88 % en la prueba nueva. Los resultados corresponden al clasificador, no a la severidad final después de las reglas ni a notificaciones recibidas en campo. Las matrices completas, la configuración y los resultados de validación están en [critical_tree_evaluation.json](../training/results/critical_tree_evaluation.json).

Para reproducir la selección y las dos pruebas: `python training/recalibrate_critical_tree.py --asset-output /tmp/critical-assets --output /tmp/critical-tree.json`. Las dependencias están fijadas en `training/requirements-evaluation.txt`.

### Geocercas circulares

La referencia de entrada o salida se determina con la posición simulada sin ruido y el radio nominal, antes de observar el error GNSS. Ambos métodos reciben las mismas observaciones. La tasa corresponde a muestras, no a notificaciones entregadas. El protocolo anterior usaba el radio adaptativo al definir la referencia; sus cifras no son comparables directamente.

| Métrica | Radio fijo | Radio adaptativo con histéresis |
| --- | ---: | ---: |
| Falsos positivos | 13,39 % | 1,29 % |
| Sensibilidad de salida | 98,86 % | 91,57 % |
| F1 | 98,62 % | 95,52 % |

Se observaron 900.000 muestras simuladas en 6.000 trayectorias. La disminución de falsas alarmas es de 12,10 puntos porcentuales, con una disminución de 7,30 puntos de sensibilidad. Se reporta el costo de la reducción junto con el beneficio. Los conteos y el intervalo por remuestreo pareado están en [independent_geofence_evaluation.json](../training/results/independent_geofence_evaluation.json).

## Alcance del cifrado y la migración

Las nuevas coordenadas remotas se cifran para el objetivo y cada observador activo mediante AES-256-GCM. La clave se deriva con X25519 y HKDF-SHA256; el sobre usa un nonce aleatorio y autentica el registro, el autor y el destinatario. Las claves privadas se almacenan con el complemento de almacenamiento seguro de Android. Firebase conserva claves públicas, sobres y metadatos, y FCM recibe un aviso genérico con IDs. El almacenamiento local usa otra clave aleatoria de 256 bits. Las reglas bloquean escrituras de la clave pública por terceros y lecturas de eventos por cuentas no vinculadas.

El prototipo confía en la autenticidad del directorio de claves de Firebase. No incorpora verificación de huellas fuera de banda, secreto hacia adelante, intercambio entre varios dispositivos de una misma cuenta ni recuperación de claves. La revocación no borra información ya descargada. Los sobres remotos anteriores no se reinterpretan como seguros: se conserva su historial de metadatos y la ubicación antigua no aparece en el mapa. La cola local anterior se intenta migrar sin borrar registros que no se puedan leer.

Los vínculos nuevos tienen identificador `objetivo:observador`. Probar primero con cuentas nuevas y datos ficticios; los vínculos históricos con IDs aleatorios no autorizan lecturas ni cifrado con la regla nueva. No desplegar sobre un proyecto existente sin revisar esos vínculos, la configuración de facturación, las claves y la conservación de datos.

## Pruebas manuales de aceptación

El [protocolo con teléfonos físicos](prueba-fisica.md) incluye el registro por ID, la separación de latencias y la captura de batería con unidades explícitas.

1. Registrar dos cuentas de prueba en Android. Enviar una solicitud; verificar que el observador no pueda acceder al historial antes de que el objetivo la acepte. Aceptar y comprobar ubicación cifrada y aviso sin coordenadas.
2. Generar un evento y un SOS sin red. Revisar que se conservan tras reiniciar la app. Restablecer la conexión: verificar un único documento por ID y entrega de la notificación. Registrar hora de generación, hora de sincronización y hora de recepción por separado.
3. Probar revocación y una tercera cuenta sin vínculo. Confirmar que no pueden leer eventos nuevos ni descifrar un sobre dirigido a otro dispositivo. Probar cierre de sesión y cambio de cuenta.
4. Repetir cruces con círculos y polígonos, de día y de noche. Registrar latencia local del árbol y latencia de entrega por separado. Para consumo de batería, conservar dispositivo, intervalo, modo y unidad del registro original.

No se han generado datos nuevos de campo, consumo de batería ni latencia entre teléfonos en esta revisión.
