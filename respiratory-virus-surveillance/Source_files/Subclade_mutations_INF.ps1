param(
  [string[]]$Repos = @(
    "influenza-clade-nomenclature/seasonal_A-H1N1pdm_HA",
    "influenza-clade-nomenclature/seasonal_A-H3N2_HA",
    "influenza-clade-nomenclature/seasonal_B-Vic_HA"
  ),
  [string]$OutCsv = "Results/Subclade_mutations_INF.csv"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic

function Parse-SubcladeYaml {
  param([string]$Text)

  $name = ""
  $parent = ""
  $mutations = @()
  $inDef = $false
  $current = @{}

  foreach ($line in ($Text -split "`n")) {
    $l = $line.TrimEnd("`r")

    if ($l -match '^name:\s*(.+)$') { $name = $Matches[1].Trim(); continue }
    if ($l -match '^parent:\s*(.*)$') { $parent = $Matches[1].Trim(); continue }
    if ($l -match '^defining_mutations:\s*$') { $inDef = $true; continue }
    if (-not $inDef) { continue }

    if ($l -match '^\s*-\s*locus:\s*(\S+)\s*$') {
      if ($current.ContainsKey("locus") -and $current.ContainsKey("position") -and $current.ContainsKey("state")) {
        $mutations += ("{0}:{1}{2}" -f $current.locus, $current.position, $current.state)
      }
      $current = @{ locus = $Matches[1] }
      continue
    }

    if ($l -match '^\s*locus:\s*(\S+)\s*$') { $current.locus = $Matches[1]; continue }
    if ($l -match '^\s*position:\s*(\S+)\s*$') { $current.position = $Matches[1]; continue }
    if ($l -match '^\s*state:\s*(\S+)\s*$') { $current.state = $Matches[1]; continue }

    if ($l -match '^(clade:|unaliased_name:|representatives:|$)') {
      if ($current.ContainsKey("locus") -and $current.ContainsKey("position") -and $current.ContainsKey("state")) {
        $mutations += ("{0}:{1}{2}" -f $current.locus, $current.position, $current.state)
      }
      $current = @{}
      if ($l -match '^clade:') { $inDef = $false }
      continue
    }
  }

  if ($current.ContainsKey("locus") -and $current.ContainsKey("position") -and $current.ContainsKey("state")) {
    $mutations += ("{0}:{1}{2}" -f $current.locus, $current.position, $current.state)
  }

  [pscustomobject]@{
    name = $name
    parent = $parent
    direct = $mutations
  }
}

function Get-CumulativeMutations {
  param(
    [string]$Name,
    [hashtable]$Nodes,
    [System.Collections.Generic.HashSet[string]]$Seen
  )

  if ($Seen.Contains($Name)) { return @() }
  [void]$Seen.Add($Name)
  if (-not $Nodes.ContainsKey($Name)) { return @() }

  $node = $Nodes[$Name]
  $anc = @()
  if ($node.parent) {
    $anc = Get-CumulativeMutations -Name $node.parent -Nodes $Nodes -Seen $Seen
  }

  $all = @($anc + $node.direct)
  $out = New-Object System.Collections.Generic.List[string]
  $uniq = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in $all) {
    if ($uniq.Add($m)) { [void]$out.Add($m) }
  }
  return ,$out.ToArray()
}

function Get-SubtypeMeta {
  param([string]$RepoName)

  switch -Regex ($RepoName) {
    "seasonal_A-H1N1pdm_HA$" { return @{ flu_type = "A"; ngs = "A/H1N1" } }
    "seasonal_A-H3N2_HA$"    { return @{ flu_type = "A"; ngs = "A/H3N2" } }
    "seasonal_B-Vic_HA$"     { return @{ flu_type = "B"; ngs = "B/Victoria" } }
    default                    { return @{ flu_type = ""; ngs = "" } }
  }
}

$outDir = Split-Path -Parent $OutCsv
if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = "." }
if (-not (Test-Path $outDir)) { [void](New-Item -ItemType Directory -Path $outDir -Force) }
$versionDir = Join-Path $outDir "Subclade_mutations_INF_versions"
if (-not (Test-Path $versionDir)) { [void](New-Item -ItemType Directory -Path $versionDir -Force) }

$headers = @{ "User-Agent" = "Subclade_mutations_INF" }
$rows = @()

foreach ($Repo in $Repos) {
  $meta = Get-SubtypeMeta -RepoName $Repo
  if ([string]::IsNullOrWhiteSpace($meta.ngs)) { continue }

  $subUri = "https://api.github.com/repos/$Repo/contents/subclades"
  $subList = Invoke-RestMethod -Uri $subUri -Headers $headers
  $subFiles = $subList | Where-Object { $_.name -like "*.yml" -and $_.download_url }

  $nodes = @{}
  foreach ($f in $subFiles) {
    $txt = [string](Invoke-RestMethod -Uri $f.download_url -Headers $headers)
    $obj = Parse-SubcladeYaml -Text $txt
    if (-not $obj.name) { continue }
    $nodes[$obj.name] = [pscustomobject]@{
      name = $obj.name
      parent = $obj.parent
      direct = $obj.direct
    }
  }

  foreach ($k in ($nodes.Keys | Sort-Object)) {
    $seen = New-Object "System.Collections.Generic.HashSet[string]"
    $cum = Get-CumulativeMutations -Name $k -Nodes $nodes -Seen $seen
    $rows += [pscustomobject]@{
      flu_type = $meta.flu_type
      ngs_sekvens_resultat = $meta.ngs
      nc_ha_subclade = $k
      ha_cluster_defining_mutations = ($cum -join "; ")
    }
  }
}

if (-not $rows -or $rows.Count -eq 0) {
  throw "No rows were generated for Subclade_mutations_INF.csv"
}

if (Test-Path $OutCsv) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $archived = Join-Path $versionDir ("Subclade_mutations_INF_{0}.csv" -f $stamp)
  Copy-Item $OutCsv $archived -Force
}

$rows | Sort-Object ngs_sekvens_resultat, nc_ha_subclade | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
Write-Output "WROTE: $OutCsv"
Write-Output "ROWS: $($rows.Count)"

$versions = Get-ChildItem $versionDir -File -Filter "Subclade_mutations_INF_*.csv" | Sort-Object LastWriteTime -Descending
if ($versions.Count -gt 3) {
  $toRecycle = $versions | Select-Object -Skip 3
  foreach ($f in $toRecycle) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
      $f.FullName,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
  }
}
