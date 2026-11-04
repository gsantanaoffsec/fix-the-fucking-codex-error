$ErrorActionPreference = 'Stop'
$script:CacheNames = @('Service Worker', 'Code Cache', 'Cache')

function Read-DoctorRegistration {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $entries = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($entry in $entries) {
        if ($entry.identifier.id -eq 'openai.chatgpt') { Write-Output $entry }
    }
}

function Get-DoctorStartupState {
    param([string[]]$Lines = @())
    $start = 0
    for ($i=0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match 'Activating Codex extension') { $start=$i }
    }
    $text = ''
    if ($Lines.Count) { $text = ($Lines[$start..($Lines.Count-1)] -join "`n") }
    $successIndex=-1; $timeoutIndex=-1
    for ($i=$start; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match 'name=app_start\b.*\boutcome=success\b') { $successIndex=$i }
        if ($Lines[$i] -match 'renderer_ready_timeout|Webview renderer did not become ready|Codex could not start its user interface') { $timeoutIndex=$i }
    }
    $signals=[ordered]@{
        BackendInitialized=($text -match 'Initialize received')
        RendererReady=($text -match '"renderer_ready"\s*:')
        Timeout=($timeoutIndex -ge 0)
        ServiceWorker=($text -match 'Could not find inner client|Failed to register a ServiceWorker|Could not register service worker')
        Certificate=($text -match 'UNABLE_TO_VERIFY_LEAF_SIGNATURE|CERT_HAS_EXPIRED|SELF_SIGNED_CERT|unable to get local issuer certificate|certificate chain')
        Authentication=($text -match 'httpStatus=401|status=401\b|token_expired|invalid_grant')
        Network=($text -match 'ENOTFOUND|ECONNREFUSED|ETIMEDOUT|ERR_PROXY_CONNECTION_FAILED|cloudflare_challenge')
        GpuCrash=($text -match 'GPU process (?:exited unexpectedly|crashed)|gpu-process.*(?:crash|exit code)')
        HostUnresponsive=($text -match 'Extension host.*is unresponsive|UNRESPONSIVE extension host')
        ProcessFailure=($text -match 'app-server.*(?:ENOENT|exited with code|failed to spawn)|spawn.*codex.*ENOENT')
        MissingModule=($text -match 'does not provide an export|ERR_FILE_NOT_FOUND|Cannot find module|Failed to fetch dynamically imported module')
    }
    $status='Unknown'
    if ($successIndex -ge 0 -and $successIndex -gt $timeoutIndex) { $status='Success' }
    elseif ($signals.Certificate) { $status='Network' }
    elseif ($signals.Authentication) { $status='Authentication' }
    elseif ($signals.Network) { $status='Network' }
    elseif ($signals.ProcessFailure) { $status='ProcessFailure' }
    elseif ($signals.HostUnresponsive) { $status='HostUnresponsive' }
    elseif ($signals.ServiceWorker) { $status='WebviewCache' }
    elseif ($signals.MissingModule) { $status='MissingModule' }
    elseif ($signals.GpuCrash) { $status='Gpu' }
    elseif ($timeoutIndex -ge 0) { $status='Timeout' }
    return [pscustomobject]@{Status=$status;Signals=[pscustomobject]$signals}
}

function Assert-DoctorRules {
    param($Rules)
    if (-not $Rules -or @($Rules.KnownBadVersions).Count -eq 0) { throw 'Regras sem versoes afetadas.' }
    foreach ($v in @($Rules.KnownBadVersions)+@($Rules.FallbackVersion)) {
        if ([string]$v -notmatch '^\d+(?:\.\d+){1,3}$') { throw 'Versao invalida nas regras.' }
    }
    $date=[datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$Rules.FallbackValidUntil,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) { throw 'Data de validade invalida nas regras.' }
}

