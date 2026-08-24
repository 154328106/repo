$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Stop-Removal {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [int]$ExitCode = 1
    )

    Write-Host ''
    Write-Host "停止：$Message" -ForegroundColor Red
    exit $ExitCode
}

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        Stop-Removal -Message $FailureMessage
    }
}

function Read-Yes {
    param([Parameter(Mandatory)][string]$Prompt)

    $answer = Read-Host "$Prompt（输入 Y 确认，其他任意内容取消）"
    if ($null -eq $answer) {
        return $false
    }
    return $answer.Trim() -match '^(?i:y|yes)$'
}

function Get-FriendlySize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return '{0:N2} GB' -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB) {
        return '{0:N2} MB' -f ($Bytes / 1MB)
    }
    return '{0:N1} KB' -f ($Bytes / 1KB)
}

Clear-Host
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host '      无言以对 · DEB 一键删除工具' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-Removal -Message '没有找到 git，请先安装 Git for Windows。'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sectionMapRelativePath = 'config/sections.tsv'
$sectionMapPath = Join-Path $repoRoot $sectionMapRelativePath

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git') -PathType Container)) {
    Stop-Removal -Message "脚本所在位置不是有效仓库：$repoRoot"
}
if (-not (Test-Path -LiteralPath $sectionMapPath -PathType Leaf)) {
    Stop-Removal -Message "缺少分类配置：$sectionMapPath"
}

Set-Location -LiteralPath $repoRoot

$branch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
    Stop-Removal -Message "当前分支是 '$branch'，请切换到 main 后再运行。"
}

$alreadyStaged = @(& git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) {
    Stop-Removal -Message '无法检查 Git 暂存区。'
}
if ($alreadyStaged.Count -gt 0) {
    Write-Host '发现运行脚本前就已经暂存的文件：' -ForegroundColor Yellow
    $alreadyStaged | ForEach-Object { Write-Host "  $_" }
    Stop-Removal -Message '为避免误提交，请先处理或取消这些暂存内容。'
}

$mapStatus = @(& git status --porcelain -- $sectionMapRelativePath)
if ($LASTEXITCODE -ne 0) {
    Stop-Removal -Message '无法检查分类配置。'
}
if ($mapStatus.Count -gt 0) {
    Stop-Removal -Message 'config/sections.tsv 已有尚未提交的修改，请先处理。'
}

Write-Host '正在同步 GitHub main 分支……' -ForegroundColor Cyan
Invoke-GitChecked -Arguments @('pull', '--ff-only', 'origin', 'main') -FailureMessage '同步远端失败。请检查网络和本地修改。'

$trackedPaths = @(& git -c core.quotePath=false ls-files -- 'debs/*.deb')
if ($LASTEXITCODE -ne 0) {
    Stop-Removal -Message '无法读取已发布的软件包列表。'
}
$trackedPaths = @($trackedPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Sort-Object)

if ($trackedPaths.Count -eq 0) {
    Stop-Removal -Message '软件源中没有可以删除的已发布 DEB。'
}

