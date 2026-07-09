# Requires admin privileges to run.
# Asus ROG Ally XG Mobile RTX 3070 Ti toggle utility.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Constants
$NvidiaVendorID = "VEN_10DE"
$AudioServiceName = "AudioSrv"
$XgMobileDeviceID = "VID_0955&PID_9000"

# Tray Icons
$iconConnected = [System.Drawing.SystemIcons]::Application
$iconDisconnected = [System.Drawing.SystemIcons]::Warning

# Globals
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true

# Functions
function Show-Notification($title, $message, $type="Info") {
    switch($type) {
        "Info" { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info }
        "Warning" { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning }
        "Error" { $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error }
    }
    $notifyIcon.BalloonTipTitle = $title
    $notifyIcon.BalloonTipText = $message
    $notifyIcon.ShowBalloonTip(3000)
}

function Get-XgMobileConnectionStatus {
    try {
        $result = Invoke-CimMethod -InputObject (Get-CimInstance -Namespace root/wmi -ClassName AsusAtkWmi_WMNB) `
            -MethodName DSTS -Arguments @{Device_ID=0x00090019}
        $status = [uint32]$result.ReturnValue
        $isValid = ($status -band 0x00010000) -ne 0
        $isConnected = ($status -band 0x00000001) -ne 0
        if ($isValid) {
            return $isConnected
        }
    } catch {
    }

    $device = Get-PnpDevice -InstanceId "*$XgMobileDeviceID*" -ErrorAction SilentlyContinue
    return $null -ne $device
}

function Get-eGPUDeviceStatus {
    $devices = Get-PnpDevice -Class Display -FriendlyName "*NVIDIA*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "OK" }
    return $null -ne $devices
}

function Get-eGPUStatus {
    if (-not (Get-XgMobileConnectionStatus)) {
        return $false
    }

    return Get-eGPUDeviceStatus
}

function Toggle-eGPU {
    $isEnabled = Get-eGPUStatus
    if ($isEnabled) {
        Disable-eGPU
    } else {
        Enable-eGPU
    }
}

function Enable-eGPU {
    Show-Notification "XG Mobile" "Enabling eGPU..." "Info"
    Invoke-CimMethod -InputObject (Get-CimInstance -Namespace root/wmi -ClassName AsusAtkWmi_WMNB) `
        -MethodName DEVS -Arguments @{Device_ID=0x00090019; Control_status=1} | Out-Null
    Start-Sleep -Seconds 2
    Get-PnpDevice -FriendlyName "*NVIDIA*" | Enable-PnpDevice -Confirm:$false
    Start-Sleep -Seconds 2
    Restart-Service -Name $AudioServiceName -Force
    Restart-Process explorer
    Update-TrayIcon
    Show-Notification "XG Mobile" "eGPU Enabled." "Info"
}

function Disable-eGPU {
    Show-Notification "XG Mobile" "Disabling eGPU..." "Info"
    Invoke-CimMethod -InputObject (Get-CimInstance -Namespace root/wmi -ClassName AsusAtkWmi_WMNB) `
        -MethodName DEVS -Arguments @{Device_ID=0x00090019; Control_status=0} | Out-Null
    Start-Sleep -Seconds 2
    Get-PnpDevice -FriendlyName "*NVIDIA*" | Disable-PnpDevice -Confirm:$false
    Start-Sleep -Seconds 2
    Restart-Service -Name $AudioServiceName -Force
    Restart-Process explorer
    Update-TrayIcon
    Show-Notification "XG Mobile" "eGPU Disabled. Safe to unplug." "Info"
}

function Restart-Process($procName) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process $procName
}

function Update-TrayIcon {
    $isConnected = Get-XgMobileConnectionStatus
    $isEnabled = $false
    if ($isConnected) {
        $isEnabled = Get-eGPUDeviceStatus
    }

    if ($isConnected) {
        $customIconPath = "C:\Program Files\ASUS\ARMOURY CRATE SE Service\GPUSwitchPlugin\AC.png"
        
        # Convert PNG to Icon at runtime
        if (Test-Path $customIconPath) {
            $bitmap = [System.Drawing.Bitmap]::FromFile($customIconPath)
            $iconHandle = $bitmap.GetHicon()
            $icon = [System.Drawing.Icon]::FromHandle($iconHandle)
            $notifyIcon.Icon = $icon
        } else {
            $notifyIcon.Icon = $iconConnected
        }

        if ($isEnabled) {
            $notifyIcon.Text = "XG Mobile eGPU Connected"
        } else {
            $notifyIcon.Text = "XG Mobile eGPU Connected (GPU Disabled)"
        }
        $menuEnable.Enabled = -not $isEnabled
        $menuDisable.Enabled = $isEnabled
    } else {
        $notifyIcon.Icon = $iconDisconnected
        $notifyIcon.Text = "XG Mobile eGPU Disconnected"
        $menuEnable.Enabled = $false
        $menuDisable.Enabled = $false
    }
}

# Setup Tray Menu
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuEnable = $contextMenu.Items.Add("Enable eGPU")
$menuDisable = $contextMenu.Items.Add("Disable eGPU")
$menuExit = $contextMenu.Items.Add("Exit")

$menuEnable.Add_Click({ Enable-eGPU })
$menuDisable.Add_Click({ Disable-eGPU })
$menuExit.Add_Click({
    $notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$notifyIcon.ContextMenuStrip = $contextMenu
Update-TrayIcon
Show-Notification "XG Mobile" "Utility ready." "Info"

# Run
$form = New-Object System.Windows.Forms.Form
$form.WindowState = "Minimized"
$form.ShowInTaskbar = $false
$form.add_Load({ $form.Hide() })
[System.Windows.Forms.Application]::Run($form)
