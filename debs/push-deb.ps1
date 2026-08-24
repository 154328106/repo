param(
    [Parameter(Position = 0)]
    [string]$SourceDirectory
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Stop-Publish {
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
        Stop-Publish -Message $FailureMessage
    }
}

function Read-Yes {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $answer = Read-Host "$Prompt（输入 Y 确认，其他任意内容取消）"
    if ($null -eq $answer) {
        return $false
    }
    $answer = $answer.Trim()
    return $answer -match '^(?i:y|yes)$'
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
Write-Host '      无言以对 · DEB 一键推送工具' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-Publish -Message '没有找到 git，请先安装 Git for Windows。'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$debDirectory = Join-Path $repoRoot 'debs'

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git') -PathType Container)) {
    Stop-Publish -Message "脚本所在位置不是有效仓库：$repoRoot"
}

Set-Location -LiteralPath $repoRoot

$branch = (& git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
    Stop-Publish -Message "当前分支是 '$branch'，请切换到 main 后再运行。"
}

$alreadyStaged = @(& git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) {
    Stop-Publish -Message '无法检查 Git 暂存区。'
}
if ($alreadyStaged.Count -gt 0) {
    Write-Host '发现运行脚本前就已经暂存的文件：' -ForegroundColor Yellow
    $alreadyStaged | ForEach-Object { Write-Host "  $_" }
    Stop-Publish -Message '为避免误提交，先处理或取消这些暂存内容。'
}

Write-Host '正在同步 GitHub main 分支……' -ForegroundColor Cyan
Invoke-GitChecked -Arguments @('pull', '--ff-only', 'origin', 'main') -FailureMessage '同步远端失败。请检查网络和本地修改，不要使用 reset --hard。'

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    Write-Host ''
    Write-Host '请输入存放插件的本地目录；也可以把文件夹拖进此窗口后按回车。'
    Write-Host "直接按回车则使用仓库目录：$debDirectory" -ForegroundColor DarkGray
    $SourceDirectory = Read-Host '插件目录'
}

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = $debDirectory
}

$SourceDirectory = $SourceDirectory.Trim().Trim('"')
try {
    $SourceDirectory = (Resolve-Path -LiteralPath $SourceDirectory -ErrorAction Stop).Path
}
catch {
    Stop-Publish -Message "目录不存在：$SourceDirectory"
}

if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    Stop-Publish -Message "这不是文件夹：$SourceDirectory"
}

$debFiles = @(Get-ChildItem -LiteralPath $SourceDirectory -File -Filter '*.deb' | Sort-Object Name)
if ($debFiles.Count -eq 0) {
    Stop-Publish -Message "目录中没有找到 .deb：$SourceDirectory"
}

Write-Host ''
Write-Host "找到 $($debFiles.Count) 个 DEB：" -ForegroundColor Green
for ($index = 0; $index -lt $debFiles.Count; $index++) {
    $number = $index + 1
    $size = Get-FriendlySize -Bytes $debFiles[$index].Length
    Write-Host ('[{0,2}] {1}  ({2})' -f $number, $debFiles[$index].Name, $size)
}

Write-Host ''
Write-Host '输入一个或多个编号，例如：1 或 1,3,5；输入 A 选择全部。'
$selectionText = (Read-Host '请选择').Trim()

if ($selectionText -match '^(?i:a|all)$') {
    $selectedIndexes = @(0..($debFiles.Count - 1))
}
else {
    $tokens = @($selectionText -split '[,，\s]+' | Where-Object { $_ })
    if ($tokens.Count -eq 0) {
        Stop-Publish -Message '没有选择任何软件包。' -ExitCode 2
    }

    $selectedIndexes = @()
    foreach ($token in $tokens) {
        $number = 0
        if (-not [int]::TryParse($token, [ref]$number)) {
            Stop-Publish -Message "无效编号：$token"
        }
        if ($number -lt 1 -or $number -gt $debFiles.Count) {
            Stop-Publish -Message "编号超出范围：$number"
        }
        $selectedIndexes += ($number - 1)
    }
    $selectedIndexes = @($selectedIndexes | Sort-Object -Unique)
}

$selectedFiles = @($selectedIndexes | ForEach-Object { $debFiles[$_] })
$relativePaths = @($selectedFiles | ForEach-Object { 'debs/' + $_.Name } | Sort-Object -Unique)
$sectionMapRelativePath = 'config/sections.tsv'
$sectionMapPath = Join-Path $repoRoot 'config/sections.tsv'

if (-not (Test-Path -LiteralPath $sectionMapPath -PathType Leaf)) {
    Stop-Publish -Message "缺少分类配置：$sectionMapPath"
}

$sectionMapStatus = @(& git status --porcelain -- $sectionMapRelativePath)
if ($LASTEXITCODE -ne 0) {
    Stop-Publish -Message '无法检查分类配置的 Git 状态。'
}
if ($sectionMapStatus.Count -gt 0) {
    Stop-Publish -Message 'config/sections.tsv 已有尚未提交的修改，请先处理，避免覆盖分类。'
}

