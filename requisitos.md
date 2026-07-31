# App Mobile — Migração para Multi-Tenant por Schema

**Status:** obrigatório. A API já está multi-tenant; o app ainda opera com a
API key global e **para de funcionar** assim que o ambiente for atualizado.

**Público:** time do app mobile (rastreador em campo).

---

## 1. O que mudou, em uma frase

A `x-api-key` deixou de ser **uma constante única do sistema** e passou a ser
**uma credencial por cliente**. É ela que diz à API em qual schema do banco a
requisição vai gravar e ler.

Antes:

```
API_KEY = "123"   (a mesma para todo mundo, fixa no .env do servidor)
```

Depois:

```
Acme Transportes  -> 86f36662f0401e4b2100d6196aba9828189bdc666203379406b223f34fc25a7c
Beta Log          -> 5c682e39c5fcbcfd9b7bf53a73b3a91dc4d9135391ea25f382f7ec608caec99d
```

Cada cliente tem o seu schema PostgreSQL isolado (`acme`, `beta`, …). A api key
é o que amarra a requisição ao schema certo.

---

## 2. Impacto direto no app hoje

| O que o app faz hoje | O que acontece depois da atualização |
|---|---|
| Envia `x-api-key` com a chave global compilada | **403 `INVALID REQUEST`** em toda chamada |
| Trata a `key` da viagem como identificador único no mundo | Passa a ser único **apenas dentro de um cliente** |
| Usa `GET /log`, `GET /log/active`, `GET /log/:key` com api key | **401** — essas rotas agora exigem JWT (ver §6) |

Não existe janela de compatibilidade: a chave antiga não é mais aceita por
nenhuma rota. O rollout precisa ser coordenado (ver §8).

---

## 3. A mudança mínima no app

A api key precisa deixar de ser constante de build e virar **configuração por
instalação**, provisionada junto com o vínculo do dispositivo ao cliente.

```diff
- const API_KEY = "123";                       // constante de build
+ const apiKey = await secureStorage.get("api_key");   // por instalação
```

Requisitos:

1. **Armazenamento seguro** (Keychain / Keystore / EncryptedSharedPreferences).
   A chave dá acesso de escrita aos dados daquele cliente — não pode ir em
   `SharedPreferences` em claro, log, crash report ou analytics.
2. **Entrada da chave** no vínculo do dispositivo: tela de configuração,
   leitura de QR Code ou deep link entregue pelo cliente. A definir com o time
   de produto — a API não impõe formato.
3. **Troca de chave sem reinstalar.** A chave pode ser rotacionada pelo backend
   (revoga a anterior). O app precisa tratar `403` como "chave inválida ou
   revogada" e pedir reconfiguração, não como erro genérico de rede.
4. **Nunca embutir a chave de um cliente no binário** — o mesmo APK/IPA atende
   todos os clientes.

---

## 4. Superfície de API que o app consome

Todas continuam autenticando por `x-api-key`. **Nenhuma URL, verbo, campo ou
formato de payload mudou** — só o valor do header.

| Endpoint | Método | Uso |
|---|---|---|
| `/log` | `POST` | Envio de posição (único ou lote) |
| `/public/trip/key/:key` | `GET` | Dados da viagem pela key |
| `/admin/checklist-media` | `POST` | Upload de mídia do checklist (`file`) |
| `/admin/checklist-media/multiple` | `POST` | Upload em lote (`files`, até 10) |
| `/admin/checklist-media/checklist/:checklist_id` | `GET` | Mídias de um checklist |
| `/admin/checklist-media/:id` | `GET` `PUT` `DELETE` | Detalhe / edição / remoção |
| `/health` | `GET` | Público, sem autenticação |

---

## 5. Contratos

### 5.1 `POST /log`

```http
POST /log
x-api-key: <api key DO CLIENTE>
Content-Type: application/json
```

Aceita um objeto ou um array:

```json
{
  "key": "ROTA-001",
  "latitude": -23.5505,
  "longitude": -46.6333,
  "speed": 42,
  "timestamp": "2026-07-31T10:00:00Z"
}
```

| Campo | Obrigatório | Regra |
|---|---|---|
| `key` | sim | key da viagem |
| `latitude` | sim | número entre -90 e 90 |
| `longitude` | sim | número entre -180 e 180 |
| `speed` | não | não numérico vira `0` |
| `timestamp` | **sim, na prática** | ISO 8601. Se vier ausente ou inválido a requisição falha com **500** — a API não assume "agora". |

Resposta `201`: objeto único se a entrada foi objeto, array se foi array.

> Envio em lote continua sendo o caminho recomendado para economizar bateria e
> dados. O lote inteiro é gravado no cliente resolvido pela api key.

### 5.2 `GET /public/trip/key/:key`

```http
GET /public/trip/key/ROTA-001
x-api-key: <api key DO CLIENTE>
```

`200` com a viagem (inclui `driver_name`, pontos de origem/destino, carga e
descarga) ou `404 {"error":"Trip não encontrado"}`.

**Atenção:** a mesma `key` pode existir em outro cliente. O que decide qual
viagem volta é a api key enviada. Chave errada = `404`, não a viagem do vizinho.

