Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Define and import the user32.dll functions to hide/show the console window
Add-Type @"
    using System;
    using System.Runtime.InteropServices;

    public class User32 {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        public const int SW_HIDE = 0;
        public const int SW_SHOW = 5;
    }
"@

# Hide the PowerShell console window initially
$consolePtr = [User32]::GetConsoleWindow()
[User32]::ShowWindow($consolePtr, [User32]::SW_HIDE)

# Function to check and request admin privileges
function Check-AdminPrivileges {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Check-AdminPrivileges

# Define the Minecraft worlds directory dynamically
$worldsDir = "$env:LOCALAPPDATA\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe\LocalState\games\com.mojang\minecraftWorlds"
$backupDirPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "MinecraftWorldBackupPath.txt"

# Function to read the backup directory from a file
function Get-BackupDirectory {
    if (Test-Path $backupDirPath) {
        return Get-Content $backupDirPath -Raw
    } else {
        return $null
    }
}

# Function to set or modify the backup directory
function Set-BackupDirectory {
    $backupDir = [System.Windows.Forms.FolderBrowserDialog]::new()
    if ($backupDir.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $backupDirPath | Out-File -FilePath $backupDirPath
        [System.Windows.Forms.MessageBox]::Show("Backup directory set to: $($backupDir.SelectedPath)", "Backup Directory Set", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

# Global variable to hold the form and flow panel
$global:worldsForm = $null
$global:flowPanel = $null

# Function to refresh the list of worlds
function Refresh-Worlds {
    $global:flowPanel.Controls.Clear()
    $worlds = Get-ChildItem -Directory -Path $worldsDir
    $i = 1
    $worldList = @()
    foreach ($world in $worlds) {
        $worldName = (Get-Content "$($world.FullName)\levelname.txt") -join ""
        $worldImage = Join-Path -Path $world.FullName -ChildPath "world_icon.jpeg"
        $worldFolder = $world.Name

        $panel = New-Object Windows.Forms.Panel
        $panel.Size = New-Object Drawing.Size(200, 400)
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

        $labelName = New-Object Windows.Forms.Label
        $labelName.Text = "$i. $worldName"
        $labelName.Dock = [System.Windows.Forms.DockStyle]::Top
        $labelName.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $labelName.Font = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Bold)
        $panel.Controls.Add($labelName)

        $labelFolder = New-Object Windows.Forms.Label
        $labelFolder.Text = "Folder: $worldFolder"
        $labelFolder.Dock = [System.Windows.Forms.DockStyle]::Top
        $labelFolder.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $labelFolder.Font = [System.Drawing.Font]::new("Arial", 8)
        $panel.Controls.Add($labelFolder)

        if (Test-Path $worldImage) {
            $pictureBox = New-Object Windows.Forms.PictureBox
            $imageBytes = [System.IO.File]::ReadAllBytes($worldImage)
            $imageStream = New-Object System.IO.MemoryStream(,$imageBytes)
            $image = [System.Drawing.Image]::FromStream($imageStream)
            $pictureBox.Image = $image
            $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
            $pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
            $panel.Controls.Add($pictureBox)
        } else {
            $labelNoImage = New-Object Windows.Forms.Label
            $labelNoImage.Text = "No image available"
            $labelNoImage.Dock = [System.Windows.Forms.DockStyle]::Fill
            $labelNoImage.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $panel.Controls.Add($labelNoImage)
        }

        $btnViewFolder = New-Object Windows.Forms.Button
        $btnViewFolder.Text = "View Folder"
        $btnViewFolder.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $btnViewFolder.Tag = $world.FullName
        $btnViewFolder.Add_Click({
            $worldPath = $this.Tag
            if ($worldPath -and $worldPath -ne "") {
                Start-Process explorer.exe -ArgumentList $worldPath
            } else {
                Write-Host "World path is null or empty"
            }
        })
        $panel.Controls.Add($btnViewFolder)

        $deleteButton = New-Object Windows.Forms.Button
        $deleteButton.Text = "Delete"
        $deleteButton.Dock = [System.Windows.Forms.DockStyle]::Bottom
        $deleteButton.Tag = $world.FullName
        $deleteButton.Add_Click({
            $worldPath = $this.Tag
            if ($worldPath -and $worldPath -ne "") {
                Write-Host "Attempting to delete world at path: $worldPath"
                Close-MinecraftIfRunning
                Delete-World -worldPath $worldPath
                Start-Sleep -Milliseconds 500
                Restart-Minecraft
                Refresh-Worlds # Refresh the list
            } else {
                Write-Host "World path is null or empty"
            }
        })
        $panel.Controls.Add($deleteButton)

        $global:flowPanel.Controls.Add($panel)
        $worldList += [PSCustomObject]@{Number = $i; Name = $worldName; ID = $worldFolder}
        $i++
    }
    return $worldList
}

# Function to refresh the list of backup worlds
function Refresh-BackupWorlds {
    $backupDir = Get-BackupDirectory
    if ($backupDir -ne $null) {
        $global:flowPanel.Controls.Clear()
        $worlds = Get-ChildItem -Directory -Path $backupDir
        $i = 1
        foreach ($world in $worlds) {
            $worldName = (Get-Content "$($world.FullName)\levelname.txt") -join ""
            $worldImage = Join-Path -Path $world.FullName -ChildPath "world_icon.jpeg"
            $worldFolder = $world.Name

            $panel = New-Object Windows.Forms.Panel
            $panel.Size = New-Object Drawing.Size(200, 400)
            $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

            $labelName = New-Object Windows.Forms.Label
            $labelName.Text = "$i. $worldName"
            $labelName.Dock = [System.Windows.Forms.DockStyle]::Top
            $labelName.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $labelName.Font = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Bold)
            $panel.Controls.Add($labelName)

            $labelFolder = New-Object Windows.Forms.Label
            $labelFolder.Text = "Folder: $worldFolder"
            $labelFolder.Dock = [System.Windows.Forms.DockStyle]::Top
            $labelFolder.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $labelFolder.Font = [System.Drawing.Font]::new("Arial", 8)
            $panel.Controls.Add($labelFolder)

            if (Test-Path $worldImage) {
                $pictureBox = New-Object Windows.Forms.PictureBox
                $imageBytes = [System.IO.File]::ReadAllBytes($worldImage)
                $imageStream = New-Object System.IO.MemoryStream(,$imageBytes)
                $image = [System.Drawing.Image]::FromStream($imageStream)
                $pictureBox.Image = $image
                $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
                $pictureBox.Dock = [System.Windows.Forms.DockStyle]::Fill
                $panel.Controls.Add($pictureBox)
            } else {
                $labelNoImage = New-Object Windows.Forms.Label
                $labelNoImage.Text = "No image available"
                $labelNoImage.Dock = [System.Windows.Forms.DockStyle]::Fill
                $labelNoImage.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
                $panel.Controls.Add($labelNoImage)
            }

            $global:flowPanel.Controls.Add($panel)
            $i++
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Backup directory not set.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to delete a specific world by path
function Delete-World {
    param (
        [string]$worldPath
    )
    Write-Host "Attempting to delete world at path: $worldPath"
    if (Test-Path $worldPath) {
        try {
            # Retry mechanism for deletion
            $retryCount = 0
            $maxRetries = 5
            $success = $false

            while (-not $success -and $retryCount -lt $maxRetries) {
                try {
                    Get-ChildItem -Path $worldPath -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    Remove-Item -Path $worldPath -Force -Recurse -ErrorAction SilentlyContinue
                    $success = $true
                } catch {
                    $retryCount++
                    Start-Sleep -Seconds 1
                }
            }

            if ($success) {
                Remove-Item -Path $worldPath -Force -Recurse -ErrorAction SilentlyContinue
                Write-Host "Successfully deleted world at path: $worldPath"
            } else {
                Write-Host "Failed to delete world at path: $worldPath after multiple attempts"
            }
        } catch {
            Write-Host "Error deleting world at path: $worldPath. The file may be in use."
        }
    } else {
        Write-Host "World at path: $worldPath does not exist."
    }
}

# Function to close Minecraft process if running
function Close-MinecraftIfRunning {
    $process = Get-Process -Name "Minecraft.Windows" -ErrorAction SilentlyContinue
    if ($process) {
        $process | Stop-Process -Force
        Write-Host "Minecraft.Windows.exe process has been closed."
    } else {
        Write-Host "Minecraft.Windows.exe process is not running."
    }
}

# Function to restart Minecraft process if it was closed
function Restart-Minecraft {
    $process = Get-Process -Name "Minecraft.Windows" -ErrorAction SilentlyContinue
    if (-not $process) {
        Start-Process -FilePath "shell:appsFolder\Microsoft.MinecraftUWP_8wekyb3d8bbwe!App"
        Write-Host "Minecraft.Windows.exe process has been restarted."
    }
}

# Function to backup worlds
function Backup-Worlds {
    $backupDir = Get-BackupDirectory
    if ($backupDir -ne $null) {
        if (!(Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir
        }
        Get-ChildItem -Directory -Path $worldsDir | ForEach-Object {
            $destination = Join-Path -Path $backupDir -ChildPath $_.Name
            Copy-Item -Path $_.FullName -Destination $destination -Recurse -Force
        }
        Write-Host "All worlds have been backed up to $backupDir."
    } else {
        [System.Windows.Forms.MessageBox]::Show("Backup directory not set.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to restore worlds from backup
function Restore-Worlds {
    $backupDir = Get-BackupDirectory
    if ($backupDir -ne $null) {
        if (Test-Path $backupDir) {
            Get-ChildItem -Directory -Path $backupDir | ForEach-Object {
                $destination = Join-Path -Path $worldsDir -ChildPath $_.Name
                Copy-Item -Path $_.FullName -Destination $destination -Recurse -Force
            }
            Write-Host "All worlds have been restored from $backupDir."
        } else {
            Write-Host "Backup directory $backupDir does not exist."
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Backup directory not set.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to delete all worlds except specified ones
function Delete-AllExcept {
    param (
        [int[]]$keepIndexes,
        [array]$worldList
    )
    for ($i = 0; $i -lt $worldList.Count; $i++) {
        if (-not ($keepIndexes -contains $i + 1)) {
            $worldID = $worldList[$i].ID
            $worldPath = Join-Path -Path $worldsDir -ChildPath $worldID
            if (Test-Path $worldPath) {
                try {
                    Remove-Item -Path $worldPath -Recurse -Force
                    Write-Host "World with ID $worldID has been deleted."
                } catch {
                    Write-Host "Error deleting world with ID $worldID. The file may be in use."
                }
            }
        }
    }
}

# Function to toggle the visibility of the PowerShell console
function Toggle-Console {
    param (
        [bool]$showConsole
    )
    if ($showConsole) {
        [User32]::ShowWindow($consolePtr, [User32]::SW_SHOW)
    } else {
        [User32]::ShowWindow($consolePtr, [User32]::SW_HIDE)
    }
}

# Function to create an input dialog
function Input-Dialog {
    param (
        [string]$message,
        [string]$title
    )
    $form = New-Object Windows.Forms.Form
    $form.Text = $title
    $form.Size = New-Object Drawing.Size(300, 150)
    $form.StartPosition = "CenterScreen"

    $label = New-Object Windows.Forms.Label
    $label.Text = $message
    $label.Size = New-Object Drawing.Size(280, 20)
    $label.Location = New-Object Drawing.Point(10, 10)
    $form.Controls.Add($label)

    $textBox = New-Object Windows.Forms.TextBox
    $textBox.Size = New-Object Drawing.Size(260, 20)
    $textBox.Location = New-Object Drawing.Point(10, 40)
    $form.Controls.Add($textBox)

    $buttonOk = New-Object Windows.Forms.Button
    $buttonOk.Text = "OK"
    $buttonOk.Size = New-Object Drawing.Size(75, 23)
    $buttonOk.Location = New-Object Drawing.Point(195, 70)
    $buttonOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $buttonOk
    $form.Controls.Add($buttonOk)

    $form.AcceptButton = $buttonOk
    $form.Controls.Add($buttonOk)

    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text
    } else {
        return $null
    }
}

# Create and show the worlds form by default
function Create-WorldsForm {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Minecraft Worlds"
    $form.Size = New-Object Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"
    $form.Font = [System.Drawing.Font]::new("Arial", 10)

    $btnToggleConsole = New-Object Windows.Forms.Button
    $btnToggleConsole.Text = "Toggle Console Visibility"
    $btnToggleConsole.Size = New-Object Drawing.Size(200, 30)
    $btnToggleConsole.Location = New-Object Drawing.Point(20, 10)
    $btnToggleConsole.Add_Click({
        if ($global:consoleVisible) {
            Toggle-Console -showConsole:$false
            $global:consoleVisible = $false
        } else {
            Toggle-Console -showConsole:$true
            $global:consoleVisible = $true
        }
    })
    $form.Controls.Add($btnToggleConsole)

    $btnRefreshWorlds = New-Object Windows.Forms.Button
    $btnRefreshWorlds.Text = "View/Refresh Worlds"
    $btnRefreshWorlds.Size = New-Object Drawing.Size(200, 30)
    $btnRefreshWorlds.Location = New-Object Drawing.Point(230, 10)
    $btnRefreshWorlds.Add_Click({
        Refresh-Worlds
    })
    $form.Controls.Add($btnRefreshWorlds)

    $btnViewBackupWorlds = New-Object Windows.Forms.Button
    $btnViewBackupWorlds.Text = "View/Refresh Backup Worlds"
    $btnViewBackupWorlds.Size = New-Object Drawing.Size(200, 30)
    $btnViewBackupWorlds.Location = New-Object Drawing.Point(440, 10)
    $btnViewBackupWorlds.Add_Click({
        Refresh-BackupWorlds
    })
    $form.Controls.Add($btnViewBackupWorlds)

    $btnBackupWorlds = New-Object Windows.Forms.Button
    $btnBackupWorlds.Text = "Backup Worlds"
    $btnBackupWorlds.Size = New-Object Drawing.Size(200, 30)
    $btnBackupWorlds.Location = New-Object Drawing.Point(20, 50)
    $btnBackupWorlds.Add_Click({
        Backup-Worlds
    })
    $form.Controls.Add($btnBackupWorlds)

    $btnRestoreWorlds = New-Object Windows.Forms.Button
    $btnRestoreWorlds.Text = "Restore Worlds"
    $btnRestoreWorlds.Size = New-Object Drawing.Size(200, 30)
    $btnRestoreWorlds.Location = New-Object Drawing.Point(230, 50)
    $btnRestoreWorlds.Add_Click({
        Restore-Worlds
    })
    $form.Controls.Add($btnRestoreWorlds)

    $btnDeleteAllExcept = New-Object Windows.Forms.Button
    $btnDeleteAllExcept.Text = "Delete All Except..."
    $btnDeleteAllExcept.Size = New-Object Drawing.Size(200, 30)
    $btnDeleteAllExcept.Location = New-Object Drawing.Point(440, 50)
    $btnDeleteAllExcept.Add_Click({
        $worldList = Refresh-Worlds
        $keep = Input-Dialog -message "Enter the numbers of the worlds you want to keep (comma-separated):" -title "Keep Worlds"
        if ($keep -ne $null) {
            $keepIndexes = $keep -split "," | ForEach-Object { $_.Trim() -as [int] }
            Delete-AllExcept -keepIndexes $keepIndexes -worldList $worldList
            Refresh-Worlds
        }
    })
    $form.Controls.Add($btnDeleteAllExcept)

    $btnSetBackupDir = New-Object Windows.Forms.Button
    $btnSetBackupDir.Text = "Add/Modify Backup World Path"
    $btnSetBackupDir.Size = New-Object Drawing.Size(200, 30)
    $btnSetBackupDir.Location = New-Object Drawing.Point(20, 90)
    $btnSetBackupDir.Add_Click({
        Set-BackupDirectory
    })
    $form.Controls.Add($btnSetBackupDir)

    $global:flowPanel = New-Object Windows.Forms.FlowLayoutPanel
    $global:flowPanel.Location = New-Object Drawing.Point(20, 130)
    $global:flowPanel.Size = New-Object Drawing.Size(750, 430)
    $global:flowPanel.AutoScroll = $true
    $form.Controls.Add($global:flowPanel)

    $global:worldsForm = $form
    $form.ShowDialog() # Use ShowDialog to keep the form open
}

Create-WorldsForm
Refresh-Worlds
