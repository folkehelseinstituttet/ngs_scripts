param(
  [string[]]$Repos = @(
    "influenza-clade-nomenclature/seasonal_A-H1N1pdm_HA",
    "influenza-clade-nomenclature/seasonal_A-H3N2_HA",
    "influenza-clade-nomenclature/seasonal_B-Vic_HA"
  ),
  [string]$OutDir = "Results"
)

$ErrorActionPreference = "Stop"

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

function Get-LineageTag {
  param([string]$RepoName)
  switch -Regex ($RepoName) {
    "seasonal_A-H1N1pdm_HA$" { return "H1N1pdm_HA" }
    "seasonal_A-H3N2_HA$" { return "H3N2_HA" }
    "seasonal_B-Vic_HA$" { return "B_Victoria_HA" }
    default { return ($RepoName -replace "[^A-Za-z0-9]+", "_") }
  }
}

function Export-CsvSafe {
  param(
    [Parameter(Mandatory = $true)] $InputObject,
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    $InputObject | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    return $Path
  } catch {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $alt = [System.IO.Path]::Combine(
      [System.IO.Path]::GetDirectoryName($Path),
      ([System.IO.Path]::GetFileNameWithoutExtension($Path) + "_" + $stamp + [System.IO.Path]::GetExtension($Path))
    )
    $InputObject | Export-Csv -Path $alt -NoTypeInformation -Encoding UTF8
    return $alt
  }
}

if (-not (Test-Path $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir) }

$headers = @{ "User-Agent" = "influenza-signature-script" }

foreach ($Repo in $Repos) {
  $subUri = "https://api.github.com/repos/$Repo/contents/subclades"
  $subList = Invoke-RestMethod -Uri $subUri -Headers $headers
  $subFiles = $subList | Where-Object { $_.name -like "*.yml" -and $_.download_url }

  $nodes = @{}
  foreach ($f in $subFiles) {
    $txt = [string](Invoke-RestMethod -Uri $f.download_url -Headers $headers)
    $obj = Parse-SubcladeYaml -Text $txt
    if (-not $obj.name) { throw "Failed parsing subclade name in $($f.name) for $Repo" }
    $nodes[$obj.name] = [pscustomobject]@{
      name = $obj.name
      parent = $obj.parent
      direct = $obj.direct
    }
  }

  $rows = @()
  $longRows = @()
  foreach ($k in ($nodes.Keys | Sort-Object)) {
    $seen = New-Object "System.Collections.Generic.HashSet[string]"
    $cum = Get-CumulativeMutations -Name $k -Nodes $nodes -Seen $seen

    $path = @()
    $cur = $k
    $guard = 0
    while ($cur -and $nodes.ContainsKey($cur) -and $guard -lt 100) {
      $path += $cur
      $cur = $nodes[$cur].parent
      $guard++
    }
    if ($cur) { $path += $cur }
    [array]::Reverse($path)

    $rows += [pscustomobject]@{
      subclade = $k
      parent = $nodes[$k].parent
      ancestor_path = ($path -join " > ")
      direct_signature_mutations = ($nodes[$k].direct -join "; ")
      cumulative_signature_mutations = ($cum -join "; ")
      n_direct = $nodes[$k].direct.Count
      n_cumulative = $cum.Count
    }

    foreach ($m in $cum) {
      $origin = if ($nodes[$k].direct -contains $m) { "direct" } else { "ancestor" }
      $longRows += [pscustomobject]@{
        subclade = $k
        mutation = $m
        origin = $origin
      }
    }
  }

  $tag = Get-LineageTag -RepoName $Repo
  $outWide = Join-Path $OutDir "${tag}_subclade_signature_mutations_with_ancestors.csv"
  $outLong = Join-Path $OutDir "${tag}_subclade_signature_mutations_with_ancestors_long.csv"

  $writtenWide = Export-CsvSafe -InputObject $rows -Path $outWide
  $writtenLong = Export-CsvSafe -InputObject ($longRows | Sort-Object subclade, mutation) -Path $outLong

  Write-Output "REPO: $Repo"
  Write-Output "WROTE: $writtenWide"
  Write-Output "WROTE: $writtenLong"
  Write-Output ("SUBCLADES: {0}" -f $rows.Count)
  Write-Output ("LONG_ROWS: {0}" -f $longRows.Count)
}
