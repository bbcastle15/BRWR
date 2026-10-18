param(
    [ValidateSet("Add","Remove","Status")]
    [string]$Action = "Add",

    [string]$RootDescription = "http://192.168.1.254:5000/rootDesc.xml",

    [string]$InternalClient = ""
)

$ErrorActionPreference = "Stop"

function Resolve-AbsoluteUrl {
    param(
        [string]$BaseUrl,
        [string]$RelativeOrAbsolute
    )
    $base = [Uri]$BaseUrl
    return ([Uri]::new($base, $RelativeOrAbsolute)).AbsoluteUri
}

function Read-HttpErrorBody {
    param($Exception)
    try {
        if ($Exception.Response -and $Exception.Response.GetResponseStream()) {
            $reader = New-Object System.IO.StreamReader($Exception.Response.GetResponseStream())
            try { return $reader.ReadToEnd() }
            finally { $reader.Dispose() }
        }
    } catch {}
    return ""
}

function Invoke-UpnpSoap {
    param(
        [string]$ControlUrl,
        [string]$ServiceType,
        [string]$ActionName,
        [string]$ArgumentsXml = ""
    )

    $body = @"
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:$ActionName xmlns:u="$ServiceType">$ArgumentsXml</u:$ActionName>
  </s:Body>
</s:Envelope>
"@

    $headers = @{
        SOAPACTION = '"' + $ServiceType + '#' + $ActionName + '"'
    }

    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri $ControlUrl `
            -Method POST `
            -ContentType 'text/xml; charset="utf-8"' `
            -Headers $headers `
            -Body $body

        return @{
            Ok = $true
            StatusCode = [int]$response.StatusCode
            Body = [string]$response.Content
        }
    }
    catch {
        $fault = Read-HttpErrorBody $_.Exception
        return @{
            Ok = $false
            StatusCode = 0
            Body = $fault
            Error = $_.Exception.Message
        }
    }
}

function XmlEscape([string]$Text) {
    return [System.Security.SecurityElement]::Escape($Text)
}

Write-Host "BRWR FASTGate direct UPnP test"
Write-Host "Root description: $RootDescription"
Write-Host ""

# 1) Read router description and discover WANIPConnection dynamically.
[xml]$root = (Invoke-WebRequest -UseBasicParsing -Uri $RootDescription).Content

$serviceNode = $root.SelectNodes("//*[local-name()='service']") |
    Where-Object {
        $_.serviceType -match 'WAN(IP|PPP)Connection'
    } |
    Select-Object -First 1

if (-not $serviceNode) {
    throw "Nessun servizio WANIPConnection/WANPPPConnection trovato nel rootDesc.xml."
}

$serviceType = [string]$serviceNode.serviceType
$controlUrl = Resolve-AbsoluteUrl $RootDescription ([string]$serviceNode.controlURL)
$scpdUrl = Resolve-AbsoluteUrl $RootDescription ([string]$serviceNode.SCPDURL)

Write-Host "ServiceType : $serviceType"
Write-Host "ControlURL  : $controlUrl"
Write-Host "SCPDURL     : $scpdUrl"

# 2) Check supported actions.
[xml]$scpd = (Invoke-WebRequest -UseBasicParsing -Uri $scpdUrl).Content
$actions = @(
    $scpd.SelectNodes("//*[local-name()='action']/*[local-name()='name']") |
        ForEach-Object { $_.InnerText }
)

foreach ($required in @("GetExternalIPAddress","AddPortMapping","DeletePortMapping")) {
    if ($actions -notcontains $required) {
        throw "Il FASTGate non pubblicizza l'azione UPnP '$required'."
    }
}
Write-Host "Azioni richieste presenti: OK"

# 3) Get WAN address.
$wan = Invoke-UpnpSoap $controlUrl $serviceType "GetExternalIPAddress"
if (-not $wan.Ok) {
    Write-Host ""
    Write-Host "GetExternalIPAddress FALLITO"
    Write-Host $wan.Error
    if ($wan.Body) { Write-Host $wan.Body }
    exit 2
}

[xml]$wanXml = $wan.Body
$wanNode = $wanXml.SelectSingleNode("//*[local-name()='NewExternalIPAddress']")
$externalIp = if ($wanNode) { $wanNode.InnerText } else { "" }
Write-Host "External IP : $externalIp"

# 4) Choose internal client automatically if omitted.
if (-not $InternalClient) {
    $InternalClient = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -like "192.168.1.*" -and
            $_.IPAddress -ne "192.168.1.254" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.AddressState -eq "Preferred"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
}

if (-not $InternalClient) {
    throw "Non riesco a determinare l'IPv4 interno. Rilancia con -InternalClient 192.168.1.231"
}

Write-Host "Internal IP : $InternalClient"
Write-Host ""

$ports = @(
    @{ Port = 8080; Description = "BRWR HTTPS" },
    @{ Port = 27847; Description = "BRWR WSS" }
)

if ($Action -eq "Status") {
    Write-Host "Discovery e GetExternalIPAddress completati."
    Write-Host "Questa modalità non modifica il router."
    exit 0
}

if ($Action -eq "Remove") {
    foreach ($p in $ports) {
        $port = [int]$p.Port
        $args = "<NewRemoteHost></NewRemoteHost><NewExternalPort>$port</NewExternalPort><NewProtocol>TCP</NewProtocol>"
        $result = Invoke-UpnpSoap $controlUrl $serviceType "DeletePortMapping" $args

        if ($result.Ok) {
            Write-Host "Rimossa TCP $port"
        } else {
            Write-Host "Rimozione TCP $port fallita"
            Write-Host $result.Error
            if ($result.Body) { Write-Host $result.Body }
        }
    }
    exit 0
}

# Action = Add
$allOk = $true

foreach ($p in $ports) {
    $port = [int]$p.Port
    $desc = XmlEscape ([string]$p.Description)
    $client = XmlEscape $InternalClient

    $args = @"
<NewRemoteHost></NewRemoteHost>
<NewExternalPort>$port</NewExternalPort>
<NewProtocol>TCP</NewProtocol>
<NewInternalPort>$port</NewInternalPort>
<NewInternalClient>$client</NewInternalClient>
<NewEnabled>1</NewEnabled>
<NewPortMappingDescription>$desc</NewPortMappingDescription>
<NewLeaseDuration>0</NewLeaseDuration>
"@

    $result = Invoke-UpnpSoap $controlUrl $serviceType "AddPortMapping" $args

    if ($result.Ok) {
        Write-Host "OPEN TCP $port -> $InternalClient`:$port"
    }
    else {
        $allOk = $false
        Write-Host ""
        Write-Host "AddPortMapping TCP $port FALLITO"
        Write-Host $result.Error
        if ($result.Body) { Write-Host $result.Body }
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "SUCCESSO: entrambe le porte BRWR sono state richieste al FASTGate."
    Write-Host "IP pubblico riportato dal router: $externalIp"
    Write-Host "Ora prova dal laptop su un'altra rete:"
    Write-Host "  Test-NetConnection $externalIp -Port 8080"
    Write-Host "  Test-NetConnection $externalIp -Port 27847"
    exit 0
} else {
    Write-Host "Uno o più mapping sono falliti. Incolla qui l'output completo del SOAP fault."
    exit 3
}
