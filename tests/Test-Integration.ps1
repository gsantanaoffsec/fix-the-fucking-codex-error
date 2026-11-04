param([string]$FixtureRoot=(Join-Path $PSScriptRoot ('integration-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$FixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
$code=Join-Path $FixtureRoot 'Code';$exts=Join-Path $FixtureRoot 'extensions';$logs=Join-Path $code 'logs\20261104T190000\window1\exthost\openai.chatgpt';$reports=Join-Path $FixtureRoot 'reports'
$extension=Join-Path $exts 'openai.chatgpt-test'
foreach($p in @($logs,(Join-Path $extension 'out'),(Join-Path $extension 'webview'),(Join-Path $extension 'bin\windows-x86_64'))){New-Item -ItemType Directory -Path $p -Force|Out-Null}
$fakeCode=Join-Path $FixtureRoot 'Code.exe';'nao e um executavel'|Set-Content -LiteralPath $fakeCode
'{"version":"26.1007.21434"}'|Set-Content -LiteralPath (Join-Path $extension 'package.json')
foreach($p in @('out\extension.js','webview\index.html','bin\windows-x86_64\codex.exe')){'fixture'|Set-Content -LiteralPath (Join-Path $extension $p)}
'[{"identifier":{"id":"other.ext"},"version":"1"},{"identifier":{"id":"openai.chatgpt"},"version":"26.1007.21434","relativeLocation":"openai.chatgpt-test","metadata":{"pinned":true}}]'|Set-Content -LiteralPath (Join-Path $exts 'extensions.json')
$time=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
@("$time [info] Activating Codex extension","$time [info] name=app_start outcome=success","$time Bearer secret-fixture-token access_token=secret-fixture-token")|Set-Content -LiteralPath (Join-Path $logs 'Codex.log')
$main=Join-Path $PSScriptRoot '..\CodexDoctor.ps1'
function RunDoctor([string]$Mode,[switch]$SkipLaunch){
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$main,'-Mode',$Mode,'-CodePath',$fakeCode,'-UserDataDir',$code,'-ExtensionsDir',$exts,'-ReportRoot',$reports,'-NoPrompt')
    if($SkipLaunch){$args+='-SkipLaunch'}
    & powershell.exe @args | Out-Host
    if($LASTEXITCODE -ne 0){throw 'Orquestrador terminou com erro'}
    $last=Get-ChildItem -LiteralPath $reports -Directory|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    Get-Content -LiteralPath (Join-Path $last.FullName 'Relatorio.json') -Raw|ConvertFrom-Json
}
$before=@(Get-ChildItem -LiteralPath $code,$exts -Recurse -File|Get-FileHash|ForEach-Object {$_.Hash}) -join ','
$r=RunDoctor 'Diagnose'
if($r.Outcome -ne 'SomenteDiagnostico' -or $r.Diagnosis -ne 'Success'){throw 'Diagnostico de sucesso incorreto'}
Write-Host 'PASS diagnostico via programa completo - PowerShell 5.1'
$r=RunDoctor 'Repair' -SkipLaunch
if($r.Outcome -ne 'UltimaInicializacaoBemSucedida' -or $r.Actions.Count -ne 0){throw 'Reparo alterou instalacao saudavel'}
Write-Host 'PASS reparo nao altera ambiente saudavel'
$after=@(Get-ChildItem -LiteralPath $code,$exts -Recurse -File|Get-FileHash|ForEach-Object {$_.Hash}) -join ','
if($before -ne $after){throw 'Arquivos de entrada foram alterados'}
Write-Host 'PASS hashes dos dados e extensoes preservados'
foreach($f in Get-ChildItem -LiteralPath $reports -Recurse -File){if((Get-Content -LiteralPath $f.FullName -Raw) -match 'secret-fixture-token'){throw 'Token de fixture vazou no relatorio'}}
Write-Host 'PASS relatorios nao copiam token dos logs'
@("$time [info] Activating Codex extension","$time [warning] IpcClient no handler")|Set-Content -LiteralPath (Join-Path $logs 'Codex.log')
$r=RunDoctor 'Repair' -SkipLaunch
if($r.Outcome -ne 'SemEvidenciaSuficiente'){throw 'Ausencia de erro interpretada como sucesso'}
Write-Host 'PASS sem evidencia nao declara sucesso'
New-Item -ItemType Directory -Path (Join-Path $code 'User\profiles\profile-id') -Force|Out-Null
$r=RunDoctor 'Repair' -SkipLaunch
if($r.Outcome -ne 'EncaminharTI' -or $r.Reason -notmatch 'Perfis personalizados'){throw 'Perfil personalizado nao bloqueou alteracoes automaticas'}
Write-Host 'PASS perfil personalizado bloqueia reparo automatico'
Write-Host 'RESULTADO 6 integracoes aprovadas'
