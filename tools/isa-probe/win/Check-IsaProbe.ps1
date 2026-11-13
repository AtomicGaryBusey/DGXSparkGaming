<#
Check-IsaProbe.ps1 — run the isa-probe PE suite on Windows (Prism) and grade it
against the Intel SDM, exactly as tools/isa-probe.sh grades FEX and Box64.

WHY THIS EXISTS
  On Windows on Arm the x86 translator is Microsoft's Prism, and Prism has
  per-executable emulation settings (Properties -> Compatibility -> Windows on
  Arm -> Change emulation settings). Microsoft documents that x87 is a 64-bit
  approximation by default ("Disable floating point optimization" restores
  80-bit), and NVIDIA's RTX Spark porting guide warns emulated x87 may lack
  "correct status flags". id Tech 4 dies on exactly a status-flag question (the
  tag word). This script answers it in seconds, with no game installed.

  It needs nothing but the PowerShell that ships with Windows: no Python, no
  install. Records are parsed here byte for byte, the same 8-byte
  [4 ASCII tag][uint32 LE] format the Linux runner reads.

HOW TO A/B PRISM SETTINGS
  Settings are stored per executable, so the kit ships each probe once and you make
  copies:   .\Check-IsaProbe.ps1 -MakeVariant fp80
  creates   x87top.32-fp80.exe etc. Apply the setting to those copies by hand in
  Properties, then:   .\Check-IsaProbe.ps1 -Variant fp80
  Results append to results.tsv with the variant label, so Default and fp80 sit
  side by side. A failure at Default that disappears at fp80 is the finding.
  Change ONE setting per variant -- a win with three set at once teaches nothing.

USAGE
  .\Check-IsaProbe.ps1                    # run every probe as shipped (Default)
  .\Check-IsaProbe.ps1 -Filter x87        # only probes whose name matches
  .\Check-IsaProbe.ps1 -MakeVariant fp80  # copy probes to *-fp80.exe, then exit
  .\Check-IsaProbe.ps1 -Variant fp80      # run the *-fp80.exe copies
  If scripts are blocked:  powershell -ExecutionPolicy Bypass -File .\Check-IsaProbe.ps1

EXIT  0 = every probe matches the SDM   1 = at least one mismatch
      2 = a probe failed to run, or nothing ran at all (never a silent pass)
