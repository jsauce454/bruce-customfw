<#
   Bruce‑Firmware upgrade script (Windows PowerShell)

   What it does:
   • Enables PSRAM and expands the QuickJS heap (default: 512 KB)
   • Adds a PSRAM‑based allocator for QuickJS
   • Adds an App‑Launcher (SD‑card /apps → native menu)
   • Adds BLE sniff, NRF24 jam, RGB‑LED and a native Menu object for JavaScript
   • Doubles all FreeRTOS task stacks from 8 KB → 16 KB
   • Increases the FreeRTOS total heap size
   • Re‑builds the firmware
#>

# ---------------------------------------------------------------
# 0️⃣  USER SETTINGS (change only if you know what you are doing)
# ---------------------------------------------------------------
$RepoRoot        = (Get-Location).Path      # run the script from the repo root
$EnvName         = "m5stack-cplus2"         # PlatformIO environment you normally use
$QuickJSHeapKB   = 512                      # QuickJS heap size in kilobytes
$StackSizeBytes  = 16384                    # 16 KB for each task (old value was 8192)
$FreeRTOSHeapKB  = 80                       # total FreeRTOS heap in kilobytes

# ---------------------------------------------------------------
# Helper – write a file only if it does NOT already exist
# ---------------------------------------------------------------
function Write-IfNotExists {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Content
    )
    if (-not (Test-Path $Path)) {
        Write-Host "Creating $Path"
        $Content | Set-Content -Encoding UTF8 -Path $Path
    } else {
        Write-Host "File $Path already exists – skipping"
    }
}

# ---------------------------------------------------------------
# 1️⃣  Enable PSRAM & bump FreeRTOS heap in platformio.ini
# ---------------------------------------------------------------
$IniPath = Join-Path $RepoRoot "platformio.ini"
if (-not (Test-Path $IniPath)) {
    Write-Error "platformio.ini not found – are you inside the Bruce repo?"
    exit 1
}

# PSRAM compiler flags (add them only once)
$psramLines = @"
    -DBOARD_HAS_PSRAM=1
    -DCONFIG_SPIRAM_SUPPORT=1
    -DCONFIG_SPIRAM_TYPE_AUTO=1
    -DCONFIG_SPIRAM_USE_CAPS_ALLOC=1
    -DCONFIG_SPIRAM_IGNORE_NOTFOUND=1
"@
if (-not (Select-String -Path $IniPath -Pattern "BOARD_HAS_PSRAM")) {
    Write-Host "Appending PSRAM compiler flags to platformio.ini"
    Add-Content -Path $IniPath -Value $psramLines
} else {
    Write-Host "PSRAM flags already present"
}

# Bump FreeRTOS total‑heap size (only once)
if (-not (Select-String -Path $IniPath -Pattern "CONFIG_TOTAL_HEAP_SIZE")) {
    $heapLine = "    -D CONFIG_TOTAL_HEAP_SIZE=$($FreeRTOSHeapKB*1024)"
    Write-Host "Setting FreeRTOS total heap to $FreeRTOSHeapKB KB"
    Add-Content -Path $IniPath -Value $heapLine
} else {
    Write-Host "CONFIG_TOTAL_HEAP_SIZE already defined – leaving it"
}

# ---------------------------------------------------------------
# 2️⃣  Modify bjs_interpreter.cpp (or .c) – enlarge heap & add PSRAM allocator
# ---------------------------------------------------------------
$InterpPath = Get-ChildItem -Path $RepoRoot -Recurse -Filter "bjs_interpreter.cpp" -ErrorAction SilentlyContinue |
                Select-Object -First 1 |
                Select-Object -ExpandProperty FullName
if (-not $InterpPath) {
    $InterpPath = Get-ChildItem -Path $RepoRoot -Recurse -Filter "bjs_interpreter.c" -ErrorAction SilentlyContinue |
                    Select-Object -First 1 |
                    Select-Object -ExpandProperty FullName
}
if (-not $InterpPath) {
    Write-Error "Cannot find bjs_interpreter.cpp or .c – aborting."
    exit 1
}
Write-Host "Updating $InterpPath"

# Replace old 64 KB heap constant with our new value
(Get-Content $InterpPath) -replace '(\d+)\*
