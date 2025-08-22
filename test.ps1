# Entra ID Sign-in Device Analysis Script

# Queries sign-in logs for users from CSV and identifies shared vs unique devices

param(
[Parameter(Mandatory=$true)]
[string]$CsvFilePath,

```
[Parameter(Mandatory=$false)]
[int]$BatchSize = 20,

[Parameter(Mandatory=$false)]
[int]$DaysBack = 7,

[Parameter(Mandatory=$false)]
[string]$OutputPath = "DeviceAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
```

)

# Import required modules

try {
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Reports -ErrorAction Stop
Write-Host “Microsoft Graph modules imported successfully” -ForegroundColor Green
} catch {
Write-Error “Failed to import Microsoft Graph modules. Please install them using: Install-Module Microsoft.Graph”
exit 1
}

# Function to connect to Microsoft Graph

function Connect-ToGraph {
try {
# Check if already connected
$context = Get-MgContext
if ($context) {
Write-Host “Already connected to Microsoft Graph as $($context.Account)” -ForegroundColor Green
return
}

```
    # Connect with required scopes
    Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All" -NoWelcome
    Write-Host "Connected to Microsoft Graph successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}
```

}

# Function to get sign-in logs for a batch of users

function Get-SignInLogsForUsers {
param(
[string[]]$UserPrincipalNames,
[datetime]$StartDate
)

```
$allSignIns = @()
$startDateString = $StartDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($upn in $UserPrincipalNames) {
    try {
        Write-Host "Querying sign-ins for user: $upn" -ForegroundColor Yellow
        
        # Query sign-in logs for the specific user
        $filter = "userPrincipalName eq '$upn' and createdDateTime ge $startDateString"
        $signIns = Get-MgAuditLogSignIn -Filter $filter -All
        
        if ($signIns) {
            $allSignIns += $signIns
            Write-Host "  Found $($signIns.Count) sign-ins for $upn" -ForegroundColor Cyan
        } else {
            Write-Host "  No sign-ins found for $upn" -ForegroundColor Gray
        }
        
        # Small delay to avoid throttling
        Start-Sleep -Milliseconds 100
        
    } catch {
        Write-Warning "Error querying sign-ins for $upn : $($_.Exception.Message)"
    }
}

return $allSignIns
```

}

# Function to process sign-in data and extract device information

function Process-SignInData {
param($SignInLogs, $UserData)

```
$deviceUserMap = @{}
$processedData = @()

foreach ($signIn in $SignInLogs) {
    $deviceId = $signIn.DeviceDetail.DeviceId
    $deviceName = $signIn.DeviceDetail.DisplayName
    $userPrincipalName = $signIn.UserPrincipalName
    $operatingSystem = $signIn.DeviceDetail.OperatingSystem
    $browser = $signIn.DeviceDetail.Browser
    $isCompliant = $signIn.DeviceDetail.IsCompliant
    $trustType = $signIn.DeviceDetail.TrustType
    
    # Skip if no device information available
    if ([string]::IsNullOrEmpty($deviceId) -and [string]::IsNullOrEmpty($deviceName)) {
        continue
    }
    
    # Use deviceId as primary key, fallback to deviceName if deviceId is null
    $deviceKey = if (![string]::IsNullOrEmpty($deviceId)) { $deviceId } else { $deviceName }
    
    if (-not $deviceUserMap.ContainsKey($deviceKey)) {
        $deviceUserMap[$deviceKey] = @{
            DeviceId = $deviceId
            DeviceName = $deviceName
            OperatingSystem = $operatingSystem
            Browser = $browser
            IsCompliant = $isCompliant
            TrustType = $trustType
            Users = @()
            UserPrincipalNames = @()
            SignInDates = @()
        }
    }
    
    # Add user to device mapping if not already present
    if ($userPrincipalName -notin $deviceUserMap[$deviceKey].UserPrincipalNames) {
        $deviceUserMap[$deviceKey].Users += $userPrincipalName
        $deviceUserMap[$deviceKey].UserPrincipalNames += $userPrincipalName
    }
    
    # Add sign-in date
    $deviceUserMap[$deviceKey].SignInDates += $signIn.CreatedDateTime
}

# Process the device data and categorize as shared or unique
foreach ($deviceKey in $deviceUserMap.Keys) {
    $device = $deviceUserMap[$deviceKey]
    $uniqueUsers = $device.UserPrincipalNames | Select-Object -Unique
    $userCount = $uniqueUsers.Count
    
    $deviceInfo = [PSCustomObject]@{
        DeviceId = $device.DeviceId
        DeviceName = $device.DeviceName
        OperatingSystem = $device.OperatingSystem
        Browser = $device.Browser
        IsCompliant = $device.IsCompliant
        TrustType = $device.TrustType
        UserCount = $userCount
        DeviceType = if ($userCount -gt 1) { "Shared" } else { "Unique" }
        Users = ($uniqueUsers -join "; ")
        FirstSignIn = ($device.SignInDates | Sort-Object | Select-Object -First 1)
        LastSignIn = ($device.SignInDates | Sort-Object | Select-Object -Last 1)
        TotalSignIns = $device.SignInDates.Count
    }
    
    $processedData += $deviceInfo
}

return $processedData
```

}

# Main execution

Write-Host “Starting Entra ID Sign-in Device Analysis” -ForegroundColor Green
Write-Host “=======================================” -ForegroundColor Green

# Validate CSV file

if (-not (Test-Path $CsvFilePath)) {
Write-Error “CSV file not found: $CsvFilePath”
exit 1
}

# Import user data from CSV

try {
$userData = Import-Csv $CsvFilePath
Write-Host “Imported $($userData.Count) users from CSV file” -ForegroundColor Green

```
# Validate required columns
$requiredColumns = @('UserPrincipalName', 'ObjectId', 'DisplayName')
$csvColumns = $userData[0].PSObject.Properties.Name

foreach ($column in $requiredColumns) {
    if ($column -notin $csvColumns) {
        Write-Error "Required column '$column' not found in CSV file"
        exit 1
    }
}
```

} catch {
Write-Error “Failed to import CSV file: $($_.Exception.Message)”
exit 1
}

# Connect to Microsoft Graph

Connect-ToGraph

# Calculate date range

$startDate = (Get-Date).AddDays(-$DaysBack)
Write-Host “Querying sign-ins from $($startDate.ToString(‘yyyy-MM-dd’)) to $(Get-Date -Format ‘yyyy-MM-dd’)” -ForegroundColor Green

# Process users in batches

$allSignInData = @()
$totalUsers = $userData.Count
$currentBatch = 0

for ($i = 0; $i -lt $totalUsers; $i += $BatchSize) {
$currentBatch++
$endIndex = [Math]::Min($i + $BatchSize - 1, $totalUsers - 1)
$batchUsers = $userData[$i..$endIndex].UserPrincipalName

```
Write-Host "`nProcessing batch $currentBatch (Users $($i+1) to $($endIndex+1) of $totalUsers)" -ForegroundColor Magenta

# Get sign-in logs for this batch
$batchSignIns = Get-SignInLogsForUsers -UserPrincipalNames $batchUsers -StartDate $startDate
$allSignInData += $batchSignIns

Write-Host "Batch $currentBatch complete. Found $($batchSignIns.Count) sign-ins" -ForegroundColor Green

# Add delay between batches to avoid throttling
if ($i + $BatchSize -lt $totalUsers) {
    Write-Host "Waiting 2 seconds before next batch..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
}
```

}

Write-Host “`nProcessing sign-in data to identify device usage…” -ForegroundColor Yellow

# Process all sign-in data to identify shared vs unique devices

$deviceAnalysis = Process-SignInData -SignInLogs $allSignInData -UserData $userData

# Generate summary statistics

$totalDevices = $deviceAnalysis.Count
$sharedDevices = ($deviceAnalysis | Where-Object { $*.DeviceType -eq “Shared” }).Count
$uniqueDevices = ($deviceAnalysis | Where-Object { $*.DeviceType -eq “Unique” }).Count

Write-Host “`nAnalysis Complete!” -ForegroundColor Green
Write-Host “==================” -ForegroundColor Green
Write-Host “Total sign-ins analyzed: $($allSignInData.Count)”
Write-Host “Total devices found: $totalDevices”
Write-Host “Shared devices: $sharedDevices”
Write-Host “Unique devices: $uniqueDevices”

# Export results to CSV

$deviceAnalysis | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host “`nResults exported to: $OutputPath” -ForegroundColor Green

# Display top shared devices

$topSharedDevices = $deviceAnalysis | Where-Object { $_.DeviceType -eq “Shared” } | Sort-Object UserCount -Descending | Select-Object -First 10

if ($topSharedDevices) {
Write-Host “`nTop 10 Most Shared Devices:” -ForegroundColor Cyan
Write-Host “============================” -ForegroundColor Cyan
$topSharedDevices | Format-Table DeviceName, UserCount, Users -AutoSize
}

Write-Host “`nScript execution completed successfully!” -ForegroundColor Green