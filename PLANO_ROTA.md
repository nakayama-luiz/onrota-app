# Plano de Implementação - Funcionalidade de Rota no Mapa

## Visão Geral
Exibir um mapa com a rota entre o **ponto de partida** e o **ponto de chegada** da trip, usando `flutter_map` (OpenStreetMap), com a localização atual do motorista sobreposta.

### Decisões Tomadas
- **Objetivo**: Navegação visual do ponto A → B
- **Map Provider**: flutter_map (OpenStreetMap, gratuito, sem API key)
- **Coordenadas**: Estratégia condicional (ver abaixo)
- **Navegação**: Apenas visual (sem voz, sem turn-by-turn)

---

## Estratégia de Coordenadas

### Estrutura da Trip
A API retorna a trip com objetos `loading` (ponto de partida) e `unloading` (ponto de chegada), que **podem** conter `latitude` e `longitude`.

**Exemplo de resposta da API**:
```json
{
  "id": 1,
  "key": "ABC123",
  "loading": {
    "name": "Centro de Distribuição A",
    "latitude": -23.5505,
    "longitude": -46.6333
  },
  "unloading": {
    "name": "Cliente B",
    "latitude": -23.5605,
    "longitude": -46.6433
  }
}
```

### Lógica de Obtenção de Coordenadas

```
1. Verificar se trip.loading.latitude e trip.loading.longitude existem
   ├─ SIM → Usar como coordenadas do ponto de partida
   └─ NÃO → Fazer geocoding de trip.loading.name

2. Verificar se trip.unloading.latitude e trip.unloading.longitude existem
   ├─ SIM → Usar como coordenadas do ponto de chegada
   └─ NÃO → Fazer geocoding de trip.unloading.name
```

**Prioridade**: Coordenadas da API > Geocoding

---

## Modelo Trip Atualizado

**Arquivo**: `lib/models/trip.dart`

Adicionar campos opcionais para coordenadas:

```dart
class Trip {
  // ... campos existentes ...
  
  // Loading (ponto de partida)
  final double? loadingLatitude;
  final double? loadingLongitude;
  final String? loadingName;
  
  // Unloading (ponto de chegada)
  final double? unloadingLatitude;
  final double? unloadingLongitude;
  final String? unloadingName;
  
  // Métodos auxiliares
  bool get hasLoadingCoordinates => 
      loadingLatitude != null && loadingLongitude != null;
  
  bool get hasUnloadingCoordinates => 
      unloadingLatitude != null && unloadingLongitude != null;
}
```

---

## Arquitetura Proposta

```
lib/
├── models/
│   ├── trip.dart                    # Atual: adicionar coordenadas (opcional)
│   └── route_info.dart              # Novo: dados da rota calculada
├── services/
│   ├── api_service.dart             # Atual
│   ├── geocoding_service.dart       # Novo: geocoding dos nomes via Nominatim
│   └── route_service.dart           # Novo: calcular rota via OSRM
├── widgets/
│   ├── route_map_widget.dart        # Novo: mapa com flutter_map
│   └── location_display_widget.dart # Mantido: sem alterações
└── main.dart                        # Atual: adicionar aba "Rota"
```

---

## Etapas de Implementação

### Etapa 1: Adicionar dependências
**Arquivo**: `pubspec.yaml`

- `flutter_map: ^7.0.2` (mapa OpenStreetMap)
- `latlong2: ^0.9.1` (coordenadas geográficas)
- `osrm: ^0.0.8` (rotas via OSRM)

**Status**: ✅ Concluído

---

### Etapa 2: Atualizar modelo Trip
**Arquivo**: `lib/models/trip.dart`

**Mudanças**:
- Adicionar campos opcionais: `loadingLatitude`, `loadingLongitude`, `loadingName`
- Adicionar campos opcionais: `unloadingLatitude`, `unloadingLongitude`, `unloadingName`
- Adicionar getters auxiliares: `hasLoadingCoordinates`, `hasUnloadingCoordinates`
- Atualizar `fromJson()` para ler objetos `loading` e `unloading` da resposta da API
- Manter compatibilidade com respostas antigas (valores default null)

**Status**: ✅ Concluído

---

### Etapa 3: Criar GeocodingService (fallback)
**Arquivo**: `lib/services/geocoding_service.dart`

**Responsabilidade**: Converter nomes de locais em coordenadas (lat/lng) **apenas quando a API não fornecer**

**Implementação**:
- Usar API gratuita do Nominatim (`https://nominatim.openstreetmap.org/search`)
- Método: `Future<LatLng?> geocode(String address)`
- Adicionar header `User-Agent` obrigatório
- Tratar erros de rede e resultados vazios
- Limitar a 1 request/segundo (limite do Nominatim)
- Método adicional: `geocodeAll(List<String>)` para múltiplos endereços

**Quando será usado**:
- Apenas se `trip.loading.latitude` ou `trip.unloading.latitude` forem nulos
- Geocodificar `trip.loadingName` ou `trip.unloadingName` como fallback

**Status**: ✅ Concluído

---

### Etapa 4: Criar RouteService
**Arquivo**: `lib/services/route_service.dart`

