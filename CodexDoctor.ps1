#requires -version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Repair','Diagnose','Restore')][string]$Mode='Repair',
    [string]$CodePath,
    [string]$UserDataDir,
    [string]$ExtensionsDir,
    [string]$ReportRoot,
    [switch]$NoPrompt,
    [switch]$SkipLaunch
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CodexDoctor.Core.psm1') -Force -DisableNameChecking
if(-not $ReportRoot){$ReportRoot=Join-Path $env:LOCALAPPDATA 'DrMais\CodexDoctor'}
$ReportRoot=Assert-DoctorPlainPath $ReportRoot
$run=Join-Path $ReportRoot ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $run -Force|Out-Null
$report=[ordered]@{Tool='Codex Doctor';ToolVersion='1.0.0';Date=(Get-Date).ToString('o');Mode=$Mode;CodeVersion=$null;CodexVersion=$null;Pinned=$false;Diagnosis='Unknown';Reason='';FreshEvidence=$false;Signals=$null;Actions=@();Outcome='NaoConcluido';Error=$null}
$script:installation=$null
$script:rules=$null

function Get-Snapshot {
    $script:installation=Get-DoctorInstallation -CodeExe $CodePath -CodeRoot $UserDataDir -ExtensionsRoot $ExtensionsDir
    $i=$script:installation
    $report.CodeVersion=$i.CodeVersion
    $report.CodexVersion=$null;$report.Pinned=$false
    if($i.Extension){$report.CodexVersion=$i.Extension.version;$report.Pinned=($i.Extension.metadata.pinned -eq $true)}
    $e=Read-DoctorEvidence $i.CodeRoot
    $decision=Get-DoctorDecision $e.State $report.CodexVersion $script:rules -Fresh:$e.Fresh
    if(-not $i.CodeExe){$decision=[pscustomobject]@{Action='Escalate';Reason='VS Code estavel nao encontrado. Instale pelo site oficial ou informe -CodePath.'}}
    elseif($i.ProfilesDetected -or $i.PortableDetected){$decision=[pscustomobject]@{Action='Escalate';Reason='Perfis personalizados ou instalacao portatil detectados. Reparo automatico bloqueado para nao alterar o perfil errado. A TI deve tratar esta instalacao.'}}
    elseif(-not $i.EngineCompatible){$decision=[pscustomobject]@{Action='Escalate';Reason='VS Code abaixo da versao minima da extensao. Atualize o editor pelo canal aprovado da empresa.'}}
    elseif(-not $i.Extension){$decision=[pscustomobject]@{Action='Install';Reason='Codex nao consta no registro desta instalacao. Instalar pelo Marketplace oficial do VS Code.'}}
    elseif(-not $i.FilesValid){$decision=[pscustomobject]@{Action='Reinstall';Reason='Arquivos essenciais ausentes ou versao dos arquivos diferente do registro. Reinstalar a mesma versao.'}}
    $report.Diagnosis=$e.State.Status;$report.Reason=$decision.Reason;$report.FreshEvidence=$e.Fresh;$report.Signals=$e.State.Signals
    [pscustomobject]@{Evidence=$e;Decision=$decision}
}

function Wait-EditorClosed {
    $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $processes=@(Get-Process -Name Code -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session})
    if(-not $processes.Count){return}
    if($NoPrompt){throw 'VS Code em execucao. Nenhuma alteracao aplicada; feche o editor antes de repetir.'}
    Write-Host ''
    Write-Host 'Salve seu trabalho e feche TODAS as janelas do VS Code.' -ForegroundColor Yellow
    Write-Host 'Nenhum processo sera encerrado a forca. Seus terminais tambem devem ser salvos/encerrados por voce.'
    Read-Host 'Quando terminar, pressione ENTER'|Out-Null
    $deadline=(Get-Date).AddSeconds(60)
    do {
        $processes=@(Get-Process -Name Code -ErrorAction SilentlyContinue|Where-Object {$_.SessionId -eq $session})
        if(-not $processes.Count){return}
        Start-Sleep -Seconds 2
    } while((Get-Date) -lt $deadline)
    throw 'VS Code continua aberto. Operacao cancelada sem encerramento forcado.'
}

function Add-Action([string]$Action,[string]$Result){
    $report.Actions+=@([pscustomobject]@{Action=$Action;Result=$Result;Date=(Get-Date).ToString('o')})
}

function Test-Startup([bool]$WithoutGpu=$false){
    Wait-EditorClosed
    $since=Get-Date
    Write-Host ''
    Write-Host 'Abrindo o Codex para verificar a interface...'
    Write-Host 'Se aparecer a confirmacao do link vscode://openai.chatgpt/, clique em Open/Abrir.' -ForegroundColor Yellow
    Write-Host 'Nao e necessario escrever mensagens nem compartilhar credenciais.'
    $arguments=@('--new-window','--log','debug','--open-url','vscode://openai.chatgpt/')
    if($WithoutGpu){$arguments+=@('--disable-gpu')}
    $result=Invoke-DoctorCodeCli $script:installation $arguments
    if($result.ExitCode -ne 0){throw ('Falha ao abrir VS Code. Exit '+$result.ExitCode+'. '+(Get-CliHint $result))}
    $deadline=(Get-Date).AddSeconds(100)
    do {
        Start-Sleep -Seconds 3
        $e=Read-DoctorEvidence $script:installation.CodeRoot -Since $since
        if(Test-DoctorStartupSuccess $e){return $e}
        if($e.Found -and $e.State.Status -in @('Timeout','WebviewCache','MissingModule','Authentication','Gpu','ProcessFailure')){return $e}
        Write-Host '.' -NoNewline
    } while((Get-Date) -lt $deadline)
    Write-Host ''
    return $e
}

