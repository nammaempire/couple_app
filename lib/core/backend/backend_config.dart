/// Where the Us server runs.
///
/// Set it when building, so no URL lives in the code:
///   flutter run --dart-define=API_URL=`https://YOUR-SERVICE.up.railway.app`
///   flutter build appbundle --dart-define=API_URL=`https://YOUR-SERVICE.up.railway.app`
///
/// Without it, the app uses the production server on Railway. For a server
/// running on your computer (`npm run dev` in server/), seen from the
/// Android emulator, pass --dart-define=API_URL=http://10.0.2.2:8080.
class BackendConfig {
  const BackendConfig._();

  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://us-server-production-c85a.up.railway.app',
  );
}