function Get-DoctorDecision {
    param($State, [string]$InstalledVersion, $Rules, [datetime]$Now=(Get-Date), [bool]$Fresh=$true)
    Assert-DoctorRules $Rules
    $action='Escalate'; $reason='Causa sem correcao automatica conhecida. Encaminhe o relatorio a TI.'
    if (-not $Fresh) { $action='Reproduce';$reason='Sem evidencia recente. Abrir o Codex para registrar uma nova tentativa.' }
    elseif ($State.Status -eq 'Success') { $action='None';$reason='A ultima tentativa registrada carregou a interface. Nenhuma correcao indicada.' }
    elseif ($State.Status -eq 'WebviewCache') { $action='Cache';$reason='Falha de Service Worker detectada. Preservar e recriar os caches de recursos da interface.' }
    elseif ($State.Status -eq 'Timeout') {
        $validUntil=[datetime]::ParseExact($Rules.FallbackValidUntil,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
        if ($InstalledVersion -in @($Rules.KnownBadVersions) -and $Now.Date -le $validUntil.Date) {
            $action='Fallback';$reason='Timeout na versao com regressao conhecida. Instalar e fixar a versao validada pela TI.'
        } else { $action='Cache';$reason='Timeout sem regressao de versao validada. Tentar uma recriacao de cache; nao fazer downgrade arbitrario.' }
    }
    elseif ($State.Status -eq 'MissingModule') { $action='Reinstall';$reason='Recurso JavaScript/modulo ausente ou inconsistente. Reinstalar a mesma versao pelo VS Code.' }
    elseif ($State.Status -eq 'Gpu') { $action='GpuTrial';$reason='Crash grafico detectado. Testar uma abertura sem GPU, sem alterar configuracoes permanentes.' }
    elseif ($State.Status -eq 'Authentication') { $reason='Autenticacao recusada. Entre novamente na conta pelo Codex; nenhuma credencial sera removida.' }
    elseif ($State.Status -eq 'Network') { $reason='Erro de rede, proxy, certificado ou bloqueio remoto. Solicitar verificacao a TI; seguranca nao sera desativada.' }
    elseif ($State.Status -eq 'HostUnresponsive') { $reason='Host de extensoes sem resposta. TI deve investigar conflito/performance; outras extensoes nao serao desativadas automaticamente.' }
    elseif ($State.Status -eq 'ProcessFailure') { $reason='O processo interno falhou. TI deve verificar o executavel e o erro; dependencias nao serao instaladas por suposicao.' }
    elseif ($State.Status -eq 'Unknown') { $action='Reproduce';$reason='Ainda sem erro de inicializacao identificavel. Registrar uma nova tentativa antes de alterar a instalacao.' }
    [pscustomobject]@{Action=$action;Reason=$reason}
}

function ConvertTo-DoctorArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped=[regex]::Replace($Value,'(\\*)"','$1$1\"')
    $escaped=[regex]::Replace($escaped,'(\\+)$','$1$1')
    return '"'+$escaped+'"'
}

function Invoke-DoctorProcess {
    param([string]$FilePath,[string[]]$Arguments=@(),[hashtable]$Environment=@{},[int]$TimeoutSeconds=180)
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$FilePath
    $info.Arguments=(($Arguments | ForEach-Object {ConvertTo-DoctorArgument $_}) -join ' ')
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    foreach($key in $Environment.Keys){$info.EnvironmentVariables[$key]=[string]$Environment[$key]}
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try {
        [void]$p.Start()
        $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit($TimeoutSeconds*1000)){
            throw "O comando excedeu o tempo de espera (PID $($p.Id)). Ele nao foi encerrado a forca; verifique antes de repetir."
        }
        $p.WaitForExit()
        return [pscustomobject]@{ExitCode=$p.ExitCode;StdOut=$outTask.GetAwaiter().GetResult();StdErr=$errTask.GetAwaiter().GetResult()}
    } finally { $p.Dispose() }
}