function Get-CliHint($Result){
    $text=$Result.StdErr+"`n"+$Result.StdOut
    if($text -match 'certificate|CERT_|SELF_SIGNED|UNABLE_TO_VERIFY'){return 'O instalador detectou erro de certificado. Encaminhe a TI; validacao TLS preservada.'}
    if($text -match 'ENOTFOUND|ETIMEDOUT|ECONNREFUSED|proxy'){return 'O instalador detectou falha de rede/proxy. Encaminhe a TI.'}
    if($text -match 'not found|not available|No extension'){return 'A versao/extensao solicitada nao esta disponivel neste canal.'}
    return 'Instalador oficial retornou erro. A TI pode repetir a instalacao pelo painel Extensoes.'
}

function Install-Extension([string]$Version){
    $spec='openai.chatgpt'
    if($Version){
        if($Version -notmatch '^\d+(?:\.\d+){1,3}$'){throw 'Versao da extensao invalida. Nenhum comando executado.'}
        $spec+='@'+$Version
    }
    Write-Host "Instalando $spec pelo VS Code. Pode levar alguns minutos..."
    $result=Invoke-DoctorCodeCli $script:installation @('--install-extension',$spec,'--force')
    if($result.ExitCode -ne 0){throw ('Instalacao falhou. Exit '+$result.ExitCode+'. '+(Get-CliHint $result))}
    $updated=Get-DoctorInstallation -CodeExe $script:installation.CodeExe -CodeRoot $script:installation.CodeRoot -ExtensionsRoot $script:installation.ExtensionsRoot
    if(-not $updated.Extension -or -not $updated.FilesValid){throw 'O instalador encerrou, mas os arquivos/registro nao confirmam uma instalacao valida.'}
    if($Version -and $updated.Extension.version -ne $Version){throw 'O instalador nao deixou registrada a versao solicitada.'}
    if($Version -and $updated.Extension.metadata.pinned -ne $true){throw 'A versao foi instalada, mas nao ficou fixada contra atualizacao automatica. Solicite verificacao a TI.'}
    $script:installation=$updated
    $report.CodexVersion=$updated.Extension.version;$report.Pinned=($updated.Extension.metadata.pinned -eq $true)
    Add-Action 'InstallExtension' ('Registro e arquivos confirmados na versao '+$updated.Extension.version)
}

function Save-Report {
    $report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $run 'Relatorio.json') -Encoding UTF8
    $rows=@('CODEX DOCTOR 1.0.0',('Data: '+$report.Date),('Modo: '+$Mode),('VS Code: '+$report.CodeVersion),('Codex: '+$report.CodexVersion),('Versao fixada: '+$report.Pinned),('Diagnostico: '+$report.Diagnosis),('Motivo: '+$report.Reason),('Resultado: '+$report.Outcome),'','ACOES:')
    foreach($action in $report.Actions){$rows+=($action.Action+': '+$action.Result)}
    if($report.Error){$rows+=('Erro: '+$report.Error)}
    $rows+=@('','O relatorio contem sinais classificados, sem copiar logs brutos ou credenciais.','Compartilhe somente Relatorio.txt e Relatorio.json com a TI.','Se a janela nao foi aberta ou o teste nao terminou, a ferramenta nao declara o problema resolvido.')
    $rows|Set-Content -LiteralPath (Join-Path $run 'Relatorio.txt') -Encoding UTF8
}

