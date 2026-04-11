import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'detalhes.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE location (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        sended INTEGER NOT NULL DEFAULT 0,
        timestamp TEXT NOT NULL,
        speed REAL NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Verifica se a coluna speed já existe antes de adicionar
      final columns = await db.rawQuery('PRAGMA table_info(location)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      
      if (!columnNames.contains('speed')) {
        await db.execute('ALTER TABLE location ADD COLUMN speed REAL DEFAULT 0');
      }
    }
  }

  // Inserir uma nova localização
  Future<int> insertLocation({
    required double latitude,
    required double longitude,
    String key = '',
    int sended = 0,
    required String timestamp,
    double speed = 0,
  }) async {
    final db = await database;
    return await db.insert('location', {
      'key': key,
      'latitude': latitude,
      'longitude': longitude,
      'sended': sended,
      'timestamp': timestamp,
      'speed': speed,
    });
  }

  // Buscar todas as localizações
  Future<List<Map<String, dynamic>>> getAllLocations() async {
    final db = await database;
    return await db.query('location', orderBy: 'timestamp DESC');
  }

  // Buscar localizações não enviadas
  Future<List<Map<String, dynamic>>> getUnsendedLocations() async {
    final db = await database;
    return await db.query('location', where: 'sended = ?', whereArgs: [0]);
  }

  // Marcar localização como enviada
  Future<void> markLocationAsSended(int id) async {
    final db = await database;
    await db.update('location', {'sended': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // Marcar múltiplas localizações como enviadas
  Future<void> markLocationsAsSended(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update('location', {'sended': 1}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  // Deletar todas as localizações
  Future<void> deleteAllLocations() async {
    final db = await database;
    await db.delete('location');
  }
}
