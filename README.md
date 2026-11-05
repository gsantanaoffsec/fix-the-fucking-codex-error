# CODEX DOCTOR 1.0.0 - DRMAIS
Diagnóstico e tratamento da inicialização do Codex no VS Code
Preparado em 04/11/2026


## COMEÇAR

1. Extraia o ZIP inteiro para uma pasta local. Não execute de dentro do ZIP.
2. Dê dois cliques em INICIAR.cmd, com sua conta normal do Windows.
3. A ferramenta lê a instalação e os logs e informa a ação correspondente.
4. Quando solicitado, salve o trabalho e feche todas as janelas do VS Code.
   Nenhum processo é encerrado à força.
5. No teste de abertura, clique em Open/Abrir se o VS Code pedir confirmação
   para o link vscode://openai.chatgpt/. Aguarde até 100 segundos.

Não é necessário instalar Python, Git, Node.js ou bibliotecas PowerShell.
Não precisa executar como administrador. A janela permanece aberta para
mostrar o resultado e a pasta do relatório.


## ARQUIVOS PARA O USUÁRIO

- `INICIAR.cmd`: Diagnostica e aplica as correções reconhecidas.
- `SOMENTE-DIAGNOSTICO.cmd`: Apenas consulta; não fecha nem altera o VS Code.
- `RESTAURAR-CACHE.cmd`: Restaura o último backup de cache disponível.
- `LEIA-ME.txt`: Este guia, incluindo a matriz de decisões.

SE O PROBLEMA FOR X, O TRATAMENTO SERÁ X

### Última tentativa recente iniciou com sucesso

  Não altera a instalação. Informa que o último registro estava saudável.

### Service Worker falhou / "Could not find inner client"

  Preserva as pastas Service Worker, Code Cache e Cache; deixa o VS Code
  recriá-las e testa a interface. O sinal indica problema de carregamento,
  mas não prova sozinho a origem; o teste verifica o resultado.

### renderer_ready_timeout com Codex 26.1021.22027

  Instala 26.1007.21434 pelo instalador oficial do VS Code, confere os
  arquivos e o registro e verifica se o VS Code fixou essa versão contra
  atualização automática. Só se aplica enquanto a regra estiver válida.
  Essa combinação funcionou no caso que originou esta ferramenta.

### Timeout em outra versão

  Tenta uma recriação de cache. Se persistir, gera relatório para a TI.
  Não rebaixa qualquer versão do Codex para uma versão antiga.

### Extensão ausente

  Solicita ao VS Code a instalação de openai.chatgpt pelo Marketplace.

### Arquivos essenciais ausentes ou registro diferente dos arquivos

  Reinstala a mesma versão. Uma versão instalada explicitamente é fixada
  pelo VS Code; a TI pode liberar a atualização depois da validação.

### Crash de GPU registrado nos logs analisados

  Testa somente aquela abertura com --disable-gpu. Não altera o driver
  nem grava uma mudança gráfica permanente. O relatório informa que o
  sucesso foi observado somente sem GPU; a TI deve avaliar a causa.

### Certificado, proxy, DNS, bloqueio remoto ou falha de autenticação

  Orienta encaminhar à TI ou entrar novamente na conta pelo próprio Codex.
  Não desativa validação TLS, firewall, antivírus ou políticas da empresa.
  Não apaga tokens e não tenta fazer login pelo usuário.

### Host de extensões travado ou processo interno do Codex encerrado

  Encaminha para investigação. Não desativa Figma, Copilot ou outras
  extensões indiscriminadamente e não instala dependências por suposição.

### Sem logs, registros antigos, histórico incompleto ou causa desconhecida

  Solicita uma nova tentativa controlada. Se continuar inconclusivo,
  gera relatório sem inventar uma correção ou afirmar que deu certo.

Se um erro explícito de rede/processo ocorrer junto com um timeout, a
causa explícita tem prioridade. Warnings IPC e avisos de depreciação do
Node não são tratados como falhas de instalação. O código de saída do
instalador é verificado, junto com o registro e os arquivos resultantes.


## CONFIRMAÇÃO DO RESULTADO

A ferramenta só confirma um NOVO teste de abertura quando encontra
"name=app_start outcome=success" em uma nova ativação e com data válida.
"Initialize received" sozinho não basta. Ausência de erro também não.
Um sucesso antigo não deve esconder uma tentativa posterior com falha.
São aplicadas no máximo duas correções por execução, sem ciclos infinitos.
Se o VS Code pedir confirmação e ninguém clicar em Abrir, o teste pode
terminar como não confirmado. Isso não significa que a interface abriu.


## RELATÓRIOS E BACKUPS

Ficam na conta da pessoa, em:
  %LOCALAPPDATA%\DrMais\CodexDoctor\DATA-HORA-ID\

