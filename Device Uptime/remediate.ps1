# Check if BurntToast is installed
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Output "BurntToast module is missing. Attempting to install..."
    
    try {
        Install-Module -Name BurntToast -Force -Scope CurrentUser -ErrorAction Stop
        Write-Output "BurntToast module installed successfully."
    } catch {
        Write-Output "Failed to install BurntToast. Exiting."
        Exit 1
    }
} else {
    Write-Output "BurntToast module is already installed."
}

# Import the BurntToast module
Import-Module BurntToast -Force

# Get Uptime
$Uptime = (Get-ComputerInfo).OSUptime
$UptimeDays = $Uptime.Days

# Define the Notification Content
$Title = "🔔 Restart Required"
$Subtitle = "Your device has been running for $UptimeDays days."
$Message = "Restart for better performance and security."

# Define Images (Optional)
$AppLogo = "https://cdn1.iconfinder.com/data/icons/basic-ui-elements-color-round/3/47-512.png"

# Define Actions
$RestartAction = New-BTButton -Content "Restart Now" -Arguments "shutdown.exe /r /t 0"
$RemindAction = New-BTButton -Content "Remind Me Later" -Dismiss

# Create and Display the Notification
New-BurntToastNotification -Text $Title, $Subtitle, $Message `
    -AppLogo $AppLogo `
    -Button $RestartAction, $RemindAction `
    -UniqueIdentifier "IT-Helpdesk-Restart-Reminder" # This keeps it in the Action Center

Write-Output "Notification displayed successfully."