$sectionMapOriginalBytes = [System.IO.File]::ReadAllBytes($sectionMapPath)

function Restore-SectionMapFile {
    [System.IO.File]::WriteAllBytes($sectionMapPath, $sectionMapOriginalBytes)
    & git add -- $sectionMapRelativePath
}

$sectionMap = @{}
foreach ($rawLine in [System.IO.File]::ReadAllLines($sectionMapPath, [System.Text.UTF8Encoding]::new($false))) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) {
        continue
    }

    $parts = @($rawLine -split "`t", 2)
    if ($parts.Count -ne 2) {
        Stop-Publish -Message "分类配置格式错误：$rawLine"
    }
    $sectionMap[$parts[0].Trim().Replace('\', '/')] = $parts[1].Trim()
}

$categoryOptions = @('依赖插件', '美化插件', '功能插件')
$selectedCategories = @{}

Write-Host ''
Write-Host '请为每个软件包选择分类：' -ForegroundColor Cyan
foreach ($relativePath in $relativePaths) {
    Write-Host ''
    Write-Host "软件包：$([System.IO.Path]::GetFileName($relativePath))" -ForegroundColor Green
    for ($categoryIndex = 0; $categoryIndex -lt $categoryOptions.Count; $categoryIndex++) {
        Write-Host "  $($categoryIndex + 1). $($categoryOptions[$categoryIndex])"
    }

    $currentCategory = $sectionMap[$relativePath]
    if ($currentCategory -in $categoryOptions) {
        Write-Host "当前分类：$currentCategory（直接回车保持不变）" -ForegroundColor DarkGray
    }

    while ($true) {
        $categoryChoice = (Read-Host '分类编号').Trim()
        if (-not $categoryChoice -and $currentCategory -in $categoryOptions) {
            $selectedCategories[$relativePath] = $currentCategory
            break
        }

        $categoryNumber = 0
        if ([int]::TryParse($categoryChoice, [ref]$categoryNumber) -and
            $categoryNumber -ge 1 -and $categoryNumber -le $categoryOptions.Count) {
            $selectedCategories[$relativePath] = $categoryOptions[$categoryNumber - 1]
            break
        }

        Write-Host '请输入 1、2 或 3。' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '本次选择：' -ForegroundColor Cyan
foreach ($relativePath in $relativePaths) {
    Write-Host "  [$($selectedCategories[$relativePath])] $([System.IO.Path]::GetFileName($relativePath))"
}

foreach ($file in $selectedFiles) {
    if ($file.Length -ge 100MB) {
        Stop-Publish -Message "$($file.Name) 达到或超过 100 MB，GitHub 普通仓库无法直接接收。"
    }
    if ($file.Length -ge 50MB) {
        Write-Host "警告：$($file.Name) 超过 50 MB，GitHub 会给出大文件警告。" -ForegroundColor Yellow
        if (-not (Read-Yes -Prompt '仍要继续')) {
            Stop-Publish -Message '用户取消。' -ExitCode 2
        }
    }
}

if (-not (Read-Yes -Prompt '确认只处理以上软件包')) {
    Stop-Publish -Message '用户取消。' -ExitCode 2
}

foreach ($sourceFile in $selectedFiles) {
    $destinationPath = Join-Path $debDirectory $sourceFile.Name
    $sourceFullPath = [System.IO.Path]::GetFullPath($sourceFile.FullName)
    $destinationFullPath = [System.IO.Path]::GetFullPath($destinationPath)
    $samePath = [System.StringComparer]::OrdinalIgnoreCase.Equals($sourceFullPath, $destinationFullPath)

    if (-not $samePath -and (Test-Path -LiteralPath $destinationFullPath -PathType Leaf)) {
        $sourceHash = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destinationFullPath -Algorithm SHA256).Hash

        if ($sourceHash -eq $destinationHash) {
            Write-Host "已存在相同文件，跳过复制：$($sourceFile.Name)" -ForegroundColor DarkGray
        }
        else {
            Write-Host ''
            Write-Host "仓库中已有同名但内容不同的文件：$($sourceFile.Name)" -ForegroundColor Yellow
            Write-Host '建议先提高包内 Version，并修改文件名，不要覆盖已发布的同版本包。' -ForegroundColor Yellow
            $overwrite = (Read-Host '如确实要覆盖，请完整输入 OVERWRITE；其他内容取消').Trim()
            if ($overwrite -cne 'OVERWRITE') {
                Stop-Publish -Message '没有覆盖同名文件。' -ExitCode 2
            }
            Copy-Item -LiteralPath $sourceFullPath -Destination $destinationFullPath -Force
        }
    }
    elseif (-not $samePath) {
        Copy-Item -LiteralPath $sourceFullPath -Destination $destinationFullPath
    }
}

foreach ($relativePath in $relativePaths) {
    $sectionMap[$relativePath] = $selectedCategories[$relativePath]
}

$sectionMapLines = @('# Filename<TAB>Section')
foreach ($filename in @($sectionMap.Keys | Sort-Object)) {
    $sectionMapLines += "$filename`t$($sectionMap[$filename])"
}
[System.IO.File]::WriteAllText(
    $sectionMapPath,
    (($sectionMapLines -join "`n") + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

$pathsToCommit = @(($relativePaths + $sectionMapRelativePath) | Sort-Object -Unique)

& git add -- @pathsToCommit
if ($LASTEXITCODE -ne 0) {
    Restore-SectionMapFile
    Stop-Publish -Message '无法把选中的 DEB 加入暂存区。'
}

$stagedNow = @(& git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) {
    Stop-Publish -Message '无法读取暂存结果。'
}

$unexpected = @($stagedNow | Where-Object { $_ -notin $pathsToCommit })
if ($unexpected.Count -gt 0) {
    & git restore --staged -- @pathsToCommit
    Restore-SectionMapFile
    Write-Host '检测到意外的暂存文件：' -ForegroundColor Yellow
    $unexpected | ForEach-Object { Write-Host "  $_" }
    Stop-Publish -Message '已取消本工具加入的暂存内容，没有创建提交。'
}

if ($stagedNow.Count -eq 0) {
    Restore-SectionMapFile
    Stop-Publish -Message '所选文件与仓库版本相同，没有需要提交的变化。' -ExitCode 2
}

Write-Host ''
Write-Host '即将提交的内容：' -ForegroundColor Cyan
& git diff --cached --stat

$stagedDebs = @($stagedNow | Where-Object { $_ -like 'debs/*.deb' })
$defaultMessage = if ($stagedDebs.Count -eq 0) {
    'Update package categories'
}
elseif ($selectedFiles.Count -eq 1) {
    "Add $($selectedFiles[0].BaseName)"
}
else {
    "Add $($selectedFiles.Count) RootHide packages"
}

Write-Host ''
$commitMessage = Read-Host "提交说明（直接回车使用：$defaultMessage）"
if ([string]::IsNullOrWhiteSpace($commitMessage)) {
    $commitMessage = $defaultMessage
}

if (-not (Read-Yes -Prompt "确认提交并推送到 main，说明为：$commitMessage")) {
    & git restore --staged -- @pathsToCommit
    Restore-SectionMapFile
    Write-Host '已取消暂存，复制到 debs 的文件仍保留在本地。' -ForegroundColor Yellow
    Stop-Publish -Message '用户取消。' -ExitCode 2
}

& git commit -m $commitMessage -- @pathsToCommit
if ($LASTEXITCODE -ne 0) {
    Stop-Publish -Message '创建 Git 提交失败。文件仍在本地，请检查上方错误。'
}

$commitSha = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    Stop-Publish -Message '无法取得新提交编号。'
}

Write-Host ''
Write-Host '正在推送到 GitHub……' -ForegroundColor Cyan
& git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "本地提交已经创建：$commitSha" -ForegroundColor Yellow
    Stop-Publish -Message '推送失败。网络恢复后可在仓库目录执行 git push origin main。'
}

Write-Host ''
Write-Host "推送成功：$commitSha" -ForegroundColor Green

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
            # GitHub CLI 偶尔会在任务刚创建时返回空内容，继续等待即可。
        }
    }
    Start-Sleep -Seconds 3
}