try {
    Write-Host 'CODEX DOCTOR - suporte ao Codex no VS Code (Windows)' -ForegroundColor Cyan
    Write-Host ('Modo: '+$Mode)
    $script:rules=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'regras.json') -Raw|ConvertFrom-Json
    Assert-DoctorRules $script:rules
    $snapshot=Get-Snapshot
    Write-Host ('VS Code: '+$report.CodeVersion+' | Codex: '+$report.CodexVersion)
    Write-Host $report.Reason

    if($Mode -eq 'Diagnose'){
        $report.Outcome='SomenteDiagnostico';Add-Action 'Diagnose' ('Recomendacao: '+$snapshot.Decision.Action)
    } elseif($Mode -eq 'Restore'){
        if($script:installation.ProfilesDetected -or $script:installation.PortableDetected){throw 'Restauracao automatica bloqueada para perfis personalizados/instalacao portatil. Solicite verificacao a TI.'}
        $backups=@(Get-ChildItem -LiteralPath $ReportRoot -Directory|Sort-Object Name -Descending|ForEach-Object {
            $p=Join-Path $_.FullName 'backup-cache'
            if((Test-Path -LiteralPath (Join-Path $p 'manifest.json')) -and @(Get-ChildItem -LiteralPath $p -Directory).Count){Write-Output $p}
        })
        if(-not $backups.Count){throw 'Nao ha backup de cache disponivel nesta conta.'}
        Write-Host ('Backup selecionado: '+$backups[0])
        Wait-EditorClosed
        [void](Restore-DoctorCaches $script:installation.CodeRoot $backups[0] $run)
        Add-Action 'RestoreCache' 'Backup restaurado; o cache substituido foi preservado separadamente.'
        $report.Outcome='CacheRestauradoNaoVerificado'
        Write-Host 'Cache restaurado. Abra o VS Code normalmente para testar.'
    } else {
        $performed=@();$changes=0;$reproduced=$false;$finished=$false
        while(-not $finished){
            $action=$snapshot.Decision.Action
            # A cache retry may expose the same known version regression.
            if($action -eq 'Cache' -and $action -in $performed -and $snapshot.Evidence.State.Signals.Timeout){
                $timeoutState=[pscustomobject]@{Status='Timeout';Signals=$snapshot.Evidence.State.Signals}
                $next=Get-DoctorDecision $timeoutState $report.CodexVersion $script:rules
                if($next.Action -eq 'Fallback'){$action='Fallback'}
            }
            if($action -eq 'None'){$report.Outcome='UltimaInicializacaoBemSucedida';$finished=$true;continue}
            if($action -eq 'Escalate'){$report.Outcome='EncaminharTI';$finished=$true;continue}
            if($action -in $performed -or $changes -ge 2){$report.Outcome='PersistiuAposCorrecoesConhecidas';$finished=$true;continue}
            if($action -eq 'Reproduce'){
                if($reproduced -or $SkipLaunch){$report.Outcome='SemEvidenciaSuficiente';$finished=$true;continue}
                $reproduced=$true
            } else {
                Wait-EditorClosed
                switch($action){
                    'Cache' {
                        $backup=Backup-DoctorCaches $script:installation.CodeRoot $run
                        Add-Action 'ResetWebviewCache' 'Caches preservados em backup-cache. Serão recriados pelo VS Code.'
                    }
                    'Fallback' {Install-Extension $script:rules.FallbackVersion}
                    'Install' {Install-Extension ''}
                    'Reinstall' {Install-Extension $report.CodexVersion}
                    'GpuTrial' {Add-Action 'GpuTrial' 'Teste sem GPU somente nesta abertura; configuracao permanente nao alterada.'}
                    default {throw 'Acao desconhecida nas regras.'}
                }
                $performed+=@($action);$changes++
                if($SkipLaunch){$report.Outcome='CorrecaoAplicadaNaoVerificada';$finished=$true;continue}
            }
            $test=Test-Startup ($action -eq 'GpuTrial')
            $report.Diagnosis=$test.State.Status;$report.Signals=$test.State.Signals;$report.FreshEvidence=$test.Fresh
            if(Test-DoctorStartupSuccess $test){
                $report.Outcome='InicializacaoConfirmada'
                if($action -eq 'GpuTrial'){$report.Outcome='InicializacaoConfirmadaSomenteSemGPU'}
                Add-Action 'StartupTest' 'app_start outcome=success observado em uma nova ativacao.'
                $finished=$true
            } elseif(-not $test.Found){
                $report.Outcome='TesteNaoConfirmado';$report.Reason='Nenhuma nova ativacao registrada. Confira a janela de confirmacao do VS Code ou encaminhe o relatorio.';$finished=$true
            } else {
                $decision=Get-DoctorDecision $test.State $report.CodexVersion $script:rules -Fresh:$test.Fresh
                $snapshot=[pscustomobject]@{Evidence=$test;Decision=$decision};$report.Reason=$decision.Reason
                if($test.State.Status -eq 'Unknown'){$report.Outcome='TesteNaoConfirmado';$finished=$true}
            }
        }
    }
    Write-Host ''
    if($report.Outcome -eq 'InicializacaoConfirmada'){Write-Host 'A interface do Codex carregou. Confirmado pelos logs.' -ForegroundColor Green}
    elseif($report.Outcome -eq 'UltimaInicializacaoBemSucedida'){Write-Host 'A ultima tentativa registrada iniciou normalmente. Nenhuma alteracao foi feita.' -ForegroundColor Green}
    else {Write-Host ('Resultado: '+$report.Outcome) -ForegroundColor Yellow;Write-Host $report.Reason}
} catch {
    $report.Outcome='Interrompido';$report.Error=Protect-DoctorText $_.Exception.Message
    Write-Host ('Operacao interrompida: '+$report.Error) -ForegroundColor Red
} finally {
    Save-Report
    Write-Host ''
    Write-Host ('Relatorio e backups locais: '+$run)
    if(-not $NoPrompt){Read-Host 'Pressione ENTER para fechar'|Out-Null}
}
if($report.Outcome -eq 'Interrompido'){exit 1}