Compartilhe com a TI somente Relatorio.txt e Relatorio.json dessa execução.
Os relatórios contêm versões, sinais classificados e ações realizadas;
não copiam logs brutos, mensagens de conversas, tokens ou arquivos auth.json.
Não há envio automático, upload ou telemetria própria desta ferramenta.
As conexões normais do VS Code e do Codex continuam sendo feitas por eles.

O backup de cache fica em backup-cache, com um manifest local. Não envie
a pasta inteira de backup: o cache pode conter dados da sua sessão.
RESTAURAR-CACHE.cmd restaura o backup mais recente ainda disponível para
a mesma instalação. O cache atual também é preservado, sem sobreposição.
O restaurador valida nomes e caminhos e recusa links/junctions.
Backups não são apagados automaticamente.

Projetos, conversas, settings.json e config.toml não são removidos.
O reparo de cache não modifica Cookies, Local Storage ou credenciais.


## VOLTAR A ATUALIZAR A EXTENSÃO

Depois que a TI validar uma versão corrigida: no VS Code, abra Extensões,
localize Codex e use Atualizar / Instalar outra versão. Reative a atualização
automática dessa extensão quando aprovado pela TI. A ferramenta não altera
a atualização automática de outras extensões.
A troca de versão é registrada no relatório; o backup automático é de cache,
não é uma cópia completa da extensão. Para reinstalar uma versão anterior,
use a versão registrada e o recurso Instalar outra versão do VS Code.


## ESCOPO SUPORTADO

Windows 10/11, Windows PowerShell 5.1+ e VS Code estável instalado localmente
para o usuário ou em Arquivos de Programas, usando o perfil padrão.
Não cobre VS Code remoto/SSH, WSL, Insiders, VSCodium ou outras IDEs.
Se detectar perfis personalizados ou instalação portátil, bloqueia alterações
automáticas para evitar agir na instalação errada. O diagnóstico continua
disponível; a TI precisa vincular o reparo ao perfil correto.
Pastas redirecionadas por links/junctions também exigem análise da TI.
Não cria permissões, serviços, tarefas agendadas ou mudanças permanentes
na política de execução do PowerShell.
O lançador usa Bypass somente no processo que executa este script. Se uma
política corporativa bloquear scripts, solicite implantação/assinatura à TI;
não desative a política da empresa.


## PARA A TI: MANUTENÇÃO DAS REGRAS

regras.json é a lista de versões do caso conhecido, não uma lista de todas
as falhas possíveis do Codex. A regra inicial vence em 04/12/2026.
Após essa data, o fallback automático deixa de ser aplicado. O diagnóstico
e os outros tratamentos continuam disponíveis.

Antes de mudar KnownBadVersions, FallbackVersion ou FallbackValidUntil:
- Valide a correção em uma máquina de teste da empresa.
- Confira que a versão está disponível no canal oficial do VS Code.
- Atualize a data de validação e a documentação do pacote.
- Execute os testes novamente e publique um novo ZIP internamente.
Uma nova versão saudável não deve ser incluída na lista de versões ruins.
regras.json contém dados; nenhum comando encontrado em logs ou nesse arquivo
é executado como código.

Parâmetros avançados, para uma instalação local estável não padrão:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexDoctor.ps1
    -Mode Diagnose -CodePath "C:\caminho\Code.exe"
    -UserDataDir "C:\caminho\Code" -ExtensionsDir "C:\caminho\extensions"

Escreva o comando em uma linha. -ReportRoot permite escolher onde salvar o
relatório. -NoPrompt remove as pausas: se o editor estiver aberto, o reparo
para em vez de encerrá-lo. -SkipLaunch aplica uma correção indicada sem abrir
o editor, mas o resultado fica explicitamente NÃO VERIFICADO.


## TESTES DO PACOTE

Na pasta extraída:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Integration.ps1
As fixtures são criadas em pastas novas de teste. Não executam reparos no
VS Code real. Há testes de registro JSON com várias extensões, warnings em
stderr, versões/data de fallback, logs antigos/múltiplas janelas, ordenação
de timestamps no PowerShell 5.1, backup/restauração e caminhos adulterados.


## REFERÊNCIAS

Configurações oficiais do Codex:
https://learn.chatgpt.com/docs/ide/settings
CLI oficial do VS Code:
https://code.visualstudio.com/docs/configure/command-line
Relato da versão 26.1021.22027 e fallback observado:
https://github.com/openai/codex/issues/56691
Falha de webview/Service Worker e relatos de recuperação:
https://github.com/openai/codex/issues/56858

Esta é uma ferramenta interna de suporte, não um produto oficial da OpenAI
ou da Microsoft. Ela trata os casos reconhecidos acima e encaminha os demais
com evidências, sem prometer corrigir toda falha possível.