**Responsabilidade**: Calcular rota entre dois pontos via OSRM

**Implementação**:
- Usar API pública OSRM (`http://router.project-osrm.org/route/v1/driving/`)
- Método: `Future<List<LatLng>> getRoute(LatLng start, LatLng end)`
- Parsear resposta JSON e extrair geometria GeoJSON da rota
- Tratar erros de rede e rotas não encontradas
- Retornar lista de coordenadas formando a polyline
- Método adicional: `getRouteDistance()` para distância total em metros

**Status**: ✅ Concluído

---

**Status**: ✅ Concluído

---

### Etapa 5: Criar RouteMapWidget
**Arquivo**: `lib/widgets/route_map_widget.dart`

**Props**:
- `Trip? currentTrip` - dados da viagem
- `Position? currentPosition` - localização atual do motorista

**Estado interno**:
- `LatLng? _startPoint` - coordenadas do ponto de partida
- `LatLng? _endPoint` - coordenadas do ponto de chegada
- `List<LatLng>? _routePoints` - pontos da rota calculada
- `String? _errorMessage` - mensagem de erro
- `bool _isLoading` - estado de carregamento

**Funcionamento**:
1. No `initState()`, obter coordenadas com lógica condicional:
   - Se `trip.hasLoadingCoordinates` → usar `trip.loadingLatitude/Longitude`
   - Senão → chamar `GeocodingService.geocode(trip.loadingName)`
   - Mesmo para ponto de chegada
2. Com coordenadas, chamar `RouteService` para calcular rota
3. Exibir mapa com:
   - **Tile layer**: OpenStreetMap
   - **Marker verde**: Ponto de partida (loading)
   - **Marker vermelho**: Ponto de chegada (unloading)
   - **Polyline azul**: Rota calculada
   - **Marker azul**: Localização atual do motorista
   - **Botão de centralizar**: Volta para localização atual
4. Quando `currentPosition` mudar, atualizar marker azul
5. Exibir loading enquanto obtém coordenadas/calcula rota
6. Exibir erro se falhar

**Status**: ✅ Concluído

---

### Etapa 6: Adicionar aba "Rota" no main.dart
**Arquivo**: `lib/main.dart`

**Mudanças**:
- Adicionar import de `RouteMapWidget`
- Adicionar variável `_currentPosition` ao estado
- Adicionar listener do stream `update_location` no `initState()`
- Adicionar aba "Rota" (ícone `Icons.map`) ao `BottomNavigationBar`
- Adicionar método `_buildRouteTab()` retornando `RouteMapWidget`
- Atualizar `_buildCurrentStep()` com switch para 3 abas

**Status**: ✅ Concluído

---

### Etapa 7: Ajustes e Otimizações

**Performance**:
- Reduzir frequência de atualização do mapa quando app em background
- Usar `MapController` para evitar rebuilds desnecessários
- Cache de coordenadas geocodificadas (evitar refazer requests)

**UX**:
- Animação suave ao mover marker do motorista
- Zoom automático para mostrar rota completa + localização atual
- Indicador de precisão do GPS (círculo ao redor do marker)

**Background Service**:
- Garantir que mapa continue funcionando com serviço ativo
- Otimizar consumo de bateria (reduzir update rate se necessário)

---

## Pontos de Atenção

### Geocoding (Nominatim)
- **Limite**: 1 request/segundo
- **User-Agent obrigatório**: Usar `detalhes/1.0 (Flutter App)`
- **Cache**: Salvar coordenadas geocodificadas para evitar requests repetidos
- **Fallback**: Se falhar, permitir ao usuário inserir coordenadas manualmente

### OSRM (Roteamento)
- **Servidor demo**: `router.project-osrm.org` (pode ter limites/instabilidade)
- **Para produção**: Considerar self-hosted ou serviço pago
- **Alternativa**: Usar `flutter_map_routing` que abstrai o provider

### flutter_map
- **Versão**: Usar ^7.0.0 (compatível com Flutter 3.10+)
- **Performance**: Evitar muitos markers/polylines simultâneos
- **Plugins**: Usar `flutter_map_marker_cluster` se necessário no futuro

---

## Ordem de Execução

1. ✅ Adicionar dependências ao `pubspec.yaml`
2. ✅ Atualizar modelo `Trip` com campos de loading/unloading
3. ✅ Criar `GeocodingService` (fallback)
4. ✅ Criar `RouteService`
5. ✅ Criar `RouteMapWidget` básico com markers
6. ✅ Integrar lógica condicional de coordenadas (API > Geocoding)
7. ✅ Adicionar localização em tempo real
8. ✅ Adicionar aba "Rota" ao `BottomNavigationBar` no `main.dart`
9. ⏳ Testes e ajustes finais

---

## Referências

- [flutter_map docs](https://docs.fleaflet.dev/)
- [Nominatim API](https://nominatim.org/release-docs/develop/api/Search/)
- [OSRM API docs](http://project-osrm.org/docs/v5.5.1/api/#route-service)
- [latlong2 package](https://pub.dev/packages/latlong2)
