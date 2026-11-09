# Protocolo de validación con dos Android físicos

Este protocolo complementa la integración emulada. Use cuentas y ubicaciones de prueba, en un proyecto Firebase separado del utilizado en la defensa privada. Anote el commit instalado en ambos teléfonos, el modelo, la versión de Android y la configuración de red. No incluya contraseñas, tokens FCM ni coordenadas privadas en el informe.

## Recepción de avisos y reconexión

1. Abra las dos cuentas y compruebe que la clave pública de cada una se registró. Envíe una solicitud de vínculo, acepte y compruebe que el observador ve una ubicación y que una cuenta sin vínculo no la puede consultar.
2. Realice al menos 20 envíos de SOS en el mismo estado de la app receptora y con la red documentada. En cada intento registre el ID del evento, hora de pulsación confirmada en el objetivo, hora de sincronización en Firestore y hora en que el aviso es visible en el observador. Sincronice ambos relojes y, si mide con video, indique su frecuencia. Resuelva el SOS entre intentos y respete el periodo de espera de la aplicación. Repita en segundo plano como condición separada.
3. En otra serie, desconecte el objetivo, genere el SOS y reinicie la app. Compruebe que el evento sigue pendiente. Reconecte y confirme que hay un único evento por ID, que el observador recibe el aviso y que puede abrir el mapa. Revocada la relación, repita la prueba de acceso.
4. Registre los intentos sin recepción como tales. Informe conteos y porcentajes por condición y las latencias de los intentos recibidos con su denominador. No mezcle tiempo sin conexión, latencia de sincronización y entrega FCM en una sola cifra.

| ID de prueba | Condición y estado | Generación | Firestore | Aviso visible | Recibido / no recibido | Observaciones |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

## Consumo de batería

En el mismo dispositivo, haga una sesión de control y una con monitoreo activo de igual duración, idealmente dos horas cada una. Repita si es posible. Mantenga comparables nivel inicial, red, brillo, pantalla y uso de otras apps. No conecte el dispositivo a alimentación durante los intervalos; use depuración inalámbrica para las capturas si está disponible.

```text
python scripts/battery_snapshot.py capture --case baseline --phase start --out control-inicio.json
python scripts/battery_snapshot.py capture --case baseline --phase end --out control-fin.json
python scripts/battery_snapshot.py capture --case monitoring --phase start --out monitoreo-inicio.json
python scripts/battery_snapshot.py capture --case monitoring --phase end --out monitoreo-fin.json
python scripts/battery_snapshot.py compare control-inicio.json control-fin.json
python scripts/battery_snapshot.py compare monitoreo-inicio.json monitoreo-fin.json
```

La comparación del nivel se expresa en **puntos porcentuales por hora**. El contador de carga, si el dispositivo lo reporta, se convierte de microamperios-hora a mAh. Ambas observaciones son del dispositivo completo; no atribuya toda la diferencia a la aplicación. No extrapole autonomía si el intervalo o la resolución del dispositivo no sustentan esa estimación.

Estos registros nuevos no permiten inferir retrospectivamente la unidad de los valores históricos de batería.
