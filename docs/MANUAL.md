# Manual do Codex Account Manager

Versão documentada: **v1.3**

Este manual descreve a instalação, configuração, operação diária, failover, retomada,
atualização, diagnóstico e manutenção do Codex Account Manager.

O projeto foi desenhado para permitir o uso de múltiplas contas do Codex CLI sem perder
continuidade de sessão quando uma conta atinge limite de uso.

---

## 1. Visão geral

O Codex Account Manager adiciona uma camada local entre o usuário e o Codex CLI.

Quando você executa:

```bash
codex
```

ou:

```bash
codex exec "faça alguma coisa"
```

o comando `codex` encontrado primeiro no `PATH` é o wrapper do manager:

```text
~/.local/lib/codex-manager/bin/codex
```

Esse wrapper decide se a chamada deve:

- ir diretamente para o runtime oficial;
- ser executada sob uma conta gerenciada;
- usar failover automático;
- retomar uma thread existente;
- criar um job agendado para depois do reset de quota.

O Codex oficial continua separado do manager.

Normalmente ele permanece disponível em:

```text
~/.local/bin/codex
```

ou em uma instalação npm, bun ou standalone equivalente.

O manager nunca precisa substituir permanentemente o executável oficial.

---

## 2. Objetivos da aplicação

O Codex Account Manager resolve cinco problemas principais.

### 2.1 Múltiplas contas

Cada conta mantém seu próprio `auth.json` em um `CODEX_HOME` isolado.

### 2.2 Sessões compartilhadas

Configuração, sessões, regras, skills e estado SQLite são compartilhados entre as contas
para que uma thread criada com uma conta possa ser retomada por outra.

### 2.3 Seleção por quota

Quando possível, o manager consulta o app-server do Codex e usa os dados de rate limit
para selecionar a conta com maior headroom.

### 2.4 Failover automático

Em `codex exec`, se uma conta atingir quota, o manager tenta outra conta automaticamente.

Se já existir uma thread, ele usa `codex exec resume`.

Se a quota ocorrer antes da criação da thread, ele reexecuta o comando original.

### 2.5 Retomada agendada

Se todas as contas estiverem temporariamente indisponíveis, o manager cria um
`systemd --user` timer para retomar o trabalho depois do reset mais próximo.

O terminal não precisa permanecer aberto.

---

## 3. Arquitetura

A instalação tem três componentes principais.

### 3.1 Wrapper

```text
~/.local/lib/codex-manager/bin/codex
```

Responsabilidades:

- interceptar o comando `codex`;
- encaminhar `--version` e `--help` diretamente ao runtime oficial;
- encaminhar `codex exec` ao gerenciador de contas;
- encaminhar o uso interativo ao gerenciador.

### 3.2 Gerenciador de contas

```text
~/.local/bin/codex-account
```

Responsabilidades:

- cadastrar contas;
- autenticar contas;
- selecionar conta;
- consultar quota;
- executar failover;
- manter estado;
- criar e retomar jobs;
- fazer diagnóstico.

### 3.3 Runtime launcher

```text
~/.local/lib/codex-manager/codex-runtime
```

Responsabilidades:

- encontrar instalações válidas do Codex oficial;
- identificar a versão;
- preferir versões stable por padrão;
- evitar o próprio wrapper;
- manter cache de descoberta;
- executar o Codex oficial selecionado.

---

## 4. Estrutura de arquivos

O estado da aplicação fica em:

```text
~/.codex-manager/
|-- accounts/
|   |-- principal/home/
|   |-- secundaria/home/
|   `-- ...
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
|-- .lock
`-- state.json
```

### 4.1 Diretórios por conta

Cada conta usa:

```text
~/.codex-manager/accounts/<nome>/home/
```

O arquivo de autenticação fica isolado:

```text
auth.json
```

### 4.2 Estado compartilhado

Os seguintes recursos são compartilhados entre as contas:

- `config.toml`;
- `sessions/`;
- `archived_sessions/`;
- `skills/`;
- `rules/`;
- SQLite.

Essa separação é o que permite trocar de conta sem perder a thread em andamento.

---

## 5. Instalação

Partindo do repositório clonado:

```bash
cd ~/code/codex_manager
./install.sh
source ~/.bashrc
```

Depois valide:

```bash
which codex
```

Esperado:

```text
/home/<usuario>/.local/lib/codex-manager/bin/codex
```

Verifique também:

```bash
codex --version
codex-account doctor
```

---

## 6. Atualização do manager

Para atualizar o Codex Account Manager:

```bash
cd ~/code/codex_manager
git pull origin main
./install.sh
source ~/.bashrc
```

Depois:

```bash
codex-account doctor
```

O instalador preserva:

- contas;
- autenticações existentes;
- sessões;
- configuração;
- estado;
- jobs pendentes.

---

## 7. Atualização do Codex oficial

O manager e o Codex oficial são independentes.

Depois de atualizar o Codex oficial, normalmente não é necessário reinstalar o manager.

Veja a versão ativa:

```bash
codex --version
```

Veja qual runtime foi selecionado:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
```

Force nova descoberta:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
```

A política padrão é:

```json
"prerelease_policy": "stable"
```

Portanto, uma versão alpha ou beta não deve substituir automaticamente uma versão stable.

---

## 8. Primeiro cadastro de conta

Se já existe uma instalação normal do Codex autenticada em `~/.codex`, importe-a:

```bash
codex-account bootstrap principal
```

O nome `principal` é apenas um exemplo.

O bootstrap:

- copia a autenticação para o home gerenciado;
- importa configuração compartilhada quando aplicável;
- importa sessões e regras;
- não destrói o `~/.codex` original.

---

## 9. Adicionar outra conta

Crie uma nova conta:

```bash
codex-account add secundaria
```

O Codex abrirá o fluxo de login usando o `CODEX_HOME` específico dessa conta.

Para criar sem iniciar login imediatamente:

```bash
codex-account add secundaria --no-login
```

Depois autentique:

```bash
codex-account login secundaria
```

---

## 10. Listar contas

Use:

```bash
codex-account list
```

A saída contém:

- nome;
- status;
- prioridade;
- headroom;
- cooldown/reset;
- último sucesso.

O `*` identifica a conta preferida.

Exemplo conceitual:

```text
NAME                 STATUS        PRIO HEADROOM RESET/COOLDOWN           LAST SUCCESS
 principal           healthy        100       62 -                        ...
*secundaria          healthy        100       81 -                        ...
```

---

## 11. Entendendo HEADROOM

Quando o app-server fornece dados de rate limit, o manager observa as janelas conhecidas.

Para cada janela:

```text
remaining = 100 - used_percent
```

O `HEADROOM` exibido é o menor valor restante entre as janelas.

Exemplo:

```text
janela curta:  40% usado -> 60% restante
janela longa:  75% usado -> 25% restante

HEADROOM = 25
```

Isso representa a janela mais restritiva.

Se não houver telemetria de uso disponível, o manager usa valor neutro para scoring.

---

## 12. Atualizar a leitura de quota

Use:

```bash
codex-account usage
```

Esse comando força uma atualização de quota das contas elegíveis e depois mostra a lista.

Por padrão, durante uso normal, snapshots com menos de 120 segundos podem ser reutilizados.

Esse intervalo é configurável por:

```json
"usage_probe_ttl_seconds": 120
```

---

## 13. Escolher uma conta manualmente

Para alterar a conta preferida:

```bash
codex-account use secundaria
```

Confirme:

```bash
codex-account list
```

A preferência manual não necessariamente força o uso dessa conta quando o scoring por quota
indica que outra está em situação significativamente melhor.

Na v1.3, headroom e prioridade são critérios mais fortes, e a preferência atua como desempate.

---

## 14. Avançar para a próxima conta

Use:

```bash
codex-account next
```

Esse comando altera a preferência para outra conta disponível.

---

## 15. Uso interativo

Para abrir o Codex normalmente:

```bash
codex
```

O manager seleciona uma conta disponível e inicia o Codex usando o `CODEX_HOME` dessa conta.

### Importante

O failover totalmente automático foi desenhado principalmente para `codex exec`.

Uma TUI já aberta não troca de autenticação no meio do processo de forma transparente.