function Assert-DoctorPlainPath {
    param([string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    if($full.TrimEnd('\','/') -eq [IO.Path]::GetPathRoot($full).TrimEnd('\','/')){throw 'Raiz de volume nao pode ser usada como alvo.'}
    $current=$full
    while($current){
        if(Test-Path -LiteralPath $current){
            $item=Get-Item -LiteralPath $current -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Caminho com junction/link recusado para proteger os dados.'}
        }
        $parent=[IO.Path]::GetDirectoryName($current)
        if($parent -eq $current){break};$current=$parent
    }
    return $full.TrimEnd('\','/')
}

function Assert-DoctorCacheTree {
    param([string]$Path)
    [void](Assert-DoctorPlainPath $Path)
    if(Test-Path -LiteralPath $Path){
        $links=@(Get-ChildItem -LiteralPath $Path -Recurse -Force -Attributes ReparsePoint -ErrorAction Stop)
        if($links.Count){throw 'Cache contem links/junctions. Operacao recusada.'}
    }
}

function Backup-DoctorCaches {
    param([string]$CodeRoot,[string]$RunRoot)
    $code=Assert-DoctorPlainPath $CodeRoot
    $run=Assert-DoctorPlainPath $RunRoot
    if($run -eq $code -or $run.StartsWith($code+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'O backup deve ficar fora dos dados do VS Code.'}
    $backup=Join-Path $run 'backup-cache'
    if(Test-Path -LiteralPath $backup){throw 'Ja existe backup neste local. Nenhum arquivo sera sobreposto.'}
    $names=@($script:CacheNames|Where-Object {Test-Path -LiteralPath (Join-Path $code $_) -PathType Container})
    foreach($name in $names){Assert-DoctorCacheTree (Join-Path $code $name)}
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    @{SchemaVersion=1;CodeRoot=$code;Names=$names;Created=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
    foreach($name in $names){Move-Item -LiteralPath (Join-Path $code $name) -Destination (Join-Path $backup $name) -ErrorAction Stop}
    return $backup
}

function Restore-DoctorCaches {
    param([string]$CodeRoot,[string]$BackupRoot,[string]$PreserveRoot)
    $code=Assert-DoctorPlainPath $CodeRoot;$backup=Assert-DoctorPlainPath $BackupRoot;$preserve=Assert-DoctorPlainPath $PreserveRoot
    if($preserve -eq $code -or $preserve.StartsWith($code+'\',[StringComparison]::OrdinalIgnoreCase) -or $preserve -eq $backup -or $preserve.StartsWith($backup+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Local de preservacao invalido.'}
    $manifestPath=Join-Path $backup 'manifest.json';[void](Assert-DoctorPlainPath $manifestPath)
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($manifest.SchemaVersion -ne 1){throw 'Formato de backup nao suportado.'}
    if([IO.Path]::GetFullPath([string]$manifest.CodeRoot).TrimEnd('\','/') -ne $code){throw 'Backup pertence a outra instalacao.'}
    $names=@($manifest.Names)
    if(-not $names.Count){throw 'O backup nao contem caches para restaurar.'}
    if(@($names|Sort-Object -Unique).Count -ne $names.Count){throw 'Nomes duplicados no manifest. Nenhum cache foi movido.'}
    $available=@()
    foreach($name in $names){
        if($name -notin $script:CacheNames){throw 'Nome de cache invalido no manifest.'}
        if(-not (Test-Path -LiteralPath (Join-Path $backup $name) -PathType Container)){
            if(Test-Path -LiteralPath (Join-Path $code $name) -PathType Container){continue}
            throw 'Cache ausente tanto no backup como na instalacao. A TI deve verificar.'
        }
        Assert-DoctorCacheTree (Join-Path $backup $name);Assert-DoctorCacheTree (Join-Path $code $name)
        $available+=@($name)
    }
    if(-not $available.Count){throw 'Este backup ja foi restaurado ou nao contem caches.'}
    $saved=Join-Path $preserve 'cache-anterior'
    if(Test-Path -LiteralPath $saved){throw 'Ja existe cache preservado neste destino.'}
    New-Item -ItemType Directory -Path $saved -Force|Out-Null
    foreach($name in $available){
        $destination=Join-Path $code $name
        if(Test-Path -LiteralPath $destination){Move-Item -LiteralPath $destination -Destination (Join-Path $saved $name)}
        Move-Item -LiteralPath (Join-Path $backup $name) -Destination $destination
    }
    return $saved
}

function Protect-DoctorText {
    param([string]$Text)
    $s=[regex]::Replace($Text,'(?i)Bearer\s+\S+','Bearer [REMOVIDO]')
    $s=[regex]::Replace($s,'(?i)(access_token|refresh_token|api_key|authorization)\s*[=:]\s*[^\s,;]+','$1=[REMOVIDO]')
    $s=[regex]::Replace($s,'sk-[A-Za-z0-9_-]{12,}','[CHAVE REMOVIDA]')
    $s=[regex]::Replace($s,'(?i)[A-Z]:\\Users\\[^\\\s]+','%USERPROFILE%')
    $s=[regex]::Replace($s,'https?://[^\s"<>]+','[URL REMOVIDA]')
    return $s
}

function Get-DoctorLineTime {
    param([string]$Line)
    $time=[datetime]::MinValue
    if($Line.Length -ge 23){
        [void][datetime]::TryParseExact($Line.Substring(0,23),'yyyy-MM-dd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$time)
    }
    return $time
}

function Read-DoctorEvidence {
    param([string]$CodeRoot,[datetime]$Since=[datetime]::MinValue,[datetime]$Now=(Get-Date))
    $logsRoot=Join-Path $CodeRoot 'logs';$candidates=@()
    if(Test-Path -LiteralPath $logsRoot){
        $sessions=@(Get-ChildItem -LiteralPath $logsRoot -Directory -ErrorAction Stop|Sort-Object Name -Descending|Select-Object -First 6)
        foreach($session in $sessions){
            foreach($window in @(Get-ChildItem -LiteralPath $session.FullName -Directory -Filter 'window*')){
                $path=Join-Path $window.FullName 'exthost\openai.chatgpt\Codex.log'
                if(-not (Test-Path -LiteralPath $path)){continue}
                $lines=@(Get-Content -LiteralPath $path -Tail 5000 -ErrorAction Stop)
                $activation=[datetime]::MinValue
                foreach($line in $lines){if($line -match 'Activating Codex extension'){$activation=Get-DoctorLineTime $line}}
                if($activation -eq [datetime]::MinValue){
                    # Do not silently choose an older success when the newest file
                    # has outgrown the bounded tail. Reproduction is safer.
                    $lastWrite=(Get-Item -LiteralPath $path).LastWriteTime
                    if($Since -eq [datetime]::MinValue -or $lastWrite -ge $Since){
                        $candidates+=[pscustomobject]@{Activation=$lastWrite;Lines=@();Window=$window.FullName;MarkerMissing=$true}
                    }
                    continue
                }
                if($Since -ne [datetime]::MinValue -and $activation -lt $Since.AddMilliseconds(-500)){continue}
                $candidates+=[pscustomobject]@{Activation=$activation;Lines=$lines;Window=$window.FullName;MarkerMissing=$false}
            }
        }
    }
    $selected=$candidates|Sort-Object Activation -Descending|Select-Object -First 1
    if(-not $selected){return [pscustomobject]@{Found=$false;Fresh=$false;ActivationTime=$null;State=(Get-DoctorStartupState);Source=$null}}
    if($selected.MarkerMissing){return [pscustomobject]@{Found=$false;Fresh=$false;ActivationTime=$null;State=(Get-DoctorStartupState);Source=$selected.Window}}
    $events=@()
    foreach($line in $selected.Lines){$time=Get-DoctorLineTime $line;if($time -ge $selected.Activation -and $time -le $Now.AddSeconds(2)){$events+=[pscustomobject]@{Time=$time;Order=$events.Count;Line=$line}}}
    $renderer=Join-Path $selected.Window 'renderer.log'
    if(Test-Path -LiteralPath $renderer){
        foreach($line in @(Get-Content -LiteralPath $renderer -Tail 3000)){
            $time=Get-DoctorLineTime $line
            if($time -ge $selected.Activation -and $time -le $Now.AddSeconds(2) -and $line -match 'Could not find inner client|ServiceWorker|Could not register service worker|GPU process (?:exited unexpectedly|crashed)|UNRESPONSIVE extension host|Extension host.*is unresponsive'){
                $events+=[pscustomobject]@{Time=$time;Order=$events.Count;Line=$line}
            }
        }
    }
    # Sort-Object in Windows PowerShell 5.1 is not stable for equal timestamps.
    $orderedLines=@($events|Sort-Object Time,Order|ForEach-Object {$_.Line})
    $fresh=$selected.Activation -ge $Now.AddHours(-24) -and $selected.Activation -le $Now.AddSeconds(2)
    return [pscustomobject]@{Found=$true;Fresh=$fresh;ActivationTime=$selected.Activation;State=(Get-DoctorStartupState $orderedLines);Source=$selected.Window}
}

function Get-DoctorInstallation {
    param([string]$CodeExe,[string]$CodeRoot,[string]$ExtensionsRoot)
    if(-not $CodeRoot){$CodeRoot=Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Code'}
    if(-not $ExtensionsRoot){$ExtensionsRoot=Join-Path $env:USERPROFILE '.vscode\extensions'}
    if(-not $CodeExe){
        $bases=@($env:LOCALAPPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)})|Where-Object {$_}
        $options=@((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'))
        foreach($base in $bases){$options+=Join-Path $base 'Microsoft VS Code\Code.exe'}
        $CodeExe=$options|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
    }
    $cliScript=$null;$codeVersion=$null;$extension=$null;$filesValid=$false;$binaryPresent=$false;$engineCompatible=$true;$portable=$false
    if($CodeExe){
        $CodeExe=[IO.Path]::GetFullPath($CodeExe)
        if(-not (Test-Path -LiteralPath $CodeExe -PathType Leaf)){throw 'Code.exe nao encontrado no caminho informado.'}
        $appRoot=Split-Path -Parent $CodeExe
        $portable=Test-Path -LiteralPath (Join-Path $appRoot 'data') -PathType Container
        $cliCandidates=@((Join-Path $appRoot 'resources\app\out\cli.js'))
        foreach($dir in @(Get-ChildItem -LiteralPath $appRoot -Directory)){$cliCandidates+=Join-Path $dir.FullName 'resources\app\out\cli.js'}
        $cliScript=$cliCandidates|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
        $codeVersion=(Get-Item -LiteralPath $CodeExe).VersionInfo.ProductVersion
    }
    $registered=@(Read-DoctorRegistration (Join-Path $ExtensionsRoot 'extensions.json'))
    if($registered.Count -gt 1){throw 'Registro ambiguo: mais de uma instalacao ativa do Codex. TI deve verificar o perfil.'}
    if($registered.Count){
        $extension=$registered[0]
        $relative=[string]$extension.relativeLocation
        if(-not $relative -or [IO.Path]::GetFileName($relative) -ne $relative){throw 'Localizacao da extensao invalida no registro.'}
        $manifestPath=Join-Path (Join-Path $ExtensionsRoot $relative) 'package.json'
        if(Test-Path -LiteralPath $manifestPath){
            try {
                $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
                $extensionDir=Split-Path -Parent $manifestPath
                $binaries=@(Get-ChildItem -LiteralPath (Join-Path $extensionDir 'bin') -Recurse -File -Filter 'codex.exe' -ErrorAction SilentlyContinue)
                $binaryPresent=$binaries.Count -gt 0
                $filesValid=$manifest.version -eq $extension.version -and (Test-Path -LiteralPath (Join-Path $extensionDir 'out\extension.js')) -and (Test-Path -LiteralPath (Join-Path $extensionDir 'webview\index.html')) -and $binaryPresent
                if($codeVersion -match '^(\d+\.\d+\.\d+)' -and $manifest.engines.vscode -match '(\d+\.\d+\.\d+)'){
                    $actual=[regex]::Match($codeVersion,'\d+\.\d+\.\d+').Value
                    $minimum=[regex]::Match($manifest.engines.vscode,'\d+\.\d+\.\d+').Value
                    $engineCompatible=[version]$actual -ge [version]$minimum
                }
            } catch {$filesValid=$false}
        }
    }
    $profilesPath=Join-Path $CodeRoot 'User\profiles'
    $profiles=$false
    if(Test-Path -LiteralPath $profilesPath){$profiles=@(Get-ChildItem -LiteralPath $profilesPath -Directory).Count -gt 0}
    [pscustomobject]@{CodeExe=$CodeExe;CodeRoot=[IO.Path]::GetFullPath($CodeRoot);ExtensionsRoot=[IO.Path]::GetFullPath($ExtensionsRoot);CliScript=$cliScript;CodeVersion=$codeVersion;Extension=$extension;FilesValid=$filesValid;EngineCompatible=$engineCompatible;ProfilesDetected=$profiles;PortableDetected=$portable}
}

function Test-DoctorStartupSuccess {
    param($Evidence)
    return [bool]($Evidence -and $Evidence.Found -and $Evidence.Fresh -and $Evidence.State.Status -eq 'Success')
}

function Invoke-DoctorCodeCli {
    param($Installation,[string[]]$CliArguments)
    if(-not $Installation.CliScript){throw 'CLI oficial do VS Code nao encontrado.'}
    $args=@($Installation.CliScript)+$CliArguments+@('--user-data-dir',$Installation.CodeRoot,'--extensions-dir',$Installation.ExtensionsRoot)
    Invoke-DoctorProcess $Installation.CodeExe $args @{ELECTRON_RUN_AS_NODE='1';VSCODE_IPC_HOOK_CLI='';VSCODE_CWD='';VSCODE_DEV=''}
}

Export-ModuleMember -Function *-Doctor*
