I’ll create a PowerShell script that queries Entra ID sign-in logs for users from your CSV file, processes them in batches, and identifies shared vs unique devices.​​​​​​​​​​​​​​​​

I’ve created a comprehensive PowerShell script that will analyze Entra ID sign-in logs to identify shared vs unique devices among your users. Here are the key features:

## Script Features:

**Parameters:**

- `CsvFilePath`: Path to your CSV file (required)
- `BatchSize`: Number of users to process at once (default: 20)
- `DaysBack`: How many days back to query (default: 7)
- `OutputPath`: Where to save results (auto-generates timestamped filename)

**Key Functionality:**

1. **Batch Processing**: Processes users in configurable batches to avoid API throttling
1. **Device Analysis**: Extracts device information including DeviceId, DeviceName, OS, Browser, etc.
1. **Shared vs Unique Classification**: Automatically categorizes devices based on how many users sign in from them
1. **Comprehensive Output**: Exports detailed CSV with device usage patterns

## Usage Example:

```powershell
.\EntraSignInAnalysis.ps1 -CsvFilePath "C:\temp\users.csv" -BatchSize 15 -DaysBack 14
```

## Prerequisites:

1. Install Microsoft Graph PowerShell modules:
   
   ```powershell
   Install-Module Microsoft.Graph.Authentication
   Install-Module Microsoft.Graph.Reports
   ```
1. Required permissions: `AuditLog.Read.All` and `Directory.Read.All`

## Output:

The script generates a CSV file with columns including:

- DeviceId/DeviceName
- Operating System and Browser
- UserCount (how many different users)
- DeviceType (Shared/Unique)
- List of users who signed in
- Sign-in statistics

The script also provides real-time progress updates and a summary showing total devices, shared devices, and the top 10 most shared devices.

This will help you quickly identify which devices are being shared among multiple users versus those that are unique to individual users.​​​​​​​​​​​​​​​​