$sectionMap = @{}
foreach ($rawLine in [System.IO.File]::ReadAllLines($sectionMapPath, [System.Text.UTF8Encoding]::new($false))) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) {
        continue
    }

    $parts = @($rawLine -split "`t", 2)
    if ($parts.Count -ne 2) {
        Stop-Removal -Message "分类配置格式错误：$rawLine"
    }
    $sectionMap[$parts[0].Trim().Replace('\', '/')] = $parts[1].Trim()
}

Write-Host ''
Write-Host "软件源中共有 $($trackedPaths.Count) 个已发布 DEB：" -ForegroundColor Green
for ($index = 0; $index -lt $trackedPaths.Count; $index++) {
    $number = $index + 1
    $path = $trackedPaths[$index]
    $file = Get-Item -LiteralPath $path
    $category = $sectionMap[$path]
    if (-not $category) {
        $category = '未分类'
    }
    $size = Get-FriendlySize -Bytes $file.Length
    Write-Host ('[{0,2}] [{1}] {2}  ({3})' -f $number, $category, $file.Name, $size)
}

Write-Host ''
Write-Host '输入一个或多个编号，例如：1 或 1,3。'
Write-Host '为防止清空整个软件源，本工具不提供全选。' -ForegroundColor DarkGray
$selectionText = Read-Host '请选择要从源里删除的插件'
if ($null -eq $selectionText) {
    Stop-Removal -Message '没有选择任何软件包。' -ExitCode 2
}
$tokens = @($selectionText.Trim() -split '[,，\s]+' | Where-Object { $_ })
if ($tokens.Count -eq 0) {
    Stop-Removal -Message '没有选择任何软件包。' -ExitCode 2
}

$selectedIndexes = @()
foreach ($token in $tokens) {
    $number = 0
    if (-not [int]::TryParse($token, [ref]$number)) {
        Stop-Removal -Message "无效编号：$token"
    }
    if ($number -lt 1 -or $number -gt $trackedPaths.Count) {
        Stop-Removal -Message "编号超出范围：$number"
    }
    $selectedIndexes += ($number - 1)
}
$selectedIndexes = @($selectedIndexes | Sort-Object -Unique)
$selectedPaths = @($selectedIndexes | ForEach-Object { $trackedPaths[$_] })

if ($selectedPaths.Count -ge $trackedPaths.Count) {
    Stop-Removal -Message '不能使用本工具一次删除全部软件包。' -ExitCode 2
}

Write-Host ''
Write-Host '准备从软件源删除：' -ForegroundColor Yellow
foreach ($path in $selectedPaths) {
    $category = $sectionMap[$path]
    if (-not $category) {
        $category = '未分类'
    }
    Write-Host "  [$category] $([System.IO.Path]::GetFileName($path))"
}

Write-Host ''
Write-Host '说明：手机上已经安装的插件不会被自动卸载。' -ForegroundColor DarkGray
$deleteConfirmation = Read-Host '确认删除请完整输入 DELETE'
if ($null -eq $deleteConfirmation -or $deleteConfirmation.Trim() -cne 'DELETE') {
    Stop-Removal -Message '用户取消，没有删除任何文件。' -ExitCode 2
}

$backupBase = Join-Path (Split-Path $repoRoot -Parent) 'repo-deb-backups'
$backupDirectory = Join-Path $backupBase (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null

Write-Host ''
Write-Host "正在备份到：$backupDirectory" -ForegroundColor Cyan
foreach ($path in $selectedPaths) {
    $sourcePath = Join-Path $repoRoot $path
    $backupPath = Join-Path $backupDirectory ([System.IO.Path]::GetFileName($path))
    Copy-Item -LiteralPath $sourcePath -Destination $backupPath

    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
    if ($sourceHash -ne $backupHash) {
        Stop-Removal -Message "备份校验失败，没有开始删除：$path"
    }
    Write-Host "  已备份：$([System.IO.Path]::GetFileName($path))"
}

$pathsToCommit = @(($selectedPaths + $sectionMapRelativePath) | Sort-Object -Unique)

function Restore-RemovalChanges {
    & git restore --staged --worktree -- @pathsToCommit
}

& git rm -- @selectedPaths
if ($LASTEXITCODE -ne 0) {
    Restore-RemovalChanges
    Stop-Removal -Message 'Git 删除失败，已经恢复仓库文件；备份仍然保留。'
}

foreach ($path in $selectedPaths) {
    [void]$sectionMap.Remove($path)
}

$sectionLines = @('# Filename<TAB>Section')
foreach ($filename in @($sectionMap.Keys | Sort-Object)) {
    $sectionLines += "$filename`t$($sectionMap[$filename])"
}
[System.IO.File]::WriteAllText(
    $sectionMapPath,
    (($sectionLines -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

& git add -- $sectionMapRelativePath
if ($LASTEXITCODE -ne 0) {
    Restore-RemovalChanges
    Stop-Removal -Message '无法更新分类配置，已经恢复仓库文件；备份仍然保留。'
}

$stagedNow = @(& git -c core.quotePath=false diff --cached --name-only)
$unexpected = @($stagedNow | Where-Object { $_ -notin $pathsToCommit })
if ($unexpected.Count -gt 0) {
    Restore-RemovalChanges
    Write-Host '检测到意外的暂存文件：' -ForegroundColor Yellow
    $unexpected | ForEach-Object { Write-Host "  $_" }
    Stop-Removal -Message '已经恢复本工具的删除操作；备份仍然保留。'
}

Write-Host ''
Write-Host '即将提交的删除内容：' -ForegroundColor Cyan
& git diff --cached --name-status
& git diff --cached --stat

$defaultMessage = if ($selectedPaths.Count -eq 1) {
    "Remove $([System.IO.Path]::GetFileNameWithoutExtension($selectedPaths[0]))"
}
else {
    "Remove $($selectedPaths.Count) packages"
}

$commitMessage = Read-Host "提交说明（直接回车使用：$defaultMessage）"
if ([string]::IsNullOrWhiteSpace($commitMessage)) {
    $commitMessage = $defaultMessage
}

if (-not (Read-Yes -Prompt "确认提交并推送到 main，说明为：$commitMessage")) {
    Restore-RemovalChanges
    Write-Host "已恢复仓库文件。安全备份仍保留在：$backupDirectory" -ForegroundColor Yellow
    Stop-Removal -Message '用户取消。' -ExitCode 2
}

& git commit -m $commitMessage -- @pathsToCommit
if ($LASTEXITCODE -ne 0) {
    Stop-Removal -Message "创建提交失败。备份位于：$backupDirectory"
}

$commitSha = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    Stop-Removal -Message '无法取得新提交编号。'
}

Write-Host ''
Write-Host '正在推送到 GitHub……' -ForegroundColor Cyan
& git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "本地提交已经创建：$commitSha" -ForegroundColor Yellow
    Stop-Removal -Message '推送失败。网络恢复后执行 git push origin main。'
}

Write-Host ''
Write-Host "推送成功：$commitSha" -ForegroundColor Green
Write-Host "安全备份：$backupDirectory" -ForegroundColor Green

$actionsPage = 'https://github.com/154328106/repo/actions'
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCommand) {
    Write-Host '电脑未安装 GitHub CLI，无法在窗口内等待 Actions。' -ForegroundColor Yellow
    Write-Host "请打开：$actionsPage"
    if (Read-Yes -Prompt '现在用浏览器打开 Actions 页面') {
        Start-Process $actionsPage
    }
    exit 0
}

Write-Host '正在等待 GitHub Actions 任务出现……' -ForegroundColor Cyan
$run = $null
for ($attempt = 1; $attempt -le 20; $attempt++) {
    $runJson = & gh run list --workflow publish.yml --commit $commitSha --limit 1 --json databaseId,status,conclusion,url 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($runJson -join ''))) {
        try {
            $runs = @($runJson -join "`n" | ConvertFrom-Json)
            if ($runs.Count -gt 0) {
                $run = $runs[0]
                break
            }
        }
        catch {
            # Actions 刚创建时偶尔返回空内容，继续等待。
        }
    }
    Start-Sleep -Seconds 3
}

if (-not $run) {
    Write-Host '暂时没有查询到 Actions 任务，但提交和推送已经成功。' -ForegroundColor Yellow
    Write-Host "请稍后打开：$actionsPage"
    exit 0
}

Write-Host "Actions：$($run.url)" -ForegroundColor Cyan
Write-Host '正在等待软件源重新生成……' -ForegroundColor Cyan
& gh run watch $run.databaseId --exit-status
$actionExit = $LASTEXITCODE

if ($actionExit -ne 0) {
    Write-Host ''
    Write-Host 'GitHub Actions 构建失败，线上软件源可能仍是旧版本。' -ForegroundColor Red
    Write-Host "查看错误：$($run.url)"
    Write-Host "安全备份：$backupDirectory"
    exit 3
}

Write-Host ''
Write-Host '删除完成，GitHub Actions 构建和部署成功！' -ForegroundColor Green
Write-Host '手机上刷新“无言以对”软件源即可。' -ForegroundColor Green
Write-Host "安全备份：$backupDirectory"
Write-Host "任务地址：$($run.url)"
exit 0
