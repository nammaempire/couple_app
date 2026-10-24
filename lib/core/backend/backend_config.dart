/// Where the Us server runs.
///
/// Set it when building, so no URL lives in the code:
///   flutter run --dart-define=API_URL=`https://YOUR-SERVICE.up.railway.app`
///   flutter build appbundle --dart-define=API_URL=`https://YOUR-SERVICE.up.railway.app`
///
/// Without it, debug builds use the Android emulator's view of your
/// computer (a server started with `npm run dev` in server/).
class BackendConfig {
  const BackendConfig._();

  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
}
