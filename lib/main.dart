import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/database_helper.dart';
import 'models/trip.dart';
import 'widgets/location_display_widget.dart';
import 'widgets/trip_select_widget.dart';
import 'widgets/cpf_input_widget.dart';
import 'services/api_service.dart';

/// Obtém a key armazenada nas preferências
Future<String> getStoredKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('log_key') ?? '';
}

/// Salva a key nas preferências
Future<void> saveStoredKey(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('log_key', key);
}

/// Obtém o CPF armazenado nas preferências
Future<String> getStoredCpf() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('cpf') ?? '';
}

/// Salva o CPF nas preferências
Future<void> saveStoredCpf(String cpf) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('cpf', cpf);
}

/// Remove o CPF das preferências
Future<void> removeStoredCpf() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('cpf');
}

/// Obtém a Trip armazenada nas preferências
Future<Trip?> getStoredTrip() async {
  final prefs = await SharedPreferences.getInstance();
  // O serviço em background roda em outro isolate, com cache próprio das
  // preferências: sem reload ele não vê a corrida trocada na tela.
  await prefs.reload();
  final tripJson = prefs.getString('trip_data');
  if (tripJson == null || tripJson.isEmpty) {
    return null;
  }
  return Trip.fromJson(jsonDecode(tripJson));
}

/// Salva a Trip nas preferências
Future<void> saveStoredTrip(Trip trip) async {
  final prefs = await SharedPreferences.getInstance();
  // ponytail: token da corrida em SharedPreferences, em claro. Ele só grava
  // posições desta corrida e expira em 7 dias; se virar credencial mais ampla,
  // mover para flutter_secure_storage.
  await prefs.setString('trip_data', jsonEncode(trip.toJson()));
}

