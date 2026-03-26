# Detalhes - Contexto do Projeto

## Visão Geral

**detalhes** é um aplicativo Flutter para monitoramento e rastreamento de localização em background. O app coleta periodicamente a posição do dispositivo (a cada 10 segundos), armazena em banco de dados local SQLite e exibe uma interface para controle do serviço.

### Funcionalidades Principais

- **Serviço em background**: Executa continuamente coletando localização mesmo com o app fechado
- **Notificações persistentes**: Exibe notificação em primeiro plano para manter o serviço ativo (Android)
- **Armazenamento local**: Salva histórico de localizações em banco SQLite (`detalhes.db`)
- **Interface de controle**: Permite iniciar/parar o serviço e visualizar registros salvos
- **Status de envio**: Cada registro possui flag `sended` para controle de sincronização

## Tecnologias

| Tecnologia | Versão/Finalidade |
|------------|-------------------|
| Flutter | Framework principal |
| Dart SDK | ^3.11.0 |
| geolocator | ^10.1.0 (GPS/location) |
| flutter_background_service | ^5.0.5 (serviço background) |
| flutter_local_notifications | ^17.0.0 (notificações) |
| sqflite | ^2.3.0 (banco SQLite) |

## Estrutura do Projeto

```
lib/
├── main.dart              # Entry point, UI e lógica do serviço background
└── data/
    └── database_helper.dart  # Singleton para operações SQLite
test/
└── widget_test.dart       # Teste básico de widget
```

### Arquitetura

- **Padrão**: Singleton para `DatabaseHelper`, estado local com `StatefulWidget`
- **Service**: `FlutterBackgroundService` com timer de 10s para coleta de localização
- **Banco**: Tabela `location` com campos: `id`, `key`, `latitude`, `longitude`, `sended`, `timestamp`

## Comandos de Build e Execução

```bash
# Instalar dependências
flutter pub get

# Rodar em desenvolvimento (hot reload habilitado)
flutter run

# Rodar em dispositivo específico
flutter devices              # Listar dispositivos
flutter run -d <device_id>

# Build de release
flutter build apk            # Android APK
flutter build ios            # iOS
flutter build web            # Web

# Análise estática
flutter analyze              # Verificar lints e erros
flutter format .             # Formatar código

# Testes
flutter test                 # Rodar testes unitários
flutter test --coverage      # Com cobertura de código
```

## Configurações de Permissões

O app requer as seguintes permissões (já implementadas no código):

- **Localização**: `LocationPermission` via `geolocator`
- **Notificações**: Canal `location_channel` para Android 13+
- **Background service**: Modo foreground com notificação persistente

## Convenções de Desenvolvimento

### Análise de Código

- **Linter**: `package:flutter_lints/flutter.yaml` (configurado em `analysis_options.yaml`)
- **Comando**: `flutter analyze` antes de commits

### Estrutura de Código

- **Entry-point**: `main.dart` contém toda a lógica principal
- **Database**: `DatabaseHelper` como singleton no padrão repository simples
- **UI**: Widgets organizados em classes separadas (`MyApp`, `LocationPage`, `_LocationPageState`)

### Banco de Dados

- **Nome**: `detalhes.db` (armazenado em diretório padrão do SQLite)
- **Versão atual**: 1
- **Migrações**: Estrutura `_onUpgrade` preparada para futuras migrações

## Observações Importantes

1. **Service ID**: Notificação de foreground usa ID `888`
2. **Intervalo**: Localização coletada a cada 10 segundos via `Timer.periodic`
3. **Precisão**: `LocationAccuracy.high` para máxima precisão
4. **Teste atual**: `widget_test.dart` está desatualizado (referencia contador inexistente)

## Links Úteis

- [Documentação Flutter](https://docs.flutter.dev/)
- [geolocator package](https://pub.dev/packages/geolocator)
- [flutter_background_service](https://pub.dev/packages/flutter_background_service)

## Qwen Added Memories
- Estrutura do JSON da API GET /public/trip/key/{string}: {"id": int, "label": string, "description": string, "status": string (ex: "PLANNED"), "starting_point_id": int, "ending_point_id": int, "key": string, "driver_id": int, "driver_name": string, "starting_point_name": string, "ending_point_name": string}
