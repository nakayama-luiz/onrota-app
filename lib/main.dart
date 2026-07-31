import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/database_helper.dart';
import 'models/trip.dart';
import 'services/installation_storage.dart';
import 'widgets/api_key_input_widget.dart';
import 'widgets/location_display_widget.dart';
import 'widgets/key_input_widget.dart';
import 'widgets/cpf_input_widget.dart';
import 'widgets/route_map_widget.dart';

/// Obtém a key da viagem armazenada nas preferências
Future<String> getStoredKey() async {
  final trip = await InstallationStorage.getStoredTrip();
  return trip?.key ?? '';
}

/// Obtém a API key do cliente
Future<String> getStoredApiKey() async {
  return (await InstallationStorage.getApiKey()) ?? '';
}

/// Salva a API key do cliente
Future<String?> saveStoredApiKey(String apiKey) async {
  return InstallationStorage.saveApiKey(apiKey);
}

/// Obtém o CPF armazenado nas preferências
Future<String> getStoredCpf() async {
  return InstallationStorage.getCpf();
}

/// Salva o CPF nas preferências
Future<void> saveStoredCpf(String cpf) async {
  await InstallationStorage.saveCpf(cpf);
}

/// Remove o CPF das preferências
Future<void> removeStoredCpf() async {
  await InstallationStorage.removeCpf();
}

/// Obtém a Trip armazenada nas preferências
Future<Trip?> getStoredTrip() async {
  return InstallationStorage.getStoredTrip();
}

/// Salva a Trip nas preferências
Future<void> saveStoredTrip(Trip trip) async {
  await InstallationStorage.saveStoredTrip(trip);
}

/// Remove a Trip das preferências
Future<void> removeStoredTrip() async {
  await InstallationStorage.removeStoredTrip();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // Arquivo .env não encontrado, continuando sem variáveis de ambiente
    print('Aviso: .env não encontrado. Usando valores padrão.');
  }
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Configurar notificações primeiro
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );

  // Criar canal de notificação com importância alta para foreground service
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'location_channel',
    'Location Service',
    description: 'Canal para serviço de localização em background',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  await androidImplementation?.createNotificationChannel(channel);

  // Solicitar permissão de notificação para Android 13+
  await androidImplementation?.requestNotificationsPermission();

  // Configurar o serviço
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'location_channel',
      initialNotificationTitle: 'Monitoramento de Localização',
      initialNotificationContent: 'Serviço em execução',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

