# Geolocalización con geocercas adaptativas

Prototipo Android de la UMSA. Una persona monitoreada comparte su ubicación con observadores autorizados. El motor ejecuta reglas explícitas y un árbol de decisión local; la cola Hive conserva eventos mientras no hay conexión.

## Revisión posterior a la defensa privada

La revisión conserva el árbol y sus umbrales desplegados en el repositorio de origen. Añade una evaluación reproducible, compara las geocercas contra una referencia independiente y corrige el manejo de alertas, de la cola y del cifrado. La revisión no representa la compilación usada en la defensa privada. El [registro de validación](docs/validacion-defensa.md) distingue resultados nuevos, resultados históricos y pruebas pendientes.

## Ejecutar en un entorno de prueba

1. Instalar Flutter 3.38 o posterior, JDK 17 y las herramientas Android. Ejecutar `flutter pub get`, `flutter analyze --no-fatal-infos --no-fatal-warnings` y `flutter test`.
2. Para una prueba con teléfonos, preparar un proyecto Firebase **de prueba** con Authentication por correo y contraseña, Firestore y Cloud Messaging. Registrar el paquete Android `com.umsa.geocercas`. Colocar su configuración `google-services.json` en `android/app/`, sin agregarla al repositorio. No incluir una cuenta de servicio en la app.
3. En ese proyecto de prueba, configurar las reglas, los índices y las funciones de este repositorio. Las funciones se ejecutan con credenciales administradas por Firebase; el despliegue de Functions puede requerir facturación. Confirmar el proyecto y el costo antes de ejecutar un despliegue. No aplicar estas reglas a datos existentes sin un plan de migración.
4. Iniciar sesión en dos instalaciones con cuentas de prueba diferentes, una de objetivo y otra de observador. Abrir ambas aplicaciones con conexión para registrar sus claves públicas antes de aceptar un vínculo. Seguir las pruebas manuales del [registro](docs/validacion-defensa.md).

Las reglas se pueden probar con el emulador sin tocar un proyecto real:

```bash
npm --prefix functions install
npm --prefix functions test
npx --yes firebase-tools@14 emulators:exec --only firestore --project demo-geocercas "npm --prefix functions run test:rules"
```

## Reproducir las evaluaciones nuevas

```bash
python -m pip install -r training/requirements-evaluation.txt
python training/evaluate_shipped_tree.py
python training/evaluate_geofences.py
```

Los JSON de `training/results/` distinguen las evaluaciones por protocolo. No volver a entrenar el árbol para reproducir el artefacto evaluado: el evaluador usa el árbol, la normalización y los umbrales que lee la aplicación.
