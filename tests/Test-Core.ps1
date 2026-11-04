param([string]$FixtureRoot = (Join-Path $PSScriptRoot ('scratch-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\CodexDoctor.Core.psm1') -Force -DisableNameChecking
New-Item -ItemType Directory -Path $FixtureRoot -Force | Out-Null
$FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
$script:Passed = 0; $script:Failed = 0
function Check($Name, [scriptblock]$Body) {
    try { & $Body; $script:Passed++; Write-Host "PASS $Name" }
    catch { $script:Failed++; Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
function Equal($Actual, $Expected) { if ($Actual -ne $Expected) { throw "Esperado [$Expected], obtido [$Actual]" } }
function MustThrow([scriptblock]$Body) { $threw=$false; try { & $Body | Out-Null } catch {$threw=$true}; if(-not $threw){throw 'Era esperado recusar a operacao'} }
$rules = [pscustomobject]@{ KnownBadVersions=@('26.1021.22027'); FallbackVersion='26.1007.21434'; FallbackValidUntil='2026-12-04' }
$now=[datetime]'2026-11-04'
Check 'registro com varias extensoes - PowerShell 5.1' {
    $p=Join-Path $FixtureRoot 'extensions.json'
    '[{"identifier":{"id":"other.one"},"version":"1"},{"identifier":{"id":"openai.chatgpt"},"version":"26.1007.21434"},{"identifier":{"id":"other.two"},"version":"2"}]' | Set-Content -LiteralPath $p
    $r=@(Read-DoctorRegistration $p); Equal $r.Count 1; Equal $r[0].version '26.1007.21434'
}
Check 'registro vazio' { $p=Join-Path $FixtureRoot 'empty.json'; '[]'|Set-Content -LiteralPath $p; Equal @(Read-DoctorRegistration $p).Count 0 }
Check 'registro corrompido nao vira extensao ausente' { $p=Join-Path $FixtureRoot 'bad.json'; '{oops'|Set-Content -LiteralPath $p; MustThrow {Read-DoctorRegistration $p} }
Check 'aviso IPC nao e timeout' { Equal (Get-DoctorStartupState @('Initialize received id=1','[warning] IpcClient no handler')).Status 'Unknown' }
Check 'timeout reconhecido' { Equal (Get-DoctorStartupState @('reason=renderer_ready_timeout')).Status 'Timeout' }
Check 'sucesso vence timeout antigo na mesma ativacao' { Equal (Get-DoctorStartupState @('reason=renderer_ready_timeout','name=app_start outcome=success')).Status 'Success' }
Check 'nova ativacao elimina sucesso anterior' { Equal (Get-DoctorStartupState @('name=app_start outcome=success','Activating Codex extension','reason=renderer_ready_timeout')).Status 'Timeout' }
Check '401 nao e erro de cache' { Equal (Get-DoctorStartupState @('httpStatus=401')).Status 'Authentication' }
Check '403 depois de sucesso nao invalida inicializacao' { Equal (Get-DoctorStartupState @('name=app_start outcome=success','httpStatus=403')).Status 'Success' }
Check 'serviceworker sem sucesso vira cache' { Equal (Get-DoctorStartupState @('Could not find inner client for request')).Status 'WebviewCache' }
Check 'certificado exige TI' { Equal (Get-DoctorStartupState @('UNABLE_TO_VERIFY_LEAF_SIGNATURE')).Status 'Network' }
Check 'GPU com crash reconhecido' { Equal (Get-DoctorStartupState @('GPU process exited unexpectedly')).Status 'Gpu' }
Check 'versao afetada permite fallback' { $s=Get-DoctorStartupState @('reason=renderer_ready_timeout'); Equal (Get-DoctorDecision $s '26.1021.22027' $rules $now).Action 'Fallback' }
Check 'timeout em versao nova nao faz downgrade' { $s=Get-DoctorStartupState @('reason=renderer_ready_timeout'); Equal (Get-DoctorDecision $s '26.1104.1' $rules $now).Action 'Cache' }
Check 'fallback expirado nao e aplicado' { $s=Get-DoctorStartupState @('reason=renderer_ready_timeout'); Equal (Get-DoctorDecision $s '26.1021.22027' $rules ([datetime]'2027-01-01')).Action 'Cache' }
Check 'sucesso nao gera alteracoes' { Equal (Get-DoctorDecision (Get-DoctorStartupState @('name=app_start outcome=success')) '26.1021.22027' $rules $now).Action 'None' }
Check 'evidencia velha so pede reproducao' { Equal (Get-DoctorDecision (Get-DoctorStartupState @('reason=renderer_ready_timeout')) '26.1021.22027' $rules $now -Fresh:$false).Action 'Reproduce' }
Check 'versao maliciosa na regra recusada' { $bad=[pscustomobject]@{KnownBadVersions=@('26.1');FallbackVersion='26.1 & calc';FallbackValidUntil='2026-12-04'}; MustThrow {Assert-DoctorRules $bad} }
Check 'data invalida recusada' { $bad=[pscustomobject]@{KnownBadVersions=@('26.1');FallbackVersion='26.1';FallbackValidUntil='amanha'}; MustThrow {Assert-DoctorRules $bad} }
Check 'processo com stderr warning e exit 0 continua' {
    $fixture=Join-Path $FixtureRoot 'warning.ps1'; '[Console]::Error.WriteLine("[DEP0169] warning"); exit 0'|Set-Content -LiteralPath $fixture
    $r=Invoke-DoctorProcess (Get-Command powershell.exe).Source @('-NoProfile','-ExecutionPolicy','Bypass','-File',$fixture)
    Equal $r.ExitCode 0; if($r.StdErr -notmatch 'DEP0169'){throw 'stderr nao capturado'}
}
Check 'processo com falha real preserva exit code' {
    $fixture=Join-Path $FixtureRoot 'failure.ps1'; '[Console]::Error.WriteLine("erro"); exit 17'|Set-Content -LiteralPath $fixture
    Equal (Invoke-DoctorProcess (Get-Command powershell.exe).Source @('-NoProfile','-ExecutionPolicy','Bypass','-File',$fixture)).ExitCode 17
}
Check 'aspas e barras em argumentos preservadas' { Equal (ConvertTo-DoctorArgument 'C:\pasta com espaco\') '"C:\pasta com espaco\\"' }
Check 'backup e restauracao preservam cache atual' {
    $code=Join-Path $FixtureRoot 'Code com espaco'; $run=Join-Path $FixtureRoot ('run-'+[guid]::NewGuid().ToString('N')); $restore=Join-Path $FixtureRoot ('restore-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $code 'Service Worker') -Force|Out-Null
    'original'|Set-Content -LiteralPath (Join-Path $code 'Service Worker\value.txt')
    $backup=Backup-DoctorCaches $code $run
    if(Test-Path -LiteralPath (Join-Path $code 'Service Worker')){throw 'Cache nao foi movido'}
    New-Item -ItemType Directory -Path (Join-Path $code 'Service Worker')|Out-Null
    'novo'|Set-Content -LiteralPath (Join-Path $code 'Service Worker\value.txt')
    Restore-DoctorCaches $code $backup $restore | Out-Null
    Equal (Get-Content -LiteralPath (Join-Path $code 'Service Worker\value.txt')) 'original'
    Equal (Get-Content -LiteralPath (Join-Path $restore 'cache-anterior\Service Worker\value.txt')) 'novo'
}
Check 'manifest adulterado nao move User' {
    $code=Join-Path $FixtureRoot 'safeCode'; $b=Join-Path $FixtureRoot 'evilBackup'; New-Item -ItemType Directory -Path $code,$b -Force|Out-Null
    @{CodeRoot=$code;Names=@('..\User')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $b 'manifest.json')
    MustThrow {Restore-DoctorCaches $code $b (Join-Path $FixtureRoot 'restore-evil')}
}
Check 'manifest de outra instalacao recusado' {
    $code=Join-Path $FixtureRoot 'safeCode'; $b=Join-Path $FixtureRoot 'wrongBackup'; New-Item -ItemType Directory -Path $b -Force|Out-Null
    @{CodeRoot=(Join-Path $FixtureRoot 'other');Names=@('Cache')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $b 'manifest.json')
    MustThrow {Restore-DoctorCaches $code $b (Join-Path $FixtureRoot 'restore-wrong')}
}
Check 'remocao de tokens e caminhos em relatorio' {
    $v=Protect-DoctorText 'Bearer abcdef123456 access_token=secret sk-abcdef123456789012345678901234 C:\Users\Maria\arquivo'
    if($v -match 'abcdef|secret|Maria'){throw 'Dado sensivel nao removido'}
}
Check 'selecionar ultima ativacao, nao ultima escrita de IPC' {
    $root=Join-Path $FixtureRoot 'evidence'; $a=Join-Path $root 'logs\20261104T120000\window1\exthost\openai.chatgpt'; $b=Join-Path $root 'logs\20261104T130000\window1\exthost\openai.chatgpt'
    New-Item -ItemType Directory -Path $a,$b -Force|Out-Null
    @('2026-11-04 12:00:00.000 [info] Activating Codex extension','2026-11-04 12:00:30.000 [error] reason=renderer_ready_timeout','2026-11-04 14:00:00.000 [warning] IpcClient no handler')|Set-Content -LiteralPath (Join-Path $a 'Codex.log')
    @('2026-11-04 13:00:00.000 [info] Activating Codex extension','2026-11-04 13:00:11.000 [info] name=app_start outcome=success')|Set-Content -LiteralPath (Join-Path $b 'Codex.log')
    $e=Read-DoctorEvidence $root -Now ([datetime]'2026-11-04T15:00:00'); Equal $e.State.Status 'Success'; Equal $e.ActivationTime.Hour 13
}
Check 'teste novo nao aceita sucesso anterior' {
    $root=Join-Path $FixtureRoot 'evidence'; $e=Read-DoctorEvidence $root -Since ([datetime]'2026-11-04T15:00:00') -Now ([datetime]'2026-11-04T15:01:00'); Equal $e.Found $false
}
Check 'log antigo nao autoriza reparo automatico' {
    $e=Read-DoctorEvidence (Join-Path $FixtureRoot 'evidence') -Now ([datetime]'2026-11-07'); Equal $e.Fresh $false
}
Check 'renderer de outra janela nao contamina diagnostico' {
    $root=Join-Path $FixtureRoot 'evidence'; $p=Join-Path $root 'logs\20261104T130000\window2';New-Item -ItemType Directory -Path $p -Force|Out-Null
    '2026-11-04 13:00:01.000 Could not find inner client for request'|Set-Content -LiteralPath (Join-Path $p 'renderer.log')
    Equal (Read-DoctorEvidence $root -Now ([datetime]'2026-11-04T15:00:00')).State.Status 'Success'
}
Check 'eventos no mesmo milissegundo mantem a ordem no PS5' {
    $root=Join-Path $FixtureRoot 'same-time';$p=Join-Path $root 'logs\20261104T150000\window1\exthost\openai.chatgpt';New-Item -ItemType Directory -Path $p -Force|Out-Null
    @('2026-11-04 15:00:00.000 Activating Codex extension','2026-11-04 15:00:00.000 name=app_start outcome=success','2026-11-04 15:00:00.000 IpcClient no handler')|Set-Content -LiteralPath (Join-Path $p 'Codex.log')
    Equal (Read-DoctorEvidence $root -Now ([datetime]'2026-11-04T16:00:00')).State.Status 'Success'
}
Check 'proxy explicito tem prioridade sobre timeout' {Equal (Get-DoctorStartupState @('ERR_PROXY_CONNECTION_FAILED','reason=renderer_ready_timeout')).Status 'Network'}
Check 'DNS explicito tem prioridade sobre timeout' {Equal (Get-DoctorStartupState @('ENOTFOUND','reason=renderer_ready_timeout')).Status 'Network'}
Check 'host travado tem prioridade sobre timeout' {Equal (Get-DoctorStartupState @('Extension host is unresponsive','reason=renderer_ready_timeout')).Status 'HostUnresponsive'}
Check 'processo interno encerrado tem prioridade sobre timeout' {Equal (Get-DoctorStartupState @('app-server exited with code 1','reason=renderer_ready_timeout')).Status 'ProcessFailure'}
Check 'log novo sem ativacao visivel nao aceita sucesso antigo' {
    $root=Join-Path $FixtureRoot 'tail-missing';$a=Join-Path $root 'logs\20261104T120000\window1\exthost\openai.chatgpt';$b=Join-Path $root 'logs\20261104T130000\window1\exthost\openai.chatgpt'
    New-Item -ItemType Directory -Path $a,$b -Force|Out-Null
    @('2026-11-04 12:00:00.000 Activating Codex extension','2026-11-04 12:00:10.000 name=app_start outcome=success')|Set-Content -LiteralPath (Join-Path $a 'Codex.log')
    $lines=@('2026-11-04 13:00:00.000 Activating Codex extension','2026-11-04 13:00:30.000 reason=renderer_ready_timeout')+@((1..5001)|ForEach-Object {'2026-11-04 14:00:00.000 IpcClient no handler'})
    $lines|Set-Content -LiteralPath (Join-Path $b 'Codex.log')
    $e=Read-DoctorEvidence $root -Now ([datetime]'2026-11-04T15:00:00')
    if($e.State.Status -eq 'Success'){throw 'Aceitou sucesso antigo ignorando log novo'}
    Equal $e.Fresh $false
}
Check 'junction no cache nao toca destino externo' {
    $code=Join-Path $FixtureRoot 'junction-code';$outside=Join-Path $FixtureRoot 'outside';New-Item -ItemType Directory -Path $code,$outside -Force|Out-Null
    'preservar'|Set-Content -LiteralPath (Join-Path $outside 'marker.txt')
    New-Item -ItemType Junction -Path (Join-Path $code 'Service Worker') -Target $outside|Out-Null
    MustThrow {Backup-DoctorCaches $code (Join-Path $FixtureRoot 'junction-run')}
    Equal (Get-Content -LiteralPath (Join-Path $outside 'marker.txt')) 'preservar'
}
Check 'sucesso sem evidencia fresca nao confirma reteste' {Equal (Test-DoctorStartupSuccess ([pscustomobject]@{Found=$true;Fresh=$false;State=[pscustomobject]@{Status='Success'}})) $false}
Check 'sucesso com evidencia fresca confirma reteste' {Equal (Test-DoctorStartupSuccess ([pscustomobject]@{Found=$true;Fresh=$true;State=[pscustomobject]@{Status='Success'}})) $true}
Check 'restauracao recusa duplicatas antes de mover arquivos' {
    $code=Join-Path $FixtureRoot 'duplicate-code';$b=Join-Path $FixtureRoot 'duplicate-backup';$r=Join-Path $FixtureRoot 'duplicate-restore'
    New-Item -ItemType Directory -Path (Join-Path $code 'Cache'),(Join-Path $b 'Cache') -Force|Out-Null
    'atual'|Set-Content -LiteralPath (Join-Path $code 'Cache\marker.txt');'anterior'|Set-Content -LiteralPath (Join-Path $b 'Cache\marker.txt')
    @{SchemaVersion=1;CodeRoot=$code;Names=@('Cache','Cache')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $b 'manifest.json')
    MustThrow {Restore-DoctorCaches $code $b $r}
    Equal (Get-Content -LiteralPath (Join-Path $code 'Cache\marker.txt')) 'atual'
    Equal (Get-Content -LiteralPath (Join-Path $b 'Cache\marker.txt')) 'anterior'
}
Check 'perfil personalizado identificado sem alterar instalacao' {
    $root=Join-Path $FixtureRoot 'profile-code';New-Item -ItemType Directory -Path (Join-Path $root 'User\profiles\profile-id') -Force|Out-Null
    $exe=Join-Path $FixtureRoot 'fake-Code.exe';'fixture'|Set-Content -LiteralPath $exe
    Equal (Get-DoctorInstallation -CodeExe $exe -CodeRoot $root -ExtensionsRoot (Join-Path $FixtureRoot 'no-extensions')).ProfilesDetected $true
}
Check 'raiz de volume recusada como alvo' {MustThrow {Assert-DoctorPlainPath ([IO.Path]::GetPathRoot($FixtureRoot))}}
Check 'backup parcial restaura somente caches efetivamente preservados' {
    $code=Join-Path $FixtureRoot 'partial-code';$b=Join-Path $FixtureRoot 'partial-backup';$r=Join-Path $FixtureRoot 'partial-restore'
    New-Item -ItemType Directory -Path (Join-Path $code 'Service Worker'),(Join-Path $b 'Cache') -Force|Out-Null
    'intacto'|Set-Content -LiteralPath (Join-Path $code 'Service Worker\marker.txt');'original'|Set-Content -LiteralPath (Join-Path $b 'Cache\marker.txt')
    @{SchemaVersion=1;CodeRoot=$code;Names=@('Service Worker','Cache')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $b 'manifest.json')
    Restore-DoctorCaches $code $b $r|Out-Null
    Equal (Get-Content -LiteralPath (Join-Path $code 'Service Worker\marker.txt')) 'intacto'
    Equal (Get-Content -LiteralPath (Join-Path $code 'Cache\marker.txt')) 'original'
}
Write-Host "RESULTADO $script:Passed aprovados, $script:Failed falhas"
if($script:Failed){exit 1}
