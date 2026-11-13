param(
    [Parameter(Mandatory = $true)][string]$Log,
    [string]$Title = "GPTKit-Echo-Window"
)
# Test fixture: a tiny window that writes every input it receives to a log file.
# Used by tests/Test-Backend.ps1 to verify the Windows backend end to end.
# ASCII-only file.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace GPTFixture -Name Imm -MemberDefinition '[DllImport("imm32.dll")] public static extern IntPtr ImmAssociateContext(IntPtr hWnd, IntPtr hIMC);'
$script:logPath = $Log
function Note([string]$line) { Add-Content -LiteralPath $script:logPath -Value $line -Encoding ASCII }

$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.ClientSize = New-Object System.Drawing.Size(480, 320)
$form.StartPosition = "Manual"
$form.Location = New-Object System.Drawing.Point(80, 80)
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 60, 120)

$box = New-Object System.Windows.Forms.TextBox
$box.Location = New-Object System.Drawing.Point(20, 20)
$box.Size = New-Object System.Drawing.Size(300, 24)
$form.Controls.Add($box)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Press"
$btn.BackColor = [System.Drawing.Color]::FromArgb(220, 180, 40)
$btn.Location = New-Object System.Drawing.Point(20, 100)
$btn.Size = New-Object System.Drawing.Size(160, 60)
$form.Controls.Add($btn)

$form.Add_KeyDown({ param($s, $e) Note ("KEYDOWN " + [int]$e.KeyCode) })
$box.Add_TextChanged({ Note ("TEXT " + $box.Text) })
$btn.Add_Click({ Note "CLICK button" })
$form.Add_MouseDown({ param($s, $e) Note ("MOUSEDOWN {0},{1} {2}" -f $e.X, $e.Y, $e.Button) })
$form.Add_MouseWheel({ param($s, $e) Note ("WHEEL " + $e.Delta) })
$form.Add_Shown({
    # detach the IME so an active input method (e.g. Chinese) cannot swallow real keystrokes as VK_PROCESSKEY (229)
    foreach ($h in @($form.Handle, $box.Handle, $btn.Handle)) { [GPTFixture.Imm]::ImmAssociateContext($h, [IntPtr]::Zero) | Out-Null }
    $box.Focus() | Out-Null
    Note "READY"
})
[System.Windows.Forms.Application]::Run($form)