/// Envia localizações não enviadas para o endpoint
/// Retorna (true, null) se sucesso, (false, mensagemDeErro) se falhou
Future<(bool, String?)> sendUnsendedLocations() async {
  try {
    final apiKey = await getStoredApiKey();
    final tripKey = await getStoredKey();

    if (apiKey.isEmpty) {
      final service = FlutterBackgroundService();
      await DatabaseHelper.instance.deleteAllLocations();
      await removeStoredTrip();
      service.invoke('auth_error', {
        'message': 'API key do cliente ausente. Reconfigure o dispositivo.',
      });
      return (false, 'API key do cliente ausente.');
    }

    if (tripKey.isEmpty) {
      return (false, 'Key da viagem ausente.');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
    };
    const url = 'https://onrota.nakafest.site/log';

    final tripResponse = await http.get(
      Uri.parse('https://onrota.nakafest.site/public/trip/key/$tripKey'),
      headers: headers,
    );

    if (tripResponse.statusCode == 401 || tripResponse.statusCode == 403) {
      final service = FlutterBackgroundService();
      await DatabaseHelper.instance.deleteAllLocations();
      await removeStoredTrip();
      await InstallationStorage.clearApiKey();
      service.invoke('auth_error', {
        'message': 'A API key do cliente foi rejeitada. Reconfigure o dispositivo.',
      });
      return (
        false,
        'A API key do cliente foi rejeitada. Reconfigure o dispositivo.',
      );
    }

    if (tripResponse.statusCode != 200) {
      final errorMsg = 'Erro ${tripResponse.statusCode}: ${tripResponse.body}';
      print('Erro ao consultar trip: $errorMsg');
      return (false, errorMsg);
    }

    final data = jsonDecode(tripResponse.body) as Map<String, dynamic>;
    final result = Trip.fromJson(data);

    if (result.status == 'FINISHED') {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      return (true, null);
    }

    final dbHelper = DatabaseHelper.instance;
    final unsendedLocations = await dbHelper.getUnsendedLocations();

    if (unsendedLocations.isEmpty) {
      return (true, null);
    }

    // Prepara a lista de eventos como JSON
    final events = unsendedLocations.map((location) {
      final locationKey = location['key'];
      final effectiveKey = (locationKey == null || locationKey == '')
          ? tripKey
          : locationKey;
      return {
        'id': location['id'],
        'key': effectiveKey,
        'latitude': location['latitude'],
        'longitude': location['longitude'],
        'timestamp': location['timestamp'],
        'speed': location['speed'] ?? 0,
      };
    }).toList();

    final payload = jsonEncode(events);

    // Envia para o endpoint usando variáveis de ambiente

    // Envia para o endpoint
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: payload,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Marca como enviadas
      final ids = unsendedLocations.map((l) => l['id'] as int).toList();
      await dbHelper.markLocationsAsSended(ids);
      print('Localizações enviadas com sucesso: ${ids.length} registros');
      return (true, null);
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      final service = FlutterBackgroundService();
      await DatabaseHelper.instance.deleteAllLocations();
      await removeStoredTrip();
      await InstallationStorage.clearApiKey();
      service.invoke('auth_error', {
        'message': 'A API key do cliente foi rejeitada durante a sincronização.',
      });
      final errorMsg =
          'A API key do cliente foi rejeitada durante a sincronização.';
      print(errorMsg);
      return (false, errorMsg);
    } else {
      final errorMsg = 'Erro ${response.statusCode}: ${response.body}';
      print('Erro ao enviar localizações: $errorMsg');
      return (false, errorMsg);
    }
  } on http.ClientException catch (e) {
    final errorMsg =
        'Sem conexão com a internet. Verifique sua rede e tente novamente.';
    print('Erro de conexão ao enviar localizações: $e');
    return (false, errorMsg);
  } catch (e) {
    final errorMsg = 'Erro ao enviar: ${e.toString()}';
    print('Erro ao enviar localizações: $errorMsg');
    return (false, errorMsg);
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance? service) async {
  // DartPluginRegistrant é inicializado automaticamente pelo Flutter
  // em versões 3.10+

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service?.on('stopService').listen((event) {
    service.stopSelf();
  });

  service?.on('auth_error').listen((event) {
    service.stopSelf();
  });

  // Envia localizações não enviadas a cada 30 segundos
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    await sendUnsendedLocations();
  });

  // Atualiza localização a cada 10 segundos
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service == null) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final timestamp = DateTime.now().toUtc().toIso8601String();
      final key = await getStoredKey();

      if (key.isEmpty) {
        return;
      }

      // Envia atualização via stream
      service.invoke('update_location', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': timestamp,
        'key': key,
        'speed': position.speed,
      });

      // Salva no banco de dados
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.insertLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        key: key,
        timestamp: timestamp,
        speed: position.speed,
      );
    } catch (e) {
      print('Erro ao obter localização: $e');
      service.invoke('location_error', {
        'error': 'Não foi possível obter a localização: ${e.toString()}',
      });
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: LocationPage());
  }
}

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final FlutterBackgroundService _service = FlutterBackgroundService();
  String _apiKey = '';
  String _cpf = '';
  Trip? _currentTrip;
  bool _isRunning = false;
  int _currentIndex = 0; // 0 = Localização, 1 = Tarefas, 2 = Rota
  bool _showedSnackbar = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadStoredData();

    // Escuta atualizações de localização do background service
    _service.on('update_location').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _currentPosition = Position(
            latitude: (event['latitude'] as num).toDouble(),
            longitude: (event['longitude'] as num).toDouble(),
            timestamp: DateTime.parse(event['timestamp'] as String),
            accuracy: (event['accuracy'] as num?)?.toDouble() ?? 0,
            speed: (event['speed'] as num?)?.toDouble() ?? 0,
            altitude: 0,
            speedAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            altitudeAccuracy: 0,
          );
        });
      }
    });

    _service.on('auth_error').listen((event) async {
      final message = event?['message'] as String?;
      await _handleApiKeyInvalid(message);
    });

    // Solicita permissão ao abrir o app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestLocationPermission();
    });
  }

  Future<void> _loadStoredData() async {
    final apiKey = await getStoredApiKey();
    final cpf = await getStoredCpf();
    final trip = await getStoredTrip();
    if (mounted) {
      setState(() {
        _apiKey = apiKey;
        _cpf = cpf;
        _currentTrip = trip;
      });
    }
  }

  void _handleCpfSubmitted(String cpf) async {
    await saveStoredCpf(cpf);
    if (mounted) {
      setState(() {
        _cpf = cpf;
      });
    }
  }

  Future<void> _handleApiKeySaved(String apiKey) async {
    final previousApiKey = await saveStoredApiKey(apiKey);
    final normalizedApiKey = apiKey.trim();

    if (previousApiKey != null &&
        previousApiKey.trim().isNotEmpty &&
        previousApiKey.trim() != normalizedApiKey) {
      await _clearLocalDataForTenantChange();
    }

    final trip = await getStoredTrip();
    if (!mounted) return;

    setState(() {
      _apiKey = normalizedApiKey;
      _currentTrip = trip;
      _currentIndex = 0;
      _showedSnackbar = false;
    });
  }

  Future<void> _clearLocalDataForTenantChange() async {
    await removeStoredTrip();
    await DatabaseHelper.instance.deleteAllLocations();
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    if (mounted) {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _handleApiKeyInvalid([String? message]) async {
    await removeStoredTrip();
    await InstallationStorage.clearApiKey();
    await DatabaseHelper.instance.deleteAllLocations();
    final service = FlutterBackgroundService();
    service.invoke('stopService');

    if (!mounted) return;

    setState(() {
      _apiKey = '';
      _currentTrip = null;
      _isRunning = false;
      _currentIndex = 0;
      _showedSnackbar = false;
    });

    if (message != null && message.isNotEmpty) {
      _showErrorAlert(message);
    }
  }

  void _handleTripChanged(Trip? trip) async {
    if (trip != null) {
      await saveStoredTrip(trip);
      setState(() {
        _showedSnackbar = false; // Mostra snackbar novamente
      });
    } else {
      await removeStoredTrip();
      await DatabaseHelper.instance.deleteAllLocations();
      final service = FlutterBackgroundService();
      service.invoke('stopService');
    }
    if (mounted) {
      setState(() {
        _currentTrip = trip;
      });
    }
  }

  /// Verifica todas as permissões necessárias antes de iniciar o serviço
  /// Retorna uma tupla (temPermissao, mensagemErro)
  Future<(bool, String?)> _checkAllPermissions() async {
    // 1. Verificar serviço de localização ativado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return (
        false,
        'O serviço de localização está desativado. '
            'Ative o GPS nas configurações do dispositivo.',
      );
    }

    // 2. Verificar permissão de localização (deve ser "always" para background)
    LocationPermission locationPermission = await Geolocator.checkPermission();

    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
    }

    if (locationPermission == LocationPermission.denied) {
      return (false, 'Permissão de localização negada.');
    }

    if (locationPermission == LocationPermission.deniedForever) {
      return (
        false,
        'Permissão de localização negada permanentemente. '
            'Vá em Configurações > Aplicativos > detalhes > Permissões e ative a permissão de localização.',
      );
    }

    // Verificar se é "always" (necessário para background)
    if (locationPermission != LocationPermission.always) {
      return (
        false,
        'A permissão de localização deve ser definida como "Sempre" para funcionar em background. '
            'Vá em Configurações > Aplicativos > detalhes > Permissões > Localização > selecione "Sempre".',
      );
    }

    // 3. Verificar permissão de notificação (Android 13+)
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      final bool? notificationsAllowed =
          await androidImplementation.areNotificationsEnabled();

      if (notificationsAllowed == null || !notificationsAllowed) {
        return (
          false,
          'A permissão de notificação é necessária para manter o serviço ativo em background. '
              'Ative nas configurações do aplicativo.',
        );
      }
    }

    // Todas as permissões OK
    return (true, null);
  }

  Future<void> _startService() async {
    // Verifica se há uma key válida antes de iniciar
    if (_currentTrip == null) {
      _showErrorAlert(
        'É necessário validar uma key antes de iniciar o serviço.',
      );
      return;
    }

    if (_apiKey.isEmpty) {
      _showErrorAlert(
        'É necessário configurar a API key do cliente antes de iniciar o serviço.',
      );
      return;
    }

    // Verifica todas as permissões antes de iniciar
    final (hasPermission, errorMessage) = await _checkAllPermissions();

    if (!hasPermission) {
      _showErrorAlert(errorMessage ?? 'Permissões insuficientes.');
      return;
    }

    // Todas as permissões OK, iniciar serviço
    await _service.startService();
    setState(() {
      _isRunning = true;
    });
  }

  Future<void> _syncLocations() async {
    final (success, errorMessage) = await sendUnsendedLocations();
    if (!mounted) return;

    if (!success &&
        errorMessage != null &&
        errorMessage.contains('API key do cliente')) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          success ? 'Sucesso' : 'Erro de Sincronização',
          style: TextStyle(color: success ? Colors.green : Colors.red),
        ),
        content: Text(
          success
              ? 'Localizações sincronizadas com sucesso!'
              : errorMessage ?? 'Não foi possível sincronizar as localizações.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorAlert(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor de Localização'),
        backgroundColor: _isRunning ? Colors.green : null,
        actions: _apiKey.isNotEmpty
            ? [
                IconButton(
                  tooltip: 'Reconfigurar API key',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _handleApiKeyInvalid(),
                ),
              ]
            : null,
      ),
      body: _buildCurrentStep(),
      bottomNavigationBar: _currentTrip != null
          ? _buildBottomNavigation()
          : null,
    );
  }

  Widget _buildBottomNavigation() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.location_on),
          label: 'Localização',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.task), label: 'Tarefas'),
        BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Rota'),
      ],
    );
  }

  Widget _buildCurrentStep() {
    // Etapa 0: API key do cliente não preenchida
    if (_apiKey.isEmpty) {
      return ApiKeyInputWidget(
        currentApiKey: _apiKey,
        onApiKeySaved: (apiKey) => _handleApiKeySaved(apiKey),
      );
    }

    // Etapa 1: CPF não preenchido
    if (_cpf.isEmpty) {
      return CpfInputWidget(
        onCpfSubmitted: (cpf) => _handleCpfSubmitted(cpf),
      );
    }

    // Etapa 2: CPF preenchido, mas sem key válida
    if (_currentTrip == null) {
      return Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'CPF cadastrado: ${_cpf.replaceAll(RegExp(r'(\d{3})(\d{3})(\d{3})(\d{2})'), r'$1.$2.$3-$4')}',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Por favor, informe sua key para continuar',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: KeyInputWidget(
              currentTrip: _currentTrip,
              apiKey: _apiKey,
              onTripChanged: (trip) => _handleTripChanged(trip),
              onApiKeyInvalid: () => _handleApiKeyInvalid(),
            ),
          ),
        ],
      );
    }

    // Etapa 3: Key válida - mostra localização ou tarefas
    if (!_showedSnackbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNavigationSnackbar();
      });
      _showedSnackbar = true;
    }

    return switch (_currentIndex) {
      0 => _buildLocationTab(),
      1 => _buildTasksTab(),
      2 => _buildRouteTab(),
      _ => _buildLocationTab(),
    };
  }

  void _showNavigationSnackbar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final snackBar = SnackBar(
      content: const Text('Key validada com sucesso!'),
      action: SnackBarAction(
        label: 'Ver Tarefas',
        onPressed: () {
          setState(() {
            _currentIndex = 1;
          });
        },
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Widget _buildLocationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // CPF e informações da trip
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Motorista',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          _currentTrip!.driverName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.grey),
                    onPressed: () async {
                      await removeStoredCpf();
                      await removeStoredTrip();
                      await DatabaseHelper.instance.deleteAllLocations();
                      final service = FlutterBackgroundService();
                      service.invoke('stopService');
                      if (mounted) {
                        setState(() {
                          _cpf = '';
                          _currentTrip = null;
                          _currentIndex = 0;
                          _isRunning = false;
                        });
                      }
                    },
                    tooltip: 'Sair',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LocationDisplayWidget(
            currentTrip: _currentTrip,
            isRunning: _isRunning,
            onStartService: _startService,
            onSyncLocations: _syncLocations,
          ),
        ],
      ),
    );
  }

  Widget _buildTasksTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.task, size: 64, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            'Tarefas',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Em breve...',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTab() {
    return RouteMapWidget(
      currentTrip: _currentTrip,
      currentPosition: _currentPosition,
    );
  }

  Future<void> _checkAndRequestLocationPermission() async {
    // 1. Verificar serviço de localização ativado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ative o serviço de localização do dispositivo.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // 2. Verificar permissão atual
    LocationPermission permission = await Geolocator.checkPermission();

    // Se negada, solicitar permissão (mostrará "Ao usar o app" no Android 11+)
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // Se ainda negada ou negada permanentemente
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A permissão de localização é necessária para o funcionamento do app.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // 3. Se permissão é "whileInUse", solicitar "always" (Android 11+ requer 2 etapas)
    if (permission == LocationPermission.whileInUse) {
      if (mounted) {
        // Mostrar diálogo explicando por que precisa de "Sempre"
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissão de Localização'),
            content: const Text(
              'Para que o monitoramento funcione mesmo com o app fechado, '
              'é necessário conceder permissão de localização "Sempre".\n\n'
              'Na próxima tela, selecione "Permitir sempre".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );

        if (shouldRequest == true) {
          // Solicitar permissão "always"
          permission = await Geolocator.requestPermission();

          // Verificar se conseguiu a permissão "always"
          if (permission != LocationPermission.always) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'É necessário selecionar "Permitir sempre" nas configurações '
                    'de localização do app para o funcionamento correto.',
                  ),
                  duration: Duration(seconds: 8),
                ),
              );
            }
          }
        }
      }
    }

    // 4. Se permissão "always" concedida, mostrar sucesso
    if (permission == LocationPermission.always && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissão de localização "Sempre" concedida!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