TESTED 2026-11-12 under PowerShell 7.6 on Linux, with each probe stood in for by a
script that replays real probe bytes: pass, mismatch (Box64's real x87top answers),
no-output, missing-variant and zero-run paths. Not yet run on Windows itself.
#>
param(
  [string]$Filter = "",
  [string]$Variant = "",
  [string]$MakeVariant = ""
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$probes = Get-ChildItem -Path $here -Filter "*.32.exe" | Where-Object { $_.BaseName -notmatch '-' }

if ($MakeVariant) {
  foreach ($p in $probes) {
    $dst = Join-Path $here ("{0}-{1}.exe" -f $p.BaseName, $MakeVariant)
    Copy-Item $p.FullName $dst -Force
    Write-Host "made $dst"
  }
  Write-Host "Now set ONE Prism emulation setting on each *-$MakeVariant.exe, then run -Variant $MakeVariant"
  exit 0
}

function Read-Records([byte[]]$d) {
  $out = @{}
  if ($null -eq $d -or $d.Length -eq 0 -or ($d.Length % 8) -ne 0) { return $null }
  for ($i = 0; $i -lt $d.Length; $i += 8) {
    $tag = [System.Text.Encoding]::ASCII.GetString($d, $i, 4).Trim()
    $out[$tag] = [System.BitConverter]::ToUInt32($d, $i + 4)
  }
  return $out
}

# Record the conditions, because on RTX Spark they are variables, not constants.
$arch = $env:PROCESSOR_ARCHITECTURE
# Name what actually executed the probe. On an ARM64 Windows host an x86 probe runs
# under Prism; on an x64 PC it runs on real silicon, which is a useful CONTROL and
# must never be written up as Prism.
$who = switch ($arch) { "ARM64" { "Prism" } "AMD64" { "native" } "x86" { "native" } default { "got" } }
# Fail soft: a missing host description must never stop the grading. (CIM does
# not exist in PowerShell on Linux, which is where this script was first tested.)
$osBuild = "unknown"
try {
  $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
  $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
  $osBuild = $os.BuildNumber
  Write-Host ("host: {0} / {1} / {2} build {3} / native arch {4}" -f $cs.Manufacturer, $cs.SystemFamily, $os.Caption, $osBuild, $arch)
} catch {
  Write-Host ("host: (no CIM: {0}) / {1}" -f [System.Runtime.InteropServices.RuntimeInformation]::OSDescription, $arch)
}
$label = if ($Variant) { $Variant } else { "default" }
Write-Host "variant: $label"
Write-Host ""

$tsv = Join-Path $here "results.tsv"
if (-not (Test-Path $tsv)) { "time`tvariant`truntime`tbuild`tprobe`ttag`texpect`tgot`tverdict" | Out-File $tsv -Encoding ascii }
$stamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")

$bad = 0; $broken = 0; $ran = 0
foreach ($p in $probes) {
  $base = $p.BaseName
  if ($Filter -and ($base -notlike "*$Filter*")) { continue }
  $exe = if ($Variant) { Join-Path $here "$base-$Variant.exe" } else { $p.FullName }
  $exp = Join-Path $here "$base.expect"
  if (-not (Test-Path $exp)) { Write-Host "skip $base - no .expect"; continue }
  if (-not (Test-Path $exe)) { Write-Host "skip $base - $exe missing (run -MakeVariant $Variant first)"; continue }

  Write-Host "== $base =="
  # Capture raw stdout bytes: PowerShell's own pipeline would decode them as text.
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $ms = New-Object System.IO.MemoryStream
  $proc.StandardOutput.BaseStream.CopyTo($ms)
  $proc.WaitForExit()
  $rec = Read-Records $ms.ToArray()
  $ran++
  if ($null -eq $rec) {
    Write-Host ("  NO OUTPUT (exit code 0x{0:x8}, {1} bytes)" -f $proc.ExitCode, $ms.Length)
    $broken++; continue
  }

  $pbad = 0
  foreach ($line in Get-Content $exp) {
    $l = ($line -split '#')[0].Trim()
    if (-not $l) { continue }
    $parts = $l -split '\s+'
    if ($parts.Count -ne 2) { continue }
    $tag = $parts[0]; $spec = $parts[1]
    if (-not $rec.ContainsKey($tag)) { $got = "----"; $verdict = "missing" }
    else {
      $v = [uint32]$rec[$tag]; $got = "0x{0:x4}" -f $v
      if ($spec -eq '*') { $verdict = "info" }
      elseif ($spec -eq '!0') { $verdict = if ($v -ne 0) { "ok" } else { "MISMATCH" } }
      else { $verdict = if ($v -eq [Convert]::ToUInt32($spec, 16)) { "ok" } else { "MISMATCH" } }
    }
    if ($verdict -eq "MISMATCH" -or $verdict -eq "missing") { $pbad++ }
    $mark = if ($verdict -eq "ok" -or $verdict -eq "info") { "" } else { "  <-- $verdict" }
    Write-Host ("  {0,-6} expect {1,-8} {2}={3}{4}" -f $tag, $spec, $who, $got, $mark)
    "$stamp`t$label`t$who`t$osBuild`t$base`t$tag`t$spec`t$got`t$verdict" | Out-File $tsv -Append -Encoding ascii
  }
  if ($pbad) { $bad++ ; Write-Host "  -> $pbad mismatch(es)" } else { Write-Host "  -> all match" }
  Write-Host ""
}

Write-Host "=================================================================="
Write-Host "probes run: $ran   with mismatches: $bad   failed to run: $broken   (log: $tsv)"
Write-Host "Before calling a mismatch a Prism bug: cpuid.32 checks what Prism ADVERTISES,"
Write-Host "which is a policy choice (DE/PSE are implied by SSE2 on real parts, not mandated"
Write-Host "for an emulator). The x87 and a3store probes have one right answer."
# Zero probes run is "nothing to conclude", never a pass (the repo's signature-check rule).
if ($ran -eq 0) { Write-Host "NOTHING RAN - no verdict. Check -Filter / -Variant."; exit 2 }
if ($broken) { exit 2 }
if ($bad) { exit 1 }
exit 0