/// Remove a Trip das preferências
Future<void> removeStoredTrip() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('trip_data');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // Arquivo .env não encontrado, continuando sem variáveis de ambiente
    debugPrint('Aviso: .env não encontrado. Usando valores padrão.');
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
    final trip = await getStoredTrip();

    if (trip == null || trip.token.isEmpty) {
      return (false, 'Nenhuma corrida selecionada. Entre com CPF e placa.');
    }

    final key = trip.key;
    final headers = ApiService.headers(trip.token);
    final url = '${ApiService.baseUrl}/log';

    final tripResponse = await http.get(
      Uri.parse('${ApiService.baseUrl}/public/trip/key/$key'),
      headers: headers,
    );

    // Token expirado/inválido não melhora com retentativa: pede novo login.
    if (tripResponse.statusCode == 401 || tripResponse.statusCode == 403) {
      return (false, 'Sessão expirada. Saia e entre novamente com CPF e placa.');
    }

    final data = jsonDecode(tripResponse.body);
    final result = Trip.fromJson(data);

    if (result.status == 'FINISHED') {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      return (true, null);
    }

    final dbHelper = DatabaseHelper.instance;
    // O token só grava na própria corrida: posições pendentes de outra corrida
    // (ou de outro cliente) nunca saem com ele.
    // ponytail: essas ficam na fila local; limpar se o volume incomodar.
    final unsendedLocations = (await dbHelper.getUnsendedLocations())
        .where((l) => l['key'] == null || l['key'] == '' || l['key'] == key)
        .toList();

    if (unsendedLocations.isEmpty) {
      return (true, null);
    }

    // Prepara a lista de eventos como JSON
    final events = unsendedLocations.map((location) {
      final locationKey = location['key'];
      final effectiveKey = (locationKey == null || locationKey == '')
          ? key
          : locationKey;
      return {
        'id': location['id'],
        'key': effectiveKey,
        'latitude': location['latitude'],
        'longitude': location['longitude'],
        'timestamp': location['timestamp'],
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
      debugPrint('Localizações enviadas com sucesso: ${ids.length} registros');
      return (true, null);
    } else {
      final errorMsg = 'Erro ${response.statusCode}: ${response.body}';
      debugPrint('Erro ao enviar localizações: $errorMsg');
      return (false, errorMsg);
    }
  } on http.ClientException catch (e) {
    final errorMsg =
        'Sem conexão com a internet. Verifique sua rede e tente novamente.';
    debugPrint('Erro de conexão ao enviar localizações: $e');
    return (false, errorMsg);
  } catch (e) {
    final errorMsg = 'Erro ao enviar: ${e.toString()}';
    debugPrint('Erro ao enviar localizações: $errorMsg');
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

      final timestamp = DateTime.now().toIso8601String();
      final key = await getStoredKey();

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
      );
    } catch (e) {
      debugPrint('Erro ao obter localização: $e');
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
  String _cpf = '';
  List<Trip>? _trips; // resultado do login, antes de escolher a corrida
  Trip? _currentTrip;
  bool _isRunning = false;
  int _currentIndex = 0; // 0 = Localização, 1 = Tarefas
  bool _showedSnackbar = false;

  @override
  void initState() {
    super.initState();
    _loadStoredData();

    // Solicita permissão ao abrir o app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestLocationPermission();
    });
  }

  Future<void> _loadStoredData() async {
    final cpf = await getStoredCpf();
    final trip = await getStoredTrip();
    if (mounted) {
      setState(() {
        _cpf = cpf;
        // Corrida salva por versão antiga (sem token) não envia nada: novo login.
        _currentTrip = (trip == null || trip.token.isEmpty) ? null : trip;
      });
    }
  }

  void _handleLogin(String cpf, List<Trip> trips) async {
    await saveStoredCpf(cpf);
    if (!mounted) return;
    setState(() {
      _cpf = cpf;
      _trips = trips;
    });
    if (trips.length == 1) {
      _handleTripChanged(trips.first);
    }
  }

  void _handleTripChanged(Trip? trip) async {
    if (trip != null) {
      await saveStoredTrip(trip);
      final key = trip.key;
      await saveStoredKey(key);
      setState(() {
        _showedSnackbar = false; // Mostra snackbar novamente
      });
    } else {
      await removeStoredTrip();
    }
    if (mounted) {
      setState(() {
        _currentTrip = trip;
      });
    }
  }

  Future<void> _startService() async {
    // Verifica se há uma key válida antes de iniciar
    if (_currentTrip == null) {
      _showErrorAlert(
        'É necessário selecionar uma corrida antes de iniciar o serviço.',
      );
      return;
    }

    await _service.startService();
    setState(() {
      _isRunning = true;
    });
  }

  Future<void> _syncLocations() async {
    final (success, errorMessage) = await sendUnsendedLocations();
    if (!mounted) return;

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
      ],
    );
  }

  Widget _buildCurrentStep() {
    if (_currentTrip == null) {
      // Etapa 1: login por CPF + placa
      if (_trips == null) {
        return CpfInputWidget(currentCpf: _cpf, onLogin: _handleLogin);
      }

      // Etapa 2: mais de uma corrida aberta — o motorista escolhe
      return TripSelectWidget(
        trips: _trips!,
        onSelected: _handleTripChanged,
        onBack: () => setState(() => _trips = null),
      );
    }

    // Etapa 3: corrida selecionada - mostra localização ou tarefas
    if (!_showedSnackbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNavigationSnackbar();
      });
      _showedSnackbar = true;
    }

    return _currentIndex == 0 ? _buildLocationTab() : _buildTasksTab();
  }

  void _showNavigationSnackbar() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final snackBar = SnackBar(
      content: const Text('Corrida selecionada!'),
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
                      if (mounted) {
                        setState(() {
                          _cpf = '';
                          _trips = null;
                          _currentTrip = null;
                          _currentIndex = 0;
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

  Future<void> _checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ative o serviço de localização do dispositivo.'),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (!mounted) return;

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (!mounted) return;
    }

    if (permission == LocationPermission.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de localização negada.')),
      );
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permissão negada permanentemente. Ative nas configurações.',
          ),
        ),
      );
      await Geolocator.openAppSettings();
      return;
    }
  }
}