### 5.3 `POST /admin/checklist-media`

`multipart/form-data`, campo `file` (ou `files` para o endpoint `/multiple`),
até 10 MB por arquivo, tipos: `jpeg, jpg, png, webp, pdf, avif, mov`.

---

## 6. Rotas que o app **não** pode mais usar com api key

`GET /log`, `GET /log/active` e `GET /log/:key` passaram a exigir **JWT de
usuário** (`Authorization: Bearer …`), porque são consultas do painel.

Motivo: a chave do painel web é pública (vai no bundle do navegador), então ela
não pode identificar cliente nenhum. Se o app usa alguma dessas rotas para
"conferir o que foi enviado", isso precisa ser removido ou repensado — o app não
tem sessão de usuário.

---

## 7. Regra nova que afeta a lógica local

**A `key` da viagem não é mais única globalmente.** Dois clientes podem usar
`ROTA-001` ao mesmo tempo, de propósito.

Revisar no app qualquer lugar que assuma unicidade global:

- cache/banco local indexado só por `key` → passar a chavear por
  `(cliente, key)`, usando a instalação como escopo;
- fila offline de posições → se o app puder ser reconfigurado para outro
  cliente, a fila pendente precisa ser descartada ou marcada com a chave que a
  originou. **Nunca** enviar posição acumulada de um cliente com a api key de
  outro;
- deep links / QR de viagem que carreguem só a `key` → passam a ser ambíguos.

---

## 8. Rollout

A mudança é quebrante nos dois sentidos: app antigo não fala com API nova, e
app novo sem chave configurada não fala com nada.

Sequência sugerida:

1. Backend gera as chaves dos clientes (`npm run tenant:create`) e as entrega
   pelos canais de cada cliente.
2. App publica versão que lê a chave de configuração, **com tela de
   reconfiguração acessível** para quem já estiver instalado.
3. Só depois o ambiente antigo (chave global) é desligado.

Se um período de convivência for necessário, o backend consegue aceitar a chave
antiga mapeada para um cliente específico — precisa ser pedido, hoje não existe.

---

## 9. Erros a tratar

| Código | Corpo | Significado | Ação no app |
|---|---|---|---|
| `401` | `{"error":"MISSING KEY"}` | Header `x-api-key` ausente | Bug de build/config — não repetir a chamada |
| `403` | `{"error":"INVALID REQUEST"}` | Chave desconhecida, revogada ou cliente inativo | Parar a fila, pedir reconfiguração ao usuário |
| `400` | `{"error":"Campo ... é obrigatório"}` | Payload inválido | Descartar o ponto, registrar; **não** reenviar em loop |
| `404` | `{"error":"Trip não encontrado"}` | Key não existe **neste cliente** | Verificar se a chave configurada é a do cliente certo |
| `500` | `{"error":"Erro interno ..."}` | Falha no servidor (ex.: `timestamp` ausente) | Backoff exponencial e retentativa |

`403` **não** é caso de retentativa cega: a chave não vai ficar válida sozinha.
Reenviar em loop só gasta bateria e polui o log do servidor.

---

## 10. Como testar

Peça uma api key de um cliente de teste ao time de backend.

```bash
# 1. Envio de posição
curl -X POST http://SEU_HOST:3525/log \
  -H "x-api-key: SUA_CHAVE_DE_TESTE" \
  -H "Content-Type: application/json" \
  -d '{"key":"ROTA-001","latitude":-23.5505,"longitude":-46.6333,"speed":42,"timestamp":"2026-07-31T10:00:00Z"}'
# esperado: 201 com o log criado

# 2. Chave inválida
curl -i -X POST http://SEU_HOST:3525/log \
  -H "x-api-key: 123" \
  -H "Content-Type: application/json" \
  -d '{"key":"ROTA-001","latitude":1,"longitude":1,"timestamp":"2026-07-31T10:00:00Z"}'
# esperado: 403 INVALID REQUEST

# 3. Consulta da viagem
curl http://SEU_HOST:3525/public/trip/key/ROTA-001 \
  -H "x-api-key: SUA_CHAVE_DE_TESTE"
# esperado: 200 com a viagem
```

**Critério de aceite:** com duas chaves de clientes diferentes e a **mesma**
`key` de viagem, cada uma devolve apenas os próprios dados — e nenhuma das duas
enxerga os da outra.

---

## 11. Checklist de implementação

- [ ] API key sai do binário e vai para armazenamento seguro
- [ ] Tela/fluxo de configuração e **reconfiguração** da chave
- [ ] Chave removida de logs, crash reports e analytics
- [ ] `403` tratado como "reconfigurar", sem retentativa cega
- [ ] Cache/fila local escopados por cliente, não só por `key`
- [ ] Fila pendente descartada ou bloqueada ao trocar de cliente
- [ ] Uso de `GET /log*` removido (agora é JWT)
- [ ] `timestamp` ISO 8601 sempre presente no envio
- [ ] Teste de aceite da §10 executado com dois clientes

---

*Dúvidas de contrato: time de backend. A API não mudou de formato — apenas de
significado da credencial.*