if (-not $run) {
    Write-Host '暂时没有查询到对应的 Actions 任务。提交和推送已经成功。' -ForegroundColor Yellow
    Write-Host "请稍后打开：$actionsPage"
    if (Read-Yes -Prompt '现在用浏览器打开 Actions 页面') {
        Start-Process $actionsPage
    }
    exit 0
}

Write-Host "Actions：$($run.url)" -ForegroundColor Cyan
Write-Host '正在等待构建和部署完成，请不要关闭窗口……' -ForegroundColor Cyan
& gh run watch $run.databaseId --exit-status
$actionExit = $LASTEXITCODE

if ($actionExit -ne 0) {
    Write-Host ''
    Write-Host 'GitHub Actions 构建失败，软件源尚未成功更新。' -ForegroundColor Red
    Write-Host "查看错误：$($run.url)"
    if (Read-Yes -Prompt '现在用浏览器打开失败任务') {
        Start-Process $run.url
    }
    exit 3
}

Write-Host ''
Write-Host 'GitHub Actions 构建和部署成功！' -ForegroundColor Green
Write-Host '手机上刷新“无言以对”软件源即可。' -ForegroundColor Green
Write-Host "任务地址：$($run.url)"

if (Read-Yes -Prompt '是否打开成功的 Actions 页面') {
    Start-Process $run.url
}

exit 0
