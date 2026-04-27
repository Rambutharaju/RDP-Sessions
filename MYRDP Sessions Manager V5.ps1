<#
================================================================================
Script Name  : MYRDP Sessions Manager
Author       : Ramanjaneyulu Butharaju (@RamB)
Description  :
    This PowerShell script provides a graphical interface (WPF-based) to manage
    and launch Remote Desktop (RDP) sessions efficiently.

    Users can create, edit, and delete RDP session entries, store multiple
    credentials securely, and launch connections with a single click.

Features     :
    - GUI-based RDP session manager
    - Persistent storage using JSON (sessions & accounts)
    - Multi-account support with secure password handling
    - Environment-based color coding (Prod, Dev, Test)
    - Search and filter sessions dynamically
    - One-click RDP launch with credential injection

Storage Path :
    %APPDATA%\MYRDP Sessions\
        - sessions.json
        - accounts.json

Usage        :
    - Run the script in PowerShell
    - Add sessions and accounts via UI
    - Click on a session tile to connect
    - Select account when prompted

Requirements :
    - Windows OS with PowerShell
    - RDP (mstsc.exe) available

================================================================================
#>


cls

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$AppName = "MYRDP Sessions"
$DataDir  = Join-Path $env:APPDATA $AppName
$SessionsPath = Join-Path $DataDir "sessions.json"
$AccountsPath = Join-Path $DataDir "accounts.json"

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj) { return @() }
        @($obj)
    } catch {
        @()
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )
    try {
        $json = $Data | ConvertTo-Json -Depth 10
        Set-Content -Path $Path -Value $json -Encoding UTF8
        $true
    } catch {
        $false
    }
}

function Load-Sessions { Read-JsonFile -Path $SessionsPath }
function Load-Accounts { Read-JsonFile -Path $AccountsPath }

function Save-Sessions {
    param([array]$Sessions)
    Write-JsonFile -Path $SessionsPath -Data $Sessions | Out-Null
}

function Save-Accounts {
    param([array]$Accounts)
    Write-JsonFile -Path $AccountsPath -Data $Accounts | Out-Null
}

function Get-EnvBrush {
    param([string]$Environment)
    $envValue = ""
    if ($null -ne $Environment) { $envValue = [string]$Environment }
    switch ($envValue.Trim().ToLowerInvariant()) {
        "prod" { return "#FFFDECEC" }
        "dev"  { return "#FFEAF7EA" }
        "test" { return "#FFFFF7E6" }
        default { return "#FFF4F4F4" }
    }
}

function Get-EnvAccent {
    param([string]$Environment)
    $envValue = ""
    if ($null -ne $Environment) { $envValue = [string]$Environment }
    switch ($envValue.Trim().ToLowerInvariant()) {
        "prod" { return "#FFE25B5B" }
        "dev"  { return "#FF50B36A" }
        "test" { return "#FFE0A800" }
        default { return "#FF7A7A7A" }
    }
}

function Show-AccountPicker {
    param([array]$Accounts)

    if (-not $Accounts -or $Accounts.Count -eq 0) { return $null }

    $pickerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Select Account" Height="260" Width="420"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="White">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Choose an account" FontSize="18" FontWeight="SemiBold" Foreground="#202020" Margin="0,0,0,10"/>
        <ComboBox Name="AccountList" Grid.Row="1" Height="34" FontSize="14"/>
        <Button Name="OkBtn" Grid.Row="2" Content="Use Selected Account" Height="36" Margin="0,14,0,0" Background="#FF1F6FEB" Foreground="White" BorderBrush="#FF1F6FEB"/>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$pickerXaml)
    $win = [Windows.Markup.XamlReader]::Load($reader)

    $list = $win.FindName("AccountList")
    $okBtn = $win.FindName("OkBtn")

    foreach ($a in $Accounts) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $label = if ([string]::IsNullOrWhiteSpace($a.Domain)) { "$($a.Username)" } else { "$($a.Domain)\$($a.Username)" }
        $item.Content = $label
        $item.Tag = $a
        [void]$list.Items.Add($item)
    }

    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }

    $selected = $null
    $okBtn.Add_Click({
        if ($list.SelectedItem) {
            $script:selectedAccount = $list.SelectedItem.Tag
            $win.DialogResult = $true
        }
    })

    $result = $win.ShowDialog()
    if ($result -eq $true) { return $script:selectedAccount }
    return $null
}