---

## 16. Uso com codex exec

Exemplo:

```bash
codex exec "implemente a próxima milestone"
```

O fluxo é:

```text
codex
  -> wrapper
  -> codex-account exec
  -> consulta quota
  -> escolhe conta
  -> codex exec --json
  -> captura thread.started
  -> acompanha execução
```

O `--json` interno permite obter de forma determinística:

```json
{"type":"thread.started","thread_id":"..."}
```

Esse ID é usado em qualquer failover posterior.

---

## 17. Saída JSON explícita

Se você executar:

```bash
codex exec --json "analise o projeto"
```

o manager preserva o JSONL do Codex na saída.

Quando `--json` não foi pedido explicitamente, o manager usa JSON internamente, mas apresenta
as mensagens do agente em formato normal.

---

## 18. Como funciona o failover

Considere duas contas:

```text
principal
secundaria
```

A execução começa na conta selecionada.

Se ocorrer um erro reconhecido como quota:

```text
conta A
  -> quota esgotada
  -> marca conta como limited
  -> registra reset/cooldown
  -> escolhe conta B
```

Se já existe `thread_id`:

```bash
codex exec resume <THREAD_ID> "<continuation_prompt>"
```

O trabalho continua na mesma thread.

---

## 19. Failover antes da criação da thread

Pode acontecer de uma conta já estar sem quota antes de o Codex criar a thread.

Nesse caso não existe `thread_id`.

A v1.3 trata isso como execução `fresh`:

```text
conta A
  -> quota antes de thread.started
  -> nenhuma thread para retomar
  -> escolhe conta B
  -> executa novamente o pedido original
```

Isso evita tentar retomar uma sessão inexistente.

---

## 20. Prompt de continuidade

Quando existe uma thread e ocorre failover, o manager adiciona um prompt de continuidade.

O padrão orienta o Codex a:

- continuar o pedido anterior;
- verificar o estado atual do repositório;
- não reverter trabalho já aplicado;
- não repetir trabalho concluído;
- usar o histórico da sessão.

Esse texto pode ser alterado em:

```text
~/.codex-manager/manager.json
```

campo:

```json
"continuation_prompt"
```

---

## 21. Quando todas as contas estão limitadas

Se todas as contas disponíveis estiverem em cooldown, o manager procura o primeiro horário
de recuperação conhecido.

Se houver um horário de reset, cria um job em:

```text
~/.codex-manager/pending/
```

e um par de units:

```text
~/.config/systemd/user/codex-resume-<JOB>.service
~/.config/systemd/user/codex-resume-<JOB>.timer
```

O terminal pode ser fechado.

---

## 22. Tipos de job

Existem dois modos.

### 22.1 resume

Existe `thread_id`.

O job executará novamente a thread existente.

### 22.2 fresh

A quota terminou antes de existir thread.

O job preserva os argumentos originais de `codex exec` e executa o pedido novamente.

---

## 23. Ver jobs pendentes

Use:

```bash
codex-account pending
```

Por padrão são mostrados apenas jobs ativos.

Para mostrar também concluídos, cancelados e falhos:

```bash
codex-account pending --all
```

---

## 24. Ver timers no systemd

Use:

```bash
systemctl --user list-timers 'codex-resume-*'
```

Para inspecionar uma unit específica:

```bash
systemctl --user status codex-resume-<ID>.timer
```

ou:

```bash
systemctl --user status codex-resume-<ID>.service
```

---

## 25. Retomar um job manualmente

Use:

```bash
codex-account resume-job <JOB_ID>
```

Para compatibilidade com versões anteriores também existe:

```bash
codex-account resume-session <SESSION_ID>
```

---

## 26. Cancelar um job

Use:

```bash
codex-account cancel <JOB_ID>
```

Isso:

- desativa/remove as units correspondentes;
- marca o registro como cancelado.

---

## 27. Limpeza de histórico

Use:

```bash
codex-account gc
```

Por padrão são removidos registros terminais antigos, preservando jobs ativos.

O período padrão é 30 dias.

Para outro período:

```bash
codex-account gc --days 7
```

---

## 28. Marcar uma conta como limitada manualmente

