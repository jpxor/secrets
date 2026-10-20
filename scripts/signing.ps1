function Save-SigningPassword([string]$Password, [string]$Path) {
  $secure = ConvertTo-SecureString $Password -AsPlainText -Force
  ConvertFrom-SecureString $secure | Set-Content -LiteralPath $Path
}
function Read-SigningPassword([string]$Path) {
  # Set-Content terminates the encrypted text with a newline; DPAPI parsing requires trimming it.
  $secure = ConvertTo-SecureString (Get-Content -LiteralPath $Path -Raw).Trim()
  return ([System.Management.Automation.PSCredential]::new('signing', $secure)).GetNetworkCredential().Password
}