function Start-RdpSession {
    param(
        [string]$Host,
        [int]$Port,
        [object]$Account
    )

    $target = if ($Port -and $Port -ne 3389) { "$Host`:$Port" } else { $Host }

    try {
        if ($Account) {
            $user = if ([string]::IsNullOrWhiteSpace($Account.Domain)) {
                $Account.Username
            } else {
                "$($Account.Domain)\$($Account.Username)"
            }

            $creds = New-Object System.Management.Automation.PSCredential (
                $user,
                ($Account.Password | ConvertTo-SecureString)
            )

            $plain = $creds.GetNetworkCredential().Password
            cmdkey /generic:"TERMSRV/$Host" /user:"$user" /pass:"$plain" | Out-Null
        }

        Start-Process mstsc.exe -ArgumentList "/v:$target"
    } catch {
        [System.Windows.MessageBox]::Show("Failed to start RDP: $($_.Exception.Message)", $AppName, 'OK', 'Error') | Out-Null
    }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="MYRDP Sessions" Height="760" Width="1280"
        WindowStartupLocation="CenterScreen"
        Background="White">
    <Grid Margin="14">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="2.15*"/>
            <ColumnDefinition Width="1.05*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.ColumnSpan="2" Orientation="Vertical" Margin="0,0,0,10">
            <TextBlock Text="MYRDP Sessions" FontSize="28" FontWeight="Bold" Foreground="#111111"/>
            <TextBlock Text="Easy access RDP launcher" FontSize="13" Foreground="#666666" Margin="0,4,0,0"/>
        </StackPanel>

        <DockPanel Grid.Row="1" Grid.ColumnSpan="2" Margin="0,0,0,12">
            <TextBox Name="SearchBox" Height="34" MinWidth="320" FontSize="14"
                     VerticalContentAlignment="Center" Margin="0,0,12,0"
                     ToolTip="Search by name, IP, port, or environment"/>
            <Button Name="RefreshBtn" Content="Refresh" Width="96" Height="34" Margin="0,0,8,0"
                    Background="#FFF0F0F0" Foreground="#111111" BorderBrush="#FFCCCCCC"/>
            <Button Name="DeleteBtn" Content="Delete Selected" Width="120" Height="34" Margin="0,0,8,0"
                    Background="#FFFFE5E5" Foreground="#8A1111" BorderBrush="#FFDDBBBB"/>
        </DockPanel>

        <Border Grid.Row="2" Grid.Column="0" CornerRadius="12" BorderBrush="#FFE0E0E0" BorderThickness="1" Background="#FFFDFDFD" Padding="12" Margin="0,0,12,0">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <WrapPanel Name="TilePanel" />
            </ScrollViewer>
        </Border>

        <Border Grid.Row="2" Grid.Column="1" CornerRadius="12" BorderBrush="#FFE0E0E0" BorderThickness="1" Background="#FFFDFDFD" Padding="14">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel>
                    <TextBlock Text="Add / Edit Server" FontSize="18" FontWeight="SemiBold" Foreground="#111111" Margin="0,0,0,10"/>

                    <TextBlock Text="Session Name" Foreground="#444" Margin="0,4,0,4"/>
                    <TextBox Name="NameBox" Height="32" FontSize="13"/>

                    <TextBlock Text="IP Address" Foreground="#444" Margin="0,10,0,4"/>
                    <TextBox Name="IpBox" Height="32" FontSize="13"/>

                    <TextBlock Text="Port" Foreground="#444" Margin="0,10,0,4"/>
                    <TextBox Name="PortBox" Height="32" Text="3389" FontSize="13"/>

                    <TextBlock Text="Environment" Foreground="#444" Margin="0,10,0,4"/>
                    <ComboBox Name="EnvBox" Height="32" SelectedIndex="0">
                        <ComboBoxItem Content="Prod"/>
                        <ComboBoxItem Content="Dev"/>
                        <ComboBoxItem Content="Test"/>
                        <ComboBoxItem Content="Other"/>
                    </ComboBox>

                    <Separator Margin="0,14,0,14"/>

                    <TextBlock Text="Username" Foreground="#444" Margin="0,4,0,4"/>
                    <TextBox Name="UserBox" Height="32" FontSize="13"/>

                    <TextBlock Text="Password" Foreground="#444" Margin="0,10,0,4"/>
                    <PasswordBox Name="PassBox" Height="32" FontSize="13"/>

                    <TextBlock Text="Domain" Foreground="#444" Margin="0,10,0,4"/>
                    <TextBox Name="DomainBox" Height="32" FontSize="13"/>

                    <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                        <Button Name="SaveBtn" Content="Save Session" Width="110" Height="36" Margin="0,0,8,0"
                                Background="#FF1F6FEB" Foreground="White" BorderBrush="#FF1F6FEB"/>
                        <Button Name="SaveAccBtn" Content="Save Account" Width="110" Height="36"
                                Background="#FFF0F0F0" Foreground="#111111" BorderBrush="#FFCCCCCC"/>
                    </StackPanel>

                    <TextBlock Text="Tip: click any tile to connect. Use Search to filter the wall." 
                               Foreground="#666666" Margin="0,16,0,0" TextWrapping="Wrap"/>
                </StackPanel>
            </ScrollViewer>
        </Border>

        <TextBlock Grid.Row="3" Grid.ColumnSpan="2" Text="@RamB" Foreground="#888888" HorizontalAlignment="Center" Margin="0,12,0,0"/>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$SearchBox = $window.FindName("SearchBox")
$RefreshBtn = $window.FindName("RefreshBtn")
$DeleteBtn = $window.FindName("DeleteBtn")
$TilePanel = $window.FindName("TilePanel")
$NameBox = $window.FindName("NameBox")
$IpBox = $window.FindName("IpBox")
$PortBox = $window.FindName("PortBox")
$EnvBox = $window.FindName("EnvBox")
$UserBox = $window.FindName("UserBox")
$PassBox = $window.FindName("PassBox")
$DomainBox = $window.FindName("DomainBox")
$SaveBtn = $window.FindName("SaveBtn")
$SaveAccBtn = $window.FindName("SaveAccBtn")

$script:Sessions = @(Load-Sessions)
$script:Accounts = @(Load-Accounts)
$script:SelectedSessionName = $null

function Get-SelectedEnvironment {
    if ($EnvBox.SelectedItem -and $EnvBox.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
        return $EnvBox.SelectedItem.Content.ToString()
    }
    return "Other"
}

function Refresh-Tiles {
    $TilePanel.Children.Clear()

    $filter = ""
    if ($null -ne $SearchBox.Text) { $filter = $SearchBox.Text }
    $filter = $filter.Trim().ToLowerInvariant()

    $visible = @($script:Sessions | Where-Object {
        if ([string]::IsNullOrWhiteSpace($filter)) { return $true }
        (($_.Name + " " + $_.IP + " " + $_.Port + " " + $_.Environment) -as [string]).ToLowerInvariant().Contains($filter)
    })

    foreach ($s in $visible) {
        $outer = New-Object System.Windows.Controls.Border
        $outer.Width = 230
        $outer.Height = 150
        $outer.Margin = "8"
        $outer.CornerRadius = "14"
        $outer.BorderThickness = "1"
        $outer.BorderBrush = "#FFD7D7D7"
        $outer.Background = (Get-EnvBrush $s.Environment)

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = "12"

        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))

        $icon = New-Object System.Windows.Controls.TextBlock
        $icon.Text = "🖥"
        $icon.FontSize = 26
        $icon.Margin = "0,0,0,8"
        $icon.Foreground = (Get-EnvAccent $s.Environment)
        [void]$grid.Children.Add($icon)

        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = $s.Name
        $name.FontSize = 18
        $name.FontWeight = "Bold"
        $name.Foreground = "#111111"
        $name.Margin = "0,34,0,0"
        [System.Windows.Controls.Grid]::SetRow($name, 1)
        [void]$grid.Children.Add($name)

        $addr = New-Object System.Windows.Controls.TextBlock
        $addr.Text = "$($s.IP):$($s.Port)"
        $addr.FontSize = 13
        $addr.Foreground = "#333333"
        $addr.Margin = "0,0,0,0"
        [System.Windows.Controls.Grid]::SetRow($addr, 2)
        [void]$grid.Children.Add($addr)

        $env = New-Object System.Windows.Controls.TextBlock
        $env.Text = $s.Environment
        $env.FontSize = 12
        $env.FontWeight = "SemiBold"
        $env.HorizontalAlignment = "Right"
        $env.VerticalAlignment = "Bottom"
        $env.Foreground = (Get-EnvAccent $s.Environment)
        [System.Windows.Controls.Grid]::SetRow($env, 3)
        [void]$grid.Children.Add($env)

        $btn = New-Object System.Windows.Controls.Button
        $btn.Background = "Transparent"
        $btn.BorderThickness = "0"
        $btn.Content = $grid
        $btn.Tag = $s

        $btn.Add_Click({
            param($sender, $e)
            $session = $sender.Tag
            $selectedAcc = Show-AccountPicker -Accounts $script:Accounts
            Start-RdpSession -Host $session.IP -Port ([int]$session.Port) -Account $selectedAcc
        })

        $outer.Child = $btn
        [void]$TilePanel.Children.Add($outer)
    }
}

