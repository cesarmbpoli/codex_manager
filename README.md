# Codex Account Manager - v1.3

Gerenciador local de múltiplas contas para o Codex CLI, com isolamento de autenticação,
sessões compartilhadas, seleção por quota, failover automático de `codex exec` e retomada
agendada via `systemd --user`.

## Manual

Para instalação, operação diária, failover, jobs agendados, diagnóstico e troubleshooting, consulte o [Manual do Codex Account Manager](docs/MANUAL.md).

## O que muda na v1.3

### Thread/session determinística

O manager não procura mais a sessão pelo arquivo `rollout-*.jsonl` mais recente.

Para execuções gerenciadas, ele ativa internamente `codex exec --json` e captura o evento:

```json
{"type":"thread.started","thread_id":"..."}
```

Esse `thread_id` é o identificador usado no `codex exec resume`. Isso torna o failover
seguro mesmo com múltiplos `codex exec` concorrentes.

Se o usuário já pediu `--json`, o JSONL é preservado na saída. Caso contrário, o manager
renderiza as mensagens do agente como saída normal.

### Quota antes da criação da thread

`thread.started` é o primeiro evento estruturado de uma execução. Portanto, se uma conta
atingir quota antes desse evento, não há thread persistida para retomar.

Nesse caso a v1.3 reexecuta o pedido original na próxima conta. Se todas as contas estiverem
limitadas, o job agendado guarda:

- diretório de trabalho;
- argumentos originais de `codex exec`;
- modo `fresh`;
- horário do próximo reset.

Quando existir `thread_id`, o job muda para modo `resume`.

### Reset de quota

O parser reconhece:

- timestamp ISO;
- `try again in N minutes/hours`;
- `try again at 7:58 PM`.

Além disso, a seleção de conta usa a interface estruturada do app-server
`account/rateLimits/read` quando disponível.

### Scoring por quota

Por padrão, antes de uma execução o manager atualiza snapshots de quota que estejam mais
velhos que 120 segundos.

O score favorece a conta com maior headroom no bucket mais restritivo. A preferência manual
continua como desempate, em vez de forçar uma conta quase esgotada.

Veja os dados:

```bash
codex-account usage
```

A coluna `HEADROOM` é o menor percentual restante entre as janelas conhecidas.

### Runtime stable

O launcher continua descobrindo automaticamente o Codex oficial, mas a política padrão agora é:

```json
"prerelease_policy": "stable"
```

Uma instalação `0.169.0-alpha.2` não passa silenciosamente à frente de uma stable
`0.167.0`.

Para permitir prerelease explicitamente:

```json
"prerelease_policy": "allow-prerelease"
```

### Runtime cache concorrente

`runtime-cache.json` agora usa:

- `flock`;
- arquivo temporário único;
- `os.replace()`.

Duas instâncias simultâneas do Codex não disputam mais o mesmo
`runtime-cache.json.tmp`.

### Contrato de compatibilidade

`codex-account doctor` valida no runtime instalado:

- `codex --version`;
- `codex exec --help`;
- suporte a `--json`;
- suporte a `resume`;
- `codex app-server --help`;
- login de cada conta.

Uma mudança incompatível no CLI deixa de aparecer apenas durante uma tarefa real.

### systemd

Valores inseridos em unit files escapam também `%`, evitando expansão involuntária de
specifiers do systemd.

O serviço de retomada não apaga mais o próprio unit file enquanto está executando.
Ao concluir, apenas desativa o timer. A remoção física é feita pelo garbage collector.

### Pending jobs

Por padrão:

```bash
codex-account pending
```

mostra apenas jobs ativos.

Histórico completo:

```bash
codex-account pending --all
```

Limpeza:

```bash
codex-account gc
```

O default é remover registros terminais com mais de 30 dias. Pode ser alterado:

```bash
codex-account gc --days 7
```

## Instalação / upgrade

```bash
cd ~/code/codex_manager
git pull origin main
./install.sh
source ~/.bashrc
```

Valide:

```bash
which codex
codex --version
codex-account doctor
codex-account usage
```

O wrapper esperado:

```text
~/.local/lib/codex-manager/bin/codex
```

O Codex oficial continua livre para usar:

```text
~/.local/bin/codex
```

## Uso normal

TUI:

```bash
codex
```

Execução com failover:

```bash
codex exec "implemente a próxima milestone"
```

JSONL explícito:

```bash
codex exec --json "analise o projeto"
```

## Contas

```bash
codex-account list
codex-account usage
codex-account use principal
codex-account next
codex-account login secundaria
```

Adicionar:

```bash
codex-account add terceira
```

## Jobs agendados

```bash
codex-account pending
systemctl --user list-timers 'codex-resume-*'
```

Cancelar por JOB:

```bash
codex-account cancel <JOB_ID>
```

Retomar manualmente:

```bash
codex-account resume-job <JOB_ID>
```

O comando antigo continua aceito para compatibilidade:

```bash
codex-account resume-session <SESSION_ID>
```

## Runtime

Inspecionar:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
```

Forçar redescoberta:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
```

## Configuração

Arquivo:

```text
~/.codex-manager/manager.json
```

Campos principais da v1.3:

```json
{
  "prerelease_policy": "stable",
  "runtime_check_ttl_seconds": 300,
  "usage_probe_ttl_seconds": 120,
  "account_scoring": true,
  "auto_schedule": true,
  "schedule_grace_seconds": 20,
  "default_cooldown_minutes": 30,
  "pending_retention_days": 30
}
```

## Estrutura

```text
~/.codex-manager/
|-- accounts/<conta>/home/
|-- shared/
|   |-- config.toml
|   |-- sessions/
|   |-- archived_sessions/
|   |-- skills/
|   |-- rules/
|   `-- sqlite/
|-- pending/
|-- manager.json
|-- runtime-cache.json
|-- .runtime.lock
`-- state.json

~/.local/lib/codex-manager/
|-- bin/codex
`-- codex-runtime
```

## Testes

A CI executa em Python 3.11, 3.12 e 3.13:

- `py_compile` dos scripts Python;
- `bash -n` dos scripts shell;
- testes unitários de parsing de reset;
- escaping do systemd;
- scoring por quota;
- parsing stable/prerelease do runtime.

Localmente:

```bash
python3 -m py_compile codex-account codex-runtime
bash -n codex-wrapper install.sh
python3 -m unittest discover -s tests -v
```