Para simular ou registrar uma indisponibilidade:

```bash
codex-account limited principal
```

Com duração:

```bash
codex-account limited principal --minutes 60
```

Com motivo:

```bash
codex-account limited principal --minutes 60 --reason "teste"
```

Isso é útil para testes de seleção e failover.

---

## 29. Status das contas

Os principais estados são:

### unknown

Ainda não houve confirmação recente de sucesso.

### healthy

A conta executou corretamente.

### limited

Foi detectado limite de uso e existe cooldown.

### needs-login

A autenticação precisa ser renovada.

### error

Ocorreu uma falha que não foi classificada como quota nem autenticação.

---

## 30. Detecção de quota

O manager reconhece mensagens de erro conhecidas, incluindo padrões como:

```text
you've hit your usage limit
usage limit reached
usage limit exceeded
workspace is out of credits
spend cap
quota exceeded
usage not included
out of credits
```

Quando possível, a informação estruturada do app-server reduz a dependência desse parsing textual.

---

## 31. Detecção de reset

A v1.3 reconhece:

### Timestamp

```text
2026-11-07T21:00:00Z
```

### Duração

```text
try again in 42 minutes
try again in 2 hours
```

### Horário local

```text
try again at 7:58 PM
```

Se nenhum formato puder ser identificado, é usado:

```json
"default_cooldown_minutes": 30
```

---

## 32. Diagnóstico

O comando principal é:

```bash
codex-account doctor
```

Ele verifica:

- localização do manager;
- runtime Codex;
- compatibilidade do CLI;
- suporte a `codex exec`;
- suporte a `--json`;
- suporte a `resume`;
- suporte a `app-server`;
- diretório SQLite compartilhado;
- disponibilidade do `systemd --user`;
- existência do `auth.json` de cada conta;
- status de login de cada conta.

O resultado esperado é:

```text
OK
```

---

## 33. Ver qual Codex real está sendo usado

Use:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
```

Exemplo:

```json
{
  "method": "standalone",
  "path": "/home/usuario/.local/bin/codex",
  "policy": "stable",
  "prerelease": false,
  "version": "codex-cli 0.167.0"
}
```

---

## 34. Forçar redescoberta do runtime

Use:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
```

Isso é útil após:

- atualizar o Codex;
- mudar método de instalação;
- instalar uma nova versão;
- remover uma instalação antiga;
- diagnosticar seleção incorreta de runtime.

---

## 35. Debug da seleção de runtime

Use:

```bash
CODEX_MANAGER_RUNTIME_DEBUG=1 codex --version
```

O launcher informa no stderr qual runtime foi escolhido.

---

## 36. Métodos de runtime reconhecidos

A descoberta procura:

- override explícito via `CODEX_REAL_OVERRIDE`;
- hints salvos;
- `~/.local/bin/codex`;
- standalone em `~/.codex/packages/standalone`;
- standalone nos `CODEX_HOME` das contas;
- instalações visíveis no `PATH`.

O método reportado pode aparecer como:

```text
standalone
npm
bun
path
```

---

## 37. Política de prerelease

Padrão:

```json
"prerelease_policy": "stable"
```

Para permitir versões prerelease:

```json
"prerelease_policy": "allow-prerelease"
```

Edite:

```text
~/.codex-manager/manager.json
```