$SearchBox.Add_TextChanged({ Refresh-Tiles })
$RefreshBtn.Add_Click({
    $script:Sessions = @(Load-Sessions)
    $script:Accounts = @(Load-Accounts)
    Refresh-Tiles
})

$DeleteBtn.Add_Click({
    if ([string]::IsNullOrWhiteSpace($script:SelectedSessionName)) {
        [System.Windows.MessageBox]::Show("Click a tile first to select a session to delete.", $AppName, 'OK', 'Information') | Out-Null
        return
    }

    $choice = [System.Windows.MessageBox]::Show("Delete '$script:SelectedSessionName'?", $AppName, 'YesNo', 'Warning')
    if ($choice -eq 'Yes') {
        $script:Sessions = @($script:Sessions | Where-Object { $_.Name -ne $script:SelectedSessionName })
        Save-Sessions -Sessions $script:Sessions
        $script:SelectedSessionName = $null
        Refresh-Tiles
    }
})

$SaveBtn.Add_Click({
    $name = $NameBox.Text.Trim()
    $ip = $IpBox.Text.Trim()
    $portText = $PortBox.Text.Trim()
    $env = Get-SelectedEnvironment

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($ip)) {
        [System.Windows.MessageBox]::Show("Session Name and IP Address are required.", $AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $port = 3389
    if (-not [string]::IsNullOrWhiteSpace($portText)) {
        [int]::TryParse($portText, [ref]$port) | Out-Null
    }

    $existing = @($script:Sessions | Where-Object { $_.Name -eq $name })
    if ($existing.Count -gt 0) {
        $script:Sessions = @($script:Sessions | Where-Object { $_.Name -ne $name })
    }

    $script:Sessions += [pscustomobject]@{
        Name = $name
        IP = $ip
        Port = $port
        Environment = $env
    }

    Save-Sessions -Sessions $script:Sessions
    $script:SelectedSessionName = $name
    Refresh-Tiles

    [System.Windows.MessageBox]::Show("Session saved: $name", $AppName, 'OK', 'Information') | Out-Null
})

$SaveAccBtn.Add_Click({
    $username = $UserBox.Text.Trim()
    $password = $PassBox.Password
    $domain = $DomainBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        [System.Windows.MessageBox]::Show("Username and Password are required.", $AppName, 'OK', 'Warning') | Out-Null
        return
    }

    $label = if ([string]::IsNullOrWhiteSpace($domain)) { $username } else { "$domain\$username" }

    $existing = @($script:Accounts | Where-Object { $_.Username -eq $username -and $_.Domain -eq $domain })
    if ($existing.Count -gt 0) {
        $script:Accounts = @($script:Accounts | Where-Object { -not ($_.Username -eq $username -and $_.Domain -eq $domain) })
    }

    $script:Accounts += [pscustomobject]@{
        Username = $username
        Password = ($password | ConvertFrom-SecureString)
        Domain   = $domain
        Label    = $label
    }

    Save-Accounts -Accounts $script:Accounts
    $PassBox.Clear()

    [System.Windows.MessageBox]::Show("Account saved: $label", $AppName, 'OK', 'Information') | Out-Null
})

$window.Add_ContentRendered({
    Refresh-Tiles
})

Refresh-Tiles
$window.ShowDialog() | Out-Null