Depois force nova descoberta:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
```

---

## 38. Configuração completa relevante

Arquivo:

```text
~/.codex-manager/manager.json
```

Campos principais:

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

### runtime_check_ttl_seconds

Tempo de cache da descoberta do Codex oficial.

### usage_probe_ttl_seconds

Tempo durante o qual um snapshot de quota pode ser reutilizado.

### account_scoring

Ativa seleção por headroom.

### auto_schedule

Permite criar timers automáticos quando todas as contas estão limitadas.

### schedule_grace_seconds

Margem adicionada após o horário de reset.

### default_cooldown_minutes

Fallback quando o reset real não pode ser inferido.

### pending_retention_days

Idade padrão para limpeza de jobs terminados.

---

## 39. Variáveis de ambiente úteis

### CODEX_ACCOUNT_MANAGER_HOME

Permite usar outro diretório de estado do manager.

Exemplo:

```bash
CODEX_ACCOUNT_MANAGER_HOME=/tmp/codex-manager-test codex-account list
```

### CODEX_ACCOUNT_MANAGER_BIN

Substitui o binário do manager usado pelo wrapper.

### CODEX_MANAGER_RUNTIME_BIN

Substitui o launcher de runtime usado pelo wrapper.

### CODEX_REAL_OVERRIDE

Força um candidato específico de Codex real para o runtime launcher.

### CODEX_MANAGER_RUNTIME_DEBUG

Mostra o runtime escolhido.

---

## 40. Segurança das credenciais

Cada conta possui um `auth.json` separado.

O manager remove do ambiente de execução variáveis que poderiam sobrescrever a identidade
da conta gerenciada, incluindo:

- `CODEX_ACCESS_TOKEN`;
- `CODEX_API_KEY`;
- `OPENAI_API_KEY`;
- `OPENAI_IDENTITY_TOKEN_FILE`;
- `OPENAI_WORKLOAD_IDENTITY_CONTEXT`.

Não compartilhe nem versione:

```text
~/.codex-manager/accounts/*/home/auth.json
```

O diretório de estado do manager não deve ser adicionado ao repositório.

---

## 41. Concorrência

A v1.3 foi desenhada para suportar múltiplos `codex exec` simultâneos.

A associação de thread não depende mais de "arquivo mais recente".

Cada execução captura seu próprio:

```text
thread.started -> thread_id
```

O estado principal usa `flock` para serializar gravações.

O cache do runtime também possui lock próprio e escrita atômica.

---

## 42. Limitações conhecidas

### TUI já aberta

Uma TUI interativa já iniciada não troca de conta de forma transparente no meio do processo.

### Máquina desligada

`Persistent=true` permite que o timer atrasado seja executado quando o user systemd voltar,
mas não liga nem acorda fisicamente a máquina por conta própria.

### Mudanças futuras do Codex

O projeto depende de contratos do Codex CLI e app-server.

Por isso, após atualizar o Codex, use:

```bash
codex-account doctor
```

### Erros não relacionados a quota

Falhas de rede, MCP, configuração ou execução não são tratadas automaticamente como quota.

Isso é intencional para evitar trocar de conta diante de um problema não relacionado a limite.

---

## 43. Troubleshooting

### 43.1 `codex --version` mostra ajuda do codex-account

O wrapper instalado está desatualizado.

Atualize:

```bash
cd ~/code/codex_manager
git pull origin main
./install.sh
source ~/.bashrc
```

### 43.2 `which codex` mostra `~/.local/bin/codex`

O diretório do wrapper não está antes no `PATH`.

Execute:

```bash
source ~/.bashrc
which codex
```

Esperado:

```text
~/.local/lib/codex-manager/bin/codex
```

### 43.3 Conta aparece como `needs-login`

Refaça login:

```bash
codex-account login <conta>
```

Depois:

```bash
codex-account doctor
```

### 43.4 Conta aparece como `limited` depois do reset

Force atualização:

```bash
codex-account usage
```

Se necessário, rode uma execução curta para confirmar disponibilidade.

### 43.5 Runtime errado

Veja:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
```

Depois:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
```

### 43.6 Job não executou

Veja:

```bash
codex-account pending --all
systemctl --user list-timers 'codex-resume-*'
```

Depois inspecione a unit:

```bash
systemctl --user status codex-resume-<ID>.timer
systemctl --user status codex-resume-<ID>.service
```

### 43.7 Projeto foi movido ou removido

O job armazena o diretório original.

Se esse caminho não existir mais, a retomada falhará com projeto indisponível.

Nesse caso, cancele o job e reinicie a execução no novo diretório.

---

### 43.8 Flags do Codex aparecem como "unrecognized arguments"

Se uma versão antiga do wrapper estiver instalada, flags globais ou de subcomandos do
Codex podem ser interpretadas pelo `argparse` do `codex-account`.

Exemplos afetados antes da correção:

```bash
codex --ignore-user-config --skip-git-repo-check
codex exec --sandbox workspace-write "..."
```

O wrapper atual usa um separador interno `--` ao chamar o manager e remove esse separador
antes de executar o Codex real. Assim, flags pertencentes ao Codex não são parseadas pelo
manager.

Se esse erro aparecer:

```bash
cd ~/code/codex_manager
git pull origin main
./install.sh
source ~/.bashrc
```

Depois valide com:

```bash
codex --version
codex --help
codex-account doctor
```

## 44. Testes

Rodar localmente:

```bash
python3 -m py_compile codex-account codex-runtime
bash -n codex-wrapper install.sh
python3 -m unittest discover -s tests -v
```

A CI executa em Python:

- 3.11;
- 3.12;
- 3.13.

Ela verifica:

- sintaxe Python;
- sintaxe shell;
- parsing de reset;
- escaping de systemd;
- scoring por quota;
- detecção de stable/prerelease.

---

## 45. Checklist de validação após upgrade

Depois de atualizar o manager:

```bash
cd ~/code/codex_manager
git pull origin main
./install.sh
source ~/.bashrc
```

Execute:

```bash
which codex
codex --version
codex-account doctor
codex-account usage
codex-account list
codex exec "responda apenas OK"
```

Resultado esperado:

1. `which codex` aponta para o wrapper;
2. `codex --version` mostra a versão real do Codex;
3. `doctor` termina com `OK`;
4. `usage` mostra as contas;
5. uma execução curta funciona.

---

## 46. Checklist de validação após atualizar o Codex

Execute:

```bash
codex --version
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
codex --version
codex-account doctor
```

Isso confirma que:

- a nova versão foi encontrada;
- a política de runtime continua válida;
- o contrato esperado pelo manager ainda existe;
- as contas continuam autenticadas.

---

## 47. Fluxo operacional recomendado

Para uso normal:

```bash
codex
```

ou:

```bash
codex exec "<pedido>"
```

Não é necessário escolher manualmente a conta na maior parte do tempo.

Para acompanhar capacidade:

```bash
codex-account usage
```

Para diagnóstico:

```bash
codex-account doctor
```

Para jobs:

```bash
codex-account pending
```

Para manutenção periódica:

```bash
codex-account gc
```

---

## 48. Referência rápida de comandos

| Comando | Função |
|---|---|
| `codex` | abre o Codex interativo via manager |
| `codex exec "<prompt>"` | execução com failover automático |
| `codex --version` | mostra versão do Codex oficial |
| `codex-account bootstrap <nome>` | importa uma conta existente |
| `codex-account add <nome>` | adiciona conta |
| `codex-account login <nome>` | refaz autenticação |
| `codex-account list` | lista estado das contas |
| `codex-account usage` | atualiza quota e lista contas |
| `codex-account use <nome>` | define conta preferida |
| `codex-account next` | avança preferência |
| `codex-account limited <nome>` | marca conta manualmente como limitada |
| `codex-account pending` | mostra jobs ativos |
| `codex-account pending --all` | mostra histórico completo |
| `codex-account resume-job <id>` | força retomada de job |
| `codex-account cancel <id>` | cancela job |
| `codex-account gc` | remove histórico antigo |
| `codex-account doctor` | diagnóstico completo |
| `codex-runtime --manager-runtime-info` | mostra runtime selecionado |
| `codex-runtime --manager-runtime-refresh` | força redescoberta |

---

## 49. Recuperação / rollback

O manager não remove o `~/.codex` original durante bootstrap.

Para retirar o wrapper do caminho:

```bash
rm ~/.local/lib/codex-manager/bin/codex
```

Depois remova do `~/.bashrc` o bloco:

```text
# >>> codex-manager >>>
export PATH="$HOME/.local/lib/codex-manager/bin:$PATH"
# <<< codex-manager <<<
```

Abra um novo shell ou rode:

```bash
source ~/.bashrc
```

O Codex oficial em `~/.local/bin/codex`, quando presente, volta a ser usado diretamente.

---

## 50. Regra prática

No uso diário, três comandos são suficientes para quase tudo:

```bash
codex exec "<pedido>"
codex-account usage
codex-account doctor
```

O restante existe para instalação, manutenção, troubleshooting e recuperação.
